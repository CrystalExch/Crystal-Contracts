// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ICrystal } from "../../../contracts/interfaces/ICrystal.sol";
import { BaseFuzzTest } from "../BaseFuzzTest.t.sol";

contract EventProperties is BaseFuzzTest {
    event Deposit(address indexed user, uint256 indexed userId, address indexed token, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed userId, address indexed token, uint256 amount);
    event Trade(
        address indexed market,
        address indexed user,
        bool isBuy,
        uint256 amountIn,
        uint256 amountOut,
        uint256 startPrice,
        uint256 endPrice
    );
    event OrdersUpdated(address indexed market, address indexed user, bytes orderData);

    function testFuzzDepositAndWithdrawEventsMatchBalanceDeltas(uint256 depositSeed, uint256 withdrawSeed) public {
        uint256 depositAmount = bound(depositSeed, MARKET_MIN_SIZE, 10_000 * QUOTE_UNIT);
        uint256 withdrawAmount = bound(withdrawSeed, MARKET_MIN_SIZE, depositAmount);
        uint256 userId = crystal.addressToUserId(alice);
        (uint256 totalBefore, uint256 availableBefore,) = crystal.getDepositedBalance(alice, address(quote));

        vm.startPrank(alice);
        vm.expectEmit(true, true, true, true, address(crystal));
        emit Deposit(alice, userId, address(quote), depositAmount);
        crystal.deposit(address(quote), depositAmount);

        vm.expectEmit(true, true, true, true, address(crystal));
        emit Withdraw(alice, userId, address(quote), withdrawAmount);
        crystal.withdraw(alice, address(quote), withdrawAmount);
        vm.stopPrank();

        (uint256 totalAfter, uint256 availableAfter, uint256 lockedAfter) =
            crystal.getDepositedBalance(alice, address(quote));

        assertEq(
            totalAfter,
            totalBefore + depositAmount - withdrawAmount,
            "assert totalAfter == totalBefore + depositAmount - withdrawAmount"
        );
        assertEq(
            availableAfter,
            availableBefore + depositAmount - withdrawAmount,
            "assert availableAfter == availableBefore + depositAmount - withdrawAmount"
        );
        assertEq(lockedAfter, 0, "assert lockedAfter == 0");
    }

    function testOrderAndTradeEventsMatchBookDeltas() public {
        uint256 price = _price(500);
        uint256 askSize = 10 ether;
        uint256 quoteIn = 1_000 * QUOTE_UNIT;

        vm.prank(alice);
        vm.expectEmit(true, true, false, false, address(crystal));
        emit OrdersUpdated(address(market), alice, "");
        crystal.limitOrder(address(market), false, 0, price, askSize, alice);

        ICrystal.PriceLevel memory levelBeforeTrade = crystal.getPriceLevel(address(market), price);

        vm.prank(bob);
        vm.expectEmit(true, true, false, false, address(crystal));
        emit Trade(address(market), bob, true, 0, 0, 0, 0);
        (uint256 amountIn, uint256 amountOut,) =
            crystal.marketOrder(address(market), true, true, 0, ORDER_TYPES_NORMAL, quoteIn, price, address(0), bob);

        ICrystal.PriceLevel memory levelAfterTrade = crystal.getPriceLevel(address(market), price);

        assertGt(amountIn, 0, "assert amountIn > 0");
        assertGt(amountOut, 0, "assert amountOut > 0");
        assertEq(levelBeforeTrade.size, askSize, "assert levelBeforeTrade.size == askSize");
        assertLt(levelAfterTrade.size, levelBeforeTrade.size, "assert levelAfterTrade.size < levelBeforeTrade.size");
    }
}
