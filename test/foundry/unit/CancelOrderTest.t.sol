// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ICrystal } from "../../../contracts/interfaces/ICrystal.sol";
import { BaseTest } from "../BaseTest.t.sol";

contract CancelOrderTest is BaseTest {
    function testCancelBuyOrderClearsBidLevel() public {
        uint256 price = _price(500);
        uint256 size = 1_000 * QUOTE_UNIT;

        vm.startPrank(alice);
        uint256 orderId = crystal.limitOrder(address(market), true, 0, price, size, alice);
        uint256 cancelledSize = crystal.cancelOrder(address(market), 0, price, orderId, alice);
        vm.stopPrank();

        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);
        assertEq(cancelledSize, size, "assert cancelledSize == size");
        assertEq(level.size, 0, "assert level.size == 0");
    }

    function testCancelSellOrderClearsAskLevel() public {
        uint256 price = _price(500);
        uint256 size = 10 ether;

        vm.startPrank(alice);
        uint256 orderId = crystal.limitOrder(address(market), false, 0, price, size, alice);
        uint256 cancelledSize = crystal.cancelOrder(address(market), 0, price, orderId, alice);
        vm.stopPrank();

        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);
        assertEq(cancelledSize, size, "assert cancelledSize == size");
        assertEq(level.size, 0, "assert level.size == 0");
    }
}
