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

interface ICrystalVault {
    struct Action {
        uint256 action;
        uint256 cloid;
        uint256 param1;
        uint256 param2;
    }

    function balanceOf(address owner) external view returns (uint);

    function crystal() external view returns (address);
    function quoteAsset() external view returns (address);
    function baseAsset() external view returns (address);
    function owner() external view returns (address);
    function factory() external view returns (address);

    function totalShares() external view returns (uint256);
    function maxShares() external view returns (uint256);
    function lastDepositTimestamp(address user) external view returns (uint256);

    function description() external view returns (string memory);
    function market() external view returns (address);
    function orderCap() external view returns (uint16);
    function lockup() external view returns (uint40);
    function locked() external view returns (bool);
    function closed() external view returns (bool);

    function lock() external;
    function unlock() external;

    function changeMaxShares(uint256 _maxShares) external;
    function changeMarket(address newMarket) external;
    function changeOrderCap(uint16 newCap) external;
    function changeDecreaseOnWithdraw(bool newDecrease) external;
    function changeLockup(uint40 newLockup) external;

    function claimFees() external;
    function clearCloidSlots(uint256 userId, uint256[] calldata ids) external;

    function previewDeposit(uint256 amountQuoteDesired, uint256 amountBaseDesired)
        external
        view
        returns (uint256 shares, uint256 amountQuote, uint256 amountBase);

    function previewWithdrawal(uint256 shares)
        external
        view
        returns (uint256 amountQuote, uint256 amountBase);

    function deposit(
        address user,
        uint256 amountQuoteDesired,
        uint256 amountBaseDesired,
        uint256 amountQuoteMin,
        uint256 amountBaseMin
    )
        external
        returns (uint256 shares, uint256 amountQuote, uint256 amountBase);

    function withdraw(
        address user,
        uint256 shares,
        uint256 amountQuoteMin,
        uint256 amountBaseMin
    )
        external
        returns (uint256 amountQuote, uint256 amountBase);

    function execute(Action[] calldata actions) external returns (bytes memory);
}

interface ICrystalVaultFactory {
    function maxOrderCap() external view returns (uint16);
    function maxLockup() external view returns (uint40);
}

contract ERC20 {
    string public name;
    string public symbol;
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

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes(_name)),
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

    function transfer(address to, uint256 value) external virtual returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external virtual returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
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

contract CrystalVault is ERC20 {
    struct Action {
        bool requireSuccess;
        uint256 action;
        uint256 param1; // price
        uint256 param2; // size/id
        uint256 cloid; // cloid
    }

    struct VaultMetaData {
        string name;
        string description;
        string social1;
        string social2;
        string social3;  
    }

    mapping(address => uint) public lastDepositTimestamp;
    uint256 public totalShares;
    uint256 public maxShares;

    address public market;
    uint40 public lockup;
    uint16 public orderCap;
    bool public decrease;
    bool public locked;
    bool public closed;

    VaultMetaData public metadata;

    address public immutable crystal;
    address public immutable quoteAsset;
    address public immutable baseAsset;
    address public immutable owner;
    address public immutable factory;

    constructor(address _crystal, address _quoteAsset, address _baseAsset, address _owner, string memory _name, string memory _symbol, string memory _description, string memory _social1, string memory _social2, string memory _social3) ERC20(_name, _symbol) {
        crystal = _crystal;
        metadata = VaultMetaData(_name, _description, _social1, _social2, _social3);
        market = ICrystal(crystal).getMarketByTokens(_quoteAsset, _baseAsset);
        require(ICrystal(crystal).getMarket(market).quoteAsset == _quoteAsset); // min owner deposit is enforced in factory, valid market is enforced here aswell
        quoteAsset = _quoteAsset;
        baseAsset = _baseAsset;
        owner = _owner;
        factory = msg.sender;
        orderCap = ICrystalVaultFactory(factory).maxOrderCap();
        lockup = ICrystalVaultFactory(factory).maxLockup();
        ICrystal(crystal).registerUser();
        IERC20(quoteAsset).approve(crystal, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        IERC20(baseAsset).approve(crystal, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
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

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _balances() internal view returns (uint256 quoteBalance, uint256 baseBalance, uint256 availableBalanceQuote, uint256 availableBalanceBase) {
        (quoteBalance, availableBalanceQuote, ) = ICrystal(crystal).getDepositedBalance(address(this), quoteAsset);
        (baseBalance, availableBalanceBase, ) = ICrystal(crystal).getDepositedBalance(address(this), baseAsset);
    }
    
    function transfer(address, uint) external pure override returns (bool) {
        revert();
    }

    function transferFrom(address, address, uint) external pure override returns (bool) {
        revert();
    }

    function lock() external {
        require((factory == msg.sender) && locked == false);
        locked = true;
    }

    function unlock() external {
        require((factory == msg.sender) && locked == true && closed == false);
        locked = false;
    }

    function changeMaxShares(uint256 _maxShares) external {
        require(factory == msg.sender);
        maxShares = _maxShares;
    }

    function changeMarket(address newMarket) external {
        require(factory == msg.sender);
        ICrystal.MarketInfo memory _market = ICrystal(crystal).getMarket(newMarket);
        require(_market.quoteAsset == quoteAsset && _market.baseAsset == baseAsset);
        cancelAll();
        market = newMarket;
    }

    function changeOrderCap(uint16 newCap) external {
        uint256 maxOrderCap = ICrystalVaultFactory(factory).maxOrderCap();
        require(factory == msg.sender && newCap <= maxOrderCap);
        (uint256[] memory cloids, ) = ICrystal(crystal).getAllOrdersByCloid(address(this), orderCap);
        for (uint256 i = 0; i < cloids.length; ++i) {
            require(newCap > cloids[i]);
        }
        orderCap = newCap;
    }

    function changeDecreaseOnWithdraw(bool newDecrease) external {
        require(factory == msg.sender);
        decrease = newDecrease;
    }

    function changeLockup(uint40 newLockup) external {
        uint256 maxLockup = ICrystalVaultFactory(factory).maxLockup();
        require(factory == msg.sender && newLockup <= maxLockup);
        lockup = newLockup;
    }

    function claimFees() external {
        require(factory == msg.sender);
        address[] memory tokens = new address[](2);
        tokens[0] = quoteAsset;
        tokens[1] = baseAsset;
        ICrystal(crystal).claimFees(owner, tokens);
    }

    function clearCloidSlots(uint256 userId, uint256[] calldata ids) external {
        require(factory == msg.sender);
        ICrystal(crystal).clearCloidSlots(userId, ids);
    }

    function previewDeposit(uint256 amountQuoteDesired, uint256 amountBaseDesired) external view returns (uint256 shares, uint256 amountQuote, uint256 amountBase) {
        (uint256 quoteBalance, uint256 baseBalance, , ) = _balances();
        if (totalShares == 0) {
            amountQuote = amountQuoteDesired;
            amountBase = amountBaseDesired;
            shares = _sqrt(amountQuote * amountBase);
        } else {
            uint256 amountBaseOptimal = (amountQuoteDesired * baseBalance) / quoteBalance;
            if (amountBaseOptimal <= amountBaseDesired) {
                amountQuote = amountQuoteDesired;
                amountBase = amountBaseOptimal;
            } else {
                uint256 amountQuoteOptimal = (amountBaseDesired * quoteBalance) / baseBalance;
                require(amountQuoteOptimal <= amountQuoteDesired);
                amountQuote = amountQuoteOptimal;
                amountBase = amountBaseDesired;
            }
            shares = _min((amountQuote * totalShares) / quoteBalance, (amountBase * totalShares) / baseBalance);
        }
    }

    function previewWithdrawal(uint256 shares) external view returns (uint256 amountQuote, uint256 amountBase) {
        (uint256 quoteBalance, uint256 baseBalance, , ) = _balances();
        amountQuote = (quoteBalance * shares) / totalShares;
        amountBase = (baseBalance * shares) / totalShares;
    }

    function deposit(address user, uint256 amountQuoteDesired, uint256 amountBaseDesired, uint256 amountQuoteMin, uint256 amountBaseMin) external returns (uint256 shares, uint256 amountQuote, uint256 amountBase) {
        require(factory == msg.sender && !locked && amountQuoteDesired != 0 && amountBaseDesired != 0);
        (uint256 quoteBalance, uint256 baseBalance, , ) = _balances();

        if (totalShares == 0) {
            amountQuote = amountQuoteDesired;
            amountBase = amountBaseDesired;
            shares = _sqrt(amountQuote * amountBase);
        } else {
            uint256 amountBaseOptimal = (amountQuoteDesired * baseBalance) / quoteBalance;
            if (amountBaseOptimal <= amountBaseDesired) {
                amountQuote = amountQuoteDesired;
                amountBase = amountBaseOptimal;
            } else {
                uint256 amountQuoteOptimal = (amountBaseDesired * quoteBalance) / baseBalance;
                require(amountQuoteOptimal <= amountQuoteDesired);
                amountQuote = amountQuoteOptimal;
                amountBase = amountBaseDesired;
            }
            shares = _min((amountQuote * totalShares) / quoteBalance, (amountBase * totalShares) / baseBalance);
        }

        require(amountQuote >= amountQuoteMin && amountBase >= amountBaseMin && (maxShares == 0 || totalShares + shares <= maxShares));

        IERC20(quoteAsset).transferFrom(msg.sender, address(this), amountQuote);
        IERC20(baseAsset).transferFrom(msg.sender, address(this), amountBase);
        ICrystal(crystal).deposit(quoteAsset, amountQuote);
        ICrystal(crystal).deposit(baseAsset, amountBase);

        totalShares += shares;
        _mint(user, shares);
        lastDepositTimestamp[user] = block.timestamp;
        require(balanceOf[owner] * 20 > totalShares);
    }

    function withdraw(address user, uint256 shares, uint256 amountQuoteMin, uint256 amountBaseMin) external returns (uint256 amountQuote, uint256 amountBase) {
        require(factory == msg.sender && shares != 0 && shares <= balanceOf[user] && lastDepositTimestamp[user] + lockup < block.timestamp);
        (uint256 quoteBalance, uint256 baseBalance, uint256 availableQuote, uint256 availableBase) = _balances();
        amountQuote = (quoteBalance * shares) / totalShares;
        amountBase = (baseBalance * shares) / totalShares;
        require(amountQuote >= amountQuoteMin && amountBase >= amountBaseMin);
        _burn(user, shares);
        totalShares -= shares;
        if (user == owner && !closed) {
            if (balanceOf[owner] == 0) {
                cancelAll();
                closed = true;
                if (!locked) {
                    locked = true;
                }
            }
            else {
                require(balanceOf[owner] * 20 > totalShares);
            }
        }
        if (decrease) {
            (uint256[] memory cloids, ICrystal.Order[] memory orders) = ICrystal(crystal).getAllOrdersByCloid(address(this), orderCap);
            bytes32[] memory data = new bytes32[](cloids.length + 1);
            data[0] = bytes32(1 << 252 | cloids.length << 160 | uint160(market));
            ICrystal.Order memory order;
            uint256 cloid;
            for (uint256 i; i < cloids.length; ++i) {
                order = orders[i];
                cloid = cloids[i];
                if (order.isBuy) {
                    if (((quoteBalance - availableQuote) * amountQuote / quoteBalance) >= (amountQuote > availableQuote ? (amountQuote - availableQuote) : 0)) { // decrease proportionally
                        data[i + 1] = bytes32((12 << 252) |
                        ((cloid & 0x3FF) << 192) |
                        ((order.size * amountQuote + quoteBalance - 1) / quoteBalance) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF);    
                    }
                    else { // decrease to make enough available
                        data[i + 1] = bytes32((12 << 252) |
                        ((cloid & 0x3FF) << 192) |
                        ((order.size * (amountQuote > availableQuote ? (amountQuote - availableQuote) : 0) + (quoteBalance - availableQuote) - 1) / (quoteBalance - availableQuote)) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
                    }
                }
                else {
                    if (((baseBalance - availableBase) * amountBase / baseBalance) >= (amountBase > availableBase ? (amountBase - availableBase) : 0)) { // decrease proportionally
                        data[i + 1] = bytes32((12 << 252) |
                        ((cloid & 0x3FF) << 192) |
                        ((order.size * amountBase + baseBalance - 1) / baseBalance) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF);    
                    }
                    else { // decrease to make enough available
                        data[i + 1] = bytes32((12 << 252) |
                        ((cloid & 0x3FF) << 192) |
                        ((order.size * (amountBase > availableBase ? (amountBase - availableBase) : 0) + (baseBalance - availableBase) - 1) / (baseBalance - availableBase)) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
                    }
                }
            }
            (bool success, bytes memory returnData) = crystal.call(abi.encodePacked(data));
            if (!success) {
                assembly {
                    revert(add(returnData, 32), mload(returnData))
                }
            }
        }
        else if (amountQuote > availableQuote || amountBase > availableBase) {
            (uint256[] memory cloids, ICrystal.Order[] memory orders) = ICrystal(crystal).getAllOrdersByCloid(address(this), orderCap);
            bytes32[] memory data = new bytes32[](cloids.length + 1);
            ICrystal.Order memory order;
            uint256 cloid;
            uint256 excessQuote = amountQuote > availableQuote ? (amountQuote - availableQuote) : 0;
            uint256 excessBase = amountBase > availableBase ? (amountBase - availableBase) : 0;
            uint256 lockedQuote = quoteBalance - availableQuote;
            uint256 lockedBase = baseBalance - availableBase;
            uint256 idx;
            for (uint256 i; i < cloids.length; ++i) {
                order = orders[i];
                cloid = cloids[i];
                if (order.isBuy && excessQuote != 0) {
                    data[++idx] = bytes32((12 << 252) |
                    ((cloid & 0x3FF) << 192) |
                    ((order.size * excessQuote + lockedQuote - 1) / lockedQuote) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
                }
                else if (!order.isBuy && excessBase != 0) {
                    data[++idx] = bytes32((12 << 252) |
                    ((cloid & 0x3FF) << 192) |
                    ((order.size * excessBase + lockedBase - 1) / lockedBase) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
                }
            }
            data[0] = bytes32(1 << 252 | idx << 160 | uint160(market));
            idx += 1;
            assembly { mstore(data, idx) }
            (bool success, bytes memory returnData) = crystal.call(abi.encodePacked(data));
            if (!success) {
                assembly {
                    revert(add(returnData, 32), mload(returnData))
                }
            }
        }
        ICrystal(crystal).withdraw(msg.sender, quoteAsset, amountQuote);
        ICrystal(crystal).withdraw(msg.sender, baseAsset, amountBase);
    }

    function cancelAll() public {
        require(msg.sender == owner || msg.sender == factory);
        (uint256[] memory cloids, ) = ICrystal(crystal).getAllOrdersByCloid(address(this), orderCap);
        bytes32[] memory data = new bytes32[](cloids.length + 1);
        uint256 cloid;
        data[0] = bytes32(1 << 252 | cloids.length << 160 | uint160(market));
        for (uint256 i; i < cloids.length; ++i) {
            cloid = cloids[i];
            uint256 word = (1 << 252) | ((cloid & 0x3FF) << 192);
            data[i + 1] = bytes32(word);
        }
        (bool success, bytes memory returnData) = crystal.call(abi.encodePacked(data));
        if (!success) {
            assembly {
                revert(add(returnData, 32), mload(returnData))
            }
        }
    }

    function execute(Action[] calldata actions) external {
        require(msg.sender == owner && actions.length < 10000 && !closed);
        bytes32[] memory data = new bytes32[](actions.length + 1);
        Action memory action;
        data[0] = bytes32(1 << 252 | actions.length << 160 | uint160(market));
        for (uint256 i; i < actions.length; ++i) {
            action = actions[i];
            if (
                action.action == 2 ||
                action.action == 3 ||
                action.action == 4 ||
                action.action == 5
            ) {
                require(action.cloid != 0 && action.cloid < orderCap);
            }
            data[i+1] = bytes32((action.action << 252) |
                (action.requireSuccess ? (1 << 246) : 0) |
                ((action.cloid & 0x3FF) << 192) |
                ((action.param1 & 0xFFFFFFFFFFFFFFFFFFFF) << 112) |
                action.param2 & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
        }
        (bool success, bytes memory returnData) = crystal.call(abi.encodePacked(data));
        if (!success) {
            assembly {
                revert(add(returnData, 32), mload(returnData))
            }
        }
    }
}

contract CrystalVaultFactory {
    struct Vault {
        address vault;
        address quoteAsset;
        address baseAsset;
        address owner;
        uint256 totalShares;
        uint256 maxShares;
        uint40 lockup;
        bool locked;
        bool closed;
        VaultMetaData metadata;
    }

    struct VaultMetaData {
        string name;
        string description;
        string social1;
        string social2;
        string social3;  
    }

    address public immutable weth; 
    address public immutable eth = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public gov;
    address public crystal;
    address[] public allVaults;
    mapping (address => Vault) public getVault;
    mapping (address => uint256) public minSize;
    uint256 public defaultQuoteMin; // min deposit, is already divided by deciamls
    uint256 public defaultBaseMin; // anti rounding error, raw value
    uint16 public maxOrderCap;
    uint40 public maxLockup;

    event VaultDeployed(address indexed vault, address quoteAsset, address baseAsset, address owner, string name, string desc, string social1, string social2, string social3);
    event Deposit(address indexed vault, address indexed sender, uint256 shares, uint256 quoteAmount, uint256 baseAmount);
    event Withdraw(address indexed vault, address indexed sender, uint256 shares, uint256 quoteAmount, uint256 baseAmount);
    event MaxSharesChanged(address indexed vault, uint256 maxShares);
    event LockupChanged(address indexed vault, uint256 lockup);
    event Locked(address indexed vault);
    event Unlocked(address indexed vault);
    event Closed(address indexed vault);

    constructor(address _crystal, address _gov, address _weth, uint256 _defaultQuoteMin, uint256 _defaultBaseMin, uint256 _maxOrderCap, uint256 _lockup) {
        crystal = _crystal;
        gov = _gov;
        weth = _weth;
        defaultQuoteMin = _defaultQuoteMin;
        defaultBaseMin = _defaultBaseMin;
        maxOrderCap = uint16(_maxOrderCap);
        maxLockup = uint40(_lockup);
    }

    function _createVault(
        address quoteAsset,
        address baseAsset,
        string memory name,
        string memory symbol,
        string memory description,
        string memory social1,
        string memory social2,
        string memory social3
    ) private returns (address vault) {
        require(quoteAsset != address(0));
        vault = address(new CrystalVault(
            crystal,
            quoteAsset,
            baseAsset,
            msg.sender,
            name,
            symbol,
            description,
            social1,
            social2,
            social3
        ));
        IERC20(quoteAsset).approve(vault, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        IERC20(baseAsset).approve(vault, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        getVault[vault] = Vault(vault, quoteAsset, baseAsset, msg.sender, 0, 0, maxLockup, false, false, VaultMetaData(name, description, social1, social2, social3));
        allVaults.push(vault);
        emit VaultDeployed(vault, quoteAsset, baseAsset, msg.sender, name, description, social1, social2, social3);
    }

    function changeGov(address newGov) external {
        require(msg.sender == gov);
        gov = newGov;
    }

    function changeMaxOrderCap(uint256 newCap) external {
        require(msg.sender == gov);
        maxOrderCap = uint16(newCap);
    }

    function changeMaxLockup(uint256 newLockup) external {
        require(msg.sender == gov);
        maxLockup = uint40(newLockup);
    }

    function changeTokenMinSize(address token, uint256 newMinSize) external {
        require(msg.sender == gov);
        minSize[token] = newMinSize;
    }

    function deploy(address quoteAsset, address baseAsset, uint256 amountQuote, uint256 amountBase, string memory name, string memory description, string memory social1, string memory social2, string memory social3) external payable returns (address vault) {
        if (minSize[quoteAsset == eth ? weth : quoteAsset] != 0) { // make sure first deposit isn't dust
            require(amountQuote > minSize[quoteAsset == eth ? weth : quoteAsset]);
        } else {
            require(amountQuote > defaultQuoteMin * 10 ** IERC20(quoteAsset == eth ? weth : quoteAsset).decimals());
        }

        if (minSize[baseAsset] != 0) {
            require(amountBase > minSize[baseAsset]);
        } else {
            require(amountBase > defaultBaseMin);
        }
        string memory symbol = string.concat("CLV-", IERC20(baseAsset).symbol(), IERC20(quoteAsset == eth ? weth : quoteAsset).symbol());

        vault = _createVault(quoteAsset == eth ? weth : quoteAsset, baseAsset == eth ? weth : baseAsset, name, symbol, description, social1, social2, social3);

        deposit(vault, quoteAsset, baseAsset, amountQuote, amountBase, 0, 0);
    }

    function allVaultsLength() external view returns (uint256) {
        return allVaults.length;
    }

    function previewDeposit(address vault, uint256 amountQuoteDesired, uint256 amountBaseDesired) external view returns (uint256 shares, uint256 amountQuote, uint256 amountBase) {
        return ICrystalVault(vault).previewDeposit(amountQuoteDesired, amountBaseDesired);
    }

    function previewWithdrawal(address vault, uint256 shares) external view returns (uint256 amountQuote, uint256 amountBase) {
        return ICrystalVault(vault).previewWithdrawal(shares);
    }

    function balanceOf(address vault, address user) external view returns (uint256 shares, uint256 amountQuote, uint256 amountBase) {
        shares = ICrystalVault(vault).balanceOf(user);
        (amountQuote, amountBase) = ICrystalVault(vault).previewWithdrawal(shares);
    }

    function deposit(address vault, address quoteAsset, address baseAsset, uint256 amountQuoteDesired, uint256 amountBaseDesired, uint256 amountQuoteMin, uint256 amountBaseMin) public payable returns (uint256 shares, uint256 amountQuote, uint256 amountBase) {
        assembly {
            if tload(0x0) { revert(0, 0) }
            tstore(0x0, 1)
        }
        require(getVault[vault].quoteAsset == (quoteAsset == eth ? weth : quoteAsset) && getVault[vault].baseAsset == (baseAsset == eth ? weth : baseAsset));
        if (quoteAsset == eth) {
            IWETH(weth).deposit{value: msg.value}();
        } else {
            IERC20(quoteAsset).transferFrom(msg.sender, address(this), amountQuoteDesired);
        }
        if (baseAsset == eth) {
            IWETH(weth).deposit{value: msg.value}();
        } else {
            IERC20(baseAsset).transferFrom(msg.sender, address(this), amountBaseDesired);
        }
        (shares, amountQuote, amountBase) = ICrystalVault(vault).deposit(msg.sender, amountQuoteDesired, amountBaseDesired, amountQuoteMin, amountBaseMin);
        if (quoteAsset == eth) {
            IWETH(weth).withdraw(msg.value-amountQuote);
            (bool success, ) = msg.sender.call{value : msg.value-amountQuote}("");
            require(success);
        } else {
            IERC20(quoteAsset).transfer(msg.sender, amountQuoteDesired - amountQuote);
        }
        if (baseAsset == eth) {
            IWETH(weth).withdraw(msg.value-amountBase);
            (bool success, ) = msg.sender.call{value : msg.value-amountBase}("");
            require(success);
        } else {
            IERC20(baseAsset).transfer(msg.sender, amountBaseDesired - amountBase);
        }
        getVault[vault].totalShares += shares;
        emit Deposit(vault, msg.sender, shares, amountQuote, amountBase);
        assembly {
            tstore(0x0, 0)
        }
    }

    function withdraw(address vault, address quoteAsset, address baseAsset, uint256 shares, uint256 amountQuoteMin, uint256 amountBaseMin) external returns (uint256 amountQuote, uint256 amountBase) {
        assembly {
            if tload(0x0) { revert(0, 0) }
            tstore(0x0, 1)
        }
        require(getVault[vault].quoteAsset == (quoteAsset == eth ? weth : quoteAsset) && getVault[vault].baseAsset == (baseAsset == eth ? weth : baseAsset));
        (amountQuote, amountBase) = ICrystalVault(vault).withdraw(msg.sender, shares, amountQuoteMin, amountBaseMin);
        if (quoteAsset == eth) {
            IWETH(weth).withdraw(amountQuote);
            (bool success, ) = msg.sender.call{value : amountQuote}("");
            require(success);
        } else {
            IERC20(quoteAsset).transfer(msg.sender, amountQuote);
        }
        if (baseAsset == eth) {
            IWETH(weth).withdraw(amountBase);
            (bool success, ) = msg.sender.call{value : amountBase}("");
            require(success);
        } else {
            IERC20(baseAsset).transfer(msg.sender, amountBase);
        }
        uint256 totalShares = ICrystalVault(vault).totalShares();
        if (totalShares == 0 && !getVault[vault].closed) { // has to be owner full withdraw causing vault to close
            if (!getVault[vault].locked) {
                getVault[vault].locked = true;
                emit Locked(vault);
            }
            getVault[vault].closed = true;
            emit Closed(vault);
        }
        getVault[vault].totalShares = totalShares;
        emit Withdraw(vault, msg.sender, shares, amountQuote, amountBase);
        assembly {
            tstore(0x0, 0)
        }
    }

    function lock(address vault) external {
        require(msg.sender == ICrystalVault(vault).owner());
        ICrystalVault(vault).lock();
        getVault[vault].locked = true;
        emit Locked(vault);
    }

    function unlock(address vault) external {
        require(msg.sender == ICrystalVault(vault).owner());
        ICrystalVault(vault).unlock();
        getVault[vault].locked = false;
        emit Unlocked(vault);
    }

    function close(address vault) external returns (uint256 amountQuote, uint256 amountBase) {
        require(msg.sender == ICrystalVault(vault).owner());
        Vault memory vaultInfo = getVault[vault];
        uint256 shares = ICrystalVault(vault).balanceOf(msg.sender);
        (amountQuote, amountBase) = ICrystalVault(vault).withdraw(msg.sender, shares, 0, 0);
        IERC20(vaultInfo.quoteAsset).transfer(msg.sender, amountQuote);
        IERC20(vaultInfo.baseAsset).transfer(msg.sender, amountBase);
        uint256 totalShares = ICrystalVault(vault).totalShares();
        if (totalShares == 0 && !getVault[vault].closed) { // has to be owner full withdraw causing vault to close
            if (!getVault[vault].locked) {
                getVault[vault].locked = true;
                emit Locked(vault);
            }
            getVault[vault].closed = true;
            emit Closed(vault);
        }
        getVault[vault].totalShares = totalShares;
        emit Withdraw(vault, msg.sender, shares, amountQuote, amountBase);
    }

    function changeMaxShares(address vault, uint256 newMaxShares) external {
        require(msg.sender == ICrystalVault(vault).owner());
        ICrystalVault(vault).changeMaxShares(newMaxShares);
        getVault[vault].maxShares = newMaxShares;
        emit MaxSharesChanged(vault, newMaxShares);
    }

    function changeLockup(address vault, uint40 newLockup) external {
        require(msg.sender == ICrystalVault(vault).owner());
        ICrystalVault(vault).changeLockup(newLockup);
        getVault[vault].lockup = newLockup;
        emit LockupChanged(vault, newLockup);
    }

    function changeOrderCap(address vault, uint16 newCap) external {
        require(msg.sender == ICrystalVault(vault).owner());
        ICrystalVault(vault).changeOrderCap(newCap);
    }

    function changeDecreaseOnWithdraw(address vault, bool newDecrease) external {
        require(msg.sender == ICrystalVault(vault).owner());
        ICrystalVault(vault).changeDecreaseOnWithdraw(newDecrease);
    }

    function changeMarket(address vault, address newMarket) external {
        require(msg.sender == ICrystalVault(vault).owner());
        ICrystalVault(vault).changeMarket(newMarket);
    }

    function claimFees(address vault) external {
        require(msg.sender == ICrystalVault(vault).owner());
        ICrystalVault(vault).claimFees();
    }

    function clearCloidSlots(address vault, uint256 userId, uint256[] calldata ids) external {
        require(msg.sender == ICrystalVault(vault).owner());
        ICrystalVault(vault).clearCloidSlots(userId, ids);
    }
}