// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBondingCurveRouter {
    struct TokenCreationParams {
        string name;
        string symbol;
        string tokenURI;
        uint256 amountOut;
        bytes32 salt;
        uint256 actionId;
    }

    struct BuyParams {
        uint256 amountOutMin;
        address token;
        address to;
        uint256 deadline;
    }

    struct ExactOutBuyParams {
        uint256 amountInMax;
        uint256 amountOut;
        address token;
        address to;
        uint256 deadline;
    }

    struct SellParams {
        uint256 amountIn;
        uint256 amountOutMin;
        address token;
        address to;
        uint256 deadline;
    }

    struct ExactOutSellParams {
        uint256 amountInMax;
        uint256 amountOut;
        address token;
        address to;
        uint256 deadline;
    }

    struct SellPermitParams {
        uint256 amountIn;
        uint256 amountOutMin;
        uint256 amountAllowance;
        address token;
        address to;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct ExactOutSellPermitParams {
        uint256 amountInMax;
        uint256 amountOut;
        uint256 amountAllowance;
        address token;
        address to;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct Config {
        uint256 virtualMonReserve;
        uint256 virtualTokenReserve;
        uint256 targetTokenAmount;
    }

    struct FeeConfig {
        uint256 deployFeeAmount;
        uint256 graduateFeeAmount;
        uint24 protocolFee;
    }

    struct AntiSnipingConfig {
        uint256 maxPenaltyBlocks;
        uint256[] penaltyBlocks;
        uint256[] penaltyRates;
    }

    struct SetConfigParams {
        Config config;
        FeeConfig feeConfig;
        AntiSnipingConfig antiSnipingConfig;
    }

    struct CurveTokenCreationParams {
        address creator;
        string name;
        string symbol;
        string tokenURI;
        bytes32 salt;
        uint8 actionId;
    }

    function create(TokenCreationParams calldata params) external payable returns (address token, address pool);
    function create(CurveTokenCreationParams calldata params) external returns (address token, address pool);

    function buy(BuyParams calldata params) external payable returns (uint256 amountOut);
    function exactOutBuy(ExactOutBuyParams calldata params) external payable returns (uint256 amountIn);
    function sell(SellParams calldata params) external;
    function exactOutSell(ExactOutSellParams calldata params) external;
    function sellPermit(SellPermitParams calldata params) external returns (uint256 amountOut);
    function exactOutSellPermit(ExactOutSellPermitParams calldata params) external returns (uint256 amountIn);

    function availableBuyTokens(address _token) external view returns (uint256 availableBuyToken, uint256 requiredMonAmount);
    function getAmountIn(address _token, uint256 _amountOut, bool _isBuy) external view returns (address router, uint256 amountIn);
    function getAmountOut(address _token, uint256 _amountIn, bool _isBuy) external view returns (address router, uint256 amountOut);
    function getInitialBuyAmountOut(uint256 _amountIn) external view returns (uint256 amountOut);
    function getProgress(address _token) external view returns (uint256 progress);
    function isGraduated(address _token) external view returns (bool isGraduated);
    function isLocked(address _token) external view returns (bool isLocked);
    function transferFrom(address token, address from, address spender, uint256 amount) external;
    function buy(address to, address token) external returns (uint256 amountOut);
    function calculateFeeAmount(uint256 amount) external view returns (uint256 feeAmount);
    function config() external view returns (uint256 virtualMonReserve, uint256 virtualTokenReserve, uint256 targetTokenAmount);
    function createdAt(address token) external view returns (uint256);
    function curves(address token)
        external
        view
        returns (
            uint256 realMonReserve,
            uint256 realTokenReserve,
            uint256 virtualMonReserve,
            uint256 virtualTokenReserve,
            uint256 k,
            uint256 targetTokenAmount,
            uint256 initVirtualMonReserve,
            uint256 initVirtualTokenReserve
        );
    function feeConfig() external view returns (uint256 deployFeeAmount, uint256 graduateFeeAmount, uint24 protocolFee);
    function foundationTreasury() external view returns (address);
    function graduate(address token) external;
    function sell(address to, address token) external returns (uint256 amountOut);
    function setConfig(SetConfigParams calldata params) external;
    function wMon() external view returns (address);
    function wMonReserve() external view returns (uint256);

    event CurveBuy(address indexed sender, address indexed token, uint256 amountIn, uint256 amountOut);
    event CurveCreate(
        address indexed creator,
        address indexed token,
        address indexed pool,
        string name,
        string symbol,
        string tokenURI,
        uint256 virtualMon,
        uint256 virtualToken,
        uint256 targetTokenAmount
    );
    event CurveGraduate(address indexed token, address indexed pool);
    event CurveSell(address indexed sender, address indexed token, uint256 amountIn, uint256 amountOut);
    event CurveSync(
        address indexed token,
        uint256 realMonReserve,
        uint256 realTokenReserve,
        uint256 virtualMonReserve,
        uint256 virtualTokenReserve
    );
    event CurveTokenLocked(address indexed token);
    event SetConfig(SetConfigParams params);

    error AlreadyGraduated();
    error AlreadySet();
    error BondingCurveLocked();
    error BondingCurveNotLocked();
    error InsufficientAmount();
    error InsufficientFee();
    error InsufficientWMon();
    error InvalidAmountIn();
    error InvalidAntiSnipingConfig();
    error InvalidFeeConfig();
    error InvalidKValue();
    error InvalidName();
    error InvalidPenaltyRate();
    error InvalidSymbol();
    error InvalidToken();
    error OverFlow();
    error TargetAmountOverflow();
    error Unauthorized();
    error ZeroAddress();
}
