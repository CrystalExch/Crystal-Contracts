// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ICrystal } from "../../../contracts/interfaces/ICrystal.sol";
import { BaseFuzzTest } from "../BaseFuzzTest.t.sol";

contract FallbackAndBatchProperties is BaseFuzzTest {
    uint256 private constant BATCH_NATIVE_ID_MASK = (uint256(1) << 41) - 1;

    struct BookSnapshot {
        uint256 levelSize;
        uint256 orderSize;
        uint256 walletQuote;
        uint256 totalQuote;
        uint256 availableQuote;
        uint256 lockedQuote;
        uint256 walletBase;
    }

    function testFuzzMultiBatchRequiredFailureRollsBackEarlierMarketBatch(uint256 quotePerBaseSeed, uint256 sizeSeed)
        public
    {
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 size = bound(sizeSeed, MARKET_MIN_SIZE * 2, DEPOSIT_QUOTE_AMOUNT / 2);
        BookSnapshot memory beforeSnapshot = _snapshot(alice, price, 0);
        ICrystal.Batch[] memory batches = new ICrystal.Batch[](2);
        batches[0] = ICrystal.Batch({
            market: address(market), actions: _singleAction(BatchAction.BuyLimit, price, size, 0), options: 0
        });
        batches[1] = ICrystal.Batch({
            market: address(market), actions: _singleAction(BatchAction.CompleteBuy, price, 2 ether, 0), options: 0
        });

        vm.prank(alice);
        vm.expectRevert();
        crystal.multiBatchOrders(batches, block.timestamp, address(0));

        _assertSnapshot(alice, price, 0, beforeSnapshot);
    }

    function testFuzzFallbackLimitBuyMatchesStructuredBatch(uint256 quotePerBaseSeed, uint256 sizeSeed) public {
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 size = bound(sizeSeed, MARKET_MIN_SIZE * 2, DEPOSIT_QUOTE_AMOUNT / 2);
        uint256 state = vm.snapshotState();

        vm.prank(alice);
        crystal.batchOrders(
            address(market), _singleAction(BatchAction.BuyLimit, price, size, 0), 0, block.timestamp, address(0), alice
        );
        ICrystal.PriceLevel memory structuredLevel = crystal.getPriceLevel(address(market), price);
        BookSnapshot memory structured = _snapshot(alice, price, structuredLevel.latestNativeId);

        assertTrue(vm.revertToState(state), "assert vm.revertToState(state)");

        _executeFallbackAs(
            alice,
            abi.encodePacked(
                _batchHeader(BATCH_BALANCE_MODE_EXTERNAL, 1), _limitAction(BatchAction.BuyLimit, true, 0, price, size)
            )
        );
        ICrystal.PriceLevel memory fallbackLevel = crystal.getPriceLevel(address(market), price);
        BookSnapshot memory fallbackSnapshot = _snapshot(alice, price, fallbackLevel.latestNativeId);

        _assertSnapshotsEqual(fallbackSnapshot, structured);
    }

    function testFallbackCancelAndDecreaseMatchStructuredBatch() public {
        uint256 price = _price(500);
        uint256 size = 2_000 * QUOTE_UNIT;
        uint256 decrease = 500 * QUOTE_UNIT;

        vm.prank(alice);
        uint256 orderId = crystal.limitOrder(address(market), true, 0, price, size, alice);
        uint256 state = vm.snapshotState();

        vm.prank(alice);
        crystal.batchOrders(
            address(market),
            _singleAction(BatchAction.DecreaseOrder, price, decrease, orderId),
            0,
            block.timestamp,
            address(0),
            alice
        );
        BookSnapshot memory structuredDecrease = _snapshot(alice, price, orderId);

        assertTrue(vm.revertToState(state), "assert vm.revertToState(state)");

        _executeFallbackAs(
            alice,
            abi.encodePacked(
                _batchHeader(BATCH_BALANCE_MODE_EXTERNAL, 1), _decreaseAction(true, price, orderId, decrease)
            )
        );
        BookSnapshot memory fallbackDecrease = _snapshot(alice, price, orderId);

        _assertSnapshotsEqual(fallbackDecrease, structuredDecrease);

        state = vm.snapshotState();
        vm.prank(alice);
        crystal.batchOrders(
            address(market),
            _singleAction(BatchAction.CancelOrder, price, orderId, 0),
            0,
            block.timestamp,
            address(0),
            alice
        );
        BookSnapshot memory structuredCancel = _snapshot(alice, price, orderId);

        assertTrue(vm.revertToState(state), "assert vm.revertToState(state)");

        _executeFallbackAs(
            alice, abi.encodePacked(_batchHeader(BATCH_BALANCE_MODE_EXTERNAL, 1), _cancelAction(true, price, orderId))
        );
        BookSnapshot memory fallbackCancel = _snapshot(alice, price, orderId);

        _assertSnapshotsEqual(fallbackCancel, structuredCancel);
    }

    function testFallbackMarketBuyMatchesStructuredBatch() public {
        uint256 price = _price(500);
        uint256 askSize = 10 ether;
        uint256 quoteIn = 1_000 * QUOTE_UNIT;

        vm.prank(alice);
        crystal.limitOrder(address(market), false, 0, price, askSize, alice);
        uint256 state = vm.snapshotState();

        vm.prank(bob);
        crystal.batchOrders(
            address(market),
            _singleAction(BatchAction.PartialBuy, price, quoteIn, 0),
            0,
            block.timestamp,
            address(0),
            bob
        );
        BookSnapshot memory structured = _snapshot(bob, price, 0);
        uint256 structuredLevelSize = crystal.getPriceLevel(address(market), price).size;

        assertTrue(vm.revertToState(state), "assert vm.revertToState(state)");

        _executeFallbackAs(
            bob,
            abi.encodePacked(
                _batchHeader(BATCH_BALANCE_MODE_EXTERNAL, 1),
                _marketAction(BatchAction.PartialBuy, true, 0, price, quoteIn)
            )
        );
        BookSnapshot memory fallbackSnapshot = _snapshot(bob, price, 0);
        uint256 fallbackLevelSize = crystal.getPriceLevel(address(market), price).size;

        _assertSnapshotsEqual(fallbackSnapshot, structured);
        assertEq(fallbackLevelSize, structuredLevelSize, "assert fallbackLevelSize == structuredLevelSize");
    }

    function _singleAction(BatchAction action, uint256 param1, uint256 param2, uint256 param3)
        private
        pure
        returns (ICrystal.Action[] memory actions)
    {
        actions = new ICrystal.Action[](1);
        actions[0] = ICrystal.Action({
            isRequireSuccess: true, action: uint256(action), param1: param1, param2: param2, param3: param3
        });
    }

    function _batchHeader(uint256 balanceMode, uint256 actionCount) private view returns (bytes32) {
        return bytes32(
            (balanceMode << BATCH_BALANCE_MODE_SHIFT) | (actionCount << BATCH_ACTION_COUNT_SHIFT)
                | uint160(address(market))
        );
    }

    function _limitAction(BatchAction action, bool requireSuccess, uint256 cloid, uint256 price, uint256 size)
        private
        pure
        returns (bytes32)
    {
        return _actionWord(action, requireSuccess, cloid, price, size);
    }

    function _marketAction(BatchAction action, bool requireSuccess, uint256 cloid, uint256 worstPrice, uint256 size)
        private
        pure
        returns (bytes32)
    {
        return _actionWord(action, requireSuccess, cloid, worstPrice, size);
    }

    function _cancelAction(bool requireSuccess, uint256 price, uint256 orderId) private pure returns (bytes32) {
        return bytes32(
            (uint256(BatchAction.CancelOrder) << BATCH_ACTION_SHIFT)
                | (requireSuccess ? (uint256(1) << BATCH_REQUIRE_SUCCESS_SHIFT) : 0)
                | ((price & BATCH_PARAM1_MASK) << BATCH_PARAM1_SHIFT) | (orderId & BATCH_PARAM2_MASK)
        );
    }

    function _decreaseAction(bool requireSuccess, uint256 price, uint256 orderId, uint256 decrease)
        private
        pure
        returns (bytes32)
    {
        return bytes32(
            (uint256(BatchAction.DecreaseOrder) << BATCH_ACTION_SHIFT)
                | (requireSuccess ? (uint256(1) << BATCH_REQUIRE_SUCCESS_SHIFT) : 0)
                | ((orderId & BATCH_NATIVE_ID_MASK) << BATCH_CLOID_SHIFT)
                | ((price & BATCH_PARAM1_MASK) << BATCH_PARAM1_SHIFT) | (decrease & BATCH_PARAM2_MASK)
        );
    }

    function _actionWord(BatchAction action, bool requireSuccess, uint256 cloid, uint256 param1, uint256 param2)
        private
        pure
        returns (bytes32)
    {
        return bytes32(
            (uint256(action) << BATCH_ACTION_SHIFT) | (requireSuccess ? (uint256(1) << BATCH_REQUIRE_SUCCESS_SHIFT) : 0)
                | ((cloid & BATCH_CLOID_MASK) << BATCH_CLOID_SHIFT)
                | ((param1 & BATCH_PARAM1_MASK) << BATCH_PARAM1_SHIFT) | (param2 & BATCH_PARAM2_MASK)
        );
    }

    function _snapshot(address user, uint256 price, uint256 orderId)
        private
        view
        returns (BookSnapshot memory snapshot)
    {
        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);
        ICrystal.Order memory order = crystal.getOrder(address(market), price, orderId);
        snapshot.levelSize = level.size;
        snapshot.orderSize = order.size;
        snapshot.walletQuote = quote.balanceOf(user);
        snapshot.walletBase = weth.balanceOf(user);
        (snapshot.totalQuote, snapshot.availableQuote, snapshot.lockedQuote) =
            crystal.getDepositedBalance(user, address(quote));
    }

    function _assertSnapshot(address user, uint256 price, uint256 orderId, BookSnapshot memory expected) private view {
        _assertSnapshotsEqual(_snapshot(user, price, orderId), expected);
    }

    function _assertSnapshotsEqual(BookSnapshot memory actual, BookSnapshot memory expected) private pure {
        assertEq(actual.levelSize, expected.levelSize, "assert actual.levelSize == expected.levelSize");
        assertEq(actual.orderSize, expected.orderSize, "assert actual.orderSize == expected.orderSize");
        assertEq(actual.walletQuote, expected.walletQuote, "assert actual.walletQuote == expected.walletQuote");
        assertEq(actual.totalQuote, expected.totalQuote, "assert actual.totalQuote == expected.totalQuote");
        assertEq(
            actual.availableQuote, expected.availableQuote, "assert actual.availableQuote == expected.availableQuote"
        );
        assertEq(actual.lockedQuote, expected.lockedQuote, "assert actual.lockedQuote == expected.lockedQuote");
        assertEq(actual.walletBase, expected.walletBase, "assert actual.walletBase == expected.walletBase");
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
}
