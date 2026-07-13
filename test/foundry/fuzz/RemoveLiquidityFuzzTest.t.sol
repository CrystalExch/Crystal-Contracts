// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseFuzzTest } from "../BaseFuzzTest.t.sol";

contract RemoveLiquidityFuzzTest is BaseFuzzTest {
    function testFuzzRemoveLiquidityReturnsQuoteAndBaseTokens(
        uint256 amountQuoteSeed,
        uint256 amountBaseSeed,
        uint256 liquiditySeed
    ) public {
        uint256 amountQuote = _boundLiquidityQuoteAmount(amountQuoteSeed);
        uint256 amountBase = _boundLiquidityBaseForQuote(amountBaseSeed, amountQuote);

        crystal.addLiquidity(address(market), address(this), amountQuote, amountBase, 0, 0);
        uint256 lpBalance = market.balanceOf(address(this));
        uint256 liquidityToRemove = bound(liquiditySeed, lpBalance / 4, lpBalance / 2);
        market.approve(address(crystal), lpBalance);

        (uint256 quoteOut, uint256 baseOut) =
            crystal.removeLiquidity(address(market), address(this), liquidityToRemove, 0, 0);

        assertGt(quoteOut, 0, "assert quoteOut > 0");
        assertGt(baseOut, 0, "assert baseOut > 0");
        assertEq(
            market.balanceOf(address(this)),
            lpBalance - liquidityToRemove,
            "assert market.balanceOf(address(this)) == lpBalance - liquidityToRemove"
        );
    }

    function testFuzzRemoveLiquidityETHUnwrapsWethBaseForRecipient(
        uint256 amountQuoteSeed,
        uint256 amountBaseSeed,
        uint256 liquiditySeed
    ) public {
        uint256 amountQuote = _boundLiquidityQuoteAmount(amountQuoteSeed);
        uint256 amountBase = _boundLiquidityBaseForQuote(amountBaseSeed, amountQuote);

        crystal.addLiquidity{ value: amountBase }(address(market), address(this), amountQuote, amountBase, 0, 0);
        uint256 lpBalance = market.balanceOf(address(this));
        uint256 liquidityToRemove = bound(liquiditySeed, lpBalance / 4, lpBalance / 2);
        uint256 recipientQuoteBefore = quote.balanceOf(carol);
        uint256 recipientWethBefore = weth.balanceOf(carol);
        uint256 recipientEthBefore = carol.balance;
        market.approve(address(crystal), liquidityToRemove);

        (uint256 quoteOut, uint256 baseOut) =
            crystal.removeLiquidityETH(address(market), carol, liquidityToRemove, 0, 0);

        assertGt(quoteOut, 0, "assert quoteOut > 0");
        assertGt(baseOut, 0, "assert baseOut > 0");
        assertEq(
            quote.balanceOf(carol),
            recipientQuoteBefore + quoteOut,
            "assert quote.balanceOf(carol) == recipientQuoteBefore + quoteOut"
        );
        assertEq(weth.balanceOf(carol), recipientWethBefore, "assert weth.balanceOf(carol) == recipientWethBefore");
        assertEq(carol.balance, recipientEthBefore + baseOut, "assert carol.balance == recipientEthBefore + baseOut");
        assertEq(
            market.balanceOf(address(this)),
            lpBalance - liquidityToRemove,
            "assert market.balanceOf(address(this)) == lpBalance - liquidityToRemove"
        );
    }
}
