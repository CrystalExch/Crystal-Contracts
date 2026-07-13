// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "../BaseTest.t.sol";

contract RemoveLiquidityTest is BaseTest {
    function testRemoveLiquidityReturnsQuoteAndBaseTokens() public {
        uint256 amountQuote = 100_000 * QUOTE_UNIT;
        uint256 amountBase = 100 ether;

        crystal.addLiquidity(address(market), address(this), amountQuote, amountBase, 0, 0);
        uint256 lpBalance = market.balanceOf(address(this));
        market.approve(address(crystal), lpBalance);

        (uint256 quoteOut, uint256 baseOut) =
            crystal.removeLiquidity(address(market), address(this), lpBalance / 2, 0, 0);

        assertGt(quoteOut, 0, "assert quoteOut > 0");
        assertGt(baseOut, 0, "assert baseOut > 0");
        assertEq(
            market.balanceOf(address(this)),
            lpBalance - (lpBalance / 2),
            "assert market.balanceOf(address(this)) == lpBalance - (lpBalance / 2)"
        );
    }

    function testRemoveLiquidityETHUnwrapsWethBaseForRecipient() public {
        uint256 amountQuote = 100_000 * QUOTE_UNIT;
        uint256 amountBase = 100 ether;

        crystal.addLiquidity{ value: amountBase }(address(market), address(this), amountQuote, amountBase, 0, 0);
        uint256 lpBalance = market.balanceOf(address(this));
        uint256 liquidityToRemove = lpBalance / 2;
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
