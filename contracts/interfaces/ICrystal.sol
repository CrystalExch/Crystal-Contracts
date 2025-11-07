// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface ICrystal {
    struct InternalOrder { //  bit is if maker wants internal balance (1) or tokens (0) order is stored at either marketid << 128 | price << 48 | id or cloid << 41 | userid; no collision because marketid seperates cloid orders from non cloid, userid prevents cloid collisions, and price n id are always unique
        uint256 size; //uint112 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF
        uint256 orderType; // uint1 0x1
        uint256 userId; // uint41 0x1FFFFFFFFFF
        uint256 fillBefore; // uint51 0x7FFFFFFFFFFFF
        uint256 fillAfter; // uint51 0x7FFFFFFFFFFFF
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

    struct PriceLevel { 
        uint256 size; // uint112 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF
        // gap uint1 0x1
        uint256 latestNativeId; // uint41 0x1FFFFFFFFFF
        uint256 latest; // uint51 0x7FFFFFFFFFFFF
        uint256 fillNext; // uint51 0x7FFFFFFFFFFFF
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
        uint88 createTimestamp;
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

    struct TokenMetadata {
        address token;
        uint256 decimals;
        string ticker;
        string name;
    }

    struct MarketDetails {
        uint256 marketId;
        uint256 marketType;
        uint256 scaleFactor;
        uint256 tickSize;
        uint256 maxPrice;
        uint256 minSize;
        uint256 takerFee;
        uint256 makerRebate;
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
        uint256 marketType;
        uint256 scaleFactor; // uint127
        uint256 tickSize; // uint80
        uint256 maxPrice; // uint80
    }
    
    struct LaunchpadMarket {
        uint112 virtualNativeReserve;
        uint112 virtualTokenReserve;
        uint256 k;
        address creator;
        address market;
        uint88 createTimestamp;
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

    event MarketCreated(bool indexed isCanonical, address indexed quoteAsset, address indexed baseAsset, address market, ICrystal.TokenMetadata quoteInfo, ICrystal.TokenMetadata baseInfo, ICrystal.MarketDetails marketInfo);
    event MarketParamsChanged(address indexed market, uint256 minSize, uint24 takerFee, uint24 makerRebate, bool isAMMEnabled);
    event GovChanged(address prev, address gov);
    event UserRegistered(bool indexed isMargin, address indexed user, uint256 indexed userId);
    event Deposit(address indexed user, uint256 indexed userId, address indexed token, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed userId, address indexed token, uint256 amount);
    event RewardsClaimed(address indexed user, address[] tokens, uint256[] amounts);
    event Trade(address indexed market, address indexed user, bool isBuy, uint256 amountIn, uint256 amountOut, uint256 startPrice, uint256 endPrice);
    event OrdersUpdated(address indexed market, address indexed user, bytes orderData);
    event Fill(address indexed market, address indexed user, uint256 fillInfo, uint256 fillAmount); // fillinfo is price id remaining size

    event TokenCreated(address indexed token, address indexed creator, string name, string symbol, string metadataCID, string description, string social1, string social2, string social3, string social4);
    event Migrated(address indexed token);
    event LaunchpadTrade(address indexed token, address indexed user, bool isBuy, uint256 amountIn, uint256 amountOut, uint256 virtualNativeReserve, uint256 virtualTokenReserve);
    event Mint(address indexed market, address indexed sender, uint amountQuote, uint amountBase);
    event Burn(address indexed market, address indexed sender, uint amountQuote, uint amountBase, address indexed to);
    event Sync(address indexed market, uint112 reserve0, uint112 reserve1);

    error Unauthorized(address user);
    error ActionFailed();
    error AccountLimitReached();
    error SlippageExceeded();
    error Expired(uint256 timestamp);
    error TransferFailed(address recipient);
    error InvalidPath(address[] path);
    error InvalidMarket(address asset0, address asset1);
    
    function feeRecipient() external view returns (address);
    function feeCommission() external view returns (uint8);
    function userIdToAddress(uint256) external view returns (address);
    function addressToUserId(address) external view returns (uint256);
    function claimableRewards(address, address) external view returns (uint256);
    function latestUserId() external view returns (uint256);
    function gov() external view returns (address);
    function feeClaimDuration() external view returns (uint256);
    function pendingClosedMarkets(address user) external view returns (uint256);
    function isCanonicalDeployer(address) external view returns (bool);
    function approvedForwarder(address, address) external view returns (bool);
    function marketToMarketId(address) external view returns (uint256);
    function marketIdToMarket(uint256) external view returns (address);
    function getMarketByTokens(address, address) external view returns (address);
    function allMarkets(uint256) external view returns (address);
    function parameters() external view returns (address, address, uint256, uint256, uint256, uint256, uint256);
    function launchpadParams() external view returns (uint112, uint256, uint256, uint256, uint256, uint256, uint256);
    function launchpadTokenToMarket(address) external view returns (uint112, uint112, uint256, address, address, uint88);
    function allTokens(uint256) external view returns (address);
    function weth() external view returns (address);
    function eth() external view returns (address);

    function allMarketsLength() external view returns (uint256);
    function getMarket(address market) external view returns (MarketInfo memory);
    function getDepositedBalance(address user, address asset) external view returns (uint256, uint256, uint256);
    function getAllOrdersByCloid(address user, uint256 range) external view returns (uint256[] memory, Order[] memory);
    function getOrderByCloid(uint256 userId, uint256 cloid) external view returns (Order memory);
    function getOrder(address market, uint256 price, uint256 id) external view returns (Order memory);
    function getPriceLevel(address market, uint256 price) external view returns (PriceLevel memory);
    function getPriceLevels(address market, bool isAscending, uint256 startPrice, uint256 distance, uint256 interval, uint256 max) external returns (bytes memory);
    function getPriceLevelsFromMid(address market, uint256 distance, uint256 interval, uint256 max) external returns (uint256, uint256, bytes memory, bytes memory);
    function getPrice(address market) external returns (uint256, uint256, uint256);
    function getQuote(address market, bool isBuy, bool isExactInput, bool isCompleteFill, uint256 size, uint256 worstPrice) external returns (uint256, uint256);
    function deploy(bool isCanonical, address quoteAsset, address baseAsset, uint256 marketType, uint256 scaleFactor, uint256 tickSize, uint256 maxPrice, uint256 minSize, uint24 takerFee, uint24 makerRebate) external returns (address);
    function registerUser(address caller) external returns (uint256);
    function deposit(address token, uint256 amount) external payable returns (uint256);
    function withdraw(address to, address token, uint256 amount) external;
    function routerDeposit(address token, uint256 amount) external payable;
    function routerWithdraw(address to, address token, uint256 amount) external;
    function claimFees(address to, address[] calldata tokens) external returns (uint256[] memory);
    function queueClaimExpiredFees(address user, address[] calldata tokens) external;
    function executeClaimExpiredFees(address user) external returns (uint256[] memory);
    function changeGov(address newGov) external;
    function changeFeeRecipient(address newFeeRecipient) external;
    function changeFeeClaimDuration(uint256 newFeeClaimDuration) external;
    function changeRefFeeCommission(uint8 newFeeCommission) external;
    function changeMarketParams(address market, uint256 newMinSize, uint24 newTakerFee, uint24 newMakerRebate, bool isAMMEnabled, bool isCanonical) external;
    function changeMarketCreatorFee(address market, address newCreator, uint256 newCreatorFee) external;
    function changeLaunchpadParams(LaunchpadParams memory newLaunchpadParams) external;
    function addCanonicalDeployer(address deployer) external;
    function removeCanonicalDeployer(address deployer) external;
    function approveForwarder(address forwarder) external;
    function removeForwarder(address forwarder) external;
    function clearCloidSlots(uint256 userId, uint256[] calldata ids) external;
    function getReserves(address market) external returns (uint112, uint112);
    function addLiquidity(address market, address to, uint256 amountQuoteDesired, uint256 amountBaseDesired, uint256 amountQuoteMin, uint256 amountBaseMin) external payable returns (uint256);
    function removeLiquidity(address market, address to, uint256 liquidity, uint256 amountQuoteMin, uint256 amountBaseMin) external returns (uint256, uint256);
    function removeLiquidityETH(address market, address to, uint256 liquidity, uint256 amountQuoteMin, uint256 amountBaseMin) external returns (uint256 amountQuote, uint256 amountBase);
    function marketOrder(address market, bool isBuy, bool isExactInput, uint256 options, uint256 orderType, uint256 size, uint256 worstPrice, address referrer, address user) external returns (uint256, uint256, uint256);
    function limitOrder(address market, bool isBuy, uint256 options, uint256 price, uint256 size, address user) external returns (uint256);
    function cancelOrder(address market, uint256 options, uint256 price, uint256 id, address user) external returns (uint256);
    function replaceOrder(address market, uint256 options, uint256 price, uint256 id, uint256 newPrice, uint256 size, address referrer, address user) external returns (uint256);
    function batchOrders(address market, Action[] calldata actions, uint256 options, uint256 deadline, address referrer, address user) external payable;
    function getAmountsOut(uint256 amountIn, address[] memory path) external returns (uint256[] memory);
    function getAmountsIn(uint256 amountOut, address[] memory path) external returns (uint256[] memory);
    function swapExactETHForTokens(uint256 amountOutMin, address[] memory path, address to, uint256 deadline, address referrer) external payable returns (uint256[] memory);
    function swapExactTokensForETH(uint256 amountIn, uint256 amountOutMin, address[] memory path, address to, uint256 deadline, address referrer) external returns (uint256[] memory);
    function swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, address[] memory path, address to, uint256 deadline, address referrer) external returns (uint256[] memory);
    function swapETHForExactTokens(uint256 amountOut, address[] memory path, address to, uint256 deadline, address referrer) external payable returns (uint256[] memory);
    function swapTokensForExactETH(uint256 amountOut, uint256 amountInMax, address[] memory path, address to, uint256 deadline, address referrer) external returns (uint256[] memory);
    function swapTokensForExactTokens(uint256 amountOut, uint256 amountInMax, address[] memory path, address to, uint256 deadline, address referrer) external returns (uint256[] memory);
    function swap(bool exactInput, address tokenIn, address tokenOut, uint256 orderType, uint256 size, uint256 worstPrice, uint256 deadline, address referrer) external payable returns (uint256, uint256, uint256);
    function placeLimitOrder(address tokenIn, address tokenOut, uint256 price, uint256 size, uint256 deadline) external payable returns (uint256);
    function cancelLimitOrder(address tokenIn, address tokenOut, uint256 price, uint256 id, uint256 deadline) external returns (uint256);
    function replaceOrder(bool isPostOnly, bool isDecrease, address tokenIn, address tokenOut, uint256 price, uint256 id, uint256 newPrice, uint256 newSize, uint256 deadline, address referrer) external payable returns (uint256);
    function multiBatchOrders(Batch[] calldata batches, uint256 deadline, address referrer) external payable;
    function createToken(string memory name,string memory symbol,string memory metadataCID,string memory description,string memory social1,string memory social2,string memory social3,string memory social4) external payable returns (address token);
    function buy(bool isExactInput, address token, uint256 amountIn, uint256 amountOut) external payable returns (uint256, uint256, bool);
    function sell(bool isExactInput, address token, uint256 amountIn, uint256 amountOut) external returns (uint256, uint256);
    function quoteBuy(bool isExactInput, address token, uint256 amountIn, uint256 amountOut) external returns (uint256, uint256, bool);
    function quoteSell(bool isExactInput, address token, uint256 amountIn, uint256 amountOut) external returns (uint256, uint256);
    function getVirtualReserves(address token) external view returns (uint256, uint256);
    function queueCloseInactiveMarket(address token) external;
    function executeCloseInactiveMarket(address token) external returns (uint256 amountQuote, uint256 amountBase);
    function lockZeroAddressLiquidity(address market) external;
}