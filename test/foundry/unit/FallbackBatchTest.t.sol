// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ICrystal } from "../../../contracts/interfaces/ICrystal.sol";
import { TestToken } from "../../../contracts/mocks/TestToken.sol";
import { BaseTest } from "../BaseTest.t.sol";

contract FallbackBatchTest is BaseTest {
    function testCrystalFallbackPlacesBuyLimitOrderFromEncodedCalldata() public {
        uint256 price = _price(500);
        uint256 size = 1_000 * QUOTE_UNIT;
        uint256 aliceQuoteBefore = quote.balanceOf(alice);

        _executeFallbackAs(
            alice,
            abi.encodePacked(
                _batchHeader(BATCH_BALANCE_MODE_EXTERNAL, 1), _limitAction(BatchAction.BuyLimit, true, 0, price, size)
            )
        );

        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);
        ICrystal.Order memory order = crystal.getOrder(address(market), price, level.latestNativeId);
        ICrystal.MarketInfo memory info = crystal.getMarket(address(market));

        assertGt(level.latestNativeId, 0, "assert level.latestNativeId > 0");
        assertEq(order.isBuy, true, "assert order.isBuy == true");
        assertEq(order.market, address(market), "assert order.market == address(market)");
        assertEq(order.price, price, "assert order.price == price");
        assertEq(order.size, size, "assert order.size == size");
        assertEq(order.userId, crystal.addressToUserId(alice), "assert order.userId == crystal.addressToUserId(alice)");
        assertEq(level.size, size, "assert level.size == size");
        assertEq(level.latest, level.latestNativeId, "assert level.latest == level.latestNativeId");
        assertEq(level.fillNext, level.latestNativeId, "assert level.fillNext == level.latestNativeId");
        assertEq(info.highestBid, price, "assert info.highestBid == price");
        assertEq(
            quote.balanceOf(alice), aliceQuoteBefore - size, "assert quote.balanceOf(alice) == aliceQuoteBefore - size"
        );
    }

    function testCrystalFallbackExecutesMultipleLimitActionsFromOneCalldata() public {
        uint256 bidPrice = _price(400);
        uint256 askPrice = _price(600);
        uint256 bidSize = 500 * QUOTE_UNIT;
        uint256 askSize = 2 ether;

        _executeFallbackAs(
            alice,
            abi.encodePacked(
                _batchHeader(BATCH_BALANCE_MODE_EXTERNAL, 2),
                _limitAction(BatchAction.BuyLimit, true, 0, bidPrice, bidSize),
                _limitAction(BatchAction.SellLimit, true, 0, askPrice, askSize)
            )
        );

        ICrystal.PriceLevel memory bidLevel = crystal.getPriceLevel(address(market), bidPrice);
        ICrystal.PriceLevel memory askLevel = crystal.getPriceLevel(address(market), askPrice);
        ICrystal.MarketInfo memory info = crystal.getMarket(address(market));

        assertEq(bidLevel.size, bidSize, "assert bidLevel.size == bidSize");
        assertEq(askLevel.size, askSize, "assert askLevel.size == askSize");
        assertGt(bidLevel.latestNativeId, 0, "assert bidLevel.latestNativeId > 0");
        assertGt(askLevel.latestNativeId, 0, "assert askLevel.latestNativeId > 0");
        assertEq(info.highestBid, bidPrice, "assert info.highestBid == bidPrice");
        assertEq(info.lowestAsk, askPrice, "assert info.lowestAsk == askPrice");
    }

    function testCrystalFallbackInternalBalanceModeLocksDepositedQuote() public {
        uint256 price = _price(500);
        uint256 size = 750 * QUOTE_UNIT;
        uint256 aliceWalletQuoteBefore = quote.balanceOf(alice);
        (uint256 totalBefore, uint256 availableBefore, uint256 lockedBefore) =
            crystal.getDepositedBalance(alice, address(quote));

        _executeFallbackAs(
            alice,
            abi.encodePacked(
                _batchHeader(BATCH_BALANCE_MODE_INTERNAL, 1), _limitAction(BatchAction.BuyLimit, true, 0, price, size)
            )
        );

        (uint256 totalAfter, uint256 availableAfter, uint256 lockedAfter) =
            crystal.getDepositedBalance(alice, address(quote));
        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);

        assertEq(level.size, size, "assert level.size == size");
        assertEq(totalAfter, totalBefore, "assert totalAfter == totalBefore");
        assertEq(availableAfter, availableBefore - size, "assert availableAfter == availableBefore - size");
        assertEq(lockedAfter, lockedBefore + size, "assert lockedAfter == lockedBefore + size");
        assertEq(
            quote.balanceOf(alice), aliceWalletQuoteBefore, "assert quote.balanceOf(alice) == aliceWalletQuoteBefore"
        );
    }

    function testCrystalFallbackCancelsBuyLimitOrderByNativeId() public {
        uint256 price = _price(500);
        uint256 size = 1_000 * QUOTE_UNIT;

        vm.prank(alice);
        uint256 orderId = crystal.limitOrder(address(market), true, 0, price, size, alice);

        ICrystal.PriceLevel memory levelBefore = crystal.getPriceLevel(address(market), price);
        assertEq(levelBefore.size, size, "assert levelBefore.size == size");
        assertEq(levelBefore.latestNativeId, orderId, "assert levelBefore.latestNativeId == orderId");

        _executeFallbackAs(
            alice, abi.encodePacked(_batchHeader(BATCH_BALANCE_MODE_EXTERNAL, 1), _cancelAction(false, price, orderId))
        );

        ICrystal.PriceLevel memory levelAfter = crystal.getPriceLevel(address(market), price);
        ICrystal.Order memory orderAfter = crystal.getOrder(address(market), price, orderId);

        assertEq(levelAfter.size, 0, "assert levelAfter.size == 0");
        assertEq(orderAfter.size, 0, "assert orderAfter.size == 0");
    }

    function testCrystalFallbackCancelsLinearBuyLimitOrderByNativeId() public {
        TestToken quote18 = new TestToken("Linear Quote", "LQ", 18);
        TestToken base18 = new TestToken("Linear Base", "LB", 18);
        uint256 price = 1e15;
        uint256 size = 2 ether;

        quote18.mint(alice, 1_000_000 ether);
        base18.mint(alice, 1_000_000 ether);

        vm.startPrank(alice);
        quote18.approve(address(crystal), type(uint256).max);
        base18.approve(address(crystal), type(uint256).max);
        vm.stopPrank();

        address linearMarket = crystal.deploy(
            false, address(quote18), address(base18), 0, 18, 1e15, 10 ether, 1 ether, 100_000, 100_000
        );

        vm.prank(alice);
        uint256 orderId = crystal.limitOrder(linearMarket, true, 0, price, size, alice);

        ICrystal.PriceLevel memory levelBefore = crystal.getPriceLevel(linearMarket, price);
        assertEq(levelBefore.size, size, "assert levelBefore.size == size");
        assertEq(levelBefore.latestNativeId, orderId, "assert levelBefore.latestNativeId == orderId");

        _executeFallbackAs(
            alice,
            abi.encodePacked(
                _batchHeaderFor(linearMarket, BATCH_BALANCE_MODE_EXTERNAL, 1), _cancelAction(false, price, orderId)
            )
        );

        ICrystal.PriceLevel memory levelAfter = crystal.getPriceLevel(linearMarket, price);
        ICrystal.Order memory orderAfter = crystal.getOrder(linearMarket, price, orderId);

        assertEq(levelAfter.size, 0, "assert levelAfter.size == 0");
        assertEq(orderAfter.size, 0, "assert orderAfter.size == 0");
    }

    function _batchHeader(uint256 balanceMode, uint256 actionCount) private view returns (bytes32) {
        return _batchHeaderFor(address(market), balanceMode, actionCount);
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

    function _cancelAction(bool requireSuccess, uint256 price, uint256 orderId) private pure returns (bytes32) {
        return bytes32(
            (uint256(BatchAction.CancelOrder) << BATCH_ACTION_SHIFT)
                | (requireSuccess ? (uint256(1) << BATCH_REQUIRE_SUCCESS_SHIFT) : 0)
                | ((price & BATCH_PARAM1_MASK) << BATCH_PARAM1_SHIFT) | (orderId & BATCH_PARAM2_MASK)
        );
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
