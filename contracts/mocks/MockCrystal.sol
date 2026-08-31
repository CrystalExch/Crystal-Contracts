// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC20} from '../interfaces/IERC20.sol';
import {ICrystal} from "../interfaces/ICrystal.sol";
import {ICrystalVault} from "../interfaces/ICrystalVault.sol";
import {CrystalVault} from "../vaults/CrystalVault.sol";

import {CrystalMarketHarness} from "./CrystalMarketHarness.sol";

/// @notice Mock Factory for deploying vaults with MockCrystal.
contract MockFactory {
    uint16 public maxOrderCap = 100;
    uint40 public maxLockup = 0;

    event VaultDeployed(address vault);

    function deployVault(
        address _crystal,
        address _quoteAsset,
        address _baseAsset,
        address _owner,
        string memory _symbol,
        ICrystalVault.VaultMetaData memory _metadata
    ) external returns (address) {
        CrystalVault vault = new CrystalVault(
            _crystal,
            _quoteAsset,
            _baseAsset,
            _owner,
            _symbol,
            _metadata
        );
        emit VaultDeployed(address(vault));
        return address(vault);
    }

    function deposit(
        address vault,
        address quoteAsset,
        address baseAsset,
        uint256 amountQuote,
        uint256 amountBase
    ) external returns (uint256 shares) {
        IERC20(quoteAsset).transferFrom(msg.sender, address(this), amountQuote);
        IERC20(baseAsset).transferFrom(msg.sender, address(this), amountBase);
        IERC20(quoteAsset).approve(vault, amountQuote);
        IERC20(baseAsset).approve(vault, amountBase);
        (shares, , ) = ICrystalVault(vault).deposit(msg.sender, amountQuote, amountBase, 0, 0);
    }

    function withdraw(
        address vault,
        uint256 shares
    ) external returns (uint256 amountQuote, uint256 amountBase) {
        (amountQuote, amountBase) = ICrystalVault(vault).withdraw(msg.sender, shares, 0, 0);
    }

    function changeDecreaseOnWithdraw(address vault, bool newDecrease) external {
        ICrystalVault(vault).changeDecreaseOnWithdraw(newDecrease);
    }

    function changeOrderCap(address vault, uint16 newCap) external {
        ICrystalVault(vault).changeOrderCap(newCap);
    }

    function changeMarket(address vault) external {
        ICrystalVault(vault).changeMarket();
    }
}

/// @notice Mock Crystal contract that returns fake orders but reverts on batch calls.
/// @dev Used to test the revert paths in CrystalVault's withdraw and cancelAll functions.
contract MockCrystal {
    address public quoteAsset;
    address public baseAsset;
    uint256 public marketId;
    uint256 public marketType;
    uint256 public scaleFactor;
    uint256 public tickSize;
    uint256 public maxPrice;
    uint256 public ammFee;

    CrystalMarketHarness public harness;

    bool public shouldRevertOnBatch = true;
    uint256 public fakeOrderCount = 1;
    bool public allBuyOrders = true; // if true, all orders are buy orders
    uint256 public baseCloid = 1; // Starting cloid value

    mapping(address => uint256) public balances;
    address public fakeMarket = address(0x1234);
    address public configuredQuoteAsset;
    address public configuredBaseAsset;

    // Configurable balances for getDepositedBalance
    mapping(address => mapping(address => uint256)) public depositedBalances;
    mapping(address => mapping(address => uint256)) public availableBalances;

    constructor(address _quoteAsset, address _baseAsset) {
        configuredQuoteAsset = _quoteAsset;
        configuredBaseAsset = _baseAsset;
    }

    /// @notice Returns parameters for CrystalMarket constructor.
    function parameters() external view returns (
        address,
        address,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256
    ) {
        return (quoteAsset, baseAsset, marketId, marketType, scaleFactor, tickSize, maxPrice, ammFee);
    }

    /// @notice Deploy a CrystalMarketHarness with the specified parameters.
    function deployHarness(
        address _quoteAsset,
        address _baseAsset,
        uint256 _marketId,
        uint256 _marketType,
        uint256 _scaleFactor,
        uint256 _tickSize,
        uint256 _maxPrice
    ) external returns (address) {
        quoteAsset = _quoteAsset;
        baseAsset = _baseAsset;
        marketId = _marketId;
        marketType = _marketType;
        scaleFactor = _scaleFactor;
        tickSize = _tickSize;
        maxPrice = _maxPrice;
        ammFee = 9975;

        harness = new CrystalMarketHarness();
        return address(harness);
    }

    function setConfiguredQuoteAsset(address _quoteAsset) external {
        configuredQuoteAsset = _quoteAsset;
    }

    function setBaseCloid(uint256 _baseCloid) external {
        baseCloid = _baseCloid;
    }

    function setShouldRevertOnBatch(bool _shouldRevert) external {
        shouldRevertOnBatch = _shouldRevert;
    }

    function setFakeOrderCount(uint256 _count) external {
        fakeOrderCount = _count;
    }

    function setAllBuyOrders(bool _allBuy) external {
        allBuyOrders = _allBuy;
    }

    function setDepositedBalance(address user, address token, uint256 total, uint256 available) external {
        depositedBalances[user][token] = total;
        availableBalances[user][token] = available;
    }

    function deposit(address token, uint256 amount) external returns (uint256) {
        depositedBalances[msg.sender][token] += amount;
        availableBalances[msg.sender][token] += amount;
        return amount;
    }

    function withdraw(address, address, uint256) external {
        // No-op for mock
    }

    function getBalance(address user, address token) external view returns (uint256) {
        return depositedBalances[user][token];
    }

    function getDepositedBalance(address user, address token) external view returns (uint256 total, uint256 available, uint256 locked) {
        total = depositedBalances[user][token];
        available = availableBalances[user][token];
        locked = total > available ? total - available : 0;
    }

    function getMarketByTokens(address, address) external view returns (address) {
        return fakeMarket;
    }

    function getMarket(address) external view returns (ICrystal.MarketInfo memory) {
        return ICrystal.MarketInfo({
            quoteAsset: configuredQuoteAsset,
            baseAsset: configuredBaseAsset,
            marketType: 0,
            highestBid: 0,
            lowestAsk: 0,
            scaleFactor: 1e18,
            tickSize: 1,
            maxPrice: 1e36,
            minSize: 0,
            takerFee: 0,
            makerRebate: 0,
            reserveQuote: 0,
            reserveBase: 0,
            isAMMEnabled: false
        });
    }

    function registerUser(address) external pure returns (uint256) {
        return 1; // Return fake user ID
    }

    function getAllOrdersByCloid(address user, uint256 cap) external view returns (uint256[] memory cloids, ICrystal.Order[] memory orders) {
        cloids = new uint256[](fakeOrderCount);
        orders = new ICrystal.Order[](fakeOrderCount);

        for (uint256 i = 0; i < fakeOrderCount; i++) {
            cloids[i] = baseCloid + i; // Use baseCloid for configurable starting value
            orders[i] = ICrystal.Order({
                isBuy: allBuyOrders ? true : (i % 2 == 0),
                market: address(0),
                price: 1000,
                size: 1000000000000000000, // 1 ether
                orderType: 0,
                userId: 1,
                fillBefore: 0,
                fillAfter: 0
            });
        }

        return (cloids, orders);
    }

    function claimFees(address[] calldata) external {
        // No-op for mock
    }

    function clearCloidSlots(uint256, uint256[] calldata) external {
        // No-op for mock
    }

    fallback() external payable {
        if (shouldRevertOnBatch) {
            revert("MockCrystal: batch call reverted");
        }
    }

    receive() external payable {}
}
