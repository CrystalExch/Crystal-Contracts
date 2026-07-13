// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "../BaseTest.t.sol";

contract SwapTest is BaseTest {
    function testSwapExactTokensForTokensSendsWethToCaller() public {
        _addAmmLiquidity();
        uint256 amountIn = 1_000 * QUOTE_UNIT;
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
        assertEq(
            quote.balanceOf(carol), quoteBefore - amountIn, "assert quote.balanceOf(carol) == quoteBefore - amountIn"
        );
        assertEq(
            weth.balanceOf(carol), wethBefore + amounts[1], "assert weth.balanceOf(carol) == wethBefore + amounts[1]"
        );
        assertGt(reserveQuoteAfter, reserveQuoteBefore, "assert reserveQuoteAfter > reserveQuoteBefore");
        assertLt(reserveBaseAfter, reserveBaseBefore, "assert reserveBaseAfter < reserveBaseBefore");
    }

    function testSwapExactETHForTokensUsesEthSentinel() public {
        _addAmmLiquidity();
        uint256 amountIn = 1 ether;
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

    function testSwapExactTokensForETHUsesEthSentinel() public {
        _addAmmLiquidity();
        uint256 amountIn = 1_000 * QUOTE_UNIT;
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
        assertEq(
            quote.balanceOf(carol), quoteBefore - amountIn, "assert quote.balanceOf(carol) == quoteBefore - amountIn"
        );
        assertEq(weth.balanceOf(carol), wethBefore, "assert weth.balanceOf(carol) == wethBefore");
        assertEq(carol.balance, ethBefore + amounts[1], "assert carol.balance == ethBefore + amounts[1]");
        assertGt(reserveQuoteAfter, reserveQuoteBefore, "assert reserveQuoteAfter > reserveQuoteBefore");
        assertLt(reserveBaseAfter, reserveBaseBefore, "assert reserveBaseAfter < reserveBaseBefore");
    }

    function _addAmmLiquidity() private {
        crystal.addLiquidity(address(market), address(this), 100_000 * QUOTE_UNIT, 100 ether, 0, 0);
    }

    function _path(address tokenIn, address tokenOut) private pure returns (address[] memory path) {
        path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
    }
}
