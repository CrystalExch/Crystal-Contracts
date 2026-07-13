// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ICrystal } from "../../../contracts/interfaces/ICrystal.sol";
import { BaseFuzzTest } from "../BaseFuzzTest.t.sol";

contract MarketOrderFuzzTest is BaseFuzzTest {
    function testFuzzMarketBuyConsumesRestingAsk(uint256 quotePerBaseSeed, uint256 askSizeSeed, uint256 quoteInSeed)
        public
    {
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 askSize = _boundPartialAskSize(askSizeSeed, price);
        uint256 quoteIn = _boundPartialQuoteIn(quoteInSeed, askSize, price);

        vm.prank(alice);
        crystal.limitOrder(address(market), false, 0, price, askSize, alice);

        uint256 takerWethBefore = weth.balanceOf(bob);

        vm.prank(bob);
        (uint256 amountIn, uint256 amountOut, uint256 id) = crystal.marketOrder(
            address(market), true, true, 0, ORDER_TYPES_NORMAL, quoteIn, price + 1, address(0), bob
        );

        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);

        assertGt(amountIn, 0, "assert amountIn > 0");
        assertGt(amountOut, 0, "assert amountOut > 0");
        assertEq(id, 0, "assert id == 0");
        assertGt(weth.balanceOf(bob), takerWethBefore, "assert weth.balanceOf(bob) > takerWethBefore");
        assertLt(level.size, askSize, "assert level.size < askSize");
    }

    function testFuzzMarketSellConsumesRestingBid(uint256 quotePerBaseSeed, uint256 bidSizeSeed, uint256 baseInSeed)
        public
    {
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 bidSize = _boundPartialBidSize(bidSizeSeed);
        uint256 baseIn = _boundPartialBaseIn(baseInSeed, bidSize, price);

        vm.prank(alice);
        crystal.limitOrder(address(market), true, 0, price, bidSize, alice);

        uint256 takerQuoteBefore = quote.balanceOf(bob);
        uint256 takerWethBefore = weth.balanceOf(bob);

        {
            (uint256 amountIn, uint256 amountOut, uint256 id) = _sellExactBase(price, baseIn);

            assertGt(amountIn, 0, "assert amountIn > 0");
            assertGt(amountOut, 0, "assert amountOut > 0");
            assertEq(id, 0, "assert id == 0");
            assertEq(
                quote.balanceOf(bob),
                takerQuoteBefore + amountOut,
                "assert quote.balanceOf(bob) == takerQuoteBefore + amountOut"
            );
            assertEq(
                weth.balanceOf(bob),
                takerWethBefore - amountIn,
                "assert weth.balanceOf(bob) == takerWethBefore - amountIn"
            );
        }

        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);
        assertLt(level.size, bidSize, "assert level.size < bidSize");
        assertGt(level.size, 0, "assert level.size > 0");
    }

    function _sellExactBase(uint256 price, uint256 baseIn)
        private
        returns (uint256 amountIn, uint256 amountOut, uint256 id)
    {
        vm.prank(bob);
        return
            crystal.marketOrder(address(market), false, true, 0, ORDER_TYPES_NORMAL, baseIn, price - 1, address(0), bob);
    }
}
