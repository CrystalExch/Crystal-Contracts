// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IERC20 } from "../../../contracts/interfaces/IERC20.sol";
import { BaseFuzzTest } from "../BaseFuzzTest.t.sol";

contract LaunchpadProperties is BaseFuzzTest {
    struct LaunchpadSnapshot {
        uint256 virtualNativeReserve;
        uint256 virtualTokenReserve;
        uint256 k;
        uint256 tokenBalance;
        uint256 nativeBalance;
    }

    function testFuzzLaunchpadQuoteBuyMatchesExecutionAndDoesNotMutate(uint256 amountSeed) public {
        address token = _createLaunchpadToken();
        uint256 amountIn = bound(amountSeed, 1 gwei, 10 ether);
        LaunchpadSnapshot memory beforeQuote = _snapshot(token, alice);

        (uint256 quotedIn, uint256 quotedOut, bool quotedGraduated) = crystal.quoteBuy(true, token, amountIn, 0);

        LaunchpadSnapshot memory afterQuote = _snapshot(token, alice);
        assertEq(
            afterQuote.virtualNativeReserve,
            beforeQuote.virtualNativeReserve,
            "assert afterQuote.virtualNativeReserve == beforeQuote.virtualNativeReserve"
        );
        assertEq(
            afterQuote.virtualTokenReserve,
            beforeQuote.virtualTokenReserve,
            "assert afterQuote.virtualTokenReserve == beforeQuote.virtualTokenReserve"
        );
        assertEq(
            afterQuote.tokenBalance,
            beforeQuote.tokenBalance,
            "assert afterQuote.tokenBalance == beforeQuote.tokenBalance"
        );

        vm.prank(alice);
        (uint256 actualIn, uint256 actualOut, bool actualGraduated) =
            crystal.buy{ value: quotedIn }(true, token, quotedIn, 0);

        assertEq(actualIn, quotedIn, "assert actualIn == quotedIn");
        assertEq(actualOut, quotedOut, "assert actualOut == quotedOut");
        assertEq(actualGraduated, quotedGraduated, "assert actualGraduated == quotedGraduated");
    }

    function testFuzzLaunchpadBuyAndSellMoveReservesAndPreserveProduct(uint256 buySeed, uint256 sellSeed) public {
        address token = _createLaunchpadToken();
        uint256 amountIn = bound(buySeed, 1 gwei, 10 ether);

        LaunchpadSnapshot memory beforeBuy = _snapshot(token, alice);
        vm.prank(alice);
        (, uint256 tokenOut,) = crystal.buy{ value: amountIn }(true, token, amountIn, 0);
        LaunchpadSnapshot memory afterBuy = _snapshot(token, alice);

        assertGt(
            afterBuy.virtualNativeReserve,
            beforeBuy.virtualNativeReserve,
            "assert afterBuy.virtualNativeReserve > beforeBuy.virtualNativeReserve"
        );
        assertLt(
            afterBuy.virtualTokenReserve,
            beforeBuy.virtualTokenReserve,
            "assert afterBuy.virtualTokenReserve < beforeBuy.virtualTokenReserve"
        );
        assertGe(
            afterBuy.virtualNativeReserve * afterBuy.virtualTokenReserve,
            afterBuy.k,
            "assert afterBuy.virtualNativeReserve * afterBuy.virtualTokenReserve >= afterBuy.k"
        );

        uint256 sellAmount = bound(sellSeed, 1, tokenOut);
        (, uint256 quotedNativeOut) = crystal.quoteSell(true, token, sellAmount, 0);
        if (quotedNativeOut == 0) {
            return;
        }
        vm.startPrank(alice);
        IERC20(token).approve(address(crystal), sellAmount);
        crystal.sell(true, token, sellAmount, 0);
        vm.stopPrank();
        LaunchpadSnapshot memory afterSell = _snapshot(token, alice);

        assertLt(
            afterSell.virtualNativeReserve,
            afterBuy.virtualNativeReserve,
            "assert afterSell.virtualNativeReserve < afterBuy.virtualNativeReserve"
        );
        assertGt(
            afterSell.virtualTokenReserve,
            afterBuy.virtualTokenReserve,
            "assert afterSell.virtualTokenReserve > afterBuy.virtualTokenReserve"
        );
        assertGe(
            afterSell.virtualNativeReserve * afterSell.virtualTokenReserve,
            afterSell.k,
            "assert afterSell.virtualNativeReserve * afterSell.virtualTokenReserve >= afterSell.k"
        );
    }

    function _createLaunchpadToken() private returns (address token) {
        vm.prank(alice);
        token = crystal.createToken{ value: LAUNCHPAD_FEE }(
            "Property Token", "PROP", "property", "property token", "", "", "", ""
        );
    }

    function _snapshot(address token, address account) private view returns (LaunchpadSnapshot memory snapshot) {
        (uint112 virtualNativeReserve, uint112 virtualTokenReserve, uint256 k,,) =
            crystal.launchpadTokenToMarket(token);
        snapshot.virtualNativeReserve = uint256(virtualNativeReserve);
        snapshot.virtualTokenReserve = uint256(virtualTokenReserve);
        snapshot.k = k;
        snapshot.tokenBalance = IERC20(token).balanceOf(account);
        snapshot.nativeBalance = account.balance;
    }
}
