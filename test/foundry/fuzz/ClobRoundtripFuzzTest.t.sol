// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ICrystal } from "../../../contracts/interfaces/ICrystal.sol";
import { BaseFuzzTest } from "../BaseFuzzTest.t.sol";

contract ClobRoundtripFuzzTest is BaseFuzzTest {
    uint256 private constant PRICE_LEVEL_SIZE_OFFSET = 2 ** 128;
    uint256 private constant MAX_ROUNDTRIP_BASE_SIZE = 100 ether;
    uint256 private constant MAX_ROUNDTRIP_BID_SIZE = 1_000 * QUOTE_UNIT;
    uint256 private constant MAX_REMAINDER_QUOTE = 10_000 * QUOTE_UNIT;
    uint256 private constant MAX_REMAINDER_BASE = 10 ether;

    struct BalanceSnapshot {
        uint256 quote;
        uint256 weth;
        uint256 depositedTotal;
        uint256 depositedAvailable;
        uint256 depositedLocked;
    }

    struct MarketResult {
        uint256 amountIn;
        uint256 amountOut;
        uint256 id;
    }

    function testFuzzQuoteThenMarketBuyRoundtrip(uint256 quotePerBaseSeed, uint256 askSizeSeed, uint256 quoteInSeed)
        public
    {
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 askSize = _boundRoundtripAskSize(askSizeSeed, price);
        uint256 quoteIn = _boundPartialQuoteIn(quoteInSeed, askSize, price);

        vm.prank(alice);
        crystal.limitOrder(address(market), false, 0, price, askSize, alice);

        MarketResult memory quoted = _quoteResult(true, true, true, quoteIn, price);
        BalanceSnapshot memory bobBefore = _snapshot(bob, address(quote));
        MarketResult memory executed = _executeMarketOrder(bob, true, true, quoteIn, price);

        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);

        assertEq(executed.amountIn, quoted.amountIn, "assert executed.amountIn == quoted.amountIn");
        assertEq(executed.amountOut, quoted.amountOut, "assert executed.amountOut == quoted.amountOut");
        assertEq(executed.id, 0, "assert executed.id == 0");
        assertEq(level.size, askSize - executed.amountOut, "assert level.size == askSize - executed.amountOut");
        assertEq(
            quote.balanceOf(bob),
            bobBefore.quote - executed.amountIn,
            "assert quote.balanceOf(bob) == bobBefore.quote - executed.amountIn"
        );
        assertEq(
            weth.balanceOf(bob),
            bobBefore.weth + executed.amountOut,
            "assert weth.balanceOf(bob) == bobBefore.weth + executed.amountOut"
        );
    }

    function testFuzzQuoteThenMarketSellRoundtrip(uint256 quotePerBaseSeed, uint256 bidSizeSeed, uint256 baseInSeed)
        public
    {
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 bidSize = _boundRoundtripBidSize(bidSizeSeed);
        uint256 baseIn = _boundPartialBaseIn(baseInSeed, bidSize, price);

        vm.prank(alice);
        crystal.limitOrder(address(market), true, 0, price, bidSize, alice);

        MarketResult memory quoted = _quoteResult(false, true, true, baseIn, price);
        BalanceSnapshot memory bobBefore = _snapshot(bob, address(weth));
        MarketResult memory executed = _executeMarketOrder(bob, false, true, baseIn, price);

        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);

        assertEq(executed.amountIn, quoted.amountIn, "assert executed.amountIn == quoted.amountIn");
        assertEq(executed.amountOut, quoted.amountOut, "assert executed.amountOut == quoted.amountOut");
        assertEq(executed.id, 0, "assert executed.id == 0");
        assertLt(level.size, bidSize, "assert level.size < bidSize");
        assertEq(
            quote.balanceOf(bob),
            bobBefore.quote + executed.amountOut,
            "assert quote.balanceOf(bob) == bobBefore.quote + executed.amountOut"
        );
        assertEq(
            weth.balanceOf(bob),
            bobBefore.weth - executed.amountIn,
            "assert weth.balanceOf(bob) == bobBefore.weth - executed.amountIn"
        );
    }

    function testFuzzBuyQuoteExactOutputExactInputRoundtrip(
        uint256 quotePerBaseSeed,
        uint256 askSizeSeed,
        uint256 desiredBaseSeed
    ) public {
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 askSize = _boundRoundtripAskSize(askSizeSeed, price);
        uint256 desiredBaseOut = bound(desiredBaseSeed, _minBaseForQuote(MARKET_MIN_SIZE, price), askSize / 2);

        vm.prank(alice);
        crystal.limitOrder(address(market), false, 0, price, askSize, alice);

        MarketResult memory exactOutput = _quoteResult(true, false, true, desiredBaseOut, price);
        MarketResult memory roundtrip = _quoteResult(true, true, true, exactOutput.amountIn, price);

        uint256 baseTolerance = (_minBaseForQuote(1, price) * 2) + 2;

        assertEq(exactOutput.amountOut, desiredBaseOut, "assert exactOutput.amountOut == desiredBaseOut");
        assertLe(roundtrip.amountIn, exactOutput.amountIn, "assert roundtrip.amountIn <= exactOutput.amountIn");
        assertLe(
            _absDiff(roundtrip.amountOut, desiredBaseOut),
            baseTolerance,
            "assert abs(roundtrip.amountOut - desiredBaseOut) <= baseTolerance"
        );
    }

    function testFuzzSellQuoteExactOutputExactInputRoundtrip(
        uint256 quotePerBaseSeed,
        uint256 bidSizeSeed,
        uint256 desiredQuoteSeed
    ) public {
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 bidSize = _boundRoundtripBidSize(bidSizeSeed);
        uint256 desiredQuoteOut = bound(desiredQuoteSeed, MARKET_MIN_SIZE, bidSize / 2);

        vm.prank(alice);
        crystal.limitOrder(address(market), true, 0, price, bidSize, alice);

        MarketResult memory exactOutput = _quoteResult(false, false, true, desiredQuoteOut, price);
        MarketResult memory roundtrip = _quoteResult(false, true, true, exactOutput.amountIn, price);

        assertEq(exactOutput.amountOut, desiredQuoteOut, "assert exactOutput.amountOut == desiredQuoteOut");
        assertLe(roundtrip.amountIn, exactOutput.amountIn, "assert roundtrip.amountIn <= exactOutput.amountIn");
        assertLe(
            _absDiff(roundtrip.amountOut, desiredQuoteOut), 1, "assert abs(roundtrip.amountOut - desiredQuoteOut) <= 1"
        );
    }

    function testFuzzBuyLimitDecreaseCancelConservationRoundtrip(
        uint256 quotePerBaseSeed,
        uint256 sizeSeed,
        uint256 decreaseSeed
    ) public {
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 size = bound(sizeSeed, MARKET_MIN_SIZE * 2, MAX_QUOTE_FUZZ_AMOUNT);
        uint256 decreaseAmount = bound(decreaseSeed, 1, size - MARKET_MIN_SIZE);
        BalanceSnapshot memory beforeSnapshot = _snapshot(alice, address(quote));

        vm.startPrank(alice);
        uint256 orderId = crystal.limitOrder(address(market), true, 0, price, size, alice);
        crystal.batchOrders(
            address(market),
            _singleAction(BatchAction.DecreaseOrder, price, decreaseAmount, orderId),
            0,
            block.timestamp,
            address(0),
            alice
        );
        uint256 cancelledSize = crystal.cancelOrder(address(market), 0, price, orderId, alice);
        vm.stopPrank();

        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);
        ICrystal.Order memory order = crystal.getOrder(address(market), price, orderId);

        assertEq(cancelledSize, size - decreaseAmount, "assert cancelledSize == size - decreaseAmount");
        assertEq(level.size, 0, "assert level.size == 0");
        assertEq(order.size, 0, "assert order.size == 0");
        _assertSnapshot(alice, address(quote), beforeSnapshot);
    }

    function testFuzzSellLimitDecreaseCancelConservationRoundtrip(
        uint256 quotePerBaseSeed,
        uint256 sizeSeed,
        uint256 decreaseSeed
    ) public {
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 minRemaining = _minBaseForQuote(MARKET_MIN_SIZE, price);
        uint256 minSize = _minBaseForQuote(MARKET_MIN_SIZE * 2, price);
        if (minSize <= minRemaining) {
            minSize = minRemaining + 1;
        }
        uint256 size = bound(sizeSeed, minSize, MAX_BASE_FUZZ_AMOUNT);
        uint256 decreaseAmount = bound(decreaseSeed, 1, size - minRemaining);
        BalanceSnapshot memory beforeSnapshot = _snapshot(alice, address(weth));

        vm.startPrank(alice);
        uint256 orderId = crystal.limitOrder(address(market), false, 0, price, size, alice);
        crystal.batchOrders(
            address(market),
            _singleAction(BatchAction.DecreaseOrder, price, decreaseAmount, orderId),
            0,
            block.timestamp,
            address(0),
            alice
        );
        uint256 cancelledSize = crystal.cancelOrder(address(market), 0, price, orderId, alice);
        vm.stopPrank();

        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);
        ICrystal.Order memory order = crystal.getOrder(address(market), price, orderId);

        assertEq(cancelledSize, size - decreaseAmount, "assert cancelledSize == size - decreaseAmount");
        assertEq(level.size, 0, "assert level.size == 0");
        assertEq(order.size, 0, "assert order.size == 0");
        _assertSnapshot(alice, address(weth), beforeSnapshot);
    }

    function testFuzzMarketToLimitBuyRemainderRoundtrip(
        uint256 quotePerBaseSeed,
        uint256 askSizeSeed,
        uint256 extraQuoteSeed
    ) public {
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 askSize = _boundRoundtripAskSize(askSizeSeed, price);

        vm.prank(alice);
        crystal.limitOrder(address(market), false, 0, price, askSize, alice);

        MarketResult memory fill = _quoteResult(true, false, true, askSize, price);
        uint256 extraQuote = bound(extraQuoteSeed, MARKET_MIN_SIZE, MAX_REMAINDER_QUOTE);
        uint256 marketToLimitSize = fill.amountIn + extraQuote;

        vm.prank(bob);
        crystal.batchOrders(
            address(market),
            _singleAction(BatchAction.MarketToLimitBuy, price, marketToLimitSize, 0),
            0,
            block.timestamp,
            address(0),
            bob
        );

        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);
        ICrystal.Order memory order = crystal.getOrder(address(market), price, level.latestNativeId);

        assertEq(fill.amountOut, askSize, "assert fill.amountOut == askSize");
        assertEq(
            level.size, marketToLimitSize - fill.amountIn, "assert level.size == marketToLimitSize - fill.amountIn"
        );
        assertEq(order.isBuy, true, "assert order.isBuy == true");
        assertEq(
            order.size, marketToLimitSize - fill.amountIn, "assert order.size == marketToLimitSize - fill.amountIn"
        );
    }

    function testFuzzMarketToLimitSellRemainderRoundtrip(
        uint256 quotePerBaseSeed,
        uint256 bidSizeSeed,
        uint256 extraBaseSeed
    ) public {
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 bidSize = _boundRoundtripBidSize(bidSizeSeed);

        vm.prank(alice);
        crystal.limitOrder(address(market), true, 0, price, bidSize, alice);

        MarketResult memory fill = _quoteResult(false, true, false, 1_000 ether, price);
        uint256 extraBase = bound(extraBaseSeed, _minBaseForQuote(MARKET_MIN_SIZE, price), MAX_REMAINDER_BASE);
        uint256 marketToLimitSize = fill.amountIn + extraBase;

        vm.prank(bob);
        crystal.batchOrders(
            address(market),
            _singleAction(BatchAction.MarketToLimitSell, price, marketToLimitSize, 0),
            0,
            block.timestamp,
            address(0),
            bob
        );

        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);
        ICrystal.Order memory order = crystal.getOrder(address(market), price, level.latestNativeId);

        assertGt(fill.amountOut, 0, "assert fill.amountOut > 0");
        assertEq(
            level.size, marketToLimitSize - fill.amountIn, "assert level.size == marketToLimitSize - fill.amountIn"
        );
        assertEq(order.isBuy, false, "assert order.isBuy == false");
        assertEq(
            order.size, marketToLimitSize - fill.amountIn, "assert order.size == marketToLimitSize - fill.amountIn"
        );
    }

    function testFuzzBuyCloidLifecycleRoundtrip(
        uint256 quotePerBaseSeed,
        uint256 newQuotePerBaseSeed,
        uint256 sizeSeed,
        uint256 decreaseSeed,
        uint256 cloidSeed
    ) public {
        (uint256 price, uint256 newPrice) = _boundDifferentPrices(quotePerBaseSeed, newQuotePerBaseSeed);
        uint256 size = bound(sizeSeed, MARKET_MIN_SIZE * 2, MAX_QUOTE_FUZZ_AMOUNT);
        uint256 decreaseAmount = MARKET_MIN_SIZE + (decreaseSeed % (size - (MARKET_MIN_SIZE * 2) + 1));
        uint256 cloid = bound(cloidSeed, 1, 1023);

        vm.startPrank(alice);
        crystal.batchOrders(
            address(market),
            _singleAction(BatchAction.BuyLimit, price, size, cloid),
            0,
            block.timestamp,
            address(0),
            alice
        );
        crystal.batchOrders(
            address(market),
            _singleAction(BatchAction.DecreaseOrder, 0, decreaseAmount, cloid),
            0,
            block.timestamp,
            address(0),
            alice
        );
        crystal.batchOrders(
            address(market), _singleAction(BatchAction.CancelOrder, 0, 0, cloid), 0, block.timestamp, address(0), alice
        );
        uint256 userId = crystal.addressToUserId(alice);
        ICrystal.Order memory cancelledOrder = crystal.getOrderByCloid(userId, cloid);
        _clearCloid(userId, cloid);
        crystal.batchOrders(
            address(market),
            _singleAction(BatchAction.BuyLimit, newPrice, size, cloid),
            0,
            block.timestamp,
            address(0),
            alice
        );
        vm.stopPrank();

        ICrystal.Order memory reusedOrder = crystal.getOrderByCloid(userId, cloid);
        ICrystal.PriceLevel memory oldLevel = crystal.getPriceLevel(address(market), price);
        ICrystal.PriceLevel memory newLevel = crystal.getPriceLevel(address(market), newPrice);

        assertEq(cancelledOrder.size, 0, "assert cancelledOrder.size == 0");
        assertEq(oldLevel.size, 0, "assert oldLevel.size == 0");
        assertEq(newLevel.size, size, "assert newLevel.size == size");
        assertEq(reusedOrder.isBuy, true, "assert reusedOrder.isBuy == true");
        assertEq(reusedOrder.price, newPrice, "assert reusedOrder.price == newPrice");
        assertEq(reusedOrder.size, size, "assert reusedOrder.size == size");
    }

    function testFuzzPriceLevelViewRoundtrip(
        uint256 lowQuotePerBaseSeed,
        uint256 bidLowSizeSeed,
        uint256 bidHighSizeSeed,
        uint256 askLowSizeSeed,
        uint256 askHighSizeSeed
    ) public {
        uint256 lowQuotePerBase = bound(lowQuotePerBaseSeed, MIN_QUOTE_PER_BASE, MAX_QUOTE_PER_BASE - 300);
        uint256 bidLow = _boundPrice(lowQuotePerBase);
        uint256 bidHigh = _boundPrice(lowQuotePerBase + 100);
        uint256 askLow = _boundPrice(lowQuotePerBase + 200);
        uint256 askHigh = _boundPrice(lowQuotePerBase + 300);
        vm.assume(bidLow < bidHigh && bidHigh < askLow && askLow < askHigh);
        uint256 bidLowSize = _boundRoundtripBidSize(bidLowSizeSeed);
        uint256 bidHighSize = _boundRoundtripBidSize(bidHighSizeSeed);
        uint256 askLowSize = _boundRoundtripAskSize(askLowSizeSeed, askLow);
        uint256 askHighSize = _boundRoundtripAskSize(askHighSizeSeed, askHigh);

        vm.startPrank(alice);
        crystal.limitOrder(address(market), true, 0, bidLow, bidLowSize, alice);
        crystal.limitOrder(address(market), true, 0, bidHigh, bidHighSize, alice);
        crystal.limitOrder(address(market), false, 0, askLow, askLowSize, alice);
        crystal.limitOrder(address(market), false, 0, askHigh, askHighSize, alice);
        vm.stopPrank();

        bytes memory levels =
            crystal.getPriceLevels(address(market), true, bidLow, askHigh - bidLow, MARKET_TICK_SIZE, 8);
        (uint256 highestBid, uint256 lowestAsk, bytes memory bids, bytes memory asks) =
            crystal.getPriceLevelsFromMid(address(market), askHigh - bidLow, MARKET_TICK_SIZE, 8);

        assertEq(highestBid, bidHigh, "assert highestBid == bidHigh");
        assertEq(lowestAsk, askLow, "assert lowestAsk == askLow");
        _assertEncodedLevelMatchesView(levels, bidLow);
        _assertEncodedLevelMatchesView(levels, bidHigh);
        _assertEncodedLevelMatchesView(levels, askLow);
        _assertEncodedLevelMatchesView(levels, askHigh);
        _assertEncodedLevelMatchesView(bids, bidLow);
        _assertEncodedLevelMatchesView(bids, bidHigh);
        _assertEncodedLevelMatchesView(asks, askLow);
        _assertEncodedLevelMatchesView(asks, askHigh);
    }

    function _boundRoundtripAskSize(uint256 seed, uint256 price) private view returns (uint256) {
        uint256 minSize = _minBaseForQuote(MARKET_MIN_SIZE * 4, price);
        return bound(seed, minSize, MAX_ROUNDTRIP_BASE_SIZE);
    }

    function _boundRoundtripBidSize(uint256 seed) private pure returns (uint256) {
        return bound(seed, MARKET_MIN_SIZE * 4, MAX_ROUNDTRIP_BID_SIZE);
    }

    function _quoteResult(bool isBuy, bool isExactInput, bool isCompleteFill, uint256 size, uint256 worstPrice)
        private
        returns (MarketResult memory result)
    {
        (result.amountIn, result.amountOut) =
            crystal.getQuote(address(market), isBuy, isExactInput, isCompleteFill, size, worstPrice);
    }

    function _executeMarketOrder(address user, bool isBuy, bool isExactInput, uint256 size, uint256 worstPrice)
        private
        returns (MarketResult memory result)
    {
        vm.prank(user);
        (result.amountIn, result.amountOut, result.id) = crystal.marketOrder(
            address(market), isBuy, isExactInput, 0, ORDER_TYPES_NORMAL, size, worstPrice, address(0), user
        );
    }

    function _snapshot(address user, address asset) private view returns (BalanceSnapshot memory snapshot) {
        snapshot.quote = quote.balanceOf(user);
        snapshot.weth = weth.balanceOf(user);
        (snapshot.depositedTotal, snapshot.depositedAvailable, snapshot.depositedLocked) =
            crystal.getDepositedBalance(user, asset);
    }

    function _assertSnapshot(address user, address asset, BalanceSnapshot memory expected) private view {
        (uint256 total, uint256 available, uint256 locked) = crystal.getDepositedBalance(user, asset);
        assertEq(quote.balanceOf(user), expected.quote, "assert quote.balanceOf(user) == expected.quote");
        assertEq(weth.balanceOf(user), expected.weth, "assert weth.balanceOf(user) == expected.weth");
        assertEq(total, expected.depositedTotal, "assert total == expected.depositedTotal");
        assertEq(available, expected.depositedAvailable, "assert available == expected.depositedAvailable");
        assertEq(locked, expected.depositedLocked, "assert locked == expected.depositedLocked");
    }

    function _clearCloid(uint256 userId, uint256 cloid) private {
        uint256[] memory ids = new uint256[](1);
        ids[0] = cloid;
        crystal.clearCloidSlots(userId, ids);
    }

    function _assertEncodedLevelMatchesView(bytes memory encodedLevels, uint256 expectedPrice) private {
        (, uint256 encodedSize, bool found) = _findEncodedLevel(encodedLevels, expectedPrice);
        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), expectedPrice);

        assertTrue(found, "assert found");
        assertEq(encodedSize, level.size, "assert encodedSize == level.size");
    }

    function _findEncodedLevel(bytes memory encodedLevels, uint256 expectedPrice)
        private
        pure
        returns (uint256 encodedPrice, uint256 encodedSize, bool found)
    {
        assertEq(encodedLevels.length % 32, 0, "assert encodedLevels.length % 32 == 0");
        for (uint256 i = 0; i < encodedLevels.length / 32; i++) {
            uint256 encoded = _encodedWordAt(encodedLevels, i);
            encodedPrice = encoded / PRICE_LEVEL_SIZE_OFFSET;
            encodedSize = encoded - (encodedPrice * PRICE_LEVEL_SIZE_OFFSET);
            if (encodedPrice == expectedPrice) {
                return (encodedPrice, encodedSize, true);
            }
        }
        return (0, 0, false);
    }

    function _encodedWordAt(bytes memory data, uint256 index) private pure returns (uint256 encoded) {
        assembly {
            encoded := mload(add(add(data, 32), mul(index, 32)))
        }
    }

    function _absDiff(uint256 a, uint256 b) private pure returns (uint256) {
        return a >= b ? a - b : b - a;
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
}
