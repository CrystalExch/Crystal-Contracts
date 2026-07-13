// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ICrystal } from "../../../contracts/interfaces/ICrystal.sol";
import { BaseFuzzTest } from "../BaseFuzzTest.t.sol";

contract BatchOrdersFuzzTest is BaseFuzzTest {
    function testFuzzBatchOrdersPlacesBuyLimitAction(uint256 quotePerBaseSeed, uint256 sizeSeed) public {
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 size = _boundQuoteAmount(sizeSeed);

        _batchOrdersAs(alice, _singleAction(BatchAction.BuyLimit, price, size));

        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);
        ICrystal.Order memory order = crystal.getOrder(address(market), price, level.latestNativeId);
        ICrystal.MarketInfo memory info = crystal.getMarket(address(market));

        assertEq(level.size, size, "assert level.size == size");
        assertGt(level.latestNativeId, 0, "assert level.latestNativeId > 0");
        assertEq(level.latest, level.latestNativeId, "assert level.latest == level.latestNativeId");
        assertEq(level.fillNext, level.latestNativeId, "assert level.fillNext == level.latestNativeId");
        assertEq(order.isBuy, true, "assert order.isBuy == true");
        assertEq(order.market, address(market), "assert order.market == address(market)");
        assertEq(order.price, price, "assert order.price == price");
        assertEq(order.size, size, "assert order.size == size");
        assertEq(order.userId, crystal.addressToUserId(alice), "assert order.userId == crystal.addressToUserId(alice)");
        assertEq(info.highestBid, price, "assert info.highestBid == price");
    }

    function testFuzzBatchOrdersPlacesSellLimitAction(uint256 quotePerBaseSeed, uint256 sizeSeed) public {
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 size = _boundSellSize(sizeSeed, price);

        _batchOrdersAs(alice, _singleAction(BatchAction.SellLimit, price, size));

        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);
        ICrystal.Order memory order = crystal.getOrder(address(market), price, level.latestNativeId);
        ICrystal.MarketInfo memory info = crystal.getMarket(address(market));

        assertEq(level.size, size, "assert level.size == size");
        assertGt(level.latestNativeId, 0, "assert level.latestNativeId > 0");
        assertEq(level.latest, level.latestNativeId, "assert level.latest == level.latestNativeId");
        assertEq(level.fillNext, level.latestNativeId, "assert level.fillNext == level.latestNativeId");
        assertEq(order.isBuy, false, "assert order.isBuy == false");
        assertEq(order.market, address(market), "assert order.market == address(market)");
        assertEq(order.price, price, "assert order.price == price");
        assertEq(order.size, size, "assert order.size == size");
        assertEq(order.userId, crystal.addressToUserId(alice), "assert order.userId == crystal.addressToUserId(alice)");
        assertEq(info.lowestAsk, price, "assert info.lowestAsk == price");
    }

    function testFuzzBatchOrdersCancelsNativeOrderAction(uint256 quotePerBaseSeed, uint256 sizeSeed) public {
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 size = _boundQuoteAmount(sizeSeed);

        vm.startPrank(alice);
        uint256 orderId = crystal.limitOrder(address(market), true, 0, price, size, alice);
        crystal.batchOrders(
            address(market),
            _singleAction(BatchAction.CancelOrder, price, orderId),
            0,
            block.timestamp,
            address(0),
            alice
        );
        vm.stopPrank();

        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);
        ICrystal.Order memory order = crystal.getOrder(address(market), price, orderId);

        assertEq(level.size, 0, "assert level.size == 0");
        assertEq(order.size, 0, "assert order.size == 0");
    }

    function testFuzzBatchOrdersMarketToLimitBuyActionPlacesRestingBid(uint256 quotePerBaseSeed, uint256 sizeSeed)
        public
    {
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 size = _boundQuoteAmount(sizeSeed);

        _batchOrdersAs(bob, _singleAction(BatchAction.MarketToLimitBuy, price, size));

        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);
        ICrystal.Order memory order = crystal.getOrder(address(market), price, level.latestNativeId);
        ICrystal.MarketInfo memory info = crystal.getMarket(address(market));

        assertEq(level.size, size, "assert level.size == size");
        assertGt(level.latestNativeId, 0, "assert level.latestNativeId > 0");
        assertEq(order.isBuy, true, "assert order.isBuy == true");
        assertEq(order.price, price, "assert order.price == price");
        assertEq(order.size, size, "assert order.size == size");
        assertEq(order.userId, crystal.addressToUserId(bob), "assert order.userId == crystal.addressToUserId(bob)");
        assertEq(info.highestBid, price, "assert info.highestBid == price");
    }

    function testFuzzBatchOrdersMarketToLimitSellActionPlacesRestingAsk(uint256 quotePerBaseSeed, uint256 sizeSeed)
        public
    {
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 size = _boundSellSize(sizeSeed, price);

        _batchOrdersAs(bob, _singleAction(BatchAction.MarketToLimitSell, price, size));

        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);
        ICrystal.Order memory order = crystal.getOrder(address(market), price, level.latestNativeId);
        ICrystal.MarketInfo memory info = crystal.getMarket(address(market));

        assertEq(level.size, size, "assert level.size == size");
        assertGt(level.latestNativeId, 0, "assert level.latestNativeId > 0");
        assertEq(order.isBuy, false, "assert order.isBuy == false");
        assertEq(order.price, price, "assert order.price == price");
        assertEq(order.size, size, "assert order.size == size");
        assertEq(order.userId, crystal.addressToUserId(bob), "assert order.userId == crystal.addressToUserId(bob)");
        assertEq(info.lowestAsk, price, "assert info.lowestAsk == price");
    }

    function testFuzzBatchOrdersExecutesPartialBuyTakerAction(
        uint256 quotePerBaseSeed,
        uint256 askSizeSeed,
        uint256 quoteInSeed
    ) public {
        _assertBuyTakerActionConsumesAsk(BatchAction.PartialBuy, quotePerBaseSeed, askSizeSeed, quoteInSeed);
    }

    function testFuzzBatchOrdersExecutesPartialSellTakerAction(
        uint256 quotePerBaseSeed,
        uint256 bidSizeSeed,
        uint256 baseInSeed
    ) public {
        _assertSellTakerActionConsumesBid(BatchAction.PartialSell, quotePerBaseSeed, bidSizeSeed, baseInSeed);
    }

    function testFuzzBatchOrdersExecutesGasAwarePartialBuyTakerAction(
        uint256 quotePerBaseSeed,
        uint256 askSizeSeed,
        uint256 quoteInSeed
    ) public {
        _assertBuyTakerActionConsumesAsk(BatchAction.GasAwarePartialBuy, quotePerBaseSeed, askSizeSeed, quoteInSeed);
    }

    function testFuzzBatchOrdersExecutesGasAwarePartialSellTakerAction(
        uint256 quotePerBaseSeed,
        uint256 bidSizeSeed,
        uint256 baseInSeed
    ) public {
        _assertSellTakerActionConsumesBid(BatchAction.GasAwarePartialSell, quotePerBaseSeed, bidSizeSeed, baseInSeed);
    }

    function testFuzzBatchOrdersExecutesCompleteBuyTakerAction(
        uint256 quotePerBaseSeed,
        uint256 askSizeSeed,
        uint256 quoteInSeed
    ) public {
        _assertBuyTakerActionConsumesAsk(BatchAction.CompleteBuy, quotePerBaseSeed, askSizeSeed, quoteInSeed);
    }

    function testFuzzBatchOrdersExecutesCompleteSellTakerAction(
        uint256 quotePerBaseSeed,
        uint256 bidSizeSeed,
        uint256 baseInSeed
    ) public {
        _assertSellTakerActionConsumesBid(BatchAction.CompleteSell, quotePerBaseSeed, bidSizeSeed, baseInSeed);
    }

    function testFuzzBatchOrdersDecreasesNativeOrderAction(
        uint256 quotePerBaseSeed,
        uint256 sizeSeed,
        uint256 decreaseSeed
    ) public {
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 size = bound(sizeSeed, MARKET_MIN_SIZE * 2, MAX_QUOTE_FUZZ_AMOUNT);
        uint256 decreaseAmount = bound(decreaseSeed, 1, size - MARKET_MIN_SIZE);

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
        vm.stopPrank();

        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);
        ICrystal.Order memory order = crystal.getOrder(address(market), price, orderId);

        assertEq(level.size, size - decreaseAmount, "assert level.size == size - decreaseAmount");
        assertEq(order.size, size - decreaseAmount, "assert order.size == size - decreaseAmount");
    }

    function _assertBuyTakerActionConsumesAsk(
        BatchAction action,
        uint256 quotePerBaseSeed,
        uint256 askSizeSeed,
        uint256 quoteInSeed
    ) private {
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 askSize = _boundPartialAskSize(askSizeSeed, price);
        uint256 quoteIn = _boundPartialQuoteIn(quoteInSeed, askSize, price);

        vm.prank(alice);
        crystal.batchOrders(
            address(market), _singleAction(BatchAction.SellLimit, price, askSize), 0, block.timestamp, address(0), alice
        );

        uint256 takerWethBefore = weth.balanceOf(bob);
        uint256 takerQuoteBefore = quote.balanceOf(bob);

        _batchOrdersAs(bob, _singleAction(action, price + 1, quoteIn));

        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);

        assertGt(weth.balanceOf(bob), takerWethBefore, "assert weth.balanceOf(bob) > takerWethBefore");
        assertLt(quote.balanceOf(bob), takerQuoteBefore, "assert quote.balanceOf(bob) < takerQuoteBefore");
        assertLt(level.size, askSize, "assert level.size < askSize");
        assertGt(level.size, 0, "assert level.size > 0");
    }

    function _assertSellTakerActionConsumesBid(
        BatchAction action,
        uint256 quotePerBaseSeed,
        uint256 bidSizeSeed,
        uint256 baseInSeed
    ) private {
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 bidSize = _boundPartialBidSize(bidSizeSeed);
        uint256 baseIn = _boundPartialBaseIn(baseInSeed, bidSize, price);

        vm.prank(alice);
        crystal.limitOrder(address(market), true, 0, price, bidSize, alice);

        uint256 takerQuoteBefore = quote.balanceOf(bob);
        uint256 takerWethBefore = weth.balanceOf(bob);

        _batchOrdersAs(bob, _singleAction(action, price - 1, baseIn));

        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);

        assertGt(quote.balanceOf(bob), takerQuoteBefore, "assert quote.balanceOf(bob) > takerQuoteBefore");
        assertLt(weth.balanceOf(bob), takerWethBefore, "assert weth.balanceOf(bob) < takerWethBefore");
        assertLt(level.size, bidSize, "assert level.size < bidSize");
        assertGt(level.size, 0, "assert level.size > 0");
    }

    function _batchOrdersAs(address user, ICrystal.Action[] memory actions) private {
        vm.prank(user);
        crystal.batchOrders(address(market), actions, 0, block.timestamp, address(0), user);
    }

    function _singleAction(BatchAction action, uint256 param1, uint256 param2)
        private
        pure
        returns (ICrystal.Action[] memory actions)
    {
        return _singleAction(action, param1, param2, 0);
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
