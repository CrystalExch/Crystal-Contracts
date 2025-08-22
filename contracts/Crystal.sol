// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;
import "hardhat/console.sol";

import {IERC20} from './interfaces/IERC20.sol';
import {IWETH} from './interfaces/IWETH.sol';
import {ICrystal} from './interfaces/ICrystal.sol';
import {CrystalToken} from './CrystalToken.sol';
import {CrystalMarket0Factory} from './factories/CrystalMarket0Factory.sol';
import {CrystalMarket1Factory} from './factories/CrystalMarket1Factory.sol';
import {CrystalMarket2Factory} from './factories/CrystalMarket2Factory.sol';

contract Crystal {
    struct InternalOrder { //  bit is if maker wants internal balance (1) or tokens (0) order is stored at either marketid << 128 | price << 48 | id or cloid << 41 | userid; no collision because marketid seperates cloid orders from non cloid, userid prevents cloid collisions, and price n id are always unique
        uint256 size; // uint112 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF
        uint256 orderType; // uint1 0x1
        uint256 userId; // uint41 0x1FFFFFFFFFF
        uint256 fillBefore; // uint51 0x7FFFFFFFFFFFF
        uint256 fillAfter; // uint51 0x7FFFFFFFFFFFF
    }

    struct Market {
        uint80 highestBid;
        uint80 lowestAsk;
        uint40 minSize;
        uint24 takerFee;
        uint24 makerRebate;
        bool isAMMEnabled;

        uint112 reserveQuote;
        uint112 reserveBase;
        
        address quoteAsset;
        address baseAsset;
        uint256 marketId;
        uint256 marketType;
        uint256 scaleFactor;
        uint256 tickSize;
        uint256 maxPrice;
        address creator;
        uint8 creatorFeeSplit;
    }

    struct MarketInfo {
        address quoteAsset;
        address baseAsset;
        uint256 marketType;
        uint256 highestBid;
        uint256 lowestAsk;
        uint256 scaleFactor;
        uint256 tickSize;
        uint256 maxPrice;
        uint256 minSize;
        uint256 takerFee;
        uint256 makerRebate;
        uint256 reserveQuote;
        uint256 reserveBase;
        bool isAMMEnabled;
    }

    struct PriceLevel { 
        uint256 size; // uint112 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF
        // gap uint1 0x1
        uint256 latestNativeId; // uint41 0x1FFFFFFFFFF
        uint256 latest; // uint51 0x7FFFFFFFFFFFF
        uint256 fillNext; // uint51 0x7FFFFFFFFFFFF
    }

    struct Order { //  bit is if maker wants internal balance (1) or tokens (0) order is stored at either marketid << 128 | price << 48 | id or cloid << 41 | userid; no collision because marketid seperates cloid orders from non cloid, userid prevents cloid collisions, and price n id are always unique
        bool isBuy;
        address market;    
        uint256 price; //uint80 0xFFFFFFFFFFFFFFFFFFFF
        uint256 size; //uint112 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF
        uint256 orderType; //uint1 0x1
        uint256 userId; // uint41 0x1FFFFFFFFFF
        uint256 fillBefore; // uint51 0x7FFFFFFFFFFFF
        uint256 fillAfter; // uint51 0x7FFFFFFFFFFFF
    }

    struct Action {
        bool isRequireSuccess;
        uint256 action;
        uint256 param1; // price
        uint256 param2; // size/id
        uint256 param3; // cloid
    }

    struct Batch {
        address market;
        Action[] actions;
        uint256 options;
    }

    struct Parameters {
        address quoteAsset;
        address baseAsset;
        uint256 marketId; // uint128
        uint256 scaleFactor; // uint127
        uint256 tickSize; // uint80
        uint256 maxPrice; // uint80
    }

    struct TriggerOrder {
        uint256 userId;
        uint256 executionPrice;
        bool isBuy;
        bool isExactInput;
        uint256 options;
        uint256 orderType;
        uint256 size;
        uint256 worstPrice;
        address referrer;
    }

    struct DCAOrder {
        uint256 userId;
        uint256 suborderCount;
        uint256 startTime;
        uint256 interval;
        uint256 currentSuborder;
        bool isBuy;
        bool isExactInput;
        uint256 options;
        uint256 totalSize;
        uint256 executedSize;
        address referrer;
    }

    struct LaunchpadMarket {
        uint112 virtualNativeReserve;
        uint112 virtualTokenReserve;
        uint256 k;
        address creator;
        address market;
    }

    struct LaunchpadParams {
        uint112 launchpadInitialNativeSupply;
        uint256 launchpadFee;
        uint256 launchpadCreatorFeeSplit;
        uint256 graduatedMinSize;
        uint256 graduatedTakerFee;
        uint256 graduatedMakerRebate;
        uint256 graduatedCreatorFeeSplit;
    }

    struct PendingExpiredFeeClaim {
        uint256 deadline;
        address[] tokens;
        uint256[] amounts;
    }
    
    // market
    address public feeRecipient;
    uint8 public feeCommission;
    uint8 public feeRebate;

    mapping (uint256 => address) public userIdToAddress; // 0 is an invalid userid
    mapping (address => uint256) public addressToUserId;
    mapping (address => Market) private _getMarket;
    mapping (uint256 => uint256) activated; // marketid << 128 | slotindex
    mapping (uint256 => uint256) priceLevels; // 0 is an invalid price marketid << 128 | price
    mapping (uint256 => uint256) orders; // 0 is an invalid cloid, valid range 1-1023 mask 0x3FF; marketid << 128 | price << 48 | id or cloid << 41 | userid
    mapping (uint256 => uint256) cloidVerify; // two cloids per slot map market and price, never zero slot
    mapping (uint256 => mapping (address => uint256)) tokenBalances;
    mapping (address => mapping (address => uint256)) public claimableRewards;
    // router
    uint256 public latestUserId; // starts with 1
    address public gov;
    uint256 public feeClaimDuration;
    mapping (address => PendingExpiredFeeClaim) public pendingExpiredFeeClaims;
    mapping (address => uint256) public marginAccounts; // max 6 per address, uint41
    mapping(address => mapping(address => address)) public getMarketByTokens; // market from input and output token, can be overriden
    mapping(address => uint256) public marketToMarketId; // uint48
    mapping(uint256 => address) public marketIdToMarket;
    mapping(address => bool) public isCanonicalDeployer;
    mapping(address => bool) public isKeeper;
    address[] public allMarkets;
    Parameters public parameters;
    // launchpad
    LaunchpadParams public launchpadParams;
    mapping(address => LaunchpadMarket) public launchpadTokenToMarket;
    address[] public allTokens;
    // referrals
    mapping(string => address) public refCodeToAddress;
    mapping(address => string) public addressToRefCode;
    mapping(address => uint256) public referrerToReferredAddressCount;
    mapping(address => address) public addressToReferrer;
    // factory
    address[] public factories;

    address public immutable weth; 
    address public immutable eth = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    event MarketCreated(address indexed quoteAsset, address indexed baseAsset, address market, uint256 marketId, uint256 marketType, uint256 scaleFactor, uint256 tickSize, uint256 maxPrice, uint256 minSize, uint24 takerFee, uint24 makerRebate);
    event MarketParamsChanged(address indexed market, uint256 minSize, uint24 takerFee, uint24 makerRebate, bool isAMMEnabled);
    event GovChanged(address prev, address gov);
    event UserRegistered(bool indexed isMargin, address indexed caller, uint256 indexed userId);
    event Deposit(address indexed caller, uint256 indexed userId, address indexed token, uint256 amount);
    event Withdraw(address indexed caller, uint256 indexed userId, address indexed token, uint256 amount);
    event RewardsClaimed(address indexed caller, address[] tokens, uint256[] amounts);
    event Trade(address indexed market, uint256 indexed userId, address indexed user, bool isBuy, uint256 amountIn, uint256 amountOut, uint256 startPrice, uint256 endPrice);
    event OrdersUpdated(address indexed market, uint256 indexed userId, bytes orderData);
    event OrderFilled(address indexed market, uint256 indexed userId, uint256 fillInfo, uint256 fillAmount) anonymous; // fillinfo is price id remaining size

    event TokenCreated(address indexed token, address indexed creator, string name, string symbol, string metadataCID, string description, string social1, string social2, string social3);
    event Migrated(address indexed token);
    event LaunchpadTrade(address indexed token, address indexed user, bool isBuy, uint256 amountIn, uint256 amountOut, uint256 virtualNativeReserve, uint256 virtualTokenReserve);
    event Mint(address indexed market, address indexed sender, uint amountQuote, uint amountBase);
    event Sync(address indexed market, uint112 reserve0, uint112 reserve1);


    event Referral(address indexed referrer, address referee);

    error Unauthorized(address caller);
    error ActionFailed();
    error AccountLimitReached();
    error SlippageExceeded();
    error Expired(uint256 timestamp);
    error TransferFailed(address recipient);
    error InvalidPath(address[] path);
    error InvalidMarket(address asset0, address asset1);

    error RefCodeAlreadyTaken();

    constructor(address _weth, address _gov, address _feeRecipient, uint8 _feeCommission, uint8 _feeRebate, uint256 _feeClaimDuration, address[] memory _factories, LaunchpadParams memory _launchpadParams) {
        weth = _weth;
        gov = _gov;
        feeRecipient = _feeRecipient;
        feeCommission = _feeCommission;
        feeRebate = _feeRebate;
        feeClaimDuration = _feeClaimDuration;
        isCanonicalDeployer[_gov] = true;
        require(_factories.length == 3 && (_feeCommission + _feeRebate) < 50);
        factories = _factories;
        uint256 minSizeZeroes;
        while (_launchpadParams.graduatedMinSize != 0 && _launchpadParams.graduatedMinSize % 10 == 0) {
            _launchpadParams.graduatedMinSize /= 10;
            ++minSizeZeroes;
        }
        require(_launchpadParams.graduatedMinSize < 0xFFFFF && minSizeZeroes < 0xFFFFF && _launchpadParams.launchpadInitialNativeSupply > 1e18 && 90000 <= _launchpadParams.launchpadFee && _launchpadParams.launchpadFee <= 100000 && 90000 <= _launchpadParams.graduatedTakerFee);
        require(_launchpadParams.graduatedTakerFee <= 100000 && 90000 <= _launchpadParams.graduatedMakerRebate && _launchpadParams.graduatedMakerRebate <= 100000 && _launchpadParams.graduatedCreatorFeeSplit < 50 && _launchpadParams.launchpadCreatorFeeSplit < 100);
        launchpadParams = _launchpadParams;
    }

    fallback() external payable { // seperate method for margin that also allows specifying userId, add bribes
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
                let bribe := and(0xFFFFFFFFFFFFFFFFFFFF, shr(172, chunk))
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
                mstore(0x00, coinbase())
                pop(call(gas(), mload(0x00), totalBribe, 0, 0, 0, 0))
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
            emit UserRegistered(false, user, _latestUserId);
        }
        else {
            _latestUserId = latestUserId;
            _latestUserId++;
            userIdToAddress[_latestUserId] = user;
            latestUserId = _latestUserId;
            uint256 _marginAccounts = marginAccounts[user];
            uint256 i;
            for (i = 0; i < 256; i += 41) {
                if (((_marginAccounts >> i) & 0x1FFFFFFFFFF) == 0) {
                    _marginAccounts |= (_latestUserId << i);
                    break;
                }
            }
            if (i > 255 || _latestUserId > 0x1FFFFFFFFFF) revert AccountLimitReached(); // overflow uint36
            marginAccounts[user] = _marginAccounts;
            emit UserRegistered(true, user, _latestUserId);
        }
    }

    function _removeMarginAccount(address owner, uint256 userId) internal {
        uint256 _marginAccounts = marginAccounts[owner];
        for (uint256 i = 0; i < 256; i += 41) {
            if (((_marginAccounts >> i) & 0x1FFFFFFFFFF) == userId) {
                _marginAccounts &= ~(0x1FFFFFFFFFF << i);
                break;
            }
        }
        marginAccounts[owner] = _marginAccounts;
    }

    function allMarketsLength() external view returns (uint256) {
        return allMarkets.length;
    }

    function getMarket(address market) external view returns (MarketInfo memory info) {
        Market storage marketInfo = _getMarket[market];
        info = MarketInfo(
            marketInfo.quoteAsset,
            marketInfo.baseAsset,
            marketInfo.marketType,
            marketInfo.highestBid,
            marketInfo.lowestAsk,
            marketInfo.scaleFactor,
            marketInfo.tickSize,
            marketInfo.maxPrice,
            (marketInfo.minSize >> 16) * 10 ** (marketInfo.minSize & 0xFFFF),
            marketInfo.takerFee,
            marketInfo.makerRebate,
            marketInfo.reserveQuote,
            marketInfo.reserveBase,
            marketInfo.isAMMEnabled
        );
    }

    function getDepositedBalance(address user, address asset) external view returns (uint256 totalBalance, uint256 availableBalance, uint256 lockedBalance) {
        uint256 tokenBalance = tokenBalances[addressToUserId[user]][asset];
        availableBalance = tokenBalance & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
        lockedBalance = tokenBalance >> 128;
        return (availableBalance + lockedBalance, availableBalance, lockedBalance);
    }

    function getAllOrdersByCloid(address user, uint256 range) external view returns (uint256[] memory cloids, Order[] memory userOrders) {
        uint256 userId = addressToUserId[user];
        uint256[] memory temp = new uint256[](range > 1024 ? 1024 : range);
        uint256 count;
        for (uint256 i = 1; i < (range > 1024 ? 1024 : range); ++i) {
            uint256 order = orders[(i << 41) | userId];
            if (order != 0) {
                temp[count++] = i;
            }
        }

        userOrders = new Order[](count);
        cloids = new uint256[](count);
        for (uint256 i = 0; i < count; ++i) {
            cloids[i] = temp[i];
            userOrders[i] = getOrderByCloid(userId, temp[i]);
        }
    }

    function getOrderByCloid(uint256 userId, uint256 cloid) public view returns (Order memory) {
        uint256 order = orders[(cloid << 41) | userId];
        uint256 price = cloidVerify[((cloid | 1) << 41) | userId];
        uint256 marketId;
        if (cloid & 1 == 1) {
            marketId = ((price >> 80) & 0xFFFFFFFFFFFF);
            price = price & 0xFFFFFFFFFFFFFFFFFFFF;
        }
        else {
            marketId = ((price >> 208) & 0xFFFFFFFFFFFF);
            price = (price >> 128) & 0xFFFFFFFFFFFFFFFFFFFF;
        }
        address market = marketIdToMarket[marketId];
        return Order(price <= _getMarket[market].highestBid ? true : false, market, price, (order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF), (order >> 112 & 0x1), (order >> 113 & 0x1FFFFFFFFFF), (order >> 154 & 0x7FFFFFFFFFFFF), (order >> 205 & 0x7FFFFFFFFFFFF));
    }
    
    function getOrder(address market, uint256 price, uint256 id) external view returns (Order memory) {
        uint256 order = orders[(marketToMarketId[market] << 128) | (price << 48) | id];
        return Order(price <= _getMarket[market].highestBid ? true : false, market, price, (order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF), (order >> 112 & 0x1), (order >> 113 & 0x1FFFFFFFFFF), (order >> 154 & 0x7FFFFFFFFFFFF), (order >> 205 & 0x7FFFFFFFFFFFF));
    }

    function getPriceLevel(address market, uint256 price) external view returns (PriceLevel memory) {
        uint256 priceLevel = priceLevels[(marketToMarketId[market] << 128) | price];
        return PriceLevel((priceLevel & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF), (priceLevel >> 113 & 0x1FFFFFFFFFF), (priceLevel >> 154 & 0x7FFFFFFFFFFFF), (priceLevel >> 205 & 0x7FFFFFFFFFFFF));
    }

    function getPriceLevels(address market, bool isAscending, uint256 startPrice, uint256 distance, uint256 interval, uint256 max) external returns (bytes memory) {
        assembly {
            mstore(0x00, market)
            mstore(0x20, _getMarket.slot)
            if iszero(sload(keccak256(0x00, 0x40))) { revert(0, 0) }
            if tload(0x0) { revert(0, 0) }
            tstore(0x0, 1)
            mstore(0x80, shl(224, 0x9c510697))
            calldatacopy(0x84, 36, 160)
            let result := delegatecall(gas(), market, 0x80, 164, 0, 0)
            returndatacopy(0x80, 0, returndatasize())
            switch result
            case 0 { revert(0x80, returndatasize()) }
            default {
                tstore(0x0, 0)
                return(0x80, returndatasize())
            }
        }
    }

    function getPriceLevelsFromMid(address market, uint256 distance, uint256 interval, uint256 max) external returns (uint256 highestBid, uint256 lowestAsk, bytes memory, bytes memory) {
        assembly {
            mstore(0x00, market)
            mstore(0x20, _getMarket.slot)
            if iszero(sload(keccak256(0x00, 0x40))) { revert(0, 0) }
            if tload(0x0) { revert(0, 0) }
            tstore(0x0, 1)
            mstore(0x80, shl(224, 0xd58887ae))
            calldatacopy(0x84, 36, 96)
            let result := delegatecall(gas(), market, 0x80, 100, 0, 0)
            returndatacopy(0x80, 0, returndatasize())
            switch result
            case 0 { revert(0x80, returndatasize()) }
            default {
                tstore(0x0, 0)
                return(0x80, returndatasize())
            }
        }
    }

    function getPrice(address market) external returns (uint256 price, uint256 highestBid, uint256 lowestAsk) {
        assembly {
            mstore(0x00, market)
            mstore(0x20, _getMarket.slot)
            if iszero(sload(keccak256(0x00, 0x40))) { revert(0, 0) }
            if tload(0x0) { revert(0, 0) }
            tstore(0x0, 1)
            mstore(0x80, shl(224, 0x98d5fdca))
            let result := delegatecall(gas(), market, 0x80, 4, 0, 0)
            returndatacopy(0x80, 0, returndatasize())
            switch result
            case 0 { revert(0x80, returndatasize()) }
            default {
                tstore(0x0, 0)
                return(0x80, 96)
            }
        }
    }

    function getQuote(address market, bool isBuy, bool isExactInput, bool isCompleteFill, uint256 size, uint256 worstPrice) external returns (uint256 amountIn, uint256 amountOut) {
        assembly {
            mstore(0x00, market)
            mstore(0x20, _getMarket.slot)
            if iszero(sload(keccak256(0x00, 0x40))) { revert(0, 0) }
            if tload(0x0) { revert(0, 0) }
            tstore(0x0, 1)
            mstore(0x80, shl(224, 0x638571e3))
            calldatacopy(0x84, 36, 160)
            let result := delegatecall(gas(), market, 0x80, 164, 0, 0)
            returndatacopy(0x80, 0, returndatasize())
            switch result
            case 0 { revert(0x80, returndatasize()) }
            default {
                tstore(0x0, 0)
                return(0x80, 64)
            }
        }
    }

    function deploy(bool isCanonical, address quoteAsset, address baseAsset, uint256 marketType, uint256 scaleFactor, uint256 tickSize, uint256 maxPrice, uint256 minSize, uint24 takerFee, uint24 makerRebate) external returns (address market) {
        if (isCanonical && !isCanonicalDeployer[msg.sender]) {
            revert Unauthorized(msg.sender);
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
        parameters = Parameters(quoteAsset, baseAsset, marketId, scaleFactor, tickSize, maxPrice); // maxsize is validated here
        uint256 maxTick;
        if (marketType == 0) {
            (bool result, bytes memory ret) = factories[0].delegatecall(abi.encodeWithSelector(0x1b3671bf, quoteAsset, baseAsset, marketId));
            if (!result) {
                revert ActionFailed();
            }
            market = abi.decode(ret, (address));
            maxTick = maxPrice / tickSize;
        }
        else if (marketType == 1 || marketType == 2) {
            (bool result, bytes memory ret) = factories[1].delegatecall(abi.encodeWithSelector(0x1b3671bf, quoteAsset, baseAsset, marketId));
            if (!result) {
                revert ActionFailed();
            }
            market = abi.decode(ret, (address));
            maxTick = _priceToTick(maxPrice, tickSize);
        }
        else {
            revert ActionFailed();
        }
        delete parameters;
        Market storage m = _getMarket[market];
        (m.quoteAsset, m.baseAsset, m.marketId, m.scaleFactor, m.tickSize) = (quoteAsset, baseAsset, marketId, scaleFactor, tickSize); // immutable params but for _getMarket
        (m.takerFee, m.makerRebate, m.maxPrice, m.marketType, m.isAMMEnabled) = (takerFee, makerRebate, maxPrice, marketType, marketType == 2);
        m.lowestAsk = uint80(maxPrice);
        activated[(marketId << 128)] = 1; // index 0
        uint256 minSizeZeroes;
        while (minSize != 0 && minSize % 10 == 0) {
            minSize /= 10;
            ++minSizeZeroes;
        }
        require(minSize < 0xFFFFF && minSizeZeroes < 0xFFFFF && marketId < 0xFFFFFFFFFFFF); // minSize is encoded as bits 20-40 * 10 ** bits 0-20, marketid max uint48 minsize is variable to prevent dos
        m.minSize = uint40((minSize << 20) | minSizeZeroes);
        activated[(marketId << 128) | (maxTick >> 8)] = (1 << (maxTick % 256));
        }
        allMarkets.push(market);
        marketToMarketId[market] = marketId;
        marketIdToMarket[marketId] = market;
        if (isCanonical) {
            getMarketByTokens[quoteAsset][baseAsset] = market;
            getMarketByTokens[baseAsset][quoteAsset] = market;
        }
        else {
            if (getMarketByTokens[quoteAsset][baseAsset] == address(0)) {
                getMarketByTokens[quoteAsset][baseAsset] = market;
                getMarketByTokens[baseAsset][quoteAsset] = market; 
            }
        }
        emit MarketCreated(quoteAsset, baseAsset, market, marketId, marketType, scaleFactor, tickSize, maxPrice, minSize, takerFee, makerRebate);
    }

    function registerUser(address caller) external returns (uint256 userId) {
        if (msg.sender != caller && msg.sender != address(this)) {
            revert Unauthorized(msg.sender);
        }
        userId = _registerUser(0, caller);
    }

    function registerNewMarginAccount() external returns (uint256 userId) {
        userId = _registerUser(1, msg.sender);
    }
    // checks incomplete, base account cannot ever support margin
    function backstopLiquidateMarginAccount(uint256 userId) internal {
        address prevOwner = userIdToAddress[userId];
        _removeMarginAccount(prevOwner, userId);
        // userIdToAddress[userId] = liquidator; maybe just do address this as liquidator
        // liquidator.setAuthorized[userId] = msg.sender;
    }
    // for base account, provide seperate method to deposit/withdraw from margin acc
    function deposit(address token, uint256 amount) public returns (uint256 userId){
        userId = addressToUserId[msg.sender];
        if (userId == 0) {
            userId = _registerUser(0, msg.sender);
        }
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        tokenBalances[userId][token] += amount;
        emit Deposit(msg.sender, userId, token, amount);
    }

    function withdraw(address to, address token, uint256 amount) public {
        uint256 userId = addressToUserId[msg.sender];
        uint256 balance = tokenBalances[userId][token];
        if (uint128(balance) < amount) {
            revert ActionFailed();
        }
        else {
            tokenBalances[userId][token] = balance - amount;
        }
        IERC20(token).transfer(to, amount);
        emit Withdraw(msg.sender, userId, token, amount);
    }

    function depositNative() public payable returns (uint256 userId){
        userId = addressToUserId[msg.sender];
        if (userId == 0) {
            userId = _registerUser(0, msg.sender);
        }
        IWETH(weth).deposit{value: msg.value}();
        tokenBalances[userId][weth] += msg.value;
        emit Deposit(msg.sender, userId, weth, msg.value);
    }

    function withdrawNative(address to, uint256 amount) public {
        uint256 userId = addressToUserId[msg.sender];
        uint256 balance = tokenBalances[userId][weth];
        if (uint128(balance) < amount) {
            revert ActionFailed();
        }
        else {
            tokenBalances[userId][weth] = balance - amount;
        }
        IWETH(weth).withdraw(amount);
        (bool success, ) = to.call{value: amount}("");
        if (!success) {
            revert TransferFailed(to);
        } 
        emit Withdraw(msg.sender, userId, weth, amount);
    }
    // vault/margin operators can claim to their wallet, resets any pending expiry claims
    function claimFees(address to, address[] calldata tokens) external returns (uint256[] memory amounts) {
        amounts = new uint256[](tokens.length);
        delete pendingExpiredFeeClaims[msg.sender];
        for (uint256 i = 0; i < tokens.length; ++i) {
            if (tokens[i] == eth) {
                amounts[i] = claimableRewards[weth][msg.sender];
                claimableRewards[weth][msg.sender] = 0;
                IWETH(weth).withdraw(amounts[i]);
                (bool success, ) = to.call{value: amounts[i]}("");
                if (!success) {
                    revert TransferFailed(to);
                } 
            }
            else {
                amounts[i] = claimableRewards[tokens[i]][msg.sender];
                claimableRewards[tokens[i]][msg.sender] = 0;
                IERC20(tokens[i]).transfer(to, amounts[i]);
            }
        }  
        emit RewardsClaimed(msg.sender, tokens, amounts);      
    }
    // anyone can queue fee claim, only governance can actually execute
    function queueClaimExpiredFees(address user, address[] calldata tokens) external {
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
            revert Unauthorized(msg.sender);
        }
        amounts = pendingExpiredFeeClaims[user].amounts;
        for (uint256 i = 0; i < pendingExpiredFeeClaims[user].tokens.length; ++i) {
            claimableRewards[pendingExpiredFeeClaims[user].tokens[i]][user] -= amounts[i];
            IERC20(pendingExpiredFeeClaims[user].tokens[i]).transfer(msg.sender, amounts[i]);
        }
        delete pendingExpiredFeeClaims[user];
    }

    function changeGov(address newGov) external {
        if (msg.sender != gov) {
            revert Unauthorized(msg.sender);
        }
        gov = newGov;
        emit GovChanged(msg.sender, newGov);
    }

    function changeFeeRecipient(address newFeeRecipient) external {
        if (msg.sender != gov) {
            revert Unauthorized(msg.sender);
        }
        feeRecipient = newFeeRecipient;
    }

    function changeFeeClaimDuration(uint256 newFeeClaimDuration) external {
        if (msg.sender != gov) {
            revert Unauthorized(msg.sender);
        }
        require(newFeeClaimDuration > 86400);
        feeClaimDuration = newFeeClaimDuration;
    }

    function changeRefFeeStructure(uint8 newFeeCommission, uint8 newFeeRebate) external {
        if (msg.sender != gov) {
            revert Unauthorized(msg.sender);
        }
        require((newFeeCommission + newFeeRebate) < 50);
        feeCommission = newFeeCommission;
        feeRebate = newFeeRebate;
    }

    function changeMarketParams(address market, uint256 newMinSize, uint24 newTakerFee, uint24 newMakerRebate, bool isAMMEnabled, bool isCanonical) external {
        require(isCanonicalDeployer[msg.sender] && 90000 <= newTakerFee && newTakerFee <= 100000 && 90000 <= newMakerRebate && newMakerRebate <= 100000);
        Market storage m = _getMarket[market];
        if (newMinSize != (m.minSize >> 20) * 10 ** (m.minSize & 0xFFFFF)) {
            uint256 minSizeZeroes;
            while (newMinSize != 0 && newMinSize % 10 == 0) {
                newMinSize /= 10;
                ++minSizeZeroes;
            }
            require(newMinSize < 0xFFFFF && minSizeZeroes < 0xFFFFF);
            m.minSize = uint40((newMinSize << 20) | minSizeZeroes);
        }
        if (newTakerFee != m.takerFee) {
            m.takerFee = newTakerFee;
        }
        if (newMakerRebate != m.makerRebate) {
            m.makerRebate = newMakerRebate;
        }
        if (m.marketType != 0 && m.isAMMEnabled != isAMMEnabled) {
            m.isAMMEnabled = isAMMEnabled;
        }
        if (isCanonical && getMarketByTokens[m.quoteAsset][m.baseAsset] != market) {
            getMarketByTokens[m.quoteAsset][m.baseAsset] = market;
            getMarketByTokens[m.baseAsset][m.quoteAsset] = market;
        }
        else if (!isCanonical && getMarketByTokens[m.quoteAsset][m.baseAsset] == market) {
            getMarketByTokens[m.quoteAsset][m.baseAsset] = address(0);
            getMarketByTokens[m.baseAsset][m.quoteAsset] = address(0);
        }
        emit MarketParamsChanged(market, (m.minSize >> 20) * 10 ** (m.minSize & 0xFFFFF), newTakerFee, newMakerRebate, m.isAMMEnabled);
    }

    function changeLaunchpadParams(LaunchpadParams memory newLaunchpadParams) external {
        if (msg.sender != gov) {
            revert Unauthorized(msg.sender);
        }
        uint256 minSizeZeroes;
        while (newLaunchpadParams.graduatedMinSize != 0 && newLaunchpadParams.graduatedMinSize % 10 == 0) {
            newLaunchpadParams.graduatedMinSize /= 10;
            ++minSizeZeroes;
        }
        require(newLaunchpadParams.graduatedMinSize < 0xFFFFF && minSizeZeroes < 0xFFFFF && newLaunchpadParams.launchpadInitialNativeSupply > 1e18 && 90000 <= newLaunchpadParams.launchpadFee && newLaunchpadParams.launchpadFee <= 100000 && 90000 <= newLaunchpadParams.graduatedTakerFee);
        require(newLaunchpadParams.graduatedTakerFee <= 100000 && 90000 <= newLaunchpadParams.graduatedMakerRebate && newLaunchpadParams.graduatedMakerRebate <= 100000 && newLaunchpadParams.graduatedCreatorFeeSplit < 50 && newLaunchpadParams.launchpadCreatorFeeSplit < 100);
        launchpadParams = newLaunchpadParams;
    }

    function addCanonicalDeployer(address deployer) external {
        if (msg.sender != gov) {
            revert Unauthorized(msg.sender);
        }
        isCanonicalDeployer[deployer] = true;
    }

    function removeCanonicalDeployer(address deployer) external {
        if (msg.sender != gov) {
            revert Unauthorized(msg.sender);
        }
        isCanonicalDeployer[deployer] = false;
    }
    // incase a rent-like mechanism ever is added
    function clearCloidSlots(uint256 userId, uint256[] calldata ids) external {
        if (msg.sender != userIdToAddress[userId] && msg.sender != gov) {
            revert Unauthorized(msg.sender);
        }
        for (uint256 i; i < ids.length; ++i) {
            if (ids[i] & 1 == 1) {
                cloidVerify[((ids[i] | 1) << 41) | userId] &= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000000000000000000000000000;
            }
            else {
                cloidVerify[((ids[i] | 1) << 41) | userId] &= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
            }
            if ((orders[(ids[i] << 41) | userId] & 0xFFFFFFFFFFFFFFFFFFFFFFFFFC0000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFF) == 0) {
                delete orders[(ids[i] << 41) | userId];
            }
        }
    }

    function getReserves(address market) external returns (uint112 reserveQuote, uint112 reserveBase) {
        assembly {
            mstore(0x00, market)
            mstore(0x20, _getMarket.slot)
            if iszero(sload(keccak256(0x00, 0x40))) { revert(0, 0) }
            if tload(0x0) { revert(0, 0) }
            tstore(0x0, 1)
            mstore(0x80, shl(224, 0x0902f1ac))
            let result := delegatecall(gas(), market, 0x80, 4, 0, 0)
            returndatacopy(0x80, 0, returndatasize())
            switch result
            case 0 { revert(0x80, returndatasize()) }
            default {
                tstore(0x0, 0)
                return(0x80, 64)
            }
        }
    }
    
    function addLiquidity(address market, address to, uint256 amountQuoteDesired, uint256 amountBaseDesired, uint256 amountQuoteMin, uint256 amountBaseMin) external returns (uint256 liquidity) {
        assembly {
            mstore(0x00, market)
            mstore(0x20, _getMarket.slot)
            if iszero(sload(keccak256(0x00, 0x40))) { revert(0, 0) }
            if tload(0x0) { revert(0, 0) }
            tstore(0x0, 1)
            mstore(0x80, shl(224, 0x74dbc248))
            calldatacopy(0x84, 36, 160)
            mstore(0x144, caller())
            let result := delegatecall(gas(), market, 0x80, 228, 0, 0)
            returndatacopy(0x80, 0, returndatasize())
            switch result
            case 0 { revert(0x80, returndatasize()) }
            default {
                tstore(0x0, 0)
                return(0x80, 32)
            }
        }
    }

    function addLiquidityETH(address market, address to, uint256 amountQuoteDesired, uint256 amountBaseDesired, uint256 amountQuoteMin, uint256 amountBaseMin) external payable returns (uint256 liquidity) {
        if (msg.value != 0) {
            IWETH(weth).deposit{value: msg.value}();
            tokenBalances[0][weth] += msg.value;
        }
        uint256 options = _getMarket[market].quoteAsset == weth ? (1) : (1 << 4);
        assembly {
            mstore(0x00, market)
            mstore(0x20, _getMarket.slot)
            if iszero(sload(keccak256(0x00, 0x40))) { revert(0, 0) }
            if tload(0x0) { revert(0, 0) }
            tstore(0x0, 1)
            mstore(0x80, shl(224, 0x74dbc248))
            calldatacopy(0x84, 36, 160)
            mstore(0x124, options)
            mstore(0x144, caller())
            let result := delegatecall(gas(), market, 0x80, 228, 0, 0)
            returndatacopy(0x80, 0, returndatasize())
            switch result
            case 0 { revert(0x80, returndatasize()) }
            default {
                tstore(0x0, 0)
                return(0x80, 32)
            }
        }
    }

    function removeLiquidity(address market, address to, uint256 liquidity, uint256 amountQuoteMin, uint256 amountBaseMin) external returns (uint256 amountQuote, uint256 amountBase) {
        assembly {
            mstore(0x00, market)
            mstore(0x20, _getMarket.slot)
            if iszero(sload(keccak256(0x00, 0x40))) { revert(0, 0) }
            if tload(0x0) { revert(0, 0) }
            tstore(0x0, 1)
            mstore(0x80, shl(224, 0x2c8f8a3a))
            calldatacopy(0x84, 36, 128)
            mstore(0x124, caller())
            let result := delegatecall(gas(), market, 0x80, 196, 0, 0)
            returndatacopy(0x80, 0, returndatasize())
            switch result
            case 0 { revert(0x80, returndatasize()) }
            default {
                tstore(0x0, 0)
                return(0x80, 64)
            }
        }
    }

    function removeLiquidityETH(address market, address to, uint256 liquidity, uint256 amountQuoteMin, uint256 amountBaseMin) external returns (uint256 amountQuote, uint256 amountBase) {
        uint256 options = _getMarket[market].quoteAsset == weth ? (1) : (1 << 4);
        assembly {
            mstore(0x00, market)
            mstore(0x20, _getMarket.slot)
            if iszero(sload(keccak256(0x00, 0x40))) { revert(0, 0) }
            if tload(0x0) { revert(0, 0) }
            tstore(0x0, 1)
            mstore(0x80, shl(224, 0x2c8f8a3a))
            calldatacopy(0x84, 36, 128)
            mstore(0x104, options)
            mstore(0x124, caller())
            let result := delegatecall(gas(), market, 0x80, 196, 0, 0)
            returndatacopy(0x80, 0, returndatasize())
            switch result
            case 0 { revert(0x80, returndatasize()) }
            default {
                tstore(0x0, 0)
                amountQuote := mload(0x80)
                amountBase  := mload(add(0x80, 0x20))
            }
        }
        uint256 balance = tokenBalances[0][weth];
        if (balance != 0) {
            tokenBalances[0][weth] = 0;
            IWETH(weth).withdraw(balance);
            (bool success, ) = msg.sender.call{value: balance}("");
            if (!success) {
                revert TransferFailed(msg.sender);
            }
        }
    }

    function marketOrder(address market, bool isBuy, bool isExactInput, uint256 options, uint256 orderType, uint256 size, uint256 worstPrice, address referrer) external returns (uint256 amountIn, uint256 amountOut, uint256 id) {
        assembly {
            mstore(0x00, market)
            mstore(0x20, _getMarket.slot)
            if iszero(sload(keccak256(0x00, 0x40))) { revert(0, 0) }
            if tload(0x0) { revert(0, 0) }
            tstore(0x0, 1)
            mstore(0x80, shl(224, 0xe690552b))
            calldatacopy(0x84, 36, 224)
            mstore(0x164, caller())
            let result := delegatecall(gas(), market, 0x80, 260, 0, 0)
            returndatacopy(0x80, 0, returndatasize())
            switch result
            case 0 { revert(0x80, returndatasize()) }
            default {
                tstore(0x0, 0)
                return(0x80, 96)
            }
        }
    }

    function limitOrder(address market, bool isBuy, uint256 options, uint256 price, uint256 size) external returns (uint256 id) {
        assembly {
            mstore(0x00, market)
            mstore(0x20, _getMarket.slot)
            if iszero(sload(keccak256(0x00, 0x40))) { revert(0, 0) }
            if tload(0x0) { revert(0, 0) }
            tstore(0x0, 1)
            mstore(0x80, shl(224, 0x218a0c31))
            calldatacopy(0x84, 36, 128)
            mstore(0x104, caller())
            let result := delegatecall(gas(), market, 0x80, 164, 0, 0)
            returndatacopy(0x80, 0, returndatasize())
            switch result
            case 0 { revert(0x80, returndatasize()) }
            default {
                tstore(0x0, 0)
                return(0x80, 32)
            }
        }
    }

    function cancelOrder(address market, uint256 options, uint256 price, uint256 id) external returns (uint256 size) {
        assembly {
            mstore(0x00, market)
            mstore(0x20, _getMarket.slot)
            if iszero(sload(keccak256(0x00, 0x40))) { revert(0, 0) }
            if tload(0x0) { revert(0, 0) }
            tstore(0x0, 1)
            mstore(0x80, shl(224, 0xb69d86f7))
            calldatacopy(0x84, 36, 96)
            mstore(0xE4, caller())
            let result := delegatecall(gas(), market, 0x80, 132, 0, 0)
            returndatacopy(0x80, 0, returndatasize())
            switch result
            case 0 { revert(0x80, returndatasize()) }
            default {
                tstore(0x0, 0)
                return(0x80, 32)
            }
        }
    }

    function replaceOrder(address market, uint256 options, uint256 price, uint256 id, uint256 newPrice, uint256 size, address referrer) external returns (uint256 _id) {
        assembly {
            mstore(0x00, market)
            mstore(0x20, _getMarket.slot)
            if iszero(sload(keccak256(0x00, 0x40))) { revert(0, 0) }
            if tload(0x0) { revert(0, 0) }
            tstore(0x0, 1)
            mstore(0x80, shl(224, 0x6c8dce79))
            calldatacopy(0x84, 36, 192)
            mstore(0x144, caller())
            let result := delegatecall(gas(), market, 0x80, 228, 0, 0)
            returndatacopy(0x80, 0, returndatasize())
            switch result
            case 0 { revert(0x80, returndatasize()) }
            default {
                tstore(0x0, 0)
                return(0x80, 32)
            }
        }
    }
    // router
    function getAmountsOut(uint256 amountIn, address[] memory path) external returns (uint256[] memory amounts) {
        if (path.length < 2) {
            revert InvalidPath(path);
        }
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i; i < path.length - 1; ++i) {
            address asset0 = path[i] == eth ? weth : path[i];
            address asset1 = path[i+1] == eth ? weth : path[i+1];
            address market = getMarketByTokens[asset0][asset1];
            if (market == address(0)) {
                revert InvalidMarket(asset0, asset1);
            }
            uint256 inputAmount;
            if (_getMarket[market].quoteAsset == asset0) {
                (bool result, bytes memory ret) = market.delegatecall(abi.encodeWithSelector(0x638571e3, true, true, i != 0, amounts[i], 0xFFFFFFFFFFFFFFFFFFFF));
                require(result);
                (inputAmount, amounts[i + 1]) = abi.decode(ret, (uint256, uint256));
            }
            else {
                (bool result, bytes memory ret) = market.delegatecall(abi.encodeWithSelector(0x638571e3, false, true, i != 0, amounts[i], 1));
                require(result);
                (inputAmount, amounts[i + 1]) = abi.decode(ret, (uint256, uint256));
            }
            if (i != 0 && amounts[i] != inputAmount) {
                revert SlippageExceeded();
            }
            amounts[i] = inputAmount;
        }
    }

    function getAmountsIn(uint256 amountOut, address[] memory path) public returns (uint256[] memory amounts) {
        if (path.length < 2) {
            revert InvalidPath(path);
        }
        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint256 i = path.length - 1; i != 0; --i) {
            address asset0 = path[i-1] == eth ? weth : path[i-1];
            address asset1 = path[i] == eth ? weth : path[i];
            address market = getMarketByTokens[asset0][asset1];
            if (market == address(0)) {
                revert InvalidMarket(asset0, asset1);
            }
            uint256 outputAmount;
            if (_getMarket[market].quoteAsset == asset0) {
                (bool result, bytes memory ret) = market.delegatecall(abi.encodeWithSelector(0x638571e3, true, false, true, amounts[i], 0xFFFFFFFFFFFFFFFFFFFF));
                if (!result) {
                    revert SlippageExceeded();
                }
                (amounts[i - 1], outputAmount) = abi.decode(ret, (uint256, uint256));
            }
            else {
                (bool result, bytes memory ret) = market.delegatecall(abi.encodeWithSelector(0x638571e3, false, false, true, amounts[i], 1));
                if (!result) {
                    revert SlippageExceeded();
                }
                (amounts[i - 1], outputAmount) = abi.decode(ret, (uint256, uint256));
            }
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
                revert InvalidMarket(asset0, asset1);
            }
            asset1 = _getMarket[market].quoteAsset;
            uint256 options = ((i != 0 || path[i] == eth) ? (1 << 64) : 0) | ((i != path.length - 2 || path[i+1] == eth || to != msg.sender) ? (1 << 60) : 0);
            bytes memory ret = abi.encodeWithSelector(0xe690552b, asset1 == asset0, true, options, 1, amounts[i], asset1 == asset0 ? 0xFFFFFFFFFFFFFFFFFFFF : 1, referrer, msg.sender);
            bool result;
            (result, ret) = market.delegatecall(ret);
            if (!result) {
                revert SlippageExceeded();
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
            asset1 = _getMarket[market].quoteAsset;
            uint256 options = ((i != 0 || path[i] == eth) ? (1 << 64) : 0) | ((i != path.length - 2 || path[i+1] == eth || to != msg.sender) ? (1 << 60) : 0);
            bytes memory ret = abi.encodeWithSelector(0xe690552b, asset1 == asset0, false, options, 1, amounts[i+1], asset1 == asset0 ? 0xFFFFFFFFFFFFFFFFFFFF : 1, referrer, msg.sender);
            bool result;
            (result, ret) = market.delegatecall(ret);
            if (!result) {
                revert SlippageExceeded();
            }
            (amounts[i], , ) = abi.decode(ret, (uint256, uint256, uint256));
        }
        assembly {
            tstore(0x0, 0)
        }
    }

    function swapExactETHForTokens(uint256 amountOutMin, address[] memory path, address to, uint256 deadline, address referrer) external payable returns (uint256[] memory amounts) {
        if (path.length < 2 || path[0] != eth) {
            revert InvalidPath(path);
        }
        if (deadline < block.timestamp) {
            revert Expired(deadline);
        }
        IWETH(weth).deposit{value: msg.value}();
        tokenBalances[0][weth] += msg.value;
        amounts = exactInputSwap(msg.value, path, to, referrer);
        if (amountOutMin > amounts[amounts.length - 1]) {
            revert SlippageExceeded();
        }
        if (to != msg.sender) {
            uint256 amount = amounts[amounts.length - 1];
            address token = path[path.length - 1];
            uint256 balance = tokenBalances[0][token];
            if (uint128(balance) < amount) {
                revert ActionFailed();
            }
            else {
                tokenBalances[0][token] = balance - amount;
            }
            IERC20(token).transfer(to, amount);
        }
    }

    function swapExactTokensForETH(uint256 amountIn, uint256 amountOutMin, address[] memory path, address to, uint256 deadline, address referrer) external returns (uint256[] memory amounts) {
        if (deadline < block.timestamp) {
            revert Expired(deadline);
        }
        if (path.length < 2 || path[path.length - 1] != eth) {
            revert InvalidPath(path);
        }
        amounts = exactInputSwap(amountIn, path, to, referrer);
        if (amountOutMin > amounts[amounts.length - 1]) {
            revert SlippageExceeded();
        }
        uint256 balance = tokenBalances[0][weth];
        uint256 amount = amounts[amounts.length - 1];
        if (uint128(balance) < amount) {
            revert ActionFailed();
        }
        else {
            tokenBalances[0][weth] = balance - amount;
        }
        IWETH(weth).withdraw(amount);
        (bool success, ) = to.call{value: amount}("");
        if (!success) {
            revert TransferFailed(to);
        }
    }

    function swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, address[] memory path, address to, uint256 deadline, address referrer) external returns (uint256[] memory amounts) {
        if (deadline < block.timestamp) {
            revert Expired(deadline);
        }
        if (path.length < 2 || path[path.length - 1] == eth) {
            revert InvalidPath(path);
        }
        amounts = exactInputSwap(amountIn, path, to, referrer);
        if (amountOutMin > amounts[amounts.length - 1]) {
            revert SlippageExceeded();
        }
        if (to != msg.sender) {
            uint256 amount = amounts[amounts.length - 1];
            address token = path[path.length - 1];
            uint256 balance = tokenBalances[0][token];
            if (uint128(balance) < amount) {
                revert ActionFailed();
            }
            else {
                tokenBalances[0][token] = balance - amount;
            }
            IERC20(token).transfer(to, amount);
        }
    }

    function swapETHForExactTokens(uint256 amountOut, address[] memory path, address to, uint256 deadline, address referrer) external payable returns (uint256[] memory amounts) {
        if (deadline < block.timestamp) {
            revert Expired(deadline);
        }
        if (path[0] != eth) {
            revert InvalidPath(path);
        }
        amounts = getAmountsIn(amountOut, path);
        if (amounts[0] > msg.value) {
            revert SlippageExceeded();
        }
        IWETH(weth).deposit{value: msg.value}();
        tokenBalances[0][weth] += msg.value;
        exactOutputSwap(amounts, path, to, referrer);
        if (to != msg.sender) {
            address token = path[path.length - 1];
            uint256 balance = tokenBalances[0][token];
            if (uint128(balance) < amountOut) {
                revert ActionFailed();
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
                revert ActionFailed();
            }
            else {
                tokenBalances[0][weth] = balance - amount;
            }
            IWETH(weth).withdraw(amount);
            (bool success, ) = to.call{value: amount}("");
            if (!success) {
                revert TransferFailed(to);
            }         
        }
    }

    function swapTokensForExactETH(uint256 amountOut, uint256 amountInMax, address[] memory path, address to, uint256 deadline, address referrer) external returns (uint256[] memory amounts) {
        if (deadline < block.timestamp) {
            revert Expired(deadline);
        }
        if (path[path.length - 1] != eth) {
            revert InvalidPath(path);
        }
        amounts = getAmountsIn(amountOut, path);
        if (amounts[0] > amountInMax) {
            revert SlippageExceeded();
        }
        exactOutputSwap(amounts, path, to, referrer);
        uint256 balance = tokenBalances[0][weth];
        if (uint128(balance) < amountOut) {
            revert ActionFailed();
        }
        else {
            tokenBalances[0][weth] = balance - amountOut;
        }
        IWETH(weth).withdraw(amountOut);
        (bool success, ) = to.call{value: amountOut}("");
        if (!success) {
            revert TransferFailed(to);
        }
    }

    function swapTokensForExactTokens(uint256 amountOut, uint256 amountInMax, address[] memory path, address to, uint256 deadline, address referrer) external returns (uint256[] memory amounts) {
        if (deadline < block.timestamp) {
            revert Expired(deadline);
        }
        if (path[path.length - 1] == eth) {
            revert InvalidPath(path);
        }
        amounts = getAmountsIn(amountOut, path);
        if (amounts[0] > amountInMax) {
            revert SlippageExceeded();
        }
        exactOutputSwap(amounts, path, to, referrer);
        if (to != msg.sender) {
            address token = path[path.length - 1];
            uint256 balance = tokenBalances[0][token];
            if (uint128(balance) < amountOut) {
                revert ActionFailed();
            }
            else {
                tokenBalances[0][token] = balance - amountOut;
            }
            IERC20(token).transfer(to, amountOut);
        }
    }

    function swap(bool isExactInput, address tokenIn, address tokenOut, uint256 orderType, uint256 size, uint256 worstPrice, uint256 deadline, address referrer) external payable returns (uint256 userId, uint256 balance, uint256 id) {
        if (deadline < block.timestamp) {
            revert Expired(deadline);
        }
        address market = getMarketByTokens[tokenIn == eth ? weth : tokenIn][tokenOut == eth ? weth : tokenOut];    
        if (market == address(0)) {
            revert InvalidMarket(tokenIn == eth ? weth : tokenIn, tokenOut == eth ? weth : tokenOut);
        }
        if (tokenIn == eth) {
            IWETH(weth).deposit{value: msg.value}();
            tokenBalances[0][weth] += msg.value;
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
            revert ActionFailed();
        }
        if (tokenIn == eth || tokenOut == eth) {
            balance = tokenBalances[0][weth];
            if (balance != 0) {
                tokenBalances[0][weth] = 0;
                IWETH(weth).withdraw(balance);
                (bool success, ) = msg.sender.call{value: balance}("");
                if (!success) {
                    revert TransferFailed(msg.sender);
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
            revert Expired(deadline);
        }
        bool isETHIn = tokenIn == eth;
        address asset0 = isETHIn ? weth : tokenIn;
        address asset1 = tokenOut == eth ? weth : tokenOut;
        address market = getMarketByTokens[asset0][asset1];    
        if (market == address(0)) {
            revert InvalidMarket(asset0, asset1);
        }
        if (isETHIn) {
            IWETH(weth).deposit{value: msg.value}();
            tokenBalances[0][weth] += msg.value;
        }
        assembly {
            if tload(0x0) { revert(0, 0) }
            tstore(0x0, 1)
        }
        uint256 options = (isETHIn ? (1 << 56) : 0);
        (bool result, bytes memory ret) = market.delegatecall(abi.encodeWithSelector(0x218a0c31, _getMarket[market].quoteAsset == asset0, options, price, size, msg.sender));
        if (!result) {
            revert ActionFailed();
        }
        id = abi.decode(ret, (uint256));
        assembly {
            tstore(0x0, 0)
        }
    }

    function cancelLimitOrder(address tokenIn, address tokenOut, uint256 price, uint256 id, uint256 deadline) external returns (uint256 size) {
        if (deadline < block.timestamp) {
            revert Expired(deadline);
        }
        bool isETHIn = tokenIn == eth;
        address asset0 = isETHIn ? weth : tokenIn;
        address asset1 = tokenOut == eth ? weth : tokenOut;
        address market = getMarketByTokens[asset0][asset1];    
        if (market == address(0)) {
            revert InvalidMarket(asset0, asset1);
        }
        assembly {
            if tload(0x0) { revert(0, 0) }
            tstore(0x0, 1)
        }
        uint256 options = (isETHIn ? (1 << 44) : 0);
        (bool result, bytes memory ret) = market.delegatecall(abi.encodeWithSelector(0xb69d86f7, options, price, id, msg.sender));
        if (!result) {
            revert ActionFailed();
        }
        size = abi.decode(ret, (uint256));
        if (size == 0) {
            revert ActionFailed();
        }
        if (isETHIn) {
            uint256 balance = tokenBalances[0][weth];
            if (uint128(balance) < size) {
                revert ActionFailed();
            }
            else {
                tokenBalances[0][weth] = balance - size;
            }
            IWETH(weth).withdraw(size);
            (bool success, ) = msg.sender.call{value: size}("");
            if (!success) {
                revert TransferFailed(msg.sender);
            }
        }
        assembly {
            tstore(0x0, 0)
        }
    }

    function replaceOrder(bool isPostOnly, bool isDecrease, address tokenIn, address tokenOut, uint256 price, uint256 id, uint256 newPrice, uint256 newSize, uint256 deadline, address referrer) external payable returns (uint256) {
        if (deadline < block.timestamp) {
            revert Expired(deadline);
        }
        address market = getMarketByTokens[tokenIn == eth ? weth : tokenIn][tokenOut == eth ? weth : tokenOut];    
        if (market == address(0)) {
            revert InvalidMarket(tokenIn == eth ? weth : tokenIn, tokenOut == eth ? weth : tokenOut);
        }
        if (tokenIn == eth) {
            IWETH(weth).deposit{value: msg.value}();
            tokenBalances[0][weth] += msg.value;
        }
        assembly {
            if tload(0x0) { revert(0, 0) }
            tstore(0x0, 1)
        }
        deadline = ((tokenIn == eth) ? (1 << 56) : 0) | ((tokenOut == eth) ? (1 << 52) : 0) | (isDecrease ? (1 << 48) : 0) | (isPostOnly ? 0 : (1 << 44));
        (bool result, bytes memory ret) = market.delegatecall(abi.encodeWithSelector(0x6c8dce79, deadline, price, id, newPrice, newSize, referrer, msg.sender));
        if (!result) {
            revert ActionFailed();
        }
        id = abi.decode(ret, (uint256));
        if (tokenIn == eth || tokenOut == eth) {
            uint256 balance = tokenBalances[0][weth];
            if (balance != 0) {
                tokenBalances[0][weth] = 0;
                IWETH(weth).withdraw(balance);
                (bool success, ) = msg.sender.call{value: balance}("");
                if (!success) {
                    revert TransferFailed(msg.sender);
                }
            }
        }
        assembly {
            tstore(0x0, 0)
        }
        return id;
    }

    function batchOrders(address market, Action[] calldata actions, uint256 options, uint256 deadline, address referrer) external payable {
        if (deadline < block.timestamp) {
            revert Expired(deadline);
        }
        if (msg.value != 0) {
            IWETH(weth).deposit{value: msg.value}();
            tokenBalances[0][weth] += msg.value;
        }
        assembly {
            mstore(0x00, market)
            mstore(0x20, _getMarket.slot)
            if iszero(sload(keccak256(0x00, 0x40))) { revert(0, 0) }
            if tload(0x0) { revert(0, 0) }
            tstore(0x0, 1)
        }
        (bool result, bytes memory ret) = market.delegatecall(
            abi.encodeWithSelector(0x5c2a91ec, actions, options, referrer, msg.sender)
        );
        uint256 balance = tokenBalances[0][weth];
        if (balance != 0) {
            tokenBalances[0][weth] = 0;
            IWETH(weth).withdraw(balance);
            (bool success, ) = msg.sender.call{value: balance}("");
            if (!success) {
                revert TransferFailed(msg.sender);
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

    function multiBatchOrders(Batch[] calldata batches, address referrer, uint256 deadline) external payable {
        if (deadline < block.timestamp) {
            revert Expired(deadline);
        }
        if (msg.value != 0) {
            IWETH(weth).deposit{value: msg.value}();
            tokenBalances[0][weth] += msg.value;
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
        uint256 balance = tokenBalances[0][weth];
        if (balance != 0) {
            tokenBalances[0][weth] = 0;
            IWETH(weth).withdraw(balance);
            (bool success, ) = msg.sender.call{value: balance}("");
            if (!success) {
                revert TransferFailed(msg.sender);
            }
        }
        assembly {
            tstore(0x0, 0)
        }
    }

    /* function placeTriggerOrder(address market) external payable {

    }

    function cancelTriggerOrder(address market) external {

    }

    function placeDCAOrder(address market) external {

    }

    function cancelDCAOrder(address market) external {
        
    }

    function executeTriggerOrders(uint256[] calldata orderids) external {

    } */
    // launchpad
    function createToken(
        string memory name,
        string memory symbol,
        string memory metadataCID,
        string memory description,
        string memory social1,
        string memory social2,
        string memory social3
    ) external returns (address token) {
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
            social3
        ));
        allTokens.push(address(token));
        emit TokenCreated(address(token), msg.sender, name, symbol, metadataCID, description, social1, social2, social3);
        uint256 marketId = allMarkets.length + 1;
        address market;
        parameters = Parameters(weth, token, marketId, 9, 1, 1000000000000000); // maxsize is validated here
        uint256 maxTick;
        (bool result, bytes memory ret) = factories[2].delegatecall(abi.encodeWithSelector(0x1b3671bf, weth, token, marketId)); // can't be traded yet as slot 0 in mapping isn't initialized, and is not in getmarketbyassets either
        if (!result) {
            revert ActionFailed();
        }
        market = abi.decode(ret, (address));
        maxTick = _priceToTick(1000000000000000, 1);
        delete parameters;
        Market storage m = _getMarket[market];
        (m.quoteAsset, m.baseAsset, m.marketId, m.scaleFactor, m.tickSize) = (weth, token, marketId, 9, 1); // immutable params but for _getMarket
        (m.maxPrice, m.marketType, m.creator, m.creatorFeeSplit) = (1000000000000000, 2, msg.sender, uint8(launchpadParams.graduatedCreatorFeeSplit));
        activated[(marketId << 128)] = 1; // index 0
        activated[(marketId << 128) | (maxTick >> 8)] = (1 << (maxTick % 256));
        allMarkets.push(market);
        marketToMarketId[market] = marketId;
        marketIdToMarket[marketId] = market;
        launchpadTokenToMarket[address(token)] = LaunchpadMarket(launchpadParams.launchpadInitialNativeSupply, 1000000000000000000000000000, uint256(launchpadParams.launchpadInitialNativeSupply) * 1000000000000000000000000000, msg.sender, market);
        (result, ret) = market.delegatecall(
            abi.encodeWithSelector(0xf7bb5c88, address(this), (1000000000000000000000000000 * uint256(launchpadParams.launchpadInitialNativeSupply) / 200000000000000000000000000) - uint256(launchpadParams.launchpadInitialNativeSupply), 200000000000000000000000000) // premint
        );
        if (!result) {
            revert ActionFailed();
        }
        (uint256 liquidity) = abi.decode(ret, (uint256));
        IERC20(market).transfer(address(0), liquidity);
        assembly {
            tstore(0x0, 0)
        }
    }

    function buy(bool isExactInput, address token, uint256 amountIn, uint256 amountOut) external payable {
        assembly {
            if tload(0x0) { revert(0, 0) }
            tstore(0x0, 1)
        }
        LaunchpadMarket storage launchpadMarket = launchpadTokenToMarket[token];
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
                claimableRewards[weth][gov] += creatorFee;
                claimableRewards[weth][launchpadMarket.creator] += collectedFee - creatorFee;
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
                    claimableRewards[weth][gov] += creatorFee;
                    claimableRewards[weth][launchpadMarket.creator] += collectedFee - creatorFee;
                    launchpadMarket.virtualNativeReserve = uint112(launchpadMarket.k / 200000000000000000000000000);
                    uint256 oldTokenReserve = launchpadMarket.virtualTokenReserve;
                    launchpadMarket.virtualTokenReserve = uint112(launchpadMarket.k / launchpadMarket.virtualNativeReserve);
                    outputAmount = oldTokenReserve - launchpadMarket.virtualTokenReserve;
                    IERC20(token).transfer(msg.sender, outputAmount);
                }
                else {
                    inputAmount = (preFeeIn * 100000 + launchpadParams.launchpadFee - 1) / launchpadParams.launchpadFee;
                    require(amountOut < launchpadMarket.virtualTokenReserve && inputAmount <= amountIn);
                    uint256 fee = inputAmount - preFeeIn;
                    uint256 creatorFee = (fee * launchpadParams.launchpadCreatorFeeSplit) / 100;
                    claimableRewards[weth][gov] += creatorFee;
                    claimableRewards[weth][launchpadMarket.creator] += (fee - creatorFee);
                    launchpadMarket.virtualNativeReserve = uint112(newNative);
                    launchpadMarket.virtualTokenReserve = uint112(newToken);
                    IWETH(weth).deposit{value: inputAmount}();
                    outputAmount = amountOut;
                    IERC20(token).transfer(msg.sender, amountOut);
                    (bool success, ) = msg.sender.call{value: msg.value - inputAmount}("");
                    if (!success) {
                        revert TransferFailed(msg.sender);
                    } 
                }
            }
            emit LaunchpadTrade(token, msg.sender, true, inputAmount, outputAmount, launchpadMarket.virtualNativeReserve, launchpadMarket.virtualTokenReserve);
            if (launchpadMarket.virtualNativeReserve >= ((launchpadMarket.k / 200000000000000000000000000))) { // graduate
                address market = launchpadMarket.market;
                delete launchpadTokenToMarket[token];
                getMarketByTokens[weth][token] = market;
                getMarketByTokens[token][weth] = market;
                Market storage m = _getMarket[market];
                uint256 minSizeZeroes;
                while (launchpadParams.graduatedMinSize != 0 && launchpadParams.graduatedMinSize % 10 == 0) {
                    launchpadParams.graduatedMinSize /= 10;
                    ++minSizeZeroes;
                }
                (m.lowestAsk, m.minSize, m.takerFee, m.makerRebate, m.isAMMEnabled) = (uint80(1000000000000000), uint40((launchpadParams.graduatedMinSize << 20) | minSizeZeroes), uint24(launchpadParams.graduatedTakerFee), uint24(launchpadParams.graduatedMakerRebate), true); // init market
                emit Migrated(token);
                emit MarketCreated(weth, token, market, marketToMarketId[market], 2, 21, 1, 1000000000000000, launchpadParams.graduatedMinSize, uint24(launchpadParams.graduatedTakerFee), uint24(launchpadParams.graduatedMakerRebate));
                emit Sync(market, 0, 0);
                emit Mint(market, address(this), 0, 0);
            }
        }
        if (isExactInput ? inputAmount < amountIn : outputAmount < amountOut) { // graduated, swap thru amm
            uint256 newInputAmount = (msg.value - inputAmount);
            IWETH(weth).deposit{value: newInputAmount}();
            tokenBalances[0][weth] += newInputAmount;
            if (!isExactInput) {
                newInputAmount = amountOut - outputAmount;
            }
            (bool result, bytes memory ret) = getMarketByTokens[weth][token].delegatecall(abi.encodeWithSelector(0xe690552b, true, isExactInput, (1 << 64), 1, newInputAmount, 0xFFFFFFFFFFFFFFFFFFFF, address(0), msg.sender));
            if (!result) {
                revert ActionFailed();
            }
            uint256 balance;
            if (!isExactInput) {
                balance = tokenBalances[0][weth];
                if (balance != 0) {
                    tokenBalances[0][weth] = 0;
                    IWETH(weth).withdraw(balance);
                    (bool success, ) = msg.sender.call{value: balance}("");
                    if (!success) {
                        revert TransferFailed(msg.sender);
                    }
                }
            }
            (newInputAmount, balance, ) = abi.decode(ret, (uint256, uint256, uint256)); // avoid std
            isExactInput ? outputAmount += balance : inputAmount += newInputAmount;
            assembly {
                tstore(0x0, 0)
            }
        }
        isExactInput ? require(outputAmount >= amountOut) : require(inputAmount <= amountIn);
        assembly {
            tstore(0x0, 0)
        }
    }

    function sell(bool isExactInput, address token, uint256 amountIn, uint256 amountOut) external {
        assembly {
            if tload(0x0) { revert(0, 0) }
            tstore(0x0, 1)
        }
        LaunchpadMarket storage launchpadMarket = launchpadTokenToMarket[token];
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
                claimableRewards[weth][gov] += creatorFee;
                claimableRewards[weth][launchpadMarket.creator] += collectedFee - creatorFee;
                outputAmount = amountAfterFee;
                require(outputAmount >= amountOut);
                IWETH(weth).withdraw(outputAmount);
                (bool success, ) = msg.sender.call{value: outputAmount}("");
                if (!success) {
                    revert TransferFailed(msg.sender);
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
                uint256 fee = outputAmountWithFee - amountOut;
                uint256 creatorFee = (fee * launchpadParams.launchpadCreatorFeeSplit) / 100;
                claimableRewards[weth][gov] += creatorFee;
                claimableRewards[weth][launchpadMarket.creator] += (fee - creatorFee);
                outputAmount = amountOut;
                IWETH(weth).withdraw(amountOut);
                (bool success, ) = msg.sender.call{value: amountOut}("");
                if (!success) {
                    revert TransferFailed(msg.sender);
                }
            }
            emit LaunchpadTrade(token, msg.sender, false, inputAmount, outputAmount, launchpadMarket.virtualNativeReserve, launchpadMarket.virtualTokenReserve);
        }
        else {
            if (isExactInput ? inputAmount < amountIn : outputAmount < amountOut) { // graduated, swap thru amm
                uint256 newInputAmount = amountIn;
                if (!isExactInput) {
                    newInputAmount = amountOut;
                }
                bool result;
                bytes memory ret = abi.encodeWithSelector(0xe690552b, false, isExactInput, (1 << 60), 1, newInputAmount, 1, address(0), msg.sender);
                (result, ret) = getMarketByTokens[weth][token].delegatecall(ret);
                if (!result) {
                    revert ActionFailed();
                }
                uint256 balance = tokenBalances[0][weth];
                if (balance != 0) {
                    tokenBalances[0][weth] = 0;
                    IWETH(weth).withdraw(balance);
                    (bool success, ) = msg.sender.call{value: balance}("");
                    if (!success) {
                        revert TransferFailed(msg.sender);
                    }
                }
                (newInputAmount, balance, ) = abi.decode(ret, (uint256, uint256, uint256)); // avoid std
                isExactInput ? require(balance >= amountOut) : require(newInputAmount <= amountIn);
            }
        }
        assembly {
            tstore(0x0, 0)
        }
    }

    function getVirtualReserves(address token) external view returns (uint256 virtualNativeReserve, uint256 virtualTokenReserve) {
        LaunchpadMarket storage market = launchpadTokenToMarket[token];
        (virtualNativeReserve, virtualTokenReserve) = (market.virtualNativeReserve, market.virtualTokenReserve);
    }
    // referral manager
    function getUsedRef(address user) external view returns (address referrer, string memory refCode) {
        referrer = addressToReferrer[user];
        refCode = addressToRefCode[referrer];
    }

    function setReferral(string memory code) external {
        bytes memory codeBytes = bytes(code);
        for (uint i = 0; i < codeBytes.length; i++) {
            if (codeBytes[i] >= 0x41 && codeBytes[i] <= 0x5A) {
                codeBytes[i] = bytes1(uint8(codeBytes[i]) + 32);
            }
        }
        code = string(codeBytes);
        if (refCodeToAddress[code] != address(0) || bytes(code).length == 0) {
            revert RefCodeAlreadyTaken();
        }
        if (bytes(addressToRefCode[msg.sender]).length != 0) {
            refCodeToAddress[addressToRefCode[msg.sender]] = address(0);
        }
        addressToRefCode[msg.sender] = code;
        refCodeToAddress[code] = msg.sender;
    }

    function setUsedRef(string memory code) external {
        bytes memory codeBytes = bytes(code);
        for (uint i = 0; i < codeBytes.length; i++) {
            if (codeBytes[i] >= 0x41 && codeBytes[i] <= 0x5A) {
                codeBytes[i] = bytes1(uint8(codeBytes[i]) + 32);
            }
        }
        code = string(codeBytes);
        if (addressToReferrer[msg.sender] != address(0)) {
            referrerToReferredAddressCount[addressToReferrer[msg.sender]] -= 1;
        }
        address referrer = refCodeToAddress[code];
        addressToReferrer[msg.sender] = referrer;
        emit Referral(referrer, msg.sender);
        if (referrer != address(0) && bytes(code).length != 0) {
            ++referrerToReferredAddressCount[referrer];
        }
    }
}