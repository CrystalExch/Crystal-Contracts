// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "../interfaces/IERC20.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {ICrystal} from "../interfaces/ICrystal.sol";
import {CrystalMath as CM} from "../libraries/CrystalMath.sol";
import {CrystalStorage as CS} from "../libraries/CrystalStorage.sol";
import {CrystalToken} from "./CrystalToken.sol";
import {CrystalMarket} from "./CrystalMarket.sol";

/**
 * @title Crystal
 * @author Crystal Labs
 *
 * @notice
 * The core exchange contract for the Crystal spot protocol.
 *
 * This contract is responsible for:
 * - Storing pending orders and their underlying assets.
 * - Processing order placement, cancellation, and matching.
 * - Routing various order types and swap paths.
 * - Adding and removing AMM liquidity.
 * - Providing endpoints to permissionlessly create and modify markets.
 *
 * @dev
 * - All exchange read and write methods on individual markets are only accessible through this contract.
 * - When querying data, subscribe to events from this contract and optionally filter by market.
 * - Token balances are all stored in this contract to optimize for gas on cross-market trades.
 * - All actions are protected via a transient storage reentrancy guard.
 * - To maintain a consistent storage layout with CrystalMarket which inherits ERC20, the first 7 storage slots are unused.
 */
contract Crystal is ICrystal {
    /// @notice Unused storage slot.
    uint256 internal slot0;

    /// @notice Unused storage slot.
    uint256 internal slot1;

    /// @notice Unused storage slot.
    uint256 internal slot2;

    /// @notice Unused storage slot.
    uint256 internal slot3;

    /// @notice Unused storage slot.
    uint256 internal slot4;

    /// @notice Unused storage slot.
    uint256 internal slot5;

    /// @notice Unused storage slot.
    uint256 internal slot6;

    /// @notice Address receiving trading fees.
    address public feeRecipient;

    /// @notice Percentage of fees that go to referrals.
    uint8 public feeCommission;

    /**
     * @notice Mapping from user id to address.
     *
     * @dev User id zero is invalid.
     */
    mapping(uint256 => address) public userIdToAddress;

    /// @notice Links each address to their user ID.
    mapping(address => uint256) public addressToUserId;

    /// @notice Stores all market configurations, indexed by market address.
    mapping(address => ICrystal.Market) internal _getMarket;

    /**
     * @notice The protocols's internal token balances.
     *
     * @dev Keyed by userId and token address.
     */
    mapping(uint256 => mapping(address => uint256)) internal tokenBalances;

    /**
     * @notice Claimable fee balances per token and user.
     *
     * @dev token => user => amount.
     */
    mapping(address => mapping(address => uint256)) public claimableRewards;

    /// @notice The governance address that can set certain parameters.
    address public gov;

    /**
     * @notice Latest registered user id.
     *
     * @dev Zero is reserved for the router which can hold temporary balances during swaps.
     */
    uint256 public latestUserId;

    /**
     * @notice Duration before expired fee claims can be processed.
     */
    uint256 public feeClaimDuration;

    /**
     * @notice Pending expired fee claims by user.
     */
    mapping(address => ICrystal.PendingExpiredFeeClaim) public pendingExpiredFeeClaims;

    /**
     * @notice Pending closed market ids by user.
     *
     * @dev Encoded as a bitmap.
     */
    mapping(address => uint256) public pendingClosedMarkets;

    /**
     * @notice Whether an address is authorized to deploy canonical markets.
     */
    mapping(address => bool) public isCanonicalDeployer;

    /**
     * @notice Approved forwarders per user.
     *
     * @dev user => forwarder => approved.
     */
    mapping(address => mapping(address => bool)) public approvedForwarder;

    /// @notice Looks up a market's address from its ID.
    mapping(uint256 => address) public marketIdToMarket;

    /**
     * @notice Market lookup by token pair.
     *
     * @dev Can be overridden for routing purposes.
     */
    mapping(address => mapping(address => address)) public getMarketByTokens;

    /// @notice Array of all markets that have been deployed.
    address[] public allMarkets;

    /**
     * @notice Parameters scratch space used during deployment.
     */
    ICrystal.Parameters public parameters;

    /**
     * @notice Global launchpad parameters.
     */
    ICrystal.LaunchpadParams public launchpadParams;

    /**
     * @notice Mapping from launchpad token to market data.
     */
    mapping(address => ICrystal.LaunchpadMarket) public launchpadTokenToMarket;

    /// @notice Array of all launchpad tokens that have been created.
    address[] public allTokens;

    /// @notice Wrapped native token address.
    address public immutable weth;

    /// @notice Placeholder native token address.
    address public constant eth = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice Placeholder market address.
    address internal constant placeholder = 0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC;

    /// @notice Maximum protocol taker fee (10%).
    uint256 internal constant MAX_FEE = 90000;

    /// @notice Initial launchpad token reserve.
    uint256 internal constant INITIAL_TOKEN_SUPPLY = 1000000000000000000000000000;

    /// @notice Graduated launchpad token reserve threshold.
    uint256 internal constant GRADUATED_TOKEN_SUPPLY = 200000000000000000000000000;
    
    /// @notice Graduated launchpad market default max price.
    uint256 internal constant GRADUATED_MAX_PRICE = 1000000000000000;

    uint256 internal constant MASK_OUT_113_154 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFC0000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 internal constant MASK_OUT_0_128 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000000000000000000000000000;
    uint256 internal constant MASK_KEEP_255_256 = 0x8000000000000000000000000000000000000000000000000000000000000000;
    uint256 internal constant MASK_KEEP_80_160 = 0x000000000000000000000000FFFFFFFFFFFFFFFFFFFF00000000000000000000;
    uint256 internal constant MASK_KEEP_0_20 = 0xFFFFF;
    uint256 internal constant MASK_KEEP_0_41 = 0x1FFFFFFFFFF;
    uint256 internal constant MASK_KEEP_0_48 = 0xFFFFFFFFFFFF;
    uint256 internal constant MASK_KEEP_0_51 = 0x7FFFFFFFFFFFF;
    uint256 internal constant MASK_KEEP_0_80 = 0xFFFFFFFFFFFFFFFFFFFF;
    uint256 internal constant MASK_KEEP_0_112 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 internal constant MASK_KEEP_0_128 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

    /// @notice Prevents reentrancy using transient storage.
    modifier nonReentrant() {
        assembly {
            if tload(0x0) {
                revert(0, 0)
            }
            tstore(0x0, 1)
        }
        _;
        assembly {
            tstore(0x0, 0)
        }
    }

    /// @notice Reverts if called by any address other than gov.
    modifier onlyOwner() {
        if (msg.sender != gov) {
            revert ICrystal.Unauthorized(msg.sender);
        }
        _;
    }

    /**
     * @notice Sets up the main Crystal contract with all its configuration
     *
     * @param _weth Address of the wrapped ETH token
     * @param _gov Who has governance/admin control
     * @param _feeRecipient Where protocol fees go
     * @param _feeCommission What percentage referrers get
     * @param _feeClaimDuration How long before expired fee claims can be processed
     * @param _launchpadParams All the launchpad settings
     */
    constructor(address _weth, address _gov, address _feeRecipient, uint8 _feeCommission, uint256 _feeClaimDuration, ICrystal.LaunchpadParams memory _launchpadParams) {
        weth = _weth;
        gov = _gov;
        feeRecipient = _feeRecipient;
        feeCommission = _feeCommission;
        feeClaimDuration = _feeClaimDuration;
        isCanonicalDeployer[_gov] = true;
        uint256 minSizeZeroes;
        uint256 minSize = _launchpadParams.graduatedMinSize;
        while (minSize != 0 && minSize % 10 == 0) {
            minSize /= 10;
            ++minSizeZeroes;
        }
        require(_feeCommission <= 50 && minSize > 0 && minSize < MASK_KEEP_0_20 && minSizeZeroes < MASK_KEEP_0_20 && _launchpadParams.launchpadInitialNativeSupply > 1e18 && MAX_FEE <= _launchpadParams.launchpadFee && _launchpadParams.launchpadFee <= 100000 && MAX_FEE <= _launchpadParams.graduatedTakerFee);
        require(_launchpadParams.graduatedTakerFee <= 100000 && MAX_FEE <= _launchpadParams.graduatedMakerRebate && _launchpadParams.graduatedMakerRebate <= 100000 && _launchpadParams.graduatedCreatorFeeSplit <= 50 && _launchpadParams.launchpadCreatorFeeSplit <= 50);
        launchpadParams = _launchpadParams;
    }

    /**
     * @notice Accepts native token transfers for ETH deposits and priority bid
     */
    receive() external payable {}

    /**
     * @notice Processes batch actions with support for multiple markets supplied via calldata.
     *
     * @dev For each market, the first 32-byte word is encoded as: (balanceMode << 252 | actionCount << 160 | market) with subsequent words being actions.
     * @dev An optional transfer to block.coinbase can be attached to each batch as a conditional priority bid.
     */
    fallback() external payable nonReentrant {
        assembly {
            mstore(0x40, 0xc0)
            mstore(0x00, caller())
            mstore(0x20, addressToUserId.slot)
            let userId := sload(keccak256(0x00, 0x40))
            if iszero(userId) {
                revert(0, 0)
            }
            let totalBid := 0
            for {
                let offset := 0
            } lt(offset, calldatasize()) {

            } {
                let chunk := calldataload(offset)
                let market := and(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, chunk)
                let len := shl(5, and(0xFFF, shr(160, chunk)))
                let bid := and(MASK_KEEP_0_80, shr(172, chunk))
                mstore(0x00, market)
                mstore(0x20, _getMarket.slot)
                if iszero(and(sload(keccak256(0x00, 0x40)), MASK_KEEP_80_160)) {
                    revert(0, 0)
                }
                mstore(0x80, or(shl(44, shr(252, chunk)), userId))
                calldatacopy(0xa0, add(offset, 0x20), len)
                let result := delegatecall(gas(), market, 0x80, add(len, 0x20), 0, 0)
                if iszero(result) {
                    returndatacopy(0, 0, returndatasize())
                    revert(0, returndatasize())
                }
                totalBid := add(totalBid, bid)
                offset := add(offset, add(len, 0x20))
            }
            if totalBid {
                pop(call(gas(), coinbase(), totalBid, 0, 0, 0, 0))
            }
            if and(callvalue(), selfbalance()) {
                pop(call(gas(), caller(), selfbalance(), 0, 0, 0, 0))
            }
        }
    }

    /**
     * @notice Checks that a market exists and locks it to prevent reentrancy attacks
     *
     * @param market The market address to check and lock
     */
    function _verifyMarket(address market) internal view {
        assembly {
            mstore(0x00, market)
            mstore(0x20, _getMarket.slot)
            if iszero(and(sload(keccak256(0x00, 0x40)), MASK_KEEP_80_160)) {
                revert(0, 0)
            }
        }
    }

    /**
     * @notice Figures out who the actual user is and makes sure they're authorized (defaults to msg.sender)
     *
     * @param user The user address provided (can be zero to use msg.sender)
     *
     * @return The verified user address after checking forwarder permissions
     */
    function _verifyUser(address user) internal view returns (address) {
        if (user == address(0)) {
            user = msg.sender;
        } else if (user != msg.sender && !approvedForwarder[user][msg.sender]) {
            revert ICrystal.Unauthorized(msg.sender);
        }
        return user;
    }

    /**
     * @notice Calls into a market contract with user data attached, using delegatecall with a reentrancy lock
     *
     * @param market Which market to call
     * @param selector Which function to call on the market
     * @param size How much calldata we have (not counting the selector and user address)
     * @param user The user address to attach to the call (can also pass options in the case of add/remove liquidity)
     */
    function _delegateToMarket(address market, bytes4 selector, uint256 size, address user) internal {
        _verifyMarket(market);
        assembly {
            mstore(0x80, selector)
            calldatacopy(0x84, 36, size)
            mstore(add(size, 0x84), user)
            let result := delegatecall(gas(), market, 0x80, add(4, add(size, mul(iszero(iszero(user)), 32))), 0, 0)
            returndatacopy(0x80, 0, returndatasize())
            switch result
            case 0 {
                revert(0x80, returndatasize())
            }
        }
    }

    /**
     * @notice Registers a new user and gives them a user ID
     *
     * @dev Only default accounts are supported.
     *
     * @param acctType Type of account (0 = standard, 1 = margin - but margin isn't supported yet)
     * @param user The address to register
     *
     * @return _latestUserId The user ID that was assigned
     */
    function _registerUser(uint256 acctType, address user) internal returns (uint256 _latestUserId) {
        if (acctType == 0) {
            _latestUserId = latestUserId;
            require(addressToUserId[user] == 0 && _latestUserId < MASK_KEEP_0_41);
            _latestUserId++;
            addressToUserId[user] = _latestUserId;
            userIdToAddress[_latestUserId] = user;
            latestUserId = _latestUserId;
            emit ICrystal.UserRegistered(false, user, _latestUserId);
        } else {
            revert ICrystal.AccountLimitReached();
        }
    }

    /**
     * @notice Buy logic lives inside internal function so it can be called in createToken without interfering with reentry guard.
     *
     * @param isExactInput True if `amountIn` is exact, false if `amountOut` is exact.
     * @param token Token to buy.
     * @param amountIn Input amount when exact input.
     * @param amountOut Desired output when exact output.
     *
     * @return inputAmount Actual input used.
     * @return outputAmount Actual output received.
     * @return isLaunchpadClosed Whether the launchpad has graduated.
     */
    function _buy(bool isExactInput, address token, uint256 amountIn, uint256 amountOut) internal returns (uint256, uint256, bool) {
        if (isExactInput) {
            require(msg.value == amountIn);
        }
        ICrystal.LaunchpadMarket storage launchpadMarket = launchpadTokenToMarket[token];
        uint256 inputAmount;
        uint256 outputAmount;
        if (launchpadMarket.virtualTokenReserve != 0) {
            if (isExactInput) {
                inputAmount = amountIn;
                if (launchpadMarket.virtualNativeReserve + ((inputAmount * launchpadParams.launchpadFee) / 100000) > (launchpadMarket.k / GRADUATED_TOKEN_SUPPLY)) {
                    inputAmount = ((((launchpadMarket.k + GRADUATED_TOKEN_SUPPLY - 1) / GRADUATED_TOKEN_SUPPLY) - launchpadMarket.virtualNativeReserve) * 100000 + launchpadParams.launchpadFee - 1) / launchpadParams.launchpadFee;
                }
                IWETH(weth).deposit{value: inputAmount}();
                uint256 amountAfterFee = (inputAmount * launchpadParams.launchpadFee) / 100000;
                uint256 collectedFee = inputAmount - amountAfterFee;
                uint256 creatorFee = (collectedFee * launchpadParams.launchpadCreatorFeeSplit) / 100;
                claimableRewards[weth][launchpadMarket.creator] += creatorFee;
                claimableRewards[weth][gov] += (collectedFee - creatorFee);
                launchpadMarket.virtualNativeReserve += uint112(amountAfterFee);
                uint256 oldTokenReserve = launchpadMarket.virtualTokenReserve;
                launchpadMarket.virtualTokenReserve = uint112((launchpadMarket.k + launchpadMarket.virtualNativeReserve - 1) / launchpadMarket.virtualNativeReserve);
                outputAmount = oldTokenReserve - launchpadMarket.virtualTokenReserve;
                IERC20(token).transfer(msg.sender, outputAmount);
            } else {
                uint256 newToken = launchpadMarket.virtualTokenReserve - amountOut;
                uint256 newNative = (uint256(launchpadMarket.k) + newToken - 1) / newToken;
                uint256 preFeeIn = newNative - launchpadMarket.virtualNativeReserve;
                if (launchpadMarket.virtualNativeReserve + preFeeIn > (launchpadMarket.k / GRADUATED_TOKEN_SUPPLY)) {
                    inputAmount = ((((launchpadMarket.k + GRADUATED_TOKEN_SUPPLY - 1) / GRADUATED_TOKEN_SUPPLY) - launchpadMarket.virtualNativeReserve) * 100000 + launchpadParams.launchpadFee - 1) / launchpadParams.launchpadFee;
                    IWETH(weth).deposit{value: inputAmount}();
                    uint256 collectedFee = inputAmount - ((inputAmount * launchpadParams.launchpadFee) / 100000);
                    uint256 creatorFee = (collectedFee * launchpadParams.launchpadCreatorFeeSplit) / 100;
                    claimableRewards[weth][launchpadMarket.creator] += creatorFee;
                    claimableRewards[weth][gov] += (collectedFee - creatorFee);
                    launchpadMarket.virtualNativeReserve = uint112(launchpadMarket.k / GRADUATED_TOKEN_SUPPLY);
                    uint256 oldTokenReserve = launchpadMarket.virtualTokenReserve;
                    launchpadMarket.virtualTokenReserve = uint112((launchpadMarket.k + launchpadMarket.virtualNativeReserve - 1) / launchpadMarket.virtualNativeReserve);
                    outputAmount = oldTokenReserve - launchpadMarket.virtualTokenReserve;
                    IERC20(token).transfer(msg.sender, outputAmount);
                } else {
                    inputAmount = (preFeeIn * 100000 + launchpadParams.launchpadFee - 1) / launchpadParams.launchpadFee;
                    uint256 collectedFee = inputAmount - preFeeIn;
                    uint256 creatorFee = (collectedFee * launchpadParams.launchpadCreatorFeeSplit) / 100;
                    claimableRewards[weth][launchpadMarket.creator] += creatorFee;
                    claimableRewards[weth][gov] += (collectedFee - creatorFee);
                    launchpadMarket.virtualNativeReserve = uint112(newNative);
                    launchpadMarket.virtualTokenReserve = uint112(newToken);
                    IWETH(weth).deposit{value: inputAmount}();
                    outputAmount = amountOut;
                    IERC20(token).transfer(msg.sender, amountOut);
                    (bool success, ) = msg.sender.call{value: msg.value - inputAmount}("");
                    if (!success) {
                        revert ICrystal.TransferFailed(msg.sender);
                    }
                }
            }
            if (inputAmount != 0 && outputAmount != 0) {
                emit ICrystal.LaunchpadTrade(token, msg.sender, true, inputAmount, outputAmount, launchpadMarket.virtualNativeReserve, launchpadMarket.virtualTokenReserve);
            }
            if (launchpadMarket.virtualNativeReserve >= ((launchpadMarket.k / GRADUATED_TOKEN_SUPPLY))) { // Graduate token from bonding curve to orderbook
                address market = launchpadMarket.market;
                delete launchpadTokenToMarket[token];
                getMarketByTokens[weth][token] = market;
                getMarketByTokens[token][weth] = market;
                ICrystal.Market storage m = _getMarket[market];
                {
                    uint256 minSizeZeroes;
                    uint256 _minSize = launchpadParams.graduatedMinSize;
                    while (_minSize != 0 && _minSize % 10 == 0) {
                        _minSize /= 10;
                        ++minSizeZeroes;
                    }
                    (m.lowestAsk, m.minSize, m.takerFee, m.makerRebate, m.createTimestamp) = (uint80(GRADUATED_MAX_PRICE), uint40((_minSize << 20) | minSizeZeroes), uint24(launchpadParams.graduatedTakerFee), uint24(launchpadParams.graduatedMakerRebate), uint88(block.timestamp));
                }
                emit ICrystal.Migrated(token);
                ICrystal.TokenMetadata memory quoteMeta = ICrystal.TokenMetadata(weth, IERC20(weth).decimals(), IERC20(weth).symbol(), IERC20(weth).name());
                ICrystal.TokenMetadata memory baseMeta = ICrystal.TokenMetadata(token, IERC20(token).decimals(), IERC20(token).symbol(), IERC20(token).name());
                ICrystal.MarketDetails memory details = ICrystal.MarketDetails(m.marketId, 3, 9, 1, GRADUATED_MAX_PRICE, launchpadParams.graduatedMinSize, uint24(launchpadParams.graduatedTakerFee), uint24(launchpadParams.graduatedMakerRebate));
                emit ICrystal.MarketCreated(true, weth, token, market, quoteMeta, baseMeta, details);
                emit ICrystal.Sync(market, m.reserveQuote, m.reserveBase);
                emit ICrystal.Mint(market, address(this), m.reserveQuote, m.reserveBase);
            }
        }
        if (isExactInput ? inputAmount < amountIn : outputAmount < amountOut) { // Token is graduated, swap through orderbook
            uint256 newInputAmount = (msg.value - inputAmount);
            IWETH(weth).deposit{value: newInputAmount}();
            {
                tokenBalances[0][weth] += newInputAmount;
            }
            if (!isExactInput) {
                newInputAmount = amountOut - outputAmount;
            }
            bytes memory ret = abi.encodeWithSelector(0xe690552b, true, isExactInput, (1 << 64), 1, newInputAmount, MASK_KEEP_0_80, address(0), msg.sender);
            bool result;
            address market = getMarketByTokens[weth][token];
            if (market == address(0) || market == placeholder) {
                revert ICrystal.InvalidMarket(weth, token);
            }
            (result, ret) = market.delegatecall(ret);
            if (!result) {
                revert ICrystal.ActionFailed();
            }
            uint256 balance;
            if (!isExactInput) {
                balance = tokenBalances[0][weth];
                if (balance != 0) {
                    tokenBalances[0][weth] = 0;
                    IWETH(weth).withdraw(balance);
                    (bool success, ) = msg.sender.call{value: balance}("");
                    if (!success) {
                        revert ICrystal.TransferFailed(msg.sender);
                    }
                }
            }
            (newInputAmount, balance, ) = abi.decode(ret, (uint256, uint256, uint256)); // Avoid stack too deep
            inputAmount += newInputAmount;
            outputAmount += balance;
        }
        isExactInput ? require(outputAmount >= amountOut) : require(amountIn != 0 ? inputAmount <= amountIn : true);
        return (inputAmount, outputAmount, launchpadMarket.market == address(0));
    }

    /**
     * @notice Returns the number of deployed markets.
     *
     * @return Length of the allMarkets array.
     */
    function allMarketsLength() external view returns (uint256) {
        return allMarkets.length;
    }

    /**
     * @notice Retrieves metadata for a market.
     *
     * @param market Market address.
     *
     * @return info Market info struct.
     */
    function getMarket(address market) external view returns (ICrystal.MarketInfo memory info) {
        ICrystal.Market storage marketInfo = _getMarket[market];
        info = ICrystal.MarketInfo(marketInfo.quoteAsset, marketInfo.baseAsset, marketInfo.marketType, marketInfo.highestBid, marketInfo.lowestAsk, marketInfo.scaleFactor, marketInfo.tickSize, marketInfo.maxPrice, (marketInfo.minSize >> 20) * 10 ** (marketInfo.minSize & MASK_KEEP_0_20), marketInfo.takerFee, marketInfo.makerRebate, marketInfo.reserveQuote, marketInfo.reserveBase, marketInfo.isAMMEnabled);
    }

    /**
     * @notice Returns a user's balances for a token.
     *
     * @param user User address.
     * @param asset Token address.
     *
     * @return totalBalance Sum of available and locked balance.
     * @return availableBalance Unlocked balance.
     * @return lockedBalance Locked balance.
     */
    function getDepositedBalance(address user, address asset) external view returns (uint256 totalBalance, uint256 availableBalance, uint256 lockedBalance) {
        uint256 tokenBalance = tokenBalances[addressToUserId[user]][asset];
        availableBalance = tokenBalance & MASK_KEEP_0_128;
        lockedBalance = tokenBalance >> 128;
        return (availableBalance + lockedBalance, availableBalance, lockedBalance);
    }

    /**
     * @notice Returns all cloid orders for a user within a range.
     *
     * @param user User address.
     * @param range Maximum cloid range to scan.
     *
     * @return cloids List of cloid identifiers.
     * @return userOrders Order structs matching the cloids.
     */
    function getAllOrdersByCloid(address user, uint256 range) external view returns (uint256[] memory cloids, ICrystal.Order[] memory userOrders) {
        uint256 userId = addressToUserId[user];
        uint256[] memory activeCloids = new uint256[](range > 1024 ? 1024 : range);
        uint256 count;
        for (uint256 i = 1; i < (range > 1024 ? 1024 : range); ++i) {
            (uint256 key, uint256 offset) = CS._getCloidOrder(userId, i);
            uint256 order = CS._readMapping(key, offset, CS.ORDERS_KEY);
            if ((order & MASK_OUT_113_154) != 0) {
                activeCloids[count++] = i;
            }
        }

        userOrders = new ICrystal.Order[](count);
        cloids = new uint256[](count);
        for (uint256 i = 0; i < count; ++i) {
            cloids[i] = activeCloids[i];
            userOrders[i] = getOrderByCloid(userId, activeCloids[i]);
        }
    }

    /**
     * @notice Returns an order by user id and cloid.
     *
     * @param userId User id.
     * @param cloid Client order id.
     *
     * @return Order struct for the cloid.
     */
    function getOrderByCloid(uint256 userId, uint256 cloid) public view returns (ICrystal.Order memory) {
        (uint256 key, uint256 offset) = CS._getCloidOrder(userId, cloid);
        uint256 order = CS._readMapping(key, offset, CS.ORDERS_KEY);
        (key, offset) = CS._getVerifyCloid(userId, cloid);
        uint256 price = CS._readMapping(key, offset, CS.ORDERS_KEY);
        uint256 marketId;
        if (cloid & 1 == 0) {
            marketId = ((price >> 208) & MASK_KEEP_0_48);
            price = (price >> 128) & MASK_KEEP_0_80;
        } else {
            marketId = ((price >> 80) & MASK_KEEP_0_48);
            price = price & MASK_KEEP_0_80;
        }
        address market = marketIdToMarket[marketId];
        return ICrystal.Order(price <= _getMarket[market].highestBid ? true : false, market, price, (order & MASK_KEEP_0_112), ((order >> 112) & 0x1), ((order >> 113) & MASK_KEEP_0_41), ((order >> 154) & MASK_KEEP_0_51), ((order >> 205) & MASK_KEEP_0_51));
    }

    /**
     * @notice Returns an order by market, price, and id.
     *
     * @param market Market address.
     * @param price Order price.
     * @param id Order id.
     *
     * @return Order struct for the specified order.
     */
    function getOrder(address market, uint256 price, uint256 id) external view returns (ICrystal.Order memory) {
        ICrystal.Market storage m = _getMarket[market];
        (uint256 key, uint256 offset) = CS._getOrder(m.marketId << 128, price, id);
        uint256 order = CS._readMapping(key, offset, CS.ORDERS_KEY);
        return ICrystal.Order(price <= m.highestBid ? true : false, market, price, (order & MASK_KEEP_0_112), ((order >> 112) & 0x1), ((order >> 113) & MASK_KEEP_0_41), ((order >> 154) & MASK_KEEP_0_51), ((order >> 205) & MASK_KEEP_0_51));
    }

    /**
     * @notice Returns a price level for a market.
     *
     * @param market Market address.
     * @param price Price level.
     *
     * @return Price level struct.
     */
    function getPriceLevel(address market, uint256 price) external view returns (ICrystal.PriceLevel memory) {
        ICrystal.Market storage m = _getMarket[market];
        (uint256 key, uint256 offset) = CS._getPriceLevel(m.marketType, m.tickSize, m.marketId << 128, price);
        uint256 priceLevel = CS._readMapping(key, offset, CS.PRICELEVELS_KEY);
        return ICrystal.PriceLevel((priceLevel & MASK_KEEP_0_112), ((priceLevel >> 113) & MASK_KEEP_0_41), ((priceLevel >> 154) & MASK_KEEP_0_51), ((priceLevel >> 205) & MASK_KEEP_0_51));
    }

    /**
     * @notice Returns aggregated price levels for a market.
     *
     * @param market Market address.
     * @param isAscending True to walk asks upward, false to walk bids downward.
     * @param startPrice Starting price for traversal.
     * @param distance Maximum distance from the start price in ticks.
     * @param interval Bucket interval size.
     * @param max Maximum number of buckets to return (0 = unlimited).
     *
     * @return Encoded price level buckets.
     */
    function getPriceLevels(address market, bool isAscending, uint256 startPrice, uint256 distance, uint256 interval, uint256 max) external returns (bytes memory) {
        _delegateToMarket(market, 0x9c510697, 160, address(0));
        assembly {
            return(0x80, returndatasize())
        }
    }

    /**
     * @notice Returns bid and ask liquidity buckets around the current mid price.
     *
     * @param market Market address.
     * @param distance Number of ticks to scan on each side.
     * @param interval Bucket interval size.
     * @param max Maximum buckets per side (0 = unlimited).
     *
     * @return highestBid Current best bid.
     * @return lowestAsk Current best ask.
     * @return bids Encoded bid buckets.
     * @return asks Encoded ask buckets.
     */
    function getPriceLevelsFromMid(address market, uint256 distance, uint256 interval, uint256 max) external returns (uint256 highestBid, uint256 lowestAsk, bytes memory, bytes memory) {
        _delegateToMarket(market, 0xd58887ae, 96, address(0));
        assembly {
            return(0x80, returndatasize())
        }
    }

    /**
     * @notice Returns the midpoint price including AMM adjustments.
     *
     * @param market Market address.
     *
     * @return price Rounded midpoint price.
     * @return highestBid Best bid considering orderbook and AMM.
     * @return lowestAsk Best ask considering orderbook and AMM.
     */
    function getPrice(address market) external returns (uint256 price, uint256 highestBid, uint256 lowestAsk) {
        _delegateToMarket(market, 0x98d5fdca, 0, address(0));
        assembly {
            price := mload(0x80)
            highestBid := mload(0xa0)
            lowestAsk := mload(0xc0)
        }
    }

    /**
     * @notice Quotes a trade against a market without modifying state.
     *
     * @param market Market address.
     * @param isBuy True for buy, false for sell.
     * @param isExactInput True if `size` is an input amount, false if output.
     * @param isCompleteFill Whether to revert when price limits are exceeded.
     * @param size Input or output amount depending on `isExactInput`.
     * @param worstPrice Inclusive worst price limit.
     *
     * @return amountIn Required input amount.
     * @return amountOut Expected output amount.
     */
    function getQuote(address market, bool isBuy, bool isExactInput, bool isCompleteFill, uint256 size, uint256 worstPrice) external returns (uint256 amountIn, uint256 amountOut) {
        _delegateToMarket(market, 0x638571e3, 160, address(0));
        assembly {
            amountIn := mload(0x80)
            amountOut := mload(0xa0)
        }
    }

    /**
     * @notice Returns AMM reserves for a market.
     *
     * @param market Market address.
     *
     * @return reserveQuote Quote asset reserve.
     * @return reserveBase Base asset reserve.
     */
    function getReserves(address market) external returns (uint112 reserveQuote, uint112 reserveBase) {
        _delegateToMarket(market, 0x0902f1ac, 0, address(0));
        assembly {
            reserveQuote := mload(0x80)
            reserveBase := mload(0xa0)
        }
    }

    /**
     * @notice Adds liquidity to a market AMM and mints LP tokens.
     *
     * @param market Market address.
     * @param to Recipient of LP tokens.
     * @param amountQuoteDesired Desired quote asset amount.
     * @param amountBaseDesired Desired base asset amount.
     * @param amountQuoteMin Minimum quote accepted.
     * @param amountBaseMin Minimum base accepted.
     *
     * @return liquidity Liquidity tokens minted.
     */
    function addLiquidity(address market, address to, uint256 amountQuoteDesired, uint256 amountBaseDesired, uint256 amountQuoteMin, uint256 amountBaseMin) external payable nonReentrant returns (uint256 liquidity) {
        uint256 options;
        if (msg.value != 0) {
            IWETH(weth).deposit{value: msg.value}();
            tokenBalances[0][weth] += msg.value;
            require(_getMarket[market].quoteAsset == weth || _getMarket[market].baseAsset == weth);
            options = _getMarket[market].quoteAsset == weth ? (1) : (1 << 4);
        }
        if (options != 0) {
            _delegateToMarket(market, 0x2563e426, 160, address(uint160(options)));
        } else {
            _delegateToMarket(market, 0x2563e426, 192, address(0));
        }
        assembly {
            liquidity := mload(0x80)
        }
        if (msg.value != 0) {
            uint256 balance = tokenBalances[0][weth] & MASK_KEEP_0_128;
            if (balance != 0) {
                tokenBalances[0][weth] = 0;
                IWETH(weth).withdraw(balance);
                (bool success, ) = msg.sender.call{value: balance}("");
                if (!success) {
                    revert ICrystal.TransferFailed(msg.sender);
                }
            }
        }
    }

    /**
     * @notice Burns LP tokens to withdraw AMM liquidity.
     *
     * @param market Market address.
     * @param to Recipient of withdrawn tokens.
     * @param liquidity LP tokens to burn.
     * @param amountQuoteMin Minimum quote expected.
     * @param amountBaseMin Minimum base expected.
     *
     * @return amountQuote Quote asset returned.
     * @return amountBase Base asset returned.
     */
    function removeLiquidity(address market, address to, uint256 liquidity, uint256 amountQuoteMin, uint256 amountBaseMin) external nonReentrant returns (uint256 amountQuote, uint256 amountBase) {
        _delegateToMarket(market, 0x13928082, 160, address(0));
        assembly {
            amountQuote := mload(0x80)
            amountBase := mload(0xa0)
        }
    }

    /**
     * @notice Burns LP tokens to withdraw AMM liquidity, unwrapping WETH.
     *
     * @param market Market address.
     * @param to Recipient of withdrawn tokens.
     * @param liquidity LP tokens to burn.
     * @param amountQuoteMin Minimum quote expected.
     * @param amountBaseMin Minimum base expected.
     *
     * @return amountQuote Quote asset returned.
     * @return amountBase Base asset returned.
     */
    function removeLiquidityETH(address market, address to, uint256 liquidity, uint256 amountQuoteMin, uint256 amountBaseMin) external nonReentrant returns (uint256 amountQuote, uint256 amountBase) {
        require(_getMarket[market].quoteAsset == weth || _getMarket[market].baseAsset == weth);
        uint256 options = _getMarket[market].quoteAsset == weth ? (1) : (1 << 4);
        _delegateToMarket(market, 0x13928082, 128, address(uint160(options)));
        assembly {
            amountQuote := mload(0x80)
            amountBase := mload(0xa0)
        }
        uint256 balance = tokenBalances[0][weth] & MASK_KEEP_0_128;
        if (balance != 0) {
            tokenBalances[0][weth] = 0;
            IWETH(weth).withdraw(balance);
            (bool success, ) = to.call{value: balance}("");
            if (!success) {
                revert ICrystal.TransferFailed(to);
            }
        }
    }

    /**
     * @notice Executes a market order through a specified market.
     *
     * @param market Market address.
     * @param isBuy True for buy, false for sell.
     * @param isExactInput True if `size` is an input amount, false if output.
     * @param options Packed flags for balance routing and identifiers.
     * @param orderType Execution type (IOC/MTL/partial/complete).
     * @param size Input or output amount depending on `isExactInput`.
     * @param worstPrice Inclusive worst price limit.
     * @param referrer Optional referrer for fee sharing.
     * @param user User executing the order.
     *
     * @return amountIn Total input amount including fees.
     * @return amountOut Total output amount after fees.
     * @return id New order id if a fallback limit order was placed.
     */
    function marketOrder(address market, bool isBuy, bool isExactInput, uint256 options, uint256 orderType, uint256 size, uint256 worstPrice, address referrer, address user) external nonReentrant returns (uint256 amountIn, uint256 amountOut, uint256 id) {
        user = _verifyUser(user);
        _delegateToMarket(market, 0xe690552b, 224, user);
        assembly {
            amountIn := mload(0x80)
            amountOut := mload(0xa0)
            id := mload(0xc0)
        }
    }

    /**
     * @notice Places a limit order through a specified market.
     *
     * @param market Market address.
     * @param isBuy True for bids, false for asks.
     * @param options Packed flags for balance routing and identifiers.
     * @param price Limit price.
     * @param size Order size.
     * @param user Order owner.
     *
     * @return id Assigned order identifier.
     */
    function limitOrder(address market, bool isBuy, uint256 options, uint256 price, uint256 size, address user) external nonReentrant returns (uint256 id) {
        user = _verifyUser(user);
        _delegateToMarket(market, 0x218a0c31, 128, user);
        assembly {
            id := mload(0x80)
        }
    }

    /**
     * @notice Cancels an order through a specified market.
     *
     * @param market Market address.
     * @param options Packed flags for balance destination and identifiers.
     * @param price Order price (0 when cancelling by cloid).
     * @param id Order id or cloid.
     * @param user Order owner.
     *
     * @return size Amount released.
     */
    function cancelOrder(address market, uint256 options, uint256 price, uint256 id, address user) external nonReentrant returns (uint256 size) {
        user = _verifyUser(user);
        _delegateToMarket(market, 0xb69d86f7, 96, user);
        assembly {
            size := mload(0x80)
        }
    }

    /**
     * @notice Replaces or decreases an existing order through a market.
     *
     * @param market Market address.
     * @param options Packed flags for balance routing and identifiers.
     * @param price Existing order price (0 when using a cloid).
     * @param id Existing order id or cloid.
     * @param newPrice New price (may embed referrer).
     * @param size New size (0 to reuse previous size).
     * @param referrer Referrer address for fee sharing.
     * @param user Order owner.
     *
     * @return _id Identifier of the replacement order, or 0 if none.
     */
    function replaceOrder(address market, uint256 options, uint256 price, uint256 id, uint256 newPrice, uint256 size, address referrer, address user) external nonReentrant returns (uint256 _id) {
        user = _verifyUser(user);
        _delegateToMarket(market, 0x6c8dce79, 192, user);
        assembly {
            _id := mload(0x80)
        }
    }

    /**
     * @notice Executes a batch of order actions on a market.
     *
     * @param market Market address.
     * @param actions Array of encoded actions to execute.
     * @param options Packed flags for balance routing and identifiers.
     * @param deadline Timestamp after which the batch expires.
     * @param referrer Referrer address used for market orders.
     * @param user Caller associated with the actions.
     */
    function batchOrders(address market, ICrystal.Action[] calldata actions, uint256 options, uint256 deadline, address referrer, address user) external payable nonReentrant {
        user = _verifyUser(user);
        if (deadline < block.timestamp) {
            revert ICrystal.Expired(deadline);
        }
        if (msg.value != 0) {
            IWETH(weth).deposit{value: msg.value}();
            tokenBalances[0][weth] += msg.value;
        }
        _verifyMarket(market);
        (bool result, bytes memory ret) = market.delegatecall(abi.encodeWithSelector(0x5c2a91ec, actions, options, referrer, user));
        assembly {
            switch result
            case 0 {
                revert(add(ret, 32), mload(ret))
            }
        }
        uint256 balance = tokenBalances[0][weth] & MASK_KEEP_0_128;
        if (balance != 0) {
            tokenBalances[0][weth] = 0;
            IWETH(weth).withdraw(balance);
            (bool success, ) = msg.sender.call{value: balance}("");
            if (!success) {
                revert ICrystal.TransferFailed(msg.sender);
            }
        }
    }

    /**
     * @notice Updates the governance address.
     *
     * @param newGov New governance address.
     */
    function changeGov(address newGov) external onlyOwner {
        gov = newGov;
        emit ICrystal.GovChanged(msg.sender, newGov);
    }

    /**
     * @notice Updates the protocol fee recipient.
     *
     * @param newFeeRecipient New fee recipient address.
     */
    function changeFeeRecipient(address newFeeRecipient) external onlyOwner {
        require(newFeeRecipient != address(0));
        feeRecipient = newFeeRecipient;
    }

    /**
     * @notice Updates the fee claim duration.
     *
     * @param newFeeClaimDuration New fee claim duration.
     */
    function changeFeeClaimDuration(uint256 newFeeClaimDuration) external onlyOwner {
        require(newFeeClaimDuration > 86400);
        feeClaimDuration = newFeeClaimDuration;
    }

    /**
     * @notice Updates the referral fee commission.
     *
     * @param newFeeCommission New commission percentage.
     */
    function changeRefFeeCommission(uint8 newFeeCommission) external onlyOwner {
        require(newFeeCommission <= 50);
        feeCommission = newFeeCommission;
    }

    /**
     * @notice Updates core parameters of a market.
     *
     * @param market Market address.
     * @param newMinSize New minimum size.
     * @param newTakerFee New taker fee (scaled by 1e5).
     * @param newMakerRebate New maker rebate (scaled by 1e5).
     * @param isAMMEnabled Whether the AMM is enabled.
     * @param isCanonical Whether the market is canonical.
     */
    function changeMarketParams(address market, uint256 newMinSize, uint24 newTakerFee, uint24 newMakerRebate, bool isAMMEnabled, bool isCanonical) external {
        require((isCanonicalDeployer[msg.sender] || msg.sender == gov) && MAX_FEE <= newTakerFee && newTakerFee <= 100000 && MAX_FEE <= newMakerRebate && newMakerRebate <= 100000);
        ICrystal.Market storage m = _getMarket[market];
        if (msg.sender != gov && msg.sender != m.creator) {
            revert ICrystal.Unauthorized(msg.sender);
        }
        uint256 minSizeZeroes;
        while (newMinSize != 0 && newMinSize % 10 == 0) {
            newMinSize /= 10;
            ++minSizeZeroes;
        }
        require(newMinSize > 0 && newMinSize < MASK_KEEP_0_20 && minSizeZeroes < MASK_KEEP_0_20);
        m.minSize = uint40((newMinSize << 20) | minSizeZeroes);
        m.takerFee = newTakerFee;
        m.makerRebate = newMakerRebate;
        m.isAMMEnabled = isAMMEnabled;
        if (isCanonical && (getMarketByTokens[m.quoteAsset][m.baseAsset] == address(0) || msg.sender == gov)) {
            getMarketByTokens[m.quoteAsset][m.baseAsset] = market;
            getMarketByTokens[m.baseAsset][m.quoteAsset] = market;
        } else if (!isCanonical && getMarketByTokens[m.quoteAsset][m.baseAsset] == market) {
            getMarketByTokens[m.quoteAsset][m.baseAsset] = address(0);
            getMarketByTokens[m.baseAsset][m.quoteAsset] = address(0);
        }
        emit ICrystal.MarketParamsChanged(market, (m.minSize >> 20) * 10 ** (m.minSize & MASK_KEEP_0_20), newTakerFee, newMakerRebate, m.isAMMEnabled);
    }

    /**
     * @notice Updates market creator address or fee split.
     *
     * @param market Market address.
     * @param newCreator New creator address.
     * @param newCreatorFee New creator fee split.
     */
    function changeMarketCreatorFee(address market, address newCreator, uint256 newCreatorFee) external {
        ICrystal.Market storage m = _getMarket[market];
        if (newCreatorFee == m.creatorFeeSplit) {
            require(msg.sender == m.creator || msg.sender == gov);
            m.creator = newCreator;
            return;
        }
        require((isCanonicalDeployer[msg.sender] || msg.sender == gov) && newCreatorFee <= 50);
        if (msg.sender != gov && msg.sender != m.creator) {
            revert ICrystal.Unauthorized(msg.sender);
        }
        m.creator = newCreator;
        m.creatorFeeSplit = uint8(newCreatorFee);
    }

    /**
     * @notice Updates global launchpad parameters.
     *
     * @param newLaunchpadParams New launchpad configuration.
     */
    function changeLaunchpadParams(ICrystal.LaunchpadParams memory newLaunchpadParams) external onlyOwner {
        uint256 minSizeZeroes;
        uint256 minSize = newLaunchpadParams.graduatedMinSize;
        while (minSize != 0 && minSize % 10 == 0) {
            minSize /= 10;
            ++minSizeZeroes;
        }
        require(minSize > 0 && minSize < MASK_KEEP_0_20 && minSizeZeroes < MASK_KEEP_0_20 && newLaunchpadParams.launchpadInitialNativeSupply > 1e18 && MAX_FEE <= newLaunchpadParams.launchpadFee && newLaunchpadParams.launchpadFee <= 100000 && MAX_FEE <= newLaunchpadParams.graduatedTakerFee);
        require(newLaunchpadParams.graduatedTakerFee <= 100000 && MAX_FEE <= newLaunchpadParams.graduatedMakerRebate && newLaunchpadParams.graduatedMakerRebate <= 100000 && newLaunchpadParams.graduatedCreatorFeeSplit <= 50 && newLaunchpadParams.launchpadCreatorFeeSplit <= 50);
        launchpadParams = newLaunchpadParams;
    }

    /**
     * @notice Adds an address authorized to deploy canonical markets.
     *
     * @param deployer Deployer address.
     */
    function addCanonicalDeployer(address deployer) external onlyOwner {
        isCanonicalDeployer[deployer] = true;
    }

    /**
     * @notice Removes a canonical deployer.
     *
     * @param deployer Deployer address.
     */
    function removeCanonicalDeployer(address deployer) external onlyOwner {
        isCanonicalDeployer[deployer] = false;
    }

    /**
     * @notice Approves a forwarder for msg.sender.
     *
     * @param forwarder Forwarder address.
     */
    function approveForwarder(address forwarder) external {
        approvedForwarder[msg.sender][forwarder] = true;
    }

    /**
     * @notice Revokes forwarder approval for msg.sender.
     *
     * @param forwarder Forwarder address.
     */
    function removeForwarder(address forwarder) external {
        approvedForwarder[msg.sender][forwarder] = false;
    }

    /**
     * @notice Registers a user and returns their user id.
     *
     * @param user User address to register (must match caller unless called internally).
     *
     * @return userId Assigned user id.
     */
    function registerUser(address user) external returns (uint256 userId) {
        if (msg.sender != user && msg.sender != address(this)) {
            revert ICrystal.Unauthorized(msg.sender);
        }
        userId = _registerUser(0, user);
    }

    /**
     * @notice Deposits tokens into the exchange for the caller.
     *
     * @param token Token address.
     * @param amount Amount to deposit.
     *
     * @return userId Caller user id.
     */
    function deposit(address token, uint256 amount) external payable nonReentrant returns (uint256 userId) {
        userId = addressToUserId[msg.sender];
        if (userId == 0) {
            userId = _registerUser(0, msg.sender);
        }
        if (token == eth) {
            require(msg.value == amount);
            token = weth;
            IWETH(weth).deposit{value: amount}();
        } else {
            IERC20(token).transferFrom(msg.sender, address(this), amount);
        }
        require(((tokenBalances[userId][token] & MASK_KEEP_0_128) + amount) <= MASK_KEEP_0_128);
        tokenBalances[userId][token] += amount;
        emit ICrystal.Deposit(msg.sender, userId, token, amount);
    }

    /**
     * @notice Withdraws tokens from the exchange.
     *
     * @param to Recipient address.
     * @param token Token address.
     * @param amount Amount to withdraw (0 withdraws full balance).
     */
    function withdraw(address to, address token, uint256 amount) external nonReentrant {
        bool isETH;
        if (token == eth) {
            token = weth;
            isETH = true;
        }
        uint256 userId = addressToUserId[msg.sender];
        uint256 balance = tokenBalances[userId][token];
        if (amount == 0) {
            amount = uint128(balance);
        }
        if (uint128(balance) < amount || userId == 0) {
            revert ICrystal.ActionFailed();
        } else {
            tokenBalances[userId][token] = balance - amount;
        }
        if (isETH) {
            IWETH(weth).withdraw(amount);
            (bool success, ) = to.call{value: amount}("");
            if (!success) {
                revert ICrystal.TransferFailed(to);
            }
        } else {
            IERC20(token).transfer(to, amount);
        }
        emit ICrystal.Withdraw(msg.sender, userId, token, amount);
    }

    /**
     * @notice Clears inactive cloid slots for a user.
     *
     * @param userId User id.
     * @param ids Cloid slot ids to clear.
     */
    function clearCloidSlots(uint256 userId, uint256[] calldata ids) external nonReentrant {
        if (msg.sender != userIdToAddress[userId] && msg.sender != gov) {
            revert ICrystal.Unauthorized(msg.sender);
        }
        for (uint256 i; i < ids.length; ++i) {
            uint256 id = ids[i];
            if (id > 0 && id < 1024) {
                (uint256 key, uint256 offset) = CS._getCloidOrder(userId, id);
                if ((CS._readMapping(key, offset, CS.ORDERS_KEY) & MASK_OUT_113_154) == 0) { // Slot is inactive and safe to clear
                    CS._writeMapping(key, offset, CS.ORDERS_KEY, 0);
                    (key, offset) = CS._getVerifyCloid(userId, id);
                    uint256 verifyCloid = CS._readMapping(key, offset, CS.ORDERS_KEY) & (id & 1 == 0 ? MASK_KEEP_0_128 : MASK_OUT_0_128);
                    CS._writeMapping(key, offset, CS.ORDERS_KEY, verifyCloid);
                }
            }
        }
    }

    /**
     * @notice Marks cloid slots as initialized for a user.
     *
     * @dev To make gas costs more deterministic.
     *
     * @param userId User id.
     * @param ids Cloid slot ids to write.
     */
    function writeCloidSlots(uint256 userId, uint256[] calldata ids) external nonReentrant {
        if (msg.sender != userIdToAddress[userId]) {
            revert ICrystal.Unauthorized(msg.sender);
        }
        for (uint256 i; i < ids.length; ++i) {
            uint256 id = ids[i];
            if (id > 0 && id < 1024) {
                (uint256 key, uint256 offset) = CS._getCloidOrder(userId, id);
                if (CS._readMapping(key, offset, CS.ORDERS_KEY) == 0) {
                    CS._writeMapping(key, offset, CS.ORDERS_KEY, (userId << 113));
                    (key, offset) = CS._getVerifyCloid(userId, id);
                    uint256 verifyCloid = CS._readMapping(key, offset, CS.ORDERS_KEY) | (id & 1 == 0 ? MASK_OUT_0_128 : MASK_KEEP_0_128);
                    CS._writeMapping(key, offset, CS.ORDERS_KEY, verifyCloid);
                }
            }
        }
    }

    /**
     * @notice Writes orderbook slot bitmaps for a market.
     *
     * @dev To make gas costs more deterministic.
     *
     * @param market Market address.
     * @param slotIndexes Slot indexes for activated bitmap.
     * @param groupIndexes Slot indexes for groups bitmap.
     */
    function writeSlots(address market, uint256[] calldata slotIndexes, uint256[] calldata groupIndexes) external nonReentrant {
        uint256 key;
        uint256 offset;
        for (uint256 i; i < slotIndexes.length; ++i) {
            require(slotIndexes[i] < MASK_KEEP_0_128);
            (key, offset) = CS._getActivated(_getMarket[market].marketId << 128, slotIndexes[i]);
            CS._writeMapping(key, offset, CS.PRICELEVELS_KEY, CS._readMapping(key, offset, CS.PRICELEVELS_KEY) | MASK_KEEP_255_256);
        }
        for (uint256 i; i < groupIndexes.length; ++i) {
            require(groupIndexes[i] < MASK_KEEP_0_128);
            (key, offset) = CS._getGroups(_getMarket[market].marketId << 128, groupIndexes[i]);
            CS._writeMapping(key, offset, CS.GROUPS_KEY, CS._readMapping(key, offset, CS.GROUPS_KEY) | MASK_KEEP_255_256);
        }
    }

    /**
     * @notice Adds claimable fee amounts for an address.
     *
     * @param to Address receiving fees.
     * @param tokens Token list.
     * @param amounts Amount list matching tokens.
     */
    function addClaimableFee(address to, address[] calldata tokens, uint256[] calldata amounts) external payable {
        uint256 value = msg.value;
        for (uint256 i = 0; i < tokens.length; ++i) {
            if (tokens[i] == eth) {
                require(value >= amounts[i]);
                value -= amounts[i];
                IWETH(weth).deposit{value: amounts[i]}();
                claimableRewards[weth][to] += amounts[i];
            } else {
                claimableRewards[tokens[i]][to] += amounts[i];
                IERC20(tokens[i]).transferFrom(msg.sender, address(this), amounts[i]);
            }
        }
        require(value == 0);
    }

    /**
     * @notice Claims accumulated trading fees for selected tokens.
     *
     * @dev Vault/margin operators can claim to their wallet, resets any pending expiry claims.
     *
     * @param to Recipient address.
     * @param tokens Token list to claim.
     *
     * @return amounts Claimed amounts per token.
     */
    function claimFees(address to, address[] calldata tokens) external nonReentrant returns (uint256[] memory amounts) {
        amounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            if (tokens[i] == eth) {
                amounts[i] = claimableRewards[weth][msg.sender];
                claimableRewards[weth][msg.sender] = 0;
                IWETH(weth).withdraw(amounts[i]);
                (bool success, ) = to.call{value: amounts[i]}("");
                if (!success) {
                    revert ICrystal.TransferFailed(to);
                }
            } else {
                amounts[i] = claimableRewards[tokens[i]][msg.sender];
                claimableRewards[tokens[i]][msg.sender] = 0;
                IERC20(tokens[i]).transfer(to, amounts[i]);
            }
        }
        delete pendingExpiredFeeClaims[msg.sender];
        emit ICrystal.RewardsClaimed(msg.sender, tokens, amounts);
    }

    /**
     * @notice Queues a claim for expired fee balances.
     *
     * @param user User whose fees are expiring.
     * @param tokens Tokens to claim.
     */
    function queueClaimExpiredFees(address user, address[] calldata tokens) external {
        if (pendingExpiredFeeClaims[user].deadline != 0 && msg.sender != gov) {
            revert ICrystal.Unauthorized(msg.sender);
        }
        require(tokens.length != 0 && tokens.length < 100);
        uint256[] memory amounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            address token = tokens[i];
            assembly {
                mstore(0x00, token)
                let slot := keccak256(0x00, 0x20)
                if tload(slot) { revert(0,0) }
                tstore(slot, 1)
            }
            uint256 amount = claimableRewards[token][user];
            if (msg.sender != gov) {
                require(amount > 0);
            }
            amounts[i] = amount;
        }
        pendingExpiredFeeClaims[user].deadline = block.timestamp + feeClaimDuration;
        pendingExpiredFeeClaims[user].tokens = tokens;
        pendingExpiredFeeClaims[user].amounts = amounts;
    }

    /**
     * @notice Executes a queued expired fee claim.
     *
     * @param user User whose fees are being claimed.
     *
     * @return amounts Claimed amounts per token.
     */
    function executeClaimExpiredFees(address user) external onlyOwner returns (uint256[] memory amounts) {
        require(block.timestamp >= pendingExpiredFeeClaims[user].deadline);
        amounts = pendingExpiredFeeClaims[user].amounts;
        for (uint256 i = 0; i < pendingExpiredFeeClaims[user].tokens.length; ++i) {
            claimableRewards[pendingExpiredFeeClaims[user].tokens[i]][user] -= amounts[i];
            IERC20(pendingExpiredFeeClaims[user].tokens[i]).transfer(msg.sender, amounts[i]);
        }
        delete pendingExpiredFeeClaims[user];
    }

    /**
     * @notice Deploys a new Crystal market.
     *
     * @dev Total fee is equal to takerFee + makerRebate.
     *
     * @param isCanonical Whether the market should be canonical for the token pair.
     * @param quoteAsset Quote asset address.
     * @param baseAsset Base asset address.
     * @param marketType Market type identifier.
     * @param scaleFactor Market scale factor.
     * @param tickSize Tick size for the market.
     * @param maxPrice Maximum price supported.
     * @param minSize Minimum order size.
     * @param takerFee Taker fee (scaled by 1e5).
     * @param makerRebate Maker rebate (scaled by 1e5).
     *
     * @return market Address of the newly deployed market.
     */
    function deploy(bool isCanonical, address quoteAsset, address baseAsset, uint256 marketType, uint256 scaleFactor, uint256 tickSize, uint256 maxPrice, uint256 minSize, uint24 takerFee, uint24 makerRebate) external nonReentrant returns (address market) {
        if (isCanonical && !isCanonicalDeployer[msg.sender]) {
            revert ICrystal.Unauthorized(msg.sender);
        }
        if (quoteAsset == eth) {
            quoteAsset = weth;
        } else if (baseAsset == eth) {
            baseAsset = weth;
        }
        require(MAX_FEE <= takerFee && takerFee <= 100000 && MAX_FEE <= makerRebate && makerRebate <= 100000 && maxPrice % tickSize == 0);
        uint256 marketId = allMarkets.length + 1;
        {
            parameters = ICrystal.Parameters(quoteAsset, baseAsset, marketId, marketType, scaleFactor, tickSize, maxPrice);
            uint256 maxTick;
            market = address(new CrystalMarket{salt: keccak256(abi.encode(marketId))}());
            if (marketType == 0) {
                maxTick = maxPrice / tickSize;
            } else if (marketType == 1 || marketType == 2 || marketType == 3) {
                maxTick = CM._priceToTick(maxPrice, tickSize);
            } else {
                revert ICrystal.ActionFailed();
            }
            delete parameters;
            ICrystal.Market storage m = _getMarket[market];
            (m.quoteAsset, m.baseAsset, m.marketId, m.scaleFactor, m.tickSize) = (quoteAsset, baseAsset, marketId, scaleFactor, tickSize);
            (m.takerFee, m.makerRebate, m.maxPrice, m.marketType, m.isAMMEnabled) = (takerFee, makerRebate, maxPrice, marketType, marketType > 1);
            (m.creator, m.creatorFeeSplit) = (msg.sender, uint8(launchpadParams.graduatedCreatorFeeSplit));
            m.lowestAsk = uint80(maxPrice);
            (uint256 key, uint256 offset) = CS._getActivated((marketId << 128), 0); // Preset index 0 and maxPrice of activated bitmap
            CS._writeMapping(key, offset, CS.PRICELEVELS_KEY, 1);
            (key, offset) = CS._getGroups((marketId << 128), 0);
            CS._writeMapping(key, offset, CS.GROUPS_KEY, 1);
            (key, offset) = CS._getActivated((marketId << 128), maxTick / 255);
            CS._writeMapping(key, offset, CS.PRICELEVELS_KEY, (1 << (maxTick % 255)) | ((maxTick / 255) == 0 ? 1 : 0));
            (key, offset) = CS._getGroups((marketId << 128), (maxTick / 255) / 255);
            CS._writeMapping(key, offset, CS.GROUPS_KEY, (1 << ((maxTick / 255) % 255)) | ((maxTick / 255) == 0 ? 1 : 0));
            uint256 minSizeZeroes;
            uint256 _minSize = minSize;
            while (_minSize != 0 && _minSize % 10 == 0) {
                _minSize /= 10;
                ++minSizeZeroes;
            }
            require(minSize > 0 && _minSize < MASK_KEEP_0_20 && minSizeZeroes < MASK_KEEP_0_20 && marketId < MASK_KEEP_0_48); // minSize is encoded as mantissa + exponent to bound storage and prevent DoS; marketId constrained to uint48
            m.minSize = uint40((_minSize << 20) | minSizeZeroes);
        }
        allMarkets.push(market);
        marketIdToMarket[marketId] = market;
        require(launchpadTokenToMarket[baseAsset].virtualNativeReserve == 0 && launchpadTokenToMarket[quoteAsset].virtualNativeReserve == 0);
        if (isCanonical) {
            getMarketByTokens[quoteAsset][baseAsset] = market;
            getMarketByTokens[baseAsset][quoteAsset] = market;
        } else {
            if (getMarketByTokens[quoteAsset][baseAsset] == address(0) && (marketType == 1 || marketType == 2)) {
                getMarketByTokens[quoteAsset][baseAsset] = market;
                getMarketByTokens[baseAsset][quoteAsset] = market;
            }
        }
        ICrystal.TokenMetadata memory quoteMeta = ICrystal.TokenMetadata(quoteAsset, IERC20(quoteAsset).decimals(), IERC20(quoteAsset).symbol(), IERC20(quoteAsset).name());
        ICrystal.TokenMetadata memory baseMeta = ICrystal.TokenMetadata(baseAsset, IERC20(baseAsset).decimals(), IERC20(baseAsset).symbol(), IERC20(baseAsset).name());
        ICrystal.MarketDetails memory details = ICrystal.MarketDetails(marketId, marketType, scaleFactor, tickSize, maxPrice, minSize, takerFee, makerRebate);
        bool _isCanonical = isCanonical; // Avoid stack too deep
        emit ICrystal.MarketCreated(_isCanonical, quoteAsset, baseAsset, market, quoteMeta, baseMeta, details);
    }

    /**
     * @notice Quotes output amounts for a multi-hop swap path.
     *
     * @param amountIn Input amount for the first hop.
     * @param path Token swap path.
     *
     * @return amounts Array of hop-by-hop amounts.
     */
    function getAmountsOut(uint256 amountIn, address[] memory path) external returns (uint256[] memory amounts) {
        if (path.length < 2) {
            revert ICrystal.InvalidPath(path);
        }
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i; i < path.length - 1; ++i) {
            address asset0 = path[i] == eth ? weth : path[i];
            address asset1 = path[i + 1] == eth ? weth : path[i + 1];
            address market = getMarketByTokens[asset0][asset1];
            if (market == address(0) || market == placeholder) {
                revert ICrystal.InvalidMarket(asset0, asset1);
            }
            uint256 inputAmount;
            (bool result, bytes memory ret) = market.delegatecall(abi.encodeWithSelector(0x638571e3, _getMarket[market].quoteAsset == asset0, true, i != 0, amounts[i], _getMarket[market].quoteAsset == asset0 ? MASK_KEEP_0_80 : 1));
            require(result);
            (inputAmount, amounts[i + 1]) = abi.decode(ret, (uint256, uint256));
            if (i != 0 && amounts[i] != inputAmount) {
                revert ICrystal.SlippageExceeded();
            }
        }
    }

    /**
     * @notice Quotes required input amounts for a desired output across a path.
     *
     * @param amountOut Desired final output amount.
     * @param path Token swap path.
     *
     * @return amounts Array of hop-by-hop amounts.
     */
    function getAmountsIn(uint256 amountOut, address[] memory path) public returns (uint256[] memory amounts) {
        if (path.length < 2) {
            revert ICrystal.InvalidPath(path);
        }
        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint256 i = path.length - 1; i != 0; --i) {
            address asset0 = path[i - 1] == eth ? weth : path[i - 1];
            address asset1 = path[i] == eth ? weth : path[i];
            address market = getMarketByTokens[asset0][asset1];
            if (market == address(0) || market == placeholder) {
                revert ICrystal.InvalidMarket(asset0, asset1);
            }
            uint256 outputAmount;
            (bool result, bytes memory ret) = market.delegatecall(abi.encodeWithSelector(0x638571e3, _getMarket[market].quoteAsset == asset0, false, true, amounts[i], _getMarket[market].quoteAsset == asset0 ? MASK_KEEP_0_80 : 1));
            if (!result) {
                revert ICrystal.SlippageExceeded();
            }
            (amounts[i - 1], outputAmount) = abi.decode(ret, (uint256, uint256));
        }
    }

    /**
     * @notice Executes an exact-input multi-hop swap.
     *
     * @param amountIn Input amount.
     * @param path Swap path.
     * @param to Recipient of final output.
     * @param referrer Optional referrer for fee sharing.
     *
     * @return amounts Hop-by-hop amounts used.
     */
    function exactInputSwap(uint256 amountIn, address[] memory path, address to, address referrer) internal returns (uint256[] memory amounts) {
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i; i < path.length - 1; ++i) {
            address asset0 = path[i] == eth ? weth : path[i];
            address asset1 = path[i + 1] == eth ? weth : path[i + 1];
            address market = getMarketByTokens[asset0][asset1];
            if (market == address(0) || market == placeholder) {
                revert ICrystal.InvalidMarket(asset0, asset1);
            }
            asset1 = _getMarket[market].quoteAsset;
            uint256 options = ((i != 0 || path[i] == eth) ? (1 << 64) : 0) | ((i != path.length - 2 || path[i + 1] == eth || to != msg.sender) ? (1 << 60) : 0);
            bytes memory ret = abi.encodeWithSelector(0xe690552b, asset1 == asset0, true, options, 1, amounts[i], asset1 == asset0 ? MASK_KEEP_0_80 : 1, referrer, msg.sender);
            bool result;
            (result, ret) = market.delegatecall(ret);
            if (!result) {
                revert ICrystal.SlippageExceeded();
            }
            (, amounts[i + 1], ) = abi.decode(ret, (uint256, uint256, uint256));
        }
    }

    /**
     * @notice Executes an exact-output multi-hop swap.
     *
     * @param amounts Precomputed hop amounts (output-focused).
     * @param path Swap path.
     * @param to Recipient of final output.
     * @param referrer Optional referrer for fee sharing.
     */
    function exactOutputSwap(uint256[] memory amounts, address[] memory path, address to, address referrer) internal {
        for (uint256 i; i < path.length - 1; ++i) {
            address asset0 = path[i] == eth ? weth : path[i];
            address asset1 = path[i + 1] == eth ? weth : path[i + 1];
            address market = getMarketByTokens[asset0][asset1];
            if (market == address(0) || market == placeholder) {
                revert ICrystal.InvalidMarket(asset0, asset1);
            }
            asset1 = _getMarket[market].quoteAsset;
            uint256 options = ((i != 0 || path[i] == eth) ? (1 << 64) : 0) | ((i != path.length - 2 || path[i + 1] == eth || to != msg.sender) ? (1 << 60) : 0);
            bytes memory ret = abi.encodeWithSelector(0xe690552b, asset1 == asset0, false, options, 1, amounts[i + 1], asset1 == asset0 ? MASK_KEEP_0_80 : 1, referrer, msg.sender);
            bool result;
            (result, ret) = market.delegatecall(ret);
            if (!result) {
                revert ICrystal.SlippageExceeded();
            }
            (amounts[i], , ) = abi.decode(ret, (uint256, uint256, uint256));
        }
    }

    /**
     * @notice Deposits tokens into the router's shared slot.
     *
     * @dev Anyone can deposit/withdraw from 0 slot, used as in between for multihop swaps.
     *
     * @param token Token address.
     * @param amount Amount to deposit.
     */
    function routerDeposit(address token, uint256 amount) external payable nonReentrant {
        if (token == eth) {
            require(msg.value == amount);
            token = weth;
            IWETH(weth).deposit{value: amount}();
        } else {
            IERC20(token).transferFrom(msg.sender, address(this), amount);
        }
        tokenBalances[0][token] += amount;
    }

    /**
     * @notice Withdraws tokens from the router's shared slot.
     *
     * @dev Anyone can deposit/withdraw from the 0 slot, if amount = 0 withdraw all.
     *
     * @param to Recipient address.
     * @param token Token address.
     * @param amount Amount to withdraw.
     */
    function routerWithdraw(address to, address token, uint256 amount) external nonReentrant {
        bool isETH;
        if (token == eth) {
            token = weth;
            isETH = true;
        }
        uint256 balance = tokenBalances[0][token];
        if (amount == 0) {
            amount = uint128(balance);
        }
        if (uint128(balance) < amount) {
            revert ICrystal.ActionFailed();
        } else {
            tokenBalances[0][token] = balance - amount;
        }
        if (isETH) {
            IWETH(weth).withdraw(amount);
            (bool success, ) = to.call{value: amount}("");
            if (!success) {
                revert ICrystal.TransferFailed(to);
            }
        } else {
            IERC20(token).transfer(to, amount);
        }
    }

    /**
     * @notice Swaps an exact amount of ETH for as many tokens as possible
     *
     * @param amountOutMin Minimum tokens you're willing to accept (slippage protection)
     * @param path The trading route (e.g., [ETH, USDC, DAI] to swap ETH → USDC → DAI)
     * @param to Who receives the tokens
     * @param deadline When this transaction expires
     * @param referrer Optional address that gets a referral commission
     *
     * @return amounts How much was swapped at each step of the route
     */
    function swapExactETHForTokens(uint256 amountOutMin, address[] memory path, address to, uint256 deadline, address referrer) external payable nonReentrant returns (uint256[] memory amounts) {
        if (path.length < 2 || path[0] != eth || path[path.length - 1] == eth) {
            revert ICrystal.InvalidPath(path);
        }
        if (deadline < block.timestamp) {
            revert ICrystal.Expired(deadline);
        }
        IWETH(weth).deposit{value: msg.value}();
        tokenBalances[0][weth] += msg.value;
        amounts = exactInputSwap(msg.value, path, to, referrer);
        if (amountOutMin > amounts[amounts.length - 1]) {
            revert ICrystal.SlippageExceeded();
        }
        if (to != msg.sender) {
            uint256 amount = amounts[amounts.length - 1];
            address token = path[path.length - 1];
            uint256 balance = tokenBalances[0][token];
            if (uint128(balance) < amount) {
                revert ICrystal.ActionFailed();
            } else {
                tokenBalances[0][token] = balance - amount;
            }
            IERC20(token).transfer(to, amount);
        }
    }

    /**
     * @notice Swaps an exact amount of tokens for as much ETH as possible
     *
     * @param amountIn How many tokens you're swapping
     * @param amountOutMin Minimum ETH you're willing to accept (slippage protection)
     * @param path The trading route (must end with ETH)
     * @param to Who receives the ETH
     * @param deadline When this transaction expires
     * @param referrer Optional address that gets a referral commission
     *
     * @return amounts How much was swapped at each step of the route
     */
    function swapExactTokensForETH(uint256 amountIn, uint256 amountOutMin, address[] memory path, address to, uint256 deadline, address referrer) external nonReentrant returns (uint256[] memory amounts) {
        if (deadline < block.timestamp) {
            revert ICrystal.Expired(deadline);
        }
        if (path.length < 2 || path[0] == eth || path[path.length - 1] != eth) {
            revert ICrystal.InvalidPath(path);
        }
        amounts = exactInputSwap(amountIn, path, to, referrer);
        if (amountOutMin > amounts[amounts.length - 1]) {
            revert ICrystal.SlippageExceeded();
        }
        uint256 balance = tokenBalances[0][weth];
        uint256 amount = amounts[amounts.length - 1];
        if (uint128(balance) < amount) {
            revert ICrystal.ActionFailed();
        } else {
            tokenBalances[0][weth] = balance - amount;
        }
        IWETH(weth).withdraw(amount);
        (bool success, ) = to.call{value: amount}("");
        if (!success) {
            revert ICrystal.TransferFailed(to);
        }
    }

    /**
     * @notice Swaps an exact amount of one token for as much of another token as possible
     *
     * @param amountIn How many tokens you're swapping
     * @param amountOutMin Minimum output tokens you're willing to accept (slippage protection)
     * @param path The trading route (can't end with ETH, use swapExactTokensForETH for that)
     * @param to Who receives the output tokens
     * @param deadline When this transaction expires
     * @param referrer Optional address that gets a referral commission
     *
     * @return amounts How much was swapped at each step of the route
     */
    function swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, address[] memory path, address to, uint256 deadline, address referrer) external nonReentrant returns (uint256[] memory amounts) {
        if (deadline < block.timestamp) {
            revert ICrystal.Expired(deadline);
        }
        if (path.length < 2 || path[0] == eth || path[path.length - 1] == eth) {
            revert ICrystal.InvalidPath(path);
        }
        amounts = exactInputSwap(amountIn, path, to, referrer);
        if (amountOutMin > amounts[amounts.length - 1]) {
            revert ICrystal.SlippageExceeded();
        }
        if (to != msg.sender) {
            uint256 amount = amounts[amounts.length - 1];
            address token = path[path.length - 1];
            uint256 balance = tokenBalances[0][token];
            if (uint128(balance) < amount) {
                revert ICrystal.ActionFailed();
            } else {
                tokenBalances[0][token] = balance - amount;
            }
            IERC20(token).transfer(to, amount);
        }
    }

    /**
     * @notice Swaps the minimum amount of ETH needed to get exactly the tokens you want
     *
     * @param amountOut Exactly how many tokens you want to receive
     * @param path The trading route (must start with ETH)
     * @param to Who receives the tokens
     * @param deadline When this transaction expires
     * @param referrer Optional address that gets a referral commission
     *
     * @return amounts How much was swapped at each step (any leftover ETH is refunded)
     */
    function swapETHForExactTokens(uint256 amountOut, address[] memory path, address to, uint256 deadline, address referrer) external payable nonReentrant returns (uint256[] memory amounts) {
        if (deadline < block.timestamp) {
            revert ICrystal.Expired(deadline);
        }
        if (path[0] != eth || path[path.length - 1] == eth) {
            revert ICrystal.InvalidPath(path);
        }
        amounts = getAmountsIn(amountOut, path);
        if (amounts[0] > msg.value) {
            revert ICrystal.SlippageExceeded();
        }
        IWETH(weth).deposit{value: msg.value}();
        tokenBalances[0][weth] += msg.value;
        exactOutputSwap(amounts, path, to, referrer);
        if (to != msg.sender) {
            address token = path[path.length - 1];
            uint256 balance = tokenBalances[0][token];
            if (uint128(balance) < amountOut) {
                revert ICrystal.ActionFailed();
            } else {
                tokenBalances[0][token] = balance - amountOut;
            }
            IERC20(token).transfer(to, amountOut);
        }
        if (msg.value > amounts[0]) {
            uint256 amount = msg.value - amounts[0];
            uint256 balance = tokenBalances[0][weth];
            if (uint128(balance) < amount) {
                revert ICrystal.ActionFailed();
            } else {
                tokenBalances[0][weth] = balance - amount;
            }
            IWETH(weth).withdraw(amount);
            (bool success, ) = msg.sender.call{value: amount}("");
            if (!success) {
                revert ICrystal.TransferFailed(msg.sender);
            }
        }
    }

    /**
     * @notice Swaps up to a maximum amount of tokens to get exactly the ETH you want
     *
     * @param amountOut Exactly how much ETH you want to receive
     * @param amountInMax Maximum tokens you're willing to spend (slippage protection)
     * @param path The trading route (must end with ETH)
     * @param to Who receives the ETH
     * @param deadline When this transaction expires
     * @param referrer Optional address that gets a referral commission
     *
     * @return amounts How much was swapped at each step
     */
    function swapTokensForExactETH(uint256 amountOut, uint256 amountInMax, address[] memory path, address to, uint256 deadline, address referrer) external nonReentrant returns (uint256[] memory amounts) {
        if (deadline < block.timestamp) {
            revert ICrystal.Expired(deadline);
        }
        if (path[0] == eth || path[path.length - 1] != eth) {
            revert ICrystal.InvalidPath(path);
        }
        amounts = getAmountsIn(amountOut, path);
        if (amounts[0] > amountInMax) revert ICrystal.SlippageExceeded();
        exactOutputSwap(amounts, path, to, referrer);
        if (amounts[0] > amountInMax) revert ICrystal.SlippageExceeded();
        uint256 balance = tokenBalances[0][weth];
        if (uint128(balance) < amountOut) {
            revert ICrystal.ActionFailed();
        } else {
            tokenBalances[0][weth] = balance - amountOut;
        }
        IWETH(weth).withdraw(amountOut);
        (bool success, ) = to.call{value: amountOut}("");
        if (!success) {
            revert ICrystal.TransferFailed(to);
        }
    }

    /**
     * @notice Swaps up to a maximum amount of one token to get exactly the amount of another token you want
     *
     * @param amountOut Exactly how many output tokens you want
     * @param amountInMax Maximum input tokens you're willing to spend (slippage protection)
     * @param path The trading route (can't end with ETH, use swapTokensForExactETH for that)
     * @param to Who receives the output tokens
     * @param deadline When this transaction expires
     * @param referrer Optional address that gets a referral commission
     *
     * @return amounts How much was swapped at each step
     */
    function swapTokensForExactTokens(uint256 amountOut, uint256 amountInMax, address[] memory path, address to, uint256 deadline, address referrer) external nonReentrant returns (uint256[] memory amounts) {
        if (deadline < block.timestamp) {
            revert ICrystal.Expired(deadline);
        }
        if (path[0] == eth || path[path.length - 1] == eth) {
            revert ICrystal.InvalidPath(path);
        }
        amounts = getAmountsIn(amountOut, path);
        if (amounts[0] > amountInMax) revert ICrystal.SlippageExceeded();
        exactOutputSwap(amounts, path, to, referrer);
        if (amounts[0] > amountInMax) revert ICrystal.SlippageExceeded();
        if (to != msg.sender) {
            address token = path[path.length - 1];
            uint256 balance = tokenBalances[0][token];
            if (uint128(balance) < amountOut) {
                revert ICrystal.ActionFailed();
            } else {
                tokenBalances[0][token] = balance - amountOut;
            }
            IERC20(token).transfer(to, amountOut);
        }
    }

    /**
     * @notice Executes a swap directly through a specific market (advanced function for direct market access)
     *
     * @param isExactInput True if `size` is input amount, false if output.
     * @param tokenIn Input token.
     * @param tokenOut Output token.
     * @param orderType Execution type.
     * @param size Input or output amount depending on `isExactInput`.
     * @param worstPrice Inclusive worst price limit.
     * @param deadline Expiration timestamp.
     * @param referrer Optional referrer for fee sharing.
     *
     * @return amountIn Total input amount including fees.
     * @return amountOut Total output amount after fees.
     * @return id New order id if a fallback limit order was placed.
     */
    function swap(bool isExactInput, address tokenIn, address tokenOut, uint256 orderType, uint256 size, uint256 worstPrice, uint256 deadline, address referrer) external payable nonReentrant returns (uint256 amountIn, uint256 amountOut, uint256 id) {
        if (deadline < block.timestamp) {
            revert ICrystal.Expired(deadline);
        }
        address market = getMarketByTokens[tokenIn == eth ? weth : tokenIn][tokenOut == eth ? weth : tokenOut];
        if (market == address(0) || market == placeholder) {
            revert ICrystal.InvalidMarket(tokenIn == eth ? weth : tokenIn, tokenOut == eth ? weth : tokenOut);
        }
        if (tokenIn == eth) {
            IWETH(weth).deposit{value: msg.value}();
            tokenBalances[0][weth] += msg.value;
        }
        bool result = _getMarket[market].quoteAsset == (tokenIn == eth ? weth : tokenIn);
        deadline = ((tokenIn == eth) ? (1 << 64) : 0) | ((tokenOut == eth) ? (1 << 60) : 0);
        bytes memory ret = abi.encodeWithSelector(0xe690552b, result, isExactInput, deadline, orderType, size, worstPrice, referrer, msg.sender);
        (result, ret) = market.delegatecall(ret);
        if (!result) {
            revert ICrystal.ActionFailed();
        }
        if (tokenIn == eth || tokenOut == eth) {
            uint256 balance = tokenBalances[0][weth];
            if (balance != 0) {
                tokenBalances[0][weth] = 0;
                IWETH(weth).withdraw(balance);
                (bool success, ) = msg.sender.call{value: balance}("");
                if (!success) {
                    revert ICrystal.TransferFailed(msg.sender);
                }
            }
        }
        (amountIn, amountOut, id) = abi.decode(ret, (uint256, uint256, uint256));
    }

    /**
     * @notice Places a limit order via the router.
     *
     * @param tokenIn Input token.
     * @param tokenOut Output token.
     * @param price Limit price.
     * @param size Order size.
     * @param deadline Expiration timestamp.
     *
     * @return id Assigned order identifier.
     */
    function placeLimitOrder(address tokenIn, address tokenOut, uint256 price, uint256 size, uint256 deadline) external payable nonReentrant returns (uint256 id) {
        if (deadline < block.timestamp) {
            revert ICrystal.Expired(deadline);
        }
        bool isETHIn = tokenIn == eth;
        address asset0 = isETHIn ? weth : tokenIn;
        address asset1 = tokenOut == eth ? weth : tokenOut;
        address market = getMarketByTokens[asset0][asset1];
        if (market == address(0) || market == placeholder) {
            revert ICrystal.InvalidMarket(asset0, asset1);
        }
        if (isETHIn) {
            require(msg.value == size);
            IWETH(weth).deposit{value: msg.value}();
            tokenBalances[0][weth] += msg.value;
        }
        uint256 options = (isETHIn ? (1 << 56) : 0);
        (bool result, bytes memory ret) = market.delegatecall(abi.encodeWithSelector(0x218a0c31, _getMarket[market].quoteAsset == asset0, options, price, size, msg.sender));
        if (!result) {
            revert ICrystal.ActionFailed();
        }
        id = abi.decode(ret, (uint256));
    }

    /**
     * @notice Cancels a limit order via the router.
     *
     * @param tokenIn Input token.
     * @param tokenOut Output token.
     * @param price Order price (0 when cancelling by cloid).
     * @param id Order id or cloid.
     * @param deadline Expiration timestamp.
     *
     * @return size Amount released.
     */
    function cancelLimitOrder(address tokenIn, address tokenOut, uint256 price, uint256 id, uint256 deadline) external nonReentrant returns (uint256 size) {
        if (deadline < block.timestamp) {
            revert ICrystal.Expired(deadline);
        }
        bool isETHIn = tokenIn == eth;
        address asset0 = isETHIn ? weth : tokenIn;
        address asset1 = tokenOut == eth ? weth : tokenOut;
        address market = getMarketByTokens[asset0][asset1];
        if (market == address(0) || market == placeholder) {
            revert ICrystal.InvalidMarket(asset0, asset1);
        }
        uint256 options = (isETHIn ? (1 << 44) : 0);
        (bool result, bytes memory ret) = market.delegatecall(abi.encodeWithSelector(0xb69d86f7, options, price, id, msg.sender));
        if (!result) {
            revert ICrystal.ActionFailed();
        }
        size = abi.decode(ret, (uint256));
        if (size == 0) {
            revert ICrystal.ActionFailed();
        }
        if (isETHIn) {
            uint256 balance = tokenBalances[0][weth];
            if (uint128(balance) < size) {
                revert ICrystal.ActionFailed();
            } else {
                tokenBalances[0][weth] = balance - size;
            }
            IWETH(weth).withdraw(size);
            (bool success, ) = msg.sender.call{value: size}("");
            if (!success) {
                revert ICrystal.TransferFailed(msg.sender);
            }
        }
    }

    /**
     * @notice Replaces or decreases an existing limit order via the router.
     *
     * @param isPostOnly Whether to post-only the replacement.
     * @param isDecrease Whether to decrease size.
     * @param tokenIn Input token.
     * @param tokenOut Output token.
     * @param price Existing order price.
     * @param id Existing order id.
     * @param newPrice New price.
     * @param newSize New size (0 to reuse previous size).
     * @param deadline Expiration timestamp.
     * @param referrer Optional referrer for fee sharing.
     *
     * @return Replacement order id.
     */
    function replaceOrder(bool isPostOnly, bool isDecrease, address tokenIn, address tokenOut, uint256 price, uint256 id, uint256 newPrice, uint256 newSize, uint256 deadline, address referrer) external payable nonReentrant returns (uint256) {
        if (deadline < block.timestamp) {
            revert ICrystal.Expired(deadline);
        }
        address market = getMarketByTokens[tokenIn == eth ? weth : tokenIn][tokenOut == eth ? weth : tokenOut];
        if (market == address(0) || market == placeholder) {
            revert ICrystal.InvalidMarket(tokenIn == eth ? weth : tokenIn, tokenOut == eth ? weth : tokenOut);
        }
        if (tokenIn == eth) {
            IWETH(weth).deposit{value: msg.value}();
            tokenBalances[0][weth] += msg.value;
        }
        deadline = ((tokenIn == eth) ? (1 << 56) : 0) | ((tokenOut == eth) ? (1 << 52) : 0) | (isDecrease ? (1 << 48) : 0) | (isPostOnly ? 0 : (1 << 44));
        (bool result, bytes memory ret) = market.delegatecall(abi.encodeWithSelector(0x6c8dce79, deadline, price, id, newPrice, newSize, referrer, msg.sender));
        if (!result) {
            revert ICrystal.ActionFailed();
        }
        id = abi.decode(ret, (uint256));
        if (tokenIn == eth || tokenOut == eth) {
            uint256 balance = tokenBalances[0][weth] & MASK_KEEP_0_128;
            if (balance != 0) {
                tokenBalances[0][weth] = 0;
                IWETH(weth).withdraw(balance);
                (bool success, ) = msg.sender.call{value: balance}("");
                if (!success) {
                    revert ICrystal.TransferFailed(msg.sender);
                }
            }
        }
        return id;
    }

    /**
     * @notice Executes multiple batch order payloads across markets.
     *
     * @param batches Array of batch requests.
     * @param deadline Expiration timestamp.
     * @param referrer Optional referrer for fee sharing.
     */
    function multiBatchOrders(ICrystal.Batch[] calldata batches, uint256 deadline, address referrer) external payable nonReentrant {
        if (deadline < block.timestamp) {
            revert ICrystal.Expired(deadline);
        }
        if (msg.value != 0) {
            IWETH(weth).deposit{value: msg.value}();
            tokenBalances[0][weth] += msg.value;
        }
        for (uint256 i; i < batches.length; ++i) {
            address market = batches[i].market;
            _verifyMarket(market);
            (bool result, bytes memory ret) = market.delegatecall(abi.encodeWithSelector(0x5c2a91ec, batches[i].actions, batches[i].options, referrer, msg.sender));
            assembly {
                switch result
                case 0 {
                    revert(add(ret, 32), mload(ret))
                }
            }
        }
        uint256 balance = tokenBalances[0][weth] & MASK_KEEP_0_128;
        if (balance != 0) {
            tokenBalances[0][weth] = 0;
            IWETH(weth).withdraw(balance);
            (bool success, ) = msg.sender.call{value: balance}("");
            if (!success) {
                revert ICrystal.TransferFailed(msg.sender);
            }
        }
    }

    /**
     * @notice Returns virtual reserves for a launchpad token.
     *
     * @param token Launchpad token address.
     *
     * @return virtualNativeReserve Virtual native reserve.
     * @return virtualTokenReserve Virtual token reserve.
     */
    function getVirtualReserves(address token) external view returns (uint256 virtualNativeReserve, uint256 virtualTokenReserve) {
        ICrystal.LaunchpadMarket storage market = launchpadTokenToMarket[token];
        (virtualNativeReserve, virtualTokenReserve) = (market.virtualNativeReserve, market.virtualTokenReserve);
    }

    /**
     * @notice Creates a new launchpad token and associated market.
     *
     * @param name Token name.
     * @param symbol Token symbol.
     * @param metadataCID Metadata CID.
     * @param description Token description.
     * @param social1 Social link 1.
     * @param social2 Social link 2.
     * @param social3 Social link 3.
     * @param social4 Social link 4.
     *
     * @return token Address of the created token.
     */
    function createToken(string memory name, string memory symbol, string memory metadataCID, string memory description, string memory social1, string memory social2, string memory social3, string memory social4) external payable nonReentrant returns (address token) {
        token = address(new CrystalToken(address(this), name, symbol, metadataCID, description, social1, social2, social3, social4));
        allTokens.push(address(token));
        emit ICrystal.TokenCreated(address(token), msg.sender, name, symbol, metadataCID, description, social1, social2, social3, social4);
        uint256 marketId = allMarkets.length + 1;
        require(marketId < MASK_KEEP_0_48);
        parameters = ICrystal.Parameters(weth, token, marketId, 3, 9, 1, GRADUATED_MAX_PRICE);
        uint256 maxTick;
        address market;
        market = address(new CrystalMarket{salt: keccak256(abi.encode(marketId))}()); // Market is disabled until market is initialized
        maxTick = CM._priceToTick(GRADUATED_MAX_PRICE, 1);
        delete parameters;
        ICrystal.Market storage m = _getMarket[market];
        (m.quoteAsset, m.baseAsset, m.marketId, m.scaleFactor, m.tickSize) = (weth, token, marketId, 9, 1);
        (m.maxPrice, m.marketType, m.creator, m.creatorFeeSplit, m.isAMMEnabled) = (GRADUATED_MAX_PRICE, 3, msg.sender, uint8(launchpadParams.graduatedCreatorFeeSplit), true);
        (uint256 key, uint256 offset) = CS._getActivated((marketId << 128), 0); // Preset index 0 and maxPrice of activated bitmap
        CS._writeMapping(key, offset, CS.PRICELEVELS_KEY, 1);
        (key, offset) = CS._getGroups((marketId << 128), 0);
        CS._writeMapping(key, offset, CS.GROUPS_KEY, 1);
        (key, offset) = CS._getActivated((marketId << 128), maxTick / 255);
        CS._writeMapping(key, offset, CS.PRICELEVELS_KEY, (1 << (maxTick % 255)) | ((maxTick / 255) == 0 ? 1 : 0));
        (key, offset) = CS._getGroups((marketId << 128), (maxTick / 255) / 255);
        CS._writeMapping(key, offset, CS.GROUPS_KEY, (1 << ((maxTick / 255) % 255)) | ((maxTick / 255) == 0 ? 1 : 0));
        allMarkets.push(market);
        marketIdToMarket[marketId] = market;
        getMarketByTokens[weth][token] = placeholder;
        getMarketByTokens[token][weth] = placeholder;
        launchpadTokenToMarket[address(token)] = ICrystal.LaunchpadMarket(launchpadParams.launchpadInitialNativeSupply, uint112(INITIAL_TOKEN_SUPPLY), uint256(launchpadParams.launchpadInitialNativeSupply) * INITIAL_TOKEN_SUPPLY, msg.sender, market, uint88(block.timestamp));
        (bool result, bytes memory ret) = market.delegatecall(
            abi.encodeWithSelector(0xf7bb5c88, address(this), (INITIAL_TOKEN_SUPPLY * uint256(launchpadParams.launchpadInitialNativeSupply) / GRADUATED_TOKEN_SUPPLY) - uint256(launchpadParams.launchpadInitialNativeSupply), GRADUATED_TOKEN_SUPPLY) // Pre-mint initial AMM liquidity
        );
        if (!result) {
            revert ICrystal.ActionFailed();
        }
        uint256 liquidity = abi.decode(ret, (uint256));
        IERC20(market).transfer(address(0), liquidity);
        if (msg.value != 0) {
            _buy(true, token, msg.value, 0);
        }
    }

    /**
     * @notice Buys launchpad tokens against the virtual AMM.
     *
     * @param isExactInput True if `amountIn` is exact, false if `amountOut` is exact.
     * @param token Token to buy.
     * @param amountIn Input amount when exact input.
     * @param amountOut Desired output when exact output.
     *
     * @return inputAmount Actual input used.
     * @return outputAmount Actual output received.
     * @return isLaunchpadClosed Whether the launchpad has graduated.
     */
    function buy(bool isExactInput, address token, uint256 amountIn, uint256 amountOut) external payable nonReentrant returns (uint256, uint256, bool) {
        return _buy(isExactInput, token, amountIn, amountOut);
    }

    /**
     * @notice Sells launchpad tokens for native asset or via AMM if graduated.
     *
     * @param isExactInput True if `amountIn` is exact, false if `amountOut` is exact.
     * @param token Launchpad token to sell.
     * @param amountIn Input amount when exact input.
     * @param amountOut Desired output when exact output.
     *
     * @return inputAmount Actual input used.
     * @return outputAmount Actual output received.
     */
    function sell(bool isExactInput, address token, uint256 amountIn, uint256 amountOut) external nonReentrant returns (uint256, uint256) {
        ICrystal.LaunchpadMarket storage launchpadMarket = launchpadTokenToMarket[token];
        uint256 inputAmount;
        uint256 outputAmount;
        if (launchpadMarket.virtualTokenReserve != 0) {
            if (isExactInput) {
                inputAmount = amountIn;
                CrystalToken(token).transferFrom(msg.sender, address(this), amountIn);
                launchpadMarket.virtualTokenReserve += uint112(amountIn);
                uint256 oldNativeReserve = launchpadMarket.virtualNativeReserve;
                launchpadMarket.virtualNativeReserve = uint112((launchpadMarket.k + launchpadMarket.virtualTokenReserve - 1) / launchpadMarket.virtualTokenReserve);
                outputAmount = oldNativeReserve - launchpadMarket.virtualNativeReserve;
                uint256 amountAfterFee = (outputAmount * launchpadParams.launchpadFee) / 100000;
                uint256 collectedFee = outputAmount - amountAfterFee;
                uint256 creatorFee = (collectedFee * launchpadParams.launchpadCreatorFeeSplit) / 100;
                claimableRewards[weth][launchpadMarket.creator] += creatorFee;
                claimableRewards[weth][gov] += (collectedFee - creatorFee);
                outputAmount = amountAfterFee;
                IWETH(weth).withdraw(outputAmount);
                (bool success, ) = msg.sender.call{value: outputAmount}("");
                if (!success) {
                    revert ICrystal.TransferFailed(msg.sender);
                }
            } else {
                uint256 outputAmountWithFee = (amountOut * 100000 + launchpadParams.launchpadFee - 1) / launchpadParams.launchpadFee;
                uint256 newNative = launchpadMarket.virtualNativeReserve - outputAmountWithFee;
                uint256 newToken = (launchpadMarket.k + newNative - 1) / newNative;
                inputAmount = newToken - launchpadMarket.virtualTokenReserve;
                IERC20(token).transferFrom(msg.sender, address(this), inputAmount);
                launchpadMarket.virtualNativeReserve = uint112(newNative);
                launchpadMarket.virtualTokenReserve = uint112(newToken);
                uint256 collectedFee = outputAmountWithFee - amountOut;
                uint256 creatorFee = (collectedFee * launchpadParams.launchpadCreatorFeeSplit) / 100;
                claimableRewards[weth][launchpadMarket.creator] += creatorFee;
                claimableRewards[weth][gov] += (collectedFee - creatorFee);
                outputAmount = amountOut;
                IWETH(weth).withdraw(amountOut);
                (bool success, ) = msg.sender.call{value: amountOut}("");
                if (!success) {
                    revert ICrystal.TransferFailed(msg.sender);
                }
            }
            if (inputAmount != 0 && outputAmount != 0) {
                emit ICrystal.LaunchpadTrade(token, msg.sender, false, inputAmount, outputAmount, launchpadMarket.virtualNativeReserve, launchpadMarket.virtualTokenReserve);
            }
        } else {
            uint256 newInputAmount = isExactInput ? amountIn : amountOut;
            bytes memory ret = abi.encodeWithSelector(0xe690552b, false, isExactInput, (1 << 60), 1, newInputAmount, 1, address(0), msg.sender);
            bool result;
            address market = getMarketByTokens[weth][token];
            if (market == address(0) || market == placeholder) {
                revert ICrystal.InvalidMarket(weth, token);
            }
            (result, ret) = market.delegatecall(ret);
            if (!result) {
                revert ICrystal.ActionFailed();
            }
            uint256 balance = tokenBalances[0][weth] & MASK_KEEP_0_128;
            if (balance != 0) {
                tokenBalances[0][weth] = 0;
                IWETH(weth).withdraw(balance);
                (bool success, ) = msg.sender.call{value: balance}("");
                if (!success) {
                    revert ICrystal.TransferFailed(msg.sender);
                }
            }
            (inputAmount, outputAmount, ) = abi.decode(ret, (uint256, uint256, uint256)); // Avoid stack too deep
        }
        isExactInput ? require(outputAmount >= amountOut) : require(amountIn != 0 ? inputAmount <= amountIn : true);
        return (inputAmount, outputAmount);
    }

    /**
     * @notice Quotes a launchpad token buy without state changes.
     *
     * @param isExactInput True if `amountIn` is exact, false if `amountOut` is exact.
     * @param token Launchpad token to buy.
     * @param amountIn Input amount when exact input.
     * @param amountOut Desired output when exact output.
     *
     * @return inputAmount Estimated input required.
     * @return outputAmount Estimated output received.
     * @return graduated Whether the launchpad would graduate during this quote.
     */
    function quoteBuy(bool isExactInput, address token, uint256 amountIn, uint256 amountOut) external returns (uint256, uint256, bool) {
        ICrystal.LaunchpadMarket storage launchpadMarket = launchpadTokenToMarket[token];
        uint256 inputAmount;
        uint256 outputAmount;
        bool graduated;
        address graduatedMarket;
        if (launchpadMarket.virtualTokenReserve != 0) {
            uint256 virtualNativeReserve;
            uint256 virtualTokenReserve;
            if (isExactInput) {
                inputAmount = amountIn;
                if (launchpadMarket.virtualNativeReserve + ((inputAmount * launchpadParams.launchpadFee) / 100000) > (launchpadMarket.k / GRADUATED_TOKEN_SUPPLY)) {
                    inputAmount = ((((launchpadMarket.k + GRADUATED_TOKEN_SUPPLY - 1) / GRADUATED_TOKEN_SUPPLY) - launchpadMarket.virtualNativeReserve) * 100000 + launchpadParams.launchpadFee - 1) / launchpadParams.launchpadFee;
                }
                uint256 amountAfterFee = (inputAmount * launchpadParams.launchpadFee) / 100000;
                virtualNativeReserve = launchpadMarket.virtualNativeReserve + uint112(amountAfterFee);
                uint256 oldTokenReserve = launchpadMarket.virtualTokenReserve;
                virtualTokenReserve = uint112((launchpadMarket.k + virtualNativeReserve - 1) / virtualNativeReserve);
                outputAmount = oldTokenReserve - virtualTokenReserve;
            } else {
                uint256 newToken = launchpadMarket.virtualTokenReserve - amountOut;
                uint256 newNative = (uint256(launchpadMarket.k) + newToken - 1) / newToken;
                uint256 preFeeIn = newNative - launchpadMarket.virtualNativeReserve;
                if (launchpadMarket.virtualNativeReserve + preFeeIn > (launchpadMarket.k / GRADUATED_TOKEN_SUPPLY)) {
                    preFeeIn = ((launchpadMarket.k + GRADUATED_TOKEN_SUPPLY - 1) / GRADUATED_TOKEN_SUPPLY) - launchpadMarket.virtualNativeReserve;
                    inputAmount = (preFeeIn * 100000 + launchpadParams.launchpadFee - 1) / launchpadParams.launchpadFee;
                    virtualNativeReserve = uint112(launchpadMarket.k / GRADUATED_TOKEN_SUPPLY);
                    uint256 oldTokenReserve = launchpadMarket.virtualTokenReserve;
                    virtualTokenReserve = uint112((launchpadMarket.k + virtualNativeReserve - 1) / virtualNativeReserve);
                    outputAmount = oldTokenReserve - virtualTokenReserve;
                } else {
                    inputAmount = (preFeeIn * 100000 + launchpadParams.launchpadFee - 1) / launchpadParams.launchpadFee;
                    virtualNativeReserve = uint112(newNative);
                    outputAmount = amountOut;
                }
            }
            if (virtualNativeReserve >= ((launchpadMarket.k / GRADUATED_TOKEN_SUPPLY))) { // Graduate token from bonding curve to orderbook
                graduatedMarket = launchpadMarket.market;
                ICrystal.Market storage m = _getMarket[graduatedMarket];
                (m.lowestAsk, m.minSize, m.takerFee, m.makerRebate, m.createTimestamp) = (uint80(GRADUATED_MAX_PRICE), uint40(0), uint24(launchpadParams.graduatedTakerFee), uint24(launchpadParams.graduatedMakerRebate), uint88(0)); // init market
                graduated = true;
            }
        }
        if (isExactInput ? inputAmount < amountIn : outputAmount < amountOut) { // Token is graduated, swap through orderbook
            uint256 newInputAmount = isExactInput ? (amountIn - inputAmount) : (amountOut - outputAmount);
            bytes memory ret = abi.encodeWithSelector(0x638571e3, true, isExactInput, true, newInputAmount, MASK_KEEP_0_80);
            bool result;
            graduatedMarket = graduatedMarket != address(0) ? graduatedMarket : getMarketByTokens[weth][token];
            if (graduatedMarket == address(0) || graduatedMarket == placeholder) {
                revert ICrystal.InvalidMarket(weth, token);
            }
            (result, ret) = graduatedMarket.delegatecall(ret);
            if (!result) {
                revert ICrystal.ActionFailed();
            }
            uint256 newOutputAmount;
            (newInputAmount, newOutputAmount) = abi.decode(ret, (uint256, uint256)); // Avoid stack too deep
            inputAmount += newInputAmount;
            outputAmount += newOutputAmount;
        }
        isExactInput ? require(outputAmount >= amountOut) : require(amountIn != 0 ? inputAmount <= amountIn : true);
        if (graduated) {
            ICrystal.Market storage m = _getMarket[graduatedMarket];
            (m.lowestAsk, m.minSize, m.takerFee, m.makerRebate, m.createTimestamp) = (uint80(0), uint40(0), uint24(0), uint24(0), uint88(0)); // If simulation graduates the market, un-graduate it
        }
        return (inputAmount, outputAmount, graduated);
    }

    /**
     * @notice Quotes a launchpad token sell without state changes.
     *
     * @param isExactInput True if `amountIn` is exact, false if `amountOut` is exact.
     * @param token Launchpad token to sell.
     * @param amountIn Input amount when exact input.
     * @param amountOut Desired output when exact output.
     *
     * @return inputAmount Estimated input required.
     * @return outputAmount Estimated output received.
     */
    function quoteSell(bool isExactInput, address token, uint256 amountIn, uint256 amountOut) external returns (uint256, uint256) {
        ICrystal.LaunchpadMarket storage launchpadMarket = launchpadTokenToMarket[token];
        uint256 inputAmount;
        uint256 outputAmount;
        if (launchpadMarket.virtualTokenReserve != 0) {
            uint256 virtualNativeReserve;
            uint256 virtualTokenReserve;
            if (isExactInput) {
                inputAmount = amountIn;
                virtualTokenReserve = launchpadMarket.virtualTokenReserve + uint112(amountIn);
                uint256 oldNativeReserve = launchpadMarket.virtualNativeReserve;
                virtualNativeReserve = uint112((launchpadMarket.k + virtualTokenReserve - 1) / virtualTokenReserve);
                outputAmount = oldNativeReserve - virtualNativeReserve;
                uint256 amountAfterFee = (outputAmount * launchpadParams.launchpadFee) / 100000;
                outputAmount = amountAfterFee;
            } else {
                uint256 outputAmountWithFee = (amountOut * 100000 + launchpadParams.launchpadFee - 1) / launchpadParams.launchpadFee;
                uint256 newNative = launchpadMarket.virtualNativeReserve - outputAmountWithFee;
                uint256 newToken = (launchpadMarket.k + newNative - 1) / newNative;
                inputAmount = newToken - launchpadMarket.virtualTokenReserve;
                outputAmount = amountOut;
            }
        } else {
            uint256 newInputAmount = isExactInput ? amountIn : amountOut;
            bytes memory ret = abi.encodeWithSelector(0x638571e3, false, isExactInput, true, newInputAmount, 1);
            bool result;
            address market = getMarketByTokens[weth][token];
            if (market == address(0) || market == placeholder) {
                revert ICrystal.InvalidMarket(weth, token);
            }
            (result, ret) = market.delegatecall(ret);
            if (!result) {
                revert ICrystal.ActionFailed();
            }
            (inputAmount, outputAmount) = abi.decode(ret, (uint256, uint256)); // Avoid stack too deep
        }
        isExactInput ? require(outputAmount >= amountOut) : require(amountIn != 0 ? inputAmount <= amountIn : true);
        return (inputAmount, outputAmount);
    }

    /**
     * @notice Queues closure of an inactive launchpad or market.
     *
     * @param token Launchpad token address.
     */
    function queueCloseInactiveMarket(address token) external {
        address market = getMarketByTokens[weth][token];
        if (market == address(0) || market == placeholder) {
            ICrystal.LaunchpadMarket storage l = launchpadTokenToMarket[token];
            require(msg.sender == gov && l.createTimestamp != 0 && block.timestamp > (l.createTimestamp + (86400 * 365)));
            pendingClosedMarkets[token] = block.timestamp;
        } else {
            ICrystal.Market storage m = _getMarket[market];
            require(msg.sender == gov && m.createTimestamp != 0 && block.timestamp > (m.createTimestamp + (86400 * 365)));
            pendingClosedMarkets[market] = block.timestamp;
        }
    }

    /**
     * @notice Executes closure of a previously queued inactive market.
     *
     * @param token Launchpad token address.
     *
     * @return amountQuote Quote asset recovered to governance.
     * @return amountBase Base asset recovered to governance.
     */
    function executeCloseInactiveMarket(address token) external nonReentrant returns (uint256 amountQuote, uint256 amountBase) {
        address market = getMarketByTokens[weth][token];
        if (market == address(0) || market == placeholder) {
            ICrystal.LaunchpadMarket storage l = launchpadTokenToMarket[token];
            require(msg.sender == gov && l.createTimestamp != 0 && pendingClosedMarkets[token] != 0 && block.timestamp > (pendingClosedMarkets[token] + (86400 * 7)) && block.timestamp < (pendingClosedMarkets[token] + (86400 * 30)));
            IERC20(token).transfer(address(0), l.virtualTokenReserve);
            uint256 initialNativeReserve = l.k / INITIAL_TOKEN_SUPPLY;
            if (l.virtualNativeReserve > initialNativeReserve) {
                claimableRewards[weth][gov] += (l.virtualNativeReserve - initialNativeReserve);
            }
            delete launchpadTokenToMarket[token];
        } else {
            require(msg.sender == gov && pendingClosedMarkets[market] != 0 && block.timestamp > (pendingClosedMarkets[market] + (86400 * 7)) && block.timestamp < (pendingClosedMarkets[market] + (86400 * 30)));
            ICrystal.Market storage m = _getMarket[market];
            m.createTimestamp = 0;
            uint256 liquidity = IERC20(market).balanceOf(address(0));
            _getMarket[market].isAMMEnabled = false;
            IERC20(market).transferFrom(address(0), address(this), liquidity - 100000);
            assembly { // Manually unset reentry guard
                tstore(0x0, 0)
            }
            (amountQuote, amountBase) = ICrystal(address(this)).removeLiquidity(market, address(this), liquidity - 100000, 0, 0);
            claimableRewards[m.quoteAsset][gov] += amountQuote;
            claimableRewards[m.baseAsset][gov] += amountBase;
            _getMarket[market].isAMMEnabled = true;
        }
    }

    /**
     * @notice Locks zero-address liquidity for a market.
     *
     * @param market Market address.
     */
    function lockZeroAddressLiquidity(address market) external {
        require(msg.sender == gov);
        _getMarket[market].createTimestamp = 0;
    }
}