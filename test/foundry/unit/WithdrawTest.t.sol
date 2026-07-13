// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "../BaseTest.t.sol";

contract WithdrawTest is BaseTest {
    function testWithdrawQuoteTokenReducesDeposit() public {
        uint256 depositAmount = 1_000 * QUOTE_UNIT;
        uint256 withdrawAmount = 250 * QUOTE_UNIT;

        vm.startPrank(carol);
        crystal.deposit(address(quote), depositAmount);
        uint256 walletBefore = quote.balanceOf(carol);
        crystal.withdraw(carol, address(quote), withdrawAmount);
        vm.stopPrank();

        (uint256 totalBalance, uint256 availableBalance, uint256 lockedBalance) =
            crystal.getDepositedBalance(carol, address(quote));

        assertEq(totalBalance, depositAmount - withdrawAmount, "assert totalBalance == depositAmount - withdrawAmount");
        assertEq(
            availableBalance,
            depositAmount - withdrawAmount,
            "assert availableBalance == depositAmount - withdrawAmount"
        );
        assertEq(lockedBalance, 0, "assert lockedBalance == 0");
        assertEq(
            quote.balanceOf(carol),
            walletBefore + withdrawAmount,
            "assert quote.balanceOf(carol) == walletBefore + withdrawAmount"
        );
    }

    function testWithdrawNativeEthUnwrapsWethDeposit() public {
        address nativeToken = crystal.eth();
        uint256 depositAmount = 10 ether;
        uint256 withdrawAmount = 3 ether;

        vm.startPrank(carol);
        crystal.deposit{ value: depositAmount }(nativeToken, depositAmount);
        uint256 walletBefore = carol.balance;
        crystal.withdraw(carol, nativeToken, withdrawAmount);
        vm.stopPrank();

        (uint256 totalBalance, uint256 availableBalance, uint256 lockedBalance) =
            crystal.getDepositedBalance(carol, address(weth));

        assertEq(totalBalance, depositAmount - withdrawAmount, "assert totalBalance == depositAmount - withdrawAmount");
        assertEq(
            availableBalance,
            depositAmount - withdrawAmount,
            "assert availableBalance == depositAmount - withdrawAmount"
        );
        assertEq(lockedBalance, 0, "assert lockedBalance == 0");
        assertEq(carol.balance, walletBefore + withdrawAmount, "assert carol.balance == walletBefore + withdrawAmount");
    }
}
