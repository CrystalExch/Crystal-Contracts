// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "../BaseTest.t.sol";

contract DepositTest is BaseTest {
    function testDepositQuoteTokenCreditsAvailableBalanceAndRegistersUser() public {
        uint256 amount = 1_000 * QUOTE_UNIT;

        vm.prank(carol);
        uint256 userId = crystal.deposit(address(quote), amount);

        (uint256 totalBalance, uint256 availableBalance, uint256 lockedBalance) =
            crystal.getDepositedBalance(carol, address(quote));

        assertEq(userId, crystal.addressToUserId(carol), "assert userId == crystal.addressToUserId(carol)");
        assertEq(totalBalance, amount, "assert totalBalance == amount");
        assertEq(availableBalance, amount, "assert availableBalance == amount");
        assertEq(lockedBalance, 0, "assert lockedBalance == 0");
    }

    function testDepositNativeEthWrapsAndCreditsWethBalance() public {
        uint256 amount = 2 ether;
        address nativeToken = crystal.eth();
        uint256 crystalWethBefore = weth.balanceOf(address(crystal));

        vm.prank(carol);
        uint256 userId = crystal.deposit{ value: amount }(nativeToken, amount);

        (uint256 totalBalance, uint256 availableBalance, uint256 lockedBalance) =
            crystal.getDepositedBalance(carol, address(weth));

        assertEq(userId, crystal.addressToUserId(carol), "assert userId == crystal.addressToUserId(carol)");
        assertEq(totalBalance, amount, "assert totalBalance == amount");
        assertEq(availableBalance, amount, "assert availableBalance == amount");
        assertEq(lockedBalance, 0, "assert lockedBalance == 0");
        assertEq(
            weth.balanceOf(address(crystal)),
            crystalWethBefore + amount,
            "assert weth.balanceOf(address(crystal)) == crystalWethBefore + amount"
        );
    }
}
