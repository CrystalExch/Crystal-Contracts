// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface ICrystal {
    // ---------- Structs ----------
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

    struct Order {
        bool isBuy;
        address market;
        uint256 price;
        uint256 size;
        uint256 orderType;
        uint256 userId;
        uint256 fillBefore;
        uint256 fillAfter;
    }

    struct PriceLevel {
        uint256 size;
        uint256 latestNativeId;
        uint256 latest;
        uint256 fillNext;
    }

    struct Action {
        bool isRequireSuccess;
        uint256 action;
        uint256 param1;
        uint256 param2;
        uint256 param3;
    }

    struct Batch {
        address market;
        Action[] actions;
        uint256 options;
    }

    struct Parameters {
        address quoteAsset;
        address baseAsset;
        uint256 marketId;
        uint256 scaleFactor;
        uint256 tickSize;
        uint256 maxPrice;
    }

    struct LaunchpadParams {
        uint112 launchpadInitialNativeSupply;
        uint256 launchpadMinSize;
        uint256 launchpadGraduationPrice;
        uint256 launchpadFee;
        uint256 launchpadTakerFee;
        uint256 launchpadMakerRebate;
        uint256 creatorFeeSplit;
    }

    struct PendingExpiredFeeClaim {
        uint256 deadline;
        address[] tokens;
        uint256[] amounts;
    }

    // ---------- Public Variables ----------
    function feeRecipient() external view returns (address);
    function feeCommission() external view returns (uint8);
    function feeRebate() external view returns (uint8);
    function userIdToAddress(uint256) external view returns (address);
    function addressToUserId(address) external view returns (uint256);
    function claimableRewards(address, address) external view returns (uint256);
    function latestUserId() external view returns (uint256);
    function gov() external view returns (address);
    function feeClaimDuration() external view returns (uint256);
    function pendingExpiredFeeClaims(address) external view returns (uint256 deadline, address[] memory tokens, uint256[] memory amounts);
    function marginAccounts(address) external view returns (uint256);
    function getMarketByTokens(address, address) external view returns (address);
    function marketToMarketId(address) external view returns (uint256);
    function marketIdToMarket(uint256) external view returns (address);
    function isCanonicalDeployer(address) external view returns (bool);
    function isKeeper(address) external view returns (bool);
    function allMarkets(uint256) external view returns (address);
    function parameters() external view returns (address, address, uint256, uint256, uint256, uint256);
    function launchpadParams() external view returns (uint112, uint256, uint256, uint256, uint256, uint256, uint256);
    function launchpadTokenToMarket(address) external view returns (uint112, uint112, uint256, address, address);
    function allTokens(uint256) external view returns (address);
    function refCodeToAddress(string calldata) external view returns (address);
    function addressToRefCode(address) external view returns (string memory);
    function referrerToReferredAddressCount(address) external view returns (uint256);
    function addressToReferrer(address) external view returns (address);
    function factories(uint256) external view returns (address);
    function weth() external view returns (address);
    function eth() external view returns (address);

    // ---------- Events ----------
    event MarketCreated(address indexed quoteAsset, address indexed baseAsset, address market, uint256 marketId, uint256 marketType, uint256 scaleFactor, uint256 tickSize, uint256 maxPrice, uint256 minSize, uint24 takerFee, uint24 makerRebate);
    event MarketParamsChanged(address indexed market, uint256 minSize, uint24 takerFee, uint24 makerRebate, bool isAMMEnabled);
    event GovChanged(address prev, address gov);
    event UserRegistered(bool indexed isMargin, address indexed caller, uint256 indexed userId);
    event Deposit(address indexed caller, uint256 indexed userId, address indexed token, uint256 amount);
    event Withdraw(address indexed caller, uint256 indexed userId, address indexed token, uint256 amount);
    event RewardsClaimed(address indexed caller, address[] tokens, uint256[] amounts);
    event Trade(address indexed market, uint256 indexed userId, address indexed user, bool isBuy, uint256 amountIn, uint256 amountOut, uint256 startPrice, uint256 endPrice);
    event OrdersUpdated(address indexed market, uint256 indexed userId, bytes orderData);
    event OrderFilled(address indexed market, uint256 indexed userId, uint256 fillInfo, uint256 fillAmount);
    event TokenCreated(address indexed token, address indexed creator, string name, string symbol, string metadataCID, string description, string social1, string social2, string social3);
    event Migrated(address indexed token);
    event LaunchpadTrade(address indexed token, address indexed user, bool isBuy, uint256 amountIn, uint256 amountOut, uint256 virtualNativeReserve, uint256 virtualTokenReserve);
    event Mint(address indexed market, address indexed sender, uint amountQuote, uint amountBase);
    event Sync(address indexed market, uint112 reserve0, uint112 reserve1);
    event Referral(address indexed referrer, address referee);

    // ---------- Errors ----------
    error Unauthorized(address caller);
    error ActionFailed();
    error AccountLimitReached();
    error SlippageExceeded();
    error Expired(uint256 timestamp);
    error TransferFailed(address recipient);
    error InvalidPath(address[] path);
    error InvalidMarket(address asset0, address asset1);
    error RefCodeAlreadyTaken();

    // ---------- Functions ----------
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
    function registerNewMarginAccount() external returns (uint256);
    function deposit(address token, uint256 amount) external returns (uint256);
    function withdraw(address to, address token, uint256 amount) external;
    function depositNative() external payable returns (uint256);
    function withdrawNative(address to, uint256 amount) external;
    function claimFees(address to, address[] calldata tokens) external returns (uint256[] memory);
    function queueClaimExpiredFees(address user, address[] calldata tokens) external;
    function executeClaimExpiredFees(address user) external returns (uint256[] memory);
    function changeGov(address newGov) external;
    function changeFeeRecipient(address newFeeRecipient) external;
    function changeFeeClaimDuration(uint256 newFeeClaimDuration) external;
    function changeRefFeeStructure(uint8 newFeeCommission, uint8 newFeeRebate) external;
    function changeMarketParams(address market, uint256 newMinSize, uint24 newTakerFee, uint24 newMakerRebate, bool isAMMEnabled, bool isCanonical) external;
    function changeLaunchpadParams(LaunchpadParams memory newLaunchpadParams) external;
    function addCanonicalDeployer(address deployer) external;
    function removeCanonicalDeployer(address deployer) external;
    function clearCloidSlots(uint256 userId, uint256[] calldata ids) external;
    function getReserves(address market) external returns (uint112, uint112);
    function ammDeposit(address market, address to, uint256 amountQuoteDesired, uint256 amountBaseDesired, uint256 amountQuoteMin, uint256 amountBaseMin) external returns (uint256);
    function ammWithdraw(address market, address to, uint256 liquidity, uint256 amountQuoteMin, uint256 amountBaseMin) external returns (uint256, uint256);
    function marketOrder(address market, bool isBuy, bool isExactInput, uint256 options, uint256 orderType, uint256 size, uint256 worstPrice, address referrer) external returns (uint256, uint256, uint256);
    function limitOrder(address market, bool isBuy, uint256 options, uint256 price, uint256 size) external returns (uint256);
    function cancelOrder(address market, uint256 options, uint256 price, uint256 id) external returns (uint256);
    function replaceOrder(address market, uint256 options, uint256 price, uint256 id, uint256 newPrice, uint256 size, address referrer) external returns (uint256);
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
    function batchOrders(address market, Action[] calldata actions, uint256 options, address referrer) external payable;
    function multiBatchOrders(Batch[] calldata batches, address referrer) external payable;
    function createToken(string memory name,string memory symbol,string memory metadataCID,string memory description,string memory social1,string memory social2,string memory social3) external;
    function buy(address token, uint256 amountOutMin) external payable;
    function sell(address token, uint256 amountIn, uint256 amountOutMin) external;
    function getVirtualReserves(address token) external view returns (uint256, uint256);
    function getUsedRef(address user) external view returns (address, string memory);
    function setReferral(string memory code) external;
    function setUsedRef(string memory code) external;
}