// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ICrystal } from "../../../contracts/interfaces/ICrystal.sol";
import { BaseTest } from "../BaseTest.t.sol";

contract MarketOrderTest is BaseTest {
    function testMarketBuyConsumesRestingAsk() public {
        uint256 price = _price(500);
        uint256 askSize = 10 ether;
        uint256 quoteIn = 2_500 * QUOTE_UNIT;

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

    function testMarketSellConsumesRestingBid() public {
        uint256 price = _price(500);
        uint256 bidSize = 5_000 * QUOTE_UNIT;

        vm.prank(alice);
        crystal.limitOrder(address(market), true, 0, price, bidSize, alice);

        uint256 takerQuoteBefore = quote.balanceOf(bob);
        uint256 takerWethBefore = weth.balanceOf(bob);

        {
            (uint256 amountIn, uint256 amountOut, uint256 id) = _sellExactBase(price);

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

    function _sellExactBase(uint256 price) private returns (uint256 amountIn, uint256 amountOut, uint256 id) {
        vm.prank(bob);
        return
            crystal.marketOrder(
                address(market), false, true, 0, ORDER_TYPES_NORMAL, 5 ether, price - 1, address(0), bob
            );
    }
}
