// SPDX-License-Identifier: MIT
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

interface ICrystalMarket {
    struct PriceLevel {
        uint128 size;
        uint40 fillNext;
        uint40 latest;
    }

    struct Order {
        uint32 owner;
        uint128 size;
        uint40 fillBefore;
        uint40 fillAfter;
    }

    function highestBid() external view returns (uint80);
    function lowestAsk() external view returns (uint80);
    function latestUserId() external view returns (uint256);
    function quoteAsset() external view returns (address);
    function baseAsset() external view returns (address);
    function router() external view returns (address);
    function gov() external view returns (address);
    function fee() external view returns (uint256);
    function maxPrice() external view returns (uint256);
    function scaleFactor() external view returns (uint256);
    function minSize() external view returns (uint256);

    function orders(uint256 price, uint256 id) external view returns (Order memory);
    function priceLevels(uint256 price) external view returns (PriceLevel memory);
    function userIdToAddress(uint256 userId) external view returns (address);
    function addressToUserId(address user) external view returns (uint256);
    function accumulatedFeeQuote(address user) external view returns (uint256);
    function accumulatedFeeBase(address user) external view returns (uint256);

    function getPrice() external view returns (uint256 price, uint256 _highestBid, uint256 _lowestAsk);
    function getPriceLevels(bool up, uint256 startPrice, uint256 distance) external view returns (bytes memory _orders);
    function getPriceLevelsFromMid(uint256 distance) external view returns (
        uint256 _highestBid,
        uint256 _lowestAsk,
        bytes memory buyOrders,
        bytes memory sellOrders
    );
    function getQuote(
        bool isBuy, 
        bool isExactInput, 
        uint256 size, 
        uint256 worstPrice
    ) external view returns (
        uint256 amountIn, 
        uint256 amountOut
    );

    function changeMaxPrice(uint256 newMaxPrice) external;
    function changeFee(uint256 newFee) external;
    function changeGov(address newGov) external;
    function marketOrder(
        bool isBuy,
        bool isExactInput, 
        bool isFromCaller, 
        bool isToCaller, 
        uint256 orderType, 
        uint256 size, 
        uint256 worstPrice, 
        address caller, 
        address referrer
    ) external returns (
        uint256 amountIn, 
        uint256 amountOut, 
        uint256 id
    );
    function limitOrder(
        bool isBuy,
        uint256 price, 
        uint256 size, 
        address from, 
        address owner
    ) external returns (uint256 id);
    function cancelOrder(
        uint256 price,
        uint256 id, 
        address to, 
        address owner
    ) external returns (uint256 size);
    function registerUser(address from) external returns (uint256 _latestUserId);
    function claimFees(address from) external returns (uint256 quoteAmount, uint256 baseAmount);
    function batchOrders(
        uint256[] calldata action, 
        uint256[] calldata price, 
        uint256[] calldata param1, 
        address[] calldata param2, 
        address owner,
        address referrer
    ) external returns (uint256[] memory returnData);
    function batchOrdersRequireSuccess(
        uint256[] calldata action, 
        uint256[] calldata price, 
        uint256[] calldata param1, 
        address[] calldata param2, 
        address owner,
        address referrer
    ) external returns (uint256[] memory returnData);

    event OrderFilled(address indexed caller, uint256 amounts, uint256 info, bytes filled);
    event OrdersUpdated(address indexed caller, bytes orderData);
}

interface ICrystalRouter {
    function parameters() external view returns (address quoteAsset, address baseAsset, uint256 _scaleFactor, uint256 tickSize, uint80 maxPrice);
    function index(address quoteAsset, address baseAsset) external view returns (uint256);

    event MarketCreated(address indexed quoteAsset, address indexed baseAsset, address market, uint256 fee, uint256 scaleFactor, uint256 minSize, uint256 maxPrice);
}

contract CrystalRouter {
    struct Parameters {
        address quoteAsset;
        address baseAsset;
        address gov;
        address router;
        uint256 fee;
        uint256 scaleFactor;
        uint256 minSize;
        uint256 maxPrice;
    }

    address public gov;

    address public immutable WETH; 
    address public immutable ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    mapping(address => mapping(address => address)) public getMarket;
    mapping(address => mapping(address => uint256)) public index;
    mapping(string => address) public refToAddress;
    mapping(address => string) public addressToRef;
    mapping(address => uint256) public referrerToReferredAddresses;
    mapping(address => address) public addressToReferrer;
    mapping(address => string) public addressToUsername;
    mapping(string => address) public usernameToAddress;
    address[] public allMarkets;

    Parameters public parameters;

    event MarketCreated(address indexed quoteAsset, address indexed baseAsset, address market, uint256 fee, uint256 scaleFactor, uint256 minSize, uint256 maxPrice, uint256);
    event Referral(address indexed referrer, address referee);
    event Username(address indexed caller, string username);
    event GovChanged(address prev, address gov);
    
    error SlippageExceeded();
    error RefCodeAlreadyTaken();
    error UsernameAlreadyTaken();
    error CancelFailed();
    error OrderFailed();
    error Expired(uint256 timestamp);
    error Unauthorized(address caller);
    error TransferFailed(address recipient);
    error Invalid(address[] path);
    error InvalidMarket(address asset0, address asset1);

    constructor(address _gov, address _WETH) {
        gov = _gov;
        WETH = _WETH;
    }

    function getAmountsOut(uint256 amountIn, address[] memory path) external view returns (uint256[] memory amounts) {
        if (path.length < 2) {
            revert Invalid(path);
        }
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i; i < path.length - 1; ++i) {
            address asset0 = path[i] == ETH ? WETH : path[i];
            address asset1 = path[i+1] == ETH ? WETH : path[i+1];
            address market = getMarket[asset0][asset1];
            if (market == address(0)) {
                revert InvalidMarket(asset0, asset1);
            }
            uint256 inputAmount;
            if (ICrystalMarket(market).quoteAsset() == asset0) {
                (inputAmount, amounts[i + 1]) = ICrystalMarket(market).getQuote(true, true, amounts[i], 0xffffffffffffffffffff);
            }
            else {
                (inputAmount, amounts[i + 1]) = ICrystalMarket(market).getQuote(false, true, amounts[i], 1);
            }
            if (amounts[i] != inputAmount && i > 0) {
                revert SlippageExceeded();
            }
            amounts[i] = inputAmount;
        }
    }

    function getAmountsIn(uint256 amountOut, address[] memory path) public view returns (uint256[] memory amounts) {
        if (path.length < 2) {
            revert Invalid(path);
        }
        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint256 i = path.length - 1; i > 0; --i) {
            address asset0 = path[i-1] == ETH ? WETH : path[i-1];
            address asset1 = path[i] == ETH ? WETH : path[i];
            address market = getMarket[asset0][asset1];
            if (market == address(0)) {
                revert InvalidMarket(asset0, asset1);
            }
            uint256 outputAmount;
            if (ICrystalMarket(market).quoteAsset() == asset0) {
                (amounts[i - 1], outputAmount) = ICrystalMarket(market).getQuote(true, false, amounts[i], 0xffffffffffffffffffff);
            }
            else {
                (amounts[i - 1], outputAmount) = ICrystalMarket(market).getQuote(false, false, amounts[i], 1);
            }
            if (amounts[i] != outputAmount) {
                revert SlippageExceeded();
            }
        }
    }
    
    function allMarketsLength() external view returns (uint256) {
        return allMarkets.length;
    }

    function exactInputSwap(uint256 amountIn, address[] memory path, address to, address referrer) internal returns (uint256[] memory amounts) {
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i; i < path.length - 1; ++i) {
            address asset0 = path[i] == ETH ? WETH : path[i];
            address asset1 = path[i+1] == ETH ? WETH : path[i+1];
            address market = getMarket[asset0][asset1];
            if (market == address(0)) {
                revert InvalidMarket(asset0, asset1);
            }
            asset1 = ICrystalMarket(market).quoteAsset();
            (, amounts[i + 1], ) = ICrystalMarket(market).marketOrder(asset1 == asset0, true, (i != 0 || path[i] == ETH) ? false : true, (i != path.length - 2 || path[i+1] == ETH || to != msg.sender) ? false : true, 1, amounts[i], asset1 == asset0 ? 0xffffffffffffffffffff : 1, msg.sender, referrer);
        }
    }

    function exactOutputSwap(uint256[] memory amounts, address[] memory path, address to, address referrer) internal {
        for (uint256 i; i < path.length - 1; ++i) {
            address asset0 = path[i] == ETH ? WETH : path[i];
            address asset1 = path[i+1] == ETH ? WETH : path[i+1];
            address market = getMarket[asset0][asset1];
            asset1 = ICrystalMarket(market).quoteAsset();
            ICrystalMarket(market).marketOrder(asset1 == asset0, false, (i != 0 || path[i] == ETH) ? false : true, (i != path.length - 2 || path[i+1] == ETH || to != msg.sender) ? false : true, 1, amounts[i+1], asset1 == asset0 ? 0xffffffffffffffffffff : 1, msg.sender, referrer);
        }
    }

    function changeGov(address newGov) external {
        if (msg.sender != gov) {
            revert Unauthorized(msg.sender);
        }
        gov = newGov;
        emit GovChanged(msg.sender, newGov);
    }

    function deploy(address quoteAsset, address baseAsset, address _gov, uint256 fee, uint256 scaleFactor, uint256 minSize, uint256 maxPrice) external returns (address market) {
        if (msg.sender != gov) {
            revert Unauthorized(msg.sender);
        }
        parameters = Parameters(quoteAsset, baseAsset, _gov, address(this), fee, scaleFactor, minSize, maxPrice);
        market = address(new CrystalMarket{salt: keccak256(abi.encode(quoteAsset, baseAsset, index[quoteAsset][baseAsset]))}());
        delete parameters;
        ++index[quoteAsset][baseAsset];
        allMarkets.push(market);
        getMarket[quoteAsset][baseAsset] = market;
        getMarket[baseAsset][quoteAsset] = market;
        IERC20(quoteAsset).approve(market, 2**256-1);
        IERC20(baseAsset).approve(market, 2**256-1);
        emit MarketCreated(quoteAsset, baseAsset, market, fee, scaleFactor, minSize, maxPrice, allMarkets.length);
    }

    function swapExactETHForTokens(uint256 amountOutMin, address[] memory path, address to, uint256 deadline, address referrer) external payable returns (uint256[] memory amounts) {
        if (path.length < 2 || path[0] != ETH) {
            revert Invalid(path);
        }
        if (deadline < block.timestamp) {
            revert Expired(deadline);
        }
        IWETH(WETH).deposit{value: msg.value}();
        amounts = exactInputSwap(msg.value, path, to, referrer);
        if (amountOutMin > amounts[amounts.length - 1]) {
            revert SlippageExceeded();
        }
        if (to != msg.sender) {
            IERC20(path[path.length - 1]).transfer(to, amounts[amounts.length - 1]);
        }
    }

    function swapExactTokensForETH(uint256 amountIn, uint256 amountOutMin, address[] memory path, address to, uint256 deadline, address referrer) external returns (uint256[] memory amounts) {
        if (deadline < block.timestamp) {
            revert Expired(deadline);
        }
        if (path.length < 2 || path[path.length - 1] != ETH) {
            revert Invalid(path);
        }
        amounts = exactInputSwap(amountIn, path, to, referrer);
        if (amountOutMin > amounts[amounts.length - 1]) {
            revert SlippageExceeded();
        }
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        (bool success, ) = to.call{value : amounts[amounts.length - 1]}("");
        if (!success) {
            revert TransferFailed(to);
        }
    }

    function swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, address[] memory path, address to, uint256 deadline, address referrer) external returns (uint256[] memory amounts) {
        if (deadline < block.timestamp) {
            revert Expired(deadline);
        }
        if (path.length < 2 || path[path.length - 1] == ETH) {
            revert Invalid(path);
        }
        amounts = exactInputSwap(amountIn, path, to, referrer);
        if (amountOutMin > amounts[amounts.length - 1]) {
            revert SlippageExceeded();
        }
        if (to != msg.sender) {
            IERC20(path[path.length - 1]).transfer(to, amounts[amounts.length - 1]);
        }
    }

    function swapETHForExactTokens(uint256 amountOut, address[] memory path, address to, uint256 deadline, address referrer) external payable returns (uint256[] memory amounts) {
        if (deadline < block.timestamp) {
            revert Expired(deadline);
        }
        if (path[0] != ETH) {
            revert Invalid(path);
        }
        amounts = getAmountsIn(amountOut, path);
        if (amounts[0] > msg.value) {
            revert SlippageExceeded();
        }
        IWETH(WETH).deposit{value: amounts[0]}();
        exactOutputSwap(amounts, path, to, referrer);
        if (to != msg.sender) {
            IERC20(path[path.length - 1]).transfer(to, amountOut);
        }
        if (msg.value > amounts[0]) {
            (bool success, ) = msg.sender.call{value : msg.value - amounts[0]}("");
            if (!success) {
                revert TransferFailed(msg.sender);
            }              
        }
    }

    function swapTokensForExactETH(uint256 amountOut, uint256 amountInMax, address[] memory path, address to, uint256 deadline, address referrer) external returns (uint256[] memory amounts) {
        if (deadline < block.timestamp) {
            revert Expired(deadline);
        }
        if (path[path.length - 1] != ETH) {
            revert Invalid(path);
        }
        amounts = getAmountsIn(amountOut, path);
        if (amounts[0] > amountInMax) {
            revert SlippageExceeded();
        }
        exactOutputSwap(amounts, path, to, referrer);
        IWETH(WETH).withdraw(amountOut);
        (bool success, ) = to.call{value : amountOut}("");
        if (!success) {
            revert TransferFailed(to);
        } 
    }

    function swapTokensForExactTokens(uint256 amountOut, uint256 amountInMax, address[] memory path, address to, uint256 deadline, address referrer) external returns (uint256[] memory amounts) {
        if (deadline < block.timestamp) {
            revert Expired(deadline);
        }
        if (path[path.length - 1] == ETH) {
            revert Invalid(path);
        }
        amounts = getAmountsIn(amountOut, path);
        if (amounts[0] > amountInMax) {
            revert SlippageExceeded();
        }
        exactOutputSwap(amounts, path, to, referrer);
        if (to != msg.sender) {
            IERC20(path[path.length - 1]).transfer(to, amountOut);
        }
    }

    function swap(bool exactInput, address tokenIn, address tokenOut, uint256 orderType, uint256 size, uint256 worstPrice, uint256 deadline, address referrer) external payable returns (uint256 amountIn, uint256 amountOut, uint256 id) {
        if (deadline < block.timestamp) {
            revert Expired(deadline);
        }
        address market = getMarket[tokenIn == ETH ? WETH : tokenIn][tokenOut == ETH ? WETH : tokenOut];    
        if (market == address(0)) {
            revert InvalidMarket(tokenIn == ETH ? WETH : tokenIn, tokenOut == ETH ? WETH : tokenOut);
        }
        if (tokenIn == ETH) {
            IWETH(WETH).deposit{value: msg.value}();
        }
        if (orderType == 2 && ICrystalMarket(market).addressToUserId(msg.sender) == 0) {
            ICrystalMarket(market).registerUser(msg.sender);
        }
        (amountIn, amountOut, id) = ICrystalMarket(market).marketOrder(ICrystalMarket(market).quoteAsset() == (tokenIn == ETH ? WETH : tokenIn), exactInput, !(tokenIn == ETH), !(tokenOut == ETH), orderType, size, worstPrice, msg.sender, referrer);
        if (tokenIn == ETH || tokenOut == ETH) {
            uint256 balance = IWETH(WETH).balanceOf(address(this));
            if (balance != 0) {
                IWETH(WETH).withdraw(balance);
                (bool success, ) = msg.sender.call{value : balance}("");
                if (!success) {
                    revert TransferFailed(msg.sender);
                }
            }
        }
    }

    function limitOrder(address tokenIn, address tokenOut, uint256 price, uint256 size, uint256 deadline) external payable returns (uint256 id) {
        if (deadline < block.timestamp) {
            revert Expired(deadline);
        }
        bool isETHIn = tokenIn == ETH;
        if (isETHIn) {
            IWETH(WETH).deposit{value: size}();
        }
        address asset0 = isETHIn ? WETH : tokenIn;
        address asset1 = tokenOut == ETH ? WETH : tokenOut;
        address market = getMarket[asset0][asset1];    
        if (market == address(0)) {
            revert InvalidMarket(asset0, asset1);
        }
        if (ICrystalMarket(market).addressToUserId(msg.sender) == 0) {
            ICrystalMarket(market).registerUser(msg.sender);
        }
        id = ICrystalMarket(market).limitOrder(ICrystalMarket(market).quoteAsset() == asset0, price, size, isETHIn ? address(this) : msg.sender, msg.sender);
        if (id == 0) {
            revert OrderFailed();
        }
    }

    function cancelOrder(address tokenIn, address tokenOut, uint256 price, uint256 id) external returns (uint256 size) {
        bool isETHIn = tokenIn == ETH;
        address asset0 = isETHIn ? WETH : tokenIn;
        address asset1 = tokenOut == ETH ? WETH : tokenOut;
        address market = getMarket[asset0][asset1];    
        if (market == address(0)) {
            revert InvalidMarket(asset0, asset1);
        }
        size = ICrystalMarket(market).cancelOrder(price, id, isETHIn ? address(this) : msg.sender, msg.sender);
        if (size == 0) {
            revert CancelFailed();
        }
        if (isETHIn) {
            uint256 balance = IWETH(WETH).balanceOf(address(this));
            if (balance != 0) {
                IWETH(WETH).withdraw(balance);
                (bool success, ) = msg.sender.call{value : balance}("");
                if (!success) {
                    revert TransferFailed(msg.sender);
                }             
            }          
        }
    }

    function replaceOrder(bool postOnly, bool noIncrease, address tokenIn, address tokenOut, uint256 price, uint256 id, uint256 newPrice, uint256 newSize, uint256 deadline, address referrer) external returns (uint256) {
        if (deadline < block.timestamp) {
            revert Expired(deadline);
        }
        address market = getMarket[tokenIn == ETH ? WETH : tokenIn][tokenOut == ETH ? WETH : tokenOut];    
        if (market == address(0)) {
            revert InvalidMarket(tokenIn == ETH ? WETH : tokenIn, tokenOut == ETH ? WETH : tokenOut);
        }
        uint256 size = ICrystalMarket(market).cancelOrder(price, id, address(this), msg.sender);
        if (size == 0) {
            revert CancelFailed();
        }
        uint256 balance = IERC20(tokenIn == ETH ? WETH : tokenIn).balanceOf(address(this));
        if (newSize == 0) {
            if (postOnly) {
                id = ICrystalMarket(market).limitOrder(ICrystalMarket(market).quoteAsset() == (tokenIn == ETH ? WETH : tokenIn), newPrice, balance, address(this), msg.sender);
                if (id == 0) {
                    revert OrderFailed();
                }
            }
            else {
                (, balance, id) = ICrystalMarket(market).marketOrder(ICrystalMarket(market).quoteAsset() == (tokenIn == ETH ? WETH : tokenIn), true, false, true, 2, balance, newPrice, msg.sender, referrer);
                if (balance == 0 && id == 0) {
                    revert OrderFailed();
                }
            }
        }
        else {
            if (newSize > balance) {
                if (noIncrease) {
                    revert SlippageExceeded();
                }
                IERC20(tokenIn == ETH ? WETH : tokenIn).transfer(msg.sender, balance);
            }
            if (postOnly) {
                id = ICrystalMarket(market).limitOrder(ICrystalMarket(market).quoteAsset() == (tokenIn == ETH ? WETH : tokenIn), newPrice, newSize, newSize > balance ? msg.sender : address(this), msg.sender);
                if (id == 0) {
                    revert OrderFailed();
                }
            }
            else {
                (, balance, id) = ICrystalMarket(market).marketOrder(ICrystalMarket(market).quoteAsset() == (tokenIn == ETH ? WETH : tokenIn), true, newSize > balance ? true : false, true, 2, newSize, newPrice, msg.sender, referrer);
                if (balance == 0 && id == 0) {
                    revert OrderFailed();
                }
            }
        }
        balance = IERC20(tokenIn == ETH ? WETH : tokenIn).balanceOf(address(this));
        if (balance != 0) {
            IERC20(tokenIn == ETH ? WETH : tokenIn).transfer(msg.sender, balance);   
        }
        return id;
    }

    function claimFees(address[] calldata markets) external {
        for (uint256 i = 0; i < markets.length; ++i) {
            ICrystalMarket(markets[i]).claimFees(msg.sender);
        }        
    }

    function setReferral(string memory code) external {
        bytes memory codeBytes = bytes(code);
        for (uint i = 0; i < codeBytes.length; i++) {
            if (codeBytes[i] >= 0x41 && codeBytes[i] <= 0x5A) {
                codeBytes[i] = bytes1(uint8(codeBytes[i]) + 32);
            }
        }
        code = string(codeBytes);
        if (refToAddress[code] != address(0) || bytes(code).length == 0) {
            revert RefCodeAlreadyTaken();
        }
        if (bytes(addressToRef[msg.sender]).length != 0) {
            refToAddress[addressToRef[msg.sender]] = address(0);
        }
        addressToRef[msg.sender] = code;
        refToAddress[code] = msg.sender;
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
            referrerToReferredAddresses[addressToReferrer[msg.sender]] -= 1;
        }
        address referrer = refToAddress[code];
        addressToReferrer[msg.sender] = referrer;
        emit Referral(referrer, msg.sender);
        if (referrer != address(0) && bytes(code).length != 0) {
            referrerToReferredAddresses[referrer] += 1;
        }
    }

    function setUsername(string memory username) external {
        if (usernameToAddress[username] != address(0) || bytes(username).length == 0) {
            revert UsernameAlreadyTaken();
        }
        if (bytes(addressToUsername[msg.sender]).length != 0) {
            usernameToAddress[addressToUsername[msg.sender]] = address(0);
        }
        addressToUsername[msg.sender] = username;
        usernameToAddress[username] = msg.sender;
        emit Username(msg.sender, username);
    }

    function clearUsername() external {
        if (bytes(addressToUsername[msg.sender]).length != 0) {
            usernameToAddress[addressToUsername[msg.sender]] = address(0);
        }
        addressToUsername[msg.sender] = '';
        emit Username(msg.sender, '');
    }

    function multiBatchOrders(address[] calldata markets, uint256[][] calldata action, uint256[][] calldata price, uint256[][] calldata param1, address[][] calldata param2, uint256 deadline, address referrer) external payable returns (uint256[][] memory returnData) {
        if (deadline < block.timestamp) {
            revert Expired(deadline);
        }
        if (msg.value != 0) {
            IWETH(WETH).deposit{value: msg.value}();
        }
        returnData = new uint256[][](markets.length);
        for (uint256 i = 0; i < markets.length; ++i) {
            if (ICrystalMarket(markets[i]).addressToUserId(msg.sender) == 0) {
                ICrystalMarket(markets[i]).registerUser(msg.sender);
            }
            returnData[i] = ICrystalMarket(markets[i]).batchOrders(action[i], price[i], param1[i], param2[i], msg.sender, referrer);
        }
        uint256 balance = IWETH(WETH).balanceOf(address(this));
        if (balance != 0) {
            IWETH(WETH).withdraw(balance);
            (bool success, ) = msg.sender.call{value : address(this).balance}("");
            if (!success) {
                revert TransferFailed(msg.sender);
            }               
        }
    }

    receive() external payable {}
}

contract CrystalMarket {
    struct PriceLevel {
        uint128 size;
        uint40 fillNext;
        uint40 latestActive;
        uint40 latest;
    }

    struct Order {
        uint128 size;
        uint40 owner;
        uint40 fillBefore;
        uint40 fillAfter;
    }

    uint256 public latestUserId;
    uint80 public highestBid;
    uint80 public lowestAsk;
    uint80 public maxPrice;
    uint16 private lock = 1;
    uint24 public takerFee;
    uint24 public makerRebate;
    uint8 public feeCommission;
    uint8 public feeRebate;
    address public gov;

    uint256 public immutable minSize;
    uint256 public immutable tickSize;
    uint256 public immutable scaleFactor;
    address public immutable quoteAsset;
    address public immutable baseAsset;
    address public immutable router;

    mapping (uint256 => uint256) public activated;
    mapping (uint256 => mapping (uint256 => uint256)) public orders;
    mapping (uint256 => uint256) public priceLevels;
    mapping (uint256 => address) public userIdToAddress;
    mapping (address => uint256) public addressToUserId;
    mapping (address => uint256) public accumulatedFeeQuote;
    mapping (address => uint256) public accumulatedFeeBase;

    event OrdersFilled(address indexed caller, uint256 amounts, uint256 info, bytes filled);
    event OrdersUpdated(address indexed caller, bytes orderData);
    event RewardsClaimed(address indexed caller, uint256 quoteAmount, uint256 baseAmount);
    event ParamsChanged(address indexed market, address gov, uint80 maxPrice, uint256 minSize, uint24 takerFee, uint24 makerRebate, uint8 feeCommission, uint8 feeRebate);

    error SlippageExceeded();
    error ActionFailed();

    /* constructor() {
        uint256 _scaleFactor;
        (quoteAsset, baseAsset, router, _scaleFactor, tickSize, gov, maxPrice, minSize, takerFee, makerRebate, feeCommission, feeRebate) = ICrystalRouter(msg.sender).parameters();
        require(quoteAsset != baseAsset && maxPrice <= 0xffffffffffffffffffff && 95000 <= takerFee && takerFee <= 100000);
        scaleFactor = 10**_scaleFactor;
        highestBid = 0;
        lowestAsk = uint80(maxPrice);
        activated[0] = 1;
        activated[maxPrice >> 8] = (1 << (maxPrice % 256));
    } */

    constructor() {
        uint256 _scaleFactor;
        (quoteAsset, baseAsset, router, _scaleFactor, tickSize, gov, maxPrice, minSize, takerFee, makerRebate, feeCommission, feeRebate) = (0xf817257fed379853cDe0fa4F97AB987181B1E5Ea, 0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701, 0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701, 21, 1, 0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701, 1000000000000000, 100000, 99970, 0, 10, 10);
        require(quoteAsset != baseAsset && maxPrice <= 0xffffffffffffffffffff && 95000 <= takerFee && takerFee <= 100000);
        scaleFactor = 10**_scaleFactor;
        highestBid = 0;
        lowestAsk = uint80(maxPrice);
        activated[0] = 1;
        uint256 maxTick = _priceToTick(maxPrice);
        activated[maxTick >> 8] = (1 << (maxTick % 256));
    }

    function _tickToPrice(uint256 i) internal pure returns (uint256 result) {
        unchecked {
            if (i <= 100_000) return i;
            uint256 x = i - 10_000;
            return 10 ** (x / 90_000) * (10_000 + (x % 90_000));
        }
    }

    function _priceToTick(uint256 p) internal pure returns (uint256) {
        unchecked {
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

    function _getPriceLevels(bool isAscending, uint256 startPrice, uint256 distance, uint256 max) internal view {
        unchecked {
            uint256 _maxPrice = maxPrice;
            if (startPrice >= _maxPrice) {
                return;
            }
            uint256 tick = _priceToTick(startPrice);
            if (!isAscending) {
                ++tick;
            }
            uint256 price;
            uint256 slotIndex = tick >> 8;
            uint256 slot = activated[slotIndex];
            uint256 position;
            assembly {
                position := mload(0x40)
                mstore(position, 0x0)
            }
            uint256 count = 0;
            if (isAscending) {
                if (startPrice + (distance) > _maxPrice) {
                    distance = (_maxPrice - startPrice);
                }
                while (count < max) {
                    uint256 _slot = slot >> tick % 256;
                    while (_slot == 0) {
                        ++slotIndex;
                        slot = activated[slotIndex];
                        _slot = slot;
                        tick = slotIndex << 8;
                    }
                    if (_slot & ((1 << 128) - 1) == 0) {_slot >>= 128; tick += 128;}
                    if (_slot & ((1 << 64) - 1) == 0) {_slot >>= 64; tick += 64;}
                    if (_slot & ((1 << 32) - 1) == 0) {_slot >>= 32; tick += 32;}
                    if (_slot & ((1 << 16) - 1) == 0) {_slot >>= 16; tick += 16;}
                    if (_slot & ((1 << 8) - 1) == 0) {_slot >>= 8; tick += 8;}
                    if (_slot & ((1 << 4) - 1) == 0) {_slot >>= 4; tick += 4;}
                    if (_slot & ((1 << 2) - 1) == 0) {_slot >>= 2; tick += 2;}
                    if (_slot & 1 == 0) {++tick;}
                    slot &= ~(1 << (tick % 256));
                    price = _tickToPrice(tick);
                    if (price < startPrice + distance) {
                        assembly {
                            mstore(0x00, price)
                            mstore(0x20, priceLevels.slot)
                            let length := mload(position)
                            mstore(add(length, add(position, 0x20)), or(shl(128, price), and(sload(keccak256(0x00, 0x40)), 0xffffffffffffffffffffffffffffffff)))
                            mstore(position, add(length, 0x20))
                        }
                        ++count;
                    }
                    else {
                        break;
                    }
                }
            }
            else {
                if (distance > startPrice) {
                    distance = startPrice;
                }
                while (count < max) {
                    uint256 _slot = slot & ((1 << (tick % 256)) - 1);
                    while (_slot == 0) {
                        --slotIndex;
                        slot = activated[slotIndex];
                        _slot = slot;
                    }
                    tick = slotIndex << 8;
                    if (_slot >= 2 ** 128) {_slot >>= 128; tick += 128;}
                    if (_slot >= 2 ** 64) {_slot >>= 64; tick += 64;}
                    if (_slot >= 2 ** 32) {_slot >>= 32; tick += 32;}
                    if (_slot >= 2 ** 16) {_slot >>= 16; tick += 16;}
                    if (_slot >= 2 ** 8) {_slot >>= 8; tick += 8;}
                    if (_slot >= 2 ** 4) {_slot >>= 4; tick += 4;}
                    if (_slot >= 2 ** 2) {_slot >>= 2; tick += 2;}
                    if (_slot >= 2 ** 1) {++tick;}
                    slot &= ~(1 << (tick % 256));
                    price = _tickToPrice(tick);
                    if (price > startPrice - distance) {
                        assembly {
                            mstore(0x00, price)
                            mstore(0x20, priceLevels.slot)
                            let length := mload(position)
                            mstore(add(length, add(position, 0x20)), or(shl(128, price), and(sload(keccak256(0x00, 0x40)), 0xffffffffffffffffffffffffffffffff)))
                            mstore(position, add(length, 0x20))
                        }
                        ++count;
                    }
                    else {
                        break;
                    }
                }     
            }
        }
    }

    function getOrder(uint256 price, uint256 id) external view returns (Order memory) {
        uint256 order = orders[price][id];
        return Order(uint128(order & 0xffffffffffffffffffffffffffffffff), uint40(order >> 128 & 0xFFFFFFFFFF), uint40(order >> 168 & 0xFFFFFFFFFF), uint40(order >> 208 & 0xFFFFFFFFFF));
    }

    function getPriceLevel(uint256 price) external view returns (PriceLevel memory) {
        uint256 priceLevel = priceLevels[price];
        return PriceLevel(uint128(priceLevel & 0xffffffffffffffffffffffffffffffff), uint40(priceLevel >> 128 & 0xFFFFFFFFFF), uint40(priceLevel >> 168 & 0xFFFFFFFFFF), uint40(priceLevel >> 208 & 0xFFFFFFFFFF));
    }

    function getPriceLevels(bool isAscending, uint256 startPrice, uint256 distance, uint256 max) external view returns (bytes memory) {
        assembly {
            mstore(0x40, 0xa0)
        }
        _getPriceLevels(isAscending, startPrice, distance, max);
        assembly {
            mstore(0x80, 0x20)
            return(0x80, add(mload(0xa0), 0x40))
        }
    }

    function getPriceLevelsFromMid(uint256 distance, uint256 max) external view returns (uint256 _highestBid, uint256 _lowestAsk, bytes memory, bytes memory) {
        uint256 length;
        _highestBid = highestBid;
        _lowestAsk = lowestAsk;
        assembly {
            mstore(0x40, 0x100)
        }
        _getPriceLevels(false, _highestBid, distance, max);
        assembly {
            length := mload(0x100)
            mstore(0x40, add(length, 0x120))
        }
        _getPriceLevels(true, _lowestAsk, distance, max);
        assembly {
            mstore(0x80, _highestBid)
            mstore(0xa0, _lowestAsk)
            mstore(0xc0, 0x80)
            mstore(0xe0, add(0xa0, length))
            return(0x80, add(0xc0, add(length, mload(add(length, 0x120)))))
        }
    }

    function getDisplayPriceLevelsFromMid(uint256 distance, uint256 numLevels) external view returns (uint256 _highestBid, uint256 _lowestAsk, bytes memory, bytes memory) {
    }

    // done
    function getPrice() external view returns (uint256 price, uint256 _highestBid, uint256 _lowestAsk) {
        uint256 count;
        _highestBid = highestBid;
        _lowestAsk = lowestAsk;
        price = _highestBid;
        if (_lowestAsk != maxPrice) {
            price += _lowestAsk;
            ++count;
        }
        if (_highestBid != 0) {
            ++count;
        }
        if (count == 2) {
            price = (price + 1) >> 1;
        }
    }
    // done
    function getQuote(bool isBuy, bool isExactInput, uint256 size, uint256 worstPrice) external view returns (uint256 amountIn, uint256 amountOut) {
        unchecked {
            uint256 price;
            if (!isExactInput) {
                size = (size * 100000 + takerFee - 1) / takerFee;
            }
            if (isBuy) {
                uint256 _maxPrice = maxPrice;
                if (worstPrice >= _maxPrice) {
                    worstPrice = _maxPrice - 1;
                }
                price = lowestAsk;
            }
            else {
                if (worstPrice == 0) {
                    worstPrice = 1;
                }
                price = highestBid;
            }
            uint256 slotIndex = price >> 8;
            uint256 slot = activated[slotIndex];
            while (isExactInput ? size > amountIn : size > amountOut) {
                if (isBuy ? price > worstPrice : price < worstPrice) {
                    return (amountIn, amountOut * takerFee / 100000);
                }
                uint256 sizeLeft = isExactInput ? size - amountIn : size - amountOut;
                uint256 liquidity = priceLevels[price] & 0xffffffffffffffffffffffffffffffff;
                if ((isExactInput == isBuy) ? liquidity > sizeLeft * scaleFactor : liquidity > sizeLeft * price) {
                    amountOut += (isExactInput ? (isBuy ? sizeLeft * scaleFactor / price : sizeLeft * price / scaleFactor) : sizeLeft);
                    if (!isExactInput) {
                        sizeLeft = isBuy ? (sizeLeft * price + scaleFactor - 1) / scaleFactor : (sizeLeft * scaleFactor + price - 1) / price;
                    }
                    amountIn += sizeLeft;
                    sizeLeft = 0;
                }
                else {
                    amountIn += isBuy ? liquidity / scaleFactor : liquidity / price;
                    amountOut += isBuy ? liquidity / scaleFactor * scaleFactor / price : liquidity / price * price / scaleFactor;
                    sizeLeft -= isExactInput ? (isBuy ? liquidity / scaleFactor : liquidity / price) : (isBuy ? liquidity / scaleFactor * scaleFactor / price : liquidity / price * price / scaleFactor);
                    liquidity = 0;
                }
                if (liquidity == 0) {
                    slot &= ~(1 << (price % 256));
                    if (isBuy) {
                        uint256 _slot = slot >> price % 256;
                        while (_slot == 0) {
                            ++slotIndex;
                            slot = activated[slotIndex];
                            _slot = slot;
                            price = slotIndex << 8;
                        }
                        if (_slot & ((1 << 128) - 1) == 0) {_slot >>= 128; price += 128;}
                        if (_slot & ((1 << 64) - 1) == 0) {_slot >>= 64; price += 64;}
                        if (_slot & ((1 << 32) - 1) == 0) {_slot >>= 32; price += 32;}
                        if (_slot & ((1 << 16) - 1) == 0) {_slot >>= 16; price += 16;}
                        if (_slot & ((1 << 8) - 1) == 0) {_slot >>= 8; price += 8;}
                        if (_slot & ((1 << 4) - 1) == 0) {_slot >>= 4; price += 4;}
                        if (_slot & ((1 << 2) - 1) == 0) {_slot >>= 2; price += 2;}
                        if (_slot & 1 == 0) {++price;}
                    }
                    else {
                        uint256 _slot = slot & ((1 << (price % 256)) - 1);
                        while (_slot == 0) {
                            --slotIndex;
                            slot = activated[slotIndex];
                            _slot = slot;
                        }
                        price = slotIndex << 8;
                        if (_slot >= 2 ** 128) {_slot >>= 128; price += 128;}
                        if (_slot >= 2 ** 64) {_slot >>= 64; price += 64;}
                        if (_slot >= 2 ** 32) {_slot >>= 32; price += 32;}
                        if (_slot >= 2 ** 16) {_slot >>= 16; price += 16;}
                        if (_slot >= 2 ** 8) {_slot >>= 8; price += 8;}
                        if (_slot >= 2 ** 4) {_slot >>= 4; price += 4;}
                        if (_slot >= 2 ** 2) {_slot >>= 2; price += 2;}
                        if (_slot >= 2 ** 1) {++price;}
                    }
                }
                else {
                    break;
                }
            }
            return (amountIn, amountOut * takerFee / 100000);
        }
    }

    function _marketOrder(uint256 size, uint256 priceAndReferrer, uint256 orderInfo) internal returns (uint256 amountIn, uint256 amountOut, uint256 id, uint256 additionalSize) {
        unchecked {
            uint256 price;
            if (!((orderInfo >> 248 & 0xF) == 0)) {
                size = (size * 100000 + takerFee - 1) / takerFee;
            }
            if ((orderInfo >> 244 & 0xF) == 0) {
                uint256 _maxPrice = maxPrice;
                if (uint80(priceAndReferrer) >= _maxPrice) {
                    priceAndReferrer = (priceAndReferrer & 0xffffffffffffffffffffffffffffffffffffffffffff00000000000000000000) | (_maxPrice - 1);
                }
                price = lowestAsk;
            }
            else {
                if (uint80(priceAndReferrer) == 0) {
                    priceAndReferrer += 1;
                }
                price = highestBid;
            }
            uint256 position;
            assembly {
                position := add(mload(0x40), 0x60)
                mstore(position, 0x0)
                mstore(0x40, add(position, 0x20))
            }
            {
                uint256 tick = _priceToTick(price);
                uint256 slotIndex = tick >> 8;
                uint256 slot = activated[slotIndex];
                while (((orderInfo >> 248 & 0xF) == 0) ? size > amountIn : size > amountOut) {
                    if (((orderInfo >> 244 & 0xF) == 0) ? price > uint80(priceAndReferrer) : price < uint80(priceAndReferrer)) {
                        if ((orderInfo >> 252) == 1) {
                            revert SlippageExceeded();
                        }
                        if (activated[slotIndex] != slot) {
                            activated[slotIndex] = slot;
                        }
                        if ((orderInfo >> 252) == 2) {
                            ((orderInfo >> 244 & 0xF) == 0) ? lowestAsk = uint80(price) : highestBid = uint80(price);
                            slot = ((orderInfo >> 248 & 0xF) == 0) ? (size - amountIn) : (((orderInfo >> 244 & 0xF) == 0) ? ((size - amountOut) * uint80(priceAndReferrer) / scaleFactor) : ((size - amountOut) * scaleFactor / uint80(priceAndReferrer)));
                            slotIndex = orderInfo;
                            (slot, id) = _limitOrder(((orderInfo >> 244 & 0xF) == 0), uint80(priceAndReferrer), slot, addressToUserId[address(uint160(slotIndex))]);
                            additionalSize |= slot << 128;
                        }
                        break;
                    }
                    uint256 _priceLevel = priceLevels[price];
                    uint256 sizeLeft = ((orderInfo >> 248 & 0xF) == 0) ? size - amountIn : size - amountOut;
                    {
                        uint256 next = priceLevels[price] >> 128 & 0xFFFFFFFFFF;
                        uint256 _orderInfo = orderInfo;
                        while ((_priceLevel & 0xffffffffffffffffffffffffffffffff) != 0 && sizeLeft != 0 && !((_orderInfo >> 252) == 3 && gasleft() < 100000)) {
                            uint256 _order = orders[price][next];
                            address owner = userIdToAddress[_order >> 128 & 0xFFFFFFFFFF];
                            if ((_orderInfo >> 240 & 0xF) != 0 && owner == address(uint160(_orderInfo))) {
                                if ((_orderInfo >> 240 & 0xF) == 1) {
                                    delete orders[price][next];
                                    _priceLevel -= (_order & 0xffffffffffffffffffffffffffffffff);
                                    if ((_orderInfo >> 244 & 0xF) == 0) {
                                        additionalSize += ((_order & 0xffffffffffffffffffffffffffffffff) / price);
                                    }
                                    else {
                                        additionalSize += ((_order & 0xffffffffffffffffffffffffffffffff) / scaleFactor);
                                    }
                                    emit OrdersUpdated(owner, abi.encodePacked(0x3000000000000000000000000000000000000000000000000000000000000000  | (price << 168) | (next << 128) | (_order & 0xffffffffffffffffffffffffffffffff)));
                                    next = _order >> 208 & 0xFFFFFFFFFF;
                                    continue;
                                }
                                else if ((_orderInfo >> 240 & 0xF) == 2) {
                                    sizeLeft = 0;
                                    break;
                                }
                                else if ((_orderInfo >> 240 & 0xF) == 3) {
                                    delete orders[price][next];
                                    _priceLevel -= (_order & 0xffffffffffffffffffffffffffffffff);
                                    if ((_orderInfo >> 244 & 0xF) == 0) {
                                        additionalSize += ((_order & 0xffffffffffffffffffffffffffffffff) / price);
                                    }
                                    else {
                                        additionalSize += ((_order & 0xffffffffffffffffffffffffffffffff) / scaleFactor);
                                    }
                                    emit OrdersUpdated(owner, abi.encodePacked(0x3000000000000000000000000000000000000000000000000000000000000000  | (price << 168) | (next << 128) | (_order & 0xffffffffffffffffffffffffffffffff)));
                                    next = _order >> 208 & 0xFFFFFFFFFF;
                                    sizeLeft = 0;
                                    break;
                                }
                            }
                            if (((_orderInfo >> 248 & 0xF) == (_orderInfo >> 244 & 0xF)) ? (_order & 0xffffffffffffffffffffffffffffffff) > sizeLeft * scaleFactor : (_order & 0xffffffffffffffffffffffffffffffff) > sizeLeft * price) {
                                amountOut += (((_orderInfo >> 248 & 0xF) == 0) ? (((_orderInfo >> 244 & 0xF) == 0) ? sizeLeft * scaleFactor / price : sizeLeft * price / scaleFactor) : sizeLeft);
                                if (!((_orderInfo >> 248 & 0xF) == 0)) {
                                    sizeLeft = ((_orderInfo >> 244 & 0xF) == 0) ? (sizeLeft * price + scaleFactor - 1) / scaleFactor : (sizeLeft * scaleFactor + price - 1) / price;
                                }
                                amountIn += sizeLeft;
                                uint256 temp = ((_orderInfo >> 244 & 0xF) == 0) ? sizeLeft * scaleFactor : sizeLeft * price;
                                _priceLevel -= temp;
                                _order -= temp;
                                orders[price][next] = _order;
                                IERC20(((_orderInfo >> 244 & 0xF) == 0) ? quoteAsset : baseAsset).transferFrom((_orderInfo >> 236 & 0x1) == 0 ? address(uint160(_orderInfo)) : msg.sender, owner, sizeLeft);
                                sizeLeft = 0;
                                assembly {
                                    let length := mload(position)
                                    mstore(add(length, add(position, 0x20)), or(shl(168, price), or(shl(128, next), and(0xffffffffffffffffffffffffffffffff, _order))))
                                    mstore(position, add(length, 0x20))
                                    mstore(0x40, add(length, add(position, 0x40)))
                                }
                            }
                            else {
                                amountIn += ((_orderInfo >> 244 & 0xF) == 0) ? (_order & 0xffffffffffffffffffffffffffffffff) / scaleFactor : (_order & 0xffffffffffffffffffffffffffffffff) / price;
                                amountOut += ((_orderInfo >> 244 & 0xF) == 0) ? (_order & 0xffffffffffffffffffffffffffffffff) / scaleFactor * scaleFactor / price : (_order & 0xffffffffffffffffffffffffffffffff) / price * price / scaleFactor;
                                _priceLevel -= (_order & 0xffffffffffffffffffffffffffffffff);
                                sizeLeft -= ((_orderInfo >> 248 & 0xF) == 0) ? (((_orderInfo >> 244 & 0xF) == 0) ? (_order & 0xffffffffffffffffffffffffffffffff) / scaleFactor : (_order & 0xffffffffffffffffffffffffffffffff) / price) : (((_orderInfo >> 244 & 0xF) == 0) ? (_order & 0xffffffffffffffffffffffffffffffff) / scaleFactor * scaleFactor / price : (_order & 0xffffffffffffffffffffffffffffffff) / price * price / scaleFactor);
                                uint256 transferAmount = (_order & 0xffffffffffffffffffffffffffffffff) / (((_orderInfo >> 244 & 0xF) == 0) ? scaleFactor : price);
                                IERC20(((_orderInfo >> 244 & 0xF) == 0) ? quoteAsset : baseAsset).transferFrom((_orderInfo >> 236 & 0x1) == 0 ? address(uint160(_orderInfo)) : msg.sender, owner, transferAmount);
                                assembly {
                                    let length := mload(position)
                                    mstore(add(length, add(position, 0x20)), or(shl(168, price), shl(128, next)))
                                    mstore(position, add(length, 0x20))
                                    mstore(0x40, add(length, add(position, 0x40)))
                                }
                                delete orders[price][next];
                                next = _order >> 208 & 0xFFFFFFFFFF;
                            }
                        }
                        priceLevels[price] = _priceLevel & 0xffffffffffffffffffffff0000000000ffffffffffffffffffffffffffffffff | (next << 128);
                    }
                    if ((_priceLevel & 0xffffffffffffffffffffffffffffffff) == 0) {
                        slot &= ~(1 << (tick % 256));
                        if ((orderInfo >> 244 & 0xF) == 0) {
                            uint256 _slot = slot >> tick % 256;
                            if (_slot == 0 && activated[slotIndex] != slot) {
                                activated[slotIndex] = slot;
                            }
                            while (_slot == 0) {
                                ++slotIndex;
                                slot = activated[slotIndex];
                                _slot = slot;
                                tick = slotIndex << 8;
                            }
                            if (_slot & ((1 << 128) - 1) == 0) {_slot >>= 128; tick += 128;}
                            if (_slot & ((1 << 64) - 1) == 0) {_slot >>= 64; tick += 64;}
                            if (_slot & ((1 << 32) - 1) == 0) {_slot >>= 32; tick += 32;}
                            if (_slot & ((1 << 16) - 1) == 0) {_slot >>= 16; tick += 16;}
                            if (_slot & ((1 << 8) - 1) == 0) {_slot >>= 8; tick += 8;}
                            if (_slot & ((1 << 4) - 1) == 0) {_slot >>= 4; tick += 4;}
                            if (_slot & ((1 << 2) - 1) == 0) {_slot >>= 2; tick += 2;}
                            if (_slot & 1 == 0) {++tick;}
                        }
                        else {
                            uint256 _slot = slot & ((1 << (tick % 256)) - 1);
                            if (_slot == 0 && activated[slotIndex] != slot) {
                                activated[slotIndex] = slot;
                            }
                            while (_slot == 0) {
                                --slotIndex;
                                slot = activated[slotIndex];
                                _slot = slot;
                            }
                            tick = slotIndex << 8;
                            if (_slot >= 2 ** 128) {_slot >>= 128; tick += 128;}
                            if (_slot >= 2 ** 64) {_slot >>= 64; tick += 64;}
                            if (_slot >= 2 ** 32) {_slot >>= 32; tick += 32;}
                            if (_slot >= 2 ** 16) {_slot >>= 16; tick += 16;}
                            if (_slot >= 2 ** 8) {_slot >>= 8; tick += 8;}
                            if (_slot >= 2 ** 4) {_slot >>= 4; tick += 4;}
                            if (_slot >= 2 ** 2) {_slot >>= 2; tick += 2;}
                            if (_slot >= 2 ** 1) {++tick;}
                        }
                        price = _tickToPrice(tick);
                    }
                    else {
                        if (activated[slotIndex] != slot) {
                            activated[slotIndex] = slot;
                        }
                    }
                    if (sizeLeft == 0 || ((orderInfo >> 252) == 3 && gasleft() < 100000)) {
                        break;
                    }
                }
            }
            if (amountOut != 0) {
                uint256 amountOutAfter = amountOut * takerFee / 100000;
                uint256 feeAmount = amountOut - amountOutAfter;
                if ((orderInfo >> 244 & 0xF) == 0) {
                    if (address(uint160(priceAndReferrer >> 80)) == address(0)) {
                        accumulatedFeeBase[gov] += feeAmount;
                    }
                    else {
                        uint256 amountCommission = feeAmount * feeCommission / 100;
                        accumulatedFeeBase[address(uint160(priceAndReferrer >> 80))] += amountCommission;
                        uint256 amountRebate = feeAmount * feeRebate / 100;
                        accumulatedFeeBase[address(uint160(orderInfo))] += amountRebate;
                        accumulatedFeeBase[gov] += (feeAmount - amountCommission - amountRebate);
                    }
                    lowestAsk = uint80(price);
                    assembly {
                        let length := mload(position)
                        mstore(sub(position, 0x60), or(shl(128, amountIn), amountOutAfter))
                        mstore(sub(position, 0x40), or(0x1000000000000000000000000000000000000000000000000000000000000000, or(shl(128, shr(176, mload(add(position, 0x20)))), shr(176, mload(add(position, length))))))
                        mstore(sub(position, 0x20), 0x60)
                        log2(sub(position, 0x60), add(length, 0x80), 0xc3bcf95b5242764f3f2dc3e504ce05823a3b50c4ccef5e660d13beab2f51f2ca, and(0xffffffffffffffffffffffffffffffffffffffff, orderInfo))
                    }
                }
                else {
                    if (address(uint160(priceAndReferrer >> 80)) == address(0)) {
                        accumulatedFeeQuote[gov] += feeAmount;
                    }
                    else {
                        uint256 amountCommission = feeAmount * feeCommission / 100;
                        accumulatedFeeQuote[address(uint160(priceAndReferrer >> 80))] += amountCommission;
                        uint256 amountRebate = feeAmount * feeRebate / 100;
                        accumulatedFeeQuote[address(uint160(orderInfo))] += amountRebate;
                        accumulatedFeeQuote[gov] += (feeAmount - amountCommission - amountRebate);
                    }
                    highestBid = uint80(price);
                    assembly {
                        let length := mload(position)
                        mstore(sub(position, 0x60), or(shl(128, amountIn), amountOutAfter))
                        mstore(sub(position, 0x40), or(shl(128, shr(176, mload(add(position, 0x20)))), shr(176, mload(add(position, length)))))
                        mstore(sub(position, 0x20), 0x60)
                        log2(sub(position, 0x60), add(length, 0x80), 0xc3bcf95b5242764f3f2dc3e504ce05823a3b50c4ccef5e660d13beab2f51f2ca, and(0xffffffffffffffffffffffffffffffffffffffff, orderInfo))
                    }
                }
                return (amountIn, amountOutAfter, id, additionalSize);
            }
            else {
                return (0, 0, id, additionalSize);
            }
        }
    }

    function _limitOrder(bool isBuy, uint256 price, uint256 size, uint256 userId) internal returns (uint256 _size, uint256 id) {
        unchecked {
            (uint256 _highestBid, uint256 _lowestAsk) = (highestBid, lowestAsk);
            if (isBuy) {
                if (price >= _lowestAsk || price == 0 || size < minSize || userId == 0) {
                    return (0, 0);
                }
                if (price > _highestBid) {
                    highestBid = uint80(price);
                }
                size *= scaleFactor;
            }
            else {
                size *= price;
                if (price <= _highestBid || price >= maxPrice || (size / scaleFactor) < minSize || userId == 0) {
                    return (0, 0);
                }
                if (price < _lowestAsk) {
                    lowestAsk = uint80(price);
                }
            }
            require(size <= type(uint128).max);
            uint256 _priceLevel = priceLevels[price];
            if ((_priceLevel >> 128 & 0xFFFFFFFFFF) == 0) {
                _priceLevel |= 0x0000000000000000000000000000000100000000000000000000000000000000;
            }
            if ((_priceLevel & 0xffffffffffffffffffffffffffffffff) == 0) {
                uint256 tick = _priceToTick(price);
                activated[tick >> 8] |= (1 << (tick % 256));
            }
            id = (_priceLevel >> 208 & 0xFFFFFFFFFF) + 1;
            orders[price][id] = ((id+1) << 208) | (_priceLevel & 0x000000000000ffffffffff000000000000000000000000000000000000000000) | (userId << 128) | size;
            priceLevels[price] = (id << 208) | (id << 168) | ((_priceLevel & 0x0000000000000000000000ffffffffffffffffffffffffffffffffffffffffff) + size);
            return (size, id);        
        }       
    }

    function _cancelOrder(uint256 price, uint256 id, uint256 userId) internal returns (uint256 size, bool isBuy) {
        unchecked {
            uint256 _order = orders[price][id];
            size = (_order & 0xffffffffffffffffffffffffffffffff);
            if (0 == size || userId != (_order >> 128 & 0xFFFFFFFFFF)) {
                return (size, isBuy);
            }
            delete orders[price][id];
            (uint256 _highestBid, uint256 _lowestAsk) = (highestBid, lowestAsk);
            if (price <= _highestBid) {
                isBuy = true;
            }
            else {
                isBuy = false;
            }
            uint256 _priceLevel = priceLevels[price];
            _priceLevel -= size;
            if (id == (_priceLevel >> 128 & 0xFFFFFFFFFF)) {
                _priceLevel = _priceLevel & 0xffffffffffffffffffffff0000000000ffffffffffffffffffffffffffffffff | (_order >> 80 & 0x0000000000000000000000ffffffffff00000000000000000000000000000000);
            }
            else if (id == (_priceLevel >> 168 & 0xFFFFFFFFFF)) {
                uint256 _id = _order >> 168 & 0xFFFFFFFFFF;
                orders[price][_id] = orders[price][_id] & 0xff0000000000ffffffffffffffffffffffffffffffffffffffffffffffffffff | (_order & 0x00ffffffffff0000000000000000000000000000000000000000000000000000);
                _priceLevel = _priceLevel & 0xffffffffffff0000000000ffffffffffffffffffffffffffffffffffffffffff | (_order & 0x000000000000ffffffffff000000000000000000000000000000000000000000);
            }
            else {                
                uint256 _id = _order >> 168 & 0xFFFFFFFFFF;
                orders[price][_id] = orders[price][_id] & 0xff0000000000ffffffffffffffffffffffffffffffffffffffffffffffffffff | (_order & 0x00ffffffffff0000000000000000000000000000000000000000000000000000);
                _id = _order >> 208 & 0xFFFFFFFFFF;
                orders[price][_id] = orders[price][_id] & 0xffffffffffff0000000000ffffffffffffffffffffffffffffffffffffffffff | (_order & 0x000000000000ffffffffff000000000000000000000000000000000000000000);
            }
            priceLevels[price] = _priceLevel;
            if ((_priceLevel & 0xffffffffffffffffffffffffffffffff) == 0) {
                uint256 tick = _priceToTick(price);
                uint256 slotIndex = tick >> 8;
                uint256 _slot = activated[slotIndex];
                _slot &= ~(1 << (tick % 256));
                activated[slotIndex] = _slot;
                if (price == _lowestAsk) {
                    _slot = _slot >> tick % 256;
                    while (_slot == 0) {
                        ++slotIndex;
                        _slot = activated[slotIndex];
                        tick = slotIndex << 8;
                    }
                    if (_slot & ((1 << 128) - 1) == 0) {_slot >>= 128; tick += 128;}
                    if (_slot & ((1 << 64) - 1) == 0) {_slot >>= 64; tick += 64;}
                    if (_slot & ((1 << 32) - 1) == 0) {_slot >>= 32; tick += 32;}
                    if (_slot & ((1 << 16) - 1) == 0) {_slot >>= 16; tick += 16;}
                    if (_slot & ((1 << 8) - 1) == 0) {_slot >>= 8; tick += 8;}
                    if (_slot & ((1 << 4) - 1) == 0) {_slot >>= 4; tick += 4;}
                    if (_slot & ((1 << 2) - 1) == 0) {_slot >>= 2; tick += 2;}
                    if (_slot & 1 == 0) {++tick;}
                    lowestAsk = uint80(_tickToPrice(tick));
                }
                else if (price == _highestBid) {
                    _slot = _slot & ((1 << (tick % 256)) - 1);
                    while (_slot == 0) {
                        --slotIndex;
                        _slot = activated[slotIndex];
                    }
                    tick = slotIndex << 8;
                    if (_slot >= 2 ** 128) {_slot >>= 128; tick += 128;}
                    if (_slot >= 2 ** 64) {_slot >>= 64; tick += 64;}
                    if (_slot >= 2 ** 32) {_slot >>= 32; tick += 32;}
                    if (_slot >= 2 ** 16) {_slot >>= 16; tick += 16;}
                    if (_slot >= 2 ** 8) {_slot >>= 8; tick += 8;}
                    if (_slot >= 2 ** 4) {_slot >>= 4; tick += 4;}
                    if (_slot >= 2 ** 2) {_slot >>= 2; tick += 2;}
                    if (_slot >= 2 ** 1) {++tick;}
                    highestBid = uint80(_tickToPrice(tick));
                }
            }
            return (size, isBuy);
        }
    }

    function _decreaseOrder(uint256 price, uint256 id, uint256 decreaseAmount, uint256 userId) internal returns (uint256 newSize, uint256 decreaseSize, bool isBuy) {
        unchecked {
            uint256 _order = orders[price][id];
            if (userId != (_order >> 128 & 0xFFFFFFFFFF)) {
                return (0, 0, isBuy);
            }
            uint256 size = (_order & 0xffffffffffffffffffffffffffffffff);
            (uint256 _highestBid, uint256 _lowestAsk) = (highestBid, lowestAsk);
            if (price <= _highestBid) {
                isBuy = true;
                decreaseAmount *= scaleFactor;
            }
            else {
                isBuy = false;
                decreaseAmount *= price;
            }
            if (size <= decreaseAmount + (minSize * scaleFactor)) {
                delete orders[price][id];
                uint256 _priceLevel = priceLevels[price];
                _priceLevel -= size;
                if (id == (_priceLevel >> 128 & 0xFFFFFFFFFF)) {
                    _priceLevel = _priceLevel & 0xffffffffffffffffffffff0000000000ffffffffffffffffffffffffffffffff | (_order >> 80 & 0x0000000000000000000000ffffffffff00000000000000000000000000000000);
                }
                else if (id == (_priceLevel >> 168 & 0xFFFFFFFFFF)) {
                    orders[price][_order >> 168 & 0xFFFFFFFFFF] = orders[price][_order >> 168 & 0xFFFFFFFFFF] & 0xff0000000000ffffffffffffffffffffffffffffffffffffffffffffffffffff | (_order & 0x00ffffffffff0000000000000000000000000000000000000000000000000000);
                    _priceLevel = _priceLevel & 0xffffffffffff0000000000ffffffffffffffffffffffffffffffffffffffffff | (_order & 0x000000000000ffffffffff000000000000000000000000000000000000000000);
                }
                else {
                    orders[price][_order >> 168 & 0xFFFFFFFFFF] = orders[price][_order >> 168 & 0xFFFFFFFFFF] & 0xff0000000000ffffffffffffffffffffffffffffffffffffffffffffffffffff | (_order & 0x00ffffffffff0000000000000000000000000000000000000000000000000000);
                    orders[price][_order >> 208 & 0xFFFFFFFFFF] = orders[price][_order >> 208 & 0xFFFFFFFFFF] & 0xffffffffffff0000000000ffffffffffffffffffffffffffffffffffffffffff | (_order & 0x000000000000ffffffffff000000000000000000000000000000000000000000);
                }
                priceLevels[price] = _priceLevel;
                if ((_priceLevel & 0xffffffffffffffffffffffffffffffff) == 0) {
                    uint256 tick = _priceToTick(price);
                    uint256 slotIndex = tick >> 8;
                    uint256 _slot = activated[slotIndex];
                    _slot &= ~(1 << (tick % 256));
                    activated[slotIndex] = _slot;
                    if (price == _lowestAsk) {
                        _slot = _slot >> tick % 256;
                        while (_slot == 0) {
                            ++slotIndex;
                            _slot = activated[slotIndex];
                            tick = slotIndex << 8;
                        }
                        if (_slot & ((1 << 128) - 1) == 0) {_slot >>= 128; tick += 128;}
                        if (_slot & ((1 << 64) - 1) == 0) {_slot >>= 64; tick += 64;}
                        if (_slot & ((1 << 32) - 1) == 0) {_slot >>= 32; tick += 32;}
                        if (_slot & ((1 << 16) - 1) == 0) {_slot >>= 16; tick += 16;}
                        if (_slot & ((1 << 8) - 1) == 0) {_slot >>= 8; tick += 8;}
                        if (_slot & ((1 << 4) - 1) == 0) {_slot >>= 4; tick += 4;}
                        if (_slot & ((1 << 2) - 1) == 0) {_slot >>= 2; tick += 2;}
                        if (_slot & 1 == 0) {++tick;}
                        lowestAsk = uint80(_tickToPrice(tick));
                    }
                    else if (price == _highestBid) {
                        _slot = _slot & ((1 << (tick % 256)) - 1);
                        while (_slot == 0) {
                            --slotIndex;
                            _slot = activated[slotIndex];
                        }
                        tick = slotIndex << 8;
                        if (_slot >= 2 ** 128) {_slot >>= 128; tick += 128;}
                        if (_slot >= 2 ** 64) {_slot >>= 64; tick += 64;}
                        if (_slot >= 2 ** 32) {_slot >>= 32; tick += 32;}
                        if (_slot >= 2 ** 16) {_slot >>= 16; tick += 16;}
                        if (_slot >= 2 ** 8) {_slot >>= 8; tick += 8;}
                        if (_slot >= 2 ** 4) {_slot >>= 4; tick += 4;}
                        if (_slot >= 2 ** 2) {_slot >>= 2; tick += 2;}
                        if (_slot >= 2 ** 1) {++tick;}
                        highestBid = uint80(_tickToPrice(tick));
                    }
                }
                return (0, size, isBuy);
            }
            else {
                orders[price][id] -= decreaseAmount;
                priceLevels[price] -= decreaseAmount;
                return (size - decreaseAmount, decreaseAmount, isBuy);
            }
        }
    }

    function marketOrder(bool isBuy, bool isExactInput, uint256 STP, uint256 orderType, uint256 size, uint256 worstPrice, address caller, address referrer) external returns (uint256 amountIn, uint256 amountOut, uint256 id) {
        unchecked {
            require((caller == msg.sender || router == msg.sender) && lock == 1);
            lock = 2;
            uint256 orderFlags = (orderType << 252) | (isExactInput ? 0 : 1 << 248) | (isBuy ? 0 : 1 << 244) | ((STP & 0xF) << 240);
            uint256 orderInfo = orderFlags | ((STP & 0xF00) << 228) | uint160(caller);
            uint256 additionalSize;
            (amountIn, amountOut, id, additionalSize) = _marketOrder(size, (uint160(referrer) << 80) | worstPrice, orderInfo);
            if (isBuy && (additionalSize >> 128) > 0) {
                IERC20(quoteAsset).transferFrom((STP >> 8) != 0 ? msg.sender : caller, address(this), (additionalSize >> 128) / scaleFactor);
                emit OrdersUpdated(caller, abi.encodePacked(0x1000000000000000000000000000000000000000000000000000000000000000 | (worstPrice << 168) | (id << 128) | (additionalSize >> 128)));
            }
            else if ((additionalSize >> 128) > 0) {
                IERC20(baseAsset).transferFrom((STP >> 8) != 0 ? msg.sender : caller, address(this), (additionalSize >> 128) / worstPrice);
                emit OrdersUpdated(caller, abi.encodePacked((worstPrice << 168) | (id << 128) | (additionalSize >> 128)));
            }
            additionalSize &= 0xffffffffffffffffffffffffffffffff;
            additionalSize += amountOut;
            if (isBuy && additionalSize > 0) {
                IERC20(baseAsset).transfer(((STP >> 4) & 0xF) != 0 ? msg.sender : caller, additionalSize);
            }
            else if (additionalSize > 0) {
                IERC20(quoteAsset).transfer(((STP >> 4) & 0xF) != 0 ? msg.sender : caller, additionalSize);
            }
            lock = 1;
        }
    }
    // done
    function limitOrder(bool isBuy, uint256 price, uint256 size, address caller) external returns (uint256 id) {
        unchecked {
            require((caller == msg.sender || router == msg.sender) && lock == 1);
            lock = 2;
            (size, id) = _limitOrder(isBuy, price, size, addressToUserId[caller]);
            if (size > 0) {
                if (isBuy) {
                    IERC20(quoteAsset).transferFrom((price >> 80) != 0 ? msg.sender : caller, address(this), size / scaleFactor);
                    emit OrdersUpdated(caller, abi.encodePacked(0x1000000000000000000000000000000000000000000000000000000000000000 | (price << 168) | (id << 128) | size));
                }
                else {
                    IERC20(baseAsset).transferFrom((price >> 80) != 0 ? msg.sender : caller, address(this), size / price);
                    emit OrdersUpdated(caller, abi.encodePacked((price << 168) | (id << 128) | size));
                }
            }
            lock = 1;
        }
    }
    // done
    function cancelOrder(uint256 price, uint256 id, address caller) external returns (uint256 size) {
        unchecked {
            require((caller == msg.sender || router == msg.sender) && lock == 1);
            lock = 2;
            bool isBuy;
            (size, isBuy) = _cancelOrder(price, id, addressToUserId[caller]);  
            if (size > 0) {
                if (isBuy) {
                    IERC20(quoteAsset).transfer((price >> 80) != 0 ? msg.sender : caller, size / scaleFactor);
                    emit OrdersUpdated(caller, abi.encodePacked(0x3000000000000000000000000000000000000000000000000000000000000000  | (price << 168) | (id << 128) | size));
                }
                else {
                    IERC20(baseAsset).transfer((price >> 80) != 0 ? msg.sender : caller, size / price);
                    emit OrdersUpdated(caller, abi.encodePacked(0x2000000000000000000000000000000000000000000000000000000000000000  | (price << 168) | (id << 128) | size));
                }
            }
            lock = 1;
        }
    }

    /* function amendOrder(bool postOnly, uint256 price, uint256 id, uint256 newPrice, uint256 newSize, address owner, address referrer) external returns (uint256 newId) {
        require((owner == msg.sender || router == msg.sender) && lock == 1);
        lock = 2;
        uint256 size;
        uint256 userId = addressToUserId[owner];
        bool isBuy;
        (size, isBuy) = _cancelOrder(price, id, userId);
        if (size == 0) {
            revert ActionFailed();
        }
        if (newSize == 0) {
            if (postOnly) {
                newId = _limitOrder(isBuy, newPrice, isBuy ? (size / scaleFactor) : (size / newPrice), userId);
                if (newId == 0) {
                    revert ActionFailed();
                }
            }
            else {
                (, newSize, id, size) = _marketOrder(isBuy ? (size / scaleFactor) : (size / newPrice), (uint160(referrer) << 80) | price, (2 << 252) | (1 << 240) | ((referrer >> 160 & 0xF) << 236) | uint160(owner));
                if (newSize == 0 && id == 0) {
                    revert ActionFailed();
                }
            }
        }
        else {
            if (newSize > size) {
                IERC20(tokenIn == ETH ? WETH : tokenIn).transfer(msg.sender, balance);
            }
            if (postOnly) {
                id = ICrystalMarket(market).limitOrder(ICrystalMarket(market).quoteAsset() == (tokenIn == ETH ? WETH : tokenIn), newPrice, newSize, newSize > balance ? msg.sender : address(this), msg.sender);
                if (id == 0) {
                    revert OrderFailed();
                }
            }
            else {
                (, balance, id) = ICrystalMarket(market).marketOrder(ICrystalMarket(market).quoteAsset() == (tokenIn == ETH ? WETH : tokenIn), true, newSize > balance ? true : false, true, 2, newSize, newPrice, msg.sender, referrer);
                if (balance == 0 && id == 0) {
                    revert OrderFailed();
                }
            }
        }
        balance = IERC20(tokenIn == ETH ? WETH : tokenIn).balanceOf(address(this));
        if (balance != 0) {
            IERC20(tokenIn == ETH ? WETH : tokenIn).transfer(msg.sender, balance);   
        }
        lock = 1; 
    } */

    function changeParams(address newGov, uint80 newMaxPrice, uint256 newMinSize, uint24 newTakerFee, uint24 newMakerRebate, uint8 newFeeCommission, uint8 newFeeRebate) external {
        require(msg.sender == gov && 90000 <= newTakerFee && newTakerFee <= 100000 && newMakerRebate <= 100000 && newMakerRebate > newTakerFee && (newFeeCommission + newFeeRebate) < 100 && newMaxPrice <= 0xffffffffffffffffffff);
        if (newGov != gov) {
            gov = newGov;
        }
        if (newMaxPrice != maxPrice) {
            if (lowestAsk == maxPrice) {
                lowestAsk = newMaxPrice;
            }
            activated[maxPrice >> 8] &= ~(1 << (maxPrice % 256));
            activated[newMaxPrice >> 8] = (1 << (newMaxPrice % 256));
            maxPrice = newMaxPrice;
        }
        if (newMinSize != minSize) {

        }
        if (newTakerFee != takerFee) {
            takerFee = newTakerFee;
        }
        if (newMakerRebate != makerRebate) {
            makerRebate = newMakerRebate;
        }
        if (newFeeCommission != feeCommission) {
            feeCommission = newFeeCommission;
        }
        if (newFeeRebate != feeRebate) {
            feeRebate = newFeeRebate;
        }
        emit ParamsChanged(address(this), newGov, newMaxPrice, newMinSize, newTakerFee, newMakerRebate, newFeeCommission, newFeeRebate);
    }
    // done
    function registerUser(address caller) external returns (uint256 _latestUserId) {
        require((caller == msg.sender || router == msg.sender) && (addressToUserId[caller] == 0));
        _latestUserId = latestUserId;
        _latestUserId++;
        addressToUserId[caller] = _latestUserId;
        userIdToAddress[_latestUserId] = caller;
        latestUserId = _latestUserId;
    }
    // done
    function claimFees(address caller) external returns (uint256 quoteAmount, uint256 baseAmount) {
        require(caller == msg.sender || router == msg.sender);
        quoteAmount = accumulatedFeeQuote[caller];
        baseAmount = accumulatedFeeBase[caller];
        accumulatedFeeQuote[caller] = 0;
        accumulatedFeeBase[caller] = 0;
        IERC20(quoteAsset).transfer(caller, quoteAmount);
        IERC20(baseAsset).transfer(caller, baseAmount);
        emit RewardsClaimed(caller, quoteAmount, baseAmount);
    }

    function batchOrders(uint256[] calldata actions, uint256[] calldata prices, uint256[] calldata param1, address owner, uint256 referrer) external returns (uint256[] memory returnData) {
        unchecked {
            require((owner == msg.sender || router == msg.sender) && lock == 1);
            lock = 2;
            returnData = new uint256[](actions.length);
            uint256 position;
            assembly {
                position := add(mload(0x40), 0x20)
                mstore(position, 0x0)
                mstore(0x40, add(position, 0x20))
            }
            uint256 userId = addressToUserId[owner];
            int256 quoteAssetDebt;
            int256 baseAssetDebt;
            uint256 flag;
            for (uint256 i = 0; i < actions.length; ++i) {
                if (actions[i] == 0) {
                    bool isBuy;
                    uint256 price = prices[i];
                    uint256 p1 = param1[i];
                    (returnData[i], isBuy) = _cancelOrder(price, p1, userId);
                    if (returnData[i] > 0) {
                        if (isBuy) {
                            quoteAssetDebt -= int256(returnData[i] / scaleFactor);
                        }
                        else {
                            baseAssetDebt -= int256(returnData[i] / price);
                        }
                        assembly {
                            let length := mload(position)
                            mstore(add(length, add(position, 0x20)), or(add(0x2000000000000000000000000000000000000000000000000000000000000000,mul(0x1000000000000000000000000000000000000000000000000000000000000000,isBuy)),or(shl(168,price),or(shl(128,p1),mload(add(add(returnData, 0x20), mul(i, 0x20)))))))
                            mstore(position, add(length, 0x20))
                            mstore(0x40, add(length, add(position, 0x40)))
                        }
                    }
                }
                else if (actions[i] == 1) {
                    uint256 size;
                    uint256 price = prices[i];
                    (size, returnData[i]) = _limitOrder(true, price, param1[i], userId);
                    if (size > 0) {
                        quoteAssetDebt += int256(size / scaleFactor);
                        assembly {
                            flag := or(flag, 1)
                            let length := mload(position)
                            mstore(add(length, add(position, 0x20)), or(or(or(0x1000000000000000000000000000000000000000000000000000000000000000, shl(168, price)), shl(128, mload(add(add(returnData, 0x20), mul(i, 0x20))))), size))
                            mstore(position, add(length, 0x20))
                            mstore(0x40, add(length, add(position, 0x40)))
                        }
                    }
                }
                else if (actions[i] == 2) {
                    uint256 size;
                    uint256 price = prices[i];
                    (size, returnData[i]) = _limitOrder(false, price, param1[i], userId);
                    if (size > 0) {
                        baseAssetDebt += int256(size / price);
                        assembly {
                            flag := or(flag, 2)
                            let length := mload(position)
                            mstore(add(length, add(position, 0x20)), or(or(shl(168, price), shl(128, mload(add(add(returnData, 0x20), mul(i, 0x20))))), size))
                            mstore(position, add(length, 0x20))
                            mstore(0x40, add(length, add(position, 0x40)))
                        }
                    }
                }
                else if (actions[i] == 3 && (flag & 2 == 0)) {
                    uint256 additionalSize;
                    uint256 price = prices[i];
                    ( , returnData[i], , additionalSize) = _marketOrder(param1[i], (uint160(referrer) << 80) | price, (1 << 240) | ((referrer >> 160 & 0xF) << 236) | uint160(owner));
                    baseAssetDebt -= int256(returnData[i] + additionalSize);
                }
                else if (actions[i] == 4 && (flag & 1 == 0)) {
                    uint256 additionalSize;
                    uint256 price = prices[i];
                    ( , returnData[i], , additionalSize) = _marketOrder(param1[i], (uint160(referrer) << 80) | price, (1 << 244) | (1 << 240) | ((referrer >> 164 & 0xF) << 236) | uint160(owner));
                    quoteAssetDebt -= int256(returnData[i] + additionalSize);
                }
                else if (actions[i] == 5 && (flag & 2 == 0)) {
                    uint256 additionalSize;
                    uint256 price = prices[i];
                    ( , returnData[i], price, additionalSize) = _marketOrder(param1[i], (uint160(referrer) << 80) | price, (2 << 252) | (1 << 240) | ((referrer >> 160 & 0xF) << 236) | uint160(owner));
                    baseAssetDebt -= int256(returnData[i] + (additionalSize & 0xffffffffffffffffffffffffffffffff));
                    if (price > 0) {
                        uint256 _price = prices[i];
                        additionalSize = (additionalSize >> 128);
                        quoteAssetDebt += int256(additionalSize / scaleFactor);
                        assembly {
                            flag := or(flag, 1)
                            let length := mload(position)
                            mstore(add(length, add(position, 0x20)), or(or(or(0x1000000000000000000000000000000000000000000000000000000000000000, shl(168, _price)), shl(128, price)), additionalSize))
                            mstore(position, add(length, 0x20))
                            mstore(0x40, add(length, add(position, 0x40)))
                        }
                    }
                }
                else if (actions[i] == 6 && (flag & 1 == 0)) {
                    uint256 additionalSize;
                    uint256 price = prices[i];
                    ( , returnData[i], price, additionalSize) = _marketOrder(param1[i], (uint160(referrer) << 80) | price, (2 << 252) | (1 << 244) | (1 << 240) | ((referrer >> 164 & 0xF) << 236) | uint160(owner));
                    quoteAssetDebt -= int256(returnData[i] + (additionalSize & 0xffffffffffffffffffffffffffffffff));
                    if (price > 0) {
                        uint256 _price = prices[i];
                        additionalSize = (additionalSize >> 128);
                        baseAssetDebt += int256(additionalSize / _price);
                        assembly {
                            flag := or(flag, 2)
                            let length := mload(position)
                            mstore(add(length, add(position, 0x20)), or(or(shl(168, _price), shl(128, price)), additionalSize))
                            mstore(position, add(length, 0x20))
                            mstore(0x40, add(length, add(position, 0x40)))
                        }
                    }
                }
                else if (actions[i] == 7 && (flag & 2 == 0)) {
                    uint256 additionalSize;
                    uint256 price = prices[i];
                    ( , returnData[i], , additionalSize) = _marketOrder(param1[i], (uint160(referrer) << 80) | price, (3 << 252) | (1 << 240) | ((referrer >> 160 & 0xF) << 236) | uint160(owner));
                    baseAssetDebt -= int256(returnData[i] + additionalSize);
                }
                else if (actions[i] == 8 && (flag & 1 == 0)) {
                    uint256 additionalSize;
                    uint256 price = prices[i];
                    ( , returnData[i], , additionalSize) = _marketOrder(param1[i], (uint160(referrer) << 80) | price, (3 << 252) | (1 << 244) | (1 << 240) | ((referrer >> 164 & 0xF) << 236) | uint160(owner));
                    quoteAssetDebt -= int256(returnData[i] + additionalSize);
                }
                else if (actions[i] == 9) {
                    bool isBuy;
                    uint256 size = param1[i];
                    uint256 price = prices[i];
                    uint256 id = (price >> 128) & 0xFFFFFFFFFF;
                    (size, returnData[i], isBuy) = _decreaseOrder(price, id, size, userId);
                    if (isBuy) {
                        quoteAssetDebt -= int256(returnData[i] / scaleFactor);
                    }
                    else {
                        baseAssetDebt -= int256(returnData[i] / price);
                    }
                    if (size == 0) {
                        assembly {
                            let length := mload(position)
                            mstore(add(length, add(position, 0x20)), or(add(0x2000000000000000000000000000000000000000000000000000000000000000,mul(0x1000000000000000000000000000000000000000000000000000000000000000,isBuy)),or(shl(168,price),or(shl(128,id),mload(add(add(returnData, 0x20), mul(i, 0x20)))))))
                            mstore(position, add(length, 0x20))
                            mstore(0x40, add(length, add(position, 0x40)))
                        }
                    }
                    else {
                        assembly {
                            flag := or(flag, add(1, iszero(isBuy)))
                            let length := mload(position)
                            mstore(add(length, add(position, 0x20)), or(add(0x4000000000000000000000000000000000000000000000000000000000000000,mul(0x1000000000000000000000000000000000000000000000000000000000000000,isBuy)),or(shl(168,price),or(shl(128,id),mload(add(add(returnData, 0x20), mul(i, 0x20)))))))
                            mstore(position, add(length, 0x20))
                            mstore(0x40, add(length, add(position, 0x40)))
                        }
                    }
                }
            }
            if (quoteAssetDebt > 0) {
                IERC20(quoteAsset).transferFrom((referrer >> 160 & 0xF == 1) ? owner : msg.sender, address(this), uint256(quoteAssetDebt));
            }
            else if (quoteAssetDebt < 0) {
                IERC20(quoteAsset).transfer((referrer >> 168 & 0xF == 1) ? owner : msg.sender, uint256(-quoteAssetDebt));
            }
            if (baseAssetDebt > 0) {
                IERC20(baseAsset).transferFrom((referrer >> 164 & 0xF == 1) ? owner : msg.sender, address(this), uint256(baseAssetDebt));
            }
            else if (baseAssetDebt < 0) {
                IERC20(baseAsset).transfer((referrer >> 172 & 0xF == 1) ? owner : msg.sender, uint256(-baseAssetDebt));
            }
            assembly {
                let length := mload(position)
                if gt(length, 0) {
                    mstore(sub(position, 0x20), 0x20)
                    log2(sub(position, 0x20), add(length, 0x40), 0x1c87843c023cd30242ff04316b77102e873496e3d8924ef015475cf066c1d4f4, owner)
                }
            }
            lock = 1;
            return returnData;
        }
    }

    function batchOrdersRequireSuccess(uint256[] calldata actions, uint256[] calldata prices, uint256[] calldata param1, address owner, uint256 referrer) external returns (uint256[] memory returnData) {
        unchecked {
            require((owner == msg.sender || router == msg.sender) && lock == 1);
            lock = 2;
            returnData = new uint256[](actions.length);
            uint256 position;
            assembly {
                position := add(mload(0x40), 0x20)
                mstore(position, 0x0)
                mstore(0x40, add(position, 0x20))
            }
            uint256 userId = addressToUserId[owner];
            int256 quoteAssetDebt;
            int256 baseAssetDebt;
            uint256 flag;
            for (uint256 i = 0; i < actions.length; ++i) {
                if (actions[i] == 0) {
                    bool isBuy;
                    uint256 price = prices[i];
                    uint256 p1 = param1[i];
                    (returnData[i], isBuy) = _cancelOrder(price, p1, userId);
                    if (returnData[i] > 0) {
                        if (isBuy) {
                            quoteAssetDebt -= int256(returnData[i] / scaleFactor);
                        }
                        else {
                            baseAssetDebt -= int256(returnData[i] / price);
                        }
                        assembly {
                            let length := mload(position)
                            mstore(add(length, add(position, 0x20)), or(add(0x2000000000000000000000000000000000000000000000000000000000000000,mul(0x1000000000000000000000000000000000000000000000000000000000000000,isBuy)),or(shl(168,price),or(shl(128,p1),mload(add(add(returnData, 0x20), mul(i, 0x20)))))))
                            mstore(position, add(length, 0x20))
                            mstore(0x40, add(length, add(position, 0x40)))
                        }
                    }
                    else {
                        revert ActionFailed();
                    }
                }
                else if (actions[i] == 1) {
                    uint256 size;
                    uint256 price = prices[i];
                    (size, returnData[i]) = _limitOrder(true, price, param1[i], userId);
                    if (size > 0) {
                        quoteAssetDebt += int256(size / scaleFactor);
                        assembly {
                            flag := or(flag, 1)
                            let length := mload(position)
                            mstore(add(length, add(position, 0x20)), or(or(or(0x1000000000000000000000000000000000000000000000000000000000000000, shl(168, price)), shl(128, mload(add(add(returnData, 0x20), mul(i, 0x20))))), size))
                            mstore(position, add(length, 0x20))
                            mstore(0x40, add(length, add(position, 0x40)))
                        }
                    }
                    else {
                        revert ActionFailed();
                    }
                }
                else if (actions[i] == 2) {
                    uint256 size;
                    uint256 price = prices[i];
                    (size, returnData[i]) = _limitOrder(false, price, param1[i], userId);
                    if (size > 0) {
                        baseAssetDebt += int256(size / price);
                        assembly {
                            flag := or(flag, 2)
                            let length := mload(position)
                            mstore(add(length, add(position, 0x20)), or(or(shl(168, price), shl(128, mload(add(add(returnData, 0x20), mul(i, 0x20))))), size))
                            mstore(position, add(length, 0x20))
                            mstore(0x40, add(length, add(position, 0x40)))
                        }
                    }
                    else {
                        revert ActionFailed();
                    }
                }
                else if (actions[i] == 3 && (flag & 2 == 0)) {
                    uint256 additionalSize;
                    uint256 price = prices[i];
                    ( , returnData[i], , additionalSize) = _marketOrder(param1[i], (uint160(referrer) << 80) | price, (1 << 252) | (1 << 240) | ((referrer >> 160 & 0xF) << 236) | uint160(owner));
                    baseAssetDebt -= int256(returnData[i] + additionalSize);
                }
                else if (actions[i] == 4 && (flag & 1 == 0)) {
                    uint256 additionalSize;
                    uint256 price = prices[i];
                    ( , returnData[i], , additionalSize) = _marketOrder(param1[i], (uint160(referrer) << 80) | price, (1 << 252) | (1 << 244) | (1 << 240) | ((referrer >> 164 & 0xF) << 236) | uint160(owner));
                    quoteAssetDebt -= int256(returnData[i] + additionalSize);
                }
                else if (actions[i] == 5 && (flag & 2 == 0)) {
                    uint256 additionalSize;
                    uint256 price = prices[i];
                    ( , returnData[i], price, additionalSize) = _marketOrder(param1[i], (uint160(referrer) << 80) | price, (2 << 252) | (1 << 240) | ((referrer >> 160 & 0xF) << 236) | uint160(owner));
                    baseAssetDebt -= int256(returnData[i] + (additionalSize & 0xffffffffffffffffffffffffffffffff));
                    if (price > 0) {
                        uint256 _price = prices[i];
                        additionalSize = (additionalSize >> 128);
                        quoteAssetDebt += int256(additionalSize / scaleFactor);
                        assembly {
                            flag := or(flag, 1)
                            let length := mload(position)
                            mstore(add(length, add(position, 0x20)), or(or(or(0x1000000000000000000000000000000000000000000000000000000000000000, shl(168, _price)), shl(128, price)), additionalSize))
                            mstore(position, add(length, 0x20))
                            mstore(0x40, add(length, add(position, 0x40)))
                        }
                    }
                }
                else if (actions[i] == 6 && (flag & 1 == 0)) {
                    uint256 additionalSize;
                    uint256 price = prices[i];
                    ( , returnData[i], price, additionalSize) = _marketOrder(param1[i], (uint160(referrer) << 80) | price, (2 << 252) | (1 << 244) | (1 << 240) | ((referrer >> 164 & 0xF) << 236) | uint160(owner));
                    quoteAssetDebt -= int256(returnData[i] + (additionalSize & 0xffffffffffffffffffffffffffffffff));
                    if (price > 0) {
                        uint256 _price = prices[i];
                        additionalSize = (additionalSize >> 128);
                        baseAssetDebt += int256(additionalSize / _price);
                        assembly {
                            flag := or(flag, 2)
                            let length := mload(position)
                            mstore(add(length, add(position, 0x20)), or(or(shl(168, _price), shl(128, price)), additionalSize))
                            mstore(position, add(length, 0x20))
                            mstore(0x40, add(length, add(position, 0x40)))
                        }
                    }
                }
                else if (actions[i] == 7 && (flag & 2 == 0)) {
                    uint256 additionalSize;
                    uint256 price = prices[i];
                    ( , returnData[i], , additionalSize) = _marketOrder(param1[i], (uint160(referrer) << 80) | price, (3 << 252) | (1 << 240) | ((referrer >> 160 & 0xF) << 236) | uint160(owner));
                    baseAssetDebt -= int256(returnData[i] + additionalSize);
                }
                else if (actions[i] == 8 && (flag & 1 == 0)) {
                    uint256 additionalSize;
                    uint256 price = prices[i];
                    ( , returnData[i], , additionalSize) = _marketOrder(param1[i], (uint160(referrer) << 80) | price, (3 << 252) | (1 << 244) | (1 << 240) | ((referrer >> 164 & 0xF) << 236) | uint160(owner));
                    quoteAssetDebt -= int256(returnData[i] + additionalSize);
                }
                else if (actions[i] == 9) {
                    bool isBuy;
                    uint256 size = param1[i];
                    uint256 price = prices[i];
                    uint256 id = (price >> 128) & 0xFFFFFFFFFF;
                    (size, returnData[i], isBuy) = _decreaseOrder(price, id, size, userId);
                    if (isBuy) {
                        quoteAssetDebt -= int256(returnData[i] / scaleFactor);
                    }
                    else {
                        baseAssetDebt -= int256(returnData[i] / price);
                    }
                    if (size == 0) {
                        assembly {
                            let length := mload(position)
                            mstore(add(length, add(position, 0x20)), or(add(0x2000000000000000000000000000000000000000000000000000000000000000,mul(0x1000000000000000000000000000000000000000000000000000000000000000,isBuy)),or(shl(168,price),or(shl(128,id),mload(add(add(returnData, 0x20), mul(i, 0x20)))))))
                            mstore(position, add(length, 0x20))
                            mstore(0x40, add(length, add(position, 0x40)))
                        }
                    }
                    else if (returnData[i] == 0) {
                        revert ActionFailed();
                    }
                    else {
                        assembly {
                            flag := or(flag, add(1, iszero(isBuy)))
                            let length := mload(position)
                            mstore(add(length, add(position, 0x20)), or(add(0x4000000000000000000000000000000000000000000000000000000000000000,mul(0x1000000000000000000000000000000000000000000000000000000000000000,isBuy)),or(shl(168,price),or(shl(128,id),mload(add(add(returnData, 0x20), mul(i, 0x20)))))))
                            mstore(position, add(length, 0x20))
                            mstore(0x40, add(length, add(position, 0x40)))
                        }
                    }
                }
            }
            if (quoteAssetDebt > 0) {
                IERC20(quoteAsset).transferFrom((referrer >> 160 & 0xF == 1) ? owner : msg.sender, address(this), uint256(quoteAssetDebt));
            }
            else if (quoteAssetDebt < 0) {
                IERC20(quoteAsset).transfer((referrer >> 168 & 0xF == 1) ? owner : msg.sender, uint256(-quoteAssetDebt));
            }
            if (baseAssetDebt > 0) {
                IERC20(baseAsset).transferFrom((referrer >> 164 & 0xF == 1) ? owner : msg.sender, address(this), uint256(baseAssetDebt));
            }
            else if (baseAssetDebt < 0) {
                IERC20(baseAsset).transfer((referrer >> 172 & 0xF == 1) ? owner : msg.sender, uint256(-baseAssetDebt));
            }
            assembly {
                let length := mload(position)
                if gt(length, 0) {
                    mstore(sub(position, 0x20), 0x20)
                    log2(sub(position, 0x20), add(length, 0x40), 0x1c87843c023cd30242ff04316b77102e873496e3d8924ef015475cf066c1d4f4, owner)
                }
            }
            lock = 1;
            return returnData;
        }
    }

    fallback() external {
        unchecked {
            require(lock == 1);
            lock = 2;
            assembly {
                mstore(0x40, 0xc0)
            }
            uint256 userId = addressToUserId[msg.sender];
            uint256 offset;
            uint256 action;
            uint256 param1;
            uint256 param2;
            uint256 flag;
            bool isBuy;
            int256 quoteAssetDebt;
            int256 baseAssetDebt;
            while (offset < msg.data.length) {
                assembly {
                    action := calldataload(offset)
                    param1 := and(0xffffffffffffffffffff, shr(128, action))
                    param2 := and(0xffffffffffffffffffffffffffffffff, action)
                }
                if (uint8(action >> 252) == 0) {
                    (action, isBuy) = _cancelOrder(param1, param2, userId);
                    if (action > 0) {
                        if (isBuy) {
                            quoteAssetDebt -= int256(action / scaleFactor);
                        }
                        else {
                            baseAssetDebt -= int256(action / param1);
                        }
                        assembly {
                            let length := mload(0xa0)
                            mstore(add(length, 0xc0), or(add(0x2000000000000000000000000000000000000000000000000000000000000000,mul(0x1000000000000000000000000000000000000000000000000000000000000000,isBuy)),or(shl(168,param1),or(shl(128,param2),action))))
                            mstore(0xa0, add(length, 0x20))
                            mstore(0x40, add(length, 0xe0))
                        }
                    }
                }
                else if (uint8(action >> 252) == 1) {
                    (action, param2) = _limitOrder(true, param1, param2, userId);
                    if (action > 0) {
                        quoteAssetDebt += int256(action / scaleFactor);
                        assembly {
                            flag := or(flag, 1)
                            let length := mload(0xa0)
                            mstore(add(length, 0xc0), or(0x1000000000000000000000000000000000000000000000000000000000000000,or(shl(168,param1),or(shl(128,param2),action))))
                            mstore(0xa0, add(length, 0x20))
                            mstore(0x40, add(length, 0xe0))
                        }
                    }
                }
                else if (uint8(action >> 252) == 2) {
                    (action, param2) = _limitOrder(false, param1, param2, userId);
                    if (action > 0) {
                        baseAssetDebt += int256(action / param1);
                        assembly {
                            flag := or(flag, 2)
                            let length := mload(0xa0)
                            mstore(add(length, 0xc0), or(shl(168,param1),or(shl(128,param2),action)))
                            mstore(0xa0, add(length, 0x20))
                            mstore(0x40, add(length, 0xe0))
                        }
                    }
                }
                else if (uint8(action >> 252) == 3 && (flag & 2 == 0)) {
                    uint256 additionalSize;
                    ( , action, , additionalSize) = _marketOrder(param2, (uint160(msg.sender) << 80) | param1, (1 << 240) | uint160(msg.sender));
                    baseAssetDebt -= int256(action + additionalSize);
                }
                else if (uint8(action >> 252) == 4 && (flag & 1 == 0)) {
                    uint256 additionalSize;
                    ( , action, , additionalSize) = _marketOrder(param2, (uint160(msg.sender) << 80) | param1, (1 << 244) | (1 << 240) | uint160(msg.sender));
                    quoteAssetDebt -= int256(action + additionalSize);
                }
                else if (uint8(action >> 252) == 5 && (flag & 2 == 0)) {
                    uint256 additionalSize;
                    ( , action, param2, additionalSize) = _marketOrder(param2, (uint160(msg.sender) << 80) | param1, (2 << 252) | (1 << 240) | uint160(msg.sender));
                    baseAssetDebt -= int256(action + (additionalSize & 0xffffffffffffffffffffffffffffffff));
                    if (param2 > 0) {
                        additionalSize = (additionalSize >> 128);
                        quoteAssetDebt += int256(additionalSize / scaleFactor);
                        assembly {
                            flag := or(flag, 1)
                            let length := mload(0xa0)
                            mstore(add(length, 0xc0), or(0x1000000000000000000000000000000000000000000000000000000000000000,or(shl(168,param1),or(shl(128,param2),additionalSize))))
                            mstore(0xa0, add(length, 0x20))
                            mstore(0x40, add(length, 0xe0))
                        }
                    }
                }
                else if (uint8(action >> 252) == 6 && (flag & 1 == 0)) {
                    uint256 additionalSize;
                    ( , action, param2, additionalSize) = _marketOrder(param2, (uint160(msg.sender) << 80) | param1, (2 << 252) | (1 << 244) | (1 << 240) | uint160(msg.sender));
                    quoteAssetDebt -= int256(action + (additionalSize & 0xffffffffffffffffffffffffffffffff));
                    if (param2 > 0) {
                        additionalSize = (additionalSize >> 128);
                        baseAssetDebt += int256(additionalSize / param1);
                        assembly {
                            flag := or(flag, 2)
                            let length := mload(0xa0)
                            mstore(add(length, 0xc0), or(shl(168,param1),or(shl(128,param2),additionalSize)))
                            mstore(0xa0, add(length, 0x20))
                            mstore(0x40, add(length, 0xe0))
                        }
                    }
                }
                else if (uint8(action >> 252) == 7 && (flag & 2 == 0)) {
                    uint256 additionalSize;
                    ( , action, , additionalSize) = _marketOrder(param2, (uint160(msg.sender) << 80) | param1, (3 << 252) | (1 << 240) | uint160(msg.sender));
                    baseAssetDebt -= int256(action + additionalSize);
                }
                else if (uint8(action >> 252) == 8 && (flag & 1 == 0)) {
                    uint256 additionalSize;
                    ( , action, , additionalSize) = _marketOrder(param2, (uint160(msg.sender) << 80) | param1, (3 << 252) | (1 << 244) | (1 << 240) | uint160(msg.sender));
                    quoteAssetDebt -= int256(action + additionalSize);
                }
                else if (uint8(action >> 252) == 9) {
                    uint256 additionalSize;
                    (param2, additionalSize, isBuy) = _decreaseOrder(param1, (action >> 208) & 0xFFFFFFFFFF, param2, userId);
                    if (isBuy) {
                        quoteAssetDebt -= int256(additionalSize / scaleFactor);
                    }
                    else {
                        baseAssetDebt -= int256(additionalSize / param1);
                    }
                    if (param2 == 0) {
                        assembly {
                            let length := mload(0xa0)
                            mstore(add(length, 0xc0), or(add(0x2000000000000000000000000000000000000000000000000000000000000000,mul(0x1000000000000000000000000000000000000000000000000000000000000000,isBuy)),or(shl(168,param1),or(shl(128,and(shr(208, action), 0xFFFFFFFFFF)),param2))))
                            mstore(0xa0, add(length, 0x20))
                            mstore(0x40, add(length, 0xe0))
                        }
                    }
                    else {
                        assembly {
                            flag := or(flag, add(1, iszero(isBuy)))
                            let length := mload(0xa0)
                            mstore(add(length, 0xc0), or(add(0x4000000000000000000000000000000000000000000000000000000000000000,mul(0x1000000000000000000000000000000000000000000000000000000000000000,isBuy)),or(shl(168,param1),or(shl(128,and(shr(208, action), 0xFFFFFFFFFF)),param2))))
                            mstore(0xa0, add(length, 0x20))
                            mstore(0x40, add(length, 0xe0))
                        }
                    }
                }
                offset += 32;
            }
            if (quoteAssetDebt > 0) {
                IERC20(quoteAsset).transferFrom(msg.sender, address(this), uint256(quoteAssetDebt));
            }
            else if (quoteAssetDebt < 0) {
                IERC20(quoteAsset).transfer(msg.sender, uint256(-quoteAssetDebt));
            }
            if (baseAssetDebt > 0) {
                IERC20(baseAsset).transferFrom(msg.sender, address(this), uint256(baseAssetDebt));
            }
            else if (baseAssetDebt < 0) {
                IERC20(baseAsset).transfer(msg.sender, uint256(-baseAssetDebt));
            }
            assembly {
                let length := mload(0xa0)
                if gt(length, 0) {
                    mstore(0x80, 0x20)
                    log2(0x80, add(length, 0x40), 0x1c87843c023cd30242ff04316b77102e873496e3d8924ef015475cf066c1d4f4, caller())
                }
            }
            lock = 1;
        }
    }
}