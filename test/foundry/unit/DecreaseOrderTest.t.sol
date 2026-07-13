// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ICrystal } from "../../../contracts/interfaces/ICrystal.sol";
import { BaseTest } from "../BaseTest.t.sol";

contract DecreaseOrderTest is BaseTest {
    function testDecreaseExistingBuyOrderViaBatchReducesSizeAndRefundsQuote() public {
        uint256 price = _price(500);
        uint256 size = 1_000 * QUOTE_UNIT;
        uint256 decreaseAmount = 250 * QUOTE_UNIT;
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

    function testDecreaseExistingSellOrderViaBatchReducesSizeAndRefundsBase() public {
        uint256 price = _price(500);
        uint256 size = 10 ether;
        uint256 decreaseAmount = 3 ether;
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
