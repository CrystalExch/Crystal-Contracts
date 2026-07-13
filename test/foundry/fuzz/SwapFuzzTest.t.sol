// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseFuzzTest } from "../BaseFuzzTest.t.sol";

contract SwapFuzzTest is BaseFuzzTest {
    function testFuzzSwapExactTokensForTokensSendsWethToCaller(
        uint256 reserveQuoteSeed,
        uint256 reserveBaseSeed,
        uint256 amountInSeed
    ) public {
        (uint256 reserveQuote,) = _addAmmLiquidity(reserveQuoteSeed, reserveBaseSeed);
        uint256 amountIn = bound(amountInSeed, MIN_QUOTE_FUZZ_AMOUNT, reserveQuote / 100);
        address[] memory path = _path(address(quote), address(weth));
        (uint256[] memory quotedAmounts, bool isPartialFill) = crystal.getAmountsOut(amountIn, path);
        assertFalse(isPartialFill, "assert isPartialFill == false");
        uint256 quoteBefore = quote.balanceOf(carol);
        uint256 wethBefore = weth.balanceOf(carol);
        (uint112 reserveQuoteBefore, uint112 reserveBaseBefore) = crystal.getReserves(address(market));

        vm.prank(carol);
        uint256[] memory amounts =
            crystal.swapExactTokensForTokens(amountIn, quotedAmounts[1], path, carol, block.timestamp, address(0));

        (uint112 reserveQuoteAfter, uint112 reserveBaseAfter) = crystal.getReserves(address(market));
        assertEq(amounts.length, 2, "assert amounts.length == 2");
        assertEq(amounts[0], amountIn, "assert amounts[0] == amountIn");
        assertEq(amounts[1], quotedAmounts[1], "assert amounts[1] == quotedAmounts[1]");
        assertApproxEqAbs(
            quote.balanceOf(carol), quoteBefore - amountIn, 1, "assert quote.balanceOf(carol) ~= quoteBefore - amountIn"
        );
        assertEq(
            weth.balanceOf(carol), wethBefore + amounts[1], "assert weth.balanceOf(carol) == wethBefore + amounts[1]"
        );
        assertGt(reserveQuoteAfter, reserveQuoteBefore, "assert reserveQuoteAfter > reserveQuoteBefore");
        assertLt(reserveBaseAfter, reserveBaseBefore, "assert reserveBaseAfter < reserveBaseBefore");
    }

    function testFuzzSwapExactETHForTokensUsesEthSentinel(
        uint256 reserveQuoteSeed,
        uint256 reserveBaseSeed,
        uint256 amountInSeed
    ) public {
        (, uint256 reserveBase) = _addAmmLiquidity(reserveQuoteSeed, reserveBaseSeed);
        uint256 amountIn = bound(amountInSeed, reserveBase / 1_000, reserveBase / 100);
        address[] memory path = _path(crystal.eth(), address(quote));
        (uint256[] memory quotedAmounts, bool isPartialFill) = crystal.getAmountsOut(amountIn, path);
        assertFalse(isPartialFill, "assert isPartialFill == false");
        uint256 ethBefore = carol.balance;
        uint256 quoteBefore = quote.balanceOf(carol);
        uint256 wethBefore = weth.balanceOf(carol);
        (uint112 reserveQuoteBefore, uint112 reserveBaseBefore) = crystal.getReserves(address(market));

        vm.prank(carol);
        uint256[] memory amounts = crystal.swapExactETHForTokens{ value: amountIn }(
            quotedAmounts[1], path, carol, block.timestamp, address(0)
        );

        (uint112 reserveQuoteAfter, uint112 reserveBaseAfter) = crystal.getReserves(address(market));
        assertEq(amounts.length, 2, "assert amounts.length == 2");
        assertEq(amounts[0], amountIn, "assert amounts[0] == amountIn");
        assertEq(amounts[1], quotedAmounts[1], "assert amounts[1] == quotedAmounts[1]");
        assertEq(carol.balance, ethBefore - amountIn, "assert carol.balance == ethBefore - amountIn");
        assertEq(
            quote.balanceOf(carol),
            quoteBefore + amounts[1],
            "assert quote.balanceOf(carol) == quoteBefore + amounts[1]"
        );
        assertEq(weth.balanceOf(carol), wethBefore, "assert weth.balanceOf(carol) == wethBefore");
        assertLt(reserveQuoteAfter, reserveQuoteBefore, "assert reserveQuoteAfter < reserveQuoteBefore");
        assertGt(reserveBaseAfter, reserveBaseBefore, "assert reserveBaseAfter > reserveBaseBefore");
    }

    function testFuzzSwapExactTokensForETHUsesEthSentinel(
        uint256 reserveQuoteSeed,
        uint256 reserveBaseSeed,
        uint256 amountInSeed
    ) public {
        (uint256 reserveQuote,) = _addAmmLiquidity(reserveQuoteSeed, reserveBaseSeed);
        uint256 amountIn = bound(amountInSeed, MIN_QUOTE_FUZZ_AMOUNT, reserveQuote / 100);
        address[] memory path = _path(address(quote), crystal.eth());
        (uint256[] memory quotedAmounts, bool isPartialFill) = crystal.getAmountsOut(amountIn, path);
        assertFalse(isPartialFill, "assert isPartialFill == false");
        uint256 quoteBefore = quote.balanceOf(carol);
        uint256 wethBefore = weth.balanceOf(carol);
        uint256 ethBefore = carol.balance;
        (uint112 reserveQuoteBefore, uint112 reserveBaseBefore) = crystal.getReserves(address(market));

        vm.prank(carol);
        uint256[] memory amounts =
            crystal.swapExactTokensForETH(amountIn, quotedAmounts[1], path, carol, block.timestamp, address(0));

        (uint112 reserveQuoteAfter, uint112 reserveBaseAfter) = crystal.getReserves(address(market));
        assertEq(amounts.length, 2, "assert amounts.length == 2");
        assertEq(amounts[0], amountIn, "assert amounts[0] == amountIn");
        assertEq(amounts[1], quotedAmounts[1], "assert amounts[1] == quotedAmounts[1]");
        assertApproxEqAbs(
            quote.balanceOf(carol), quoteBefore - amountIn, 1, "assert quote.balanceOf(carol) ~= quoteBefore - amountIn"
        );
        assertEq(weth.balanceOf(carol), wethBefore, "assert weth.balanceOf(carol) == wethBefore");
        assertEq(carol.balance, ethBefore + amounts[1], "assert carol.balance == ethBefore + amounts[1]");
        assertGt(reserveQuoteAfter, reserveQuoteBefore, "assert reserveQuoteAfter > reserveQuoteBefore");
        assertLt(reserveBaseAfter, reserveBaseBefore, "assert reserveBaseAfter < reserveBaseBefore");
    }

    function _addAmmLiquidity(uint256 reserveQuoteSeed, uint256 reserveBaseSeed)
        private
        returns (uint256 reserveQuote, uint256 reserveBase)
    {
        reserveQuote = bound(reserveQuoteSeed, MARKET_MIN_SIZE * 1_000, MAX_LIQUIDITY_QUOTE_FUZZ_AMOUNT);
        reserveBase = _boundAmmBaseForQuote(reserveBaseSeed, reserveQuote);
        crystal.addLiquidity(address(market), address(this), reserveQuote, reserveBase, 0, 0);
    }

    function _path(address tokenIn, address tokenOut) private pure returns (address[] memory path) {
        path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
    }
}
