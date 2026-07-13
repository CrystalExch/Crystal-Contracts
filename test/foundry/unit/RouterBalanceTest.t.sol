// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "../BaseTest.t.sol";

contract RouterBalanceTest is BaseTest {
    function testRouterDepositTracksQuoteInSharedSlot() public {
        uint256 amount = 1_250 * QUOTE_UNIT;
        uint256 routerQuoteBefore = _routerAvailableBalance(address(quote));
        uint256 carolQuoteBefore = quote.balanceOf(carol);
        uint256 crystalQuoteBefore = quote.balanceOf(address(crystal));

        vm.prank(carol);
        crystal.routerDeposit(address(quote), amount);

        assertEq(
            _routerAvailableBalance(address(quote)),
            routerQuoteBefore + amount,
            "assert _routerAvailableBalance(address(quote)) == routerQuoteBefore + amount"
        );
        assertEq(
            quote.balanceOf(carol),
            carolQuoteBefore - amount,
            "assert quote.balanceOf(carol) == carolQuoteBefore - amount"
        );
        assertEq(
            quote.balanceOf(address(crystal)),
            crystalQuoteBefore + amount,
            "assert quote.balanceOf(address(crystal)) == crystalQuoteBefore + amount"
        );
    }

    function testRouterWithdrawReturnsQuoteAndReducesSharedSlot() public {
        uint256 depositAmount = 2_000 * QUOTE_UNIT;
        uint256 withdrawAmount = 750 * QUOTE_UNIT;

        vm.startPrank(carol);
        crystal.routerDeposit(address(quote), depositAmount);
        uint256 carolQuoteBefore = quote.balanceOf(carol);
        uint256 crystalQuoteBefore = quote.balanceOf(address(crystal));
        crystal.routerWithdraw(carol, address(quote), withdrawAmount);
        vm.stopPrank();

        assertEq(
            _routerAvailableBalance(address(quote)),
            depositAmount - withdrawAmount,
            "assert _routerAvailableBalance(address(quote)) == depositAmount - withdrawAmount"
        );
        assertEq(
            quote.balanceOf(carol),
            carolQuoteBefore + withdrawAmount,
            "assert quote.balanceOf(carol) == carolQuoteBefore + withdrawAmount"
        );
        assertEq(
            quote.balanceOf(address(crystal)),
            crystalQuoteBefore - withdrawAmount,
            "assert quote.balanceOf(address(crystal)) == crystalQuoteBefore - withdrawAmount"
        );
    }

    function testRouterDepositWrapsNativeEthIntoWethSlot() public {
        uint256 amount = 3 ether;
        uint256 routerWethBefore = _routerAvailableBalance(address(weth));
        uint256 crystalEthBefore = address(crystal).balance;
        uint256 crystalWethBefore = weth.balanceOf(address(crystal));
        uint256 wethSupplyBefore = weth.totalSupply();

        vm.prank(carol);
        crystal.routerDeposit{ value: amount }(crystal.eth(), amount);

        assertEq(
            _routerAvailableBalance(address(weth)),
            routerWethBefore + amount,
            "assert _routerAvailableBalance(address(weth)) == routerWethBefore + amount"
        );
        assertEq(
            weth.balanceOf(address(crystal)),
            crystalWethBefore + amount,
            "assert weth.balanceOf(address(crystal)) == crystalWethBefore + amount"
        );
        assertEq(
            weth.totalSupply(), wethSupplyBefore + amount, "assert weth.totalSupply() == wethSupplyBefore + amount"
        );
        assertEq(address(crystal).balance, crystalEthBefore, "assert address(crystal).balance == crystalEthBefore");
    }

    function testRouterWithdrawUnwrapsWethSlotToNativeEth() public {
        uint256 depositAmount = 4 ether;
        uint256 withdrawAmount = 1.5 ether;

        vm.startPrank(carol);
        crystal.routerDeposit{ value: depositAmount }(crystal.eth(), depositAmount);
        uint256 carolEthBefore = carol.balance;
        uint256 crystalWethBefore = weth.balanceOf(address(crystal));
        uint256 wethSupplyBefore = weth.totalSupply();
        crystal.routerWithdraw(carol, crystal.eth(), withdrawAmount);
        vm.stopPrank();

        assertEq(
            _routerAvailableBalance(address(weth)),
            depositAmount - withdrawAmount,
            "assert _routerAvailableBalance(address(weth)) == depositAmount - withdrawAmount"
        );
        assertEq(
            weth.balanceOf(address(crystal)),
            crystalWethBefore - withdrawAmount,
            "assert weth.balanceOf(address(crystal)) == crystalWethBefore - withdrawAmount"
        );
        assertEq(
            weth.totalSupply(),
            wethSupplyBefore - withdrawAmount,
            "assert weth.totalSupply() == wethSupplyBefore - withdrawAmount"
        );
        assertEq(
            carol.balance, carolEthBefore + withdrawAmount, "assert carol.balance == carolEthBefore + withdrawAmount"
        );
    }

    function _routerAvailableBalance(address token) private view returns (uint256 availableBalance) {
        (, availableBalance,) = crystal.getDepositedBalance(address(0), token);
    }
}
