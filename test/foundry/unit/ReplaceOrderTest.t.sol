// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ICrystal } from "../../../contracts/interfaces/ICrystal.sol";
import { BaseTest } from "../BaseTest.t.sol";

contract ReplaceOrderTest is BaseTest {
    function testReplaceBuyOrderMovesLiquidityToNewPrice() public {
        uint256 price = _price(500);
        uint256 newPrice = _price(600);
        uint256 size = 1_000 * QUOTE_UNIT;

        vm.startPrank(alice);
        uint256 orderId = crystal.limitOrder(address(market), true, 0, price, size, alice);
        uint256 replacementId =
            crystal.replaceOrder(address(market), 0, price, orderId, newPrice, size, address(0), alice);
        vm.stopPrank();

        ICrystal.PriceLevel memory oldLevel = crystal.getPriceLevel(address(market), price);
        ICrystal.PriceLevel memory newLevel = crystal.getPriceLevel(address(market), newPrice);
        ICrystal.Order memory replacementOrder = crystal.getOrder(address(market), newPrice, replacementId);

        assertGt(replacementId, 0, "assert replacementId > 0");
        assertEq(oldLevel.size, 0, "assert oldLevel.size == 0");
        assertEq(newLevel.size, size, "assert newLevel.size == size");
        assertEq(replacementOrder.isBuy, true, "assert replacementOrder.isBuy == true");
        assertEq(replacementOrder.price, newPrice, "assert replacementOrder.price == newPrice");
        assertEq(replacementOrder.size, size, "assert replacementOrder.size == size");
        assertEq(
            replacementOrder.userId,
            crystal.addressToUserId(alice),
            "assert replacementOrder.userId == crystal.addressToUserId(alice)"
        );
    }

    function testReplaceSellOrderMovesLiquidityToNewPrice() public {
        uint256 price = _price(500);
        uint256 newPrice = _price(600);
        uint256 size = 10 ether;

        vm.startPrank(alice);
        uint256 orderId = crystal.limitOrder(address(market), false, 0, price, size, alice);
        uint256 replacementId =
            crystal.replaceOrder(address(market), 0, price, orderId, newPrice, size, address(0), alice);
        vm.stopPrank();

        ICrystal.PriceLevel memory oldLevel = crystal.getPriceLevel(address(market), price);
        ICrystal.PriceLevel memory newLevel = crystal.getPriceLevel(address(market), newPrice);
        ICrystal.Order memory replacementOrder = crystal.getOrder(address(market), newPrice, replacementId);

        assertGt(replacementId, 0, "assert replacementId > 0");
        assertEq(oldLevel.size, 0, "assert oldLevel.size == 0");
        assertEq(newLevel.size, size, "assert newLevel.size == size");
        assertEq(replacementOrder.isBuy, false, "assert replacementOrder.isBuy == false");
        assertEq(replacementOrder.price, newPrice, "assert replacementOrder.price == newPrice");
        assertEq(replacementOrder.size, size, "assert replacementOrder.size == size");
        assertEq(
            replacementOrder.userId,
            crystal.addressToUserId(alice),
            "assert replacementOrder.userId == crystal.addressToUserId(alice)"
        );
    }
}
