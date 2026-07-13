// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ICrystal } from "../../../contracts/interfaces/ICrystal.sol";
import { BaseFuzzTest } from "../BaseFuzzTest.t.sol";

contract LimitOrderFuzzTest is BaseFuzzTest {
    function testFuzzBuyLimitOrderPlacesBid(uint256 quotePerBaseSeed, uint256 sizeSeed) public {
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 size = _boundQuoteAmount(sizeSeed);

        vm.prank(alice);
        uint256 orderId = crystal.limitOrder(address(market), true, 0, price, size, alice);

        ICrystal.Order memory order = crystal.getOrder(address(market), price, orderId);
        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);
        ICrystal.MarketInfo memory info = crystal.getMarket(address(market));

        assertGt(orderId, 0, "assert orderId > 0");
        assertEq(order.isBuy, true, "assert order.isBuy == true");
        assertEq(order.market, address(market), "assert order.market == address(market)");
        assertEq(order.price, price, "assert order.price == price");
        assertEq(order.size, size, "assert order.size == size");
        assertEq(order.userId, crystal.addressToUserId(alice), "assert order.userId == crystal.addressToUserId(alice)");
        assertEq(level.size, size, "assert level.size == size");
        assertEq(level.latestNativeId, orderId, "assert level.latestNativeId == orderId");
        assertEq(level.latest, orderId, "assert level.latest == orderId");
        assertEq(level.fillNext, orderId, "assert level.fillNext == orderId");
        assertEq(info.highestBid, price, "assert info.highestBid == price");
    }

    function testFuzzSellLimitOrderPlacesAsk(uint256 quotePerBaseSeed, uint256 sizeSeed) public {
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 size = _boundSellSize(sizeSeed, price);

        vm.prank(alice);
        uint256 orderId = crystal.limitOrder(address(market), false, 0, price, size, alice);

        ICrystal.Order memory order = crystal.getOrder(address(market), price, orderId);
        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);
        ICrystal.MarketInfo memory info = crystal.getMarket(address(market));

        assertGt(orderId, 0, "assert orderId > 0");
        assertEq(order.isBuy, false, "assert order.isBuy == false");
        assertEq(order.market, address(market), "assert order.market == address(market)");
        assertEq(order.price, price, "assert order.price == price");
        assertEq(order.size, size, "assert order.size == size");
        assertEq(order.userId, crystal.addressToUserId(alice), "assert order.userId == crystal.addressToUserId(alice)");
        assertEq(level.size, size, "assert level.size == size");
        assertEq(level.latestNativeId, orderId, "assert level.latestNativeId == orderId");
        assertEq(level.latest, orderId, "assert level.latest == orderId");
        assertEq(level.fillNext, orderId, "assert level.fillNext == orderId");
        assertEq(info.lowestAsk, price, "assert info.lowestAsk == price");
    }
}
