// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC20} from './interfaces/IERC20.sol';
import {IWETH} from './interfaces/IWETH.sol';
import {ICrystal} from './interfaces/ICrystal.sol';
import {CrystalToken} from './CrystalToken.sol';
import {CrystalMarket} from './CrystalMarket.sol';

contract Crystal is ICrystal {
    address public feeRecipient;
    uint8 public feeCommission;
    uint8 public feeRebate;

    mapping (uint256 => address) public userIdToAddress;
    mapping (address => uint256) public addressToUserId;
    mapping (address => ICrystal.Market) private _getMarket;
    mapping (uint256 => uint256) private activated; // marketid << 128 | slotindex
    mapping (uint256 => uint256) private activated2; // marketid << 128 | slotindex2
    mapping (uint256 => uint256) private priceLevels; // 0 is an invalid price marketid << 128 | price
    mapping (uint256 => uint256) private orders; // 0 is an invalid cloid, valid range 1-1023 mask uint10; marketid << 128 | price << 48 | id or cloid << 41 | userid
    mapping (uint256 => uint256) private cloidVerify; // two cloids per slot map market and price, never zero slot
    mapping (uint256 => mapping (address => uint256)) private tokenBalances;
    mapping (address => mapping (address => uint256)) public claimableRewards;
    // router
    address public gov;
    uint256 public latestUserId; // first user id is 1 not 0, 0 is used internally by the router
    uint256 public feeClaimDuration;
    mapping (address => ICrystal.PendingExpiredFeeClaim) public pendingExpiredFeeClaims;
    mapping(address => bool) public isCanonicalDeployer;
    mapping(address => mapping(address => bool)) public approvedForwarder;
    mapping(address => uint256) public marketToMarketId; // uint48
    mapping(uint256 => address) public marketIdToMarket;
    mapping(address => mapping(address => address)) public getMarketByTokens; // market from input and output token, can be overriden
    address[] public allMarkets;
    ICrystal.Parameters public parameters;
    // launchpad
    ICrystal.LaunchpadParams public launchpadParams;
    mapping(address => ICrystal.LaunchpadMarket) public launchpadTokenToMarket;
    address[] public allTokens;

    address public immutable weth; 
    address public constant eth = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

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

    constructor(address _weth, address _gov, address _feeRecipient, uint8 _feeCommission, uint8 _feeRebate, uint256 _feeClaimDuration, ICrystal.LaunchpadParams memory _launchpadParams) {
        weth = _weth;
        gov = _gov;
        feeRecipient = _feeRecipient;
        feeCommission = _feeCommission;
        feeRebate = _feeRebate;
        feeClaimDuration = _feeClaimDuration;
        isCanonicalDeployer[_gov] = true;
        uint256 minSizeZeroes;
        uint256 minSize = _launchpadParams.graduatedMinSize;
        while (minSize != 0 && minSize % 10 == 0) {
            minSize /= 10;
            ++minSizeZeroes;
        }
        require((_feeCommission + _feeRebate) <= 50 && minSize < MASK_KEEP_0_20 && minSizeZeroes < MASK_KEEP_0_20 && _launchpadParams.launchpadInitialNativeSupply > 1e18 && 90000 <= _launchpadParams.launchpadFee && _launchpadParams.launchpadFee <= 100000 && 90000 <= _launchpadParams.graduatedTakerFee);
        require(_launchpadParams.graduatedTakerFee <= 100000 && 90000 <= _launchpadParams.graduatedMakerRebate && _launchpadParams.graduatedMakerRebate <= 100000 && _launchpadParams.graduatedCreatorFeeSplit <= 50 && _launchpadParams.launchpadCreatorFeeSplit <= 50);
        launchpadParams = _launchpadParams;
    }

    fallback() external payable {
        assembly {
            if tload(0x0) { revert(0, 0) }
            tstore(0x0, 1)
            mstore(0x40, 0xc0)
            mstore(0x00, caller())
            mstore(0x20, addressToUserId.slot)
            let userId := sload(keccak256(0x00, 0x40))
            if iszero(userId) { revert(0, 0) }
            let totalBribe := 0
            for { let offset := 0 } lt(offset, calldatasize()) { } {
                let chunk := calldataload(offset) // balancemode << 252 | actioncount << 160 | market
                let market := and(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, chunk)
                let len := shl(5, and(0xFFF, shr(160, chunk)))
                let bribe := and(MASK_KEEP_0_80, shr(172, chunk))
                mstore(0x00, market)
                mstore(0x20, _getMarket.slot)
                if iszero(sload(keccak256(0x00, 0x40))) { revert(0, 0) }
                mstore(0x80, or(shl(44, shr(252, chunk)), userId))
                calldatacopy(0xa0, add(offset, 0x20), len)
                let result := delegatecall(gas(), market, 0x80, add(len, 0x20), 0, 0)
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

    function _priceToTick(uint256 p, uint256 tickSize) internal pure returns (uint256) {
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

    function _registerUser(uint256 acctType, address user) internal returns (uint256 _latestUserId) { // 0 default 1 margin
        if (acctType == 0) {
            require(addressToUserId[user] == 0);
            _latestUserId = latestUserId;
            _latestUserId++;
            addressToUserId[user] = _latestUserId;
            userIdToAddress[_latestUserId] = user;
            latestUserId = _latestUserId;
            emit ICrystal.UserRegistered(false, user, _latestUserId);
        }
        else {
            revert ICrystal.AccountLimitReached();
        }
    }

    function _verifyMarketAndLock(address market) internal {
        assembly {
            mstore(0x00, market)
            mstore(0x20, _getMarket.slot)
            if iszero(and(sload(keccak256(0x00, 0x40)), MASK_KEEP_80_160)) { revert(0, 0) }
            if tload(0x0) { revert(0, 0) }
            tstore(0x0, 1)
        }
    }

    function _verifyUser(address user) internal view returns (address) {
        if (user == address(0)) {
            user = msg.sender;
        }
        else if (user != msg.sender && !approvedForwarder[user][msg.sender]) {
            revert ICrystal.Unauthorized(msg.sender);
        }
        return user;
    }

    function _delegateToMarket(address market, bytes4 selector, uint256 size, address user) internal returns (bytes memory) {
        _verifyMarketAndLock(market);
        assembly {
            mstore(0x80, selector)
            calldatacopy(0x84, 36, size)
            mstore(add(size, 0x84), user)
            let result := delegatecall(gas(), market, 0x80, add(4, add(size, mul(iszero(iszero(user)), 32))), 0, 0)
            returndatacopy(0x80, 0, returndatasize())
            switch result
            case 0 { revert(0x80, returndatasize()) }
            default {
                tstore(0x0, 0)
                return(0x80, returndatasize())
            }
        }
    }

    function allMarketsLength() external view returns (uint256) {
        return allMarkets.length;
    }

    function getMarket(address market) external view returns (ICrystal.MarketInfo memory info) {
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
            (marketInfo.minSize >> 20) * 10 ** (marketInfo.minSize & MASK_KEEP_0_20),
            marketInfo.takerFee,
            marketInfo.makerRebate,
            marketInfo.reserveQuote,
            marketInfo.reserveBase,
            marketInfo.isAMMEnabled
        );
    }

    function getDepositedBalance(address user, address asset) external view returns (uint256 totalBalance, uint256 availableBalance, uint256 lockedBalance) {
        uint256 tokenBalance = tokenBalances[addressToUserId[user]][asset];
        availableBalance = tokenBalance & MASK_KEEP_0_128;
        lockedBalance = tokenBalance >> 128;
        return (availableBalance + lockedBalance, availableBalance, lockedBalance);
    }

    function getAllOrdersByCloid(address user, uint256 range) external view returns (uint256[] memory cloids, ICrystal.Order[] memory userOrders) {
        uint256 userId = addressToUserId[user];
        uint256[] memory temp = new uint256[](range > 1024 ? 1024 : range);
        uint256 count;
        for (uint256 i = 1; i < (range > 1024 ? 1024 : range); ++i) {
            uint256 order = orders[(i << 41) | userId];
            if (order != 0) {
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

    function getOrderByCloid(uint256 userId, uint256 cloid) public view returns (ICrystal.Order memory) {
        uint256 order = orders[(cloid << 41) | userId];
        uint256 price = cloidVerify[((cloid | 1) << 41) | userId];
        uint256 marketId;
        if (cloid & 1 != 0) {
            marketId = ((price >> 80) & MASK_KEEP_0_48);
            price = price & MASK_KEEP_0_80;
        }
        else {
            marketId = ((price >> 208) & MASK_KEEP_0_48);
            price = (price >> 128) & MASK_KEEP_0_80;
        }
        address market = marketIdToMarket[marketId];
        return ICrystal.Order(price <= _getMarket[market].highestBid ? true : false, market, price, (order & MASK_KEEP_0_112), (order >> 112 & 0x1), (order >> 113 & MASK_KEEP_0_41), (order >> 154 & MASK_KEEP_0_51), (order >> 205 & MASK_KEEP_0_51));
    }
    
    function getOrder(address market, uint256 price, uint256 id) external view returns (ICrystal.Order memory) {
        uint256 order = orders[(marketToMarketId[market] << 128) | (price << 48) | id];
        return ICrystal.Order(price <= _getMarket[market].highestBid ? true : false, market, price, (order & MASK_KEEP_0_112), (order >> 112 & 0x1), (order >> 113 & MASK_KEEP_0_41), (order >> 154 & MASK_KEEP_0_51), (order >> 205 & MASK_KEEP_0_51));
    }

    function getPriceLevel(address market, uint256 price) external view returns (ICrystal.PriceLevel memory) {
        uint256 priceLevel = priceLevels[(marketToMarketId[market] << 128) | price];
        return ICrystal.PriceLevel((priceLevel & MASK_KEEP_0_112), (priceLevel >> 113 & MASK_KEEP_0_41), (priceLevel >> 154 & MASK_KEEP_0_51), (priceLevel >> 205 & MASK_KEEP_0_51));
    }
    // market methods
    function getPriceLevels(address market, bool isAscending, uint256 startPrice, uint256 distance, uint256 interval, uint256 max) external returns (bytes memory) {
        _delegateToMarket(market, 0x9c510697, 160, address(0));
    }

    function getPriceLevelsFromMid(address market, uint256 distance, uint256 interval, uint256 max) external returns (uint256 highestBid, uint256 lowestAsk, bytes memory, bytes memory) {
        _delegateToMarket(market, 0xd58887ae, 96, address(0));
    }

    function getPrice(address market) external returns (uint256 price, uint256 highestBid, uint256 lowestAsk) {
        _delegateToMarket(market, 0x98d5fdca, 0, address(0));
    }

    function getQuote(address market, bool isBuy, bool isExactInput, bool isCompleteFill, uint256 size, uint256 worstPrice) external returns (uint256 amountIn, uint256 amountOut) {
        _delegateToMarket(market, 0x638571e3, 160, address(0));
    }

    function getReserves(address market) external returns (uint112 reserveQuote, uint112 reserveBase) {
        _delegateToMarket(market, 0x0902f1ac, 0, address(0));
    }
    
    function addLiquidity(address market, address to, uint256 amountQuoteDesired, uint256 amountBaseDesired, uint256 amountQuoteMin, uint256 amountBaseMin) external payable returns (uint256 liquidity) {
        uint256 options;
        if (msg.value != 0) {
            IWETH(weth).deposit{value: msg.value}();
            uint256 balance = tokenBalances[0][weth] & MASK_KEEP_0_128;
            require((balance + msg.value) <= MASK_KEEP_0_128);
            tokenBalances[0][weth] = (balance + msg.value);
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
            case 0 { revert(0x80, returndatasize()) }
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

    function removeLiquidity(address market, address to, uint256 liquidity, uint256 amountQuoteMin, uint256 amountBaseMin) external returns (uint256 amountQuote, uint256 amountBase) {
        _delegateToMarket(market, 0x13928082, 160, address(0));
    }

    function removeLiquidityETH(address market, address to, uint256 liquidity, uint256 amountQuoteMin, uint256 amountBaseMin) external returns (uint256 amountQuote, uint256 amountBase) {
        uint256 options = _getMarket[market].quoteAsset == weth ? (1) : (1 << 4);
        _verifyMarketAndLock(market);
        assembly {
            mstore(0x80, shl(224, 0x13928082))
            calldatacopy(0x84, 36, 128)
            mstore(0x104, options)
            let result := delegatecall(gas(), market, 0x80, 164, 0, 0)
            returndatacopy(0x80, 0, returndatasize())
            switch result
            case 0 { revert(0x80, returndatasize()) }
            default {
                tstore(0x0, 0)
                amountQuote := mload(0x80)
                amountBase  := mload(add(0x80, 0x20))
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

    function marketOrder(address market, bool isBuy, bool isExactInput, uint256 options, uint256 orderType, uint256 size, uint256 worstPrice, address referrer, address user) external returns (uint256 amountIn, uint256 amountOut, uint256 id) {
        user = _verifyUser(user);
        _delegateToMarket(market, 0xe690552b, 224, user);
    }

    function limitOrder(address market, bool isBuy, uint256 options, uint256 price, uint256 size, address user) external returns (uint256 id) {
        user = _verifyUser(user);
        _delegateToMarket(market, 0x218a0c31, 128, user);
    }

    function cancelOrder(address market, uint256 options, uint256 price, uint256 id, address user) external returns (uint256 size) {
        user = _verifyUser(user);
        _delegateToMarket(market, 0xb69d86f7, 96, user);
    }

    function replaceOrder(address market, uint256 options, uint256 price, uint256 id, uint256 newPrice, uint256 size, address referrer, address user) external returns (uint256 _id) {
        user = _verifyUser(user);
        _delegateToMarket(market, 0x6c8dce79, 192, user);
    }

    function batchOrders(address market, ICrystal.Action[] calldata actions, uint256 options, uint256 deadline, address referrer, address user) external payable {
        user = _verifyUser(user);
        if (deadline < block.timestamp) {
            revert ICrystal.Expired(deadline);
        }
        if (msg.value != 0) {
            IWETH(weth).deposit{value: msg.value}();
            uint256 preBalance = tokenBalances[0][weth] & MASK_KEEP_0_128;
            require((preBalance + msg.value) <= MASK_KEEP_0_128);
            tokenBalances[0][weth] = (preBalance + msg.value);
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
            case 0 { revert(add(ret, 32), mload(ret)) }
            default {
                tstore(0x0, 0)
            }
        }
    }
    // non-market methods
    function changeGov(address newGov) external {
        if (msg.sender != gov) {
            revert ICrystal.Unauthorized(msg.sender);
        }
        gov = newGov;
        emit ICrystal.GovChanged(msg.sender, newGov);
    }

    function changeFeeRecipient(address newFeeRecipient) external {
        if (msg.sender != gov || newFeeRecipient == address(0)) {
            revert ICrystal.Unauthorized(msg.sender);
        }
        feeRecipient = newFeeRecipient;
    }

    function changeFeeClaimDuration(uint256 newFeeClaimDuration) external {
        if (msg.sender != gov) {
            revert ICrystal.Unauthorized(msg.sender);
        }
        require(newFeeClaimDuration > 86400);
        feeClaimDuration = newFeeClaimDuration;
    }

    function changeRefFeeStructure(uint8 newFeeCommission, uint8 newFeeRebate) external {
        if (msg.sender != gov) {
            revert ICrystal.Unauthorized(msg.sender);
        }
        require((newFeeCommission + newFeeRebate) <= 50);
        feeCommission = newFeeCommission;
        feeRebate = newFeeRebate;
    }

    function changeMarketParams(address market, uint256 newMinSize, uint24 newTakerFee, uint24 newMakerRebate, bool isAMMEnabled, bool isCanonical) external {
        require((isCanonicalDeployer[msg.sender] || msg.sender == gov) && 90000 <= newTakerFee && newTakerFee <= 100000 && 90000 <= newMakerRebate && newMakerRebate <= 100000);
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
        if (isCanonical && (getMarketByTokens[m.quoteAsset][m.baseAsset] == address(0) || msg.sender == gov)) {
            getMarketByTokens[m.quoteAsset][m.baseAsset] = market;
            getMarketByTokens[m.baseAsset][m.quoteAsset] = market;
        }
        else if (!isCanonical && getMarketByTokens[m.quoteAsset][m.baseAsset] == market) {
            getMarketByTokens[m.quoteAsset][m.baseAsset] = address(0);
            getMarketByTokens[m.baseAsset][m.quoteAsset] = address(0);
        }
        emit ICrystal.MarketParamsChanged(market, (m.minSize >> 20) * 10 ** (m.minSize & MASK_KEEP_0_20), newTakerFee, newMakerRebate, m.isAMMEnabled);
    }

    function changeMarketCreatorFee(address market, address newCreator, uint256 newCreatorFee) external {
        require(isCanonicalDeployer[msg.sender] || msg.sender == gov && newCreatorFee <= 50);
        ICrystal.Market storage m = _getMarket[market];
        if (msg.sender != gov && msg.sender != m.creator) {
            revert ICrystal.Unauthorized(msg.sender);
        }
        m.creator = newCreator;
        m.creatorFeeSplit = uint8(newCreatorFee);
    }

    function changeLaunchpadParams(ICrystal.LaunchpadParams memory newLaunchpadParams) external {
        if (msg.sender != gov) {
            revert ICrystal.Unauthorized(msg.sender);
        }
        uint256 minSizeZeroes;
        uint256 minSize = newLaunchpadParams.graduatedMinSize;
        while (minSize != 0 && minSize % 10 == 0) {
            minSize /= 10;
            ++minSizeZeroes;
        }
        require(minSize < MASK_KEEP_0_20 && minSizeZeroes < MASK_KEEP_0_20 && newLaunchpadParams.launchpadInitialNativeSupply > 1e18 && 90000 <= newLaunchpadParams.launchpadFee && newLaunchpadParams.launchpadFee <= 100000 && 90000 <= newLaunchpadParams.graduatedTakerFee);
        require(newLaunchpadParams.graduatedTakerFee <= 100000 && 90000 <= newLaunchpadParams.graduatedMakerRebate && newLaunchpadParams.graduatedMakerRebate <= 100000 && newLaunchpadParams.graduatedCreatorFeeSplit <= 50 && newLaunchpadParams.launchpadCreatorFeeSplit <= 50);
        launchpadParams = newLaunchpadParams;
    }

    function addCanonicalDeployer(address deployer) external {
        if (msg.sender != gov) {
            revert ICrystal.Unauthorized(msg.sender);
        }
        isCanonicalDeployer[deployer] = true;
    }

    function removeCanonicalDeployer(address deployer) external {
        if (msg.sender != gov) {
            revert ICrystal.Unauthorized(msg.sender);
        }
        isCanonicalDeployer[deployer] = false;
    }

    function approveForwarder(address forwarder) external {
        approvedForwarder[msg.sender][forwarder] = true;
    }

    function removeForwarder(address forwarder) external {
        approvedForwarder[msg.sender][forwarder] = false;
    }

    function registerUser(address user) external returns (uint256 userId) {
        if (msg.sender != user && msg.sender != address(this)) {
            revert ICrystal.Unauthorized(msg.sender);
        }
        userId = _registerUser(0, user);
    }

    function deposit(address token, uint256 amount) external payable returns (uint256 userId) {
        userId = addressToUserId[msg.sender];
        if (userId == 0) {
            userId = _registerUser(0, msg.sender);
        }
        if (token == eth) {
            token = weth;
            IWETH(weth).deposit{value: amount}();
        }
        else {
            IERC20(token).transferFrom(msg.sender, address(this), amount);
        }
        uint256 balance = tokenBalances[userId][token] & MASK_KEEP_0_128;
        require((balance + amount) <= MASK_KEEP_0_128);
        tokenBalances[userId][token] = (balance + amount);
        emit ICrystal.Deposit(msg.sender, userId, token, amount);
    }
    // if amount = 0 withdraw all
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
        if (uint128(balance) < amount) {
            revert ICrystal.ActionFailed();
        }
        else {
            tokenBalances[userId][token] = balance - amount;
        }
        if (isETH) {
            IWETH(weth).withdraw(amount);
            (bool success, ) = to.call{value: amount}("");
            if (!success) {
                revert ICrystal.TransferFailed(to);
            }
        }
        else {
            IERC20(token).transfer(to, amount);
        }
        emit ICrystal.Withdraw(msg.sender, userId, token, amount);
    }
    // incase a rent-like mechanism ever is added
    function clearCloidSlots(uint256 userId, uint256[] calldata ids) external {
        if (msg.sender != userIdToAddress[userId] && msg.sender != gov) {
            revert ICrystal.Unauthorized(msg.sender);
        }
        for (uint256 i; i < ids.length; ++i) {
            if (ids[i] & 1 != 0) {
                cloidVerify[((ids[i] | 1) << 41) | userId] &= MASK_OUT_0_128;
            }
            else {
                cloidVerify[((ids[i] | 1) << 41) | userId] &= MASK_KEEP_0_128;
            }
            if ((orders[(ids[i] << 41) | userId] & MASK_OUT_113_154) == 0) {
                delete orders[(ids[i] << 41) | userId];
            }
        }
    }
    // to make gas costs more deterministic
    function writeCloidSlots(uint256 userId, uint256[] calldata ids) external {
        if (msg.sender != userIdToAddress[userId]) {
            revert ICrystal.Unauthorized(msg.sender);
        }
        for (uint256 i; i < ids.length; ++i) {
            if (orders[(ids[i] << 41) | userId] == 0) {
                orders[(ids[i] << 41) | userId] |= (userId << 113);
                if (ids[i] & 1 != 0) {
                    cloidVerify[((ids[i] | 1) << 41) | userId] |= MASK_KEEP_0_128;
                }
                else {
                    cloidVerify[((ids[i] | 1) << 41) | userId] |= MASK_OUT_0_128;
                }
            }
        }
    }
    // to make gas costs more deterministic
    function writeSlots(address market, uint256[] calldata slotIndexes, uint256[] calldata slotIndexes2) external {
        for (uint256 i; i < slotIndexes.length; ++i) {
            activated[(marketToMarketId[market] << 128) | slotIndexes[i]] |= MASK_KEEP_255_256;
        }
        for (uint256 i; i < slotIndexes2.length; ++i) {
            activated2[(marketToMarketId[market] << 128) | slotIndexes2[i]] |= MASK_KEEP_255_256;
        }
    }
    // vault/margin operators can claim to their wallet, resets any pending expiry claims
    function claimFees(address to, address[] calldata tokens) external returns (uint256[] memory amounts) {
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
            }
            else {
                amounts[i] = claimableRewards[tokens[i]][msg.sender];
                claimableRewards[tokens[i]][msg.sender] = 0;
                IERC20(tokens[i]).transfer(to, amounts[i]);
            }
        }
        delete pendingExpiredFeeClaims[msg.sender];
        emit ICrystal.RewardsClaimed(msg.sender, tokens, amounts);      
    }
    // anyone can queue fee claim for if user is inactive, only governance can actually execute
    function queueClaimExpiredFees(address user, address[] calldata tokens) external {
        if (pendingExpiredFeeClaims[user].deadline != 0 && msg.sender != gov) {
            revert ICrystal.Unauthorized(msg.sender);
        }
        require(tokens.length < 100);
        uint256[] memory amounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            amounts[i] = claimableRewards[tokens[i]][user];
        }
        pendingExpiredFeeClaims[user].deadline = block.timestamp + feeClaimDuration;
        pendingExpiredFeeClaims[user].tokens = tokens;
        pendingExpiredFeeClaims[user].amounts = amounts;
    }
    // only governance can execute fee claim
    function executeClaimExpiredFees(address user) external returns (uint256[] memory amounts) {
        if (msg.sender != gov || block.timestamp < pendingExpiredFeeClaims[user].deadline) {
            revert ICrystal.Unauthorized(msg.sender);
        }
        amounts = pendingExpiredFeeClaims[user].amounts;
        for (uint256 i = 0; i < pendingExpiredFeeClaims[user].tokens.length; ++i) {
            claimableRewards[pendingExpiredFeeClaims[user].tokens[i]][user] -= amounts[i];
            IERC20(pendingExpiredFeeClaims[user].tokens[i]).transfer(msg.sender, amounts[i]);
        }
        delete pendingExpiredFeeClaims[user];
    }

    function deploy(bool isCanonical, address quoteAsset, address baseAsset, uint256 marketType, uint256 scaleFactor, uint256 tickSize, uint256 maxPrice, uint256 minSize, uint24 takerFee, uint24 makerRebate) external returns (address market) {
        if (isCanonical && !isCanonicalDeployer[msg.sender]) {
            revert ICrystal.Unauthorized(msg.sender);
        }
        if (quoteAsset == eth) {
            quoteAsset = weth;
        }
        else if (baseAsset == eth) {
            baseAsset = weth;
        }
        require(90000 <= takerFee && takerFee <= 100000 && 90000 <= makerRebate && makerRebate <= 100000); // validate all fee params, total fee is takerFee+makerRebate
        uint256 marketId = allMarkets.length + 1;
        {
            parameters = ICrystal.Parameters(quoteAsset, baseAsset, marketId, marketType, scaleFactor, tickSize, maxPrice); // maxsize is validated here
            uint256 maxTick;
            market = address(new CrystalMarket{salt: keccak256(abi.encode(marketId))}());
            if (marketType == 0) {
                require(maxPrice % tickSize == 0);
                maxTick = maxPrice / tickSize;
            }
            else if (marketType == 1 || marketType == 2 || marketType == 3) {
                maxTick = _priceToTick(maxPrice, tickSize);
            }
            else {
                revert ICrystal.ActionFailed();
            }
            delete parameters;
            ICrystal.Market storage m = _getMarket[market];
            (m.quoteAsset, m.baseAsset, m.marketId, m.scaleFactor, m.tickSize) = (quoteAsset, baseAsset, marketId, scaleFactor, tickSize); // immutable params but for _getMarket
            (m.takerFee, m.makerRebate, m.maxPrice, m.marketType, m.isAMMEnabled) = (takerFee, makerRebate, maxPrice, marketType, marketType > 1);
            (m.creator, m.creatorFeeSplit) = (msg.sender, uint8(launchpadParams.graduatedCreatorFeeSplit));
            m.lowestAsk = uint80(maxPrice);
            activated[(marketId << 128)] = 1; // index 0
            activated2[(marketId << 128)] = 1;
            activated[(marketId << 128) | (maxTick / 255)] = (1 << (maxTick % 255));
            activated2[(marketId << 128) | ((maxTick / 255) / 255)] = (1 << ((maxTick / 255) % 255));
            uint256 minSizeZeroes;
            uint256 tempMinSize = minSize;
            while (tempMinSize != 0 && tempMinSize % 10 == 0) {
                tempMinSize /= 10;
                ++minSizeZeroes;
            }
            require(tempMinSize < MASK_KEEP_0_20 && minSizeZeroes < MASK_KEEP_0_20 && marketId < MASK_KEEP_0_48); // minSize is encoded as bits 20-40 * 10 ** bits 0-20, marketid max uint48 minsize is variable to prevent dos
            m.minSize = uint40((tempMinSize << 20) | minSizeZeroes);
        }
        allMarkets.push(market);
        marketToMarketId[market] = marketId;
        marketIdToMarket[marketId] = market;
        require(launchpadTokenToMarket[baseAsset].virtualNativeReserve == 0);
        if (isCanonical) {
            getMarketByTokens[quoteAsset][baseAsset] = market;
            getMarketByTokens[baseAsset][quoteAsset] = market;
        }
        else {
            if (getMarketByTokens[quoteAsset][baseAsset] == address(0) && (marketType == 1 || marketType == 2)) {
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
        emit ICrystal.MarketCreated(_isCanonical, quoteAsset, baseAsset, market, qMeta, bMeta, details);
    }
    // router methods
    function getAmountsOut(uint256 amountIn, address[] memory path) external returns (uint256[] memory amounts) {
        if (path.length < 2) {
            revert ICrystal.InvalidPath(path);
        }
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i; i < path.length - 1; ++i) {
            address asset0 = path[i] == eth ? weth : path[i];
            address asset1 = path[i+1] == eth ? weth : path[i+1];
            address market = getMarketByTokens[asset0][asset1];
            if (market == address(0)) {
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

    function getAmountsIn(uint256 amountOut, address[] memory path) public returns (uint256[] memory amounts) {
        if (path.length < 2) {
            revert ICrystal.InvalidPath(path);
        }
        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint256 i = path.length - 1; i != 0; --i) {
            address asset0 = path[i-1] == eth ? weth : path[i-1];
            address asset1 = path[i] == eth ? weth : path[i];
            address market = getMarketByTokens[asset0][asset1];
            if (market == address(0)) {
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

    function exactInputSwap(uint256 amountIn, address[] memory path, address to, address referrer) internal returns (uint256[] memory amounts) {
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        assembly {
            if tload(0x0) { revert(0, 0) }
            tstore(0x0, 1)
        }
        for (uint256 i; i < path.length - 1; ++i) {
            address asset0 = path[i] == eth ? weth : path[i];
            address asset1 = path[i+1] == eth ? weth : path[i+1];
            address market = getMarketByTokens[asset0][asset1];
            if (market == address(0)) {
                revert ICrystal.InvalidMarket(asset0, asset1);
            }
            asset1 = _getMarket[market].quoteAsset;
            uint256 options = ((i != 0 || path[i] == eth) ? (1 << 64) : 0) | ((i != path.length - 2 || path[i+1] == eth || to != msg.sender) ? (1 << 60) : 0);
            bytes memory ret = abi.encodeWithSelector(0xe690552b, asset1 == asset0, true, options, 1, amounts[i], asset1 == asset0 ? MASK_KEEP_0_80 : 1, referrer, msg.sender);
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

    function exactOutputSwap(uint256[] memory amounts, address[] memory path, address to, address referrer) internal {
        assembly {
            if tload(0x0) { revert(0, 0) }
            tstore(0x0, 1)
        }
        for (uint256 i; i < path.length - 1; ++i) {
            address asset0 = path[i] == eth ? weth : path[i];
            address asset1 = path[i+1] == eth ? weth : path[i+1];
            address market = getMarketByTokens[asset0][asset1];
            if (market == address(0)) {
                revert ICrystal.InvalidMarket(asset0, asset1);
            }
            asset1 = _getMarket[market].quoteAsset;
            uint256 options = ((i != 0 || path[i] == eth) ? (1 << 64) : 0) | ((i != path.length - 2 || path[i+1] == eth || to != msg.sender) ? (1 << 60) : 0);
            bytes memory ret = abi.encodeWithSelector(0xe690552b, asset1 == asset0, false, options, 1, amounts[i+1], asset1 == asset0 ? MASK_KEEP_0_80 : 1, referrer, msg.sender);
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
    // anyone can deposit/withdraw from 0 slot, used as in between for multihop swaps
    function routerDeposit(address token, uint256 amount) external payable {
        if (token == eth) {
            token = weth;
            IWETH(weth).deposit{value: amount}();
        }
        else {
            IERC20(token).transferFrom(msg.sender, address(this), amount);
        }
        uint256 balance = tokenBalances[0][token] & MASK_KEEP_0_128;
        require((balance + amount) <= MASK_KEEP_0_128);
        tokenBalances[0][token] = (balance + amount);
    }
    // if amount = 0 withdraw all
    function routerWithdraw(address to, address token, uint256 amount) external {
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
        }
        else {
            tokenBalances[0][token] = balance - amount;
        }
        if (isETH) {
            IWETH(weth).withdraw(amount);
            (bool success, ) = to.call{value: amount}("");
            if (!success) {
                revert ICrystal.TransferFailed(to);
            }
        }
        else {
            IERC20(token).transfer(to, amount);
        }
    }

    function swapExactETHForTokens(uint256 amountOutMin, address[] memory path, address to, uint256 deadline, address referrer) external payable returns (uint256[] memory amounts) {
        if (path.length < 2 || path[0] != eth) {
            revert ICrystal.InvalidPath(path);
        }
        if (deadline < block.timestamp) {
            revert ICrystal.Expired(deadline);
        }
        IWETH(weth).deposit{value: msg.value}();
        uint256 preBalance = tokenBalances[0][weth] & MASK_KEEP_0_128;
        require((preBalance + msg.value) <= MASK_KEEP_0_128);
        tokenBalances[0][weth] = (preBalance + msg.value);
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
            }
            else {
                tokenBalances[0][token] = balance - amount;
            }
            IERC20(token).transfer(to, amount);
        }
    }

    function swapExactTokensForETH(uint256 amountIn, uint256 amountOutMin, address[] memory path, address to, uint256 deadline, address referrer) external returns (uint256[] memory amounts) {
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
        }
        else {
            tokenBalances[0][weth] = balance - amount;
        }
        IWETH(weth).withdraw(amount);
        (bool success, ) = to.call{value: amount}("");
        if (!success) {
            revert ICrystal.TransferFailed(to);
        }
    }

    function swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, address[] memory path, address to, uint256 deadline, address referrer) external returns (uint256[] memory amounts) {
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
            }
            else {
                tokenBalances[0][token] = balance - amount;
            }
            IERC20(token).transfer(to, amount);
        }
    }

    function swapETHForExactTokens(uint256 amountOut, address[] memory path, address to, uint256 deadline, address referrer) external payable returns (uint256[] memory amounts) {
        if (deadline < block.timestamp) {
            revert ICrystal.Expired(deadline);
        }
        if (path[0] != eth) {
            revert ICrystal.InvalidPath(path);
        }
        amounts = getAmountsIn(amountOut, path);
        if (amounts[0] > msg.value) {
            revert ICrystal.SlippageExceeded();
        }
        IWETH(weth).deposit{value: msg.value}();
        uint256 preBalance = tokenBalances[0][weth] & MASK_KEEP_0_128;
        require((preBalance + msg.value) <= MASK_KEEP_0_128);
        tokenBalances[0][weth] = (preBalance + msg.value);
        exactOutputSwap(amounts, path, to, referrer);
        if (to != msg.sender) {
            address token = path[path.length - 1];
            uint256 balance = tokenBalances[0][token];
            if (uint128(balance) < amountOut) {
                revert ICrystal.ActionFailed();
            }
            else {
                tokenBalances[0][token] = balance - amountOut;
            }
            IERC20(token).transfer(to, amountOut);
        }
        if (msg.value > amounts[0]) {
            uint256 amount = msg.value - amounts[0];
            uint256 balance = tokenBalances[0][weth];
            if (uint128(balance) < amount) {
                revert ICrystal.ActionFailed();
            }
            else {
                tokenBalances[0][weth] = balance - amount;
            }
            IWETH(weth).withdraw(amount);
            (bool success, ) = to.call{value: amount}("");
            if (!success) {
                revert ICrystal.TransferFailed(to);
            }         
        }
    }

    function swapTokensForExactETH(uint256 amountOut, uint256 amountInMax, address[] memory path, address to, uint256 deadline, address referrer) external returns (uint256[] memory amounts) {
        if (deadline < block.timestamp) {
            revert ICrystal.Expired(deadline);
        }
        if (path[path.length - 1] != eth) {
            revert ICrystal.InvalidPath(path);
        }
        amounts = getAmountsIn(amountOut, path);
        if (amounts[0] > amountInMax) {
            revert ICrystal.SlippageExceeded();
        }
        exactOutputSwap(amounts, path, to, referrer);
        uint256 balance = tokenBalances[0][weth];
        if (uint128(balance) < amountOut) {
            revert ICrystal.ActionFailed();
        }
        else {
            tokenBalances[0][weth] = balance - amountOut;
        }
        IWETH(weth).withdraw(amountOut);
        (bool success, ) = to.call{value: amountOut}("");
        if (!success) {
            revert ICrystal.TransferFailed(to);
        }
    }

    function swapTokensForExactTokens(uint256 amountOut, uint256 amountInMax, address[] memory path, address to, uint256 deadline, address referrer) external returns (uint256[] memory amounts) {
        if (deadline < block.timestamp) {
            revert ICrystal.Expired(deadline);
        }
        if (path[path.length - 1] == eth) {
            revert ICrystal.InvalidPath(path);
        }
        amounts = getAmountsIn(amountOut, path);
        if (amounts[0] > amountInMax) {
            revert ICrystal.SlippageExceeded();
        }
        exactOutputSwap(amounts, path, to, referrer);
        if (to != msg.sender) {
            address token = path[path.length - 1];
            uint256 balance = tokenBalances[0][token];
            if (uint128(balance) < amountOut) {
                revert ICrystal.ActionFailed();
            }
            else {
                tokenBalances[0][token] = balance - amountOut;
            }
            IERC20(token).transfer(to, amountOut);
        }
    }

    function swap(bool isExactInput, address tokenIn, address tokenOut, uint256 orderType, uint256 size, uint256 worstPrice, uint256 deadline, address referrer) external payable returns (uint256 userId, uint256 balance, uint256 id) {
        if (deadline < block.timestamp) {
            revert ICrystal.Expired(deadline);
        }
        address market = getMarketByTokens[tokenIn == eth ? weth : tokenIn][tokenOut == eth ? weth : tokenOut];    
        if (market == address(0)) {
            revert ICrystal.InvalidMarket(tokenIn == eth ? weth : tokenIn, tokenOut == eth ? weth : tokenOut);
        }
        if (tokenIn == eth) {
            IWETH(weth).deposit{value: msg.value}();
            balance = tokenBalances[0][weth];
            require((balance + msg.value) <= MASK_KEEP_0_128);
            tokenBalances[0][weth] = (balance + msg.value);
        }
        assembly {
            if tload(0x0) { revert(0, 0) }
            tstore(0x0, 1)
        }
        bool result = _getMarket[market].quoteAsset == (tokenIn == eth ? weth : tokenIn);
        deadline = ((tokenIn == eth) ? (1 << 64) : 0) | ((tokenOut == eth) ? (1 << 60) : 0);
        bytes memory ret = abi.encodeWithSelector(0xe690552b, result, isExactInput, deadline, orderType, size, worstPrice, referrer, msg.sender);
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

    function placeLimitOrder(address tokenIn, address tokenOut, uint256 price, uint256 size, uint256 deadline) external payable returns (uint256 id) {
        if (deadline < block.timestamp) {
            revert ICrystal.Expired(deadline);
        }
        bool isETHIn = tokenIn == eth;
        address asset0 = isETHIn ? weth : tokenIn;
        address asset1 = tokenOut == eth ? weth : tokenOut;
        address market = getMarketByTokens[asset0][asset1];    
        if (market == address(0)) {
            revert ICrystal.InvalidMarket(asset0, asset1);
        }
        if (isETHIn) {
            IWETH(weth).deposit{value: msg.value}();
            uint256 balance = tokenBalances[0][weth] & MASK_KEEP_0_128;
            require((balance + msg.value) <= MASK_KEEP_0_128);
            tokenBalances[0][weth] = (balance + msg.value);
        }
        assembly {
            if tload(0x0) { revert(0, 0) }
            tstore(0x0, 1)
        }
        uint256 options = (isETHIn ? (1 << 56) : 0);
        (bool result, bytes memory ret) = market.delegatecall(abi.encodeWithSelector(0x218a0c31, _getMarket[market].quoteAsset == asset0, options, price, size, msg.sender));
        if (!result) {
            revert ICrystal.ActionFailed();
        }
        id = abi.decode(ret, (uint256));
        assembly {
            tstore(0x0, 0)
        }
    }

    function cancelLimitOrder(address tokenIn, address tokenOut, uint256 price, uint256 id, uint256 deadline) external returns (uint256 size) {
        if (deadline < block.timestamp) {
            revert ICrystal.Expired(deadline);
        }
        bool isETHIn = tokenIn == eth;
        address asset0 = isETHIn ? weth : tokenIn;
        address asset1 = tokenOut == eth ? weth : tokenOut;
        address market = getMarketByTokens[asset0][asset1];    
        if (market == address(0)) {
            revert ICrystal.InvalidMarket(asset0, asset1);
        }
        assembly {
            if tload(0x0) { revert(0, 0) }
            tstore(0x0, 1)
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
            }
            else {
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

    function replaceOrder(bool isPostOnly, bool isDecrease, address tokenIn, address tokenOut, uint256 price, uint256 id, uint256 newPrice, uint256 newSize, uint256 deadline, address referrer) external payable returns (uint256) {
        if (deadline < block.timestamp) {
            revert ICrystal.Expired(deadline);
        }
        address market = getMarketByTokens[tokenIn == eth ? weth : tokenIn][tokenOut == eth ? weth : tokenOut];    
        if (market == address(0)) {
            revert ICrystal.InvalidMarket(tokenIn == eth ? weth : tokenIn, tokenOut == eth ? weth : tokenOut);
        }
        if (tokenIn == eth) {
            IWETH(weth).deposit{value: msg.value}();
            uint256 balance = tokenBalances[0][weth] & MASK_KEEP_0_128;
            require((balance + msg.value) <= MASK_KEEP_0_128);
            tokenBalances[0][weth] = (balance + msg.value);
        }
        assembly {
            if tload(0x0) { revert(0, 0) }
            tstore(0x0, 1)
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
        assembly {
            tstore(0x0, 0)
        }
        return id;
    }

    function multiBatchOrders(ICrystal.Batch[] calldata batches, uint256 deadline, address referrer) external payable {
        if (deadline < block.timestamp) {
            revert ICrystal.Expired(deadline);
        }
        if (msg.value != 0) {
            IWETH(weth).deposit{value: msg.value}();
            uint256 preBalance = tokenBalances[0][weth] & MASK_KEEP_0_128;
            require((preBalance + msg.value) <= MASK_KEEP_0_128);
            tokenBalances[0][weth] = (preBalance + msg.value);
        }
        assembly {
            if tload(0x0) { revert(0, 0) }
            tstore(0x0, 1)
        }
        for (uint256 i; i < batches.length; ++i) {
            address market = batches[i].market;
            assembly {
                mstore(0x00, market)
                mstore(0x20, _getMarket.slot)
                if iszero(sload(keccak256(0x00, 0x40))) { revert(0, 0) }
            }
            (bool result, bytes memory ret) = market.delegatecall(
                abi.encodeWithSelector(0x5c2a91ec, batches[i].actions, batches[i].options, referrer, msg.sender)
            );
            assembly {
                switch result
                case 0 { revert(add(ret, 32), mload(ret)) }
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
    // launchpad
    function getVirtualReserves(address token) external view returns (uint256 virtualNativeReserve, uint256 virtualTokenReserve) {
        ICrystal.LaunchpadMarket storage market = launchpadTokenToMarket[token];
        (virtualNativeReserve, virtualTokenReserve) = (market.virtualNativeReserve, market.virtualTokenReserve);
    }

    function createToken(string memory name, string memory symbol, string memory metadataCID, string memory description, string memory social1, string memory social2, string memory social3, string memory social4) external returns (address token) {
        assembly {
            if tload(0x0) { revert(0, 0) }
            tstore(0x0, 1)
        }
        token = address(new CrystalToken(
            address(this),
            name,
            symbol,
            metadataCID,
            description,
            social1,
            social2,
            social3,
            social4
        ));
        allTokens.push(address(token));
        emit ICrystal.TokenCreated(address(token), msg.sender, name, symbol, metadataCID, description, social1, social2, social3, social4);
        uint256 marketId = allMarkets.length + 1;
        parameters = ICrystal.Parameters(weth, token, marketId, 3, 9, 1, 1000000000000000); // maxsize is validated here
        uint256 maxTick;
        address market;
        market = address(new CrystalMarket{salt: keccak256(abi.encode(marketId))}()); // can't be traded yet as slot 0 in mapping isn't initialized, and is not in getmarketbyassets either
        maxTick = _priceToTick(1000000000000000, 1);
        delete parameters;
        ICrystal.Market storage m = _getMarket[market];
        (m.quoteAsset, m.baseAsset, m.marketId, m.scaleFactor, m.tickSize) = (weth, token, marketId, 9, 1); // immutable params but for _getMarket
        (m.maxPrice, m.marketType, m.creator, m.creatorFeeSplit, m.isAMMEnabled) = (1000000000000000, 3, msg.sender, uint8(launchpadParams.graduatedCreatorFeeSplit), true);
        activated[(marketId << 128)] = 1; // index 0
        activated2[(marketId << 128)] = 1;
        activated[(marketId << 128) | (maxTick / 255)] = (1 << (maxTick % 255));
        activated2[(marketId << 128) | ((maxTick / 255) / 255)] = (1 << ((maxTick / 255) % 255));
        allMarkets.push(market);
        marketToMarketId[market] = marketId;
        marketIdToMarket[marketId] = market;
        launchpadTokenToMarket[address(token)] = ICrystal.LaunchpadMarket(launchpadParams.launchpadInitialNativeSupply, 1000000000000000000000000000, uint256(launchpadParams.launchpadInitialNativeSupply) * 1000000000000000000000000000, msg.sender, market, uint88(block.timestamp));
        (bool result, bytes memory ret) = market.delegatecall(
            abi.encodeWithSelector(0xf7bb5c88, address(this), (1000000000000000000000000000 * uint256(launchpadParams.launchpadInitialNativeSupply) / 200000000000000000000000000) - uint256(launchpadParams.launchpadInitialNativeSupply), 200000000000000000000000000) // premint
        );
        if (!result) {
            revert ICrystal.ActionFailed();
        }
        (uint256 liquidity) = abi.decode(ret, (uint256));
        IERC20(market).transfer(address(0), liquidity);
        assembly {
            tstore(0x0, 0)
        }
    }

    function buy(bool isExactInput, address token, uint256 amountIn, uint256 amountOut) external payable returns (uint256, uint256, bool) {
        assembly {
            if tload(0x0) { revert(0, 0) }
            tstore(0x0, 1)
        }
        ICrystal.LaunchpadMarket storage launchpadMarket = launchpadTokenToMarket[token];
        uint256 inputAmount;
        uint256 outputAmount;
        if (launchpadMarket.virtualTokenReserve != 0) {
            if (isExactInput) {
                inputAmount = amountIn;
                require(msg.value == inputAmount);
                if (launchpadMarket.virtualNativeReserve + ((inputAmount * launchpadParams.launchpadFee) / 100000) > (launchpadMarket.k / 200000000000000000000000000)) {
                    inputAmount = (((launchpadMarket.k / 200000000000000000000000000) - launchpadMarket.virtualNativeReserve) * 100000 + launchpadParams.launchpadFee - 1) / launchpadParams.launchpadFee;
                }
                IWETH(weth).deposit{value: inputAmount}();
                uint256 amountAfterFee = (inputAmount * launchpadParams.launchpadFee) / 100000;
                uint256 collectedFee = inputAmount - amountAfterFee;
                uint256 creatorFee = collectedFee * launchpadParams.launchpadCreatorFeeSplit / 100;
                claimableRewards[weth][launchpadMarket.creator] += creatorFee;
                claimableRewards[weth][gov] += (collectedFee - creatorFee);
                launchpadMarket.virtualNativeReserve += uint112(amountAfterFee);
                uint256 oldTokenReserve = launchpadMarket.virtualTokenReserve;
                launchpadMarket.virtualTokenReserve = uint112(launchpadMarket.k / launchpadMarket.virtualNativeReserve);
                outputAmount = oldTokenReserve - launchpadMarket.virtualTokenReserve;
                IERC20(token).transfer(msg.sender, outputAmount);
            }
            else {
                uint256 newToken = launchpadMarket.virtualTokenReserve - amountOut;
                uint256 newNative = uint256(launchpadMarket.k) / newToken;
                uint256 preFeeIn = newNative - launchpadMarket.virtualNativeReserve;
                if (launchpadMarket.virtualNativeReserve + preFeeIn > (launchpadMarket.k / 200000000000000000000000000)) {
                    inputAmount = (((launchpadMarket.k / 200000000000000000000000000) - launchpadMarket.virtualNativeReserve) * 100000 + launchpadParams.launchpadFee - 1) / launchpadParams.launchpadFee;
                    IWETH(weth).deposit{value: inputAmount}();
                    uint256 collectedFee = inputAmount - ((inputAmount * launchpadParams.launchpadFee) / 100000);
                    uint256 creatorFee = collectedFee * launchpadParams.launchpadCreatorFeeSplit / 100;
                    claimableRewards[weth][launchpadMarket.creator] += creatorFee;
                    claimableRewards[weth][gov] += (collectedFee - creatorFee);
                    launchpadMarket.virtualNativeReserve = uint112(launchpadMarket.k / 200000000000000000000000000);
                    uint256 oldTokenReserve = launchpadMarket.virtualTokenReserve;
                    launchpadMarket.virtualTokenReserve = uint112(launchpadMarket.k / launchpadMarket.virtualNativeReserve);
                    outputAmount = oldTokenReserve - launchpadMarket.virtualTokenReserve;
                    IERC20(token).transfer(msg.sender, outputAmount);
                }
                else {
                    inputAmount = (preFeeIn * 100000 + launchpadParams.launchpadFee - 1) / launchpadParams.launchpadFee;
                    require(amountOut < launchpadMarket.virtualTokenReserve && inputAmount <= amountIn);
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
            emit ICrystal.LaunchpadTrade(token, msg.sender, true, inputAmount, outputAmount, launchpadMarket.virtualNativeReserve, launchpadMarket.virtualTokenReserve);
            if (launchpadMarket.virtualNativeReserve >= ((launchpadMarket.k / 200000000000000000000000000))) { // graduate
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
                    (m.lowestAsk, m.minSize, m.takerFee, m.makerRebate, m.createTimestamp) = (uint80(1000000000000000), uint40((tempMinSize << 20) | minSizeZeroes), uint24(launchpadParams.graduatedTakerFee), uint24(launchpadParams.graduatedMakerRebate), uint88(block.timestamp)); // init market
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
                    2,
                    9,
                    1,
                    1000000000000000,
                    launchpadParams.graduatedMinSize,
                    uint24(launchpadParams.graduatedTakerFee),
                    uint24(launchpadParams.graduatedMakerRebate)
                );
                emit ICrystal.MarketCreated(true, weth, token, market, qMeta, bMeta, details);
                emit ICrystal.Sync(market, m.reserveQuote, m.reserveBase);
                emit ICrystal.Mint(market, address(this), m.reserveQuote, m.reserveBase);
            }
        }
        if (isExactInput ? inputAmount < amountIn : outputAmount < amountOut) { // graduated, swap thru amm
            uint256 newInputAmount = (msg.value - inputAmount);
            IWETH(weth).deposit{value: newInputAmount}();
            {
                uint256 preBalance = tokenBalances[0][weth] & MASK_KEEP_0_128;
                require((preBalance + newInputAmount) <= MASK_KEEP_0_128);
                tokenBalances[0][weth] = (preBalance + newInputAmount);
            }
            if (!isExactInput) {
                newInputAmount = amountOut - outputAmount;
            }
            bool result;
            bytes memory ret = abi.encodeWithSelector(0xe690552b, true, isExactInput, (1 << 64), 1, newInputAmount, MASK_KEEP_0_80, address(0), msg.sender);
            address market = getMarketByTokens[weth][token];    
            if (market == address(0)) {
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
            (newInputAmount, balance, ) = abi.decode(ret, (uint256, uint256, uint256)); // avoid std
            isExactInput ? outputAmount += balance : inputAmount += newInputAmount;
        }
        isExactInput ? require(outputAmount >= amountOut) : require(inputAmount <= amountIn);
        assembly {
            tstore(0x0, 0)
        }
        return (amountIn, amountOut, launchpadMarket.market == address(0));
    }

    function sell(bool isExactInput, address token, uint256 amountIn, uint256 amountOut) external returns (uint256, uint256) {
        assembly {
            if tload(0x0) { revert(0, 0) }
            tstore(0x0, 1)
        }
        ICrystal.LaunchpadMarket storage launchpadMarket = launchpadTokenToMarket[token];
        uint256 inputAmount;
        uint256 outputAmount;
        if (launchpadMarket.virtualTokenReserve != 0) {
            if (isExactInput) {
                inputAmount = amountIn;
                CrystalToken(token).transferFrom(msg.sender, address(this), amountIn);
                launchpadMarket.virtualTokenReserve += uint112(amountIn);
                uint256 oldNativeReserve = launchpadMarket.virtualNativeReserve;
                launchpadMarket.virtualNativeReserve = uint112(launchpadMarket.k / launchpadMarket.virtualTokenReserve);
                outputAmount = oldNativeReserve - launchpadMarket.virtualNativeReserve;
                uint256 amountAfterFee = (outputAmount * launchpadParams.launchpadFee) / 100000;
                uint256 collectedFee = outputAmount - amountAfterFee;
                uint256 creatorFee = collectedFee * launchpadParams.launchpadCreatorFeeSplit / 100;
                claimableRewards[weth][launchpadMarket.creator] += creatorFee;
                claimableRewards[weth][gov] += (collectedFee - creatorFee);
                outputAmount = amountAfterFee;
                require(outputAmount >= amountOut);
                IWETH(weth).withdraw(outputAmount);
                (bool success, ) = msg.sender.call{value: outputAmount}("");
                if (!success) {
                    revert ICrystal.TransferFailed(msg.sender);
                }
            }
            else {
                uint256 outputAmountWithFee = (amountOut * 100000 + launchpadParams.launchpadFee - 1) / launchpadParams.launchpadFee;
                uint256 newNative = launchpadMarket.virtualNativeReserve - outputAmountWithFee;
                uint256 newToken = launchpadMarket.k / newNative;
                inputAmount = newToken - launchpadMarket.virtualTokenReserve;
                require(outputAmountWithFee < launchpadMarket.virtualNativeReserve && inputAmount <= amountIn);
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
            emit ICrystal.LaunchpadTrade(token, msg.sender, false, inputAmount, outputAmount, launchpadMarket.virtualNativeReserve, launchpadMarket.virtualTokenReserve);
        }
        else {
            if (isExactInput ? inputAmount < amountIn : outputAmount < amountOut) { // graduated, swap thru amm
                uint256 newInputAmount = amountIn;
                if (!isExactInput) {
                    newInputAmount = amountOut;
                }
                bool result;
                bytes memory ret = abi.encodeWithSelector(0xe690552b, false, isExactInput, (1 << 60), 1, newInputAmount, 1, address(0), msg.sender);
                address market = getMarketByTokens[weth][token];    
                if (market == address(0)) {
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
                (newInputAmount, balance, ) = abi.decode(ret, (uint256, uint256, uint256)); // avoid std
                isExactInput ? require(balance >= amountOut) : require(newInputAmount <= amountIn);
            }
        }
        assembly {
            tstore(0x0, 0)
        }
        return (amountIn, amountOut);
    }

    function close(address token) external returns (uint256 amountQuote, uint256 amountBase) {
        address market = getMarketByTokens[weth][token];    
        if (market == address(0)) {
            ICrystal.LaunchpadMarket storage l = launchpadTokenToMarket[token];
            require(msg.sender == gov && l.createTimestamp != 0 && block.timestamp > (l.createTimestamp + (86400 * 365)));
            IERC20(token).transfer(address(0), l.virtualTokenReserve);
            uint256 initialNativeReserve = l.k / 1000000000000000000000000000;
            if (l.virtualNativeReserve > initialNativeReserve) {
                claimableRewards[weth][gov] = l.virtualNativeReserve - initialNativeReserve;
            }
            delete launchpadTokenToMarket[token];
        }
        else {
            ICrystal.Market storage m = _getMarket[market];
            require(msg.sender == gov && m.createTimestamp != 0 && block.timestamp > (m.createTimestamp + (86400 * 365)));
            uint256 liquidity = IERC20(market).balanceOf(address(0));
            IERC20(market).transferFrom(address(0), address(this), liquidity);
            (amountQuote, amountBase) = ICrystal(address(this)).removeLiquidity(market, address(this), liquidity, 0, 0);
            claimableRewards[m.quoteAsset][gov] = amountQuote;
            claimableRewards[m.baseAsset][gov] = amountBase;
        }
    }

    function lock(address market) external {
        require(msg.sender == gov);
        _getMarket[market].createTimestamp = 0;
    }
}