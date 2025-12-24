// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "../interfaces/IERC20.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {ICrystal} from "../interfaces/ICrystal.sol";
import {CrystalToken} from "./CrystalToken.sol";
import {CrystalMarket} from "./CrystalMarket.sol";

/**
 * @title Crystal
 * @author Crystal Labs
 *
 * @notice
 * All asset balances, markets, and trading functionality are accessible through a single central contract featuring swap endpoints across the orderbook, AMM, and launchpad.
 *
 * @dev
 * All asset balances, markets, and trading functionality are accessible through a single central contract featuring swap endpoints across the orderbook, AMM, and launchpad.
 */
contract Crystal is ICrystal {
    /// @notice Address receiving protocol fees.
    address public feeRecipient;

    /// @notice Referral commission percentage.
    uint8 public feeCommission;

    /// @notice Mapping from user id to address.
    mapping(uint256 => address) public userIdToAddress;

    /// @notice Mapping from address to user id.
    mapping(address => uint256) public addressToUserId;

    /// @notice Market configuration keyed by market address.
    mapping(address => ICrystal.Market) private _getMarket;

    /// @notice Activated price bitmaps for ticks.
    mapping(uint256 => uint256) private activated; // marketid << 128 | slotindex

    /// @notice Secondary activated bitmap for higher-level aggregation.
    mapping(uint256 => uint256) private activated2; // marketid << 128 | slotindex2

    /// @notice Aggregate liquidity per price level.
    mapping(uint256 => uint256) private priceLevels; // 0 is an invalid price marketid << 128 | price

    /// @notice Order storage keyed by market+price+id or user+cloid.
    mapping(uint256 => uint256) private orders; // 0 is an invalid cloid, valid range 1-1023 mask uint10; marketid << 128 | price << 48 | id or cloid << 41 | userid

    /// @notice Mapping to verify cloid market/price associations.
    mapping(uint256 => uint256) private cloidVerify; // two cloids per slot map market and price, never zero slot

    /// @notice Internal token balances for router and users.
    mapping(uint256 => mapping(address => uint256)) private tokenBalances;

    /// @notice Claimable fee balances per token and user.
    mapping(address => mapping(address => uint256)) public claimableRewards;

    /// @notice Governance address with admin privileges.
    address public gov;

    /// @notice Latest registered user id (0 reserved for router).
    uint256 public latestUserId; // first user id is 1 not 0, 0 is used internally by the router

    /// @notice Duration before expired fee claims can be processed.
    uint256 public feeClaimDuration;

    /// @notice Pending expired fee claims by user.
    mapping(address => ICrystal.PendingExpiredFeeClaim) public pendingExpiredFeeClaims;

    /// @notice Pending closed market ids by user.
    mapping(address => uint256) public pendingClosedMarkets;

    /// @notice Whether an address is authorized to deploy canonical markets.
    mapping(address => bool) public isCanonicalDeployer;

    /// @notice Approved forwarders per user.
    mapping(address => mapping(address => bool)) public approvedForwarder;

    /// @notice Mapping from market address to market id.
    mapping(address => uint256) public marketToMarketId; // uint48

    /// @notice Mapping from market id to market address.
    mapping(uint256 => address) public marketIdToMarket;

    /// @notice Market lookup by token pair (can be overridden).
    mapping(address => mapping(address => address)) public getMarketByTokens; // market from input and output token, can be overriden

    /// @notice List of all deployed markets.
    address[] public allMarkets;

    /// @notice Parameters scratch space used during deployment.
    ICrystal.Parameters public parameters;

    /// @notice Global launchpad parameters.
    ICrystal.LaunchpadParams public launchpadParams;

    /// @notice Mapping from launchpad token to market data.
    mapping(address => ICrystal.LaunchpadMarket) public launchpadTokenToMarket;

    /// @notice List of all launchpad tokens.
    address[] public allTokens;

    /// @notice WETH token address.
    address public immutable weth;

    /// @notice Sentinel address representing native ETH.
    address public constant eth = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice Placeholder address used during token/market creation.
    address private constant placeholder = 0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC;

    uint256 private constant MASK_OUT_113_154 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFC0000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 private constant MASK_OUT_0_128 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000000000000000000000000000;
    uint256 private constant MASK_KEEP_255_256 = 0x8000000000000000000000000000000000000000000000000000000000000000;
    uint256 private constant MASK_KEEP_80_160 = 0x000000000000000000000000FFFFFFFFFFFFFFFFFFFF00000000000000000000;
    uint256 private constant MASK_KEEP_0_20 = 0xFFFFF;
    uint256 private constant MASK_KEEP_0_41 = 0x1FFFFFFFFFF;
    uint256 private constant MASK_KEEP_0_48 = 0xFFFFFFFFFFFF;
    uint256 private constant MASK_KEEP_0_51 = 0x7FFFFFFFFFFFF;
    uint256 private constant MASK_KEEP_0_80 = 0xFFFFFFFFFFFFFFFFFFFF;
    uint256 private constant MASK_KEEP_0_112 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 private constant MASK_KEEP_0_128 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

    /**
     * @notice Initializes the Crystal core contract.
     *
     * @param _weth WETH token address.
     * @param _gov Governance address with admin privileges.
     * @param _feeRecipient Address receiving protocol fees.
     * @param _feeCommission Referral commission percentage.
     * @param _feeClaimDuration Duration before expired fee claims can be processed.
     * @param _launchpadParams Launchpad configuration parameters.
     */
    constructor(
        address _weth,
        address _gov,
        address _feeRecipient,
        uint8 _feeCommission,
        uint256 _feeClaimDuration,
        ICrystal.LaunchpadParams memory _launchpadParams
    ) {
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
        require(
            _feeCommission <= 50 &&
                minSize < MASK_KEEP_0_20 &&
                minSizeZeroes < MASK_KEEP_0_20 &&
                _launchpadParams.launchpadInitialNativeSupply > 1e18 &&
                90000 <= _launchpadParams.launchpadFee &&
                _launchpadParams.launchpadFee <= 100000 &&
                90000 <= _launchpadParams.graduatedTakerFee
        );
        require(
            _launchpadParams.graduatedTakerFee <= 100000 &&
                90000 <= _launchpadParams.graduatedMakerRebate &&
                _launchpadParams.graduatedMakerRebate <= 100000 &&
                _launchpadParams.graduatedCreatorFeeSplit <= 50 &&
                _launchpadParams.launchpadCreatorFeeSplit <= 50
        );
        launchpadParams = _launchpadParams;
    }

    /**
     * @notice Converts a price to its tick index given a tick size.
     *
     * @param p Price value.
     * @param tickSize Tick size for the market.
     *
     * @return Tick index for the given price.
     */
    function _priceToTick(
        uint256 p,
        uint256 tickSize
    ) internal pure returns (uint256) {
        unchecked {
            p /= tickSize;
            if (p <= 100_000) return p;
            else if (p < 1_000_000) {
                if (p % 10 != 0) revert();
                return 90_000 + p / 10;
            } else if (p < 10_000_000) {
                if (p % 100 != 0) revert();
                return 180_000 + p / 100;
            } else if (p < 100_000_000) {
                if (p % 1_000 != 0) revert();
                return 270_000 + p / 1_000;
            } else if (p < 1_000_000_000) {
                if (p % 10_000 != 0) revert();
                return 360_000 + p / 10_000;
            } else if (p < 10_000_000_000) {
                if (p % 100_000 != 0) revert();
                return 450_000 + p / 100_000;
            } else if (p < 100_000_000_000) {
                if (p % 1_000_000 != 0) revert();
                return 540_000 + p / 1_000_000;
            } else if (p < 1_000_000_000_000) {
                if (p % 10_000_000 != 0) revert();
                return 630_000 + p / 10_000_000;
            } else if (p < 10_000_000_000_000) {
                if (p % 100_000_000 != 0) revert();
                return 720_000 + p / 100_000_000;
            } else if (p < 100_000_000_000_000) {
                if (p % 1_000_000_000 != 0) revert();
                return 810_000 + p / 1_000_000_000;
            } else if (p <= 1_000_000_000_000_000) {
                if (p % 10_000_000_000 != 0) revert();
                return 900_000 + p / 10_000_000_000;
            }
            revert();
        }
    }

    /**
     * @notice Registers a user and assigns a user id.
     *
     * @dev Only default (non-margin) accounts are supported.
     *
     * @param acctType Account type flag (0 = default).
     * @param user Address to register.
     *
     * @return _latestUserId Assigned user id.
     */
    function _registerUser(
        uint256 acctType,
        address user
    ) internal returns (uint256 _latestUserId) {
        // 0 default 1 margin
        if (acctType == 0) {
            _latestUserId = latestUserId;
            require(
                addressToUserId[user] == 0 && _latestUserId < MASK_KEEP_0_41
            );
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
     * @notice Validates a market exists and sets a transient reentrancy guard.
     *
     * @param market Market address to verify.
     */
    function _verifyMarketAndLock(address market) internal {
        assembly {
            mstore(0x00, market)
            mstore(0x20, _getMarket.slot)
            if iszero(and(sload(keccak256(0x00, 0x40)), MASK_KEEP_80_160)) {
                revert(0, 0)
            }
            if tload(0x0) {
                revert(0, 0)
            }
            tstore(0x0, 1)
        }
    }

    /**
     * @notice Resolves and authorizes a user, defaulting to msg.sender.
     *
     * @param user Supplied user address (optional).
     *
     * @return Resolved user address after forwarder checks.
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
     * @notice Delegatecalls into a market with appended user data and transient lock.
     *
     * @param market Target market address.
     * @param selector Function selector to invoke.
     * @param size Calldata size excluding selector and user address.
     * @param user User address to append.
     *
     * @return Raw return data from the delegatecall.
     */
    function _delegateToMarket(
        address market,
        bytes4 selector,
        uint256 size,
        address user
    ) internal returns (bytes memory) {
        _verifyMarketAndLock(market);
        assembly {
            mstore(0x80, selector)
            calldatacopy(0x84, 36, size)
            mstore(add(size, 0x84), user)
            let result := delegatecall(
                gas(),
                market,
                0x80,
                add(4, add(size, mul(iszero(iszero(user)), 32))),
                0,
                0
            )
            returndatacopy(0x80, 0, returndatasize())
            switch result
            case 0 {
                revert(0x80, returndatasize())
            }
            default {
                tstore(0x0, 0)
                return(0x80, returndatasize())
            }
        }
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
    function getMarket(
        address market
    ) external view returns (ICrystal.MarketInfo memory info) {
        ICrystal.Market storage marketInfo = _getMarket[market];
        info = ICrystal.MarketInfo(
            marketInfo.quoteAsset,
            marketInfo.baseAsset,
            marketInfo.marketType,
            marketInfo.highestBid,
            marketInfo.lowestAsk,
            marketInfo.scaleFactor,
            marketInfo.tickSize,
            marketInfo.maxPrice,
            (marketInfo.minSize >> 20) *
                10 ** (marketInfo.minSize & MASK_KEEP_0_20),
            marketInfo.takerFee,
            marketInfo.makerRebate,
            marketInfo.reserveQuote,
            marketInfo.reserveBase,
            marketInfo.isAMMEnabled
        );
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
    function getDepositedBalance(
        address user,
        address asset
    )
        external
        view
        returns (
            uint256 totalBalance,
            uint256 availableBalance,
            uint256 lockedBalance
        )
    {
        uint256 tokenBalance = tokenBalances[addressToUserId[user]][asset];
        availableBalance = tokenBalance & MASK_KEEP_0_128;
        lockedBalance = tokenBalance >> 128;
        return (
            availableBalance + lockedBalance,
            availableBalance,
            lockedBalance
        );
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
    function getAllOrdersByCloid(
        address user,
        uint256 range
    )
        external
        view
        returns (uint256[] memory cloids, ICrystal.Order[] memory userOrders)
    {
        uint256 userId = addressToUserId[user];
        uint256[] memory temp = new uint256[](range > 1024 ? 1024 : range);
        uint256 count;
        for (uint256 i = 1; i < (range > 1024 ? 1024 : range); ++i) {
            uint256 order = orders[(i << 41) | userId];
            if ((order & MASK_OUT_113_154) != 0) {
                temp[count++] = i;
            }
        }

        userOrders = new ICrystal.Order[](count);
        cloids = new uint256[](count);
        for (uint256 i = 0; i < count; ++i) {
            cloids[i] = temp[i];
            userOrders[i] = getOrderByCloid(userId, temp[i]);
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
    /**
     * @notice Returns an order by user id and cloid.
     *
     * @param userId User id.
     * @param cloid Client order id.
     *
     * @return Order struct for the cloid.
     */
    function getOrderByCloid(
        uint256 userId,
        uint256 cloid
    ) public view returns (ICrystal.Order memory) {
        uint256 order = orders[(cloid << 41) | userId];
        uint256 price = cloidVerify[((cloid | 1) << 41) | userId];
        uint256 marketId;
        if (cloid & 1 != 0) {
            marketId = ((price >> 80) & MASK_KEEP_0_48);
            price = price & MASK_KEEP_0_80;
        } else {
            marketId = ((price >> 208) & MASK_KEEP_0_48);
            price = (price >> 128) & MASK_KEEP_0_80;
        }
        address market = marketIdToMarket[marketId];
        return
            ICrystal.Order(
                price <= _getMarket[market].highestBid ? true : false,
                market,
                price,
                (order & MASK_KEEP_0_112),
                ((order >> 112) & 0x1),
                ((order >> 113) & MASK_KEEP_0_41),
                ((order >> 154) & MASK_KEEP_0_51),
                ((order >> 205) & MASK_KEEP_0_51)
            );
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
    function getOrder(
        address market,
        uint256 price,
        uint256 id
    ) external view returns (ICrystal.Order memory) {
        uint256 order = orders[
            (marketToMarketId[market] << 128) | (price << 48) | id
        ];
        return
            ICrystal.Order(
                price <= _getMarket[market].highestBid ? true : false,
                market,
                price,
                (order & MASK_KEEP_0_112),
                ((order >> 112) & 0x1),
                ((order >> 113) & MASK_KEEP_0_41),
                ((order >> 154) & MASK_KEEP_0_51),
                ((order >> 205) & MASK_KEEP_0_51)
            );
    }

    /**
     * @notice Returns a price level for a market.
     *
     * @param market Market address.
     * @param price Price level.
     *
     * @return Price level struct.
     */
    /**
     * @notice Returns a price level for a market.
     *
     * @param market Market address.
     * @param price Price level.
     *
     * @return Price level struct.
     */
    function getPriceLevel(
        address market,
        uint256 price
    ) external view returns (ICrystal.PriceLevel memory) {
        uint256 priceLevel = priceLevels[
            (marketToMarketId[market] << 128) | price
        ];
        return
            ICrystal.PriceLevel(
                (priceLevel & MASK_KEEP_0_112),
                ((priceLevel >> 113) & MASK_KEEP_0_41),
                ((priceLevel >> 154) & MASK_KEEP_0_51),
                ((priceLevel >> 205) & MASK_KEEP_0_51)
            );
    }
    // market methods
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
    function getPriceLevels(
        address market,
        bool isAscending,
        uint256 startPrice,
        uint256 distance,
        uint256 interval,
        uint256 max
    ) external returns (bytes memory) {
        _delegateToMarket(market, 0x9c510697, 160, address(0));
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
    function getPriceLevelsFromMid(
        address market,
        uint256 distance,
        uint256 interval,
        uint256 max
    )
        external
        returns (
            uint256 highestBid,
            uint256 lowestAsk,
            bytes memory,
            bytes memory
        )
    {
        _delegateToMarket(market, 0xd58887ae, 96, address(0));
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
    function getPrice(
        address market
    ) external returns (uint256 price, uint256 highestBid, uint256 lowestAsk) {
        _delegateToMarket(market, 0x98d5fdca, 0, address(0));
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
    function getQuote(
        address market,
        bool isBuy,
        bool isExactInput,
        bool isCompleteFill,
        uint256 size,
        uint256 worstPrice
    ) external returns (uint256 amountIn, uint256 amountOut) {
        _delegateToMarket(market, 0x638571e3, 160, address(0));
    }

    /**
     * @notice Returns AMM reserves for a market.
     *
     * @param market Market address.
     *
     * @return reserveQuote Quote asset reserve.
     * @return reserveBase Base asset reserve.
     */
    function getReserves(
        address market
    ) external returns (uint112 reserveQuote, uint112 reserveBase) {
        _delegateToMarket(market, 0x0902f1ac, 0, address(0));
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
    function addLiquidity(
        address market,
        address to,
        uint256 amountQuoteDesired,
        uint256 amountBaseDesired,
        uint256 amountQuoteMin,
        uint256 amountBaseMin
    ) external payable returns (uint256 liquidity) {
        uint256 options;
        if (msg.value != 0) {
            IWETH(weth).deposit{value: msg.value}();
            tokenBalances[0][weth] += msg.value;
            require(
                _getMarket[market].quoteAsset == weth ||
                    _getMarket[market].baseAsset == weth
            );
            options = _getMarket[market].quoteAsset == weth ? (1) : (1 << 4);
        }
        _verifyMarketAndLock(market);
        assembly {
            mstore(0x80, shl(224, 0x2563e426))
            calldatacopy(0x84, 36, 160)
            mstore(0x124, options)
            let result := delegatecall(gas(), market, 0x80, 196, 0, 0)
            returndatacopy(0x80, 0, returndatasize())
            switch result
            case 0 {
                revert(0x80, returndatasize())
            }
            default {
                tstore(0x0, 0)
                liquidity := mload(0x80)
            }
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
    function removeLiquidity(
        address market,
        address to,
        uint256 liquidity,
        uint256 amountQuoteMin,
        uint256 amountBaseMin
    ) external returns (uint256 amountQuote, uint256 amountBase) {
        _delegateToMarket(market, 0x13928082, 160, address(0));
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
    function removeLiquidityETH(
        address market,
        address to,
        uint256 liquidity,
        uint256 amountQuoteMin,
        uint256 amountBaseMin
    ) external returns (uint256 amountQuote, uint256 amountBase) {
        require(
            _getMarket[market].quoteAsset == weth ||
                _getMarket[market].baseAsset == weth
        );
        uint256 options = _getMarket[market].quoteAsset == weth
            ? (1)
            : (1 << 4);
        _verifyMarketAndLock(market);
        assembly {
            mstore(0x80, shl(224, 0x13928082))
            calldatacopy(0x84, 36, 128)
            mstore(0x104, options)
            let result := delegatecall(gas(), market, 0x80, 164, 0, 0)
            returndatacopy(0x80, 0, returndatasize())
            switch result
            case 0 {
                revert(0x80, returndatasize())
            }
            default {
                tstore(0x0, 0)
                amountQuote := mload(0x80)
                amountBase := mload(add(0x80, 0x20))
            }
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
    function marketOrder(
        address market,
        bool isBuy,
        bool isExactInput,
        uint256 options,
        uint256 orderType,
        uint256 size,
        uint256 worstPrice,
        address referrer,
        address user
    ) external returns (uint256 amountIn, uint256 amountOut, uint256 id) {
        user = _verifyUser(user);
        _delegateToMarket(market, 0xe690552b, 224, user);
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
    function limitOrder(
        address market,
        bool isBuy,
        uint256 options,
        uint256 price,
        uint256 size,
        address user
    ) external returns (uint256 id) {
        user = _verifyUser(user);
        _delegateToMarket(market, 0x218a0c31, 128, user);
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
    function cancelOrder(
        address market,
        uint256 options,
        uint256 price,
        uint256 id,
        address user
    ) external returns (uint256 size) {
        user = _verifyUser(user);
        _delegateToMarket(market, 0xb69d86f7, 96, user);
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
    function replaceOrder(
        address market,
        uint256 options,
        uint256 price,
        uint256 id,
        uint256 newPrice,
        uint256 size,
        address referrer,
        address user
    ) external returns (uint256 _id) {
        user = _verifyUser(user);
        _delegateToMarket(market, 0x6c8dce79, 192, user);
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
    function batchOrders(
        address market,
        ICrystal.Action[] calldata actions,
        uint256 options,
        uint256 deadline,
        address referrer,
        address user
    ) external payable {
        user = _verifyUser(user);
        if (deadline < block.timestamp) {
            revert ICrystal.Expired(deadline);
        }
        if (msg.value != 0) {
            IWETH(weth).deposit{value: msg.value}();
            tokenBalances[0][weth] += msg.value;
        }
        _verifyMarketAndLock(market);
        (bool result, bytes memory ret) = market.delegatecall(
            abi.encodeWithSelector(0x5c2a91ec, actions, options, referrer, user)
        );
        uint256 balance = tokenBalances[0][weth] & MASK_KEEP_0_128;
        if (balance != 0) {
            tokenBalances[0][weth] = 0;
            IWETH(weth).withdraw(balance);
            (bool success, ) = msg.sender.call{value: balance}("");
            if (!success) {
                revert ICrystal.TransferFailed(msg.sender);
            }
        }
        assembly {
            switch result
            case 0 {
                revert(add(ret, 32), mload(ret))
            }
            default {
                tstore(0x0, 0)
            }
        }
    }

    /**
     * @notice Updates the governance address.
     *
     * @param newGov New governance address.
     */
    function changeGov(address newGov) external {
        if (msg.sender != gov) {
            revert ICrystal.Unauthorized(msg.sender);
        }
        gov = newGov;
        emit ICrystal.GovChanged(msg.sender, newGov);
    }

    /**
     * @notice Updates the protocol fee recipient.
     *
     * @param newFeeRecipient New fee recipient address.
     */
    function changeFeeRecipient(address newFeeRecipient) external {
        if (msg.sender != gov || newFeeRecipient == address(0)) {
            revert ICrystal.Unauthorized(msg.sender);
        }
        feeRecipient = newFeeRecipient;
    }

    /**
     * @notice Updates the fee claim duration.
     *
     * @param newFeeClaimDuration New fee claim duration.
     */
    function changeFeeClaimDuration(uint256 newFeeClaimDuration) external {
        if (msg.sender != gov) {
            revert ICrystal.Unauthorized(msg.sender);
        }
        require(newFeeClaimDuration > 86400);
        feeClaimDuration = newFeeClaimDuration;
    }

    /**
     * @notice Updates the referral fee commission.
     *
     * @param newFeeCommission New commission percentage.
     */
    function changeRefFeeCommission(uint8 newFeeCommission) external {
        if (msg.sender != gov) {
            revert ICrystal.Unauthorized(msg.sender);
        }
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
    function changeMarketParams(
        address market,
        uint256 newMinSize,
        uint24 newTakerFee,
        uint24 newMakerRebate,
        bool isAMMEnabled,
        bool isCanonical
    ) external {
        require(
            (isCanonicalDeployer[msg.sender] || msg.sender == gov) &&
                90000 <= newTakerFee &&
                newTakerFee <= 100000 &&
                90000 <= newMakerRebate &&
                newMakerRebate <= 100000
        );
        ICrystal.Market storage m = _getMarket[market];
        if (msg.sender != gov && msg.sender != m.creator) {
            revert ICrystal.Unauthorized(msg.sender);
        }
        uint256 minSizeZeroes;
        while (newMinSize != 0 && newMinSize % 10 == 0) {
            newMinSize /= 10;
            ++minSizeZeroes;
        }
        require(newMinSize < MASK_KEEP_0_20 && minSizeZeroes < MASK_KEEP_0_20);
        m.minSize = uint40((newMinSize << 20) | minSizeZeroes);
        m.takerFee = newTakerFee;
        m.makerRebate = newMakerRebate;
        m.isAMMEnabled = isAMMEnabled;
        if (
            isCanonical &&
            (getMarketByTokens[m.quoteAsset][m.baseAsset] == address(0) ||
                msg.sender == gov)
        ) {
            getMarketByTokens[m.quoteAsset][m.baseAsset] = market;
            getMarketByTokens[m.baseAsset][m.quoteAsset] = market;
        } else if (
            !isCanonical &&
            getMarketByTokens[m.quoteAsset][m.baseAsset] == market
        ) {
            getMarketByTokens[m.quoteAsset][m.baseAsset] = address(0);
            getMarketByTokens[m.baseAsset][m.quoteAsset] = address(0);
        }
        emit ICrystal.MarketParamsChanged(
            market,
            (m.minSize >> 20) * 10 ** (m.minSize & MASK_KEEP_0_20),
            newTakerFee,
            newMakerRebate,
            m.isAMMEnabled
        );
    }

    /**
     * @notice Updates market creator address or fee split.
     *
     * @param market Market address.
     * @param newCreator New creator address.
     * @param newCreatorFee New creator fee split.
     */
    function changeMarketCreatorFee(
        address market,
        address newCreator,
        uint256 newCreatorFee
    ) external {
        ICrystal.Market storage m = _getMarket[market];
        if (newCreatorFee == m.creatorFeeSplit) {
            require(msg.sender == m.creator || msg.sender == gov);
            m.creator = newCreator;
            return;
        }
        require(
            (isCanonicalDeployer[msg.sender] || msg.sender == gov) &&
                newCreatorFee <= 50
        );
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
    function changeLaunchpadParams(
        ICrystal.LaunchpadParams memory newLaunchpadParams
    ) external {
        if (msg.sender != gov) {
            revert ICrystal.Unauthorized(msg.sender);
        }
        uint256 minSizeZeroes;
        uint256 minSize = newLaunchpadParams.graduatedMinSize;
        while (minSize != 0 && minSize % 10 == 0) {
            minSize /= 10;
            ++minSizeZeroes;
        }
        require(
            minSize < MASK_KEEP_0_20 &&
                minSizeZeroes < MASK_KEEP_0_20 &&
                newLaunchpadParams.launchpadInitialNativeSupply > 1e18 &&
                90000 <= newLaunchpadParams.launchpadFee &&
                newLaunchpadParams.launchpadFee <= 100000 &&
                90000 <= newLaunchpadParams.graduatedTakerFee
        );
        require(
            newLaunchpadParams.graduatedTakerFee <= 100000 &&
                90000 <= newLaunchpadParams.graduatedMakerRebate &&
                newLaunchpadParams.graduatedMakerRebate <= 100000 &&
                newLaunchpadParams.graduatedCreatorFeeSplit <= 50 &&
                newLaunchpadParams.launchpadCreatorFeeSplit <= 50
        );
        launchpadParams = newLaunchpadParams;
    }

    /**
     * @notice Adds an address authorized to deploy canonical markets.
     *
     * @param deployer Deployer address.
     */
    function addCanonicalDeployer(address deployer) external {
        if (msg.sender != gov) {
            revert ICrystal.Unauthorized(msg.sender);
        }
        isCanonicalDeployer[deployer] = true;
    }

    /**
     * @notice Removes a canonical deployer.
     *
     * @param deployer Deployer address.
     */
    function removeCanonicalDeployer(address deployer) external {
        if (msg.sender != gov) {
            revert ICrystal.Unauthorized(msg.sender);
        }
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
     * @notice Deposits tokens into the router for the caller.
     *
     * @param token Token address (ETH sentinel supported).
     * @param amount Amount to deposit.
     *
     * @return userId Caller user id.
     */
    function deposit(
        address token,
        uint256 amount
    ) external payable returns (uint256 userId) {
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
        require(
            ((tokenBalances[userId][token] & MASK_KEEP_0_128) + amount) <=
                MASK_KEEP_0_128
        );
        tokenBalances[userId][token] += amount;
        emit ICrystal.Deposit(msg.sender, userId, token, amount);
    }

    /**
     * @notice Withdraws tokens from the router.
     *
     * @param to Recipient address.
     * @param token Token address (ETH sentinel supported).
     * @param amount Amount to withdraw (0 withdraws full balance).
     */
    function withdraw(address to, address token, uint256 amount) external {
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
    function clearCloidSlots(uint256 userId, uint256[] calldata ids) external {
        if (msg.sender != userIdToAddress[userId] && msg.sender != gov) {
            revert ICrystal.Unauthorized(msg.sender);
        }
        for (uint256 i; i < ids.length; ++i) {
            if ((orders[(ids[i] << 41) | userId] & MASK_OUT_113_154) == 0) {
                // order can't be active
                delete orders[(ids[i] << 41) | userId];
                if (ids[i] & 1 != 0) {
                    cloidVerify[
                        ((ids[i] | 1) << 41) | userId
                    ] &= MASK_OUT_0_128;
                } else {
                    cloidVerify[
                        ((ids[i] | 1) << 41) | userId
                    ] &= MASK_KEEP_0_128;
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
    function writeCloidSlots(uint256 userId, uint256[] calldata ids) external {
        if (msg.sender != userIdToAddress[userId]) {
            revert ICrystal.Unauthorized(msg.sender);
        }
        for (uint256 i; i < ids.length; ++i) {
            uint256 id = ids[i];
            if (id < 1024) {
                if (orders[(id << 41) | userId] == 0) {
                    orders[(id << 41) | userId] |= (userId << 113);
                    if (id & 1 != 0) {
                        cloidVerify[
                            ((id | 1) << 41) | userId
                        ] |= MASK_KEEP_0_128;
                    } else {
                        cloidVerify[
                            ((id | 1) << 41) | userId
                        ] |= MASK_OUT_0_128;
                    }
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
     * @param slotIndexes2 Slot indexes for activated2 bitmap.
     */
    function writeSlots(
        address market,
        uint256[] calldata slotIndexes,
        uint256[] calldata slotIndexes2
    ) external {
        for (uint256 i; i < slotIndexes.length; ++i) {
            activated[
                (marketToMarketId[market] << 128) |
                    (slotIndexes[i] & MASK_KEEP_0_128)
            ] |= MASK_KEEP_255_256;
        }
        for (uint256 i; i < slotIndexes2.length; ++i) {
            activated2[
                (marketToMarketId[market] << 128) |
                    (slotIndexes2[i] & MASK_KEEP_0_128)
            ] |= MASK_KEEP_255_256;
        }
    }

    /**
     * @notice Adds claimable fee amounts for an address.
     *
     * @param to Address receiving fees.
     * @param tokens Token list.
     * @param amounts Amount list matching tokens.
     */
    function addClaimableFee(
        address to,
        address[] calldata tokens,
        uint256[] calldata amounts
    ) external payable {
        uint256 value = msg.value;
        for (uint256 i = 0; i < tokens.length; ++i) {
            if (tokens[i] == eth) {
                require(value >= amounts[i]);
                value -= amounts[i];
                IWETH(weth).deposit{value: amounts[i]}();
                claimableRewards[weth][to] += amounts[i];
            } else {
                claimableRewards[tokens[i]][to] += amounts[i];
                IERC20(tokens[i]).transferFrom(
                    msg.sender,
                    address(this),
                    amounts[i]
                );
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
    function claimFees(
        address to,
        address[] calldata tokens
    ) external returns (uint256[] memory amounts) {
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
    function queueClaimExpiredFees(
        address user,
        address[] calldata tokens
    ) external {
        if (pendingExpiredFeeClaims[user].deadline != 0 && msg.sender != gov) {
            revert ICrystal.Unauthorized(msg.sender);
        }
        require(tokens.length != 0 && tokens.length < 100);
        uint256[] memory amounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            uint256 amount = claimableRewards[tokens[i]][user];
            if (msg.sender != gov) {
                require(amount > 0);
            }
            amounts[i] = amount;
        }
        pendingExpiredFeeClaims[user].deadline =
            block.timestamp +
            feeClaimDuration;
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
    function executeClaimExpiredFees(
        address user
    ) external returns (uint256[] memory amounts) {
        if (
            msg.sender != gov ||
            block.timestamp < pendingExpiredFeeClaims[user].deadline
        ) {
            revert ICrystal.Unauthorized(msg.sender);
        }
        amounts = pendingExpiredFeeClaims[user].amounts;
        for (
            uint256 i = 0;
            i < pendingExpiredFeeClaims[user].tokens.length;
            ++i
        ) {
            claimableRewards[pendingExpiredFeeClaims[user].tokens[i]][
                user
            ] -= amounts[i];
            IERC20(pendingExpiredFeeClaims[user].tokens[i]).transfer(
                msg.sender,
                amounts[i]
            );
        }
        delete pendingExpiredFeeClaims[user];
    }

    /**
     * @notice Deploys a new Crystal market.
     *
     * @param isCanonical Whether the market should be canonical for the token pair.
     * @param quoteAsset Quote asset address (ETH sentinel supported).
     * @param baseAsset Base asset address (ETH sentinel supported).
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
    function deploy(
        bool isCanonical,
        address quoteAsset,
        address baseAsset,
        uint256 marketType,
        uint256 scaleFactor,
        uint256 tickSize,
        uint256 maxPrice,
        uint256 minSize,
        uint24 takerFee,
        uint24 makerRebate
    ) external returns (address market) {
        if (isCanonical && !isCanonicalDeployer[msg.sender]) {
            revert ICrystal.Unauthorized(msg.sender);
        }
        if (quoteAsset == eth) {
            quoteAsset = weth;
        } else if (baseAsset == eth) {
            baseAsset = weth;
        }
        require(
            90000 <= takerFee &&
                takerFee <= 100000 &&
                90000 <= makerRebate &&
                makerRebate <= 100000
        ); // validate all fee params, total fee is takerFee+makerRebate
        uint256 marketId = allMarkets.length + 1;
        {
            parameters = ICrystal.Parameters(
                quoteAsset,
                baseAsset,
                marketId,
                marketType,
                scaleFactor,
                tickSize,
                maxPrice
            ); // maxsize is validated here
            uint256 maxTick;
            market = address(
                new CrystalMarket{salt: keccak256(abi.encode(marketId))}()
            );
            if (marketType == 0) {
                require(maxPrice % tickSize == 0);
                maxTick = maxPrice / tickSize;
            } else if (marketType == 1 || marketType == 2 || marketType == 3) {
                maxTick = _priceToTick(maxPrice, tickSize);
            } else {
                revert ICrystal.ActionFailed();
            }
            delete parameters;
            ICrystal.Market storage m = _getMarket[market];
            (
                m.quoteAsset,
                m.baseAsset,
                m.marketId,
                m.scaleFactor,
                m.tickSize
            ) = (quoteAsset, baseAsset, marketId, scaleFactor, tickSize); // immutable params but for _getMarket
            (
                m.takerFee,
                m.makerRebate,
                m.maxPrice,
                m.marketType,
                m.isAMMEnabled
            ) = (takerFee, makerRebate, maxPrice, marketType, marketType > 1);
            (m.creator, m.creatorFeeSplit) = (
                msg.sender,
                uint8(launchpadParams.graduatedCreatorFeeSplit)
            );
            m.lowestAsk = uint80(maxPrice);
            activated[(marketId << 128)] = 1; // index 0
            activated2[(marketId << 128)] = 1;
            activated[(marketId << 128) | (maxTick / 255)] = (1 <<
                (maxTick % 255));
            activated2[(marketId << 128) | ((maxTick / 255) / 255)] = (1 <<
                ((maxTick / 255) % 255));
            uint256 minSizeZeroes;
            uint256 tempMinSize = minSize;
            while (tempMinSize != 0 && tempMinSize % 10 == 0) {
                tempMinSize /= 10;
                ++minSizeZeroes;
            }
            require(
                tempMinSize < MASK_KEEP_0_20 &&
                    minSizeZeroes < MASK_KEEP_0_20 &&
                    marketId < MASK_KEEP_0_48
            ); // minSize is encoded as bits 20-40 * 10 ** bits 0-20, marketid max uint48 minsize is variable to prevent dos
            m.minSize = uint40((tempMinSize << 20) | minSizeZeroes);
        }
        allMarkets.push(market);
        marketToMarketId[market] = marketId;
        marketIdToMarket[marketId] = market;
        require(
            launchpadTokenToMarket[baseAsset].virtualNativeReserve == 0 &&
                launchpadTokenToMarket[quoteAsset].virtualNativeReserve == 0
        );
        if (isCanonical) {
            getMarketByTokens[quoteAsset][baseAsset] = market;
            getMarketByTokens[baseAsset][quoteAsset] = market;
        } else {
            if (
                getMarketByTokens[quoteAsset][baseAsset] == address(0) &&
                (marketType == 1 || marketType == 2)
            ) {
                getMarketByTokens[quoteAsset][baseAsset] = market;
                getMarketByTokens[baseAsset][quoteAsset] = market;
            }
        }
        ICrystal.TokenMetadata memory qMeta = ICrystal.TokenMetadata(
            quoteAsset,
            IERC20(quoteAsset).decimals(),
            IERC20(quoteAsset).symbol(),
            IERC20(quoteAsset).name()
        );
        ICrystal.TokenMetadata memory bMeta = ICrystal.TokenMetadata(
            baseAsset,
            IERC20(baseAsset).decimals(),
            IERC20(baseAsset).symbol(),
            IERC20(baseAsset).name()
        );
        ICrystal.MarketDetails memory details = ICrystal.MarketDetails(
            marketId,
            marketType,
            scaleFactor,
            tickSize,
            maxPrice,
            minSize,
            takerFee,
            makerRebate
        );
        bool _isCanonical = isCanonical; // avoid stack too deep
        emit ICrystal.MarketCreated(
            _isCanonical,
            quoteAsset,
            baseAsset,
            market,
            qMeta,
            bMeta,
            details
        );
    }

    /**
     * @notice Quotes output amounts for a multi-hop swap path.
     *
     * @param amountIn Input amount for the first hop.
     * @param path Token swap path.
     *
     * @return amounts Array of hop-by-hop amounts.
     */
    function getAmountsOut(
        uint256 amountIn,
        address[] memory path
    ) external returns (uint256[] memory amounts) {
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
            (bool result, bytes memory ret) = market.delegatecall(
                abi.encodeWithSelector(
                    0x638571e3,
                    _getMarket[market].quoteAsset == asset0,
                    true,
                    i != 0,
                    amounts[i],
                    _getMarket[market].quoteAsset == asset0 ? MASK_KEEP_0_80 : 1
                )
            );
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
    function getAmountsIn(
        uint256 amountOut,
        address[] memory path
    ) public returns (uint256[] memory amounts) {
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
            (bool result, bytes memory ret) = market.delegatecall(
                abi.encodeWithSelector(
                    0x638571e3,
                    _getMarket[market].quoteAsset == asset0,
                    false,
                    true,
                    amounts[i],
                    _getMarket[market].quoteAsset == asset0 ? MASK_KEEP_0_80 : 1
                )
            );
            if (!result) {
                revert ICrystal.SlippageExceeded();
            }
            (amounts[i - 1], outputAmount) = abi.decode(
                ret,
                (uint256, uint256)
            );
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
    function exactInputSwap(
        uint256 amountIn,
        address[] memory path,
        address to,
        address referrer
    ) internal returns (uint256[] memory amounts) {
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        assembly {
            if tload(0x0) {
                revert(0, 0)
            }
            tstore(0x0, 1)
        }
        for (uint256 i; i < path.length - 1; ++i) {
            address asset0 = path[i] == eth ? weth : path[i];
            address asset1 = path[i + 1] == eth ? weth : path[i + 1];
            address market = getMarketByTokens[asset0][asset1];
            if (market == address(0) || market == placeholder) {
                revert ICrystal.InvalidMarket(asset0, asset1);
            }
            asset1 = _getMarket[market].quoteAsset;
            uint256 options = ((i != 0 || path[i] == eth) ? (1 << 64) : 0) |
                (
                    (i != path.length - 2 ||
                        path[i + 1] == eth ||
                        to != msg.sender)
                        ? (1 << 60)
                        : 0
                );
            bytes memory ret = abi.encodeWithSelector(
                0xe690552b,
                asset1 == asset0,
                true,
                options,
                1,
                amounts[i],
                asset1 == asset0 ? MASK_KEEP_0_80 : 1,
                referrer,
                msg.sender
            );
            bool result;
            (result, ret) = market.delegatecall(ret);
            if (!result) {
                revert ICrystal.SlippageExceeded();
            }
            (, amounts[i + 1], ) = abi.decode(ret, (uint256, uint256, uint256));
        }
        assembly {
            tstore(0x0, 0)
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
    function exactOutputSwap(
        uint256[] memory amounts,
        address[] memory path,
        address to,
        address referrer
    ) internal {
        assembly {
            if tload(0x0) {
                revert(0, 0)
            }
            tstore(0x0, 1)
        }
        for (uint256 i; i < path.length - 1; ++i) {
            address asset0 = path[i] == eth ? weth : path[i];
            address asset1 = path[i + 1] == eth ? weth : path[i + 1];
            address market = getMarketByTokens[asset0][asset1];
            if (market == address(0) || market == placeholder) {
                revert ICrystal.InvalidMarket(asset0, asset1);
            }
            asset1 = _getMarket[market].quoteAsset;
            uint256 options = ((i != 0 || path[i] == eth) ? (1 << 64) : 0) |
                (
                    (i != path.length - 2 ||
                        path[i + 1] == eth ||
                        to != msg.sender)
                        ? (1 << 60)
                        : 0
                );
            bytes memory ret = abi.encodeWithSelector(
                0xe690552b,
                asset1 == asset0,
                false,
                options,
                1,
                amounts[i + 1],
                asset1 == asset0 ? MASK_KEEP_0_80 : 1,
                referrer,
                msg.sender
            );
            bool result;
            (result, ret) = market.delegatecall(ret);
            if (!result) {
                revert ICrystal.SlippageExceeded();
            }
            (amounts[i], , ) = abi.decode(ret, (uint256, uint256, uint256));
        }
        assembly {
            tstore(0x0, 0)
        }
    }

    /**
     * @notice Deposits tokens into the router's shared slot.
     *
     * @dev Anyone can deposit/withdraw from 0 slot, used as in between for multihop swaps.
     *
     * @param token Token address (ETH sentinel supported).
     * @param amount Amount to deposit.
     */
    function routerDeposit(address token, uint256 amount) external payable {
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
     * @param token Token address (ETH sentinel supported).
     * @param amount Amount to withdraw.
     */
    function routerWithdraw(
        address to,
        address token,
        uint256 amount
    ) external {
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
     * @notice Swaps an exact amount of ETH for tokens.
     *
     * @param amountOutMin Minimum tokens expected.
     * @param path Swap path.
     * @param to Recipient address.
     * @param deadline Expiration timestamp.
     * @param referrer Optional referrer for fee sharing.
     *
     * @return amounts Hop-by-hop amounts.
     */
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] memory path,
        address to,
        uint256 deadline,
        address referrer
    ) external payable returns (uint256[] memory amounts) {
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
     * @notice Swaps an exact amount of tokens for ETH.
     *
     * @param amountIn Tokens to swap.
     * @param amountOutMin Minimum ETH expected.
     * @param path Swap path.
     * @param to Recipient address.
     * @param deadline Expiration timestamp.
     * @param referrer Optional referrer for fee sharing.
     *
     * @return amounts Hop-by-hop amounts.
     */
    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path,
        address to,
        uint256 deadline,
        address referrer
    ) external returns (uint256[] memory amounts) {
        if (deadline < block.timestamp) {
            revert ICrystal.Expired(deadline);
        }
        if (path.length < 2 || path[path.length - 1] != eth) {
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
     * @notice Swaps an exact amount of tokens for tokens.
     *
     * @param amountIn Tokens to swap.
     * @param amountOutMin Minimum output expected.
     * @param path Swap path.
     * @param to Recipient address.
     * @param deadline Expiration timestamp.
     * @param referrer Optional referrer for fee sharing.
     *
     * @return amounts Hop-by-hop amounts.
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path,
        address to,
        uint256 deadline,
        address referrer
    ) external returns (uint256[] memory amounts) {
        if (deadline < block.timestamp) {
            revert ICrystal.Expired(deadline);
        }
        if (path.length < 2 || path[path.length - 1] == eth) {
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
     * @notice Swaps ETH for an exact token amount.
     *
     * @param amountOut Desired output amount.
     * @param path Swap path.
     * @param to Recipient address.
     * @param deadline Expiration timestamp.
     * @param referrer Optional referrer for fee sharing.
     *
     * @return amounts Hop-by-hop amounts.
     */
    function swapETHForExactTokens(
        uint256 amountOut,
        address[] memory path,
        address to,
        uint256 deadline,
        address referrer
    ) external payable returns (uint256[] memory amounts) {
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
     * @notice Swaps tokens for an exact amount of ETH.
     *
     * @param amountOut Desired ETH output.
     * @param amountInMax Maximum tokens to spend.
     * @param path Swap path.
     * @param to Recipient address.
     * @param deadline Expiration timestamp.
     * @param referrer Optional referrer for fee sharing.
     *
     * @return amounts Hop-by-hop amounts.
     */
    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] memory path,
        address to,
        uint256 deadline,
        address referrer
    ) external returns (uint256[] memory amounts) {
        if (deadline < block.timestamp) {
            revert ICrystal.Expired(deadline);
        }
        if (path[path.length - 1] != eth) {
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
     * @notice Swaps tokens for an exact token amount.
     *
     * @param amountOut Desired output amount.
     * @param amountInMax Maximum input allowed.
     * @param path Swap path.
     * @param to Recipient address.
     * @param deadline Expiration timestamp.
     * @param referrer Optional referrer for fee sharing.
     *
     * @return amounts Hop-by-hop amounts.
     */
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] memory path,
        address to,
        uint256 deadline,
        address referrer
    ) external returns (uint256[] memory amounts) {
        if (deadline < block.timestamp) {
            revert ICrystal.Expired(deadline);
        }
        if (path[path.length - 1] == eth) {
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
     * @notice Executes a swap through the underlying market router.
     *
     * @param isExactInput True if `size` is input amount, false if output.
     * @param tokenIn Input token (ETH sentinel supported).
     * @param tokenOut Output token (ETH sentinel supported).
     * @param orderType Execution type.
     * @param size Input or output amount depending on `isExactInput`.
     * @param worstPrice Inclusive worst price limit.
     * @param deadline Expiration timestamp.
     * @param referrer Optional referrer for fee sharing.
     *
     * @return userId User id of caller.
     * @return balance Remaining WETH balance returned.
     * @return id Order id if created.
     */
    function swap(
        bool isExactInput,
        address tokenIn,
        address tokenOut,
        uint256 orderType,
        uint256 size,
        uint256 worstPrice,
        uint256 deadline,
        address referrer
    ) external payable returns (uint256 userId, uint256 balance, uint256 id) {
        if (deadline < block.timestamp) {
            revert ICrystal.Expired(deadline);
        }
        address market = getMarketByTokens[tokenIn == eth ? weth : tokenIn][
            tokenOut == eth ? weth : tokenOut
        ];
        if (market == address(0) || market == placeholder) {
            revert ICrystal.InvalidMarket(
                tokenIn == eth ? weth : tokenIn,
                tokenOut == eth ? weth : tokenOut
            );
        }
        if (tokenIn == eth) {
            IWETH(weth).deposit{value: msg.value}();
            tokenBalances[0][weth] += msg.value;
        }
        assembly {
            if tload(0x0) {
                revert(0, 0)
            }
            tstore(0x0, 1)
        }
        bool result = _getMarket[market].quoteAsset ==
            (tokenIn == eth ? weth : tokenIn);
        deadline =
            ((tokenIn == eth) ? (1 << 64) : 0) |
            ((tokenOut == eth) ? (1 << 60) : 0);
        bytes memory ret = abi.encodeWithSelector(
            0xe690552b,
            result,
            isExactInput,
            deadline,
            orderType,
            size,
            worstPrice,
            referrer,
            msg.sender
        );
        (result, ret) = market.delegatecall(ret);
        if (!result) {
            revert ICrystal.ActionFailed();
        }
        if (tokenIn == eth || tokenOut == eth) {
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
        (userId, balance, id) = abi.decode(ret, (uint256, uint256, uint256));
        assembly {
            tstore(0x0, 0)
        }
    }

    /**
     * @notice Places a limit order via the router.
     *
     * @param tokenIn Input token (ETH sentinel supported).
     * @param tokenOut Output token (ETH sentinel supported).
     * @param price Limit price.
     * @param size Order size.
     * @param deadline Expiration timestamp.
     *
     * @return id Assigned order identifier.
     */
    function placeLimitOrder(
        address tokenIn,
        address tokenOut,
        uint256 price,
        uint256 size,
        uint256 deadline
    ) external payable returns (uint256 id) {
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
        assembly {
            if tload(0x0) {
                revert(0, 0)
            }
            tstore(0x0, 1)
        }
        uint256 options = (isETHIn ? (1 << 56) : 0);
        (bool result, bytes memory ret) = market.delegatecall(
            abi.encodeWithSelector(
                0x218a0c31,
                _getMarket[market].quoteAsset == asset0,
                options,
                price,
                size,
                msg.sender
            )
        );
        if (!result) {
            revert ICrystal.ActionFailed();
        }
        id = abi.decode(ret, (uint256));
        assembly {
            tstore(0x0, 0)
        }
    }

    /**
     * @notice Cancels a limit order via the router.
     *
     * @param tokenIn Input token (ETH sentinel supported).
     * @param tokenOut Output token (ETH sentinel supported).
     * @param price Order price (0 when cancelling by cloid).
     * @param id Order id or cloid.
     * @param deadline Expiration timestamp.
     *
     * @return size Amount released.
     */
    function cancelLimitOrder(
        address tokenIn,
        address tokenOut,
        uint256 price,
        uint256 id,
        uint256 deadline
    ) external returns (uint256 size) {
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
        assembly {
            if tload(0x0) {
                revert(0, 0)
            }
            tstore(0x0, 1)
        }
        uint256 options = (isETHIn ? (1 << 44) : 0);
        (bool result, bytes memory ret) = market.delegatecall(
            abi.encodeWithSelector(0xb69d86f7, options, price, id, msg.sender)
        );
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
        assembly {
            tstore(0x0, 0)
        }
    }

    /**
     * @notice Replaces or decreases an existing limit order via the router.
     *
     * @param isPostOnly Whether to post-only the replacement.
     * @param isDecrease Whether to decrease size.
     * @param tokenIn Input token (ETH sentinel supported).
     * @param tokenOut Output token (ETH sentinel supported).
     * @param price Existing order price.
     * @param id Existing order id.
     * @param newPrice New price.
     * @param newSize New size (0 to reuse previous size).
     * @param deadline Expiration timestamp.
     * @param referrer Optional referrer for fee sharing.
     *
     * @return Replacement order id.
     */
    function replaceOrder(
        bool isPostOnly,
        bool isDecrease,
        address tokenIn,
        address tokenOut,
        uint256 price,
        uint256 id,
        uint256 newPrice,
        uint256 newSize,
        uint256 deadline,
        address referrer
    ) external payable returns (uint256) {
        if (deadline < block.timestamp) {
            revert ICrystal.Expired(deadline);
        }
        address market = getMarketByTokens[tokenIn == eth ? weth : tokenIn][
            tokenOut == eth ? weth : tokenOut
        ];
        if (market == address(0) || market == placeholder) {
            revert ICrystal.InvalidMarket(
                tokenIn == eth ? weth : tokenIn,
                tokenOut == eth ? weth : tokenOut
            );
        }
        if (tokenIn == eth) {
            IWETH(weth).deposit{value: msg.value}();
            tokenBalances[0][weth] += msg.value;
        }
        assembly {
            if tload(0x0) {
                revert(0, 0)
            }
            tstore(0x0, 1)
        }
        deadline =
            ((tokenIn == eth) ? (1 << 56) : 0) |
            ((tokenOut == eth) ? (1 << 52) : 0) |
            (isDecrease ? (1 << 48) : 0) |
            (isPostOnly ? 0 : (1 << 44));
        (bool result, bytes memory ret) = market.delegatecall(
            abi.encodeWithSelector(
                0x6c8dce79,
                deadline,
                price,
                id,
                newPrice,
                newSize,
                referrer,
                msg.sender
            )
        );
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
        assembly {
            tstore(0x0, 0)
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
    function multiBatchOrders(
        ICrystal.Batch[] calldata batches,
        uint256 deadline,
        address referrer
    ) external payable {
        if (deadline < block.timestamp) {
            revert ICrystal.Expired(deadline);
        }
        if (msg.value != 0) {
            IWETH(weth).deposit{value: msg.value}();
            tokenBalances[0][weth] += msg.value;
        }
        assembly {
            if tload(0x0) {
                revert(0, 0)
            }
            tstore(0x0, 1)
        }
        for (uint256 i; i < batches.length; ++i) {
            address market = batches[i].market;
            assembly {
                mstore(0x00, market)
                mstore(0x20, _getMarket.slot)
                if iszero(and(sload(keccak256(0x00, 0x40)), MASK_KEEP_80_160)) {
                    revert(0, 0)
                }
            }
            (bool result, bytes memory ret) = market.delegatecall(
                abi.encodeWithSelector(
                    0x5c2a91ec,
                    batches[i].actions,
                    batches[i].options,
                    referrer,
                    msg.sender
                )
            );
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
        assembly {
            tstore(0x0, 0)
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
    function getVirtualReserves(
        address token
    )
        external
        view
        returns (uint256 virtualNativeReserve, uint256 virtualTokenReserve)
    {
        ICrystal.LaunchpadMarket storage market = launchpadTokenToMarket[token];
        (virtualNativeReserve, virtualTokenReserve) = (
            market.virtualNativeReserve,
            market.virtualTokenReserve
        );
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
    function createToken(
        string memory name,
        string memory symbol,
        string memory metadataCID,
        string memory description,
        string memory social1,
        string memory social2,
        string memory social3,
        string memory social4
    ) external payable returns (address token) {
        assembly {
            if tload(0x0) {
                revert(0, 0)
            }
            tstore(0x0, 1)
        }
        token = address(
            new CrystalToken(
                address(this),
                name,
                symbol,
                metadataCID,
                description,
                social1,
                social2,
                social3,
                social4
            )
        );
        allTokens.push(address(token));
        emit ICrystal.TokenCreated(
            address(token),
            msg.sender,
            name,
            symbol,
            metadataCID,
            description,
            social1,
            social2,
            social3,
            social4
        );
        uint256 marketId = allMarkets.length + 1;
        require(marketId < MASK_KEEP_0_48);
        parameters = ICrystal.Parameters(
            weth,
            token,
            marketId,
            3,
            9,
            1,
            1000000000000000
        ); // maxsize is validated here
        uint256 maxTick;
        address market;
        market = address(
            new CrystalMarket{salt: keccak256(abi.encode(marketId))}()
        ); // can't be traded yet as slot 0 in mapping isn't initialized, and is not in getmarketbyassets either
        maxTick = _priceToTick(1000000000000000, 1);
        delete parameters;
        ICrystal.Market storage m = _getMarket[market];
        (m.quoteAsset, m.baseAsset, m.marketId, m.scaleFactor, m.tickSize) = (
            weth,
            token,
            marketId,
            9,
            1
        ); // immutable params but for _getMarket
        (
            m.maxPrice,
            m.marketType,
            m.creator,
            m.creatorFeeSplit,
            m.isAMMEnabled
        ) = (
            1000000000000000,
            3,
            msg.sender,
            uint8(launchpadParams.graduatedCreatorFeeSplit),
            true
        );
        activated[(marketId << 128)] = 1; // index 0
        activated2[(marketId << 128)] = 1;
        activated[(marketId << 128) | (maxTick / 255)] = (1 << (maxTick % 255));
        activated2[(marketId << 128) | ((maxTick / 255) / 255)] = (1 <<
            ((maxTick / 255) % 255));
        allMarkets.push(market);
        marketToMarketId[market] = marketId;
        marketIdToMarket[marketId] = market;
        getMarketByTokens[weth][token] = placeholder;
        getMarketByTokens[token][weth] = placeholder;
        launchpadTokenToMarket[address(token)] = ICrystal.LaunchpadMarket(
            launchpadParams.launchpadInitialNativeSupply,
            1000000000000000000000000000,
            uint256(launchpadParams.launchpadInitialNativeSupply) *
                1000000000000000000000000000,
            msg.sender,
            market,
            uint88(block.timestamp)
        );
        (bool result, bytes memory ret) = market.delegatecall(
            abi.encodeWithSelector(
                0xf7bb5c88,
                address(this),
                ((1000000000000000000000000000 *
                    uint256(launchpadParams.launchpadInitialNativeSupply)) /
                    200000000000000000000000000) -
                    uint256(launchpadParams.launchpadInitialNativeSupply),
                200000000000000000000000000
            ) // premint
        );
        if (!result) {
            revert ICrystal.ActionFailed();
        }
        uint256 liquidity = abi.decode(ret, (uint256));
        IERC20(market).transfer(address(0), liquidity);
        assembly {
            tstore(0x0, 0)
        }
        if (msg.value != 0) {
            buy(true, token, msg.value, 0);
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
    function buy(
        bool isExactInput,
        address token,
        uint256 amountIn,
        uint256 amountOut
    ) public payable returns (uint256, uint256, bool) {
        assembly {
            if tload(0x0) {
                revert(0, 0)
            }
            tstore(0x0, 1)
        }
        if (isExactInput) {
            require(msg.value == amountIn);
        }
        ICrystal.LaunchpadMarket
            storage launchpadMarket = launchpadTokenToMarket[token];
        uint256 inputAmount;
        uint256 outputAmount;
        if (launchpadMarket.virtualTokenReserve != 0) {
            if (isExactInput) {
                inputAmount = amountIn;
                if (
                    launchpadMarket.virtualNativeReserve +
                        ((inputAmount * launchpadParams.launchpadFee) /
                            100000) >
                    (launchpadMarket.k / 200000000000000000000000000)
                ) {
                    inputAmount =
                        ((((launchpadMarket.k +
                            200000000000000000000000000 -
                            1) / 200000000000000000000000000) -
                            launchpadMarket.virtualNativeReserve) *
                            100000 +
                            launchpadParams.launchpadFee -
                            1) /
                        launchpadParams.launchpadFee;
                }
                IWETH(weth).deposit{value: inputAmount}();
                uint256 amountAfterFee = (inputAmount *
                    launchpadParams.launchpadFee) / 100000;
                uint256 collectedFee = inputAmount - amountAfterFee;
                uint256 creatorFee = (collectedFee *
                    launchpadParams.launchpadCreatorFeeSplit) / 100;
                claimableRewards[weth][launchpadMarket.creator] += creatorFee;
                claimableRewards[weth][gov] += (collectedFee - creatorFee);
                launchpadMarket.virtualNativeReserve += uint112(amountAfterFee);
                uint256 oldTokenReserve = launchpadMarket.virtualTokenReserve;
                launchpadMarket.virtualTokenReserve = uint112(
                    (launchpadMarket.k +
                        launchpadMarket.virtualNativeReserve -
                        1) / launchpadMarket.virtualNativeReserve
                );
                outputAmount =
                    oldTokenReserve -
                    launchpadMarket.virtualTokenReserve;
                IERC20(token).transfer(msg.sender, outputAmount);
            } else {
                uint256 newToken = launchpadMarket.virtualTokenReserve -
                    amountOut;
                uint256 newNative = (uint256(launchpadMarket.k) +
                    newToken -
                    1) / newToken;
                uint256 preFeeIn = newNative -
                    launchpadMarket.virtualNativeReserve;
                if (
                    launchpadMarket.virtualNativeReserve + preFeeIn >
                    (launchpadMarket.k / 200000000000000000000000000)
                ) {
                    inputAmount =
                        ((((launchpadMarket.k +
                            200000000000000000000000000 -
                            1) / 200000000000000000000000000) -
                            launchpadMarket.virtualNativeReserve) *
                            100000 +
                            launchpadParams.launchpadFee -
                            1) /
                        launchpadParams.launchpadFee;
                    IWETH(weth).deposit{value: inputAmount}();
                    uint256 collectedFee = inputAmount -
                        ((inputAmount * launchpadParams.launchpadFee) / 100000);
                    uint256 creatorFee = (collectedFee *
                        launchpadParams.launchpadCreatorFeeSplit) / 100;
                    claimableRewards[weth][
                        launchpadMarket.creator
                    ] += creatorFee;
                    claimableRewards[weth][gov] += (collectedFee - creatorFee);
                    launchpadMarket.virtualNativeReserve = uint112(
                        launchpadMarket.k / 200000000000000000000000000
                    );
                    uint256 oldTokenReserve = launchpadMarket
                        .virtualTokenReserve;
                    launchpadMarket.virtualTokenReserve = uint112(
                        (launchpadMarket.k +
                            launchpadMarket.virtualNativeReserve -
                            1) / launchpadMarket.virtualNativeReserve
                    );
                    outputAmount =
                        oldTokenReserve -
                        launchpadMarket.virtualTokenReserve;
                    IERC20(token).transfer(msg.sender, outputAmount);
                } else {
                    inputAmount =
                        (preFeeIn * 100000 + launchpadParams.launchpadFee - 1) /
                        launchpadParams.launchpadFee;
                    require(amountOut < launchpadMarket.virtualTokenReserve);
                    uint256 collectedFee = inputAmount - preFeeIn;
                    uint256 creatorFee = (collectedFee *
                        launchpadParams.launchpadCreatorFeeSplit) / 100;
                    claimableRewards[weth][
                        launchpadMarket.creator
                    ] += creatorFee;
                    claimableRewards[weth][gov] += (collectedFee - creatorFee);
                    launchpadMarket.virtualNativeReserve = uint112(newNative);
                    launchpadMarket.virtualTokenReserve = uint112(newToken);
                    IWETH(weth).deposit{value: inputAmount}();
                    outputAmount = amountOut;
                    IERC20(token).transfer(msg.sender, amountOut);
                    (bool success, ) = msg.sender.call{
                        value: msg.value - inputAmount
                    }("");
                    if (!success) {
                        revert ICrystal.TransferFailed(msg.sender);
                    }
                }
            }
            if (inputAmount != 0 && outputAmount != 0) {
                emit ICrystal.LaunchpadTrade(
                    token,
                    msg.sender,
                    true,
                    inputAmount,
                    outputAmount,
                    launchpadMarket.virtualNativeReserve,
                    launchpadMarket.virtualTokenReserve
                );
            }
            if (
                launchpadMarket.virtualNativeReserve >=
                ((launchpadMarket.k / 200000000000000000000000000))
            ) {
                // graduate
                address market = launchpadMarket.market;
                delete launchpadTokenToMarket[token];
                getMarketByTokens[weth][token] = market;
                getMarketByTokens[token][weth] = market;
                ICrystal.Market storage m = _getMarket[market];
                {
                    uint256 minSizeZeroes;
                    uint256 tempMinSize = launchpadParams.graduatedMinSize;
                    while (tempMinSize != 0 && tempMinSize % 10 == 0) {
                        tempMinSize /= 10;
                        ++minSizeZeroes;
                    }
                    (
                        m.lowestAsk,
                        m.minSize,
                        m.takerFee,
                        m.makerRebate,
                        m.createTimestamp
                    ) = (
                        uint80(1000000000000000),
                        uint40((tempMinSize << 20) | minSizeZeroes),
                        uint24(launchpadParams.graduatedTakerFee),
                        uint24(launchpadParams.graduatedMakerRebate),
                        uint88(block.timestamp)
                    ); // init market
                }
                emit ICrystal.Migrated(token);
                ICrystal.TokenMetadata memory qMeta = ICrystal.TokenMetadata(
                    weth,
                    IERC20(weth).decimals(),
                    IERC20(weth).symbol(),
                    IERC20(weth).name()
                );
                ICrystal.TokenMetadata memory bMeta = ICrystal.TokenMetadata(
                    token,
                    IERC20(token).decimals(),
                    IERC20(token).symbol(),
                    IERC20(token).name()
                );
                ICrystal.MarketDetails memory details = ICrystal.MarketDetails(
                    marketToMarketId[market],
                    3,
                    9,
                    1,
                    1000000000000000,
                    launchpadParams.graduatedMinSize,
                    uint24(launchpadParams.graduatedTakerFee),
                    uint24(launchpadParams.graduatedMakerRebate)
                );
                emit ICrystal.MarketCreated(
                    true,
                    weth,
                    token,
                    market,
                    qMeta,
                    bMeta,
                    details
                );
                emit ICrystal.Sync(market, m.reserveQuote, m.reserveBase);
                emit ICrystal.Mint(
                    market,
                    address(this),
                    m.reserveQuote,
                    m.reserveBase
                );
            }
        }
        if (isExactInput ? inputAmount < amountIn : outputAmount < amountOut) {
            // graduated, swap thru amm
            uint256 newInputAmount = (msg.value - inputAmount);
            IWETH(weth).deposit{value: newInputAmount}();
            {
                tokenBalances[0][weth] += newInputAmount;
            }
            if (!isExactInput) {
                newInputAmount = amountOut - outputAmount;
            }
            bytes memory ret = abi.encodeWithSelector(
                0xe690552b,
                true,
                isExactInput,
                (1 << 64),
                1,
                newInputAmount,
                MASK_KEEP_0_80,
                address(0),
                msg.sender
            );
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
            (newInputAmount, balance, ) = abi.decode(
                ret,
                (uint256, uint256, uint256)
            ); // avoid std
            inputAmount += newInputAmount;
            outputAmount += balance;
        }
        isExactInput
            ? require(outputAmount >= amountOut)
            : require(amountIn != 0 ? inputAmount <= amountIn : true);
        assembly {
            tstore(0x0, 0)
        }
        return (
            inputAmount,
            outputAmount,
            launchpadMarket.market == address(0)
        );
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
    function sell(
        bool isExactInput,
        address token,
        uint256 amountIn,
        uint256 amountOut
    ) external returns (uint256, uint256) {
        assembly {
            if tload(0x0) {
                revert(0, 0)
            }
            tstore(0x0, 1)
        }
        ICrystal.LaunchpadMarket
            storage launchpadMarket = launchpadTokenToMarket[token];
        uint256 inputAmount;
        uint256 outputAmount;
        if (launchpadMarket.virtualTokenReserve != 0) {
            if (isExactInput) {
                inputAmount = amountIn;
                CrystalToken(token).transferFrom(
                    msg.sender,
                    address(this),
                    amountIn
                );
                launchpadMarket.virtualTokenReserve += uint112(amountIn);
                uint256 oldNativeReserve = launchpadMarket.virtualNativeReserve;
                launchpadMarket.virtualNativeReserve = uint112(
                    (launchpadMarket.k +
                        launchpadMarket.virtualTokenReserve -
                        1) / launchpadMarket.virtualTokenReserve
                );
                outputAmount =
                    oldNativeReserve -
                    launchpadMarket.virtualNativeReserve;
                uint256 amountAfterFee = (outputAmount *
                    launchpadParams.launchpadFee) / 100000;
                uint256 collectedFee = outputAmount - amountAfterFee;
                uint256 creatorFee = (collectedFee *
                    launchpadParams.launchpadCreatorFeeSplit) / 100;
                claimableRewards[weth][launchpadMarket.creator] += creatorFee;
                claimableRewards[weth][gov] += (collectedFee - creatorFee);
                outputAmount = amountAfterFee;
                IWETH(weth).withdraw(outputAmount);
                (bool success, ) = msg.sender.call{value: outputAmount}("");
                if (!success) {
                    revert ICrystal.TransferFailed(msg.sender);
                }
            } else {
                uint256 outputAmountWithFee = (amountOut *
                    100000 +
                    launchpadParams.launchpadFee -
                    1) / launchpadParams.launchpadFee;
                uint256 newNative = launchpadMarket.virtualNativeReserve -
                    outputAmountWithFee;
                uint256 newToken = (launchpadMarket.k + newNative - 1) /
                    newNative;
                inputAmount = newToken - launchpadMarket.virtualTokenReserve;
                require(
                    outputAmountWithFee < launchpadMarket.virtualNativeReserve
                );
                IERC20(token).transferFrom(
                    msg.sender,
                    address(this),
                    inputAmount
                );
                launchpadMarket.virtualNativeReserve = uint112(newNative);
                launchpadMarket.virtualTokenReserve = uint112(newToken);
                uint256 collectedFee = outputAmountWithFee - amountOut;
                uint256 creatorFee = (collectedFee *
                    launchpadParams.launchpadCreatorFeeSplit) / 100;
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
                emit ICrystal.LaunchpadTrade(
                    token,
                    msg.sender,
                    false,
                    inputAmount,
                    outputAmount,
                    launchpadMarket.virtualNativeReserve,
                    launchpadMarket.virtualTokenReserve
                );
            }
        } else {
            uint256 newInputAmount = isExactInput ? amountIn : amountOut;
            bytes memory ret = abi.encodeWithSelector(
                0xe690552b,
                false,
                isExactInput,
                (1 << 60),
                1,
                newInputAmount,
                1,
                address(0),
                msg.sender
            );
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
            (inputAmount, outputAmount, ) = abi.decode(
                ret,
                (uint256, uint256, uint256)
            ); // avoid std
        }
        isExactInput
            ? require(outputAmount >= amountOut)
            : require(amountIn != 0 ? inputAmount <= amountIn : true);
        assembly {
            tstore(0x0, 0)
        }
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
    function quoteBuy(
        bool isExactInput,
        address token,
        uint256 amountIn,
        uint256 amountOut
    ) external returns (uint256, uint256, bool) {
        ICrystal.LaunchpadMarket
            storage launchpadMarket = launchpadTokenToMarket[token];
        uint256 inputAmount;
        uint256 outputAmount;
        bool graduated;
        address graduatedMarket;
        if (launchpadMarket.virtualTokenReserve != 0) {
            uint256 virtualNativeReserve;
            uint256 virtualTokenReserve;
            if (isExactInput) {
                inputAmount = amountIn;
                if (
                    launchpadMarket.virtualNativeReserve +
                        ((inputAmount * launchpadParams.launchpadFee) /
                            100000) >
                    (launchpadMarket.k / 200000000000000000000000000)
                ) {
                    inputAmount =
                        ((((launchpadMarket.k +
                            200000000000000000000000000 -
                            1) / 200000000000000000000000000) -
                            launchpadMarket.virtualNativeReserve) *
                            100000 +
                            launchpadParams.launchpadFee -
                            1) /
                        launchpadParams.launchpadFee;
                }
                uint256 amountAfterFee = (inputAmount *
                    launchpadParams.launchpadFee) / 100000;
                virtualNativeReserve =
                    launchpadMarket.virtualNativeReserve +
                    uint112(amountAfterFee);
                uint256 oldTokenReserve = launchpadMarket.virtualTokenReserve;
                virtualTokenReserve = uint112(
                    (launchpadMarket.k + virtualNativeReserve - 1) /
                        virtualNativeReserve
                );
                outputAmount = oldTokenReserve - virtualTokenReserve;
            } else {
                uint256 newToken = launchpadMarket.virtualTokenReserve -
                    amountOut;
                uint256 newNative = (uint256(launchpadMarket.k) +
                    newToken -
                    1) / newToken;
                uint256 preFeeIn = newNative -
                    launchpadMarket.virtualNativeReserve;
                if (
                    launchpadMarket.virtualNativeReserve + preFeeIn >
                    (launchpadMarket.k / 200000000000000000000000000)
                ) {
                    inputAmount =
                        ((((launchpadMarket.k +
                            200000000000000000000000000 -
                            1) / 200000000000000000000000000) -
                            launchpadMarket.virtualNativeReserve) *
                            100000 +
                            launchpadParams.launchpadFee -
                            1) /
                        launchpadParams.launchpadFee;
                    virtualNativeReserve = uint112(
                        launchpadMarket.k / 200000000000000000000000000
                    );
                    uint256 oldTokenReserve = launchpadMarket
                        .virtualTokenReserve;
                    virtualTokenReserve = uint112(
                        (launchpadMarket.k + virtualNativeReserve - 1) /
                            virtualNativeReserve
                    );
                    outputAmount = oldTokenReserve - virtualTokenReserve;
                } else {
                    inputAmount =
                        (preFeeIn * 100000 + launchpadParams.launchpadFee - 1) /
                        launchpadParams.launchpadFee;
                    require(amountOut < launchpadMarket.virtualTokenReserve);
                    virtualNativeReserve = uint112(newNative);
                    outputAmount = amountOut;
                }
            }
            if (
                virtualNativeReserve >=
                ((launchpadMarket.k / 200000000000000000000000000))
            ) {
                // graduate
                graduatedMarket = launchpadMarket.market;
                ICrystal.Market storage m = _getMarket[graduatedMarket];
                (
                    m.lowestAsk,
                    m.minSize,
                    m.takerFee,
                    m.makerRebate,
                    m.createTimestamp
                ) = (
                    uint80(1000000000000000),
                    uint40(0),
                    uint24(launchpadParams.graduatedTakerFee),
                    uint24(launchpadParams.graduatedMakerRebate),
                    uint88(0)
                ); // init market
                graduated = true;
            }
        }
        if (isExactInput ? inputAmount < amountIn : outputAmount < amountOut) {
            // graduated, swap thru amm
            uint256 newInputAmount = isExactInput
                ? (amountIn - inputAmount)
                : (amountOut - outputAmount);
            bytes memory ret = abi.encodeWithSelector(
                0x638571e3,
                true,
                isExactInput,
                true,
                newInputAmount,
                MASK_KEEP_0_80
            );
            bool result;
            graduatedMarket = graduatedMarket != address(0)
                ? graduatedMarket
                : getMarketByTokens[weth][token];
            if (
                graduatedMarket == address(0) || graduatedMarket == placeholder
            ) {
                revert ICrystal.InvalidMarket(weth, token);
            }
            (result, ret) = graduatedMarket.delegatecall(ret);
            if (!result) {
                revert ICrystal.ActionFailed();
            }
            uint256 newOutputAmount;
            (newInputAmount, newOutputAmount) = abi.decode(
                ret,
                (uint256, uint256)
            ); // avoid std
            inputAmount += newInputAmount;
            outputAmount += newOutputAmount;
        }
        isExactInput
            ? require(outputAmount >= amountOut)
            : require(amountIn != 0 ? inputAmount <= amountIn : true);
        if (graduated) {
            ICrystal.Market storage m = _getMarket[graduatedMarket];
            (
                m.lowestAsk,
                m.minSize,
                m.takerFee,
                m.makerRebate,
                m.createTimestamp
            ) = (uint80(0), uint40(0), uint24(0), uint24(0), uint88(0)); // un initialize market
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
    function quoteSell(
        bool isExactInput,
        address token,
        uint256 amountIn,
        uint256 amountOut
    ) external returns (uint256, uint256) {
        ICrystal.LaunchpadMarket
            storage launchpadMarket = launchpadTokenToMarket[token];
        uint256 inputAmount;
        uint256 outputAmount;
        if (launchpadMarket.virtualTokenReserve != 0) {
            uint256 virtualNativeReserve;
            uint256 virtualTokenReserve;
            if (isExactInput) {
                inputAmount = amountIn;
                virtualTokenReserve =
                    launchpadMarket.virtualTokenReserve +
                    uint112(amountIn);
                uint256 oldNativeReserve = launchpadMarket.virtualNativeReserve;
                virtualNativeReserve = uint112(
                    (launchpadMarket.k +
                        launchpadMarket.virtualTokenReserve -
                        1) / launchpadMarket.virtualTokenReserve
                );
                outputAmount = oldNativeReserve - virtualNativeReserve;
                uint256 amountAfterFee = (outputAmount *
                    launchpadParams.launchpadFee) / 100000;
                outputAmount = amountAfterFee;
            } else {
                uint256 outputAmountWithFee = (amountOut *
                    100000 +
                    launchpadParams.launchpadFee -
                    1) / launchpadParams.launchpadFee;
                uint256 newNative = launchpadMarket.virtualNativeReserve -
                    outputAmountWithFee;
                uint256 newToken = (launchpadMarket.k + newNative - 1) /
                    newNative;
                inputAmount = newToken - launchpadMarket.virtualTokenReserve;
                require(
                    outputAmountWithFee < launchpadMarket.virtualNativeReserve
                );
                outputAmount = amountOut;
            }
        } else {
            uint256 newInputAmount = isExactInput ? amountIn : amountOut;
            bytes memory ret = abi.encodeWithSelector(
                0x638571e3,
                false,
                isExactInput,
                true,
                newInputAmount,
                1
            );
            bool result;
            address market = getMarketByTokens[weth][token];
            if (market == address(0) || market == placeholder) {
                revert ICrystal.InvalidMarket(weth, token);
            }
            (result, ret) = market.delegatecall(ret);
            if (!result) {
                revert ICrystal.ActionFailed();
            }
            (inputAmount, outputAmount) = abi.decode(ret, (uint256, uint256)); // avoid std
        }
        isExactInput
            ? require(outputAmount >= amountOut)
            : require(amountIn != 0 ? inputAmount <= amountIn : true);
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
            require(
                msg.sender == gov &&
                    l.createTimestamp != 0 &&
                    block.timestamp > (l.createTimestamp + (86400 * 365))
            );
            pendingClosedMarkets[market] = block.timestamp;
        } else {
            ICrystal.Market storage m = _getMarket[market];
            require(
                msg.sender == gov &&
                    m.createTimestamp != 0 &&
                    block.timestamp > (m.createTimestamp + (86400 * 365))
            );
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
    function executeCloseInactiveMarket(
        address token
    ) external returns (uint256 amountQuote, uint256 amountBase) {
        address market = getMarketByTokens[weth][token];
        require(
            msg.sender == gov &&
                pendingClosedMarkets[market] != 0 &&
                block.timestamp >
                (pendingClosedMarkets[market] + (86400 * 7)) &&
                block.timestamp < (pendingClosedMarkets[market] + (86400 * 30))
        );
        if (market == address(0) || market == placeholder) {
            ICrystal.LaunchpadMarket storage l = launchpadTokenToMarket[token];
            IERC20(token).transfer(address(0), l.virtualTokenReserve);
            uint256 initialNativeReserve = l.k / 1000000000000000000000000000;
            if (l.virtualNativeReserve > initialNativeReserve) {
                claimableRewards[weth][gov] += (l.virtualNativeReserve -
                    initialNativeReserve);
            }
            delete launchpadTokenToMarket[token];
        } else {
            ICrystal.Market storage m = _getMarket[market];
            m.createTimestamp = 0;
            uint256 liquidity = IERC20(market).balanceOf(address(0));
            _getMarket[market].isAMMEnabled = false;
            IERC20(market).transferFrom(
                address(0),
                address(this),
                liquidity - 100000
            );
            (amountQuote, amountBase) = ICrystal(address(this)).removeLiquidity(
                market,
                address(this),
                liquidity - 100000,
                0,
                0
            );
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

    fallback() external payable {
        assembly {
            if tload(0x0) {
                revert(0, 0)
            }
            tstore(0x0, 1)
            mstore(0x40, 0xc0)
            mstore(0x00, caller())
            mstore(0x20, addressToUserId.slot)
            let userId := sload(keccak256(0x00, 0x40))
            if iszero(userId) {
                revert(0, 0)
            }
            let totalBribe := 0
            for {
                let offset := 0
            } lt(offset, calldatasize()) {

            } {
                let chunk := calldataload(offset) // balancemode << 252 | actioncount << 160 | market
                let market := and(
                    0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
                    chunk
                )
                let len := shl(5, and(0xFFF, shr(160, chunk)))
                let bribe := and(MASK_KEEP_0_80, shr(172, chunk))
                mstore(0x00, market)
                mstore(0x20, _getMarket.slot)
                if iszero(and(sload(keccak256(0x00, 0x40)), MASK_KEEP_80_160)) {
                    revert(0, 0)
                }
                mstore(0x80, or(shl(44, shr(252, chunk)), userId))
                calldatacopy(0xa0, add(offset, 0x20), len)
                let result := delegatecall(
                    gas(),
                    market,
                    0x80,
                    add(len, 0x20),
                    0,
                    0
                )
                if iszero(result) {
                    returndatacopy(0, 0, returndatasize())
                    revert(0, returndatasize())
                }
                totalBribe := add(totalBribe, bribe)
                offset := add(offset, add(len, 0x20))
            }
            if totalBribe {
                pop(call(gas(), coinbase(), totalBribe, 0, 0, 0, 0))
            }
            if and(callvalue(), selfbalance()) {
                pop(call(gas(), caller(), selfbalance(), 0, 0, 0, 0))
            }
            tstore(0x0, 0)
        }
    }

    receive() external payable {}
}
