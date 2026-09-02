// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "./BaseTest.t.sol";
import { CrystalMath } from "../../contracts/libraries/CrystalMath.sol";
import { console2 } from "forge-std/console2.sol";

contract GasBenchmark is BaseTest {
    event GasUsed(string name, uint256 gasUsed);

    uint256 private constant BENCH_ORDER_SIZE = 1 ether;
    uint256 private constant INTERNAL_LIMIT_OPTIONS = 1 << 60;
    uint256 private constant INTERNAL_MARKET_OPTIONS = 1 << 68;
    uint256 private constant SEEDED_ASK_LEVELS = 100;
    uint256 private constant START_QUOTE_PER_BASE = 500;
    uint256 private constant COUNT_ONE = 1;
    uint256 private constant COUNT_TEN = 10;
    uint256 private constant COUNT_FIFTY = 50;
    uint256 private constant FIRST_CLOID_ONE = 1;
    uint256 private constant FIRST_CLOID_TEN = 2;
    uint256 private constant FIRST_CLOID_FIFTY = 12;

    function testBenchmarkCrystalCoreActions() public {
        uint256 limitSellGas = _measureLimitOrderSell();
        uint256 addLiquidityGas = _measureAddLiquidity();
        uint256 marketBuyGas = _measureMarketBuy();
        uint256 getAmountsOutGas = _measureGetAmountsOut();

        _emitGasUsed("Crystal.limitOrder.sell", limitSellGas);
        _emitGasUsed("Crystal.addLiquidity", addLiquidityGas);
        _emitGasUsed("Crystal.marketOrder.buy.exactInput", marketBuyGas);
        _emitGasUsed("Crystal.getAmountsOut", getAmountsOutGas);

        _assertPositive(limitSellGas, "assert limitSellGas > 0");
        _assertPositive(addLiquidityGas, "assert addLiquidityGas > 0");
        _assertPositive(marketBuyGas, "assert marketBuyGas > 0");
        _assertPositive(getAmountsOutGas, "assert getAmountsOutGas > 0");
    }

    function testBenchmarkFallbackCloidCancelReplaceSameTx() public {
        uint256 oneOrderTotalGas = _measureFallbackCloidCancelReplaceSamePage(COUNT_ONE, FIRST_CLOID_ONE);
        uint256 tenOrdersTotalGas = _measureFallbackCloidCancelReplaceSamePage(COUNT_TEN, FIRST_CLOID_TEN);
        uint256 fiftyOrdersTotalGas = _measureFallbackCloidCancelReplaceSamePage(COUNT_FIFTY, FIRST_CLOID_FIFTY);

        _emitGasPerUnit("fallback.cloid.cancelReplace.samePage.perOrder.1", oneOrderTotalGas, COUNT_ONE);
        _emitGasPerUnit("fallback.cloid.cancelReplace.samePage.perOrder.10", tenOrdersTotalGas, COUNT_TEN);
        _emitGasPerUnit("fallback.cloid.cancelReplace.samePage.perOrder.50", fiftyOrdersTotalGas, COUNT_FIFTY);

        _assertIncreasingTotals(oneOrderTotalGas, tenOrdersTotalGas, fiftyOrdersTotalGas);
    }

    function testBenchmarkNormalOrderFills() public {
        uint256 oneFillTotalGas = _measureConsecutiveAskFills(COUNT_ONE);
        uint256 tenFillTotalGas = _measureConsecutiveAskFills(COUNT_TEN);
        uint256 fiftyFillTotalGas = _measureConsecutiveAskFills(COUNT_FIFTY);

        _emitGasPerUnit("normal.fill.consecutiveAskLevels.perFill.1", oneFillTotalGas, COUNT_ONE);
        _emitGasPerUnit("normal.fill.consecutiveAskLevels.perFill.10", tenFillTotalGas, COUNT_TEN);
        _emitGasPerUnit("normal.fill.consecutiveAskLevels.perFill.50", fiftyFillTotalGas, COUNT_FIFTY);

        _assertIncreasingTotals(oneFillTotalGas, tenFillTotalGas, fiftyFillTotalGas);
    }

    function _measureLimitOrderSell() private returns (uint256 gasUsed) {
        address bookMarket = address(_deployMarket());
        uint256 price = _price(START_QUOTE_PER_BASE);

        vm.startPrank(alice);
        crystal.limitOrder(bookMarket, false, INTERNAL_LIMIT_OPTIONS, price, BENCH_ORDER_SIZE, alice);
        crystal.limitOrder(bookMarket, false, INTERNAL_LIMIT_OPTIONS, price, BENCH_ORDER_SIZE, alice);
        crystal.limitOrder(bookMarket, false, INTERNAL_LIMIT_OPTIONS, price, BENCH_ORDER_SIZE, alice);
        uint256 startGas = gasleft();
        crystal.limitOrder(bookMarket, false, INTERNAL_LIMIT_OPTIONS, price, BENCH_ORDER_SIZE, alice);
        gasUsed = startGas - gasleft();
        vm.stopPrank();
    }

    function _measureMarketBuy() private returns (uint256 gasUsed) {
        address bookMarket = address(_deployMarket());
        uint256 price = _price(START_QUOTE_PER_BASE);
        vm.prank(alice);
        crystal.limitOrder(bookMarket, false, INTERNAL_LIMIT_OPTIONS, price, 10 ether, alice);
        vm.prank(bob);
        uint256 startGas = gasleft();
        crystal.marketOrder(
            bookMarket,
            true,
            true,
            INTERNAL_MARKET_OPTIONS,
            ORDER_TYPES_NORMAL,
            1_000 * QUOTE_UNIT,
            price + 1,
            address(0),
            bob
        );
        gasUsed = startGas - gasleft();
    }

    function _measureAddLiquidity() private returns (uint256 gasUsed) {
        address ammMarket = address(_deployMarket());
        uint256 startGas = gasleft();
        crystal.addLiquidity(ammMarket, address(this), 10_000 * QUOTE_UNIT, 20 ether, 0, 0);
        gasUsed = startGas - gasleft();
    }

    function _measureGetAmountsOut() private returns (uint256 gasUsed) {
        address ammMarket = address(_deployMarket());
        address[] memory path = new address[](2);
        path[0] = address(quote);
        path[1] = address(weth);
        crystal.addLiquidity(ammMarket, address(this), 10_000 * QUOTE_UNIT, 20 ether, 0, 0);
        uint256 startGas = gasleft();
        crystal.getAmountsOut(1_000 * QUOTE_UNIT, path);
        gasUsed = startGas - gasleft();
    }

    function _measureConsecutiveAskFills(uint256 fillCount) private returns (uint256 gasUsed) {
        address bookMarket = address(_deployMarket());
        uint256 worstPrice = _seedConsecutiveAskLevels(bookMarket, fillCount);

        vm.prank(bob);
        uint256 startGas = gasleft();
        crystal.marketOrder(
            bookMarket,
            true,
            false,
            INTERNAL_MARKET_OPTIONS,
            ORDER_TYPES_NORMAL,
            fillCount * BENCH_ORDER_SIZE,
            worstPrice,
            address(0),
            bob
        );
        gasUsed = startGas - gasleft();
    }

    function _seedConsecutiveAskLevels(address bookMarket, uint256 fillCount) private returns (uint256 worstPrice) {
        uint256 startTick = CrystalMath._priceToTick(_price(START_QUOTE_PER_BASE), MARKET_TICK_SIZE);

        vm.startPrank(alice);
        for (uint256 i; i < SEEDED_ASK_LEVELS; ++i) {
            uint256 price = CrystalMath._tickToPrice(startTick + i, MARKET_TICK_SIZE);
            crystal.limitOrder(bookMarket, false, INTERNAL_LIMIT_OPTIONS, price, BENCH_ORDER_SIZE, alice);
            if (i + 1 == fillCount) {
                worstPrice = price;
            }
        }
        vm.stopPrank();
    }

    function _measureFallbackCloidCancelReplaceSamePage(uint256 orderCount, uint256 firstCloid)
        private
        returns (uint256 gasUsed)
    {
        address bookMarket = address(_deployMarket());
        uint256 price = _price(START_QUOTE_PER_BASE);
        bytes memory placeData = _fallbackCloidSellOrderData(bookMarket, orderCount, firstCloid, price);
        bytes memory cancelReplaceData = _fallbackCloidCancelReplaceOrderData(bookMarket, orderCount, firstCloid, price);

        _executeFallbackAs(alice, placeData);

        vm.prank(alice);
        uint256 startGas = gasleft();
        (bool success, bytes memory returnData) = address(crystal).call(cancelReplaceData);
        gasUsed = startGas - gasleft();
        if (!success) {
            assembly {
                revert(add(returnData, 32), mload(returnData))
            }
        }
    }

    function _fallbackCloidSellOrderData(address bookMarket, uint256 orderCount, uint256 firstCloid, uint256 price)
        private
        pure
        returns (bytes memory data)
    {
        data = abi.encodePacked(_batchHeaderFor(bookMarket, BATCH_BALANCE_MODE_INTERNAL, orderCount));
        for (uint256 i; i < orderCount; ++i) {
            data = abi.encodePacked(
                data, _limitAction(BatchAction.SellLimit, true, firstCloid + i, price, BENCH_ORDER_SIZE)
            );
        }
    }

    function _fallbackCloidCancelReplaceOrderData(
        address bookMarket,
        uint256 orderCount,
        uint256 firstCloid,
        uint256 price
    ) private pure returns (bytes memory data) {
        data = abi.encodePacked(_batchHeaderFor(bookMarket, BATCH_BALANCE_MODE_INTERNAL, orderCount * 2));
        for (uint256 i; i < orderCount; ++i) {
            uint256 cloid = firstCloid + i;
            data = abi.encodePacked(
                data,
                _cancelCloidAction(true, cloid),
                _limitAction(BatchAction.SellLimit, true, cloid, price, BENCH_ORDER_SIZE)
            );
        }
    }

    function _executeFallbackAs(address caller, bytes memory data) private {
        vm.prank(caller);
        (bool success, bytes memory returnData) = address(crystal).call(data);
        if (!success) {
            assembly {
                revert(add(returnData, 32), mload(returnData))
            }
        }
    }

    function _batchHeaderFor(address market_, uint256 balanceMode, uint256 actionCount) private pure returns (bytes32) {
        return bytes32(
            (balanceMode << BATCH_BALANCE_MODE_SHIFT) | (actionCount << BATCH_ACTION_COUNT_SHIFT) | uint160(market_)
        );
    }

    function _limitAction(BatchAction action, bool requireSuccess, uint256 cloid, uint256 price, uint256 size)
        private
        pure
        returns (bytes32)
    {
        return bytes32(
            (uint256(action) << BATCH_ACTION_SHIFT) | (requireSuccess ? (uint256(1) << BATCH_REQUIRE_SUCCESS_SHIFT) : 0)
                | ((cloid & BATCH_CLOID_MASK) << BATCH_CLOID_SHIFT)
                | ((price & BATCH_PARAM1_MASK) << BATCH_PARAM1_SHIFT) | (size & BATCH_PARAM2_MASK)
        );
    }

    function _cancelCloidAction(bool requireSuccess, uint256 cloid) private pure returns (bytes32) {
        return bytes32(
            (uint256(BatchAction.CancelOrder) << BATCH_ACTION_SHIFT)
                | (requireSuccess ? (uint256(1) << BATCH_REQUIRE_SUCCESS_SHIFT) : 0)
                | ((cloid & BATCH_CLOID_MASK) << BATCH_CLOID_SHIFT)
        );
    }

    function _emitGasUsed(string memory name, uint256 gasUsed) private {
        console2.log(name);
        console2.log("gasUsed", gasUsed);
        emit GasUsed(name, gasUsed);
    }

    function _emitGasPerUnit(string memory name, uint256 totalGasUsed, uint256 unitCount) private {
        uint256 gasPerUnit = totalGasUsed / unitCount;
        console2.log(name);
        console2.log("gasPerUnit", gasPerUnit);
        emit GasUsed(name, gasPerUnit);
    }

    function _assertPositive(uint256 gasUsed, string memory reason) private pure {
        assertGt(gasUsed, 0, reason);
    }

    function _assertIncreasingTotals(uint256 one, uint256 ten, uint256 fifty) private pure {
        assertGt(one, 0, "assert one > 0");
        assertGt(ten, one, "assert ten > one");
        assertGt(fifty, ten, "assert fifty > ten");
    }
}
