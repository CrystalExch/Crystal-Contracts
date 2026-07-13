// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ICrystal } from "../../../contracts/interfaces/ICrystal.sol";
import { BaseFuzzTest } from "../BaseFuzzTest.t.sol";

contract DecreaseOrderFuzzTest is BaseFuzzTest {
    function testFuzzDecreaseExistingBuyOrderViaBatchReducesSizeAndRefundsQuote(
        uint256 quotePerBaseSeed,
        uint256 sizeSeed,
        uint256 decreaseSeed
    ) public {
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 size = bound(sizeSeed, MARKET_MIN_SIZE * 2, MAX_QUOTE_FUZZ_AMOUNT);
        uint256 decreaseAmount = bound(decreaseSeed, 1, size - MARKET_MIN_SIZE);
        uint256 remainingSize = size - decreaseAmount;

        vm.startPrank(alice);
        uint256 orderId = crystal.limitOrder(address(market), true, 0, price, size, alice);
        uint256 quoteBalanceBeforeDecrease = quote.balanceOf(alice);
        crystal.batchOrders(
            address(market), _decreaseActions(price, orderId, decreaseAmount), 0, block.timestamp, address(0), alice
        );
        vm.stopPrank();

        ICrystal.Order memory order = crystal.getOrder(address(market), price, orderId);
        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);
        ICrystal.MarketInfo memory info = crystal.getMarket(address(market));

        assertEq(order.isBuy, true, "assert order.isBuy == true");
        assertEq(order.market, address(market), "assert order.market == address(market)");
        assertEq(order.price, price, "assert order.price == price");
        assertEq(order.size, remainingSize, "assert order.size == remainingSize");
        assertEq(order.userId, crystal.addressToUserId(alice), "assert order.userId == crystal.addressToUserId(alice)");
        assertEq(level.size, remainingSize, "assert level.size == remainingSize");
        assertEq(info.highestBid, price, "assert info.highestBid == price");
        assertEq(
            quote.balanceOf(alice),
            quoteBalanceBeforeDecrease + decreaseAmount,
            "assert quote.balanceOf(alice) == quoteBalanceBeforeDecrease + decreaseAmount"
        );
    }

    function testFuzzDecreaseExistingSellOrderViaBatchReducesSizeAndRefundsBase(
        uint256 quotePerBaseSeed,
        uint256 sizeSeed,
        uint256 decreaseSeed
    ) public {
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 minSize = _minBaseForQuote(MARKET_MIN_SIZE * 2, price);
        uint256 size = bound(sizeSeed, minSize, MAX_BASE_FUZZ_AMOUNT);
        uint256 maxDecrease = size - _minBaseForQuote(MARKET_MIN_SIZE, price);
        uint256 decreaseAmount = bound(decreaseSeed, 1, maxDecrease);
        uint256 remainingSize = size - decreaseAmount;

        vm.startPrank(alice);
        uint256 orderId = crystal.limitOrder(address(market), false, 0, price, size, alice);
        uint256 wethBalanceBeforeDecrease = weth.balanceOf(alice);
        crystal.batchOrders(
            address(market), _decreaseActions(price, orderId, decreaseAmount), 0, block.timestamp, address(0), alice
        );
        vm.stopPrank();

        ICrystal.Order memory order = crystal.getOrder(address(market), price, orderId);
        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);
        ICrystal.MarketInfo memory info = crystal.getMarket(address(market));

        assertEq(order.isBuy, false, "assert order.isBuy == false");
        assertEq(order.market, address(market), "assert order.market == address(market)");
        assertEq(order.price, price, "assert order.price == price");
        assertEq(order.size, remainingSize, "assert order.size == remainingSize");
        assertEq(order.userId, crystal.addressToUserId(alice), "assert order.userId == crystal.addressToUserId(alice)");
        assertEq(level.size, remainingSize, "assert level.size == remainingSize");
        assertEq(info.lowestAsk, price, "assert info.lowestAsk == price");
        assertEq(
            weth.balanceOf(alice),
            wethBalanceBeforeDecrease + decreaseAmount,
            "assert weth.balanceOf(alice) == wethBalanceBeforeDecrease + decreaseAmount"
        );
    }

    function _decreaseActions(uint256 price, uint256 orderId, uint256 decreaseAmount)
        private
        pure
        returns (ICrystal.Action[] memory actions)
    {
        actions = new ICrystal.Action[](1);
        actions[0] = ICrystal.Action({
            isRequireSuccess: true,
            action: uint256(BatchAction.DecreaseOrder),
            param1: price,
            param2: decreaseAmount,
            param3: orderId
        });
    }
}
