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

interface IPyth {
    struct Price {
        int64 price;
    }

    function getPriceNoOlderThan(bytes32 feedId, uint64 maxAge) external view returns (Price memory);
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

interface ICrystalPriceAdapter {
    function getPrice() external view returns (uint256);
}

contract CrystalSuppliedToken {

}

contract CrystalDebtToken {

}

contract CrystalLend {
    struct Token {
        address oracle;
        address CrystalMarket;
        bool isQuoteToken;
        uint256 scaleFactor;
        uint256 maxBorrowLTV;
        uint256 liquidationLTV;
        uint256 liquidationBonus;
        uint256 currentRate;
        uint256 totalSupplied;
        uint256 totalBorrowed;
        uint256 supplyIndex;
        uint256 borrowIndex;
    }

    struct Account {
        address[] suppliedTokens;
        uint256[] suppliedAmounts;
        address[] borrowedTokens;
        uint256[] borrowedAmounts;
    }

    mapping(uint256 => Account) accounts;
    mapping(address => Token) public tokens;

    address public gov;

    function listToken(address token, address oracle, address CrystalMarket, bool isQuoteToken, uint256 oraclePriceFactor, uint256 maxBorrowLTV, uint256 liquidationLTV, uint256 liquidationBonus) external {
        require(msg.sender == gov);
        tokens[token] = Token(oracle, CrystalMarket, isQuoteToken, (10**18) / (10**oraclePriceFactor) / (10**IERC20(token).decimals()), maxBorrowLTV, liquidationLTV, liquidationBonus, 0, 0, 0, 1, 1);
        IERC20(token).approve(CrystalMarket, type(uint256).max);
    }

    function updateParams(address token, address oracle, address CrystalMarket, bool isQuoteToken, uint256 oraclePriceFactor, uint256 maxBorrowLTV, uint256 liquidationLTV, uint256 liquidationBonus) external {
        require(msg.sender == gov);
        Token storage t = tokens[token];
        t.oracle = oracle;
        t.CrystalMarket = CrystalMarket;
        t.isQuoteToken = isQuoteToken;
        t.scaleFactor = (10**18) / (10**oraclePriceFactor) / (10**IERC20(token).decimals());
        t.maxBorrowLTV = maxBorrowLTV;
        t.liquidationLTV = liquidationLTV;
        t.liquidationBonus = liquidationBonus;
        IERC20(token).approve(CrystalMarket, type(uint256).max);
    }

    function getInterestRate(address token) public view returns (uint256 supplyRate, uint256 borrowRate) {

    }

    function getAccountHealth(bool isIncrease, address owner, uint256 id) public view returns (uint256 solvency) {
        Account memory account = accounts[uint256(uint160(owner)) | id << 160];
        if (account.borrowedTokens.length == 0) {
            return type(uint256).max;
        }
        uint256 supplyValue;
        uint256 borrowValue;
        uint256 amount;
        uint256 price;
        for (uint256 i = 0; i < account.suppliedTokens.length; ++i) {
            Token memory token = tokens[account.suppliedTokens[i]];
            amount = account.suppliedAmounts[i];
            price = ICrystalPriceAdapter(token.oracle).getPrice();
            supplyValue += amount * price * token.scaleFactor * (isIncrease ? token.maxBorrowLTV : token.liquidationLTV);
        }
        for (uint256 i = 0; i < account.borrowedTokens.length; ++i) {
            Token memory token = tokens[account.borrowedTokens[i]];
            amount = account.borrowedAmounts[i];
            price = ICrystalPriceAdapter(token.oracle).getPrice();
            borrowValue += amount * price * token.scaleFactor;
        }
        solvency = supplyValue / borrowValue;
    }

    function supply(address token, uint256 amount, uint256 accountId) external {
        tokens[token].totalSupplied += amount;
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        Account storage account = accounts[uint256(uint160(msg.sender)) | accountId << 160];
        for (uint256 i = 0; i < account.suppliedTokens.length; ++i) {
            if (account.suppliedTokens[i] == token) {
                account.suppliedAmounts[i] += amount;
                return;
            }
        }
        account.suppliedTokens.push(token);
        account.suppliedAmounts.push(amount);
    }

    function borrow(address token, uint256 amount, uint256 accountId) external {
        require(tokens[token].totalSupplied >= tokens[token].totalBorrowed + amount);
        tokens[token].totalBorrowed += amount;
        IERC20(token).transfer(msg.sender, amount);
        Account storage account = accounts[uint256(uint160(msg.sender)) | accountId << 160];
        for (uint256 i = 0; i < account.borrowedTokens.length; ++i) {
            if (account.borrowedTokens[i] == token) {
                account.borrowedAmounts[i] += amount;
                require(getAccountHealth(true, msg.sender, accountId) > 100000);
                return;
            }
        }
        account.borrowedTokens.push(token);
        account.borrowedAmounts.push(amount);
        require(getAccountHealth(true, msg.sender, accountId) > 100000);
    }

    function withdraw(address token, uint256 amount, uint256 accountId) external {
        Account storage account = accounts[uint256(uint160(msg.sender)) | accountId << 160];
        for (uint256 i = 0; i < account.suppliedTokens.length; ++i) {
            if (account.suppliedTokens[i] == token) {
                if (amount > account.suppliedAmounts[i]) {
                    amount = account.suppliedAmounts[i];
                }
                account.suppliedAmounts[i] -= amount;
                tokens[token].totalSupplied -= amount;
                require(getAccountHealth(true, msg.sender, accountId) > 100000);
                IERC20(token).transfer(msg.sender, amount);
                return;
            }
        }
        revert();
    }

    function repay(address token, uint256 amount, uint256 accountId) external {
        Account storage account = accounts[uint256(uint160(msg.sender)) | accountId << 160];
        for (uint256 i = 0; i < account.borrowedTokens.length; ++i) {
            if (account.borrowedTokens[i] == token) {
                if (amount > account.borrowedAmounts[i]) {
                    amount = account.borrowedAmounts[i];
                }
                account.borrowedAmounts[i] -= amount;
                tokens[token].totalBorrowed -= amount;
                IERC20(token).transferFrom(msg.sender, address(this), amount);
                return;
            }
        }
        revert();
    }

    function flash(address supplyToken, uint256 supplyCollateral, address borrowToken, uint256 borrowAmount) external {
        Token memory token = tokens[borrowToken];
        (uint256 inputAmount, uint256 outputAmount, ) = ICrystalMarket(token.CrystalMarket).marketOrder(token.isQuoteToken, true, false, false, 0, borrowAmount, token.isQuoteToken ? type(uint256).max : 0, msg.sender, address(0));

    }

    function liquidate(address user, uint256 accountId, address[] calldata repaymentTokens, uint256[] calldata repaymentAmounts, address[] calldata collateralToClaim) external {
        require(getAccountHealth(false, user, accountId) < 100000);
        for (uint256 i = 0; i < repaymentTokens.length; ++i) {
            IERC20(repaymentTokens[i]).transferFrom(msg.sender, address(this), repaymentAmounts[i]);
        }
    }
}

contract CrystalMarginAccount {

}

contract PythPriceAdapter {
    IPyth public immutable pyth;

    constructor(address core) {
        pyth = IPyth(core);
    }

    function verify(
        bytes32 feedId,
        uint64  maxAge,
        int64   keeperPrice,
        uint16  maxDrift
    )
        external
        view
        returns (bool ok)
    {
        IPyth.Price memory p = pyth.getPriceNoOlderThan(feedId, maxAge);

        int64 pythPrice = p.price;
        int256 diff = pythPrice - keeperPrice;
        if (diff < 0) diff = -diff;

        int256 driftBps  = diff * 10_000 / int256(pythPrice);
        ok = driftBps <= int256(uint256(maxDrift));
    }
}

contract CrystalPriceAdapter {
    address public immutable oracle;

    constructor(address _oracle) {
        oracle = _oracle;
    }

    function getPrice() external view returns (uint256 price) {
        (price, , ) = ICrystalMarket(oracle).getPrice();
    } 
}

contract CrystalPriceAdapterUSD {
    function getPrice() external pure returns (uint256 price) {
        price = 1;
    } 
}