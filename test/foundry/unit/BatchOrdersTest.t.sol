// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ICrystal } from "../../../contracts/interfaces/ICrystal.sol";
import { BaseTest } from "../BaseTest.t.sol";

contract BatchOrdersTest is BaseTest {
    function testBatchOrdersPlacesBuyLimitAction() public {
        uint256 price = _price(500);
        uint256 size = 1_000 * QUOTE_UNIT;

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

    function testBatchOrdersPlacesSellLimitAction() public {
        uint256 price = _price(500);
        uint256 size = 10 ether;

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

    function testBatchOrdersCancelsNativeOrderAction() public {
        uint256 price = _price(500);
        uint256 size = 1_000 * QUOTE_UNIT;

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

    function testBatchOrdersMarketToLimitBuyActionPlacesRestingBid() public {
        uint256 price = _price(500);
        uint256 size = 1_000 * QUOTE_UNIT;

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

    function testBatchOrdersMarketToLimitSellActionPlacesRestingAsk() public {
        uint256 price = _price(500);
        uint256 size = 2 ether;

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

    function testBatchOrdersExecutesPartialBuyTakerAction() public {
        _assertBuyTakerActionConsumesAsk(BatchAction.PartialBuy);
    }

    function testBatchOrdersExecutesPartialSellTakerAction() public {
        _assertSellTakerActionConsumesBid(BatchAction.PartialSell);
    }

    function testBatchOrdersExecutesGasAwarePartialBuyTakerAction() public {
        _assertBuyTakerActionConsumesAsk(BatchAction.GasAwarePartialBuy);
    }

    function testBatchOrdersExecutesGasAwarePartialSellTakerAction() public {
        _assertSellTakerActionConsumesBid(BatchAction.GasAwarePartialSell);
    }

    function testBatchOrdersExecutesCompleteBuyTakerAction() public {
        _assertBuyTakerActionConsumesAsk(BatchAction.CompleteBuy);
    }

    function testBatchOrdersExecutesCompleteSellTakerAction() public {
        _assertSellTakerActionConsumesBid(BatchAction.CompleteSell);
    }

    function testBatchOrdersDecreasesNativeOrderAction() public {
        uint256 price = _price(500);
        uint256 size = 1_000 * QUOTE_UNIT;
        uint256 decreaseAmount = 250 * QUOTE_UNIT;

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

    function _assertBuyTakerActionConsumesAsk(BatchAction action) private {
        uint256 price = _price(500);
        uint256 askSize = 10 ether;
        uint256 quoteIn = 2_500 * QUOTE_UNIT;

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

    function _assertSellTakerActionConsumesBid(BatchAction action) private {
        uint256 price = _price(500);
        uint256 bidSize = 5_000 * QUOTE_UNIT;
        uint256 baseIn = 5 ether;

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
