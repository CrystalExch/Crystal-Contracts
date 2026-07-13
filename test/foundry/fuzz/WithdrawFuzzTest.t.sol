// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseFuzzTest } from "../BaseFuzzTest.t.sol";

contract WithdrawFuzzTest is BaseFuzzTest {
    function testFuzzWithdrawQuoteTokenReducesDeposit(uint256 depositSeed, uint256 withdrawSeed) public {
        uint256 depositAmount = _boundQuoteAmount(depositSeed);
        uint256 withdrawAmount = bound(withdrawSeed, 1, depositAmount);

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

    function testFuzzWithdrawNativeEthUnwrapsWethDeposit(uint256 depositSeed, uint256 withdrawSeed) public {
        address nativeToken = crystal.eth();
        uint256 depositAmount = _boundEthAmount(depositSeed);
        uint256 withdrawAmount = bound(withdrawSeed, 1, depositAmount);

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
