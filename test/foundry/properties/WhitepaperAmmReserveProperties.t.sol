// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseFuzzTest } from "../BaseFuzzTest.t.sol";

contract WhitepaperAmmReserveProperties is BaseFuzzTest {
    function testFuzzExactInputAmmSwapDoesNotDecreaseReserveProduct(
        uint256 reserveQuoteSeed,
        uint256 reserveBaseSeed,
        uint256 amountInSeed
    ) public {
        uint256 amountQuote = _boundLargeLiquidityQuote(reserveQuoteSeed);
        uint256 amountBase = _boundAmmBaseForQuote(reserveBaseSeed, amountQuote);
        crystal.addLiquidity(address(market), address(this), amountQuote, amountBase, 0, 0);
        uint256 amountIn = bound(amountInSeed, MARKET_MIN_SIZE, amountQuote / 10);
        address[] memory path = _path(address(quote), address(weth));
        (uint256[] memory quotedAmounts, bool isPartialFill) = crystal.getAmountsOut(amountIn, path);
        if (isPartialFill) {
            return;
        }
        (uint112 reserveQuoteBefore, uint112 reserveBaseBefore) = crystal.getReserves(address(market));
        uint256 productBefore = uint256(reserveQuoteBefore) * uint256(reserveBaseBefore);

        assertGt(quotedAmounts[1], 0, "assert quotedAmounts[1] > 0");

        vm.prank(carol);
        crystal.swapExactTokensForTokens(amountIn, quotedAmounts[1], path, carol, block.timestamp, address(0));

        (uint112 reserveQuoteAfter, uint112 reserveBaseAfter) = crystal.getReserves(address(market));
        uint256 productAfter = uint256(reserveQuoteAfter) * uint256(reserveBaseAfter);

        assertGe(productAfter, productBefore, "assert productAfter >= productBefore");
        assertGt(reserveQuoteAfter, reserveQuoteBefore, "assert reserveQuoteAfter > reserveQuoteBefore");
        assertLt(reserveBaseAfter, reserveBaseBefore, "assert reserveBaseAfter < reserveBaseBefore");
    }

    function testFuzzRemoveLiquidityBurnsLpAndDebitsReservesProRata(
        uint256 reserveQuoteSeed,
        uint256 reserveBaseSeed,
        uint256 liquiditySeed
    ) public {
        uint256 amountQuote = _boundLargeLiquidityQuote(reserveQuoteSeed);
        uint256 amountBase = _boundAmmBaseForQuote(reserveBaseSeed, amountQuote);
        crystal.addLiquidity(address(market), address(this), amountQuote, amountBase, 0, 0);
        uint256 lpBalance = market.balanceOf(address(this));
        uint256 liquidityToRemove = bound(liquiditySeed, 1, lpBalance);
        uint256 totalSupplyBefore = market.totalSupply();
        (uint112 reserveQuoteBefore, uint112 reserveBaseBefore) = crystal.getReserves(address(market));
        uint256 expectedQuoteOut = (liquidityToRemove * reserveQuoteBefore) / totalSupplyBefore;
        uint256 expectedBaseOut = (liquidityToRemove * reserveBaseBefore) / totalSupplyBefore;
        market.approve(address(crystal), liquidityToRemove);

        (uint256 quoteOut, uint256 baseOut) =
            crystal.removeLiquidity(address(market), address(this), liquidityToRemove, 0, 0);

        (uint112 reserveQuoteAfter, uint112 reserveBaseAfter) = crystal.getReserves(address(market));

        assertEq(quoteOut, expectedQuoteOut, "assert quoteOut == expectedQuoteOut");
        assertEq(baseOut, expectedBaseOut, "assert baseOut == expectedBaseOut");
        assertEq(
            market.totalSupply(),
            totalSupplyBefore - liquidityToRemove,
            "assert market.totalSupply() == totalSupplyBefore - liquidityToRemove"
        );
        assertEq(
            reserveQuoteAfter,
            reserveQuoteBefore - quoteOut,
            "assert reserveQuoteAfter == reserveQuoteBefore - quoteOut"
        );
        assertEq(
            reserveBaseAfter, reserveBaseBefore - baseOut, "assert reserveBaseAfter == reserveBaseBefore - baseOut"
        );
    }

    function _boundLargeLiquidityQuote(uint256 amount) private pure returns (uint256) {
        return bound(amount, MARKET_MIN_SIZE * 1_000, 100_000_000 * QUOTE_UNIT);
    }

    function _path(address tokenIn, address tokenOut) private pure returns (address[] memory path) {
        path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
    }
}
