// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ICrystal } from "../../../contracts/interfaces/ICrystal.sol";
import { BaseFuzzTest } from "../BaseFuzzTest.t.sol";

contract AddLiquidityFuzzTest is BaseFuzzTest {
    function testFuzzAddLiquidityMintsLpAndSetsReserves(uint256 amountQuoteSeed, uint256 amountBaseSeed) public {
        uint256 amountQuote = _boundLiquidityQuoteAmount(amountQuoteSeed);
        uint256 amountBase = _boundLiquidityBaseForQuote(amountBaseSeed, amountQuote);

        uint256 liquidity = crystal.addLiquidity(address(market), address(this), amountQuote, amountBase, 0, 0);

        ICrystal.MarketInfo memory info = crystal.getMarket(address(market));
        assertGt(liquidity, 0, "assert liquidity > 0");
        assertGt(market.balanceOf(address(this)), 0, "assert market.balanceOf(address(this)) > 0");
        assertEq(info.reserveQuote, amountQuote, "assert info.reserveQuote == amountQuote");
        assertEq(info.reserveBase, amountBase, "assert info.reserveBase == amountBase");
    }

    function testFuzzAddLiquidityUsesEthForWethBase(uint256 amountQuoteSeed, uint256 amountBaseSeed) public {
        uint256 amountQuote = _boundLiquidityQuoteAmount(amountQuoteSeed);
        uint256 amountBase = _boundLiquidityBaseForQuote(amountBaseSeed, amountQuote);
        uint256 callerEthBefore = address(this).balance;
        uint256 callerWethBefore = weth.balanceOf(address(this));
        uint256 crystalWethBefore = weth.balanceOf(address(crystal));

        uint256 liquidity =
            crystal.addLiquidity{ value: amountBase }(address(market), address(this), amountQuote, amountBase, 0, 0);

        ICrystal.MarketInfo memory info = crystal.getMarket(address(market));
        assertGt(liquidity, 0, "assert liquidity > 0");
        assertGt(market.balanceOf(address(this)), 0, "assert market.balanceOf(address(this)) > 0");
        assertEq(info.reserveQuote, amountQuote, "assert info.reserveQuote == amountQuote");
        assertEq(info.reserveBase, amountBase, "assert info.reserveBase == amountBase");
        assertEq(
            address(this).balance,
            callerEthBefore - amountBase,
            "assert address(this).balance == callerEthBefore - amountBase"
        );
        assertEq(
            weth.balanceOf(address(this)), callerWethBefore, "assert weth.balanceOf(address(this)) == callerWethBefore"
        );
        assertEq(
            weth.balanceOf(address(crystal)),
            crystalWethBefore + amountBase,
            "assert weth.balanceOf(address(crystal)) == crystalWethBefore + amountBase"
        );
    }
}
