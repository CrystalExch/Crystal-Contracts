// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;
import "hardhat/console.sol";

interface IERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);
    function transfer(address to, uint value) external returns (bool);
    function approve(address spender, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);
    function mint(address to, uint256 value) external;
    function burn(address from, uint256 value) external;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IWETH {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);
    function transfer(address to, uint value) external returns (bool);
    function approve(address spender, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);
    function deposit() external payable;
    function withdraw(uint amount) external;

    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed owner, address indexed spender, uint value);
    event Deposit(address indexed to, uint amount);
    event Withdrawal(address indexed to, uint amount);
}

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
    function registerUser() external returns (uint256);
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

contract CrystalToken {
    struct TokenMetaData {
        string name;
        string symbol;
        string metadataCID;
        string description;
        string social1;
        string social2;
        string social3;  
    }

    string public name;
    string public symbol;
    TokenMetaData public metadata;

    uint8 public constant decimals = 18;
    uint256 public constant totalSupply = 1000000000000000000000000000;

    address public immutable crystal;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    bytes32 public DOMAIN_SEPARATOR;
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint256) public nonces;

    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);

    constructor(
        address _crystal,
        string memory _name,
        string memory _symbol,
        string memory _metadataCID,
        string memory _description,
        string memory _social1,
        string memory _social2,
        string memory _social3
    ) {
        crystal = _crystal;
        name = _name;
        symbol = _symbol;
        metadata = TokenMetaData(_name, _symbol, _metadataCID, _description, _social1, _social2, _social3);
        _mint(_crystal, totalSupply);
    }

    function _mint(address to, uint256 value) internal {
        balanceOf[to] += value;
        emit Transfer(address(0), to, value);
    }

    function _burn(address from, uint256 value) internal {
        balanceOf[from] -= value;
        emit Transfer(from, address(0), value);
    }

    function _approve(address owner, address spender, uint256 value) private {
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _transfer(address from, address to, uint256 value) private {
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
    }

    function approve(address spender, uint256 value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max && to != crystal) {
            allowance[from][msg.sender] -= value;
        }
        _transfer(from, to, value);
        return true;
    }

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(deadline >= block.timestamp, 'UniswapV2: EXPIRED');
        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01',
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, 'UniswapV2: INVALID_SIGNATURE');
        _approve(owner, spender, value);
    }
}

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
    uint256 public latestUserId;
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
        require(_launchpadParams.graduatedMinSize < 0xFFFFF && minSizeZeroes < 0xFFFFF && _launchpadParams.launchpadInitialNativeSupply > 1e18 && _launchpadParams.launchpadFee < 1000 && 90000 <= _launchpadParams.graduatedTakerFee);
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

    function _registerUser(uint256 acctType) internal returns (uint256 _latestUserId) { // 0 default 1 margin
        if (acctType == 0) {
            require(addressToUserId[msg.sender] == 0);
            _latestUserId = latestUserId;
            _latestUserId++;
            addressToUserId[msg.sender] = _latestUserId;
            userIdToAddress[_latestUserId] = msg.sender;
            latestUserId = _latestUserId;
            emit UserRegistered(false, msg.sender, _latestUserId);
        }
        else {
            _latestUserId = latestUserId;
            _latestUserId++;
            userIdToAddress[_latestUserId] = msg.sender;
            latestUserId = _latestUserId;
            uint256 _marginAccounts = marginAccounts[msg.sender];
            uint256 i;
            for (i = 0; i < 256; i += 41) {
                if (((_marginAccounts >> i) & 0x1FFFFFFFFFF) == 0) {
                    _marginAccounts |= (_latestUserId << i);
                    break;
                }
            }
            if (i > 255 || _latestUserId > 0x1FFFFFFFFFF) revert AccountLimitReached(); // overflow uint36
            marginAccounts[msg.sender] = _marginAccounts;
            emit UserRegistered(true, msg.sender, _latestUserId);
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

    function registerUser() external returns (uint256 userId) {
        userId = _registerUser(0);
    }

    function registerNewMarginAccount() external returns (uint256 userId) {
        userId = _registerUser(1);
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
            userId = _registerUser(0);
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
            userId = _registerUser(0);
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
        require(newLaunchpadParams.graduatedMinSize < 0xFFFFF && minSizeZeroes < 0xFFFFF && newLaunchpadParams.launchpadInitialNativeSupply > 1e18 && newLaunchpadParams.launchpadFee < 1000 && 90000 <= newLaunchpadParams.graduatedTakerFee);
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
        uint256 userId = addressToUserId[msg.sender];
        if (userId == 0) {
            userId = _registerUser(0);
        }
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
        uint256 userId = addressToUserId[msg.sender];
        if (userId == 0) {
            userId = _registerUser(0);
        }
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

    function batchOrders(address market, Action[] calldata actions, uint256 options, address referrer) external payable {
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

    function multiBatchOrders(Batch[] calldata batches, address referrer) external payable {
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
                if (launchpadMarket.virtualNativeReserve + (inputAmount - ((inputAmount * launchpadParams.launchpadFee) / 10000)) > (launchpadMarket.k / 200000000000000000000000000)) {
                    inputAmount = (((launchpadMarket.k / 200000000000000000000000000) - launchpadMarket.virtualNativeReserve) * 10000) / (10000 - launchpadParams.launchpadFee);
                }
                IWETH(weth).deposit{value: inputAmount}();
                uint256 collectedFee = (inputAmount * launchpadParams.launchpadFee) / 10000;
                uint256 creatorFee = collectedFee * launchpadParams.launchpadCreatorFeeSplit / 100;
                claimableRewards[weth][gov] += creatorFee;
                claimableRewards[weth][launchpadMarket.creator] += collectedFee - creatorFee;
                launchpadMarket.virtualNativeReserve += uint112(inputAmount - collectedFee);
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
                    inputAmount = (((launchpadMarket.k / 200000000000000000000000000) - launchpadMarket.virtualNativeReserve) * 10000) / (10000 - launchpadParams.launchpadFee);
                    IWETH(weth).deposit{value: inputAmount}();
                    uint256 collectedFee = (inputAmount * launchpadParams.launchpadFee) / 10000;
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
                    inputAmount = (preFeeIn * 10000 + 10000 - launchpadParams.launchpadFee - 1) / (10000 - launchpadParams.launchpadFee);
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
                uint256 collectedFee = (outputAmount * launchpadParams.launchpadFee) / 10000;
                uint256 creatorFee = collectedFee * launchpadParams.launchpadCreatorFeeSplit / 100;
                claimableRewards[weth][gov] += creatorFee;
                claimableRewards[weth][launchpadMarket.creator] += collectedFee - creatorFee;
                outputAmount -= collectedFee;
                require(outputAmount >= amountOut);
                IWETH(weth).withdraw(outputAmount);
                (bool success, ) = msg.sender.call{value: outputAmount}("");
                if (!success) {
                    revert TransferFailed(msg.sender);
                }
            }
            else {
                uint256 denom = 10000 - launchpadParams.launchpadFee;
                uint256 outputAmountWithFee = (amountOut * 10000 + denom - 1) / denom;
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

contract CrystalMarket0 { // support for margin, doesn't have to be enabled, static tick size no amm
    struct PriceLevel { 
        uint256 size; // uint112 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF
        // gap uint1 0x1
        uint256 latestNativeId; // uint41 0x1FFFFFFFFFF
        uint256 latest; // uint51 0x7FFFFFFFFFFFF
        uint256 fillNext; // uint51 0x7FFFFFFFFFFFF
    }

    struct InternalOrder { //  bit is if maker wants internal balance (1) or tokens (0) order is stored at either marketid << 128 | price << 48 | id or cloid << 41 | userid; no collision because marketid seperates cloid orders from non cloid, userid prevents cloid collisions, and price n id are always unique
        uint256 size; //uint112 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF
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

    struct Action {
        bool isRequireSuccess;
        uint256 action;
        uint256 param1; // price
        uint256 param2; // size/id
        uint256 param3; // cloid
    }

    address feeRecipient; // public is useless so everything isn't
    uint8 feeCommission;
    uint8 feeRebate;

    mapping (uint256 => address) userIdToAddress; // 0 is an invalid userid
    mapping (address => uint256) addressToUserId;
    mapping (address => Market) _getMarket;
    mapping (uint256 => uint256) activated; // marketid << 128 | slotindex
    mapping (uint256 => uint256) priceLevels; // 0 is an invalid price marketid << 128 | price
    mapping (uint256 => uint256) orders; // 0 is an invalid cloid, valid range 1-1023 mask 0x3FF; marketid << 128 | price << 48 | id or userid << 41 | cloid
    mapping (uint256 => uint256) cloidVerify; // two cloids per slot map market and price, never zero slot 1 << 255 | marketId << 208 | price << 128 | marketId << 80 | price
    mapping (uint256 => mapping (address => uint256)) tokenBalances;
    mapping (address => mapping (address => uint256)) claimableRewards;

    address public immutable quoteAsset;
    address public immutable baseAsset;
    address public immutable crystal;
    uint256 public immutable scaleFactor;
    uint256 public immutable tickSize;
    uint256 public immutable maxPrice;
    address private immutable market; // address of market even when delegate called
    uint256 private immutable marketId; // 0 is an invalid marketid, is already << 128

    event Trade(address indexed market, uint256 indexed userId, address indexed user, bool isBuy, uint256 amountIn, uint256 amountOut, uint256 startPrice, uint256 endPrice);
    event OrdersUpdated(address indexed market, uint256 indexed userId, bytes orderData);
    event OrderFilled(address indexed market, uint256 indexed userId, uint256 fillInfo, uint256 fillAmount) anonymous; // fillinfo is isSell << 252 | price << 168 | id << 112 | remaining size

    error SlippageExceeded();
    error ActionFailed();

    constructor() {
        (quoteAsset, baseAsset, marketId, scaleFactor, tickSize, maxPrice) = ICrystal(msg.sender).parameters();
        marketId <<= 128;
        scaleFactor = 10 ** scaleFactor;
        market = address(this);
        crystal = msg.sender;
        require(quoteAsset != address(0) && baseAsset != address(0) && quoteAsset != baseAsset && maxPrice <= 0xFFFFFFFFFFFFFFFFFFFF && tickSize <= 0xFFFFFFFFFFFFFFFFFFFF && scaleFactor <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
    }

    function _searchSlotUp(uint256 slot, uint256 tick) internal pure returns (uint256) {
        if (slot & ((1 << 128) - 1) == 0) {slot >>= 128; tick += 128;}
        if (slot & ((1 << 64) - 1) == 0) {slot >>= 64; tick += 64;}
        if (slot & ((1 << 32) - 1) == 0) {slot >>= 32; tick += 32;}
        if (slot & ((1 << 16) - 1) == 0) {slot >>= 16; tick += 16;}
        if (slot & ((1 << 8) - 1) == 0) {slot >>= 8; tick += 8;}
        if (slot & ((1 << 4) - 1) == 0) {slot >>= 4; tick += 4;}
        if (slot & ((1 << 2) - 1) == 0) {slot >>= 2; tick += 2;}
        if (slot & 1 == 0) {++tick;}
        return tick;
    }

    function _searchSlotDown(uint256 slot, uint256 tick) internal pure returns (uint256) {
        if (slot >= 2 ** 128) {slot >>= 128; tick += 128;}
        if (slot >= 2 ** 64) {slot >>= 64; tick += 64;}
        if (slot >= 2 ** 32) {slot >>= 32; tick += 32;}
        if (slot >= 2 ** 16) {slot >>= 16; tick += 16;}
        if (slot >= 2 ** 8) {slot >>= 8; tick += 8;}
        if (slot >= 2 ** 4) {slot >>= 4; tick += 4;}
        if (slot >= 2 ** 2) {slot >>= 2; tick += 2;}
        if (slot >= 2 ** 1) {++tick;}
        return tick;
    }

    function _settleBalances(address caller, int256 quoteAssetDebt, int256 baseAssetDebt, uint256 userId, uint256 balanceMode, uint256 balanceModeOut, uint256 balanceModeIn) internal {
        if (balanceMode == 0) { // external txfers
            if (balanceModeIn != 0) {
                if (quoteAssetDebt > 0) {
                    uint256 balance = tokenBalances[0][quoteAsset];
                    if (uint128(balance) < uint256(quoteAssetDebt)) {
                        revert ActionFailed();
                    }
                    else {
                        tokenBalances[0][quoteAsset] = balance - uint256(quoteAssetDebt);
                    }
                }
                if (baseAssetDebt > 0) {
                    uint256 balance = tokenBalances[0][baseAsset];
                    if (uint128(balance) < uint256(baseAssetDebt)) {
                        revert ActionFailed();
                    }
                    else {
                        tokenBalances[0][baseAsset] = balance - uint256(baseAssetDebt);
                    }
                }
            }
            else {
                if (quoteAssetDebt > 0) {
                    IERC20(quoteAsset).transferFrom(caller, address(this), uint256(quoteAssetDebt));
                }
                if (baseAssetDebt > 0) {
                    IERC20(baseAsset).transferFrom(caller, address(this), uint256(baseAssetDebt));
                }
            }
            if (balanceModeOut != 0) {
                if (quoteAssetDebt < 0) {
                    tokenBalances[0][quoteAsset] += uint256(-quoteAssetDebt);
                }
                if (baseAssetDebt < 0) {
                    tokenBalances[0][baseAsset] += uint256(-baseAssetDebt);
                }
            }
            else {
                if (quoteAssetDebt < 0) {
                    IERC20(quoteAsset).transfer(caller, uint256(-quoteAssetDebt));
                }
                if (baseAssetDebt < 0) {
                    IERC20(baseAsset).transfer(caller, uint256(-baseAssetDebt));
                }
            }
        }
        else {
            if (balanceMode == 1) { // internal balances
                if (quoteAssetDebt > 0) {
                    uint256 balance = tokenBalances[userId][quoteAsset];
                    if (uint128(balance) < uint256(quoteAssetDebt)) {
                        revert ActionFailed();
                    }
                    else {
                        tokenBalances[userId][quoteAsset] = balance - uint256(quoteAssetDebt);
                    }
                }
                else if (quoteAssetDebt < 0) {
                    tokenBalances[userId][quoteAsset] += uint256(-quoteAssetDebt);
                }
                if (baseAssetDebt > 0) {
                    uint256 balance = tokenBalances[userId][baseAsset];
                    if (uint128(balance) < uint256(baseAssetDebt)) {
                        revert ActionFailed();
                    }
                    else {
                        tokenBalances[userId][baseAsset] = balance - uint256(baseAssetDebt);
                    }
                }
                else if (baseAssetDebt < 0) {
                    tokenBalances[userId][baseAsset] += uint256(-baseAssetDebt);
                }
            }
            else {
                revert ActionFailed();
            }
        }
    }

    function _internalCancel(uint256 price, uint256 id, uint256 size, uint256 _highestBid, uint256 _lowestAsk, uint256 _order) internal {
        uint256 _priceLevel = priceLevels[marketId | price];
        _priceLevel -= size; // can't overflow
        if (id == (_priceLevel >> 205 & 0x7FFFFFFFFFFFF)) { // if pricelevel fillnext then set to fillafter
            _priceLevel = (_order & (0x7FFFFFFFFFFFF << 205)) | (_priceLevel & 0x0000000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
        }
        else if (id == (_priceLevel >> 154 & 0x7FFFFFFFFFFFF)) { // if pricelevel latest then set latest to fillbefore
            uint256 temp = ((((_order >> 154) & 0x7FFFFFFFFFFFF) > 0x1FFFFFFFFFF) ? ((_order >> 154) & 0x7FFFFFFFFFFFF) : marketId | (price << 48) | ((_order >> 154) & 0x7FFFFFFFFFFFF));
            orders[temp] = orders[temp] & 0x0000000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF | (_order & (0x7FFFFFFFFFFFF << 205)); // set fillbefores fillafter to fillafter
            _priceLevel = (_priceLevel & 0xFFFFFFFFFFFFE0000000000003FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) | (_order & (0x7FFFFFFFFFFFF << 154));
        }
        else {           
            uint256 temp = (((_order >> 154) & 0x7FFFFFFFFFFFF > 0x1FFFFFFFFFF) ? (_order >> 154) & 0x7FFFFFFFFFFFF : marketId | (price << 48) | (_order >> 154) & 0x7FFFFFFFFFFFF);
            orders[temp] = orders[temp] & 0x0000000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF | (_order & (0x7FFFFFFFFFFFF << 205)); // set fillbefores fillafter to fillafter
            temp = ((((_order >> 205) & 0x7FFFFFFFFFFFF) > 0x1FFFFFFFFFF) ? ((_order >> 205) & 0x7FFFFFFFFFFFF) : marketId | (price << 48) | ((_order >> 205) & 0x7FFFFFFFFFFFF));
            orders[temp] = orders[temp] & 0xFFFFFFFFFFFFE0000000000003FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF | (_order & (0x7FFFFFFFFFFFF << 154)); // setfillafters fillbefore to fillbefore
        }
        priceLevels[marketId | price] = _priceLevel;
        if ((_priceLevel & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) == 0) {
            uint256 tick = price / tickSize;
            uint256 slotIndex = tick >> 8;
            uint256 _slot = activated[marketId | slotIndex];
            _slot &= ~(1 << (tick % 256));
            activated[marketId | slotIndex] = _slot;
            if (price == _lowestAsk) {
                _slot = _slot >> tick % 256;
                while (_slot == 0) {
                    ++slotIndex;
                    _slot = activated[marketId | slotIndex];
                    tick = slotIndex << 8;
                }
                tick = _searchSlotUp(_slot, tick);
                _getMarket[market].lowestAsk = uint80(tick * tickSize);
            }
            else if (price == _highestBid) {
                _slot = _slot & ((1 << (tick % 256)) - 1);
                while (_slot == 0) {
                    --slotIndex;
                    _slot = activated[marketId | slotIndex];
                }
                tick = _searchSlotDown(_slot, slotIndex << 8);
                _getMarket[market].highestBid = uint80(tick * tickSize);
            }
        }
    }
    // max is in buckets
    function _getPriceLevels(bool isAscending, uint256 startPrice, uint256 distance, uint256 interval, uint256 max) internal view {
        unchecked {
            uint256 _maxPrice = maxPrice;
            if (startPrice >= _maxPrice) {
                return;
            }
            uint256 _marketId = marketId;
            uint256 tick = startPrice / tickSize;
            startPrice = tick; // turn startprice into starttick
            if (!isAscending) {
                ++tick;
            }
            uint256 count;
            uint256 price;
            uint256 position;
            uint256 bucket = type(uint256).max;
            uint256 slotIndex = tick >> 8;
            uint256 slot = activated[marketId | slotIndex];
            assembly {
                position := mload(0x40)
                mstore(position, 0x0)
            }
            if (isAscending) {
                if (startPrice + (distance) > (_maxPrice / tickSize)) {
                    distance = ((_maxPrice / tickSize) - startPrice);
                }
                while (true) {
                    uint256 _slot = slot >> tick % 256;
                    while (_slot == 0) {
                        ++slotIndex;
                        slot = activated[marketId | slotIndex];
                        _slot = slot;
                        tick = slotIndex << 8;
                    }
                    tick = _searchSlotUp(_slot, tick);
                    slot &= ~(1 << (tick % 256));
                    price = tick * tickSize;
                    if ((price / interval * interval) == bucket) {
                        assembly {
                            mstore(0x00, or(_marketId, price))
                            mstore(0x20, priceLevels.slot)
                            let length := mload(position)
                            let existing := mload(add(length, position))
                            mstore(add(length, position), add(existing, and(sload(keccak256(0x00, 0x40)), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF)))
                        }
                    }
                    else {
                        ++count;
                        if (count > max && max != 0 || (tick >= startPrice + distance)) {
                            break;
                        }
                        bucket = price / interval * interval;
                        assembly {
                            mstore(0x00, or(_marketId, price))
                            mstore(0x20, priceLevels.slot)
                            let length := mload(position)
                            mstore(add(length, add(position, 0x20)), or(shl(128, bucket), and(sload(keccak256(0x00, 0x40)), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF)))
                            mstore(position, add(length, 0x20))
                        }
                    }
                }
            }
            else {
                if (distance > startPrice) {
                    distance = startPrice;
                }
                while (true) {
                    uint256 _slot = slot & ((1 << (tick % 256)) - 1);
                    while (_slot == 0) {
                        --slotIndex;
                        slot = activated[marketId | slotIndex];
                        _slot = slot;
                    }
                    tick = _searchSlotDown(_slot, slotIndex << 8);
                    slot &= ~(1 << (tick % 256));
                    price = tick * tickSize;
                    if ((((price + interval - 1) / interval) * interval) == bucket) {
                        assembly {
                            mstore(0x00, or(_marketId, price))
                            mstore(0x20, priceLevels.slot)
                            let length := mload(position)
                            let existing := mload(add(length, position))
                            mstore(add(length, position), add(existing, and(sload(keccak256(0x00, 0x40)), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF)))
                        }
                    }
                    else {
                        ++count;
                        if (count > max && max != 0 || (tick <= startPrice - distance)) {
                            break;
                        }
                        bucket = ((price + interval - 1) / interval) * interval;
                        assembly {
                            mstore(0x00, or(_marketId, price))
                            mstore(0x20, priceLevels.slot)
                            let length := mload(position)
                            mstore(add(length, add(position, 0x20)), or(shl(128, bucket), and(sload(keccak256(0x00, 0x40)), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF)))
                            mstore(position, add(length, 0x20))
                        }
                    }
                }     
            }
        }
    }

    function getPriceLevels(bool isAscending, uint256 startPrice, uint256 distance, uint256 interval, uint256 max) external payable returns (bytes memory) {
        assembly {
            mstore(0x40, 0xa0)
        }
        _getPriceLevels(isAscending, startPrice, distance, interval, max);
        assembly {
            mstore(0x80, 0x20)
            return(0x80, add(mload(0xa0), 0x40))
        }
    }

    function getPriceLevelsFromMid(uint256 distance, uint256 interval, uint256 max) external payable returns (uint256 highestBid, uint256 lowestAsk, bytes memory, bytes memory) {
        Market storage m = _getMarket[market];
        uint256 length;
        (highestBid, lowestAsk) = (m.highestBid, m.lowestAsk);
        assembly {
            mstore(0x40, 0x100)
        }
        _getPriceLevels(false, highestBid, distance, interval, max);
        assembly {
            length := mload(0x100)
            mstore(0x40, add(length, 0x120))
        }
        _getPriceLevels(true, lowestAsk, distance, interval, max);
        assembly {
            mstore(0x80, highestBid)
            mstore(0xa0, lowestAsk)
            mstore(0xc0, 0x80)
            mstore(0xe0, add(0xa0, length))
            return(0x80, add(0xc0, add(length, mload(add(length, 0x120)))))
        }
    }
    // done
    function getPrice() external payable returns (uint256 price, uint256 highestBid, uint256 lowestAsk) {
        Market storage m = _getMarket[market];
        uint256 count;
        (highestBid, lowestAsk) = (m.highestBid, m.lowestAsk);
        price = highestBid;
        if (lowestAsk != maxPrice) {
            price += lowestAsk;
            ++count;
        }
        if (highestBid != 0) {
            ++count;
        }
        if (count == 2) {
            price = (price + 1) >> 1;
        }
    }
    // done
    function getQuote(bool isBuy, bool isExactInput, bool isCompleteFill, uint256 size, uint256 worstPrice) external payable returns (uint256 amountIn, uint256 amountOut) {
        unchecked {
            Market storage m = _getMarket[market];
            uint256 price;
            if (isBuy) {
                if (isExactInput) { // orderInfo is 256-252 ordertype 252-248 !isExactInput 248-244 !isBuy 244-240 STP 240-236 !useexternalbalance 236-232 !fromcaller
                    size = (size * m.takerFee) / 100000;
                }
                uint256 _maxPrice = maxPrice;
                if (worstPrice >= _maxPrice) {
                    worstPrice = _maxPrice - 1;
                }
                price = m.lowestAsk;
            }
            else {
                if (!isExactInput) {
                    size = (size * 100000 + m.takerFee - 1) / m.takerFee;
                }
                if (worstPrice == 0) {
                    worstPrice = 1;
                }
                price = m.highestBid;
            }
            uint256 tick = price / tickSize;
            uint256 slot = activated[marketId | (tick >> 8)];
            while (isExactInput ? size > amountIn : size > amountOut) {
                if (isBuy ? price > worstPrice : price < worstPrice) {
                    if (isCompleteFill) {
                        revert SlippageExceeded();
                    }
                    else {
                        break;
                    }
                }
                uint256 sizeLeft = isExactInput ? (size - amountIn) : (size - amountOut);
                uint256 liquidity = priceLevels[marketId | price] & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
                if (isExactInput ? (isBuy ? (liquidity > (sizeLeft * m.makerRebate / 100000) * scaleFactor / price) : (liquidity > (sizeLeft * m.makerRebate / 100000) * price / scaleFactor)) : (liquidity > sizeLeft)) {
                    amountOut += (isExactInput ? (isBuy ? (sizeLeft * m.makerRebate / 100000) * scaleFactor / price : (sizeLeft * m.makerRebate / 100000) * price / scaleFactor) : sizeLeft);
                    if (!isExactInput) {
                        sizeLeft = isBuy ? (sizeLeft * price + scaleFactor - 1) / scaleFactor * 100000 / m.makerRebate : (sizeLeft * scaleFactor + price - 1) / price * 100000 / m.makerRebate;
                    }
                    amountIn += sizeLeft;
                    sizeLeft = 0;
                }
                else {
                    uint256 _amountIn = (isBuy ? (((liquidity * price / scaleFactor) * 100000) / m.makerRebate) : (((liquidity * scaleFactor / price) * 100000) / m.makerRebate));
                    amountIn += _amountIn;
                    amountOut += isBuy ? liquidity : liquidity;
                    sizeLeft -= isExactInput ? _amountIn : liquidity;
                    liquidity = 0;
                }
                if (liquidity == 0) {
                    slot &= ~(1 << (tick % 256));
                    uint256 slotIndex = tick >> 8;
                    if (isBuy) {
                        uint256 _slot = slot >> tick % 256;
                        while (_slot == 0) {
                            ++slotIndex;
                            slot = activated[marketId | slotIndex];
                            _slot = slot;
                            tick = slotIndex << 8;
                        }
                        tick = _searchSlotUp(_slot, tick);
                    }
                    else {
                        uint256 _slot = slot & ((1 << (tick % 256)) - 1);
                        while (_slot == 0) {
                            --slotIndex;
                            slot = activated[marketId | slotIndex];
                            _slot = slot;
                        }
                        tick = _searchSlotDown(_slot, slotIndex << 8);
                    }
                    price = tick * tickSize;
                }
                else {
                    break;
                }
            }
            isBuy ? amountIn = (amountIn * 100000 + m.takerFee - 1) / m.takerFee : amountOut = amountOut * m.takerFee / 100000;
            return (amountIn, amountOut);
        }
    }
    // done
    function _marketOrder(uint256 size, uint256 priceAndReferrer, uint256 orderInfo) internal returns (uint256 amountIn, uint256 amountOut, uint256 id, uint256 settlementDelta) { // settlement delta is debit amt << 128 | credit amt, already processed
        unchecked {
            Market storage m = _getMarket[market];
            uint256 price;
            if ((orderInfo >> 244 & 0xF) == 0) {
                if (((orderInfo >> 248 & 0xF) == 0)) { // orderInfo is 256-252 ordertype 252-248 !isExactInput 248-244 !isBuy 244-240 STP 240-236 !useexternalbalance 236-232 !fromcaller
                    size = (size * m.takerFee) / 100000;
                }
                uint256 _maxPrice = maxPrice;
                if ((priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFF) >= _maxPrice) {
                    priceAndReferrer = (priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000000000000000) | (_maxPrice - 1);
                }
                price = m.lowestAsk;
            }
            else {
                if (((orderInfo >> 248 & 0xF) != 0)) { // orderInfo is 256-252 ordertype 252-248 !isExactInput 248-244 !isBuy 244-240 STP 240-236 !useexternalbalance 236-232 !fromcaller
                    size = (size * 100000 + m.takerFee - 1) / m.takerFee;
                }
                if ((priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFF) == 0) {
                    ++priceAndReferrer;
                }
                price = m.highestBid;
            }
            assembly {
                mstore(0x80, shl(128, price)) // top 128 is start price bottom 128 is end price
            }
            {
                uint256 tick = price / tickSize;
                uint256 slot = activated[marketId | (tick >> 8)];
                while (((orderInfo >> 248 & 0xF) == 0) ? size > amountIn : size > amountOut) {
                    if (((orderInfo >> 244 & 0xF) == 0) ? price > (priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFF) : price < (priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFF)) {
                        if ((orderInfo >> 252) == 1) {
                            revert SlippageExceeded();
                        }
                        if (activated[marketId | (tick >> 8)] != slot) {
                            activated[marketId | (tick >> 8)] = slot;
                        }
                        if ((orderInfo >> 252) == 2) {
                            ((orderInfo >> 244 & 0xF) == 0) ? m.lowestAsk = uint80(price) : m.highestBid = uint80(price);
                            slot = ((orderInfo >> 248 & 0xF) == 0) ? (size - amountIn) : (((orderInfo >> 244 & 0xF) == 0) ? ((size - amountOut) * (priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFF) / scaleFactor) : ((size - amountOut) * scaleFactor / (priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFF)));
                            tick = orderInfo;
                            (slot, id) = _limitOrder(((tick >> 244 & 0xF) == 0), (tick >> 236 & 0x1) == 0, (priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFF), slot, (tick >> 160 & 0x1FFFFFFFFFF), (tick >> 208 & 0x3FF));
                            settlementDelta += (slot << 128);
                            if (slot != 0) { // mtl event is written to memory, emitted in parent
                                assembly {
                                    let length := mload(0xc0)
                                    mstore(add(length, add(0xc0, 0x20)), or(add(0x2000000000000000000000000000000000000000000000000000000000000000,mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(iszero(and(shr(244,orderInfo),0xF))))),or(shl(168,and(0xFFFFFFFFFFFFFFFFFFFF,priceAndReferrer)),or(shl(112,id),slot))))
                                    mstore(0xc0, add(length, 0x20))
                                    mstore(0x40, add(length, add(0xc0, 0x40)))
                                }
                            }
                        }
                        break;
                    }
                    uint256 _priceLevel = priceLevels[marketId | price];
                    uint256 sizeLeft = ((orderInfo >> 248 & 0xF) == 0) ? size - amountIn : size - amountOut;
                    {
                        uint256 next = (_priceLevel >> 205) & 0x7FFFFFFFFFFFF;
                        uint256 _orderInfo = orderInfo;
                        while ((_priceLevel & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) != 0 && sizeLeft != 0 && !((_orderInfo >> 252) == 3 && gasleft() < 100000)) {
                            uint256 _order = orders[((next > 0x1FFFFFFFFFF) ? next : marketId | (price << 48) | next)];
                            if ((_orderInfo >> 240 & 0xF) != 0 && (_order >> 113 & 0x1FFFFFFFFFF) == (_orderInfo >> 160 & 0x1FFFFFFFFFF)) {
                                if (((_orderInfo >> 240) & 0x1) != 0) { // stp is 0 do nothing 1 cancel maker 2 cancel taker 3 cancel both
                                    if (next > 0x1FFFFFFFFFF) {
                                        orders[next] &= 0x00000000000000000000000003FFFFFFFFFE0000000000000000000000000000;
                                    }
                                    else {
                                        delete orders[marketId | (price << 48) | next];
                                    }
                                    _priceLevel -= (_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF); // can't overflow
                                    if ((_orderInfo >> 244 & 0xF) == 0) {
                                        settlementDelta += ((_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF));
                                    }
                                    else {
                                        settlementDelta += ((_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF));
                                    }
                                    if ((_order & 0x0000000000000000000000000000000000010000000000000000000000000000) != 0) {
                                        tokenBalances[_order >> 113 & 0x1FFFFFFFFFF][((_orderInfo >> 244 & 0xF) == 0) ? baseAsset : quoteAsset] -= ((((_orderInfo >> 244 & 0xF) == 0) ? (_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) : (_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF)) << 128); // unlock tokens if internal can't overflow
                                    }
                                    assembly {
                                        mstore(add(mload(0xc0), add(0xc0, 0x20)), or(mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(and(shr(244, _orderInfo), 0xF))),or(shl(168,price),or(shl(112,next),and(_order, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF)))))
                                        mstore(0xc0, add(mload(0xc0), 0x20))
                                        mstore(0x40, add(mload(0xc0), add(0xc0, 0x20))) // avoid initializing length bc stack too deep
                                    }
                                    next = (_order >> 205) & 0x7FFFFFFFFFFFF;
                                }
                                if (((_orderInfo >> 240) & 0xF) == 1) {
                                    continue;
                                }
                                else {
                                    sizeLeft = 0;
                                    break;
                                }
                            } // should switch over to do operations on resting size
                            if (((_orderInfo >> 248 & 0xF) == 0) ? (((_orderInfo >> 244 & 0xF) == 0) ? ((_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) > (sizeLeft * m.makerRebate / 100000) * scaleFactor / price) : ((_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) > (sizeLeft * m.makerRebate / 100000) * price / scaleFactor)) : ((_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) > sizeLeft)) {
                                uint256 _amountOut;
                                {
                                    _amountOut = (((_orderInfo >> 248 & 0xF) == 0) ? (((_orderInfo >> 244 & 0xF) == 0) ? (sizeLeft * m.makerRebate / 100000) * scaleFactor / price : (sizeLeft * m.makerRebate / 100000) * price / scaleFactor) : sizeLeft); // output amount for just this swap, round down
                                    amountOut += _amountOut;
                                    if (((_orderInfo >> 248 & 0xF) != 0)) {
                                        sizeLeft = ((_orderInfo >> 244 & 0xF) == 0) ? (sizeLeft * price + scaleFactor - 1) / scaleFactor * 100000 / m.makerRebate : (sizeLeft * scaleFactor + price - 1) / price * 100000 / m.makerRebate; // transfer to maker amount, round up
                                    }
                                    _priceLevel -= _amountOut; // can't overflow
                                    _order -= _amountOut; // can't overflow
                                    orders[((next > 0x1FFFFFFFFFF) ? next : marketId | (price << 48) | next)] = _order;
                                    if (_order & 0x0000000000000000000000000000000000010000000000000000000000000000 == 0) { // maker wants tokens
                                        address owner = userIdToAddress[_order >> 113 & 0x1FFFFFFFFFF];
                                        if ((_orderInfo >> 236 & 0x1) == 0 && (_orderInfo >> 232 & 0x1) == 0) { // taker gives tokens
                                            IERC20(((_orderInfo >> 244 & 0xF) == 0) ? quoteAsset : baseAsset).transferFrom(address(uint160(_orderInfo)), owner, sizeLeft);
                                        }
                                        else { // taker gives internal balance
                                            settlementDelta += sizeLeft << 128;
                                            IERC20(((_orderInfo >> 244 & 0xF) == 0) ? quoteAsset : baseAsset).transfer(owner, sizeLeft);
                                        }
                                    }
                                    else { // maker wants internal balance
                                        settlementDelta += sizeLeft << 128;
                                        tokenBalances[_order >> 113 & 0x1FFFFFFFFFF][((_orderInfo >> 244 & 0xF) == 0) ? quoteAsset : baseAsset] += sizeLeft;
                                        tokenBalances[_order >> 113 & 0x1FFFFFFFFFF][((_orderInfo >> 244 & 0xF) == 0) ? baseAsset : quoteAsset] -= (_amountOut << 128); // unlock maker internal                       
                                    }
                                }
                                amountIn += sizeLeft;
                                address _market = market;
                                assembly {
                                    let length := mload(0xc0)
                                    mstore(add(length, add(0xc0, 0x20)), or(mul(0x1000000000000000000000000000000000000000000000000000000000000000, iszero(and(shr(244, _orderInfo), 0xF))), or(shl(168, price), or(shl(112, next), and(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF, _order)))))
                                    mstore(add(length, add(0xc0, 0x40)), _amountOut)
                                    log2(add(length, add(0xc0, 0x20)), 0x40, _market, and(0x1FFFFFFFFFF, shr(113, _order))) // anon event (orderfilled)
                                    mstore(0x40, add(length, add(0xc0, 0x20)))
                                }
                                sizeLeft = 0;
                            }
                            else {
                                uint256 transferAmount = ((_orderInfo >> 244 & 0xF) == 0) ? ((((_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) * price / scaleFactor) * 100000) / m.makerRebate) : ((((_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) * scaleFactor / price) * 100000) / m.makerRebate);
                                amountIn += transferAmount; // round up maybe?
                                uint256 _amountOut = (_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
                                amountOut += _amountOut;
                                _priceLevel -= _amountOut;
                                sizeLeft -= ((_orderInfo >> 248 & 0xF) == 0) ? transferAmount : _amountOut;
                                if (_order & 0x0000000000000000000000000000000000010000000000000000000000000000 == 0) { // maker wants tokens
                                    address owner = userIdToAddress[_order >> 113 & 0x1FFFFFFFFFF];
                                    if ((_orderInfo >> 236 & 0x1) == 0 && (_orderInfo >> 232 & 0x1) == 0) { // taker gives tokens
                                        IERC20(((_orderInfo >> 244 & 0xF) == 0) ? quoteAsset : baseAsset).transferFrom(address(uint160(_orderInfo)), owner, transferAmount);
                                    }
                                    else { // taker gives internal balance
                                        settlementDelta += transferAmount << 128;
                                        IERC20(((_orderInfo >> 244 & 0xF) == 0) ? quoteAsset : baseAsset).transfer(owner, transferAmount);
                                    }
                                }
                                else { // maker wants internal balance
                                    settlementDelta += transferAmount << 128;
                                    tokenBalances[_order >> 113 & 0x1FFFFFFFFFF][((_orderInfo >> 244 & 0xF) == 0) ? quoteAsset : baseAsset] += transferAmount;
                                    tokenBalances[_order >> 113 & 0x1FFFFFFFFFF][((_orderInfo >> 244 & 0xF) == 0) ? baseAsset : quoteAsset] -= _amountOut << 128; // unlock maker internal                      
                                }
                                address _market = market;
                                assembly {
                                    let length := mload(0xc0)
                                    mstore(add(length, add(0xc0, 0x20)), or(mul(0x1000000000000000000000000000000000000000000000000000000000000000, iszero(and(shr(244, _orderInfo), 0xF))), or(shl(168, price), shl(112, next))))
                                    mstore(add(length, add(0xc0, 0x40)), and(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF, _order))
                                    log2(add(length, add(0xc0, 0x20)), 0x40, _market, and(0x1FFFFFFFFFF, shr(113, _order))) // anon event (orderfilled)
                                    mstore(0x40, add(length, add(0xc0, 0x20)))
                                }
                                if (next > 0x1FFFFFFFFFF) {
                                    orders[next] &= 0x00000000000000000000000003FFFFFFFFFE0000000000000000000000000000;
                                }
                                else {
                                    delete orders[marketId | (price << 48) | next];
                                }
                                next = (_order >> 205) & 0x7FFFFFFFFFFFF;
                            }
                        }
                        priceLevels[marketId | price] = (next << 205) | (_priceLevel & 0x0000000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF); // set fillnext to next
                    }
                    assembly {
                        let temp := mload(0x80)
                        temp := or(and(temp, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000000000000000000000000000), price) // set end price
                        mstore(0x80, temp)
                    }
                    if ((_priceLevel & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) == 0) {
                        slot &= ~(1 << (tick % 256));
                        uint256 slotIndex = tick >> 8;
                        if ((orderInfo >> 244 & 0xF) == 0) {
                            uint256 _slot = slot >> tick % 256;
                            if (_slot == 0 && activated[marketId | slotIndex] != slot) {
                                activated[marketId | slotIndex] = slot;
                            }
                            while (_slot == 0) {
                                ++slotIndex;
                                slot = activated[marketId | slotIndex];
                                _slot = slot;
                                tick = slotIndex << 8;
                            }
                            tick = _searchSlotUp(_slot, tick);
                        }
                        else {
                            uint256 _slot = slot & ((1 << (tick % 256)) - 1);
                            if (_slot == 0 && activated[marketId | slotIndex] != slot) {
                                activated[marketId | slotIndex] = slot;
                            }
                            while (_slot == 0) {
                                --slotIndex;
                                slot = activated[marketId | slotIndex];
                                _slot = slot;
                            }
                            tick = _searchSlotDown(_slot, slotIndex << 8);
                        }
                        price = tick * tickSize;
                    }
                    else {
                        if (activated[marketId | (tick >> 8)] != slot) {
                            activated[marketId | (tick >> 8)] = slot;
                        }
                    }
                    if (sizeLeft == 0 || ((orderInfo >> 252) == 3 && gasleft() < 100000)) {
                        break;
                    }
                }
            }
            if (amountOut != 0) {
                uint256 feeAmount;
                if ((orderInfo >> 244 & 0xF) == 0) {
                    feeAmount = (amountIn * 100000 + m.takerFee - 1) / m.takerFee - amountIn;
                    amountIn += feeAmount;
                    settlementDelta += (feeAmount << 128);
                    m.lowestAsk = uint80(price);
                }
                else {
                    feeAmount = amountOut - amountOut * m.takerFee / 100000;
                    amountOut -= feeAmount;
                    m.highestBid = uint80(price);
                }
                if (address(uint160(priceAndReferrer >> 80)) == address(0)) {
                    claimableRewards[quoteAsset][feeRecipient] += feeAmount;
                }
                else {
                    uint256 amountCommission = feeAmount * feeCommission / 100;
                    claimableRewards[quoteAsset][address(uint160(priceAndReferrer >> 80))] += amountCommission;
                    uint256 amountRebate = feeAmount * feeRebate / 100;
                    claimableRewards[quoteAsset][address(uint160(orderInfo))] += amountRebate;
                    claimableRewards[quoteAsset][feeRecipient] += (feeAmount - amountCommission - amountRebate);
                }
                assembly {
                    price := mload(0x80)
                }
                emit Trade(market, (orderInfo >> 160) & 0x1FFFFFFFFFF, address(uint160(orderInfo)), (orderInfo >> 244 & 0xF) == 0, amountIn, amountOut, price >> 128, price & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
                return (amountIn, amountOut, id, settlementDelta);
            }
            else {
                return (amountIn, 0, id, settlementDelta);
            }
        }
    }
    // done
    function _limitOrder(bool isBuy, bool isRecieveTokens, uint256 price, uint256 size, uint256 userId, uint256 cloid) internal returns (uint256, uint256 id) { // cloid being under uint10 is enforced in entry points
        unchecked {
            Market storage m = _getMarket[market];
            (uint256 _highestBid, uint256 _lowestAsk) = (m.highestBid, m.lowestAsk);
            if (isBuy) {
                if (price >= _lowestAsk || price == 0 || size < ((m.minSize >> 20) * 10 ** (m.minSize & 0xFFFFF)) || ((orders[(cloid << 41) | userId] & 0xFFFFFFFFFFFFFFFFFFFFFFFFFC0000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFF) != 0)) {
                    return (0, 0);
                }
                if (price > _highestBid) {
                    m.highestBid = uint80(price);
                }
                if (!isRecieveTokens) {
                    tokenBalances[userId][quoteAsset] += (size << 128); // lock tokens if internal
                }
            }
            else {
                if (price <= _highestBid || price >= maxPrice || (size * price / scaleFactor) < ((m.minSize >> 20) * 10 ** (m.minSize & 0xFFFFF)) || ((orders[(cloid << 41) | userId] & 0xFFFFFFFFFFFFFFFFFFFFFFFFFC0000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFF) != 0)) {
                    return (0, 0);
                }
                if (price < _lowestAsk) {
                    m.lowestAsk = uint80(price);
                }
                if (!isRecieveTokens) {
                    tokenBalances[userId][baseAsset] += (size << 128); // lock tokens if internal
                }
            }
            uint256 _priceLevel = priceLevels[marketId | price];
            require((size <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) && ((_priceLevel & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) + size) <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF); // overflow check, if invalid params are entered could revert instead of silent return
            if (cloid != 0) {
                _highestBid = ((cloid | 1) << 41) | userId;
                if (cloid & 1 == 1) {
                    cloidVerify[_highestBid] = cloidVerify[_highestBid] & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000000000000000000000000000 | ((marketId >> 48) | price);
                }
                else {
                    cloidVerify[_highestBid] = cloidVerify[_highestBid] & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF | ((marketId << 80) | (price << 128));
                }
                cloid = (cloid << 41) | userId; // cloid to pointer using userid
                if ((_priceLevel & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) == 0) {
                    require(price % tickSize == 0);
                    uint256 tick = price / tickSize;
                    activated[marketId | (tick >> 8)] |= (1 << (tick % 256));
                    _priceLevel =  (cloid << 205) | (_priceLevel & 0x0000000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF); // set fillNext to cloid
                }
                else {
                    uint256 fillBefore = (_priceLevel >> 154) & 0x7FFFFFFFFFFFF;
                    orders[(fillBefore > 0x1FFFFFFFFFF) ? fillBefore : (marketId | (price << 48) | fillBefore)] = (cloid << 205) | (orders[(fillBefore > 0x1FFFFFFFFFF) ? fillBefore : (marketId | (price << 48) | fillBefore)] & 0x0000000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF); // set fillbefores fillafter to cloid instead of prev native id
                }
                orders[cloid] = (((_priceLevel >> 113 & 0x1FFFFFFFFFF) + 1) << 205) | (_priceLevel & (0x7FFFFFFFFFFFF << 154)) | (userId << 113) | (isRecieveTokens ? 0 : (1 << 112)) | size; // fillAfter to priceLevels latestNativeId+1, fillBefore to latest
                priceLevels[marketId | price] = (cloid << 154) | ((_priceLevel & 0xFFFFFFFFFFFFE0000000000003FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) + size); // latest to cloid and add size
                return (size, cloid);
            }
            else {
                id = (_priceLevel >> 113 & 0x1FFFFFFFFFF) + 1;
                require(id <= 0x1FFFFFFFFFF); // overflow uint41
                if ((_priceLevel & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) == 0) {
                    require(price % tickSize == 0);
                    uint256 tick = price / tickSize;
                    activated[marketId | (tick >> 8)] |= (1 << (tick % 256));
                    _priceLevel = (id << 205) | (_priceLevel & 0x0000000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF); // set fillNext to id, sometimes redundant
                }
                orders[marketId | (price << 48) | id] = ((id + 1) << 205) | (_priceLevel & (0x7FFFFFFFFFFFF << 154)) | (userId << 113) | (isRecieveTokens ? 0 : (1 << 112)) | size; // fillAfter to id+1, fillBefore to latest
                priceLevels[marketId | price] = (id << 154) | (id << 113) | ((_priceLevel & 0xFFFFFFFFFFFFE00000000000000000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFF) + size); // latest and latestNativeId to id and add size
                return (size, id);
            }
        }       
    }
    // done
    function _cancelOrder(uint256 price, uint256 id, uint256 userId) internal returns (uint256, uint256 size, bool isBuy) { // id is cloid if price is missing
        unchecked {
            Market storage m = _getMarket[market];
            uint256 _order = orders[(price != 0 ? (marketId | (price << 48) | id) : ((id << 41) | userId))]; // id is not yet pointer
            size = (_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
            if (0 == size || userId != (_order >> 113 & 0x1FFFFFFFFFF)) {
                return (0, 0, isBuy);
            }
            if (price != 0) {
                delete orders[marketId | (price << 48) | id];
            }
            else {
                price = cloidVerify[((id | 1) << 41) | userId]; // avoid stack too deep, there's no reason to zero out/edit this as it's not needed
                if (id & 1 == 1) { // make sure order is in right market, get price because cloid doesn't come with it
                    if (((price >> 80) & 0xFFFFFFFFFFFF) != (marketId >> 128)) {
                        return (0, 0, isBuy);
                    }
                    price = price & 0xFFFFFFFFFFFFFFFFFFFF;
                }
                else {
                    if (((price >> 208) & 0xFFFFFFFFFFFF) != (marketId >> 128)) {
                        return (0, 0, isBuy);
                    }
                    price = (price >> 128) & 0xFFFFFFFFFFFFFFFFFFFF;
                }
                id = (id << 41) | userId; // id to pointer using userid
                orders[id] &= 0x00000000000000000000000003FFFFFFFFFE0000000000000000000000000000;
            }
            (uint256 _highestBid, uint256 _lowestAsk) = (m.highestBid, m.lowestAsk);
            if (price <= _highestBid) {
                isBuy = true;
                if ((_order & 0x0000000000000000000000000000000000010000000000000000000000000000) != 0) {
                    tokenBalances[userId][quoteAsset] -= (size << 128); // unlock tokens if internal can't overflow
                }
            }
            else {
                if ((_order & 0x0000000000000000000000000000000000010000000000000000000000000000) != 0) {
                    tokenBalances[userId][baseAsset] -= (size << 128); // unlock tokens if internal can't overflow
                }
            }
            _internalCancel(price, id, size, _highestBid, _lowestAsk, _order);
            return (price, size, isBuy);
        }
    }
    // done
    function _decreaseOrder(uint256 price, uint256 id, uint256 decreaseAmount, uint256 userId) internal returns (uint256, uint256 size, bool isBuy) { // id is cloid if price is missing
        unchecked {
            Market storage m = _getMarket[market];
            uint256 _order = orders[(price != 0 ? (marketId | (price << 48) | id) : ((id << 41) | userId))]; // id is not yet pointer
            size = (_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
            if (0 == size || userId != (_order >> 113 & 0x1FFFFFFFFFF)) {
                return (0, 0, isBuy);
            }
            if (price == 0) {
                price = cloidVerify[((id | 1) << 41) | userId]; // avoid stack too deep, there's no reason to zero out/edit this as it's not needed
                if (id & 1 == 1) { // make sure order is in right market, get price because cloid doesn't come with it
                    if (((price >> 80) & 0xFFFFFFFFFFFF) != (marketId >> 128)) {
                        return (0, 0, isBuy);
                    }
                    price = price & 0xFFFFFFFFFFFFFFFFFFFF;
                }
                else {
                    if (((price >> 208) & 0xFFFFFFFFFFFF) != (marketId >> 128)) {
                        return (0, 0, isBuy);
                    }
                    price = (price >> 128) & 0xFFFFFFFFFFFFFFFFFFFF;
                }
                id = (id << 41) | userId; // id to pointer using userid
            }
            (uint256 _highestBid, uint256 _lowestAsk) = (m.highestBid, m.lowestAsk);
            if (price <= _highestBid) {
                isBuy = true;
            }
            if ((isBuy ? size : (size * price / scaleFactor)) <= (isBuy ? decreaseAmount : (decreaseAmount * price / scaleFactor)) + (((m.minSize >> 20) * 10 ** (m.minSize & 0xFFFFF)))) { // cancel if resulting order would be too small
                if ((_order & 0x0000000000000000000000000000000000010000000000000000000000000000) != 0) {
                    isBuy ? tokenBalances[userId][quoteAsset] -= (size << 128) : tokenBalances[userId][baseAsset] -= (size << 128); // unlock tokens if internal can't overflow
                }
                if (price != 0) {
                    delete orders[marketId | (price << 48) | id];
                }
                else {
                    orders[id] &= 0x00000000000000000000000003FFFFFFFFFE0000000000000000000000000000;
                }
                _internalCancel(price, id, size, _highestBid, _lowestAsk, _order);
                return (price, size, isBuy);
            }
            else {
                if ((_order & 0x0000000000000000000000000000000000010000000000000000000000000000) != 0) {
                    isBuy ? tokenBalances[userId][quoteAsset] -= (decreaseAmount << 128) : tokenBalances[userId][baseAsset] -= (decreaseAmount << 128); // unlock tokens if internal can't overflow
                }
                orders[(price != 0 ? (marketId | (price << 48) | id) : id)] -= decreaseAmount; // can't overflow
                priceLevels[marketId | price] -= decreaseAmount;
                return (price, decreaseAmount << 128, isBuy); // price, decrease amount, isBuy
            }
        }
    }
    // done
    function _replaceOrder(uint256 options, uint256 price, uint256 id, uint256 newPrice, uint256 size) internal returns (int256 quoteAssetDebt, int256 baseAssetDebt, uint256) {
        unchecked {
            bool _isBuy;
            bool _isCloid;
            uint256 _size;
            if (price != 0) {
                _size = (orders[(marketId | (price << 48) | id)] & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF); // id is not pointer
            }
            else {
                _isCloid = true;
                price = cloidVerify[((id | 1) << 41) | (options & 0x1FFFFFFFFFF)]; // avoid stack too deep, there's no reason to zero out/edit this as it's not needed
                if (id & 1 == 1) { // make sure order is in right market, get price because cloid doesn't come with it
                    if (((price >> 80) & 0xFFFFFFFFFFFF) != (marketId >> 128)) {
                        return (0, 0, 0);
                    }
                    price = price & 0xFFFFFFFFFFFFFFFFFFFF;
                }
                else {
                    if (((price >> 208) & 0xFFFFFFFFFFFF) != (marketId >> 128)) {
                        return (0, 0, 0);
                    }
                    price = (price >> 128) & 0xFFFFFFFFFFFFFFFFFFFF;
                }
                _size = (orders[((id << 41) | (options & 0x1FFFFFFFFFF))] & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF); // id is not pointer
            }
            if (price <= _getMarket[market].highestBid) {
                _isBuy = true;
            }
            if (newPrice == 0) {
                newPrice = price;
            }
            if ((((options >> 48) & 0xF) != 0) || (newPrice == price && (_size > size))) {
                (price, _size, _isBuy) = _decreaseOrder(_isCloid ? 0 : price, id, _size - size, (options & 0x1FFFFFFFFFF)); // price is 0 if cloid
                if (_isCloid) {
                    id = (id << 41) | (options & 0x1FFFFFFFFFF); // differentiate emitted cloid
                }
                if (_size != 0) {
                    if ((_size >> 128) == 0) { // cancel
                        _isBuy ? quoteAssetDebt -= int256(_size & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) : baseAssetDebt -= int256(_size & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
                        assembly {
                            let length := mload(0xc0)
                            mstore(add(length, 0xe0), or(mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(_isBuy)),or(shl(168,price),or(shl(112,id),and(112, _size))))) // 3 bits flag 80 price 56 id 112 cancel size
                            mstore(0xc0, add(length, 0x20))
                            mstore(0x40, add(length, 0x100))
                        }
                    }
                    else {
                        _isBuy ? quoteAssetDebt -= int256(_size >> 128) : baseAssetDebt -= int256(_size >> 128);
                        assembly {
                            let length := mload(0xc0)
                            mstore(add(length, 0xe0), or(add(0x4000000000000000000000000000000000000000000000000000000000000000,mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(_isBuy))),or(shl(168,price),or(shl(112,id),shr(128, _size))))) // 3 bits flag 80 price 56 id 112 decrease size not remaining
                            mstore(0xc0, add(length, 0x20))
                            mstore(0x40, add(length, 0x100))
                        }
                    }
                    return (quoteAssetDebt, baseAssetDebt, id);
                }
                else {
                    return (0, 0, 0); // no state is changed, can silent return
                }
            }
            else {
                (price, _size, _isBuy) = _cancelOrder((_isCloid) ? 0 : price, id, (options & 0x1FFFFFFFFFF)); // price is 0 if cloid
                if (_isCloid) {
                    id = (id << 41) | (options & 0x1FFFFFFFFFF); // differentiate emitted cloid
                }
                if (_size != 0) {
                    _isBuy ? quoteAssetDebt -= int256(_size) : baseAssetDebt -= int256(_size);
                    assembly {
                        let length := mload(0xc0)
                        mstore(add(length, 0xe0), or(mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(_isBuy)),or(shl(168,price),or(shl(112,id),_size)))) // 3 bits flag 80 price 56 id 112 size
                        mstore(0xc0, add(length, 0x20))
                        mstore(0x40, add(length, 0x100))
                    }
                }
                else {
                    return (0, 0, 0); // no state is changed, can silent return
                }
                if (_isCloid) {
                    id = id >> 41; // back to normal cloid
                }
                if (size == 0) {
                    size = _size;
                }
                if (((options >> 44) & 0xF) == 0) { // post only
                    (_size, id) = _limitOrder(_isBuy, (((options >> 60) & 0xF) == 0), newPrice, size, (options & 0x1FFFFFFFFFF), id);
                    if (_size != 0) {
                        _isBuy ? quoteAssetDebt += int256(_size) : baseAssetDebt += int256(_size);
                        assembly {
                            let length := mload(0xc0)
                            mstore(add(length, 0xe0), or(add(0x2000000000000000000000000000000000000000000000000000000000000000,mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(_isBuy))),or(shl(168,newPrice),or(shl(112,id),_size)))) // 3 bits flag 80 price 56 id 112 size
                            mstore(0xc0, add(length, 0x20))
                            mstore(0x40, add(length, 0x100))
                        }
                    }
                    else {
                        return (quoteAssetDebt, baseAssetDebt, 0);
                    }
                }
                else {
                    _isCloid = ((options >> 60) & 0xF) == 0; // avoid stack too deep, true if external balances
                    uint256 settlementDelta;
                    uint256 referrer = (options >> 96);
                    uint256 orderInfo = (2 << 252) | (_isBuy ? 0 : (1 << 244)) | (1 << 240) | (_isCloid ? 0 : (1 << 236)) | (id << 208) | ((options & 0x1FFFFFFFFFF) << 160) | uint160(msg.sender);
                    (, _size, id, settlementDelta) = _marketOrder(size, (uint160(referrer) << 80) | newPrice, orderInfo);
                    if (_isBuy) {
                        quoteAssetDebt += int256(settlementDelta >> 128);
                        baseAssetDebt -= int256(_size + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                    }
                    else {
                        baseAssetDebt += int256(settlementDelta >> 128);
                        quoteAssetDebt -= int256(_size + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                    }
                }
                return (quoteAssetDebt, baseAssetDebt, id);
            }
        }
    }
    // make sure to keep pricetimepriority, relinking order on partial fill is fine because it's a single fill
    function _placeGridOrder(bool isBuy, uint256 price, uint256 mirroredPrice, uint256 size, uint256 userId) internal returns (uint256 _size, uint256 id) {
    }
    // done, these methods support margin which is managed before/after the call, just set internal balance mode to true
    function marketOrder(bool isBuy, bool isExactInput, uint256 options, uint256 orderType, uint256 size, uint256 worstPrice, address referrer, address caller) external payable returns (uint256 amountIn, uint256 amountOut, uint256 id) {
        unchecked {
            uint256 orderInfo; // options is 0-44 userId 44-54 cloid 56-60 stp 60-64 tointernalbalances 64-68 frominternalbalances 68-72 useinternalbalances
            uint256 userId;
            {
                uint256 orderFlags = ((orderType & 0xF) << 252) | ((isExactInput ? 0 : (1 << 248))) | ((isBuy ? 0 : (1 << 244))) | (((options >> 56) & 0xF) << 240); // ordertype exactinput=0 isbuy=0 stp
                orderInfo = orderFlags | (((options >> 68) & 0xF) << 236) | (((options >> 64) & 0xF) << 232) | uint160(caller); // useexternalbalance=0 fromcaller=0 add userId 160-208 if internal balance or mtl and cloid if provided 208-218 if mtl and margin enforced elsewhere
                userId = (options & 0x1FFFFFFFFFF);
                if (userId != 0) {
                    require(userIdToAddress[userId] == caller);
                }
                else {
                    userId = addressToUserId[caller];
                    if (userId == 0) {
                        userId = ICrystal(crystal).registerUser();
                    }
                }
                orderInfo |= (userId << 160); // add userId to orderInfo
                if (((options >> 44) & 0x3FF) != 0) { // if cloid
                    orderInfo |= (((options >> 44) & 0x3FF) << 208);
                }
            }
            uint256 settlementDelta;
            assembly {
                mstore(0x40, 0xe0) // 0x80 is used by _marketOrder internally to avoid stack too deep
            }
            (amountIn, amountOut, id, settlementDelta) = _marketOrder(size, (uint160(referrer) << 80) | worstPrice, orderInfo);
            address _market = market;
            assembly {
                let length := mload(0xc0)
                if gt(length, 0) {
                    mstore(0xa0, 0x20)
                    log3(0xa0, add(length, 0x40), 0xcd726e874e479599fa8abfd7a4ad443b08415d78fb36a088cd0e9c88b249ba66, _market, userId)
                }
            }
            address token = isBuy ? quoteAsset : baseAsset;
            if ((settlementDelta >> 128) != 0) { // input token for both limit order and maker internal balance fills
                if (((options >> 68) & 0xF) != 0) {
                    uint256 balance = tokenBalances[userId][token];
                    if (uint128(balance) < (settlementDelta >> 128)) {
                        revert ActionFailed();
                    }
                    else {
                        tokenBalances[userId][token] = balance - (settlementDelta >> 128);
                    }
                }
                else { // use external balance
                    if (((options >> 64) & 0xF) != 0) { // use router balance
                        uint256 balance = tokenBalances[0][token];
                        if (uint128(balance) < (settlementDelta >> 128)) {
                            revert ActionFailed();
                        }
                        else {
                            tokenBalances[0][token] = balance - (settlementDelta >> 128);
                        }
                    }
                    else {
                        IERC20(token).transferFrom(caller, address(this), (settlementDelta >> 128));
                    }
                }
            }
            settlementDelta &= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
            settlementDelta += amountOut; // add output to self cancel credit
            token = isBuy ? baseAsset : quoteAsset;
            if (settlementDelta != 0) { // output token, stp cancels + amountout
                if (((options >> 68) & 0xF) != 0) {
                    tokenBalances[userId][token] += settlementDelta;
                }
                else { // use external balance
                    if (((options >> 60) & 0xF) != 0) {
                        tokenBalances[0][token] += settlementDelta;
                    }
                    else {
                        IERC20(token).transfer(caller, settlementDelta);
                    }
                }
            }
        }
    }
    // done
    function limitOrder(bool isBuy, uint256 options, uint256 price, uint256 size, address caller) external payable returns (uint256 id) { // options is 0-41 userId 44-54 cloid 56-60 frominternalbalances 60-64 useinternalbalances
        unchecked {
            uint256 userId = (options & 0x1FFFFFFFFFF);
            if (userId != 0) { // if userId is supplied verify
                require(userIdToAddress[userId] == caller);
            }
            else { // get default userId
                userId = addressToUserId[caller];
                if (userId == 0) {
                    userId = ICrystal(crystal).registerUser();
                }
            }
            bool useExternalBalances = (((options >> 60) & 0xF) == 0);
            (size, id) = _limitOrder(isBuy, useExternalBalances, price, size, userId, (options >> 44) & 0x3FF);
            if (size != 0) { // if order success
                address token = isBuy ? quoteAsset : baseAsset;
                if (useExternalBalances) {
                    if (((options >> 56) & 0xF) != 0) {
                        uint256 balance = tokenBalances[0][token];
                        if (uint128(balance) < size) {
                            revert ActionFailed();
                        }
                        else {
                            tokenBalances[0][token] = balance - size;
                        }
                    }
                    else {
                        IERC20(token).transferFrom(caller, address(this), size);
                    }
                }
                else {
                    uint256 balance = tokenBalances[userId][token];
                    if (uint128(balance) < size) {
                        revert ActionFailed();
                    }
                    else {
                        tokenBalances[userId][token] = balance - size; // token txfer don't care about locking since done in internal function
                    }
                }
                emit OrdersUpdated(market, userId, abi.encodePacked((isBuy ? 0x2000000000000000000000000000000000000000000000000000000000000000 : 0x3000000000000000000000000000000000000000000000000000000000000000) | (price << 168) | (id << 112) | size)); // if id is a cloid it is already merged w user id
            }
            else {
                revert ActionFailed();
            }
        }
    } 
    // done
    function cancelOrder(uint256 options, uint256 price, uint256 id, address caller) external payable returns (uint256 size) { // options is 0-41 userId 44-48 tointernalbalances 48-52 useinternalbalances
        unchecked {
            bool isBuy;
            uint256 userId = (options & 0x1FFFFFFFFFF);
            if (userId != 0) { // if userId is supplied verify
                require(userIdToAddress[userId] == caller);
            }
            else { // get default userId
                userId = addressToUserId[caller];
            }
            bool useExternalBalances = (((options >> 48) & 0xF) == 0);
            bool isCloid = (price == 0); // if price isn't 0 assume it's a normal order
            (price, size, isBuy) = _cancelOrder(price, id, userId); // if no price attached update price
            if (isCloid) {
                id = (id << 41) | userId;
            }
            if (size != 0) { // if cancel success
                address token = isBuy ? quoteAsset : baseAsset;
                if (useExternalBalances) {
                    if (((options >> 44) & 0xF) != 0) {
                        tokenBalances[0][token] += size;
                    }
                    else {
                        IERC20(token).transfer(caller, size);
                    }
                }
                else {
                    tokenBalances[userId][token] += size;
                }
                emit OrdersUpdated(market, userId, abi.encodePacked((isBuy ? 0 : 0x1000000000000000000000000000000000000000000000000000000000000000) | (price << 168) | (id << 112) | size));
            }
        }
    }
    // replace is useful in that if cancel fails there's no order, will decrease if its best course of action, and also that you can take the proceeds of the cancel as the order size by setting size=0, can also do decrease
    function replaceOrder(uint256 options, uint256 price, uint256 id, uint256 newPrice, uint256 size, address referrer, address caller) external payable returns (uint256 _id) { // options is 0-41 userId 44-48 postOnly=0 48-52 isDecrease 52-56 tointernalbalances 56-60 frominternalbalances 60-64 useinternalbalances
        int256 quoteAssetDebt;
        int256 baseAssetDebt;
        uint256 userId = (options & 0x1FFFFFFFFFF);
        if (userId != 0) { // if userId is supplied verify
            require(userIdToAddress[userId] == caller);
        }
        else { // get default userId
            userId = addressToUserId[caller];
            options = (options & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE0000000000) | userId; // add userId to options
            if (userId == 0) {
                userId = ICrystal(crystal).registerUser();
            }
        }
        options = (uint160(referrer) << 96) | options;
        assembly {
            mstore(0x40, 0xe0) // 0x80 is used by _marketOrder internally to avoid stack too deep
        }
        (quoteAssetDebt, baseAssetDebt, _id) = _replaceOrder(options, price, id, newPrice, size);
        uint256 balanceMode = options; // avoid std
        _settleBalances(caller, quoteAssetDebt, baseAssetDebt, userId, ((balanceMode >> 60) & 0xF), ((balanceMode >> 52) & 0xF), ((balanceMode >> 56) & 0xF));
        address _market = market;
        assembly {
            let length := mload(0xc0)
            switch gt(length, 0)
            case true {
                mstore(0xa0, 0x20)
                log3(0xa0, add(length, 0x40), 0xcd726e874e479599fa8abfd7a4ad443b08415d78fb36a088cd0e9c88b249ba66, _market, userId)
            }
            default {
                revert(0, 0)
            }
        }
    }
    // done except replace if needed, maybe add bribe endpoint in parent, do margin in balance mode param
    function batchOrders(Action[] calldata actions, uint256 options, address referrer, address caller) external payable { // options is 0-41 userId 44-48 tointernalbalances 48-52 frominternalbalances 52-56 useinternalbalances
        unchecked {
            uint256 userId;
            uint256 offset;
            uint256 action;
            uint256 param1;
            uint256 param2;
            uint256 cloid;
            bool isBuy;
            uint256 balanceMode;
            int256 quoteAssetDebt;
            int256 baseAssetDebt;
            if ((options & 0x1FFFFFFFFFF) != 0) { // if userId is supplied verify
                userId = (options & 0x1FFFFFFFFFF);
                require(userIdToAddress[userId] == caller);
            }
            else { // get default userId
                userId = addressToUserId[caller];
                if (userId == 0) {
                    userId = ICrystal(crystal).registerUser();
                }
            }
            balanceMode = ((options >> 52) & 0xF);
            assembly {
                mstore(0x40, 0xe0)
            }
            while (offset < actions.length) {
                action = actions[offset].action & 0xF;
                param1 = actions[offset].param1 & 0xFFFFFFFFFFFFFFFFFFFF;
                param2 = actions[offset].param2 & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
                cloid = actions[offset].param3 & 0x3FF;
                if (action == 1) { // cancel, pass either price and id or cloid
                    if (cloid != 0) {
                        (param1, action, isBuy) = _cancelOrder(0, cloid, userId);
                        param2 = (cloid << 41) | userId; // differentiate emitted cloid
                    }
                    else {
                        (param1, action, isBuy) = _cancelOrder(param1, param2, userId);
                    }
                    if (action != 0) {
                        isBuy ? quoteAssetDebt -= int256(action) : baseAssetDebt -= int256(action);
                        assembly {
                            let length := mload(0xc0)
                            mstore(add(length, 0xe0), or(mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(isBuy)),or(shl(168,param1),or(shl(112,param2),action)))) // 8 flag 80 price 56 id 112 size
                            mstore(0xc0, add(length, 0x20))
                            mstore(0x40, add(length, 0x100))
                        }
                    }
                    else {
                        if (actions[offset].isRequireSuccess) {
                            revert ActionFailed();
                        }
                    }
                }
                else if (action == 2) { // limit buy, pass price size and optional cloid
                    (action, param2) = _limitOrder(true, balanceMode == 0, param1, param2, userId, cloid);
                    if (action != 0) {
                        quoteAssetDebt += int256(action);
                        assembly {
                            let length := mload(0xc0)
                            mstore(add(length, 0xe0), or(0x2000000000000000000000000000000000000000000000000000000000000000,or(shl(168,param1),or(shl(112,param2),action)))) // 8 flag 80 price 56 id 112 size
                            mstore(0xc0, add(length, 0x20))
                            mstore(0x40, add(length, 0x100))
                        }
                    }
                    else {
                        if (actions[offset].isRequireSuccess) {
                            revert ActionFailed();
                        }
                    }
                }
                else if (action == 3) { // limit sell
                    (action, param2) = _limitOrder(false, balanceMode == 0, param1, param2, userId, cloid);
                    if (action != 0) {
                        baseAssetDebt += int256(action);
                        assembly {
                            let length := mload(0xc0)
                            mstore(add(length, 0xe0), or(0x3000000000000000000000000000000000000000000000000000000000000000, or(shl(168,param1),or(shl(112,param2),action)))) // 8 flag 80 price 56 id 112 size
                            mstore(0xc0, add(length, 0x20))
                            mstore(0x40, add(length, 0x100))
                        }
                    }
                    else {
                        if (actions[offset].isRequireSuccess) {
                            revert ActionFailed();
                        }
                    }
                }
                else if (action == 4) { // mtl buy
                    uint256 settlementDelta;
                    settlementDelta = (uint160(referrer) << 80) | param1; // avoid stack too deep
                    ( , action, , settlementDelta) = _marketOrder(param2, settlementDelta, (2 << 252) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    quoteAssetDebt += int256(settlementDelta >> 128);
                    baseAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 5) { // mtl sell
                    uint256 settlementDelta;
                    settlementDelta = (uint160(referrer) << 80) | param1;
                    ( , action, , settlementDelta) = _marketOrder(param2, settlementDelta, (2 << 252) | (1 << 244) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    baseAssetDebt += int256(settlementDelta >> 128);
                    quoteAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 6) { // partialfill buy
                    uint256 settlementDelta;
                    settlementDelta = (uint160(referrer) << 80) | param1;
                    ( , action, , settlementDelta) = _marketOrder(param2, settlementDelta, (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    quoteAssetDebt += int256(settlementDelta >> 128);
                    baseAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 7) { // partialfill sell
                    uint256 settlementDelta;
                    settlementDelta = (uint160(referrer) << 80) | param1;
                    ( , action, , settlementDelta) = _marketOrder(param2, settlementDelta, (1 << 244) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    baseAssetDebt += int256(settlementDelta >> 128);
                    quoteAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 8) { // partial buy terminate when low on remaining gas
                    uint256 settlementDelta;
                    settlementDelta = (uint160(referrer) << 80) | param1;
                    ( , action, , settlementDelta) = _marketOrder(param2, settlementDelta, (3 << 252) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    quoteAssetDebt += int256(settlementDelta >> 128);
                    baseAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 9) { // partial sell terminate when low on remaining gas
                    uint256 settlementDelta;
                    settlementDelta = (uint160(referrer) << 80) | param1;
                    ( , action, , settlementDelta) = _marketOrder(param2, settlementDelta, (3 << 252) | (1 << 244) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    baseAssetDebt += int256(settlementDelta >> 128);
                    quoteAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 10) { // complete fill buy
                    uint256 settlementDelta;
                    settlementDelta = (uint160(referrer) << 80) | param1;
                    ( , action, , settlementDelta) = _marketOrder(param2, settlementDelta, (1 << 252) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    quoteAssetDebt += int256(settlementDelta >> 128);
                    baseAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 11) { // complete fill sell
                    uint256 settlementDelta;
                    settlementDelta = (uint160(referrer) << 80) | param1;
                    ( , action, , settlementDelta) = _marketOrder(param2, settlementDelta, (1 << 252) | (1 << 244) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    baseAssetDebt += int256(settlementDelta >> 128);
                    quoteAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 12) { // decrease order, if price then use cloid else use id
                    bool isCloid;
                    if (param1 != 0) { // if price is provided, id is used not cloid
                        cloid = actions[offset].param3 & 0x1FFFFFFFFFF; // id is a uint41
                    }
                    else {
                        isCloid = true;
                    }
                    (param1, param2, isBuy) = _decreaseOrder(param1, cloid, param2, userId);
                    if (isCloid) {
                        cloid = (cloid << 41) | userId; // differentiate emitted cloid
                    }
                    if (param2 != 0) {
                        if ((param2 >> 128) == 0) { // cancel
                            isBuy ? quoteAssetDebt -= int256(param2 & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) : baseAssetDebt -= int256(param2 & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
                            assembly {
                                let length := mload(0xc0)
                                mstore(add(length, 0xe0), or(mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(isBuy)),or(shl(168,param1),or(shl(112,cloid),and(112,param2))))) // 8 flag 80 price 56 id 112 cancel size
                                mstore(0xc0, add(length, 0x20))
                                mstore(0x40, add(length, 0x100))
                            }
                        }
                        else {
                            isBuy ? quoteAssetDebt -= int256(param2 >> 128) : baseAssetDebt -= int256(param2 >> 128);
                            assembly {
                                let length := mload(0xc0)
                                mstore(add(length, 0xe0), or(add(0x4000000000000000000000000000000000000000000000000000000000000000,mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(isBuy))),or(shl(168,param1),or(shl(112,cloid),shr(128, param2))))) // 8 flag 80 price 56 id 112 decrease size not remaining size
                                mstore(0xc0, add(length, 0x20))
                                mstore(0x40, add(length, 0x100))
                            }
                        }
                    }
                    else {
                        if (actions[offset].isRequireSuccess) {
                            revert ActionFailed();
                        }
                    }
                }
                ++offset;
            }
            param1 = options; // avoid std
            param2 = options; // avoid std
            _settleBalances(caller, quoteAssetDebt, baseAssetDebt, userId, balanceMode, ((param1 >> 44) & 0xF), ((param2 >> 48) & 0xF));
            address _market = market;
            assembly {
                let length := mload(0xc0)
                if gt(length, 0) {
                    mstore(0xa0, 0x20)
                    log3(0xa0, add(length, 0x40), 0xcd726e874e479599fa8abfd7a4ad443b08415d78fb36a088cd0e9c88b249ba66, _market, userId)
                }
            }
        }
    }
    // done except replace if needed, add bribe endpoint in parent, userid is prevalidated, do margin in balance mode param
    fallback() external payable {
        unchecked {
            uint256 userId;
            uint256 offset;
            uint256 action;
            uint256 param1;
            uint256 param2;
            uint256 cloid;
            bool isBuy;
            uint256 balanceMode;
            int256 quoteAssetDebt;
            int256 baseAssetDebt;
            assembly {
                mstore(0x40, 0xe0)
                userId := calldataload(offset)
                balanceMode := shr(44, userId)
                userId := and(0x1FFFFFFFFFF, userId) // it's a uint41 but encoded like a uint44
            }
            offset += 32;
            while (offset < msg.data.length) {
                assembly { // 4-8 is isRequireSuccess
                    action := calldataload(offset)
                    param1 := and(0xFFFFFFFFFFFFFFFFFFFF, shr(112, action)) // 64-144
                    param2 := and(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF, action) // 144-256
                    cloid := and(0x3FF, shr(192, action)) // 20-64
                    action := shr(252, action) // 0-4
                }
                if (action == 1) { // cancel, pass either price and id or cloid
                    if (cloid != 0) {
                        (param1, action, isBuy) = _cancelOrder(0, cloid, userId);
                        param2 = (cloid << 41) | userId; // differentiate emitted cloid
                    }
                    else {
                        (param1, action, isBuy) = _cancelOrder(param1, param2, userId);
                    }
                    if (action != 0) {
                        isBuy ? quoteAssetDebt -= int256(action) : baseAssetDebt -= int256(action);
                        assembly {
                            let length := mload(0xc0)
                            mstore(add(length, 0xe0), or(mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(isBuy)),or(shl(168,param1),or(shl(112,param2),action)))) // 8 flag 80 price 56 id 112 size
                            mstore(0xc0, add(length, 0x20))
                            mstore(0x40, add(length, 0x100))
                        }
                    }
                    else {
                        assembly { // reuse isBuy as isRequireSuccess
                            isBuy := and(0x1, shr(248, calldataload(offset))) // 4-8
                        }
                        if (isBuy) {
                            revert ActionFailed();
                        }
                    }
                }
                else if (action == 2) { // limit buy, pass price size and optional cloid
                    (action, param2) = _limitOrder(true, balanceMode == 0, param1, param2, userId, cloid);
                    if (action != 0) {
                        quoteAssetDebt += int256(action);
                        assembly {
                            let length := mload(0xc0)
                            mstore(add(length, 0xe0), or(0x2000000000000000000000000000000000000000000000000000000000000000,or(shl(168,param1),or(shl(112,param2),action)))) // 8 flag 80 price 56 id 112 size
                            mstore(0xc0, add(length, 0x20))
                            mstore(0x40, add(length, 0x100))
                        }
                    }
                    else {
                        assembly { // reuse isBuy as isRequireSuccess
                            isBuy := and(0x1, shr(248, calldataload(offset))) // 4-8
                        }
                        if (isBuy) {
                            revert ActionFailed();
                        }
                    }
                }
                else if (action == 3) { // limit sell
                    (action, param2) = _limitOrder(false, balanceMode == 0, param1, param2, userId, cloid);
                    if (action != 0) {
                        baseAssetDebt += int256(action);
                        assembly {
                            let length := mload(0xc0)
                            mstore(add(length, 0xe0), or(0x3000000000000000000000000000000000000000000000000000000000000000, or(shl(168,param1),or(shl(112,param2),action)))) // 8 flag 80 price 56 id 112 size
                            mstore(0xc0, add(length, 0x20))
                            mstore(0x40, add(length, 0x100))
                        }
                    }
                    else {
                        assembly { // reuse isBuy as isRequireSuccess
                            isBuy := and(0x1, shr(248, calldataload(offset))) // 4-8
                        }
                        if (isBuy) {
                            revert ActionFailed();
                        }
                    }
                }
                else if (action == 4) { // mtl buy
                    uint256 settlementDelta;
                    ( , action, , settlementDelta) = _marketOrder(param2, (uint160(msg.sender) << 80) | param1, (2 << 252) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    quoteAssetDebt += int256(settlementDelta >> 128);
                    baseAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 5) { // mtl sell
                    uint256 settlementDelta;
                    ( , action, , settlementDelta) = _marketOrder(param2, (uint160(msg.sender) << 80) | param1, (2 << 252) | (1 << 244) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    baseAssetDebt += int256(settlementDelta >> 128);
                    quoteAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 6) { // partialfill buy
                    uint256 settlementDelta;
                    ( , action, , settlementDelta) = _marketOrder(param2, (uint160(msg.sender) << 80) | param1, (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    quoteAssetDebt += int256(settlementDelta >> 128);
                    baseAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 7) { // partialfill sell
                    uint256 settlementDelta;
                    ( , action, , settlementDelta) = _marketOrder(param2, (uint160(msg.sender) << 80) | param1, (1 << 244) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    baseAssetDebt += int256(settlementDelta >> 128);
                    quoteAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 8) { // partial buy terminate when low on remaining gas
                    uint256 settlementDelta;
                    ( , action, , settlementDelta) = _marketOrder(param2, (uint160(msg.sender) << 80) | param1, (3 << 252) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    quoteAssetDebt += int256(settlementDelta >> 128);
                    baseAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 9) { // partial sell terminate when low on remaining gas
                    uint256 settlementDelta;
                    ( , action, , settlementDelta) = _marketOrder(param2, (uint160(msg.sender) << 80) | param1, (3 << 252) | (1 << 244) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    baseAssetDebt += int256(settlementDelta >> 128);
                    quoteAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 10) { // complete fill buy
                    uint256 settlementDelta;
                    ( , action, , settlementDelta) = _marketOrder(param2, (uint160(msg.sender) << 80) | param1, (1 << 252) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    quoteAssetDebt += int256(settlementDelta >> 128);
                    baseAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 11) { // complete fill sell
                    uint256 settlementDelta;
                    ( , action, , settlementDelta) = _marketOrder(param2, (uint160(msg.sender) << 80) | param1, (1 << 252) | (1 << 244) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    baseAssetDebt += int256(settlementDelta >> 128);
                    quoteAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 12) { // decrease order, if price then use cloid else use id
                    bool isCloid;
                    if (param1 != 0) { // if price is provided, id is used not cloid
                        assembly {
                            cloid := and(0x1FFFFFFFFFF, shr(192, calldataload(offset))) // id is a uint41, 16-64
                        }
                    }
                    else {
                        isCloid = true;
                    }
                    (param1, param2, isBuy) = _decreaseOrder(param1, cloid, param2, userId);
                    if (isCloid) {
                        cloid = (cloid << 41) | userId; // differentiate emitted cloid
                    }
                    if (param2 != 0) {
                        if ((param2 >> 128) == 0) { // cancel
                            isBuy ? quoteAssetDebt -= int256(param2 & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) : baseAssetDebt -= int256(param2 & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
                            assembly {
                                let length := mload(0xc0)
                                mstore(add(length, 0xe0), or(mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(isBuy)),or(shl(168,param1),or(shl(112,cloid),and(112,param2))))) // 8 flag 80 price 56 id 112 cancel size
                                mstore(0xc0, add(length, 0x20))
                                mstore(0x40, add(length, 0x100))
                            }
                        }
                        else {
                            isBuy ? quoteAssetDebt -= int256(param2 >> 128) : baseAssetDebt -= int256(param2 >> 128);
                            assembly {
                                let length := mload(0xc0)
                                mstore(add(length, 0xe0), or(add(0x4000000000000000000000000000000000000000000000000000000000000000,mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(isBuy))),or(shl(168,param1),or(shl(112,cloid),shr(128, param2))))) // 8 flag 80 price 56 id 112 decrease size not remaining size
                                mstore(0xc0, add(length, 0x20))
                                mstore(0x40, add(length, 0x100))
                            }
                        }
                    }
                    else {
                        assembly { // reuse isBuy as isRequireSuccess
                            isBuy := and(0x1, shr(248, calldataload(offset))) // 4-8
                        }
                        if (isBuy) {
                            revert ActionFailed();
                        }
                    }
                }
                offset += 32;
            }
            _settleBalances(msg.sender, quoteAssetDebt, baseAssetDebt, userId, balanceMode, 0, 0);
            address _market = market;
            assembly {
                let length := mload(0xc0)
                if gt(length, 0) {
                    mstore(0xa0, 0x20)
                    log3(0xa0, add(length, 0x40), 0xcd726e874e479599fa8abfd7a4ad443b08415d78fb36a088cd0e9c88b249ba66, _market, userId)
                }
            }
        }
    }
}

contract CrystalMarket1 { // support for margin, doesn't have to be enabled, dynamic tick size with amm
    struct PriceLevel { 
        uint256 size; // uint112 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF
        // gap uint1 0x1
        uint256 latestNativeId; // uint41 0x1FFFFFFFFFF
        uint256 latest; // uint51 0x7FFFFFFFFFFFF
        uint256 fillNext; // uint51 0x7FFFFFFFFFFFF
    }

    struct InternalOrder { //  bit is if maker wants internal balance (1) or tokens (0) order is stored at either marketid << 128 | price << 48 | id or cloid << 41 | userid; no collision because marketid seperates cloid orders from non cloid, userid prevents cloid collisions, and price n id are always unique
        uint256 size; //uint112 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF
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

    struct Action {
        bool isRequireSuccess;
        uint256 action;
        uint256 param1; // price
        uint256 param2; // size/id
        uint256 param3; // cloid
    }

    address feeRecipient; // public is useless so everything isn't
    uint8 feeCommission;
    uint8 feeRebate;

    mapping (uint256 => address) userIdToAddress; // 0 is an invalid userid
    mapping (address => uint256) addressToUserId;
    mapping (address => Market) _getMarket;
    mapping (uint256 => uint256) activated; // marketid << 128 | slotindex
    mapping (uint256 => uint256) priceLevels; // 0 is an invalid price marketid << 128 | price
    mapping (uint256 => uint256) orders; // 0 is an invalid cloid, valid range 1-1023 mask 0x3FF; marketid << 128 | price << 48 | id or userid << 41 | cloid
    mapping (uint256 => uint256) cloidVerify; // two cloids per slot map market and price, never zero slot 1 << 255 | marketId << 208 | price << 128 | marketId << 80 | price
    mapping (uint256 => mapping (address => uint256)) tokenBalances;
    mapping (address => mapping (address => uint256)) claimableRewards;

    address public immutable quoteAsset;
    address public immutable baseAsset;
    address public immutable crystal;
    uint256 public immutable scaleFactor;
    uint256 public immutable tickSize;
    uint256 public immutable maxPrice;
    address private immutable market; // address of market even when delegate called
    uint256 private immutable marketId; // 0 is an invalid marketid, is already << 128

    event Trade(address indexed market, uint256 indexed userId, address indexed user, bool isBuy, uint256 amountIn, uint256 amountOut, uint256 startPrice, uint256 endPrice);
    event OrdersUpdated(address indexed market, uint256 indexed userId, bytes orderData);
    event OrderFilled(address indexed market, uint256 indexed userId, uint256 fillInfo, uint256 fillAmount) anonymous; // fillinfo is isSell << 252 | price << 168 | id << 112 | remaining size

    error SlippageExceeded();
    error ActionFailed();

    string public constant name = 'Crystal V2';
    string public constant symbol = 'CRY-V2';
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    bytes32 public DOMAIN_SEPARATOR;
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint256) public nonces;

    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Mint(address indexed market, address indexed sender, uint amountQuote, uint amountBase);
    event Burn(address indexed market, address indexed sender, uint amountQuote, uint amountBase, address indexed to);
    event Sync(address indexed market, uint112 reserve0, uint112 reserve1);

    constructor() {
        (quoteAsset, baseAsset, marketId, scaleFactor, tickSize, maxPrice) = ICrystal(msg.sender).parameters();
        marketId <<= 128;
        scaleFactor = 10 ** scaleFactor;
        market = address(this);
        crystal = msg.sender;
        require(quoteAsset != address(0) && baseAsset != address(0) && quoteAsset != baseAsset && maxPrice <= 0xFFFFFFFFFFFFFFFFFFFF && tickSize <= 0xFFFFFFFFFFFFFFFFFFFF && scaleFactor <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes(name)),
                keccak256(bytes('1')),
                chainId,
                address(this)
            )
        );
    }

    function _mint(address to, uint256 value) internal {
        totalSupply += value;
        balanceOf[to] += value;
        emit Transfer(address(0), to, value);
    }

    function _burn(address from, uint256 value) internal {
        balanceOf[from] -= value;
        totalSupply -= value;
        emit Transfer(from, address(0), value);
    }

    function _approve(address owner, address spender, uint256 value) internal {
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _transfer(address from, address to, uint256 value) internal {
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
    }

    function mint(address to, uint256 value) external {
        require(msg.sender == crystal);
        _mint(to, value);
    }

    function burn(address from, uint256 value) external {
        require(msg.sender == crystal);
        _burn(from, value);
    }

    function approve(address spender, uint256 value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max && to != crystal) {
            allowance[from][msg.sender] -= value;
        }
        _transfer(from, to, value);
        return true;
    }

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(deadline >= block.timestamp, 'UniswapV2: EXPIRED');
        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01',
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, 'UniswapV2: INVALID_SIGNATURE');
        _approve(owner, spender, value);
    }

    function getReserves() external payable returns (uint112 reserveQuote, uint112 reserveBase) {
        Market storage m = _getMarket[market];
        (reserveQuote, reserveBase) = (m.reserveQuote, m.reserveBase);
    }
    
    function addLiquidity(address to, uint256 amountQuoteDesired, uint256 amountBaseDesired, uint256 amountQuoteMin, uint256 amountBaseMin, uint256 options, address caller) external payable returns (uint256 liquidity) {
        Market storage m = _getMarket[market];
        (uint112 reserveQuote, uint112 reserveBase) = (m.reserveQuote, m.reserveBase);
        uint256 amountQuote;
        uint256 amountBase;
        uint256 _totalSupply = IERC20(market).totalSupply(); // gas savings, must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {
            amountQuote = amountQuoteDesired;
            amountBase = amountBaseDesired;
            liquidity = _sqrt(amountQuote * (amountBase)) - (1000);
            IERC20(market).mint(address(0), 1000); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            uint256 amountBaseOptimal = (amountQuoteDesired * reserveBase) / reserveQuote;
            if (amountBaseOptimal <= amountBaseDesired) {
                amountQuote = amountQuoteDesired;
                amountBase = amountBaseOptimal;
            } else {
                uint256 amountQuoteOptimal = (amountBaseDesired * reserveQuote) / reserveBase;
                require(amountQuoteOptimal <= amountQuoteDesired);
                amountQuote = amountQuoteOptimal;
                amountBase = amountBaseDesired;
            }
            liquidity = amountQuote * (_totalSupply) / reserveQuote < amountBase * (_totalSupply) / reserveBase ? amountQuote * (_totalSupply) / reserveQuote : amountBase * (_totalSupply) / reserveBase;
        }
        reserveQuote += uint112(amountQuote);
        reserveBase += uint112(amountBase);
        if ((options & 0xF) == 0) {
            IERC20(quoteAsset).transferFrom(caller, address(this), amountQuote);
        }
        else {
            tokenBalances[0][quoteAsset] -= amountQuote; // checked
        }
        if ((options >> 4 & 0xF) == 0) {
            IERC20(baseAsset).transferFrom(caller, address(this), amountBase);
        }
        else {
            tokenBalances[0][baseAsset] -= amountBase; // checked
        }
        IERC20(market).mint(to, liquidity);
        require(liquidity != 0 && amountQuote >= amountQuoteMin && amountBase >= amountBaseMin && reserveQuote <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF && reserveBase <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF && m.isAMMEnabled == true);

        (m.reserveQuote, m.reserveBase) = (reserveQuote, reserveBase);
        emit Sync(market, reserveQuote, reserveBase);
        emit Mint(market, caller, amountQuote, amountBase);
    }

    function removeLiquidity(address to, uint256 liquidity, uint256 amountQuoteMin, uint256 amountBaseMin, uint256 options, address caller) external payable returns (uint256 amountQuote, uint256 amountBase) {
        Market storage m = _getMarket[market];
        (uint112 reserveQuote, uint112 reserveBase) = (m.reserveQuote, m.reserveBase);
        IERC20(market).transferFrom(caller, address(this), liquidity);

        uint256 _totalSupply = IERC20(market).totalSupply(); // gas savings, must be defined here since totalSupply can update in _mintFee
        amountQuote = liquidity * (reserveQuote) / _totalSupply; // using balances ensures pro-rata distribution
        amountBase = liquidity * (reserveBase) / _totalSupply; // using balances ensures pro-rata distribution
        IERC20(market).burn(address(this), liquidity);
        if ((options & 0xF) == 0) {
            IERC20(quoteAsset).transfer(to, amountQuote);
        }
        else {
            tokenBalances[0][quoteAsset] += amountQuote;
        }
        if ((options >> 4 & 0xF) == 0) {
            IERC20(baseAsset).transfer(to, amountBase);
        }
        else {
            tokenBalances[0][baseAsset] += amountBase;
        }
        reserveQuote -= uint112(amountQuote); // checked
        reserveBase -= uint112(amountBase); // checked

        require(amountQuote != 0 && amountBase != 0 && amountQuote >= amountQuoteMin && amountBase >= amountBaseMin && reserveQuote <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF && reserveBase <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
        (m.reserveQuote, m.reserveBase) = (reserveQuote, reserveBase);
        emit Sync(market, reserveQuote, reserveBase);
        emit Burn(market, caller, amountQuote, amountBase, to);
    }

    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        unchecked {
            if (y > 3) {
                z = y;
                uint x = (y >> 1) + 1;
                while (x < z) {
                    z = x;
                    x = (y / x + x) >> 1;
                }
            } else if (y != 0) {
                z = 1;
            }
        }
    }

    function _tickToPrice(uint256 t) internal view returns (uint256) {
        unchecked {
            if (t <= 100_000) return t * tickSize;
            uint256 x = t - 10_000;
            return 10 ** (x / 90_000) * (10_000 + (x % 90_000)) * tickSize;
        }
    }

    function _priceToTick(uint256 p) internal view returns (uint256) {
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

    function _searchSlotUp(uint256 slot, uint256 tick) internal pure returns (uint256) {
        if (slot & ((1 << 128) - 1) == 0) {slot >>= 128; tick += 128;}
        if (slot & ((1 << 64) - 1) == 0) {slot >>= 64; tick += 64;}
        if (slot & ((1 << 32) - 1) == 0) {slot >>= 32; tick += 32;}
        if (slot & ((1 << 16) - 1) == 0) {slot >>= 16; tick += 16;}
        if (slot & ((1 << 8) - 1) == 0) {slot >>= 8; tick += 8;}
        if (slot & ((1 << 4) - 1) == 0) {slot >>= 4; tick += 4;}
        if (slot & ((1 << 2) - 1) == 0) {slot >>= 2; tick += 2;}
        if (slot & 1 == 0) {++tick;}
        return tick;
    }

    function _searchSlotDown(uint256 slot, uint256 tick) internal pure returns (uint256) {
        if (slot >= 2 ** 128) {slot >>= 128; tick += 128;}
        if (slot >= 2 ** 64) {slot >>= 64; tick += 64;}
        if (slot >= 2 ** 32) {slot >>= 32; tick += 32;}
        if (slot >= 2 ** 16) {slot >>= 16; tick += 16;}
        if (slot >= 2 ** 8) {slot >>= 8; tick += 8;}
        if (slot >= 2 ** 4) {slot >>= 4; tick += 4;}
        if (slot >= 2 ** 2) {slot >>= 2; tick += 2;}
        if (slot >= 2 ** 1) {++tick;}
        return tick;
    }

    function _settleBalances(address caller, int256 quoteAssetDebt, int256 baseAssetDebt, uint256 userId, uint256 balanceMode, uint256 balanceModeOut, uint256 balanceModeIn) internal {
        if (balanceMode == 0) { // external txfers
            if (balanceModeIn != 0) {
                if (quoteAssetDebt > 0) {
                    uint256 balance = tokenBalances[0][quoteAsset];
                    if (uint128(balance) < uint256(quoteAssetDebt)) {
                        revert ActionFailed();
                    }
                    else {
                        tokenBalances[0][quoteAsset] = balance - uint256(quoteAssetDebt);
                    }
                }
                if (baseAssetDebt > 0) {
                    uint256 balance = tokenBalances[0][baseAsset];
                    if (uint128(balance) < uint256(baseAssetDebt)) {
                        revert ActionFailed();
                    }
                    else {
                        tokenBalances[0][baseAsset] = balance - uint256(baseAssetDebt);
                    }
                }
            }
            else {
                if (quoteAssetDebt > 0) {
                    IERC20(quoteAsset).transferFrom(caller, address(this), uint256(quoteAssetDebt));
                }
                if (baseAssetDebt > 0) {
                    IERC20(baseAsset).transferFrom(caller, address(this), uint256(baseAssetDebt));
                }
            }
            if (balanceModeOut != 0) {
                if (quoteAssetDebt < 0) {
                    tokenBalances[0][quoteAsset] += uint256(-quoteAssetDebt);
                }
                if (baseAssetDebt < 0) {
                    tokenBalances[0][baseAsset] += uint256(-baseAssetDebt);
                }
            }
            else {
                if (quoteAssetDebt < 0) {
                    IERC20(quoteAsset).transfer(caller, uint256(-quoteAssetDebt));
                }
                if (baseAssetDebt < 0) {
                    IERC20(baseAsset).transfer(caller, uint256(-baseAssetDebt));
                }
            }
        }
        else {
            if (balanceMode == 1) { // internal balances
                if (quoteAssetDebt > 0) {
                    uint256 balance = tokenBalances[userId][quoteAsset];
                    if (uint128(balance) < uint256(quoteAssetDebt)) {
                        revert ActionFailed();
                    }
                    else {
                        tokenBalances[userId][quoteAsset] = balance - uint256(quoteAssetDebt);
                    }
                }
                else if (quoteAssetDebt < 0) {
                    tokenBalances[userId][quoteAsset] += uint256(-quoteAssetDebt);
                }
                if (baseAssetDebt > 0) {
                    uint256 balance = tokenBalances[userId][baseAsset];
                    if (uint128(balance) < uint256(baseAssetDebt)) {
                        revert ActionFailed();
                    }
                    else {
                        tokenBalances[userId][baseAsset] = balance - uint256(baseAssetDebt);
                    }
                }
                else if (baseAssetDebt < 0) {
                    tokenBalances[userId][baseAsset] += uint256(-baseAssetDebt);
                }
            }
            else {
                revert ActionFailed();
            }
        }
    }

    function _internalCancel(uint256 price, uint256 id, uint256 size, uint256 _highestBid, uint256 _lowestAsk, uint256 _order) internal {
        uint256 _priceLevel = priceLevels[marketId | price];
        _priceLevel -= size; // can't overflow
        if (id == (_priceLevel >> 205 & 0x7FFFFFFFFFFFF)) { // if pricelevel fillnext then set to fillafter
            _priceLevel = (_order & (0x7FFFFFFFFFFFF << 205)) | (_priceLevel & 0x0000000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
        }
        else if (id == (_priceLevel >> 154 & 0x7FFFFFFFFFFFF)) { // if pricelevel latest then set latest to fillbefore
            uint256 temp = ((((_order >> 154) & 0x7FFFFFFFFFFFF) > 0x1FFFFFFFFFF) ? ((_order >> 154) & 0x7FFFFFFFFFFFF) : marketId | (price << 48) | ((_order >> 154) & 0x7FFFFFFFFFFFF));
            orders[temp] = orders[temp] & 0x0000000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF | (_order & (0x7FFFFFFFFFFFF << 205)); // set fillbefores fillafter to fillafter
            _priceLevel = (_priceLevel & 0xFFFFFFFFFFFFE0000000000003FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) | (_order & (0x7FFFFFFFFFFFF << 154));
        }
        else {           
            uint256 temp = (((_order >> 154) & 0x7FFFFFFFFFFFF > 0x1FFFFFFFFFF) ? (_order >> 154) & 0x7FFFFFFFFFFFF : marketId | (price << 48) | (_order >> 154) & 0x7FFFFFFFFFFFF);
            orders[temp] = orders[temp] & 0x0000000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF | (_order & (0x7FFFFFFFFFFFF << 205)); // set fillbefores fillafter to fillafter
            temp = ((((_order >> 205) & 0x7FFFFFFFFFFFF) > 0x1FFFFFFFFFF) ? ((_order >> 205) & 0x7FFFFFFFFFFFF) : marketId | (price << 48) | ((_order >> 205) & 0x7FFFFFFFFFFFF));
            orders[temp] = orders[temp] & 0xFFFFFFFFFFFFE0000000000003FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF | (_order & (0x7FFFFFFFFFFFF << 154)); // setfillafters fillbefore to fillbefore
        }
        priceLevels[marketId | price] = _priceLevel;
        if ((_priceLevel & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) == 0) {
            uint256 tick = _priceToTick(price);
            uint256 slotIndex = tick >> 8;
            uint256 _slot = activated[marketId | slotIndex];
            _slot &= ~(1 << (tick % 256));
            activated[marketId | slotIndex] = _slot;
            if (price == _lowestAsk) {
                _slot = _slot >> tick % 256;
                while (_slot == 0) {
                    ++slotIndex;
                    _slot = activated[marketId | slotIndex];
                    tick = slotIndex << 8;
                }
                tick = _searchSlotUp(_slot, tick);
                _getMarket[market].lowestAsk = uint80(_tickToPrice(tick));
            }
            else if (price == _highestBid) {
                _slot = _slot & ((1 << (tick % 256)) - 1);
                while (_slot == 0) {
                    --slotIndex;
                    _slot = activated[marketId | slotIndex];
                }
                tick = _searchSlotDown(_slot, slotIndex << 8);
                _getMarket[market].highestBid = uint80(_tickToPrice(tick));
            }
        }
    }
    // max is in buckets
    function _getPriceLevels(bool isAscending, uint256 startPrice, uint256 distance, uint256 interval, uint256 max) internal view {
        unchecked {
            uint256 _maxPrice = maxPrice;
            if (startPrice >= _maxPrice) {
                return;
            }
            uint256 _marketId = marketId;
            uint256 tick = _priceToTick(startPrice);
            startPrice = tick; // turn startprice into starttick
            if (!isAscending) {
                ++tick;
            }
            uint256 count;
            uint256 price;
            uint256 position;
            uint256 bucket = type(uint256).max;
            uint256 slotIndex = tick >> 8;
            uint256 slot = activated[marketId | slotIndex];
            assembly {
                position := mload(0x40)
                mstore(position, 0x0)
            }
            if (isAscending) {
                if (startPrice + (distance) > _priceToTick(_maxPrice)) {
                    distance = (_priceToTick(_maxPrice) - startPrice);
                }
                while (true) {
                    uint256 _slot = slot >> tick % 256;
                    while (_slot == 0) {
                        ++slotIndex;
                        slot = activated[marketId | slotIndex];
                        _slot = slot;
                        tick = slotIndex << 8;
                    }
                    tick = _searchSlotUp(_slot, tick);
                    slot &= ~(1 << (tick % 256));
                    price = _tickToPrice(tick);
                    if ((price / interval * interval) == bucket) {
                        assembly {
                            mstore(0x00, or(_marketId, price))
                            mstore(0x20, priceLevels.slot)
                            let length := mload(position)
                            let existing := mload(add(length, position))
                            mstore(add(length, position), add(existing, and(sload(keccak256(0x00, 0x40)), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF)))
                        }
                    }
                    else {
                        ++count;
                        if (count > max && max != 0 || (tick >= startPrice + distance)) {
                            break;
                        }
                        bucket = price / interval * interval;
                        assembly {
                            mstore(0x00, or(_marketId, price))
                            mstore(0x20, priceLevels.slot)
                            let length := mload(position)
                            mstore(add(length, add(position, 0x20)), or(shl(128, bucket), and(sload(keccak256(0x00, 0x40)), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF)))
                            mstore(position, add(length, 0x20))
                        }
                    }
                }
            }
            else {
                if (distance > startPrice) {
                    distance = startPrice;
                }
                while (true) {
                    uint256 _slot = slot & ((1 << (tick % 256)) - 1);
                    while (_slot == 0) {
                        --slotIndex;
                        slot = activated[marketId | slotIndex];
                        _slot = slot;
                    }
                    tick = _searchSlotDown(_slot, slotIndex << 8);
                    slot &= ~(1 << (tick % 256));
                    price = _tickToPrice(tick);
                    if ((((price + interval - 1) / interval) * interval) == bucket) {
                        assembly {
                            mstore(0x00, or(_marketId, price))
                            mstore(0x20, priceLevels.slot)
                            let length := mload(position)
                            let existing := mload(add(length, position))
                            mstore(add(length, position), add(existing, and(sload(keccak256(0x00, 0x40)), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF)))
                        }
                    }
                    else {
                        ++count;
                        if (count > max && max != 0 || (tick <= startPrice - distance)) {
                            break;
                        }
                        bucket = ((price + interval - 1) / interval) * interval;
                        assembly {
                            mstore(0x00, or(_marketId, price))
                            mstore(0x20, priceLevels.slot)
                            let length := mload(position)
                            mstore(add(length, add(position, 0x20)), or(shl(128, bucket), and(sload(keccak256(0x00, 0x40)), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF)))
                            mstore(position, add(length, 0x20))
                        }
                    }
                }     
            }
        }
    }

    function getPriceLevels(bool isAscending, uint256 startPrice, uint256 distance, uint256 interval, uint256 max) external payable returns (bytes memory) {
        assembly {
            mstore(0x40, 0xa0)
        }
        _getPriceLevels(isAscending, startPrice, distance, interval, max);
        assembly {
            mstore(0x80, 0x20)
            return(0x80, add(mload(0xa0), 0x40))
        }
    }

    function getPriceLevelsFromMid(uint256 distance, uint256 interval, uint256 max) external payable returns (uint256 highestBid, uint256 lowestAsk, bytes memory, bytes memory) {
        Market storage m = _getMarket[market];
        uint256 length;
        (highestBid, lowestAsk) = (m.highestBid, m.lowestAsk);
        assembly {
            mstore(0x40, 0x100)
        }
        _getPriceLevels(false, highestBid, distance, interval, max);
        assembly {
            length := mload(0x100)
            mstore(0x40, add(length, 0x120))
        }
        _getPriceLevels(true, lowestAsk, distance, interval, max);
        assembly {
            mstore(0x80, highestBid)
            mstore(0xa0, lowestAsk)
            mstore(0xc0, 0x80)
            mstore(0xe0, add(0xa0, length))
            return(0x80, add(0xc0, add(length, mload(add(length, 0x120)))))
        }
    }
    // done
    function getPrice() external payable returns (uint256 price, uint256 highestBid, uint256 lowestAsk) {
        Market storage m = _getMarket[market];
        uint256 count;
        (highestBid, lowestAsk) = (m.highestBid, m.lowestAsk);
        price = highestBid;
        if (lowestAsk != maxPrice) {
            price += lowestAsk;
            ++count;
        }
        if (highestBid != 0) {
            ++count;
        }
        if (count == 2) {
            price = (price + 1) >> 1;
        }
    }
    // done
    function getQuote(bool isBuy, bool isExactInput, bool isCompleteFill, uint256 size, uint256 worstPrice) external payable returns (uint256 amountIn, uint256 amountOut) {
        unchecked {
            Market storage m = _getMarket[market];
            uint256 price;
            (uint256 reserveQuote, uint256 reserveBase) = m.isAMMEnabled ? (m.reserveQuote, m.reserveBase) : (0, 0);
            if (isBuy) {
                if (isExactInput) { // orderInfo is 256-252 ordertype 252-248 !isExactInput 248-244 !isBuy 244-240 STP 240-236 !useexternalbalance 236-232 !fromcaller
                    size = (size * m.takerFee) / 100000;
                }
                uint256 _maxPrice = maxPrice;
                if (worstPrice >= _maxPrice) {
                    worstPrice = _maxPrice - 1;
                }
                price = m.lowestAsk;
            }
            else {
                if (!isExactInput) {
                    size = (size * 100000 + m.takerFee - 1) / m.takerFee;
                }
                if (worstPrice == 0) {
                    worstPrice = 1;
                }
                price = m.highestBid;
            }
            uint256 tick = _priceToTick(price);
            uint256 slot = activated[marketId | (tick >> 8)];
            while (isExactInput ? size > amountIn : size > amountOut) {
                uint256 sizeLeft = isExactInput ? (size - amountIn) : (size - amountOut);
                if (reserveQuote != 0 && reserveBase != 0) {
                    if (isBuy && ((reserveQuote * scaleFactor * 10000) / (reserveBase * 9975)) < (price * 100000 / m.makerRebate)) {
                        if (isExactInput) {
                            uint256 temp1 = reserveQuote * 10000;
                            uint256 _amountIn = _sqrt(temp1 * reserveBase / scaleFactor * price / 9975) - (temp1 / 9975);
                            if (sizeLeft > _amountIn) {
                                uint256 temp2 = _amountIn * 9975;
                                uint256 _amountOut = (temp2 * reserveBase) / (temp1 + temp2);
                                reserveQuote += _amountIn;
                                reserveBase -= _amountOut;
                                amountIn += _amountIn;
                                amountOut += _amountOut;
                                sizeLeft -= _amountIn;
                            }
                            else {
                                uint256 temp2 = sizeLeft * 9975;
                                uint256 _amountOut = (temp2 * reserveBase) / (temp1 + temp2);
                                reserveQuote += sizeLeft;
                                reserveBase -= _amountOut;
                                amountIn += sizeLeft;
                                amountOut += _amountOut;
                                break;
                            }
                        }
                        else {
                            uint256 temp1 = reserveQuote * 10000;
                            uint256 _amountOut = reserveBase - _sqrt(temp1 * reserveQuote / price * scaleFactor / 9975);
                            if (sizeLeft > _amountOut) {
                                uint256 _amountIn = (_amountOut * temp1) / ((reserveBase - _amountOut) * 9975) + 1;
                                reserveQuote += _amountIn;
                                reserveBase -= _amountOut;
                                amountIn += _amountIn;
                                amountOut += _amountOut;
                                sizeLeft -= _amountOut;
                            }
                            else {
                                uint256 _amountIn = (sizeLeft * temp1) / ((reserveBase - sizeLeft) * 9975) + 1;
                                reserveQuote += _amountIn;
                                reserveBase -= sizeLeft;
                                amountIn += _amountIn;
                                amountOut += sizeLeft;
                                break;
                            }
                        }
                    }
                    else if (!isBuy && ((reserveQuote * scaleFactor * 10000) / (reserveBase * 9975)) > (price * m.makerRebate / 100000)) {
                        if (isExactInput) {
                            uint256 temp1 = reserveBase * 10000;
                            uint256 _amountIn = _sqrt(temp1 * reserveQuote / (price < worstPrice ? worstPrice : price) * scaleFactor / 9975) - (temp1 / 9975);
                            if (sizeLeft > _amountIn) {
                                uint256 temp2 = _amountIn * 9975;
                                uint256 _amountOut = (temp2 * reserveQuote) / (temp1 + temp2);
                                reserveBase += _amountIn;
                                reserveQuote -= _amountOut;
                                amountIn += _amountIn;
                                amountOut += _amountOut;
                                sizeLeft -= _amountIn;
                            }
                            else {
                                uint256 temp2 = sizeLeft * 9975;
                                uint256 _amountOut = (temp2 * reserveQuote) / (temp1 + temp2);
                                reserveBase += sizeLeft;
                                reserveQuote -= _amountOut;
                                amountIn += sizeLeft;
                                amountOut += _amountOut;
                                break;
                            }
                        }
                        else {
                            uint256 temp1 = reserveBase * 10000;
                            uint256 _amountOut = reserveQuote - _sqrt(temp1 * reserveQuote / scaleFactor * (price < worstPrice ? worstPrice : price) / 9975);
                            if (sizeLeft > _amountOut) {
                                uint256 _amountIn = (_amountOut * temp1) / ((reserveQuote - _amountOut) * 9975) + 1;
                                reserveBase += _amountIn;
                                reserveQuote -= _amountOut;
                                amountIn += _amountIn;
                                amountOut += _amountOut;
                                sizeLeft -= _amountOut;
                            }
                            else {
                                uint256 _amountIn = (sizeLeft * temp1) / ((reserveQuote - sizeLeft) * 9975) + 1;
                                reserveBase += _amountIn;
                                reserveQuote -= sizeLeft;
                                amountIn += _amountIn;
                                amountOut += sizeLeft;
                                break;
                            }
                        }
                    }
                }
                if (isBuy ? price > worstPrice : price < worstPrice) {
                    if (isCompleteFill) {
                        revert SlippageExceeded();
                    }
                    else {
                        break;
                    }
                }
                uint256 liquidity = priceLevels[marketId | price] & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
                if (isExactInput ? (isBuy ? (liquidity > (sizeLeft * m.makerRebate / 100000) * scaleFactor / price) : (liquidity > (sizeLeft * m.makerRebate / 100000) * price / scaleFactor)) : (liquidity > sizeLeft)) {
                    amountOut += (isExactInput ? (isBuy ? (sizeLeft * m.makerRebate / 100000) * scaleFactor / price : (sizeLeft * m.makerRebate / 100000) * price / scaleFactor) : sizeLeft);
                    if (!isExactInput) {
                        sizeLeft = isBuy ? (sizeLeft * price + scaleFactor - 1) / scaleFactor * 100000 / m.makerRebate : (sizeLeft * scaleFactor + price - 1) / price * 100000 / m.makerRebate;
                    }
                    amountIn += sizeLeft;
                    sizeLeft = 0;
                }
                else {
                    uint256 _amountIn = (isBuy ? (((liquidity * price / scaleFactor) * 100000) / m.makerRebate) : (((liquidity * scaleFactor / price) * 100000) / m.makerRebate));
                    amountIn += _amountIn;
                    amountOut += isBuy ? liquidity : liquidity;
                    sizeLeft -= isExactInput ? _amountIn : liquidity;
                    liquidity = 0;
                }
                if (liquidity == 0) {
                    slot &= ~(1 << (tick % 256));
                    uint256 slotIndex = tick >> 8;
                    if (isBuy) {
                        uint256 _slot = slot >> tick % 256;
                        while (_slot == 0) {
                            ++slotIndex;
                            slot = activated[marketId | slotIndex];
                            _slot = slot;
                            tick = slotIndex << 8;
                        }
                        tick = _searchSlotUp(_slot, tick);
                    }
                    else {
                        uint256 _slot = slot & ((1 << (tick % 256)) - 1);
                        while (_slot == 0) {
                            --slotIndex;
                            slot = activated[marketId | slotIndex];
                            _slot = slot;
                        }
                        tick = _searchSlotDown(_slot, slotIndex << 8);
                    }
                    price = _tickToPrice(tick);
                }
                else {
                    break;
                }
            }
            isBuy ? amountIn = (amountIn * 100000 + m.takerFee - 1) / m.takerFee : amountOut = amountOut * m.takerFee / 100000;
            return (amountIn, amountOut);
        }
    }
    // done
    function _marketOrder(uint256 size, uint256 priceAndReferrer, uint256 orderInfo) internal returns (uint256 amountIn, uint256 amountOut, uint256 id, uint256 settlementDelta) { // settlement delta is debit amt << 128 | credit amt, already processed
        unchecked {
            Market storage m = _getMarket[market];
            uint256 price;
            uint256 reserves =  m.isAMMEnabled ? ((uint256(m.reserveQuote) << 128) | m.reserveBase) : 0;
            if ((orderInfo >> 244 & 0xF) == 0) {
                if (((orderInfo >> 248 & 0xF) == 0)) { // orderInfo is 256-252 ordertype 252-248 !isExactInput 248-244 !isBuy 244-240 STP 240-236 !useexternalbalance 236-232 !fromcaller
                    size = (size * m.takerFee) / 100000;
                }
                uint256 _maxPrice = maxPrice;
                if ((priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFF) >= _maxPrice) {
                    priceAndReferrer = (priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000000000000000) | (_maxPrice - 1);
                }
                price = m.lowestAsk;
            }
            else {
                if (((orderInfo >> 248 & 0xF) != 0)) { // orderInfo is 256-252 ordertype 252-248 !isExactInput 248-244 !isBuy 244-240 STP 240-236 !useexternalbalance 236-232 !fromcaller
                    size = (size * 100000 + m.takerFee - 1) / m.takerFee;
                }
                if ((priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFF) == 0) {
                    ++priceAndReferrer;
                }
                price = m.highestBid;
            }
            assembly {
                mstore(0x80, shl(128, price)) // top 128 is start price bottom 128 is end price
            }
            {
                uint256 tick = _priceToTick(price);
                uint256 slot = activated[marketId | (tick >> 8)];
                while (((orderInfo >> 248 & 0xF) == 0) ? size > amountIn : size > amountOut) {
                    uint256 sizeLeft = ((orderInfo >> 248 & 0xF) == 0) ? size - amountIn : size - amountOut;
                    {
                        (uint256 reserveQuote, uint256 reserveBase) = (reserves >> 128, reserves & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
                        if (reserveQuote != 0 && reserveBase != 0) {
                            if (((orderInfo >> 244 & 0xF) == 0) && ((reserveQuote * scaleFactor * 10000) / (reserveBase * 9975)) < (price * 100000 / m.makerRebate)) {
                                if ((orderInfo >> 248 & 0xF) == 0) {
                                    uint256 _amountOut = reserveQuote * 10000; // reuse to avoid stack too deep
                                    uint256 worstPrice = (priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFF);
                                    uint256 _amountIn = _sqrt(_amountOut * reserveBase / scaleFactor * (price > worstPrice ? worstPrice : price) / 9975) - (_amountOut / 9975);
                                    if (sizeLeft > _amountIn) {
                                        _amountOut = ((_amountIn * 9975) * reserveBase) / (_amountOut + (_amountIn * 9975));
                                        settlementDelta += _amountIn << 128;
                                        reserveQuote += _amountIn;
                                        reserveBase -= _amountOut;
                                        amountIn += _amountIn;
                                        amountOut += _amountOut;
                                        sizeLeft -= _amountIn;
                                    }
                                    else {
                                        _amountOut = ((sizeLeft * 9975) * reserveBase) / (_amountOut + (sizeLeft * 9975));
                                        settlementDelta += sizeLeft << 128;
                                        reserveQuote += sizeLeft;
                                        reserveBase -= _amountOut;
                                        amountIn += sizeLeft;
                                        amountOut += _amountOut;
                                        reserves = (reserveQuote << 128) | reserveBase;
                                        if (activated[marketId | (tick >> 8)] != slot) {
                                            activated[marketId | (tick >> 8)] = slot;
                                        }
                                        break;
                                    }
                                }
                                else {
                                    uint256 _amountIn = reserveQuote * 10000; // reuse to avoid stack too deep
                                    uint256 worstPrice = (priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFF);
                                    uint256 _amountOut = reserveBase - _sqrt(_amountIn * reserveQuote / (price > worstPrice ? worstPrice : price) * scaleFactor / 9975);
                                    if (sizeLeft > _amountOut) {
                                        _amountIn = (_amountOut * _amountIn) / ((reserveBase - _amountOut) * 9975) + 1;
                                        settlementDelta += _amountIn << 128;
                                        reserveQuote += _amountIn;
                                        reserveBase -= _amountOut;
                                        amountIn += _amountIn;
                                        amountOut += _amountOut;
                                        sizeLeft -= _amountOut;
                                    }
                                    else {
                                        _amountIn = (sizeLeft * _amountIn) / ((reserveBase - sizeLeft) * 9975) + 1;
                                        settlementDelta += _amountIn << 128;
                                        reserveQuote += _amountIn;
                                        reserveBase -= sizeLeft;
                                        amountIn += _amountIn;
                                        amountOut += sizeLeft;
                                        reserves = (reserveQuote << 128) | reserveBase;
                                        if (activated[marketId | (tick >> 8)] != slot) {
                                            activated[marketId | (tick >> 8)] = slot;
                                        }
                                        break;
                                    }
                                }
                            }
                            else if (((orderInfo >> 244 & 0xF) != 0) && ((reserveQuote * scaleFactor * 10000) / (reserveBase * 9975)) > (price * m.makerRebate / 100000)) {
                                if ((orderInfo >> 248 & 0xF) == 0) {
                                    uint256 _amountOut = reserveBase * 10000; // reuse to avoid stack too deep
                                    uint256 worstPrice = (priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFF);
                                    uint256 _amountIn = _sqrt(_amountOut * reserveQuote / (price < worstPrice ? worstPrice : price) * scaleFactor / 9975) - (_amountOut / 9975);
                                    if (sizeLeft > _amountIn) {
                                        _amountOut = ((_amountIn * 9975) * reserveQuote) / (_amountOut + (_amountIn * 9975));
                                        settlementDelta += _amountIn << 128;
                                        reserveBase += _amountIn;
                                        reserveQuote -= _amountOut;
                                        amountIn += _amountIn;
                                        amountOut += _amountOut;
                                        sizeLeft -= _amountIn;
                                    }
                                    else {
                                        _amountOut = ((sizeLeft * 9975) * reserveQuote) / (_amountOut + (sizeLeft * 9975));
                                        settlementDelta += sizeLeft << 128;
                                        reserveBase += sizeLeft;
                                        reserveQuote -= _amountOut;
                                        amountIn += sizeLeft;
                                        amountOut += _amountOut;
                                        reserves = (reserveQuote << 128) | reserveBase;
                                        if (activated[marketId | (tick >> 8)] != slot) {
                                            activated[marketId | (tick >> 8)] = slot;
                                        }
                                        break;
                                    }
                                }
                                else {
                                    uint256 _amountIn = reserveBase * 10000; // reuse to avoid stack too deep
                                    uint256 worstPrice = (priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFF);
                                    uint256 _amountOut = reserveQuote - _sqrt(_amountIn * reserveQuote / scaleFactor * (price < worstPrice ? worstPrice : price) / 9975);
                                    if (sizeLeft > _amountOut) {
                                        _amountIn = (_amountOut * _amountIn) / ((reserveQuote - _amountOut) * 9975) + 1;
                                        settlementDelta += _amountIn << 128;
                                        reserveBase += _amountIn;
                                        reserveQuote -= _amountOut;
                                        amountIn += _amountIn;
                                        amountOut += _amountOut;
                                        sizeLeft -= _amountOut;
                                    }
                                    else {
                                        _amountIn = (sizeLeft * _amountIn) / ((reserveQuote - sizeLeft) * 9975) + 1;
                                        settlementDelta += _amountIn << 128;
                                        reserveBase += _amountIn;
                                        reserveQuote -= sizeLeft;
                                        amountIn += _amountIn;
                                        amountOut += sizeLeft;
                                        reserves = (reserveQuote << 128) | reserveBase;
                                        if (activated[marketId | (tick >> 8)] != slot) {
                                            activated[marketId | (tick >> 8)] = slot;
                                        }
                                        break;
                                    }
                                }
                            }
                            reserves = (reserveQuote << 128) | reserveBase;
                        }
                    }
                    if (((orderInfo >> 244 & 0xF) == 0) ? price > (priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFF) : price < (priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFF)) {
                        if ((orderInfo >> 252) == 1) {
                            revert SlippageExceeded();
                        }
                        if (activated[marketId | (tick >> 8)] != slot) {
                            activated[marketId | (tick >> 8)] = slot;
                        }
                        if ((orderInfo >> 252) == 2) {
                            ((orderInfo >> 244 & 0xF) == 0) ? m.lowestAsk = uint80(price) : m.highestBid = uint80(price);
                            slot = ((orderInfo >> 248 & 0xF) == 0) ? (size - amountIn) : (((orderInfo >> 244 & 0xF) == 0) ? ((size - amountOut) * (priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFF) / scaleFactor) : ((size - amountOut) * scaleFactor / (priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFF)));
                            tick = orderInfo;
                            (slot, id) = _limitOrder(((tick >> 244 & 0xF) == 0), (tick >> 236 & 0x1) == 0, (priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFF), slot, (tick >> 160 & 0x1FFFFFFFFFF), (tick >> 208 & 0x3FF));
                            settlementDelta += (slot << 128);
                            if (slot != 0) { // mtl event is written to memory, emitted in parent
                                assembly {
                                    let length := mload(0xc0)
                                    mstore(add(length, add(0xc0, 0x20)), or(add(0x2000000000000000000000000000000000000000000000000000000000000000,mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(iszero(and(shr(244,orderInfo),0xF))))),or(shl(168,and(0xFFFFFFFFFFFFFFFFFFFF,priceAndReferrer)),or(shl(112,id),slot))))
                                    mstore(0xc0, add(length, 0x20))
                                    mstore(0x40, add(length, add(0xc0, 0x40)))
                                }
                            }
                        }
                        break;
                    }
                    uint256 _priceLevel = priceLevels[marketId | price];
                    {
                        uint256 next = (_priceLevel >> 205) & 0x7FFFFFFFFFFFF;
                        uint256 _orderInfo = orderInfo;
                        while ((_priceLevel & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) != 0 && sizeLeft != 0 && !((_orderInfo >> 252) == 3 && gasleft() < 100000)) {
                            uint256 _order = orders[((next > 0x1FFFFFFFFFF) ? next : marketId | (price << 48) | next)];
                            if ((_orderInfo >> 240 & 0xF) != 0 && (_order >> 113 & 0x1FFFFFFFFFF) == (_orderInfo >> 160 & 0x1FFFFFFFFFF)) {
                                if (((_orderInfo >> 240) & 0x1) != 0) { // stp is 0 do nothing 1 cancel maker 2 cancel taker 3 cancel both
                                    if (next > 0x1FFFFFFFFFF) {
                                        orders[next] &= 0x00000000000000000000000003FFFFFFFFFE0000000000000000000000000000;
                                    }
                                    else {
                                        delete orders[marketId | (price << 48) | next];
                                    }
                                    _priceLevel -= (_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF); // can't overflow
                                    if ((_orderInfo >> 244 & 0xF) == 0) {
                                        settlementDelta += ((_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF));
                                    }
                                    else {
                                        settlementDelta += ((_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF));
                                    }
                                    if ((_order & 0x0000000000000000000000000000000000010000000000000000000000000000) != 0) {
                                        tokenBalances[_order >> 113 & 0x1FFFFFFFFFF][((_orderInfo >> 244 & 0xF) == 0) ? baseAsset : quoteAsset] -= ((((_orderInfo >> 244 & 0xF) == 0) ? (_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) : (_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF)) << 128); // unlock tokens if internal can't overflow
                                    }
                                    assembly {
                                        mstore(add(mload(0xc0), add(0xc0, 0x20)), or(mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(and(shr(244, _orderInfo), 0xF))),or(shl(168,price),or(shl(112,next),and(_order, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF)))))
                                        mstore(0xc0, add(mload(0xc0), 0x20))
                                        mstore(0x40, add(mload(0xc0), add(0xc0, 0x20))) // avoid initializing length bc stack too deep
                                    }
                                    next = (_order >> 205) & 0x7FFFFFFFFFFFF;
                                }
                                if (((_orderInfo >> 240) & 0xF) == 1) {
                                    continue;
                                }
                                else {
                                    sizeLeft = 0;
                                    break;
                                }
                            } // should switch over to do operations on resting size
                            if (((_orderInfo >> 248 & 0xF) == 0) ? (((_orderInfo >> 244 & 0xF) == 0) ? ((_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) > (sizeLeft * m.makerRebate / 100000) * scaleFactor / price) : ((_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) > (sizeLeft * m.makerRebate / 100000) * price / scaleFactor)) : ((_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) > sizeLeft)) {
                                uint256 _amountOut;
                                {
                                    _amountOut = (((_orderInfo >> 248 & 0xF) == 0) ? (((_orderInfo >> 244 & 0xF) == 0) ? (sizeLeft * m.makerRebate / 100000) * scaleFactor / price : (sizeLeft * m.makerRebate / 100000) * price / scaleFactor) : sizeLeft); // output amount for just this swap, round down
                                    amountOut += _amountOut;
                                    if (((_orderInfo >> 248 & 0xF) != 0)) {
                                        sizeLeft = ((_orderInfo >> 244 & 0xF) == 0) ? (sizeLeft * price + scaleFactor - 1) / scaleFactor * 100000 / m.makerRebate : (sizeLeft * scaleFactor + price - 1) / price * 100000 / m.makerRebate; // transfer to maker amount, round up
                                    }
                                    _priceLevel -= _amountOut; // can't overflow
                                    _order -= _amountOut; // can't overflow
                                    orders[((next > 0x1FFFFFFFFFF) ? next : marketId | (price << 48) | next)] = _order;
                                    if (_order & 0x0000000000000000000000000000000000010000000000000000000000000000 == 0) { // maker wants tokens
                                        address owner = userIdToAddress[_order >> 113 & 0x1FFFFFFFFFF];
                                        if ((_orderInfo >> 236 & 0x1) == 0 && (_orderInfo >> 232 & 0x1) == 0) { // taker gives tokens
                                            IERC20(((_orderInfo >> 244 & 0xF) == 0) ? quoteAsset : baseAsset).transferFrom(address(uint160(_orderInfo)), owner, sizeLeft);
                                        }
                                        else { // taker gives internal balance
                                            settlementDelta += sizeLeft << 128;
                                            IERC20(((_orderInfo >> 244 & 0xF) == 0) ? quoteAsset : baseAsset).transfer(owner, sizeLeft);
                                        }
                                    }
                                    else { // maker wants internal balance
                                        settlementDelta += sizeLeft << 128;
                                        tokenBalances[_order >> 113 & 0x1FFFFFFFFFF][((_orderInfo >> 244 & 0xF) == 0) ? quoteAsset : baseAsset] += sizeLeft;
                                        tokenBalances[_order >> 113 & 0x1FFFFFFFFFF][((_orderInfo >> 244 & 0xF) == 0) ? baseAsset : quoteAsset] -= (_amountOut << 128); // unlock maker internal                       
                                    }
                                }
                                amountIn += sizeLeft;
                                address _market = market;
                                assembly {
                                    let length := mload(0xc0)
                                    mstore(add(length, add(0xc0, 0x20)), or(mul(0x1000000000000000000000000000000000000000000000000000000000000000, iszero(and(shr(244, _orderInfo), 0xF))), or(shl(168, price), or(shl(112, next), and(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF, _order)))))
                                    mstore(add(length, add(0xc0, 0x40)), _amountOut)
                                    log2(add(length, add(0xc0, 0x20)), 0x40, _market, and(0x1FFFFFFFFFF, shr(113, _order))) // anon event (orderfilled)
                                    mstore(0x40, add(length, add(0xc0, 0x20)))
                                }
                                sizeLeft = 0;
                            }
                            else {
                                uint256 transferAmount = ((_orderInfo >> 244 & 0xF) == 0) ? ((((_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) * price / scaleFactor) * 100000) / m.makerRebate) : ((((_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) * scaleFactor / price) * 100000) / m.makerRebate);
                                amountIn += transferAmount; // round up maybe?
                                uint256 _amountOut = (_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
                                amountOut += _amountOut;
                                _priceLevel -= _amountOut;
                                sizeLeft -= ((_orderInfo >> 248 & 0xF) == 0) ? transferAmount : _amountOut;
                                if (_order & 0x0000000000000000000000000000000000010000000000000000000000000000 == 0) { // maker wants tokens
                                    address owner = userIdToAddress[_order >> 113 & 0x1FFFFFFFFFF];
                                    if ((_orderInfo >> 236 & 0x1) == 0 && (_orderInfo >> 232 & 0x1) == 0) { // taker gives tokens
                                        IERC20(((_orderInfo >> 244 & 0xF) == 0) ? quoteAsset : baseAsset).transferFrom(address(uint160(_orderInfo)), owner, transferAmount);
                                    }
                                    else { // taker gives internal balance
                                        settlementDelta += transferAmount << 128;
                                        IERC20(((_orderInfo >> 244 & 0xF) == 0) ? quoteAsset : baseAsset).transfer(owner, transferAmount);
                                    }
                                }
                                else { // maker wants internal balance
                                    settlementDelta += transferAmount << 128;
                                    tokenBalances[_order >> 113 & 0x1FFFFFFFFFF][((_orderInfo >> 244 & 0xF) == 0) ? quoteAsset : baseAsset] += transferAmount;
                                    tokenBalances[_order >> 113 & 0x1FFFFFFFFFF][((_orderInfo >> 244 & 0xF) == 0) ? baseAsset : quoteAsset] -= _amountOut << 128; // unlock maker internal                      
                                }
                                address _market = market;
                                assembly {
                                    let length := mload(0xc0)
                                    mstore(add(length, add(0xc0, 0x20)), or(mul(0x1000000000000000000000000000000000000000000000000000000000000000, iszero(and(shr(244, _orderInfo), 0xF))), or(shl(168, price), shl(112, next))))
                                    mstore(add(length, add(0xc0, 0x40)), and(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF, _order))
                                    log2(add(length, add(0xc0, 0x20)), 0x40, _market, and(0x1FFFFFFFFFF, shr(113, _order))) // anon event (orderfilled)
                                    mstore(0x40, add(length, add(0xc0, 0x20)))
                                }
                                if (next > 0x1FFFFFFFFFF) {
                                    orders[next] &= 0x00000000000000000000000003FFFFFFFFFE0000000000000000000000000000;
                                }
                                else {
                                    delete orders[marketId | (price << 48) | next];
                                }
                                next = (_order >> 205) & 0x7FFFFFFFFFFFF;
                            }
                        }
                        priceLevels[marketId | price] = (next << 205) | (_priceLevel & 0x0000000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF); // set fillnext to next
                    }
                    assembly {
                        let temp := mload(0x80)
                        temp := or(and(temp, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000000000000000000000000000), price) // set end price
                        mstore(0x80, temp)
                    }
                    if ((_priceLevel & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) == 0) {
                        slot &= ~(1 << (tick % 256));
                        uint256 slotIndex = tick >> 8;
                        if ((orderInfo >> 244 & 0xF) == 0) {
                            uint256 _slot = slot >> tick % 256;
                            if (_slot == 0 && activated[marketId | slotIndex] != slot) {
                                activated[marketId | slotIndex] = slot;
                            }
                            while (_slot == 0) {
                                ++slotIndex;
                                slot = activated[marketId | slotIndex];
                                _slot = slot;
                                tick = slotIndex << 8;
                            }
                            tick = _searchSlotUp(_slot, tick);
                        }
                        else {
                            uint256 _slot = slot & ((1 << (tick % 256)) - 1);
                            if (_slot == 0 && activated[marketId | slotIndex] != slot) {
                                activated[marketId | slotIndex] = slot;
                            }
                            while (_slot == 0) {
                                --slotIndex;
                                slot = activated[marketId | slotIndex];
                                _slot = slot;
                            }
                            tick = _searchSlotDown(_slot, slotIndex << 8);
                        }
                        price = _tickToPrice(tick);
                    }
                    else {
                        if (activated[marketId | (tick >> 8)] != slot) {
                            activated[marketId | (tick >> 8)] = slot;
                        }
                    }
                    if (sizeLeft == 0 || ((orderInfo >> 252) == 3 && gasleft() < 100000)) {
                        break;
                    }
                }
            }
            if (amountOut != 0) {
                {   
                    if (reserves != 0) {
                        (uint112 reserveQuote, uint112 reserveBase) = (uint112(reserves >> 128), uint112(reserves & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF));
                        if (reserveQuote != m.reserveQuote || reserveBase != m.reserveBase) {
                            (m.reserveQuote, m.reserveBase) = (reserveQuote, reserveBase);
                            emit Sync(market, reserveQuote, reserveBase);
                        }
                    }
                }
                uint256 feeAmount;
                if ((orderInfo >> 244 & 0xF) == 0) {
                    feeAmount = (amountIn * 100000 + m.takerFee - 1) / m.takerFee - amountIn;
                    amountIn += feeAmount;
                    settlementDelta += (feeAmount << 128);
                    m.lowestAsk = uint80(price);
                }
                else {
                    feeAmount = amountOut - amountOut * m.takerFee / 100000;
                    amountOut -= feeAmount;
                    m.highestBid = uint80(price);
                }
                if (address(uint160(priceAndReferrer >> 80)) == address(0)) {
                    claimableRewards[quoteAsset][feeRecipient] += feeAmount;
                }
                else {
                    uint256 amountCommission = feeAmount * feeCommission / 100;
                    claimableRewards[quoteAsset][address(uint160(priceAndReferrer >> 80))] += amountCommission;
                    uint256 amountRebate = feeAmount * feeRebate / 100;
                    claimableRewards[quoteAsset][address(uint160(orderInfo))] += amountRebate;
                    claimableRewards[quoteAsset][feeRecipient] += (feeAmount - amountCommission - amountRebate);
                }
                assembly {
                    price := mload(0x80)
                }
                emit Trade(market, (orderInfo >> 160) & 0x1FFFFFFFFFF, address(uint160(orderInfo)), (orderInfo >> 244 & 0xF) == 0, amountIn, amountOut, price >> 128, price & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
                return (amountIn, amountOut, id, settlementDelta);
            }
            else {
                return (amountIn, 0, id, settlementDelta);
            }
        }
    }
    // done
    function _limitOrder(bool isBuy, bool isRecieveTokens, uint256 price, uint256 size, uint256 userId, uint256 cloid) internal returns (uint256, uint256 id) { // cloid being under uint10 is enforced in entry points
        unchecked {
            Market storage m = _getMarket[market];
            (uint256 _highestBid, uint256 _lowestAsk) = (m.highestBid, m.lowestAsk);
            if (isBuy) {
                if (price >= _lowestAsk || price == 0 || size < ((m.minSize >> 20) * 10 ** (m.minSize & 0xFFFFF)) || ((orders[(cloid << 41) | userId] & 0xFFFFFFFFFFFFFFFFFFFFFFFFFC0000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFF) != 0)) {
                    return (0, 0);
                }
                if (price > _highestBid) {
                    m.highestBid = uint80(price);
                }
                if (!isRecieveTokens) {
                    tokenBalances[userId][quoteAsset] += (size << 128); // lock tokens if internal
                }
            }
            else {
                if (price <= _highestBid || price >= maxPrice || (size * price / scaleFactor) < ((m.minSize >> 20) * 10 ** (m.minSize & 0xFFFFF)) || ((orders[(cloid << 41) | userId] & 0xFFFFFFFFFFFFFFFFFFFFFFFFFC0000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFF) != 0)) {
                    return (0, 0);
                }
                if (price < _lowestAsk) {
                    m.lowestAsk = uint80(price);
                }
                if (!isRecieveTokens) {
                    tokenBalances[userId][baseAsset] += (size << 128); // lock tokens if internal
                }
            }
            uint256 _priceLevel = priceLevels[marketId | price];
            require((size <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) && ((_priceLevel & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) + size) <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF); // overflow check, if invalid params are entered could revert instead of silent return
            if (cloid != 0) {
                _highestBid = ((cloid | 1) << 41) | userId;
                if (cloid & 1 == 1) {
                    cloidVerify[_highestBid] = cloidVerify[_highestBid] & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000000000000000000000000000 | ((marketId >> 48) | price);
                }
                else {
                    cloidVerify[_highestBid] = cloidVerify[_highestBid] & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF | ((marketId << 80) | (price << 128));
                }
                cloid = (cloid << 41) | userId; // cloid to pointer using userid
                if ((_priceLevel & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) == 0) {
                    require(price % tickSize == 0);
                    uint256 tick = _priceToTick(price);
                    activated[marketId | (tick >> 8)] |= (1 << (tick % 256));
                    _priceLevel =  (cloid << 205) | (_priceLevel & 0x0000000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF); // set fillNext to cloid
                }
                else {
                    uint256 fillBefore = (_priceLevel >> 154) & 0x7FFFFFFFFFFFF;
                    orders[(fillBefore > 0x1FFFFFFFFFF) ? fillBefore : (marketId | (price << 48) | fillBefore)] = (cloid << 205) | (orders[(fillBefore > 0x1FFFFFFFFFF) ? fillBefore : (marketId | (price << 48) | fillBefore)] & 0x0000000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF); // set fillbefores fillafter to cloid instead of prev native id
                }
                orders[cloid] = (((_priceLevel >> 113 & 0x1FFFFFFFFFF) + 1) << 205) | (_priceLevel & (0x7FFFFFFFFFFFF << 154)) | (userId << 113) | (isRecieveTokens ? 0 : (1 << 112)) | size; // fillAfter to priceLevels latestNativeId+1, fillBefore to latest
                priceLevels[marketId | price] = (cloid << 154) | ((_priceLevel & 0xFFFFFFFFFFFFE0000000000003FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) + size); // latest to cloid and add size
                return (size, cloid);
            }
            else {
                id = (_priceLevel >> 113 & 0x1FFFFFFFFFF) + 1;
                require(id <= 0x1FFFFFFFFFF); // overflow uint41
                if ((_priceLevel & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) == 0) {
                    require(price % tickSize == 0);
                    uint256 tick = _priceToTick(price);
                    activated[marketId | (tick >> 8)] |= (1 << (tick % 256));
                    _priceLevel = (id << 205) | (_priceLevel & 0x0000000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF); // set fillNext to id, sometimes redundant
                }
                orders[marketId | (price << 48) | id] = ((id + 1) << 205) | (_priceLevel & (0x7FFFFFFFFFFFF << 154)) | (userId << 113) | (isRecieveTokens ? 0 : (1 << 112)) | size; // fillAfter to id+1, fillBefore to latest
                priceLevels[marketId | price] = (id << 154) | (id << 113) | ((_priceLevel & 0xFFFFFFFFFFFFE00000000000000000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFF) + size); // latest and latestNativeId to id and add size
                return (size, id);
            }
        }       
    }
    // done
    function _cancelOrder(uint256 price, uint256 id, uint256 userId) internal returns (uint256, uint256 size, bool isBuy) { // id is cloid if price is missing
        unchecked {
            Market storage m = _getMarket[market];
            uint256 _order = orders[(price != 0 ? (marketId | (price << 48) | id) : ((id << 41) | userId))]; // id is not yet pointer
            size = (_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
            if (0 == size || userId != (_order >> 113 & 0x1FFFFFFFFFF)) {
                return (0, 0, isBuy);
            }
            if (price != 0) {
                delete orders[marketId | (price << 48) | id];
            }
            else {
                price = cloidVerify[((id | 1) << 41) | userId]; // avoid stack too deep, there's no reason to zero out/edit this as it's not needed
                if (id & 1 == 1) { // make sure order is in right market, get price because cloid doesn't come with it
                    if (((price >> 80) & 0xFFFFFFFFFFFF) != (marketId >> 128)) {
                        return (0, 0, isBuy);
                    }
                    price = price & 0xFFFFFFFFFFFFFFFFFFFF;
                }
                else {
                    if (((price >> 208) & 0xFFFFFFFFFFFF) != (marketId >> 128)) {
                        return (0, 0, isBuy);
                    }
                    price = (price >> 128) & 0xFFFFFFFFFFFFFFFFFFFF;
                }
                id = (id << 41) | userId; // id to pointer using userid
                orders[id] &= 0x00000000000000000000000003FFFFFFFFFE0000000000000000000000000000;
            }
            (uint256 _highestBid, uint256 _lowestAsk) = (m.highestBid, m.lowestAsk);
            if (price <= _highestBid) {
                isBuy = true;
                if ((_order & 0x0000000000000000000000000000000000010000000000000000000000000000) != 0) {
                    tokenBalances[userId][quoteAsset] -= (size << 128); // unlock tokens if internal can't overflow
                }
            }
            else {
                if ((_order & 0x0000000000000000000000000000000000010000000000000000000000000000) != 0) {
                    tokenBalances[userId][baseAsset] -= (size << 128); // unlock tokens if internal can't overflow
                }
            }
            _internalCancel(price, id, size, _highestBid, _lowestAsk, _order);
            return (price, size, isBuy);
        }
    }
    // done
    function _decreaseOrder(uint256 price, uint256 id, uint256 decreaseAmount, uint256 userId) internal returns (uint256, uint256 size, bool isBuy) { // id is cloid if price is missing
        unchecked {
            Market storage m = _getMarket[market];
            uint256 _order = orders[(price != 0 ? (marketId | (price << 48) | id) : ((id << 41) | userId))]; // id is not yet pointer
            size = (_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
            if (0 == size || userId != (_order >> 113 & 0x1FFFFFFFFFF)) {
                return (0, 0, isBuy);
            }
            if (price == 0) {
                price = cloidVerify[((id | 1) << 41) | userId]; // avoid stack too deep, there's no reason to zero out/edit this as it's not needed
                if (id & 1 == 1) { // make sure order is in right market, get price because cloid doesn't come with it
                    if (((price >> 80) & 0xFFFFFFFFFFFF) != (marketId >> 128)) {
                        return (0, 0, isBuy);
                    }
                    price = price & 0xFFFFFFFFFFFFFFFFFFFF;
                }
                else {
                    if (((price >> 208) & 0xFFFFFFFFFFFF) != (marketId >> 128)) {
                        return (0, 0, isBuy);
                    }
                    price = (price >> 128) & 0xFFFFFFFFFFFFFFFFFFFF;
                }
                id = (id << 41) | userId; // id to pointer using userid
            }
            (uint256 _highestBid, uint256 _lowestAsk) = (m.highestBid, m.lowestAsk);
            if (price <= _highestBid) {
                isBuy = true;
            }
            if ((isBuy ? size : (size * price / scaleFactor)) <= (isBuy ? decreaseAmount : (decreaseAmount * price / scaleFactor)) + (((m.minSize >> 20) * 10 ** (m.minSize & 0xFFFFF)))) { // cancel if resulting order would be too small
                if ((_order & 0x0000000000000000000000000000000000010000000000000000000000000000) != 0) {
                    isBuy ? tokenBalances[userId][quoteAsset] -= (size << 128) : tokenBalances[userId][baseAsset] -= (size << 128); // unlock tokens if internal can't overflow
                }
                if (price != 0) {
                    delete orders[marketId | (price << 48) | id];
                }
                else {
                    orders[id] &= 0x00000000000000000000000003FFFFFFFFFE0000000000000000000000000000;
                }
                _internalCancel(price, id, size, _highestBid, _lowestAsk, _order);
                return (price, size, isBuy);
            }
            else {
                if ((_order & 0x0000000000000000000000000000000000010000000000000000000000000000) != 0) {
                    isBuy ? tokenBalances[userId][quoteAsset] -= (decreaseAmount << 128) : tokenBalances[userId][baseAsset] -= (decreaseAmount << 128); // unlock tokens if internal can't overflow
                }
                orders[(price != 0 ? (marketId | (price << 48) | id) : id)] -= decreaseAmount; // can't overflow
                priceLevels[marketId | price] -= decreaseAmount;
                return (price, decreaseAmount << 128, isBuy); // price, decrease amount, isBuy
            }
        }
    }
    // done
    function _replaceOrder(uint256 options, uint256 price, uint256 id, uint256 newPrice, uint256 size) internal returns (int256 quoteAssetDebt, int256 baseAssetDebt, uint256) {
        unchecked {
            bool _isBuy;
            bool _isCloid;
            uint256 _size;
            if (price != 0) {
                _size = (orders[(marketId | (price << 48) | id)] & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF); // id is not pointer
            }
            else {
                _isCloid = true;
                price = cloidVerify[((id | 1) << 41) | (options & 0x1FFFFFFFFFF)]; // avoid stack too deep, there's no reason to zero out/edit this as it's not needed
                if (id & 1 == 1) { // make sure order is in right market, get price because cloid doesn't come with it
                    if (((price >> 80) & 0xFFFFFFFFFFFF) != (marketId >> 128)) {
                        return (0, 0, 0);
                    }
                    price = price & 0xFFFFFFFFFFFFFFFFFFFF;
                }
                else {
                    if (((price >> 208) & 0xFFFFFFFFFFFF) != (marketId >> 128)) {
                        return (0, 0, 0);
                    }
                    price = (price >> 128) & 0xFFFFFFFFFFFFFFFFFFFF;
                }
                _size = (orders[((id << 41) | (options & 0x1FFFFFFFFFF))] & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF); // id is not pointer
            }
            if (price <= _getMarket[market].highestBid) {
                _isBuy = true;
            }
            if (newPrice == 0) {
                newPrice = price;
            }
            if ((((options >> 48) & 0xF) != 0) || (newPrice == price && (_size > size))) {
                (price, _size, _isBuy) = _decreaseOrder(_isCloid ? 0 : price, id, _size - size, (options & 0x1FFFFFFFFFF)); // price is 0 if cloid
                if (_isCloid) {
                    id = (id << 41) | (options & 0x1FFFFFFFFFF); // differentiate emitted cloid
                }
                if (_size != 0) {
                    if ((_size >> 128) == 0) { // cancel
                        _isBuy ? quoteAssetDebt -= int256(_size & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) : baseAssetDebt -= int256(_size & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
                        assembly {
                            let length := mload(0xc0)
                            mstore(add(length, 0xe0), or(mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(_isBuy)),or(shl(168,price),or(shl(112,id),and(112, _size))))) // 3 bits flag 80 price 56 id 112 cancel size
                            mstore(0xc0, add(length, 0x20))
                            mstore(0x40, add(length, 0x100))
                        }
                    }
                    else {
                        _isBuy ? quoteAssetDebt -= int256(_size >> 128) : baseAssetDebt -= int256(_size >> 128);
                        assembly {
                            let length := mload(0xc0)
                            mstore(add(length, 0xe0), or(add(0x4000000000000000000000000000000000000000000000000000000000000000,mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(_isBuy))),or(shl(168,price),or(shl(112,id),shr(128, _size))))) // 3 bits flag 80 price 56 id 112 decrease size not remaining
                            mstore(0xc0, add(length, 0x20))
                            mstore(0x40, add(length, 0x100))
                        }
                    }
                    return (quoteAssetDebt, baseAssetDebt, id);
                }
                else {
                    return (0, 0, 0); // no state is changed, can silent return
                }
            }
            else {
                (price, _size, _isBuy) = _cancelOrder((_isCloid) ? 0 : price, id, (options & 0x1FFFFFFFFFF)); // price is 0 if cloid
                if (_isCloid) {
                    id = (id << 41) | (options & 0x1FFFFFFFFFF); // differentiate emitted cloid
                }
                if (_size != 0) {
                    _isBuy ? quoteAssetDebt -= int256(_size) : baseAssetDebt -= int256(_size);
                    assembly {
                        let length := mload(0xc0)
                        mstore(add(length, 0xe0), or(mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(_isBuy)),or(shl(168,price),or(shl(112,id),_size)))) // 3 bits flag 80 price 56 id 112 size
                        mstore(0xc0, add(length, 0x20))
                        mstore(0x40, add(length, 0x100))
                    }
                }
                else {
                    return (0, 0, 0); // no state is changed, can silent return
                }
                if (_isCloid) {
                    id = id >> 41; // back to normal cloid
                }
                if (size == 0) {
                    size = _size;
                }
                if (((options >> 44) & 0xF) == 0) { // post only
                    (_size, id) = _limitOrder(_isBuy, (((options >> 60) & 0xF) == 0), newPrice, size, (options & 0x1FFFFFFFFFF), id);
                    if (_size != 0) {
                        _isBuy ? quoteAssetDebt += int256(_size) : baseAssetDebt += int256(_size);
                        assembly {
                            let length := mload(0xc0)
                            mstore(add(length, 0xe0), or(add(0x2000000000000000000000000000000000000000000000000000000000000000,mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(_isBuy))),or(shl(168,newPrice),or(shl(112,id),_size)))) // 3 bits flag 80 price 56 id 112 size
                            mstore(0xc0, add(length, 0x20))
                            mstore(0x40, add(length, 0x100))
                        }
                    }
                    else {
                        return (quoteAssetDebt, baseAssetDebt, 0);
                    }
                }
                else {
                    _isCloid = ((options >> 60) & 0xF) == 0; // avoid stack too deep, true if external balances
                    uint256 settlementDelta;
                    uint256 referrer = (options >> 96);
                    uint256 orderInfo = (2 << 252) | (_isBuy ? 0 : (1 << 244)) | (1 << 240) | (_isCloid ? 0 : (1 << 236)) | (id << 208) | ((options & 0x1FFFFFFFFFF) << 160) | uint160(msg.sender);
                    (, _size, id, settlementDelta) = _marketOrder(size, (uint160(referrer) << 80) | newPrice, orderInfo);
                    if (_isBuy) {
                        quoteAssetDebt += int256(settlementDelta >> 128);
                        baseAssetDebt -= int256(_size + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                    }
                    else {
                        baseAssetDebt += int256(settlementDelta >> 128);
                        quoteAssetDebt -= int256(_size + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                    }
                }
                return (quoteAssetDebt, baseAssetDebt, id);
            }
        }
    }
    // make sure to keep pricetimepriority, relinking order on partial fill is fine because it's a single fill
    function _placeGridOrder(bool isBuy, uint256 price, uint256 mirroredPrice, uint256 size, uint256 userId) internal returns (uint256 _size, uint256 id) {
    }
    // done, these methods support margin which is managed before/after the call, just set internal balance mode to true
    function marketOrder(bool isBuy, bool isExactInput, uint256 options, uint256 orderType, uint256 size, uint256 worstPrice, address referrer, address caller) external payable returns (uint256 amountIn, uint256 amountOut, uint256 id) {
        unchecked {
            uint256 orderInfo; // options is 0-44 userId 44-54 cloid 56-60 stp 60-64 tointernalbalances 64-68 frominternalbalances 68-72 useinternalbalances
            uint256 userId;
            {
                uint256 orderFlags = ((orderType & 0xF) << 252) | ((isExactInput ? 0 : (1 << 248))) | ((isBuy ? 0 : (1 << 244))) | (((options >> 56) & 0xF) << 240); // ordertype exactinput=0 isbuy=0 stp
                orderInfo = orderFlags | (((options >> 68) & 0xF) << 236) | (((options >> 64) & 0xF) << 232) | uint160(caller); // useexternalbalance=0 fromcaller=0 add userId 160-208 if internal balance or mtl and cloid if provided 208-218 if mtl and margin enforced elsewhere
                userId = (options & 0x1FFFFFFFFFF);
                if (userId != 0) {
                    require(userIdToAddress[userId] == caller);
                }
                else {
                    userId = addressToUserId[caller];
                    if (userId == 0) {
                        userId = ICrystal(crystal).registerUser();
                    }
                }
                orderInfo |= (userId << 160); // add userId to orderInfo
                if (((options >> 44) & 0x3FF) != 0) { // if cloid
                    orderInfo |= (((options >> 44) & 0x3FF) << 208);
                }
            }
            uint256 settlementDelta;
            assembly {
                mstore(0x40, 0xe0) // 0x80 is used by _marketOrder internally to avoid stack too deep
            }
            (amountIn, amountOut, id, settlementDelta) = _marketOrder(size, (uint160(referrer) << 80) | worstPrice, orderInfo);
            address _market = market;
            assembly {
                let length := mload(0xc0)
                if gt(length, 0) {
                    mstore(0xa0, 0x20)
                    log3(0xa0, add(length, 0x40), 0xcd726e874e479599fa8abfd7a4ad443b08415d78fb36a088cd0e9c88b249ba66, _market, userId)
                }
            }
            address token = isBuy ? quoteAsset : baseAsset;
            if ((settlementDelta >> 128) != 0) { // input token for both limit order and maker internal balance fills
                if (((options >> 68) & 0xF) != 0) {
                    uint256 balance = tokenBalances[userId][token];
                    if (uint128(balance) < (settlementDelta >> 128)) {
                        revert ActionFailed();
                    }
                    else {
                        tokenBalances[userId][token] = balance - (settlementDelta >> 128);
                    }
                }
                else { // use external balance
                    if (((options >> 64) & 0xF) != 0) { // use router balance
                        uint256 balance = tokenBalances[0][token];
                        if (uint128(balance) < (settlementDelta >> 128)) {
                            revert ActionFailed();
                        }
                        else {
                            tokenBalances[0][token] = balance - (settlementDelta >> 128);
                        }
                    }
                    else {
                        IERC20(token).transferFrom(caller, address(this), (settlementDelta >> 128));
                    }
                }
            }
            settlementDelta &= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
            settlementDelta += amountOut; // add output to self cancel credit
            token = isBuy ? baseAsset : quoteAsset;
            if (settlementDelta != 0) { // output token, stp cancels + amountout
                if (((options >> 68) & 0xF) != 0) {
                    tokenBalances[userId][token] += settlementDelta;
                }
                else { // use external balance
                    if (((options >> 60) & 0xF) != 0) {
                        tokenBalances[0][token] += settlementDelta;
                    }
                    else {
                        IERC20(token).transfer(caller, settlementDelta);
                    }
                }
            }
        }
    }
    // done
    function limitOrder(bool isBuy, uint256 options, uint256 price, uint256 size, address caller) external payable returns (uint256 id) { // options is 0-41 userId 44-54 cloid 56-60 frominternalbalances 60-64 useinternalbalances
        unchecked {
            uint256 userId = (options & 0x1FFFFFFFFFF);
            if (userId != 0) { // if userId is supplied verify
                require(userIdToAddress[userId] == caller);
            }
            else { // get default userId
                userId = addressToUserId[caller];
                if (userId == 0) {
                    userId = ICrystal(crystal).registerUser();
                }
            }
            bool useExternalBalances = (((options >> 60) & 0xF) == 0);
            (size, id) = _limitOrder(isBuy, useExternalBalances, price, size, userId, (options >> 44) & 0x3FF);
            if (size != 0) { // if order success
                address token = isBuy ? quoteAsset : baseAsset;
                if (useExternalBalances) {
                    if (((options >> 56) & 0xF) != 0) {
                        uint256 balance = tokenBalances[0][token];
                        if (uint128(balance) < size) {
                            revert ActionFailed();
                        }
                        else {
                            tokenBalances[0][token] = balance - size;
                        }
                    }
                    else {
                        IERC20(token).transferFrom(caller, address(this), size);
                    }
                }
                else {
                    uint256 balance = tokenBalances[userId][token];
                    if (uint128(balance) < size) {
                        revert ActionFailed();
                    }
                    else {
                        tokenBalances[userId][token] = balance - size; // token txfer don't care about locking since done in internal function
                    }
                }
                emit OrdersUpdated(market, userId, abi.encodePacked((isBuy ? 0x2000000000000000000000000000000000000000000000000000000000000000 : 0x3000000000000000000000000000000000000000000000000000000000000000) | (price << 168) | (id << 112) | size)); // if id is a cloid it is already merged w user id
            }
            else {
                revert ActionFailed();
            }
        }
    } 
    // done
    function cancelOrder(uint256 options, uint256 price, uint256 id, address caller) external payable returns (uint256 size) { // options is 0-41 userId 44-48 tointernalbalances 48-52 useinternalbalances
        unchecked {
            bool isBuy;
            uint256 userId = (options & 0x1FFFFFFFFFF);
            if (userId != 0) { // if userId is supplied verify
                require(userIdToAddress[userId] == caller);
            }
            else { // get default userId
                userId = addressToUserId[caller];
            }
            bool useExternalBalances = (((options >> 48) & 0xF) == 0);
            bool isCloid = (price == 0); // if price isn't 0 assume it's a normal order
            (price, size, isBuy) = _cancelOrder(price, id, userId); // if no price attached update price
            if (isCloid) {
                id = (id << 41) | userId;
            }
            if (size != 0) { // if cancel success
                address token = isBuy ? quoteAsset : baseAsset;
                if (useExternalBalances) {
                    if (((options >> 44) & 0xF) != 0) {
                        tokenBalances[0][token] += size;
                    }
                    else {
                        IERC20(token).transfer(caller, size);
                    }
                }
                else {
                    tokenBalances[userId][token] += size;
                }
                emit OrdersUpdated(market, userId, abi.encodePacked((isBuy ? 0 : 0x1000000000000000000000000000000000000000000000000000000000000000) | (price << 168) | (id << 112) | size));
            }
        }
    }
    // replace is useful in that if cancel fails there's no order, will decrease if its best course of action, and also that you can take the proceeds of the cancel as the order size by setting size=0, can also do decrease
    function replaceOrder(uint256 options, uint256 price, uint256 id, uint256 newPrice, uint256 size, address referrer, address caller) external payable returns (uint256 _id) { // options is 0-41 userId 44-48 postOnly=0 48-52 isDecrease 52-56 tointernalbalances 56-60 frominternalbalances 60-64 useinternalbalances
        int256 quoteAssetDebt;
        int256 baseAssetDebt;
        uint256 userId = (options & 0x1FFFFFFFFFF);
        if (userId != 0) { // if userId is supplied verify
            require(userIdToAddress[userId] == caller);
        }
        else { // get default userId
            userId = addressToUserId[caller];
            options = (options & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE0000000000) | userId; // add userId to options
            if (userId == 0) {
                userId = ICrystal(crystal).registerUser();
            }
        }
        options = (uint160(referrer) << 96) | options;
        assembly {
            mstore(0x40, 0xe0) // 0x80 is used by _marketOrder internally to avoid stack too deep
        }
        (quoteAssetDebt, baseAssetDebt, _id) = _replaceOrder(options, price, id, newPrice, size);
        uint256 balanceMode = options; // avoid std
        _settleBalances(caller, quoteAssetDebt, baseAssetDebt, userId, ((balanceMode >> 60) & 0xF), ((balanceMode >> 52) & 0xF), ((balanceMode >> 56) & 0xF));
        address _market = market;
        assembly {
            let length := mload(0xc0)
            switch gt(length, 0)
            case true {
                mstore(0xa0, 0x20)
                log3(0xa0, add(length, 0x40), 0xcd726e874e479599fa8abfd7a4ad443b08415d78fb36a088cd0e9c88b249ba66, _market, userId)
            }
            default {
                revert(0, 0)
            }
        }
    }
    // done except replace if needed, maybe add bribe endpoint in parent, do margin in balance mode param
    function batchOrders(Action[] calldata actions, uint256 options, address referrer, address caller) external payable { // options is 0-41 userId 44-48 tointernalbalances 48-52 frominternalbalances 52-56 useinternalbalances
        unchecked {
            uint256 userId;
            uint256 offset;
            uint256 action;
            uint256 param1;
            uint256 param2;
            uint256 cloid;
            bool isBuy;
            uint256 balanceMode;
            int256 quoteAssetDebt;
            int256 baseAssetDebt;
            if ((options & 0x1FFFFFFFFFF) != 0) { // if userId is supplied verify
                userId = (options & 0x1FFFFFFFFFF);
                require(userIdToAddress[userId] == caller);
            }
            else { // get default userId
                userId = addressToUserId[caller];
                if (userId == 0) {
                    userId = ICrystal(crystal).registerUser();
                }
            }
            balanceMode = ((options >> 52) & 0xF);
            assembly {
                mstore(0x40, 0xe0)
            }
            while (offset < actions.length) {
                action = actions[offset].action & 0xF;
                param1 = actions[offset].param1 & 0xFFFFFFFFFFFFFFFFFFFF;
                param2 = actions[offset].param2 & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
                cloid = actions[offset].param3 & 0x3FF;
                if (action == 1) { // cancel, pass either price and id or cloid
                    if (cloid != 0) {
                        (param1, action, isBuy) = _cancelOrder(0, cloid, userId);
                        param2 = (cloid << 41) | userId; // differentiate emitted cloid
                    }
                    else {
                        (param1, action, isBuy) = _cancelOrder(param1, param2, userId);
                    }
                    if (action != 0) {
                        isBuy ? quoteAssetDebt -= int256(action) : baseAssetDebt -= int256(action);
                        assembly {
                            let length := mload(0xc0)
                            mstore(add(length, 0xe0), or(mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(isBuy)),or(shl(168,param1),or(shl(112,param2),action)))) // 8 flag 80 price 56 id 112 size
                            mstore(0xc0, add(length, 0x20))
                            mstore(0x40, add(length, 0x100))
                        }
                    }
                    else {
                        if (actions[offset].isRequireSuccess) {
                            revert ActionFailed();
                        }
                    }
                }
                else if (action == 2) { // limit buy, pass price size and optional cloid
                    (action, param2) = _limitOrder(true, balanceMode == 0, param1, param2, userId, cloid);
                    if (action != 0) {
                        quoteAssetDebt += int256(action);
                        assembly {
                            let length := mload(0xc0)
                            mstore(add(length, 0xe0), or(0x2000000000000000000000000000000000000000000000000000000000000000,or(shl(168,param1),or(shl(112,param2),action)))) // 8 flag 80 price 56 id 112 size
                            mstore(0xc0, add(length, 0x20))
                            mstore(0x40, add(length, 0x100))
                        }
                    }
                    else {
                        if (actions[offset].isRequireSuccess) {
                            revert ActionFailed();
                        }
                    }
                }
                else if (action == 3) { // limit sell
                    (action, param2) = _limitOrder(false, balanceMode == 0, param1, param2, userId, cloid);
                    if (action != 0) {
                        baseAssetDebt += int256(action);
                        assembly {
                            let length := mload(0xc0)
                            mstore(add(length, 0xe0), or(0x3000000000000000000000000000000000000000000000000000000000000000, or(shl(168,param1),or(shl(112,param2),action)))) // 8 flag 80 price 56 id 112 size
                            mstore(0xc0, add(length, 0x20))
                            mstore(0x40, add(length, 0x100))
                        }
                    }
                    else {
                        if (actions[offset].isRequireSuccess) {
                            revert ActionFailed();
                        }
                    }
                }
                else if (action == 4) { // mtl buy
                    uint256 settlementDelta;
                    settlementDelta = (uint160(referrer) << 80) | param1; // avoid stack too deep
                    ( , action, , settlementDelta) = _marketOrder(param2, settlementDelta, (2 << 252) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    quoteAssetDebt += int256(settlementDelta >> 128);
                    baseAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 5) { // mtl sell
                    uint256 settlementDelta;
                    settlementDelta = (uint160(referrer) << 80) | param1;
                    ( , action, , settlementDelta) = _marketOrder(param2, settlementDelta, (2 << 252) | (1 << 244) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    baseAssetDebt += int256(settlementDelta >> 128);
                    quoteAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 6) { // partialfill buy
                    uint256 settlementDelta;
                    settlementDelta = (uint160(referrer) << 80) | param1;
                    ( , action, , settlementDelta) = _marketOrder(param2, settlementDelta, (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    quoteAssetDebt += int256(settlementDelta >> 128);
                    baseAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 7) { // partialfill sell
                    uint256 settlementDelta;
                    settlementDelta = (uint160(referrer) << 80) | param1;
                    ( , action, , settlementDelta) = _marketOrder(param2, settlementDelta, (1 << 244) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    baseAssetDebt += int256(settlementDelta >> 128);
                    quoteAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 8) { // partial buy terminate when low on remaining gas
                    uint256 settlementDelta;
                    settlementDelta = (uint160(referrer) << 80) | param1;
                    ( , action, , settlementDelta) = _marketOrder(param2, settlementDelta, (3 << 252) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    quoteAssetDebt += int256(settlementDelta >> 128);
                    baseAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 9) { // partial sell terminate when low on remaining gas
                    uint256 settlementDelta;
                    settlementDelta = (uint160(referrer) << 80) | param1;
                    ( , action, , settlementDelta) = _marketOrder(param2, settlementDelta, (3 << 252) | (1 << 244) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    baseAssetDebt += int256(settlementDelta >> 128);
                    quoteAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 10) { // complete fill buy
                    uint256 settlementDelta;
                    settlementDelta = (uint160(referrer) << 80) | param1;
                    ( , action, , settlementDelta) = _marketOrder(param2, settlementDelta, (1 << 252) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    quoteAssetDebt += int256(settlementDelta >> 128);
                    baseAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 11) { // complete fill sell
                    uint256 settlementDelta;
                    settlementDelta = (uint160(referrer) << 80) | param1;
                    ( , action, , settlementDelta) = _marketOrder(param2, settlementDelta, (1 << 252) | (1 << 244) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    baseAssetDebt += int256(settlementDelta >> 128);
                    quoteAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 12) { // decrease order, if price then use cloid else use id
                    bool isCloid;
                    if (param1 != 0) { // if price is provided, id is used not cloid
                        cloid = actions[offset].param3 & 0x1FFFFFFFFFF; // id is a uint41
                    }
                    else {
                        isCloid = true;
                    }
                    (param1, param2, isBuy) = _decreaseOrder(param1, cloid, param2, userId);
                    if (isCloid) {
                        cloid = (cloid << 41) | userId; // differentiate emitted cloid
                    }
                    if (param2 != 0) {
                        if ((param2 >> 128) == 0) { // cancel
                            isBuy ? quoteAssetDebt -= int256(param2 & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) : baseAssetDebt -= int256(param2 & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
                            assembly {
                                let length := mload(0xc0)
                                mstore(add(length, 0xe0), or(mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(isBuy)),or(shl(168,param1),or(shl(112,cloid),and(112,param2))))) // 8 flag 80 price 56 id 112 cancel size
                                mstore(0xc0, add(length, 0x20))
                                mstore(0x40, add(length, 0x100))
                            }
                        }
                        else {
                            isBuy ? quoteAssetDebt -= int256(param2 >> 128) : baseAssetDebt -= int256(param2 >> 128);
                            assembly {
                                let length := mload(0xc0)
                                mstore(add(length, 0xe0), or(add(0x4000000000000000000000000000000000000000000000000000000000000000,mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(isBuy))),or(shl(168,param1),or(shl(112,cloid),shr(128, param2))))) // 8 flag 80 price 56 id 112 decrease size not remaining size
                                mstore(0xc0, add(length, 0x20))
                                mstore(0x40, add(length, 0x100))
                            }
                        }
                    }
                    else {
                        if (actions[offset].isRequireSuccess) {
                            revert ActionFailed();
                        }
                    }
                }
                ++offset;
            }
            param1 = options; // avoid std
            param2 = options; // avoid std
            _settleBalances(caller, quoteAssetDebt, baseAssetDebt, userId, balanceMode, ((param1 >> 44) & 0xF), ((param2 >> 48) & 0xF));
            address _market = market;
            assembly {
                let length := mload(0xc0)
                if gt(length, 0) {
                    mstore(0xa0, 0x20)
                    log3(0xa0, add(length, 0x40), 0xcd726e874e479599fa8abfd7a4ad443b08415d78fb36a088cd0e9c88b249ba66, _market, userId)
                }
            }
        }
    }
    // done except replace if needed, add bribe endpoint in parent, userid is prevalidated, do margin in balance mode param
    fallback() external payable {
        unchecked {
            uint256 userId;
            uint256 offset;
            uint256 action;
            uint256 param1;
            uint256 param2;
            uint256 cloid;
            bool isBuy;
            uint256 balanceMode;
            int256 quoteAssetDebt;
            int256 baseAssetDebt;
            assembly {
                mstore(0x40, 0xe0)
                userId := calldataload(offset)
                balanceMode := shr(44, userId)
                userId := and(0x1FFFFFFFFFF, userId) // it's a uint41 but encoded like a uint44
            }
            offset += 32;
            while (offset < msg.data.length) {
                assembly { // 4-8 is isRequireSuccess
                    action := calldataload(offset)
                    param1 := and(0xFFFFFFFFFFFFFFFFFFFF, shr(112, action)) // 64-144
                    param2 := and(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF, action) // 144-256
                    cloid := and(0x3FF, shr(192, action)) // 20-64
                    action := shr(252, action) // 0-4
                }
                if (action == 1) { // cancel, pass either price and id or cloid
                    if (cloid != 0) {
                        (param1, action, isBuy) = _cancelOrder(0, cloid, userId);
                        param2 = (cloid << 41) | userId; // differentiate emitted cloid
                    }
                    else {
                        (param1, action, isBuy) = _cancelOrder(param1, param2, userId);
                    }
                    if (action != 0) {
                        isBuy ? quoteAssetDebt -= int256(action) : baseAssetDebt -= int256(action);
                        assembly {
                            let length := mload(0xc0)
                            mstore(add(length, 0xe0), or(mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(isBuy)),or(shl(168,param1),or(shl(112,param2),action)))) // 8 flag 80 price 56 id 112 size
                            mstore(0xc0, add(length, 0x20))
                            mstore(0x40, add(length, 0x100))
                        }
                    }
                    else {
                        assembly { // reuse isBuy as isRequireSuccess
                            isBuy := and(0x1, shr(248, calldataload(offset))) // 4-8
                        }
                        if (isBuy) {
                            revert ActionFailed();
                        }
                    }
                }
                else if (action == 2) { // limit buy, pass price size and optional cloid
                    (action, param2) = _limitOrder(true, balanceMode == 0, param1, param2, userId, cloid);
                    if (action != 0) {
                        quoteAssetDebt += int256(action);
                        assembly {
                            let length := mload(0xc0)
                            mstore(add(length, 0xe0), or(0x2000000000000000000000000000000000000000000000000000000000000000,or(shl(168,param1),or(shl(112,param2),action)))) // 8 flag 80 price 56 id 112 size
                            mstore(0xc0, add(length, 0x20))
                            mstore(0x40, add(length, 0x100))
                        }
                    }
                    else {
                        assembly { // reuse isBuy as isRequireSuccess
                            isBuy := and(0x1, shr(248, calldataload(offset))) // 4-8
                        }
                        if (isBuy) {
                            revert ActionFailed();
                        }
                    }
                }
                else if (action == 3) { // limit sell
                    (action, param2) = _limitOrder(false, balanceMode == 0, param1, param2, userId, cloid);
                    if (action != 0) {
                        baseAssetDebt += int256(action);
                        assembly {
                            let length := mload(0xc0)
                            mstore(add(length, 0xe0), or(0x3000000000000000000000000000000000000000000000000000000000000000, or(shl(168,param1),or(shl(112,param2),action)))) // 8 flag 80 price 56 id 112 size
                            mstore(0xc0, add(length, 0x20))
                            mstore(0x40, add(length, 0x100))
                        }
                    }
                    else {
                        assembly { // reuse isBuy as isRequireSuccess
                            isBuy := and(0x1, shr(248, calldataload(offset))) // 4-8
                        }
                        if (isBuy) {
                            revert ActionFailed();
                        }
                    }
                }
                else if (action == 4) { // mtl buy
                    uint256 settlementDelta;
                    ( , action, , settlementDelta) = _marketOrder(param2, (uint160(msg.sender) << 80) | param1, (2 << 252) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    quoteAssetDebt += int256(settlementDelta >> 128);
                    baseAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 5) { // mtl sell
                    uint256 settlementDelta;
                    ( , action, , settlementDelta) = _marketOrder(param2, (uint160(msg.sender) << 80) | param1, (2 << 252) | (1 << 244) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    baseAssetDebt += int256(settlementDelta >> 128);
                    quoteAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 6) { // partialfill buy
                    uint256 settlementDelta;
                    ( , action, , settlementDelta) = _marketOrder(param2, (uint160(msg.sender) << 80) | param1, (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    quoteAssetDebt += int256(settlementDelta >> 128);
                    baseAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 7) { // partialfill sell
                    uint256 settlementDelta;
                    ( , action, , settlementDelta) = _marketOrder(param2, (uint160(msg.sender) << 80) | param1, (1 << 244) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    baseAssetDebt += int256(settlementDelta >> 128);
                    quoteAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 8) { // partial buy terminate when low on remaining gas
                    uint256 settlementDelta;
                    ( , action, , settlementDelta) = _marketOrder(param2, (uint160(msg.sender) << 80) | param1, (3 << 252) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    quoteAssetDebt += int256(settlementDelta >> 128);
                    baseAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 9) { // partial sell terminate when low on remaining gas
                    uint256 settlementDelta;
                    ( , action, , settlementDelta) = _marketOrder(param2, (uint160(msg.sender) << 80) | param1, (3 << 252) | (1 << 244) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    baseAssetDebt += int256(settlementDelta >> 128);
                    quoteAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 10) { // complete fill buy
                    uint256 settlementDelta;
                    ( , action, , settlementDelta) = _marketOrder(param2, (uint160(msg.sender) << 80) | param1, (1 << 252) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    quoteAssetDebt += int256(settlementDelta >> 128);
                    baseAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 11) { // complete fill sell
                    uint256 settlementDelta;
                    ( , action, , settlementDelta) = _marketOrder(param2, (uint160(msg.sender) << 80) | param1, (1 << 252) | (1 << 244) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    baseAssetDebt += int256(settlementDelta >> 128);
                    quoteAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 12) { // decrease order, if price then use cloid else use id
                    bool isCloid;
                    if (param1 != 0) { // if price is provided, id is used not cloid
                        assembly {
                            cloid := and(0x1FFFFFFFFFF, shr(192, calldataload(offset))) // id is a uint41, 16-64
                        }
                    }
                    else {
                        isCloid = true;
                    }
                    (param1, param2, isBuy) = _decreaseOrder(param1, cloid, param2, userId);
                    if (isCloid) {
                        cloid = (cloid << 41) | userId; // differentiate emitted cloid
                    }
                    if (param2 != 0) {
                        if ((param2 >> 128) == 0) { // cancel
                            isBuy ? quoteAssetDebt -= int256(param2 & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) : baseAssetDebt -= int256(param2 & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
                            assembly {
                                let length := mload(0xc0)
                                mstore(add(length, 0xe0), or(mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(isBuy)),or(shl(168,param1),or(shl(112,cloid),and(112,param2))))) // 8 flag 80 price 56 id 112 cancel size
                                mstore(0xc0, add(length, 0x20))
                                mstore(0x40, add(length, 0x100))
                            }
                        }
                        else {
                            isBuy ? quoteAssetDebt -= int256(param2 >> 128) : baseAssetDebt -= int256(param2 >> 128);
                            assembly {
                                let length := mload(0xc0)
                                mstore(add(length, 0xe0), or(add(0x4000000000000000000000000000000000000000000000000000000000000000,mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(isBuy))),or(shl(168,param1),or(shl(112,cloid),shr(128, param2))))) // 8 flag 80 price 56 id 112 decrease size not remaining size
                                mstore(0xc0, add(length, 0x20))
                                mstore(0x40, add(length, 0x100))
                            }
                        }
                    }
                    else {
                        assembly { // reuse isBuy as isRequireSuccess
                            isBuy := and(0x1, shr(248, calldataload(offset))) // 4-8
                        }
                        if (isBuy) {
                            revert ActionFailed();
                        }
                    }
                }
                offset += 32;
            }
            _settleBalances(msg.sender, quoteAssetDebt, baseAssetDebt, userId, balanceMode, 0, 0);
            address _market = market;
            assembly {
                let length := mload(0xc0)
                if gt(length, 0) {
                    mstore(0xa0, 0x20)
                    log3(0xa0, add(length, 0x40), 0xcd726e874e479599fa8abfd7a4ad443b08415d78fb36a088cd0e9c88b249ba66, _market, userId)
                }
            }
        }
    }
}

contract CrystalMarket2 { // support for margin, doesn't have to be enabled, dynamic tick size with amm, delayed deployment + creator fee
    struct PriceLevel { 
        uint256 size; // uint112 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF
        // gap uint1 0x1
        uint256 latestNativeId; // uint41 0x1FFFFFFFFFF
        uint256 latest; // uint51 0x7FFFFFFFFFFFF
        uint256 fillNext; // uint51 0x7FFFFFFFFFFFF
    }

    struct InternalOrder { //  bit is if maker wants internal balance (1) or tokens (0) order is stored at either marketid << 128 | price << 48 | id or cloid << 41 | userid; no collision because marketid seperates cloid orders from non cloid, userid prevents cloid collisions, and price n id are always unique
        uint256 size; //uint112 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF
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

    struct Action {
        bool isRequireSuccess;
        uint256 action;
        uint256 param1; // price
        uint256 param2; // size/id
        uint256 param3; // cloid
    }

    address feeRecipient; // public is useless so everything isn't
    uint8 feeCommission;
    uint8 feeRebate;

    mapping (uint256 => address) userIdToAddress; // 0 is an invalid userid
    mapping (address => uint256) addressToUserId;
    mapping (address => Market) _getMarket;
    mapping (uint256 => uint256) activated; // marketid << 128 | slotindex
    mapping (uint256 => uint256) priceLevels; // 0 is an invalid price marketid << 128 | price
    mapping (uint256 => uint256) orders; // 0 is an invalid cloid, valid range 1-1023 mask 0x3FF; marketid << 128 | price << 48 | id or userid << 41 | cloid
    mapping (uint256 => uint256) cloidVerify; // two cloids per slot map market and price, never zero slot 1 << 255 | marketId << 208 | price << 128 | marketId << 80 | price
    mapping (uint256 => mapping (address => uint256)) tokenBalances;
    mapping (address => mapping (address => uint256)) claimableRewards;

    address public immutable quoteAsset;
    address public immutable baseAsset;
    address public immutable crystal;
    uint256 public immutable scaleFactor;
    uint256 public immutable tickSize;
    uint256 public immutable maxPrice;
    address private immutable market; // address of market even when delegate called
    uint256 private immutable marketId; // 0 is an invalid marketid, is already << 128

    event Trade(address indexed market, uint256 indexed userId, address indexed user, bool isBuy, uint256 amountIn, uint256 amountOut, uint256 startPrice, uint256 endPrice);
    event OrdersUpdated(address indexed market, uint256 indexed userId, bytes orderData);
    event OrderFilled(address indexed market, uint256 indexed userId, uint256 fillInfo, uint256 fillAmount) anonymous; // fillinfo is isSell << 252 | price << 168 | id << 112 | remaining size

    error SlippageExceeded();
    error ActionFailed();

    string public constant name = 'Crystal V2';
    string public constant symbol = 'CRY-V2';
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    bytes32 public DOMAIN_SEPARATOR;
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint256) public nonces;

    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Mint(address indexed market, address indexed sender, uint amountQuote, uint amountBase);
    event Burn(address indexed market, address indexed sender, uint amountQuote, uint amountBase, address indexed to);
    event Sync(address indexed market, uint112 reserve0, uint112 reserve1);

    constructor() {
        (quoteAsset, baseAsset, marketId, scaleFactor, tickSize, maxPrice) = ICrystal(msg.sender).parameters();
        marketId <<= 128;
        scaleFactor = 10 ** scaleFactor;
        market = address(this);
        crystal = msg.sender;
        require(quoteAsset != address(0) && baseAsset != address(0) && quoteAsset != baseAsset && maxPrice <= 0xFFFFFFFFFFFFFFFFFFFF && tickSize <= 0xFFFFFFFFFFFFFFFFFFFF && scaleFactor <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes(name)),
                keccak256(bytes('1')),
                chainId,
                address(this)
            )
        );
    }

    function _mint(address to, uint256 value) internal {
        totalSupply += value;
        balanceOf[to] += value;
        emit Transfer(address(0), to, value);
    }

    function _burn(address from, uint256 value) internal {
        balanceOf[from] -= value;
        totalSupply -= value;
        emit Transfer(from, address(0), value);
    }

    function _approve(address owner, address spender, uint256 value) internal {
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _transfer(address from, address to, uint256 value) internal {
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
    }

    function mint(address to, uint256 value) external {
        require(msg.sender == crystal);
        _mint(to, value);
    }

    function burn(address from, uint256 value) external {
        require(msg.sender == crystal);
        _burn(from, value);
    }

    function approve(address spender, uint256 value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max && to != crystal) {
            allowance[from][msg.sender] -= value;
        }
        _transfer(from, to, value);
        return true;
    }

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(deadline >= block.timestamp, 'UniswapV2: EXPIRED');
        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01',
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, 'UniswapV2: INVALID_SIGNATURE');
        _approve(owner, spender, value);
    }

    function getReserves() external payable returns (uint112 reserveQuote, uint112 reserveBase) {
        Market storage m = _getMarket[market];
        (reserveQuote, reserveBase) = (m.reserveQuote, m.reserveBase);
    }
    
    function premint(address to, uint256 amountQuoteDesired, uint256 amountBaseDesired) external payable returns (uint256 liquidity) {
        Market storage m = _getMarket[market];
        liquidity = _sqrt(amountQuoteDesired * (amountBaseDesired)) - 1000;
        require(IERC20(market).totalSupply() == 0 && liquidity != 0 && amountQuoteDesired <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF && amountBaseDesired <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
        IERC20(market).mint(address(0), 1000); // permanently lock the first MINIMUM_LIQUIDITY tokens
        IERC20(market).mint(to, liquidity);

        (m.reserveQuote, m.reserveBase) = (uint112(amountQuoteDesired), uint112(amountBaseDesired));
    }

    function addLiquidity(address to, uint256 amountQuoteDesired, uint256 amountBaseDesired, uint256 amountQuoteMin, uint256 amountBaseMin, uint256 options, address caller) external payable returns (uint256 liquidity) {
        Market storage m = _getMarket[market];
        (uint112 reserveQuote, uint112 reserveBase) = (m.reserveQuote, m.reserveBase);
        uint256 amountQuote;
        uint256 amountBase;
        uint256 _totalSupply = IERC20(market).totalSupply(); // gas savings, must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {
            amountQuote = amountQuoteDesired;
            amountBase = amountBaseDesired;
            liquidity = _sqrt(amountQuote * (amountBase)) - (1000);
            IERC20(market).mint(address(0), 1000); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            uint256 amountBaseOptimal = (amountQuoteDesired * reserveBase) / reserveQuote;
            if (amountBaseOptimal <= amountBaseDesired) {
                amountQuote = amountQuoteDesired;
                amountBase = amountBaseOptimal;
            } else {
                uint256 amountQuoteOptimal = (amountBaseDesired * reserveQuote) / reserveBase;
                require(amountQuoteOptimal <= amountQuoteDesired);
                amountQuote = amountQuoteOptimal;
                amountBase = amountBaseDesired;
            }
            liquidity = amountQuote * (_totalSupply) / reserveQuote < amountBase * (_totalSupply) / reserveBase ? amountQuote * (_totalSupply) / reserveQuote : amountBase * (_totalSupply) / reserveBase;
        }
        reserveQuote += uint112(amountQuote);
        reserveBase += uint112(amountBase);
        if ((options & 0xF) == 0) {
            IERC20(quoteAsset).transferFrom(caller, address(this), amountQuote);
        }
        else {
            tokenBalances[0][quoteAsset] -= amountQuote; // checked
        }
        if ((options >> 4 & 0xF) == 0) {
            IERC20(baseAsset).transferFrom(caller, address(this), amountBase);
        }
        else {
            tokenBalances[0][baseAsset] -= amountBase; // checked
        }
        IERC20(market).mint(to, liquidity);
        require(liquidity != 0 && amountQuote >= amountQuoteMin && amountBase >= amountBaseMin && reserveQuote <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF && reserveBase <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF && m.isAMMEnabled == true);

        (m.reserveQuote, m.reserveBase) = (reserveQuote, reserveBase);
        emit Sync(market, reserveQuote, reserveBase);
        emit Mint(market, caller, amountQuote, amountBase);
    }

    function removeLiquidity(address to, uint256 liquidity, uint256 amountQuoteMin, uint256 amountBaseMin, uint256 options, address caller) external payable returns (uint256 amountQuote, uint256 amountBase) {
        Market storage m = _getMarket[market];
        (uint112 reserveQuote, uint112 reserveBase) = (m.reserveQuote, m.reserveBase);
        IERC20(market).transferFrom(caller, address(this), liquidity);

        uint256 _totalSupply = IERC20(market).totalSupply(); // gas savings, must be defined here since totalSupply can update in _mintFee
        amountQuote = liquidity * (reserveQuote) / _totalSupply; // using balances ensures pro-rata distribution
        amountBase = liquidity * (reserveBase) / _totalSupply; // using balances ensures pro-rata distribution
        IERC20(market).burn(address(this), liquidity);
        if ((options & 0xF) == 0) {
            IERC20(quoteAsset).transfer(to, amountQuote);
        }
        else {
            tokenBalances[0][quoteAsset] += amountQuote;
        }
        if ((options >> 4 & 0xF) == 0) {
            IERC20(baseAsset).transfer(to, amountBase);
        }
        else {
            tokenBalances[0][baseAsset] += amountBase;
        }
        reserveQuote -= uint112(amountQuote); // checked
        reserveBase -= uint112(amountBase); // checked

        require(amountQuote != 0 && amountBase != 0 && amountQuote >= amountQuoteMin && amountBase >= amountBaseMin && reserveQuote <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF && reserveBase <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
        (m.reserveQuote, m.reserveBase) = (reserveQuote, reserveBase);
        emit Sync(market, reserveQuote, reserveBase);
        emit Burn(market, caller, amountQuote, amountBase, to);
    }

    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        unchecked {
            if (y > 3) {
                z = y;
                uint x = (y >> 1) + 1;
                while (x < z) {
                    z = x;
                    x = (y / x + x) >> 1;
                }
            } else if (y != 0) {
                z = 1;
            }
        }
    }

    function _tickToPrice(uint256 t) internal view returns (uint256) {
        unchecked {
            if (t <= 100_000) return t * tickSize;
            uint256 x = t - 10_000;
            return 10 ** (x / 90_000) * (10_000 + (x % 90_000)) * tickSize;
        }
    }

    function _priceToTick(uint256 p) internal view returns (uint256) {
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

    function _searchSlotUp(uint256 slot, uint256 tick) internal pure returns (uint256) {
        if (slot & ((1 << 128) - 1) == 0) {slot >>= 128; tick += 128;}
        if (slot & ((1 << 64) - 1) == 0) {slot >>= 64; tick += 64;}
        if (slot & ((1 << 32) - 1) == 0) {slot >>= 32; tick += 32;}
        if (slot & ((1 << 16) - 1) == 0) {slot >>= 16; tick += 16;}
        if (slot & ((1 << 8) - 1) == 0) {slot >>= 8; tick += 8;}
        if (slot & ((1 << 4) - 1) == 0) {slot >>= 4; tick += 4;}
        if (slot & ((1 << 2) - 1) == 0) {slot >>= 2; tick += 2;}
        if (slot & 1 == 0) {++tick;}
        return tick;
    }

    function _searchSlotDown(uint256 slot, uint256 tick) internal pure returns (uint256) {
        if (slot >= 2 ** 128) {slot >>= 128; tick += 128;}
        if (slot >= 2 ** 64) {slot >>= 64; tick += 64;}
        if (slot >= 2 ** 32) {slot >>= 32; tick += 32;}
        if (slot >= 2 ** 16) {slot >>= 16; tick += 16;}
        if (slot >= 2 ** 8) {slot >>= 8; tick += 8;}
        if (slot >= 2 ** 4) {slot >>= 4; tick += 4;}
        if (slot >= 2 ** 2) {slot >>= 2; tick += 2;}
        if (slot >= 2 ** 1) {++tick;}
        return tick;
    }

    function _settleBalances(address caller, int256 quoteAssetDebt, int256 baseAssetDebt, uint256 userId, uint256 balanceMode, uint256 balanceModeOut, uint256 balanceModeIn) internal {
        if (balanceMode == 0) { // external txfers
            if (balanceModeIn != 0) {
                if (quoteAssetDebt > 0) {
                    uint256 balance = tokenBalances[0][quoteAsset];
                    if (uint128(balance) < uint256(quoteAssetDebt)) {
                        revert ActionFailed();
                    }
                    else {
                        tokenBalances[0][quoteAsset] = balance - uint256(quoteAssetDebt);
                    }
                }
                if (baseAssetDebt > 0) {
                    uint256 balance = tokenBalances[0][baseAsset];
                    if (uint128(balance) < uint256(baseAssetDebt)) {
                        revert ActionFailed();
                    }
                    else {
                        tokenBalances[0][baseAsset] = balance - uint256(baseAssetDebt);
                    }
                }
            }
            else {
                if (quoteAssetDebt > 0) {
                    IERC20(quoteAsset).transferFrom(caller, address(this), uint256(quoteAssetDebt));
                }
                if (baseAssetDebt > 0) {
                    IERC20(baseAsset).transferFrom(caller, address(this), uint256(baseAssetDebt));
                }
            }
            if (balanceModeOut != 0) {
                if (quoteAssetDebt < 0) {
                    tokenBalances[0][quoteAsset] += uint256(-quoteAssetDebt);
                }
                if (baseAssetDebt < 0) {
                    tokenBalances[0][baseAsset] += uint256(-baseAssetDebt);
                }
            }
            else {
                if (quoteAssetDebt < 0) {
                    IERC20(quoteAsset).transfer(caller, uint256(-quoteAssetDebt));
                }
                if (baseAssetDebt < 0) {
                    IERC20(baseAsset).transfer(caller, uint256(-baseAssetDebt));
                }
            }
        }
        else {
            if (balanceMode == 1) { // internal balances
                if (quoteAssetDebt > 0) {
                    uint256 balance = tokenBalances[userId][quoteAsset];
                    if (uint128(balance) < uint256(quoteAssetDebt)) {
                        revert ActionFailed();
                    }
                    else {
                        tokenBalances[userId][quoteAsset] = balance - uint256(quoteAssetDebt);
                    }
                }
                else if (quoteAssetDebt < 0) {
                    tokenBalances[userId][quoteAsset] += uint256(-quoteAssetDebt);
                }
                if (baseAssetDebt > 0) {
                    uint256 balance = tokenBalances[userId][baseAsset];
                    if (uint128(balance) < uint256(baseAssetDebt)) {
                        revert ActionFailed();
                    }
                    else {
                        tokenBalances[userId][baseAsset] = balance - uint256(baseAssetDebt);
                    }
                }
                else if (baseAssetDebt < 0) {
                    tokenBalances[userId][baseAsset] += uint256(-baseAssetDebt);
                }
            }
            else {
                revert ActionFailed();
            }
        }
    }

    function _internalCancel(uint256 price, uint256 id, uint256 size, uint256 _highestBid, uint256 _lowestAsk, uint256 _order) internal {
        uint256 _priceLevel = priceLevels[marketId | price];
        _priceLevel -= size; // can't overflow
        if (id == (_priceLevel >> 205 & 0x7FFFFFFFFFFFF)) { // if pricelevel fillnext then set to fillafter
            _priceLevel = (_order & (0x7FFFFFFFFFFFF << 205)) | (_priceLevel & 0x0000000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
        }
        else if (id == (_priceLevel >> 154 & 0x7FFFFFFFFFFFF)) { // if pricelevel latest then set latest to fillbefore
            uint256 temp = ((((_order >> 154) & 0x7FFFFFFFFFFFF) > 0x1FFFFFFFFFF) ? ((_order >> 154) & 0x7FFFFFFFFFFFF) : marketId | (price << 48) | ((_order >> 154) & 0x7FFFFFFFFFFFF));
            orders[temp] = orders[temp] & 0x0000000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF | (_order & (0x7FFFFFFFFFFFF << 205)); // set fillbefores fillafter to fillafter
            _priceLevel = (_priceLevel & 0xFFFFFFFFFFFFE0000000000003FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) | (_order & (0x7FFFFFFFFFFFF << 154));
        }
        else {           
            uint256 temp = (((_order >> 154) & 0x7FFFFFFFFFFFF > 0x1FFFFFFFFFF) ? (_order >> 154) & 0x7FFFFFFFFFFFF : marketId | (price << 48) | (_order >> 154) & 0x7FFFFFFFFFFFF);
            orders[temp] = orders[temp] & 0x0000000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF | (_order & (0x7FFFFFFFFFFFF << 205)); // set fillbefores fillafter to fillafter
            temp = ((((_order >> 205) & 0x7FFFFFFFFFFFF) > 0x1FFFFFFFFFF) ? ((_order >> 205) & 0x7FFFFFFFFFFFF) : marketId | (price << 48) | ((_order >> 205) & 0x7FFFFFFFFFFFF));
            orders[temp] = orders[temp] & 0xFFFFFFFFFFFFE0000000000003FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF | (_order & (0x7FFFFFFFFFFFF << 154)); // setfillafters fillbefore to fillbefore
        }
        priceLevels[marketId | price] = _priceLevel;
        if ((_priceLevel & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) == 0) {
            uint256 tick = _priceToTick(price);
            uint256 slotIndex = tick >> 8;
            uint256 _slot = activated[marketId | slotIndex];
            _slot &= ~(1 << (tick % 256));
            activated[marketId | slotIndex] = _slot;
            if (price == _lowestAsk) {
                _slot = _slot >> tick % 256;
                while (_slot == 0) {
                    ++slotIndex;
                    _slot = activated[marketId | slotIndex];
                    tick = slotIndex << 8;
                }
                tick = _searchSlotUp(_slot, tick);
                _getMarket[market].lowestAsk = uint80(_tickToPrice(tick));
            }
            else if (price == _highestBid) {
                _slot = _slot & ((1 << (tick % 256)) - 1);
                while (_slot == 0) {
                    --slotIndex;
                    _slot = activated[marketId | slotIndex];
                }
                tick = _searchSlotDown(_slot, slotIndex << 8);
                _getMarket[market].highestBid = uint80(_tickToPrice(tick));
            }
        }
    }
    // max is in buckets
    function _getPriceLevels(bool isAscending, uint256 startPrice, uint256 distance, uint256 interval, uint256 max) internal view {
        unchecked {
            uint256 _maxPrice = maxPrice;
            if (startPrice >= _maxPrice) {
                return;
            }
            uint256 _marketId = marketId;
            uint256 tick = _priceToTick(startPrice);
            startPrice = tick; // turn startprice into starttick
            if (!isAscending) {
                ++tick;
            }
            uint256 count;
            uint256 price;
            uint256 position;
            uint256 bucket = type(uint256).max;
            uint256 slotIndex = tick >> 8;
            uint256 slot = activated[marketId | slotIndex];
            assembly {
                position := mload(0x40)
                mstore(position, 0x0)
            }
            if (isAscending) {
                if (startPrice + (distance) > _priceToTick(_maxPrice)) {
                    distance = (_priceToTick(_maxPrice) - startPrice);
                }
                while (true) {
                    uint256 _slot = slot >> tick % 256;
                    while (_slot == 0) {
                        ++slotIndex;
                        slot = activated[marketId | slotIndex];
                        _slot = slot;
                        tick = slotIndex << 8;
                    }
                    tick = _searchSlotUp(_slot, tick);
                    slot &= ~(1 << (tick % 256));
                    price = _tickToPrice(tick);
                    if ((price / interval * interval) == bucket) {
                        assembly {
                            mstore(0x00, or(_marketId, price))
                            mstore(0x20, priceLevels.slot)
                            let length := mload(position)
                            let existing := mload(add(length, position))
                            mstore(add(length, position), add(existing, and(sload(keccak256(0x00, 0x40)), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF)))
                        }
                    }
                    else {
                        ++count;
                        if (count > max && max != 0 || (tick >= startPrice + distance)) {
                            break;
                        }
                        bucket = price / interval * interval;
                        assembly {
                            mstore(0x00, or(_marketId, price))
                            mstore(0x20, priceLevels.slot)
                            let length := mload(position)
                            mstore(add(length, add(position, 0x20)), or(shl(128, bucket), and(sload(keccak256(0x00, 0x40)), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF)))
                            mstore(position, add(length, 0x20))
                        }
                    }
                }
            }
            else {
                if (distance > startPrice) {
                    distance = startPrice;
                }
                while (true) {
                    uint256 _slot = slot & ((1 << (tick % 256)) - 1);
                    while (_slot == 0) {
                        --slotIndex;
                        slot = activated[marketId | slotIndex];
                        _slot = slot;
                    }
                    tick = _searchSlotDown(_slot, slotIndex << 8);
                    slot &= ~(1 << (tick % 256));
                    price = _tickToPrice(tick);
                    if ((((price + interval - 1) / interval) * interval) == bucket) {
                        assembly {
                            mstore(0x00, or(_marketId, price))
                            mstore(0x20, priceLevels.slot)
                            let length := mload(position)
                            let existing := mload(add(length, position))
                            mstore(add(length, position), add(existing, and(sload(keccak256(0x00, 0x40)), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF)))
                        }
                    }
                    else {
                        ++count;
                        if (count > max && max != 0 || (tick <= startPrice - distance)) {
                            break;
                        }
                        bucket = ((price + interval - 1) / interval) * interval;
                        assembly {
                            mstore(0x00, or(_marketId, price))
                            mstore(0x20, priceLevels.slot)
                            let length := mload(position)
                            mstore(add(length, add(position, 0x20)), or(shl(128, bucket), and(sload(keccak256(0x00, 0x40)), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF)))
                            mstore(position, add(length, 0x20))
                        }
                    }
                }     
            }
        }
    }

    function getPriceLevels(bool isAscending, uint256 startPrice, uint256 distance, uint256 interval, uint256 max) external payable returns (bytes memory) {
        assembly {
            mstore(0x40, 0xa0)
        }
        _getPriceLevels(isAscending, startPrice, distance, interval, max);
        assembly {
            mstore(0x80, 0x20)
            return(0x80, add(mload(0xa0), 0x40))
        }
    }

    function getPriceLevelsFromMid(uint256 distance, uint256 interval, uint256 max) external payable returns (uint256 highestBid, uint256 lowestAsk, bytes memory, bytes memory) {
        Market storage m = _getMarket[market];
        uint256 length;
        (highestBid, lowestAsk) = (m.highestBid, m.lowestAsk);
        assembly {
            mstore(0x40, 0x100)
        }
        _getPriceLevels(false, highestBid, distance, interval, max);
        assembly {
            length := mload(0x100)
            mstore(0x40, add(length, 0x120))
        }
        _getPriceLevels(true, lowestAsk, distance, interval, max);
        assembly {
            mstore(0x80, highestBid)
            mstore(0xa0, lowestAsk)
            mstore(0xc0, 0x80)
            mstore(0xe0, add(0xa0, length))
            return(0x80, add(0xc0, add(length, mload(add(length, 0x120)))))
        }
    }
    // done
    function getPrice() external payable returns (uint256 price, uint256 highestBid, uint256 lowestAsk) {
        Market storage m = _getMarket[market];
        uint256 count;
        (highestBid, lowestAsk) = (m.highestBid, m.lowestAsk);
        price = highestBid;
        if (lowestAsk != maxPrice) {
            price += lowestAsk;
            ++count;
        }
        if (highestBid != 0) {
            ++count;
        }
        if (count == 2) {
            price = (price + 1) >> 1;
        }
    }
    // done
    function getQuote(bool isBuy, bool isExactInput, bool isCompleteFill, uint256 size, uint256 worstPrice) external payable returns (uint256 amountIn, uint256 amountOut) {
        unchecked {
            Market storage m = _getMarket[market];
            uint256 price;
            (uint256 reserveQuote, uint256 reserveBase) = m.isAMMEnabled ? (m.reserveQuote, m.reserveBase) : (0, 0);
            if (isBuy) {
                if (isExactInput) { // orderInfo is 256-252 ordertype 252-248 !isExactInput 248-244 !isBuy 244-240 STP 240-236 !useexternalbalance 236-232 !fromcaller
                    size = (size * m.takerFee) / 100000;
                }
                uint256 _maxPrice = maxPrice;
                if (worstPrice >= _maxPrice) {
                    worstPrice = _maxPrice - 1;
                }
                price = m.lowestAsk;
            }
            else {
                if (!isExactInput) {
                    size = (size * 100000 + m.takerFee - 1) / m.takerFee;
                }
                if (worstPrice == 0) {
                    worstPrice = 1;
                }
                price = m.highestBid;
            }
            uint256 tick = _priceToTick(price);
            uint256 slot = activated[marketId | (tick >> 8)];
            while (isExactInput ? size > amountIn : size > amountOut) {
                uint256 sizeLeft = isExactInput ? (size - amountIn) : (size - amountOut);
                if (reserveQuote != 0 && reserveBase != 0) {
                    if (isBuy && ((reserveQuote * scaleFactor * 10000) / (reserveBase * 9975)) < (price * 100000 / m.makerRebate)) {
                        if (isExactInput) {
                            uint256 temp1 = reserveQuote * 10000;
                            uint256 _amountIn = _sqrt(temp1 * reserveBase / scaleFactor * price / 9975) - (temp1 / 9975);
                            if (sizeLeft > _amountIn) {
                                uint256 temp2 = _amountIn * 9975;
                                uint256 _amountOut = (temp2 * reserveBase) / (temp1 + temp2);
                                reserveQuote += _amountIn;
                                reserveBase -= _amountOut;
                                amountIn += _amountIn;
                                amountOut += _amountOut;
                                sizeLeft -= _amountIn;
                            }
                            else {
                                uint256 temp2 = sizeLeft * 9975;
                                uint256 _amountOut = (temp2 * reserveBase) / (temp1 + temp2);
                                reserveQuote += sizeLeft;
                                reserveBase -= _amountOut;
                                amountIn += sizeLeft;
                                amountOut += _amountOut;
                                break;
                            }
                        }
                        else {
                            uint256 temp1 = reserveQuote * 10000;
                            uint256 _amountOut = reserveBase - _sqrt(temp1 * reserveQuote / price * scaleFactor / 9975);
                            if (sizeLeft > _amountOut) {
                                uint256 _amountIn = (_amountOut * temp1) / ((reserveBase - _amountOut) * 9975) + 1;
                                reserveQuote += _amountIn;
                                reserveBase -= _amountOut;
                                amountIn += _amountIn;
                                amountOut += _amountOut;
                                sizeLeft -= _amountOut;
                            }
                            else {
                                uint256 _amountIn = (sizeLeft * temp1) / ((reserveBase - sizeLeft) * 9975) + 1;
                                reserveQuote += _amountIn;
                                reserveBase -= sizeLeft;
                                amountIn += _amountIn;
                                amountOut += sizeLeft;
                                break;
                            }
                        }
                    }
                    else if (!isBuy && ((reserveQuote * scaleFactor * 10000) / (reserveBase * 9975)) > (price * m.makerRebate / 100000)) {
                        if (isExactInput) {
                            uint256 temp1 = reserveBase * 10000;
                            uint256 _amountIn = _sqrt(temp1 * reserveQuote / (price < worstPrice ? worstPrice : price) * scaleFactor / 9975) - (temp1 / 9975);
                            if (sizeLeft > _amountIn) {
                                uint256 temp2 = _amountIn * 9975;
                                uint256 _amountOut = (temp2 * reserveQuote) / (temp1 + temp2);
                                reserveBase += _amountIn;
                                reserveQuote -= _amountOut;
                                amountIn += _amountIn;
                                amountOut += _amountOut;
                                sizeLeft -= _amountIn;
                            }
                            else {
                                uint256 temp2 = sizeLeft * 9975;
                                uint256 _amountOut = (temp2 * reserveQuote) / (temp1 + temp2);
                                reserveBase += sizeLeft;
                                reserveQuote -= _amountOut;
                                amountIn += sizeLeft;
                                amountOut += _amountOut;
                                break;
                            }
                        }
                        else {
                            uint256 temp1 = reserveBase * 10000;
                            uint256 _amountOut = reserveQuote - _sqrt(temp1 * reserveQuote / scaleFactor * (price < worstPrice ? worstPrice : price) / 9975);
                            if (sizeLeft > _amountOut) {
                                uint256 _amountIn = (_amountOut * temp1) / ((reserveQuote - _amountOut) * 9975) + 1;
                                reserveBase += _amountIn;
                                reserveQuote -= _amountOut;
                                amountIn += _amountIn;
                                amountOut += _amountOut;
                                sizeLeft -= _amountOut;
                            }
                            else {
                                uint256 _amountIn = (sizeLeft * temp1) / ((reserveQuote - sizeLeft) * 9975) + 1;
                                reserveBase += _amountIn;
                                reserveQuote -= sizeLeft;
                                amountIn += _amountIn;
                                amountOut += sizeLeft;
                                break;
                            }
                        }
                    }
                }
                if (isBuy ? price > worstPrice : price < worstPrice) {
                    if (isCompleteFill) {
                        revert SlippageExceeded();
                    }
                    else {
                        break;
                    }
                }
                uint256 liquidity = priceLevels[marketId | price] & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
                if (isExactInput ? (isBuy ? (liquidity > (sizeLeft * m.makerRebate / 100000) * scaleFactor / price) : (liquidity > (sizeLeft * m.makerRebate / 100000) * price / scaleFactor)) : (liquidity > sizeLeft)) {
                    amountOut += (isExactInput ? (isBuy ? (sizeLeft * m.makerRebate / 100000) * scaleFactor / price : (sizeLeft * m.makerRebate / 100000) * price / scaleFactor) : sizeLeft);
                    if (!isExactInput) {
                        sizeLeft = isBuy ? (sizeLeft * price + scaleFactor - 1) / scaleFactor * 100000 / m.makerRebate : (sizeLeft * scaleFactor + price - 1) / price * 100000 / m.makerRebate;
                    }
                    amountIn += sizeLeft;
                    sizeLeft = 0;
                }
                else {
                    uint256 _amountIn = (isBuy ? (((liquidity * price / scaleFactor) * 100000) / m.makerRebate) : (((liquidity * scaleFactor / price) * 100000) / m.makerRebate));
                    amountIn += _amountIn;
                    amountOut += isBuy ? liquidity : liquidity;
                    sizeLeft -= isExactInput ? _amountIn : liquidity;
                    liquidity = 0;
                }
                if (liquidity == 0) {
                    slot &= ~(1 << (tick % 256));
                    uint256 slotIndex = tick >> 8;
                    if (isBuy) {
                        uint256 _slot = slot >> tick % 256;
                        while (_slot == 0) {
                            ++slotIndex;
                            slot = activated[marketId | slotIndex];
                            _slot = slot;
                            tick = slotIndex << 8;
                        }
                        tick = _searchSlotUp(_slot, tick);
                    }
                    else {
                        uint256 _slot = slot & ((1 << (tick % 256)) - 1);
                        while (_slot == 0) {
                            --slotIndex;
                            slot = activated[marketId | slotIndex];
                            _slot = slot;
                        }
                        tick = _searchSlotDown(_slot, slotIndex << 8);
                    }
                    price = _tickToPrice(tick);
                }
                else {
                    break;
                }
            }
            isBuy ? amountIn = (amountIn * 100000 + m.takerFee - 1) / m.takerFee : amountOut = amountOut * m.takerFee / 100000;
            return (amountIn, amountOut);
        }
    }
    // done
    function _marketOrder(uint256 size, uint256 priceAndReferrer, uint256 orderInfo) internal returns (uint256 amountIn, uint256 amountOut, uint256 id, uint256 settlementDelta) { // settlement delta is debit amt << 128 | credit amt, already processed
        unchecked {
            Market storage m = _getMarket[market];
            uint256 price;
            uint256 reserves =  m.isAMMEnabled ? ((uint256(m.reserveQuote) << 128) | m.reserveBase) : 0;
            if ((orderInfo >> 244 & 0xF) == 0) {
                if (((orderInfo >> 248 & 0xF) == 0)) { // orderInfo is 256-252 ordertype 252-248 !isExactInput 248-244 !isBuy 244-240 STP 240-236 !useexternalbalance 236-232 !fromcaller
                    size = (size * m.takerFee) / 100000;
                }
                uint256 _maxPrice = maxPrice;
                if ((priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFF) >= _maxPrice) {
                    priceAndReferrer = (priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000000000000000) | (_maxPrice - 1);
                }
                price = m.lowestAsk;
            }
            else {
                if (((orderInfo >> 248 & 0xF) != 0)) { // orderInfo is 256-252 ordertype 252-248 !isExactInput 248-244 !isBuy 244-240 STP 240-236 !useexternalbalance 236-232 !fromcaller
                    size = (size * 100000 + m.takerFee - 1) / m.takerFee;
                }
                if ((priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFF) == 0) {
                    ++priceAndReferrer;
                }
                price = m.highestBid;
            }
            assembly {
                mstore(0x80, shl(128, price)) // top 128 is start price bottom 128 is end price
            }
            {
                uint256 tick = _priceToTick(price);
                uint256 slot = activated[marketId | (tick >> 8)];
                while (((orderInfo >> 248 & 0xF) == 0) ? size > amountIn : size > amountOut) {
                    uint256 sizeLeft = ((orderInfo >> 248 & 0xF) == 0) ? size - amountIn : size - amountOut;
                    {
                        (uint256 reserveQuote, uint256 reserveBase) = (reserves >> 128, reserves & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
                        if (reserveQuote != 0 && reserveBase != 0) {
                            if (((orderInfo >> 244 & 0xF) == 0) && ((reserveQuote * scaleFactor * 10000) / (reserveBase * 9975)) < (price * 100000 / m.makerRebate)) {
                                if ((orderInfo >> 248 & 0xF) == 0) {
                                    uint256 _amountOut = reserveQuote * 10000; // reuse to avoid stack too deep
                                    uint256 worstPrice = (priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFF);
                                    uint256 _amountIn = _sqrt(_amountOut * reserveBase / scaleFactor * (price > worstPrice ? worstPrice : price) / 9975) - (_amountOut / 9975);
                                    if (sizeLeft > _amountIn) {
                                        _amountOut = ((_amountIn * 9975) * reserveBase) / (_amountOut + (_amountIn * 9975));
                                        settlementDelta += _amountIn << 128;
                                        reserveQuote += _amountIn;
                                        reserveBase -= _amountOut;
                                        amountIn += _amountIn;
                                        amountOut += _amountOut;
                                        sizeLeft -= _amountIn;
                                    }
                                    else {
                                        _amountOut = ((sizeLeft * 9975) * reserveBase) / (_amountOut + (sizeLeft * 9975));
                                        settlementDelta += sizeLeft << 128;
                                        reserveQuote += sizeLeft;
                                        reserveBase -= _amountOut;
                                        amountIn += sizeLeft;
                                        amountOut += _amountOut;
                                        reserves = (reserveQuote << 128) | reserveBase;
                                        if (activated[marketId | (tick >> 8)] != slot) {
                                            activated[marketId | (tick >> 8)] = slot;
                                        }
                                        break;
                                    }
                                }
                                else {
                                    uint256 _amountIn = reserveQuote * 10000; // reuse to avoid stack too deep
                                    uint256 worstPrice = (priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFF);
                                    uint256 _amountOut = reserveBase - _sqrt(_amountIn * reserveQuote / (price > worstPrice ? worstPrice : price) * scaleFactor / 9975);
                                    if (sizeLeft > _amountOut) {
                                        _amountIn = (_amountOut * _amountIn) / ((reserveBase - _amountOut) * 9975) + 1;
                                        settlementDelta += _amountIn << 128;
                                        reserveQuote += _amountIn;
                                        reserveBase -= _amountOut;
                                        amountIn += _amountIn;
                                        amountOut += _amountOut;
                                        sizeLeft -= _amountOut;
                                    }
                                    else {
                                        _amountIn = (sizeLeft * _amountIn) / ((reserveBase - sizeLeft) * 9975) + 1;
                                        settlementDelta += _amountIn << 128;
                                        reserveQuote += _amountIn;
                                        reserveBase -= sizeLeft;
                                        amountIn += _amountIn;
                                        amountOut += sizeLeft;
                                        reserves = (reserveQuote << 128) | reserveBase;
                                        if (activated[marketId | (tick >> 8)] != slot) {
                                            activated[marketId | (tick >> 8)] = slot;
                                        }
                                        break;
                                    }
                                }
                            }
                            else if (((orderInfo >> 244 & 0xF) != 0) && ((reserveQuote * scaleFactor * 10000) / (reserveBase * 9975)) > (price * m.makerRebate / 100000)) {
                                if ((orderInfo >> 248 & 0xF) == 0) {
                                    uint256 _amountOut = reserveBase * 10000; // reuse to avoid stack too deep
                                    uint256 worstPrice = (priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFF);
                                    uint256 _amountIn = _sqrt(_amountOut * reserveQuote / (price < worstPrice ? worstPrice : price) * scaleFactor / 9975) - (_amountOut / 9975);
                                    if (sizeLeft > _amountIn) {
                                        _amountOut = ((_amountIn * 9975) * reserveQuote) / (_amountOut + (_amountIn * 9975));
                                        settlementDelta += _amountIn << 128;
                                        reserveBase += _amountIn;
                                        reserveQuote -= _amountOut;
                                        amountIn += _amountIn;
                                        amountOut += _amountOut;
                                        sizeLeft -= _amountIn;
                                    }
                                    else {
                                        _amountOut = ((sizeLeft * 9975) * reserveQuote) / (_amountOut + (sizeLeft * 9975));
                                        settlementDelta += sizeLeft << 128;
                                        reserveBase += sizeLeft;
                                        reserveQuote -= _amountOut;
                                        amountIn += sizeLeft;
                                        amountOut += _amountOut;
                                        reserves = (reserveQuote << 128) | reserveBase;
                                        if (activated[marketId | (tick >> 8)] != slot) {
                                            activated[marketId | (tick >> 8)] = slot;
                                        }
                                        break;
                                    }
                                }
                                else {
                                    uint256 _amountIn = reserveBase * 10000; // reuse to avoid stack too deep
                                    uint256 worstPrice = (priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFF);
                                    uint256 _amountOut = reserveQuote - _sqrt(_amountIn * reserveQuote / scaleFactor * (price < worstPrice ? worstPrice : price) / 9975);
                                    if (sizeLeft > _amountOut) {
                                        _amountIn = (_amountOut * _amountIn) / ((reserveQuote - _amountOut) * 9975) + 1;
                                        settlementDelta += _amountIn << 128;
                                        reserveBase += _amountIn;
                                        reserveQuote -= _amountOut;
                                        amountIn += _amountIn;
                                        amountOut += _amountOut;
                                        sizeLeft -= _amountOut;
                                    }
                                    else {
                                        _amountIn = (sizeLeft * _amountIn) / ((reserveQuote - sizeLeft) * 9975) + 1;
                                        settlementDelta += _amountIn << 128;
                                        reserveBase += _amountIn;
                                        reserveQuote -= sizeLeft;
                                        amountIn += _amountIn;
                                        amountOut += sizeLeft;
                                        reserves = (reserveQuote << 128) | reserveBase;
                                        if (activated[marketId | (tick >> 8)] != slot) {
                                            activated[marketId | (tick >> 8)] = slot;
                                        }
                                        break;
                                    }
                                }
                            }
                            reserves = (reserveQuote << 128) | reserveBase;
                        }
                    }
                    if (((orderInfo >> 244 & 0xF) == 0) ? price > (priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFF) : price < (priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFF)) {
                        if ((orderInfo >> 252) == 1) {
                            revert SlippageExceeded();
                        }
                        if (activated[marketId | (tick >> 8)] != slot) {
                            activated[marketId | (tick >> 8)] = slot;
                        }
                        if ((orderInfo >> 252) == 2) {
                            ((orderInfo >> 244 & 0xF) == 0) ? m.lowestAsk = uint80(price) : m.highestBid = uint80(price);
                            slot = ((orderInfo >> 248 & 0xF) == 0) ? (size - amountIn) : (((orderInfo >> 244 & 0xF) == 0) ? ((size - amountOut) * (priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFF) / scaleFactor) : ((size - amountOut) * scaleFactor / (priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFF)));
                            tick = orderInfo;
                            (slot, id) = _limitOrder(((tick >> 244 & 0xF) == 0), (tick >> 236 & 0x1) == 0, (priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFF), slot, (tick >> 160 & 0x1FFFFFFFFFF), (tick >> 208 & 0x3FF));
                            settlementDelta += (slot << 128);
                            if (slot != 0) { // mtl event is written to memory, emitted in parent
                                assembly {
                                    let length := mload(0xc0)
                                    mstore(add(length, add(0xc0, 0x20)), or(add(0x2000000000000000000000000000000000000000000000000000000000000000,mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(iszero(and(shr(244,orderInfo),0xF))))),or(shl(168,and(0xFFFFFFFFFFFFFFFFFFFF,priceAndReferrer)),or(shl(112,id),slot))))
                                    mstore(0xc0, add(length, 0x20))
                                    mstore(0x40, add(length, add(0xc0, 0x40)))
                                }
                            }
                        }
                        break;
                    }
                    uint256 _priceLevel = priceLevels[marketId | price];
                    {
                        uint256 next = (_priceLevel >> 205) & 0x7FFFFFFFFFFFF;
                        uint256 _orderInfo = orderInfo;
                        while ((_priceLevel & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) != 0 && sizeLeft != 0 && !((_orderInfo >> 252) == 3 && gasleft() < 100000)) {
                            uint256 _order = orders[((next > 0x1FFFFFFFFFF) ? next : marketId | (price << 48) | next)];
                            if ((_orderInfo >> 240 & 0xF) != 0 && (_order >> 113 & 0x1FFFFFFFFFF) == (_orderInfo >> 160 & 0x1FFFFFFFFFF)) {
                                if (((_orderInfo >> 240) & 0x1) != 0) { // stp is 0 do nothing 1 cancel maker 2 cancel taker 3 cancel both
                                    if (next > 0x1FFFFFFFFFF) {
                                        orders[next] &= 0x00000000000000000000000003FFFFFFFFFE0000000000000000000000000000;
                                    }
                                    else {
                                        delete orders[marketId | (price << 48) | next];
                                    }
                                    _priceLevel -= (_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF); // can't overflow
                                    if ((_orderInfo >> 244 & 0xF) == 0) {
                                        settlementDelta += ((_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF));
                                    }
                                    else {
                                        settlementDelta += ((_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF));
                                    }
                                    if ((_order & 0x0000000000000000000000000000000000010000000000000000000000000000) != 0) {
                                        tokenBalances[_order >> 113 & 0x1FFFFFFFFFF][((_orderInfo >> 244 & 0xF) == 0) ? baseAsset : quoteAsset] -= ((((_orderInfo >> 244 & 0xF) == 0) ? (_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) : (_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF)) << 128); // unlock tokens if internal can't overflow
                                    }
                                    assembly {
                                        mstore(add(mload(0xc0), add(0xc0, 0x20)), or(mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(and(shr(244, _orderInfo), 0xF))),or(shl(168,price),or(shl(112,next),and(_order, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF)))))
                                        mstore(0xc0, add(mload(0xc0), 0x20))
                                        mstore(0x40, add(mload(0xc0), add(0xc0, 0x20))) // avoid initializing length bc stack too deep
                                    }
                                    next = (_order >> 205) & 0x7FFFFFFFFFFFF;
                                }
                                if (((_orderInfo >> 240) & 0xF) == 1) {
                                    continue;
                                }
                                else {
                                    sizeLeft = 0;
                                    break;
                                }
                            } // should switch over to do operations on resting size
                            if (((_orderInfo >> 248 & 0xF) == 0) ? (((_orderInfo >> 244 & 0xF) == 0) ? ((_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) > (sizeLeft * m.makerRebate / 100000) * scaleFactor / price) : ((_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) > (sizeLeft * m.makerRebate / 100000) * price / scaleFactor)) : ((_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) > sizeLeft)) {
                                uint256 _amountOut;
                                {
                                    _amountOut = (((_orderInfo >> 248 & 0xF) == 0) ? (((_orderInfo >> 244 & 0xF) == 0) ? (sizeLeft * m.makerRebate / 100000) * scaleFactor / price : (sizeLeft * m.makerRebate / 100000) * price / scaleFactor) : sizeLeft); // output amount for just this swap, round down
                                    amountOut += _amountOut;
                                    if (((_orderInfo >> 248 & 0xF) != 0)) {
                                        sizeLeft = ((_orderInfo >> 244 & 0xF) == 0) ? (sizeLeft * price + scaleFactor - 1) / scaleFactor * 100000 / m.makerRebate : (sizeLeft * scaleFactor + price - 1) / price * 100000 / m.makerRebate; // transfer to maker amount, round up
                                    }
                                    _priceLevel -= _amountOut; // can't overflow
                                    _order -= _amountOut; // can't overflow
                                    orders[((next > 0x1FFFFFFFFFF) ? next : marketId | (price << 48) | next)] = _order;
                                    if (_order & 0x0000000000000000000000000000000000010000000000000000000000000000 == 0) { // maker wants tokens
                                        address owner = userIdToAddress[_order >> 113 & 0x1FFFFFFFFFF];
                                        if ((_orderInfo >> 236 & 0x1) == 0 && (_orderInfo >> 232 & 0x1) == 0) { // taker gives tokens
                                            IERC20(((_orderInfo >> 244 & 0xF) == 0) ? quoteAsset : baseAsset).transferFrom(address(uint160(_orderInfo)), owner, sizeLeft);
                                        }
                                        else { // taker gives internal balance
                                            settlementDelta += sizeLeft << 128;
                                            IERC20(((_orderInfo >> 244 & 0xF) == 0) ? quoteAsset : baseAsset).transfer(owner, sizeLeft);
                                        }
                                    }
                                    else { // maker wants internal balance
                                        settlementDelta += sizeLeft << 128;
                                        tokenBalances[_order >> 113 & 0x1FFFFFFFFFF][((_orderInfo >> 244 & 0xF) == 0) ? quoteAsset : baseAsset] += sizeLeft;
                                        tokenBalances[_order >> 113 & 0x1FFFFFFFFFF][((_orderInfo >> 244 & 0xF) == 0) ? baseAsset : quoteAsset] -= (_amountOut << 128); // unlock maker internal                       
                                    }
                                }
                                amountIn += sizeLeft;
                                address _market = market;
                                assembly {
                                    let length := mload(0xc0)
                                    mstore(add(length, add(0xc0, 0x20)), or(mul(0x1000000000000000000000000000000000000000000000000000000000000000, iszero(and(shr(244, _orderInfo), 0xF))), or(shl(168, price), or(shl(112, next), and(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF, _order)))))
                                    mstore(add(length, add(0xc0, 0x40)), _amountOut)
                                    log2(add(length, add(0xc0, 0x20)), 0x40, _market, and(0x1FFFFFFFFFF, shr(113, _order))) // anon event (orderfilled)
                                    mstore(0x40, add(length, add(0xc0, 0x20)))
                                }
                                sizeLeft = 0;
                            }
                            else {
                                uint256 transferAmount = ((_orderInfo >> 244 & 0xF) == 0) ? ((((_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) * price / scaleFactor) * 100000) / m.makerRebate) : ((((_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) * scaleFactor / price) * 100000) / m.makerRebate);
                                amountIn += transferAmount; // round up maybe?
                                uint256 _amountOut = (_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
                                amountOut += _amountOut;
                                _priceLevel -= _amountOut;
                                sizeLeft -= ((_orderInfo >> 248 & 0xF) == 0) ? transferAmount : _amountOut;
                                if (_order & 0x0000000000000000000000000000000000010000000000000000000000000000 == 0) { // maker wants tokens
                                    address owner = userIdToAddress[_order >> 113 & 0x1FFFFFFFFFF];
                                    if ((_orderInfo >> 236 & 0x1) == 0 && (_orderInfo >> 232 & 0x1) == 0) { // taker gives tokens
                                        IERC20(((_orderInfo >> 244 & 0xF) == 0) ? quoteAsset : baseAsset).transferFrom(address(uint160(_orderInfo)), owner, transferAmount);
                                    }
                                    else { // taker gives internal balance
                                        settlementDelta += transferAmount << 128;
                                        IERC20(((_orderInfo >> 244 & 0xF) == 0) ? quoteAsset : baseAsset).transfer(owner, transferAmount);
                                    }
                                }
                                else { // maker wants internal balance
                                    settlementDelta += transferAmount << 128;
                                    tokenBalances[_order >> 113 & 0x1FFFFFFFFFF][((_orderInfo >> 244 & 0xF) == 0) ? quoteAsset : baseAsset] += transferAmount;
                                    tokenBalances[_order >> 113 & 0x1FFFFFFFFFF][((_orderInfo >> 244 & 0xF) == 0) ? baseAsset : quoteAsset] -= _amountOut << 128; // unlock maker internal                      
                                }
                                address _market = market;
                                assembly {
                                    let length := mload(0xc0)
                                    mstore(add(length, add(0xc0, 0x20)), or(mul(0x1000000000000000000000000000000000000000000000000000000000000000, iszero(and(shr(244, _orderInfo), 0xF))), or(shl(168, price), shl(112, next))))
                                    mstore(add(length, add(0xc0, 0x40)), and(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF, _order))
                                    log2(add(length, add(0xc0, 0x20)), 0x40, _market, and(0x1FFFFFFFFFF, shr(113, _order))) // anon event (orderfilled)
                                    mstore(0x40, add(length, add(0xc0, 0x20)))
                                }
                                if (next > 0x1FFFFFFFFFF) {
                                    orders[next] &= 0x00000000000000000000000003FFFFFFFFFE0000000000000000000000000000;
                                }
                                else {
                                    delete orders[marketId | (price << 48) | next];
                                }
                                next = (_order >> 205) & 0x7FFFFFFFFFFFF;
                            }
                        }
                        priceLevels[marketId | price] = (next << 205) | (_priceLevel & 0x0000000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF); // set fillnext to next
                    }
                    assembly {
                        let temp := mload(0x80)
                        temp := or(and(temp, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000000000000000000000000000), price) // set end price
                        mstore(0x80, temp)
                    }
                    if ((_priceLevel & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) == 0) {
                        slot &= ~(1 << (tick % 256));
                        uint256 slotIndex = tick >> 8;
                        if ((orderInfo >> 244 & 0xF) == 0) {
                            uint256 _slot = slot >> tick % 256;
                            if (_slot == 0 && activated[marketId | slotIndex] != slot) {
                                activated[marketId | slotIndex] = slot;
                            }
                            while (_slot == 0) {
                                ++slotIndex;
                                slot = activated[marketId | slotIndex];
                                _slot = slot;
                                tick = slotIndex << 8;
                            }
                            tick = _searchSlotUp(_slot, tick);
                        }
                        else {
                            uint256 _slot = slot & ((1 << (tick % 256)) - 1);
                            if (_slot == 0 && activated[marketId | slotIndex] != slot) {
                                activated[marketId | slotIndex] = slot;
                            }
                            while (_slot == 0) {
                                --slotIndex;
                                slot = activated[marketId | slotIndex];
                                _slot = slot;
                            }
                            tick = _searchSlotDown(_slot, slotIndex << 8);
                        }
                        price = _tickToPrice(tick);
                    }
                    else {
                        if (activated[marketId | (tick >> 8)] != slot) {
                            activated[marketId | (tick >> 8)] = slot;
                        }
                    }
                    if (sizeLeft == 0 || ((orderInfo >> 252) == 3 && gasleft() < 100000)) {
                        break;
                    }
                }
            }
            if (amountOut != 0) {
                {   
                    if (reserves != 0) {
                        (uint112 reserveQuote, uint112 reserveBase) = (uint112(reserves >> 128), uint112(reserves & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF));
                        if (reserveQuote != m.reserveQuote || reserveBase != m.reserveBase) {
                            (m.reserveQuote, m.reserveBase) = (reserveQuote, reserveBase);
                            emit Sync(market, reserveQuote, reserveBase);
                        }
                    }
                }
                uint256 feeAmount;
                if ((orderInfo >> 244 & 0xF) == 0) {
                    feeAmount = (amountIn * 100000 + m.takerFee - 1) / m.takerFee - amountIn;
                    amountIn += feeAmount;
                    settlementDelta += (feeAmount << 128);
                    m.lowestAsk = uint80(price);
                }
                else {
                    feeAmount = amountOut - amountOut * m.takerFee / 100000;
                    amountOut -= feeAmount;
                    m.highestBid = uint80(price);
                }
                if (address(uint160(priceAndReferrer >> 80)) == address(0)) {
                    uint256 creatorFee = feeAmount * m.creatorFeeSplit / 100;
                    claimableRewards[quoteAsset][m.creator] += creatorFee;
                    claimableRewards[quoteAsset][feeRecipient] += (feeAmount - creatorFee);
                }
                else {
                    uint256 amountCommission = feeAmount * feeCommission / 100;
                    claimableRewards[quoteAsset][address(uint160(priceAndReferrer >> 80))] += amountCommission;
                    uint256 amountRebate = feeAmount * feeRebate / 100;
                    claimableRewards[quoteAsset][address(uint160(orderInfo))] += amountRebate;
                    uint256 creatorFee = feeAmount * m.creatorFeeSplit / 100;
                    claimableRewards[quoteAsset][m.creator] += creatorFee;
                    claimableRewards[quoteAsset][feeRecipient] += (feeAmount - amountCommission - amountRebate - creatorFee);
                }
                assembly {
                    price := mload(0x80)
                }
                emit Trade(market, (orderInfo >> 160) & 0x1FFFFFFFFFF, address(uint160(orderInfo)), (orderInfo >> 244 & 0xF) == 0, amountIn, amountOut, price >> 128, price & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
                return (amountIn, amountOut, id, settlementDelta);
            }
            else {
                return (amountIn, 0, id, settlementDelta);
            }
        }
    }
    // done
    function _limitOrder(bool isBuy, bool isRecieveTokens, uint256 price, uint256 size, uint256 userId, uint256 cloid) internal returns (uint256, uint256 id) { // cloid being under uint10 is enforced in entry points
        unchecked {
            Market storage m = _getMarket[market];
            (uint256 _highestBid, uint256 _lowestAsk) = (m.highestBid, m.lowestAsk);
            if (isBuy) {
                if (price >= _lowestAsk || price == 0 || size < ((m.minSize >> 20) * 10 ** (m.minSize & 0xFFFFF)) || ((orders[(cloid << 41) | userId] & 0xFFFFFFFFFFFFFFFFFFFFFFFFFC0000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFF) != 0)) {
                    return (0, 0);
                }
                if (price > _highestBid) {
                    m.highestBid = uint80(price);
                }
                if (!isRecieveTokens) {
                    tokenBalances[userId][quoteAsset] += (size << 128); // lock tokens if internal
                }
            }
            else {
                if (price <= _highestBid || price >= maxPrice || (size * price / scaleFactor) < ((m.minSize >> 20) * 10 ** (m.minSize & 0xFFFFF)) || ((orders[(cloid << 41) | userId] & 0xFFFFFFFFFFFFFFFFFFFFFFFFFC0000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFF) != 0)) {
                    return (0, 0);
                }
                if (price < _lowestAsk) {
                    m.lowestAsk = uint80(price);
                }
                if (!isRecieveTokens) {
                    tokenBalances[userId][baseAsset] += (size << 128); // lock tokens if internal
                }
            }
            uint256 _priceLevel = priceLevels[marketId | price];
            require((size <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) && ((_priceLevel & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) + size) <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF); // overflow check, if invalid params are entered could revert instead of silent return
            if (cloid != 0) {
                _highestBid = ((cloid | 1) << 41) | userId;
                if (cloid & 1 == 1) {
                    cloidVerify[_highestBid] = cloidVerify[_highestBid] & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000000000000000000000000000 | ((marketId >> 48) | price);
                }
                else {
                    cloidVerify[_highestBid] = cloidVerify[_highestBid] & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF | ((marketId << 80) | (price << 128));
                }
                cloid = (cloid << 41) | userId; // cloid to pointer using userid
                if ((_priceLevel & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) == 0) {
                    require(price % tickSize == 0);
                    uint256 tick = _priceToTick(price);
                    activated[marketId | (tick >> 8)] |= (1 << (tick % 256));
                    _priceLevel =  (cloid << 205) | (_priceLevel & 0x0000000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF); // set fillNext to cloid
                }
                else {
                    uint256 fillBefore = (_priceLevel >> 154) & 0x7FFFFFFFFFFFF;
                    orders[(fillBefore > 0x1FFFFFFFFFF) ? fillBefore : (marketId | (price << 48) | fillBefore)] = (cloid << 205) | (orders[(fillBefore > 0x1FFFFFFFFFF) ? fillBefore : (marketId | (price << 48) | fillBefore)] & 0x0000000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF); // set fillbefores fillafter to cloid instead of prev native id
                }
                orders[cloid] = (((_priceLevel >> 113 & 0x1FFFFFFFFFF) + 1) << 205) | (_priceLevel & (0x7FFFFFFFFFFFF << 154)) | (userId << 113) | (isRecieveTokens ? 0 : (1 << 112)) | size; // fillAfter to priceLevels latestNativeId+1, fillBefore to latest
                priceLevels[marketId | price] = (cloid << 154) | ((_priceLevel & 0xFFFFFFFFFFFFE0000000000003FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) + size); // latest to cloid and add size
                return (size, cloid);
            }
            else {
                id = (_priceLevel >> 113 & 0x1FFFFFFFFFF) + 1;
                require(id <= 0x1FFFFFFFFFF); // overflow uint41
                if ((_priceLevel & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) == 0) {
                    require(price % tickSize == 0);
                    uint256 tick = _priceToTick(price);
                    activated[marketId | (tick >> 8)] |= (1 << (tick % 256));
                    _priceLevel = (id << 205) | (_priceLevel & 0x0000000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF); // set fillNext to id, sometimes redundant
                }
                orders[marketId | (price << 48) | id] = ((id + 1) << 205) | (_priceLevel & (0x7FFFFFFFFFFFF << 154)) | (userId << 113) | (isRecieveTokens ? 0 : (1 << 112)) | size; // fillAfter to id+1, fillBefore to latest
                priceLevels[marketId | price] = (id << 154) | (id << 113) | ((_priceLevel & 0xFFFFFFFFFFFFE00000000000000000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFF) + size); // latest and latestNativeId to id and add size
                return (size, id);
            }
        }       
    }
    // done
    function _cancelOrder(uint256 price, uint256 id, uint256 userId) internal returns (uint256, uint256 size, bool isBuy) { // id is cloid if price is missing
        unchecked {
            Market storage m = _getMarket[market];
            uint256 _order = orders[(price != 0 ? (marketId | (price << 48) | id) : ((id << 41) | userId))]; // id is not yet pointer
            size = (_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
            if (0 == size || userId != (_order >> 113 & 0x1FFFFFFFFFF)) {
                return (0, 0, isBuy);
            }
            if (price != 0) {
                delete orders[marketId | (price << 48) | id];
            }
            else {
                price = cloidVerify[((id | 1) << 41) | userId]; // avoid stack too deep, there's no reason to zero out/edit this as it's not needed
                if (id & 1 == 1) { // make sure order is in right market, get price because cloid doesn't come with it
                    if (((price >> 80) & 0xFFFFFFFFFFFF) != (marketId >> 128)) {
                        return (0, 0, isBuy);
                    }
                    price = price & 0xFFFFFFFFFFFFFFFFFFFF;
                }
                else {
                    if (((price >> 208) & 0xFFFFFFFFFFFF) != (marketId >> 128)) {
                        return (0, 0, isBuy);
                    }
                    price = (price >> 128) & 0xFFFFFFFFFFFFFFFFFFFF;
                }
                id = (id << 41) | userId; // id to pointer using userid
                orders[id] &= 0x00000000000000000000000003FFFFFFFFFE0000000000000000000000000000;
            }
            (uint256 _highestBid, uint256 _lowestAsk) = (m.highestBid, m.lowestAsk);
            if (price <= _highestBid) {
                isBuy = true;
                if ((_order & 0x0000000000000000000000000000000000010000000000000000000000000000) != 0) {
                    tokenBalances[userId][quoteAsset] -= (size << 128); // unlock tokens if internal can't overflow
                }
            }
            else {
                if ((_order & 0x0000000000000000000000000000000000010000000000000000000000000000) != 0) {
                    tokenBalances[userId][baseAsset] -= (size << 128); // unlock tokens if internal can't overflow
                }
            }
            _internalCancel(price, id, size, _highestBid, _lowestAsk, _order);
            return (price, size, isBuy);
        }
    }
    // done
    function _decreaseOrder(uint256 price, uint256 id, uint256 decreaseAmount, uint256 userId) internal returns (uint256, uint256 size, bool isBuy) { // id is cloid if price is missing
        unchecked {
            Market storage m = _getMarket[market];
            uint256 _order = orders[(price != 0 ? (marketId | (price << 48) | id) : ((id << 41) | userId))]; // id is not yet pointer
            size = (_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
            if (0 == size || userId != (_order >> 113 & 0x1FFFFFFFFFF)) {
                return (0, 0, isBuy);
            }
            if (price == 0) {
                price = cloidVerify[((id | 1) << 41) | userId]; // avoid stack too deep, there's no reason to zero out/edit this as it's not needed
                if (id & 1 == 1) { // make sure order is in right market, get price because cloid doesn't come with it
                    if (((price >> 80) & 0xFFFFFFFFFFFF) != (marketId >> 128)) {
                        return (0, 0, isBuy);
                    }
                    price = price & 0xFFFFFFFFFFFFFFFFFFFF;
                }
                else {
                    if (((price >> 208) & 0xFFFFFFFFFFFF) != (marketId >> 128)) {
                        return (0, 0, isBuy);
                    }
                    price = (price >> 128) & 0xFFFFFFFFFFFFFFFFFFFF;
                }
                id = (id << 41) | userId; // id to pointer using userid
            }
            (uint256 _highestBid, uint256 _lowestAsk) = (m.highestBid, m.lowestAsk);
            if (price <= _highestBid) {
                isBuy = true;
            }
            if ((isBuy ? size : (size * price / scaleFactor)) <= (isBuy ? decreaseAmount : (decreaseAmount * price / scaleFactor)) + (((m.minSize >> 20) * 10 ** (m.minSize & 0xFFFFF)))) { // cancel if resulting order would be too small
                if ((_order & 0x0000000000000000000000000000000000010000000000000000000000000000) != 0) {
                    isBuy ? tokenBalances[userId][quoteAsset] -= (size << 128) : tokenBalances[userId][baseAsset] -= (size << 128); // unlock tokens if internal can't overflow
                }
                if (price != 0) {
                    delete orders[marketId | (price << 48) | id];
                }
                else {
                    orders[id] &= 0x00000000000000000000000003FFFFFFFFFE0000000000000000000000000000;
                }
                _internalCancel(price, id, size, _highestBid, _lowestAsk, _order);
                return (price, size, isBuy);
            }
            else {
                if ((_order & 0x0000000000000000000000000000000000010000000000000000000000000000) != 0) {
                    isBuy ? tokenBalances[userId][quoteAsset] -= (decreaseAmount << 128) : tokenBalances[userId][baseAsset] -= (decreaseAmount << 128); // unlock tokens if internal can't overflow
                }
                orders[(price != 0 ? (marketId | (price << 48) | id) : id)] -= decreaseAmount; // can't overflow
                priceLevels[marketId | price] -= decreaseAmount;
                return (price, decreaseAmount << 128, isBuy); // price, decrease amount, isBuy
            }
        }
    }
    // done
    function _replaceOrder(uint256 options, uint256 price, uint256 id, uint256 newPrice, uint256 size) internal returns (int256 quoteAssetDebt, int256 baseAssetDebt, uint256) {
        unchecked {
            bool _isBuy;
            bool _isCloid;
            uint256 _size;
            if (price != 0) {
                _size = (orders[(marketId | (price << 48) | id)] & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF); // id is not pointer
            }
            else {
                _isCloid = true;
                price = cloidVerify[((id | 1) << 41) | (options & 0x1FFFFFFFFFF)]; // avoid stack too deep, there's no reason to zero out/edit this as it's not needed
                if (id & 1 == 1) { // make sure order is in right market, get price because cloid doesn't come with it
                    if (((price >> 80) & 0xFFFFFFFFFFFF) != (marketId >> 128)) {
                        return (0, 0, 0);
                    }
                    price = price & 0xFFFFFFFFFFFFFFFFFFFF;
                }
                else {
                    if (((price >> 208) & 0xFFFFFFFFFFFF) != (marketId >> 128)) {
                        return (0, 0, 0);
                    }
                    price = (price >> 128) & 0xFFFFFFFFFFFFFFFFFFFF;
                }
                _size = (orders[((id << 41) | (options & 0x1FFFFFFFFFF))] & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF); // id is not pointer
            }
            if (price <= _getMarket[market].highestBid) {
                _isBuy = true;
            }
            if (newPrice == 0) {
                newPrice = price;
            }
            if ((((options >> 48) & 0xF) != 0) || (newPrice == price && (_size > size))) {
                (price, _size, _isBuy) = _decreaseOrder(_isCloid ? 0 : price, id, _size - size, (options & 0x1FFFFFFFFFF)); // price is 0 if cloid
                if (_isCloid) {
                    id = (id << 41) | (options & 0x1FFFFFFFFFF); // differentiate emitted cloid
                }
                if (_size != 0) {
                    if ((_size >> 128) == 0) { // cancel
                        _isBuy ? quoteAssetDebt -= int256(_size & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) : baseAssetDebt -= int256(_size & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
                        assembly {
                            let length := mload(0xc0)
                            mstore(add(length, 0xe0), or(mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(_isBuy)),or(shl(168,price),or(shl(112,id),and(112, _size))))) // 3 bits flag 80 price 56 id 112 cancel size
                            mstore(0xc0, add(length, 0x20))
                            mstore(0x40, add(length, 0x100))
                        }
                    }
                    else {
                        _isBuy ? quoteAssetDebt -= int256(_size >> 128) : baseAssetDebt -= int256(_size >> 128);
                        assembly {
                            let length := mload(0xc0)
                            mstore(add(length, 0xe0), or(add(0x4000000000000000000000000000000000000000000000000000000000000000,mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(_isBuy))),or(shl(168,price),or(shl(112,id),shr(128, _size))))) // 3 bits flag 80 price 56 id 112 decrease size not remaining
                            mstore(0xc0, add(length, 0x20))
                            mstore(0x40, add(length, 0x100))
                        }
                    }
                    return (quoteAssetDebt, baseAssetDebt, id);
                }
                else {
                    return (0, 0, 0); // no state is changed, can silent return
                }
            }
            else {
                (price, _size, _isBuy) = _cancelOrder((_isCloid) ? 0 : price, id, (options & 0x1FFFFFFFFFF)); // price is 0 if cloid
                if (_isCloid) {
                    id = (id << 41) | (options & 0x1FFFFFFFFFF); // differentiate emitted cloid
                }
                if (_size != 0) {
                    _isBuy ? quoteAssetDebt -= int256(_size) : baseAssetDebt -= int256(_size);
                    assembly {
                        let length := mload(0xc0)
                        mstore(add(length, 0xe0), or(mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(_isBuy)),or(shl(168,price),or(shl(112,id),_size)))) // 3 bits flag 80 price 56 id 112 size
                        mstore(0xc0, add(length, 0x20))
                        mstore(0x40, add(length, 0x100))
                    }
                }
                else {
                    return (0, 0, 0); // no state is changed, can silent return
                }
                if (_isCloid) {
                    id = id >> 41; // back to normal cloid
                }
                if (size == 0) {
                    size = _size;
                }
                if (((options >> 44) & 0xF) == 0) { // post only
                    (_size, id) = _limitOrder(_isBuy, (((options >> 60) & 0xF) == 0), newPrice, size, (options & 0x1FFFFFFFFFF), id);
                    if (_size != 0) {
                        _isBuy ? quoteAssetDebt += int256(_size) : baseAssetDebt += int256(_size);
                        assembly {
                            let length := mload(0xc0)
                            mstore(add(length, 0xe0), or(add(0x2000000000000000000000000000000000000000000000000000000000000000,mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(_isBuy))),or(shl(168,newPrice),or(shl(112,id),_size)))) // 3 bits flag 80 price 56 id 112 size
                            mstore(0xc0, add(length, 0x20))
                            mstore(0x40, add(length, 0x100))
                        }
                    }
                    else {
                        return (quoteAssetDebt, baseAssetDebt, 0);
                    }
                }
                else {
                    _isCloid = ((options >> 60) & 0xF) == 0; // avoid stack too deep, true if external balances
                    uint256 settlementDelta;
                    uint256 referrer = (options >> 96);
                    uint256 orderInfo = (2 << 252) | (_isBuy ? 0 : (1 << 244)) | (1 << 240) | (_isCloid ? 0 : (1 << 236)) | (id << 208) | ((options & 0x1FFFFFFFFFF) << 160) | uint160(msg.sender);
                    (, _size, id, settlementDelta) = _marketOrder(size, (uint160(referrer) << 80) | newPrice, orderInfo);
                    if (_isBuy) {
                        quoteAssetDebt += int256(settlementDelta >> 128);
                        baseAssetDebt -= int256(_size + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                    }
                    else {
                        baseAssetDebt += int256(settlementDelta >> 128);
                        quoteAssetDebt -= int256(_size + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                    }
                }
                return (quoteAssetDebt, baseAssetDebt, id);
            }
        }
    }
    // make sure to keep pricetimepriority, relinking order on partial fill is fine because it's a single fill
    function _placeGridOrder(bool isBuy, uint256 price, uint256 mirroredPrice, uint256 size, uint256 userId) internal returns (uint256 _size, uint256 id) {
    }
    // done, these methods support margin which is managed before/after the call, just set internal balance mode to true
    function marketOrder(bool isBuy, bool isExactInput, uint256 options, uint256 orderType, uint256 size, uint256 worstPrice, address referrer, address caller) external payable returns (uint256 amountIn, uint256 amountOut, uint256 id) {
        unchecked {
            uint256 orderInfo; // options is 0-44 userId 44-54 cloid 56-60 stp 60-64 tointernalbalances 64-68 frominternalbalances 68-72 useinternalbalances
            uint256 userId;
            {
                uint256 orderFlags = ((orderType & 0xF) << 252) | ((isExactInput ? 0 : (1 << 248))) | ((isBuy ? 0 : (1 << 244))) | (((options >> 56) & 0xF) << 240); // ordertype exactinput=0 isbuy=0 stp
                orderInfo = orderFlags | (((options >> 68) & 0xF) << 236) | (((options >> 64) & 0xF) << 232) | uint160(caller); // useexternalbalance=0 fromcaller=0 add userId 160-208 if internal balance or mtl and cloid if provided 208-218 if mtl and margin enforced elsewhere
                userId = (options & 0x1FFFFFFFFFF);
                if (userId != 0) {
                    require(userIdToAddress[userId] == caller);
                }
                else {
                    userId = addressToUserId[caller];
                    if (userId == 0) {
                        userId = ICrystal(crystal).registerUser();
                    }
                }
                orderInfo |= (userId << 160); // add userId to orderInfo
                if (((options >> 44) & 0x3FF) != 0) { // if cloid
                    orderInfo |= (((options >> 44) & 0x3FF) << 208);
                }
            }
            uint256 settlementDelta;
            assembly {
                mstore(0x40, 0xe0) // 0x80 is used by _marketOrder internally to avoid stack too deep
            }
            (amountIn, amountOut, id, settlementDelta) = _marketOrder(size, (uint160(referrer) << 80) | worstPrice, orderInfo);
            address _market = market;
            assembly {
                let length := mload(0xc0)
                if gt(length, 0) {
                    mstore(0xa0, 0x20)
                    log3(0xa0, add(length, 0x40), 0xcd726e874e479599fa8abfd7a4ad443b08415d78fb36a088cd0e9c88b249ba66, _market, userId)
                }
            }
            address token = isBuy ? quoteAsset : baseAsset;
            if ((settlementDelta >> 128) != 0) { // input token for both limit order and maker internal balance fills
                if (((options >> 68) & 0xF) != 0) {
                    uint256 balance = tokenBalances[userId][token];
                    if (uint128(balance) < (settlementDelta >> 128)) {
                        revert ActionFailed();
                    }
                    else {
                        tokenBalances[userId][token] = balance - (settlementDelta >> 128);
                    }
                }
                else { // use external balance
                    if (((options >> 64) & 0xF) != 0) { // use router balance
                        uint256 balance = tokenBalances[0][token];
                        if (uint128(balance) < (settlementDelta >> 128)) {
                            revert ActionFailed();
                        }
                        else {
                            tokenBalances[0][token] = balance - (settlementDelta >> 128);
                        }
                    }
                    else {
                        IERC20(token).transferFrom(caller, address(this), (settlementDelta >> 128));
                    }
                }
            }
            settlementDelta &= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
            settlementDelta += amountOut; // add output to self cancel credit
            token = isBuy ? baseAsset : quoteAsset;
            if (settlementDelta != 0) { // output token, stp cancels + amountout
                if (((options >> 68) & 0xF) != 0) {
                    tokenBalances[userId][token] += settlementDelta;
                }
                else { // use external balance
                    if (((options >> 60) & 0xF) != 0) {
                        tokenBalances[0][token] += settlementDelta;
                    }
                    else {
                        IERC20(token).transfer(caller, settlementDelta);
                    }
                }
            }
        }
    }
    // done
    function limitOrder(bool isBuy, uint256 options, uint256 price, uint256 size, address caller) external payable returns (uint256 id) { // options is 0-41 userId 44-54 cloid 56-60 frominternalbalances 60-64 useinternalbalances
        unchecked {
            uint256 userId = (options & 0x1FFFFFFFFFF);
            if (userId != 0) { // if userId is supplied verify
                require(userIdToAddress[userId] == caller);
            }
            else { // get default userId
                userId = addressToUserId[caller];
                if (userId == 0) {
                    userId = ICrystal(crystal).registerUser();
                }
            }
            bool useExternalBalances = (((options >> 60) & 0xF) == 0);
            (size, id) = _limitOrder(isBuy, useExternalBalances, price, size, userId, (options >> 44) & 0x3FF);
            if (size != 0) { // if order success
                address token = isBuy ? quoteAsset : baseAsset;
                if (useExternalBalances) {
                    if (((options >> 56) & 0xF) != 0) {
                        uint256 balance = tokenBalances[0][token];
                        if (uint128(balance) < size) {
                            revert ActionFailed();
                        }
                        else {
                            tokenBalances[0][token] = balance - size;
                        }
                    }
                    else {
                        IERC20(token).transferFrom(caller, address(this), size);
                    }
                }
                else {
                    uint256 balance = tokenBalances[userId][token];
                    if (uint128(balance) < size) {
                        revert ActionFailed();
                    }
                    else {
                        tokenBalances[userId][token] = balance - size; // token txfer don't care about locking since done in internal function
                    }
                }
                emit OrdersUpdated(market, userId, abi.encodePacked((isBuy ? 0x2000000000000000000000000000000000000000000000000000000000000000 : 0x3000000000000000000000000000000000000000000000000000000000000000) | (price << 168) | (id << 112) | size)); // if id is a cloid it is already merged w user id
            }
            else {
                revert ActionFailed();
            }
        }
    } 
    // done
    function cancelOrder(uint256 options, uint256 price, uint256 id, address caller) external payable returns (uint256 size) { // options is 0-41 userId 44-48 tointernalbalances 48-52 useinternalbalances
        unchecked {
            bool isBuy;
            uint256 userId = (options & 0x1FFFFFFFFFF);
            if (userId != 0) { // if userId is supplied verify
                require(userIdToAddress[userId] == caller);
            }
            else { // get default userId
                userId = addressToUserId[caller];
            }
            bool useExternalBalances = (((options >> 48) & 0xF) == 0);
            bool isCloid = (price == 0); // if price isn't 0 assume it's a normal order
            (price, size, isBuy) = _cancelOrder(price, id, userId); // if no price attached update price
            if (isCloid) {
                id = (id << 41) | userId;
            }
            if (size != 0) { // if cancel success
                address token = isBuy ? quoteAsset : baseAsset;
                if (useExternalBalances) {
                    if (((options >> 44) & 0xF) != 0) {
                        tokenBalances[0][token] += size;
                    }
                    else {
                        IERC20(token).transfer(caller, size);
                    }
                }
                else {
                    tokenBalances[userId][token] += size;
                }
                emit OrdersUpdated(market, userId, abi.encodePacked((isBuy ? 0 : 0x1000000000000000000000000000000000000000000000000000000000000000) | (price << 168) | (id << 112) | size));
            }
        }
    }
    // replace is useful in that if cancel fails there's no order, will decrease if its best course of action, and also that you can take the proceeds of the cancel as the order size by setting size=0, can also do decrease
    function replaceOrder(uint256 options, uint256 price, uint256 id, uint256 newPrice, uint256 size, address referrer, address caller) external payable returns (uint256 _id) { // options is 0-41 userId 44-48 postOnly=0 48-52 isDecrease 52-56 tointernalbalances 56-60 frominternalbalances 60-64 useinternalbalances
        int256 quoteAssetDebt;
        int256 baseAssetDebt;
        uint256 userId = (options & 0x1FFFFFFFFFF);
        if (userId != 0) { // if userId is supplied verify
            require(userIdToAddress[userId] == caller);
        }
        else { // get default userId
            userId = addressToUserId[caller];
            options = (options & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE0000000000) | userId; // add userId to options
            if (userId == 0) {
                userId = ICrystal(crystal).registerUser();
            }
        }
        options = (uint160(referrer) << 96) | options;
        assembly {
            mstore(0x40, 0xe0) // 0x80 is used by _marketOrder internally to avoid stack too deep
        }
        (quoteAssetDebt, baseAssetDebt, _id) = _replaceOrder(options, price, id, newPrice, size);
        uint256 balanceMode = options; // avoid std
        _settleBalances(caller, quoteAssetDebt, baseAssetDebt, userId, ((balanceMode >> 60) & 0xF), ((balanceMode >> 52) & 0xF), ((balanceMode >> 56) & 0xF));
        address _market = market;
        assembly {
            let length := mload(0xc0)
            switch gt(length, 0)
            case true {
                mstore(0xa0, 0x20)
                log3(0xa0, add(length, 0x40), 0xcd726e874e479599fa8abfd7a4ad443b08415d78fb36a088cd0e9c88b249ba66, _market, userId)
            }
            default {
                revert(0, 0)
            }
        }
    }
    // done except replace if needed, maybe add bribe endpoint in parent, do margin in balance mode param
    function batchOrders(Action[] calldata actions, uint256 options, address referrer, address caller) external payable { // options is 0-41 userId 44-48 tointernalbalances 48-52 frominternalbalances 52-56 useinternalbalances
        unchecked {
            uint256 userId;
            uint256 offset;
            uint256 action;
            uint256 param1;
            uint256 param2;
            uint256 cloid;
            bool isBuy;
            uint256 balanceMode;
            int256 quoteAssetDebt;
            int256 baseAssetDebt;
            if ((options & 0x1FFFFFFFFFF) != 0) { // if userId is supplied verify
                userId = (options & 0x1FFFFFFFFFF);
                require(userIdToAddress[userId] == caller);
            }
            else { // get default userId
                userId = addressToUserId[caller];
                if (userId == 0) {
                    userId = ICrystal(crystal).registerUser();
                }
            }
            balanceMode = ((options >> 52) & 0xF);
            assembly {
                mstore(0x40, 0xe0)
            }
            while (offset < actions.length) {
                action = actions[offset].action & 0xF;
                param1 = actions[offset].param1 & 0xFFFFFFFFFFFFFFFFFFFF;
                param2 = actions[offset].param2 & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
                cloid = actions[offset].param3 & 0x3FF;
                if (action == 1) { // cancel, pass either price and id or cloid
                    if (cloid != 0) {
                        (param1, action, isBuy) = _cancelOrder(0, cloid, userId);
                        param2 = (cloid << 41) | userId; // differentiate emitted cloid
                    }
                    else {
                        (param1, action, isBuy) = _cancelOrder(param1, param2, userId);
                    }
                    if (action != 0) {
                        isBuy ? quoteAssetDebt -= int256(action) : baseAssetDebt -= int256(action);
                        assembly {
                            let length := mload(0xc0)
                            mstore(add(length, 0xe0), or(mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(isBuy)),or(shl(168,param1),or(shl(112,param2),action)))) // 8 flag 80 price 56 id 112 size
                            mstore(0xc0, add(length, 0x20))
                            mstore(0x40, add(length, 0x100))
                        }
                    }
                    else {
                        if (actions[offset].isRequireSuccess) {
                            revert ActionFailed();
                        }
                    }
                }
                else if (action == 2) { // limit buy, pass price size and optional cloid
                    (action, param2) = _limitOrder(true, balanceMode == 0, param1, param2, userId, cloid);
                    if (action != 0) {
                        quoteAssetDebt += int256(action);
                        assembly {
                            let length := mload(0xc0)
                            mstore(add(length, 0xe0), or(0x2000000000000000000000000000000000000000000000000000000000000000,or(shl(168,param1),or(shl(112,param2),action)))) // 8 flag 80 price 56 id 112 size
                            mstore(0xc0, add(length, 0x20))
                            mstore(0x40, add(length, 0x100))
                        }
                    }
                    else {
                        if (actions[offset].isRequireSuccess) {
                            revert ActionFailed();
                        }
                    }
                }
                else if (action == 3) { // limit sell
                    (action, param2) = _limitOrder(false, balanceMode == 0, param1, param2, userId, cloid);
                    if (action != 0) {
                        baseAssetDebt += int256(action);
                        assembly {
                            let length := mload(0xc0)
                            mstore(add(length, 0xe0), or(0x3000000000000000000000000000000000000000000000000000000000000000, or(shl(168,param1),or(shl(112,param2),action)))) // 8 flag 80 price 56 id 112 size
                            mstore(0xc0, add(length, 0x20))
                            mstore(0x40, add(length, 0x100))
                        }
                    }
                    else {
                        if (actions[offset].isRequireSuccess) {
                            revert ActionFailed();
                        }
                    }
                }
                else if (action == 4) { // mtl buy
                    uint256 settlementDelta;
                    settlementDelta = (uint160(referrer) << 80) | param1; // avoid stack too deep
                    ( , action, , settlementDelta) = _marketOrder(param2, settlementDelta, (2 << 252) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    quoteAssetDebt += int256(settlementDelta >> 128);
                    baseAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 5) { // mtl sell
                    uint256 settlementDelta;
                    settlementDelta = (uint160(referrer) << 80) | param1;
                    ( , action, , settlementDelta) = _marketOrder(param2, settlementDelta, (2 << 252) | (1 << 244) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    baseAssetDebt += int256(settlementDelta >> 128);
                    quoteAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 6) { // partialfill buy
                    uint256 settlementDelta;
                    settlementDelta = (uint160(referrer) << 80) | param1;
                    ( , action, , settlementDelta) = _marketOrder(param2, settlementDelta, (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    quoteAssetDebt += int256(settlementDelta >> 128);
                    baseAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 7) { // partialfill sell
                    uint256 settlementDelta;
                    settlementDelta = (uint160(referrer) << 80) | param1;
                    ( , action, , settlementDelta) = _marketOrder(param2, settlementDelta, (1 << 244) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    baseAssetDebt += int256(settlementDelta >> 128);
                    quoteAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 8) { // partial buy terminate when low on remaining gas
                    uint256 settlementDelta;
                    settlementDelta = (uint160(referrer) << 80) | param1;
                    ( , action, , settlementDelta) = _marketOrder(param2, settlementDelta, (3 << 252) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    quoteAssetDebt += int256(settlementDelta >> 128);
                    baseAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 9) { // partial sell terminate when low on remaining gas
                    uint256 settlementDelta;
                    settlementDelta = (uint160(referrer) << 80) | param1;
                    ( , action, , settlementDelta) = _marketOrder(param2, settlementDelta, (3 << 252) | (1 << 244) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    baseAssetDebt += int256(settlementDelta >> 128);
                    quoteAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 10) { // complete fill buy
                    uint256 settlementDelta;
                    settlementDelta = (uint160(referrer) << 80) | param1;
                    ( , action, , settlementDelta) = _marketOrder(param2, settlementDelta, (1 << 252) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    quoteAssetDebt += int256(settlementDelta >> 128);
                    baseAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 11) { // complete fill sell
                    uint256 settlementDelta;
                    settlementDelta = (uint160(referrer) << 80) | param1;
                    ( , action, , settlementDelta) = _marketOrder(param2, settlementDelta, (1 << 252) | (1 << 244) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    baseAssetDebt += int256(settlementDelta >> 128);
                    quoteAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 12) { // decrease order, if price then use cloid else use id
                    bool isCloid;
                    if (param1 != 0) { // if price is provided, id is used not cloid
                        cloid = actions[offset].param3 & 0x1FFFFFFFFFF; // id is a uint41
                    }
                    else {
                        isCloid = true;
                    }
                    (param1, param2, isBuy) = _decreaseOrder(param1, cloid, param2, userId);
                    if (isCloid) {
                        cloid = (cloid << 41) | userId; // differentiate emitted cloid
                    }
                    if (param2 != 0) {
                        if ((param2 >> 128) == 0) { // cancel
                            isBuy ? quoteAssetDebt -= int256(param2 & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) : baseAssetDebt -= int256(param2 & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
                            assembly {
                                let length := mload(0xc0)
                                mstore(add(length, 0xe0), or(mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(isBuy)),or(shl(168,param1),or(shl(112,cloid),and(112,param2))))) // 8 flag 80 price 56 id 112 cancel size
                                mstore(0xc0, add(length, 0x20))
                                mstore(0x40, add(length, 0x100))
                            }
                        }
                        else {
                            isBuy ? quoteAssetDebt -= int256(param2 >> 128) : baseAssetDebt -= int256(param2 >> 128);
                            assembly {
                                let length := mload(0xc0)
                                mstore(add(length, 0xe0), or(add(0x4000000000000000000000000000000000000000000000000000000000000000,mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(isBuy))),or(shl(168,param1),or(shl(112,cloid),shr(128, param2))))) // 8 flag 80 price 56 id 112 decrease size not remaining size
                                mstore(0xc0, add(length, 0x20))
                                mstore(0x40, add(length, 0x100))
                            }
                        }
                    }
                    else {
                        if (actions[offset].isRequireSuccess) {
                            revert ActionFailed();
                        }
                    }
                }
                ++offset;
            }
            param1 = options; // avoid std
            param2 = options; // avoid std
            _settleBalances(caller, quoteAssetDebt, baseAssetDebt, userId, balanceMode, ((param1 >> 44) & 0xF), ((param2 >> 48) & 0xF));
            address _market = market;
            assembly {
                let length := mload(0xc0)
                if gt(length, 0) {
                    mstore(0xa0, 0x20)
                    log3(0xa0, add(length, 0x40), 0xcd726e874e479599fa8abfd7a4ad443b08415d78fb36a088cd0e9c88b249ba66, _market, userId)
                }
            }
        }
    }
    // done except replace if needed, add bribe endpoint in parent, userid is prevalidated, do margin in balance mode param
    fallback() external payable {
        unchecked {
            uint256 userId;
            uint256 offset;
            uint256 action;
            uint256 param1;
            uint256 param2;
            uint256 cloid;
            bool isBuy;
            uint256 balanceMode;
            int256 quoteAssetDebt;
            int256 baseAssetDebt;
            assembly {
                mstore(0x40, 0xe0)
                userId := calldataload(offset)
                balanceMode := shr(44, userId)
                userId := and(0x1FFFFFFFFFF, userId) // it's a uint41 but encoded like a uint44
            }
            offset += 32;
            while (offset < msg.data.length) {
                assembly { // 4-8 is isRequireSuccess
                    action := calldataload(offset)
                    param1 := and(0xFFFFFFFFFFFFFFFFFFFF, shr(112, action)) // 64-144
                    param2 := and(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF, action) // 144-256
                    cloid := and(0x3FF, shr(192, action)) // 20-64
                    action := shr(252, action) // 0-4
                }
                if (action == 1) { // cancel, pass either price and id or cloid
                    if (cloid != 0) {
                        (param1, action, isBuy) = _cancelOrder(0, cloid, userId);
                        param2 = (cloid << 41) | userId; // differentiate emitted cloid
                    }
                    else {
                        (param1, action, isBuy) = _cancelOrder(param1, param2, userId);
                    }
                    if (action != 0) {
                        isBuy ? quoteAssetDebt -= int256(action) : baseAssetDebt -= int256(action);
                        assembly {
                            let length := mload(0xc0)
                            mstore(add(length, 0xe0), or(mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(isBuy)),or(shl(168,param1),or(shl(112,param2),action)))) // 8 flag 80 price 56 id 112 size
                            mstore(0xc0, add(length, 0x20))
                            mstore(0x40, add(length, 0x100))
                        }
                    }
                    else {
                        assembly { // reuse isBuy as isRequireSuccess
                            isBuy := and(0x1, shr(248, calldataload(offset))) // 4-8
                        }
                        if (isBuy) {
                            revert ActionFailed();
                        }
                    }
                }
                else if (action == 2) { // limit buy, pass price size and optional cloid
                    (action, param2) = _limitOrder(true, balanceMode == 0, param1, param2, userId, cloid);
                    if (action != 0) {
                        quoteAssetDebt += int256(action);
                        assembly {
                            let length := mload(0xc0)
                            mstore(add(length, 0xe0), or(0x2000000000000000000000000000000000000000000000000000000000000000,or(shl(168,param1),or(shl(112,param2),action)))) // 8 flag 80 price 56 id 112 size
                            mstore(0xc0, add(length, 0x20))
                            mstore(0x40, add(length, 0x100))
                        }
                    }
                    else {
                        assembly { // reuse isBuy as isRequireSuccess
                            isBuy := and(0x1, shr(248, calldataload(offset))) // 4-8
                        }
                        if (isBuy) {
                            revert ActionFailed();
                        }
                    }
                }
                else if (action == 3) { // limit sell
                    (action, param2) = _limitOrder(false, balanceMode == 0, param1, param2, userId, cloid);
                    if (action != 0) {
                        baseAssetDebt += int256(action);
                        assembly {
                            let length := mload(0xc0)
                            mstore(add(length, 0xe0), or(0x3000000000000000000000000000000000000000000000000000000000000000, or(shl(168,param1),or(shl(112,param2),action)))) // 8 flag 80 price 56 id 112 size
                            mstore(0xc0, add(length, 0x20))
                            mstore(0x40, add(length, 0x100))
                        }
                    }
                    else {
                        assembly { // reuse isBuy as isRequireSuccess
                            isBuy := and(0x1, shr(248, calldataload(offset))) // 4-8
                        }
                        if (isBuy) {
                            revert ActionFailed();
                        }
                    }
                }
                else if (action == 4) { // mtl buy
                    uint256 settlementDelta;
                    ( , action, , settlementDelta) = _marketOrder(param2, (uint160(msg.sender) << 80) | param1, (2 << 252) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    quoteAssetDebt += int256(settlementDelta >> 128);
                    baseAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 5) { // mtl sell
                    uint256 settlementDelta;
                    ( , action, , settlementDelta) = _marketOrder(param2, (uint160(msg.sender) << 80) | param1, (2 << 252) | (1 << 244) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    baseAssetDebt += int256(settlementDelta >> 128);
                    quoteAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 6) { // partialfill buy
                    uint256 settlementDelta;
                    ( , action, , settlementDelta) = _marketOrder(param2, (uint160(msg.sender) << 80) | param1, (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    quoteAssetDebt += int256(settlementDelta >> 128);
                    baseAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 7) { // partialfill sell
                    uint256 settlementDelta;
                    ( , action, , settlementDelta) = _marketOrder(param2, (uint160(msg.sender) << 80) | param1, (1 << 244) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    baseAssetDebt += int256(settlementDelta >> 128);
                    quoteAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 8) { // partial buy terminate when low on remaining gas
                    uint256 settlementDelta;
                    ( , action, , settlementDelta) = _marketOrder(param2, (uint160(msg.sender) << 80) | param1, (3 << 252) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    quoteAssetDebt += int256(settlementDelta >> 128);
                    baseAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 9) { // partial sell terminate when low on remaining gas
                    uint256 settlementDelta;
                    ( , action, , settlementDelta) = _marketOrder(param2, (uint160(msg.sender) << 80) | param1, (3 << 252) | (1 << 244) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    baseAssetDebt += int256(settlementDelta >> 128);
                    quoteAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 10) { // complete fill buy
                    uint256 settlementDelta;
                    ( , action, , settlementDelta) = _marketOrder(param2, (uint160(msg.sender) << 80) | param1, (1 << 252) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    quoteAssetDebt += int256(settlementDelta >> 128);
                    baseAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 11) { // complete fill sell
                    uint256 settlementDelta;
                    ( , action, , settlementDelta) = _marketOrder(param2, (uint160(msg.sender) << 80) | param1, (1 << 252) | (1 << 244) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    baseAssetDebt += int256(settlementDelta >> 128);
                    quoteAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 12) { // decrease order, if price then use cloid else use id
                    bool isCloid;
                    if (param1 != 0) { // if price is provided, id is used not cloid
                        assembly {
                            cloid := and(0x1FFFFFFFFFF, shr(192, calldataload(offset))) // id is a uint41, 16-64
                        }
                    }
                    else {
                        isCloid = true;
                    }
                    (param1, param2, isBuy) = _decreaseOrder(param1, cloid, param2, userId);
                    if (isCloid) {
                        cloid = (cloid << 41) | userId; // differentiate emitted cloid
                    }
                    if (param2 != 0) {
                        if ((param2 >> 128) == 0) { // cancel
                            isBuy ? quoteAssetDebt -= int256(param2 & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) : baseAssetDebt -= int256(param2 & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
                            assembly {
                                let length := mload(0xc0)
                                mstore(add(length, 0xe0), or(mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(isBuy)),or(shl(168,param1),or(shl(112,cloid),and(112,param2))))) // 8 flag 80 price 56 id 112 cancel size
                                mstore(0xc0, add(length, 0x20))
                                mstore(0x40, add(length, 0x100))
                            }
                        }
                        else {
                            isBuy ? quoteAssetDebt -= int256(param2 >> 128) : baseAssetDebt -= int256(param2 >> 128);
                            assembly {
                                let length := mload(0xc0)
                                mstore(add(length, 0xe0), or(add(0x4000000000000000000000000000000000000000000000000000000000000000,mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(isBuy))),or(shl(168,param1),or(shl(112,cloid),shr(128, param2))))) // 8 flag 80 price 56 id 112 decrease size not remaining size
                                mstore(0xc0, add(length, 0x20))
                                mstore(0x40, add(length, 0x100))
                            }
                        }
                    }
                    else {
                        assembly { // reuse isBuy as isRequireSuccess
                            isBuy := and(0x1, shr(248, calldataload(offset))) // 4-8
                        }
                        if (isBuy) {
                            revert ActionFailed();
                        }
                    }
                }
                offset += 32;
            }
            _settleBalances(msg.sender, quoteAssetDebt, baseAssetDebt, userId, balanceMode, 0, 0);
            address _market = market;
            assembly {
                let length := mload(0xc0)
                if gt(length, 0) {
                    mstore(0xa0, 0x20)
                    log3(0xa0, add(length, 0x40), 0xcd726e874e479599fa8abfd7a4ad443b08415d78fb36a088cd0e9c88b249ba66, _market, userId)
                }
            }
        }
    }
}

contract CrystalMarket0Factory {
    function deploy(address quoteAsset, address baseAsset, uint256 marketId) external returns (address market) {
        market = address(new CrystalMarket0{salt: keccak256(abi.encode(quoteAsset, baseAsset, marketId))}());
    }
}

contract CrystalMarket1Factory {
    function deploy(address quoteAsset, address baseAsset, uint256 marketId) external returns (address market) {
        market = address(new CrystalMarket1{salt: keccak256(abi.encode(quoteAsset, baseAsset, marketId))}());
    }
}

contract CrystalMarket2Factory {
    function deploy(address quoteAsset, address baseAsset, uint256 marketId) external returns (address market) {
        market = address(new CrystalMarket2{salt: keccak256(abi.encode(quoteAsset, baseAsset, marketId))}());
    }
}