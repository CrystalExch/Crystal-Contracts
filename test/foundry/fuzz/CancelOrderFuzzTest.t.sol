// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ICrystal } from "../../../contracts/interfaces/ICrystal.sol";
import { BaseFuzzTest } from "../BaseFuzzTest.t.sol";

contract CancelOrderFuzzTest is BaseFuzzTest {
    function testFuzzCancelBuyOrderClearsBidLevel(uint256 quotePerBaseSeed, uint256 sizeSeed) public {
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 size = _boundQuoteAmount(sizeSeed);

        vm.startPrank(alice);
        uint256 orderId = crystal.limitOrder(address(market), true, 0, price, size, alice);
        uint256 cancelledSize = crystal.cancelOrder(address(market), 0, price, orderId, alice);
        vm.stopPrank();

        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);
        assertEq(cancelledSize, size, "assert cancelledSize == size");
        assertEq(level.size, 0, "assert level.size == 0");
    }

    function testFuzzCancelSellOrderClearsAskLevel(uint256 quotePerBaseSeed, uint256 sizeSeed) public {
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 size = _boundSellSize(sizeSeed, price);

        vm.startPrank(alice);
        uint256 orderId = crystal.limitOrder(address(market), false, 0, price, size, alice);
        uint256 cancelledSize = crystal.cancelOrder(address(market), 0, price, orderId, alice);
        vm.stopPrank();

        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);
        assertEq(cancelledSize, size, "assert cancelledSize == size");
        assertEq(level.size, 0, "assert level.size == 0");
    }
}
