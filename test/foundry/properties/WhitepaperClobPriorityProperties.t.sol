// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ICrystal } from "../../../contracts/interfaces/ICrystal.sol";
import { BaseFuzzTest } from "../BaseFuzzTest.t.sol";

contract WhitepaperClobPriorityProperties is BaseFuzzTest {
    uint256 private constant MAX_FUNDED_ASK_SIZE = 100 ether;

    function setUp() public override {
        super.setUp();
        _registerAndDeposit(carol);
    }

    function testFuzzMarketBuyConsumesLowestAskBeforeHigherAsk(
        uint256 lowQuotePerBaseSeed,
        uint256 highQuotePerBaseSeed,
        uint256 lowAskValueSeed,
        uint256 highAskValueSeed,
        uint256 quoteInSeed
    ) public {
        (uint256 lowAskPrice, uint256 highAskPrice) = _boundOrderedPrices(lowQuotePerBaseSeed, highQuotePerBaseSeed);
        uint256 lowAskSize = _boundAskSize(lowAskValueSeed, lowAskPrice);
        uint256 highAskSize = _boundAskSize(highAskValueSeed, highAskPrice);
        uint256 lowAskValue = _quoteValue(lowAskSize, lowAskPrice);
        uint256 quoteIn = bound(quoteInSeed, MARKET_MIN_SIZE, lowAskValue / 2);

        vm.prank(alice);
        crystal.limitOrder(address(market), false, 0, highAskPrice, highAskSize, alice);
        vm.prank(bob);
        crystal.limitOrder(address(market), false, 0, lowAskPrice, lowAskSize, bob);

        vm.prank(carol);
        (, uint256 amountOut,) = crystal.marketOrder(
            address(market), true, true, 0, ORDER_TYPES_NORMAL, quoteIn, highAskPrice, address(0), carol
        );

        ICrystal.PriceLevel memory lowAskLevel = crystal.getPriceLevel(address(market), lowAskPrice);
        ICrystal.PriceLevel memory highAskLevel = crystal.getPriceLevel(address(market), highAskPrice);

        assertGt(amountOut, 0, "assert amountOut > 0");
        assertLt(lowAskLevel.size, lowAskSize, "assert lowAskLevel.size < lowAskSize");
        assertGt(lowAskLevel.size, 0, "assert lowAskLevel.size > 0");
        assertEq(highAskLevel.size, highAskSize, "assert highAskLevel.size == highAskSize");
    }

    function testFuzzMarketSellConsumesHighestBidBeforeLowerBid(
        uint256 lowQuotePerBaseSeed,
        uint256 highQuotePerBaseSeed,
        uint256 lowBidSizeSeed,
        uint256 highBidSizeSeed,
        uint256 baseInSeed
    ) public {
        (uint256 lowBidPrice, uint256 highBidPrice) = _boundOrderedPrices(lowQuotePerBaseSeed, highQuotePerBaseSeed);
        uint256 lowBidSize = _boundBidSize(lowBidSizeSeed);
        uint256 highBidSize = _boundBidSize(highBidSizeSeed);
        uint256 minBaseIn = _minBaseForQuote(MARKET_MIN_SIZE, highBidPrice);
        uint256 maxBaseIn = _minBaseForQuote(highBidSize / 2, highBidPrice);
        if (maxBaseIn <= minBaseIn) {
            maxBaseIn = minBaseIn + 1;
        }
        uint256 baseIn = bound(baseInSeed, minBaseIn, maxBaseIn);

        vm.prank(alice);
        crystal.limitOrder(address(market), true, 0, lowBidPrice, lowBidSize, alice);
        vm.prank(bob);
        crystal.limitOrder(address(market), true, 0, highBidPrice, highBidSize, bob);

        vm.prank(carol);
        (, uint256 amountOut,) = crystal.marketOrder(
            address(market), false, true, 0, ORDER_TYPES_NORMAL, baseIn, lowBidPrice, address(0), carol
        );

        ICrystal.PriceLevel memory lowBidLevel = crystal.getPriceLevel(address(market), lowBidPrice);
        ICrystal.PriceLevel memory highBidLevel = crystal.getPriceLevel(address(market), highBidPrice);

        assertGt(amountOut, 0, "assert amountOut > 0");
        assertLt(highBidLevel.size, highBidSize, "assert highBidLevel.size < highBidSize");
        assertGt(highBidLevel.size, 0, "assert highBidLevel.size > 0");
        assertEq(lowBidLevel.size, lowBidSize, "assert lowBidLevel.size == lowBidSize");
    }

    function testFuzzMarketBuyConsumesOlderSamePriceAskBeforeNewerAsk(
        uint256 quotePerBaseSeed,
        uint256 firstAskValueSeed,
        uint256 secondAskValueSeed
    ) public {
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 firstAskSize = _boundAskSize(firstAskValueSeed, price);
        uint256 secondAskSize = _boundAskSize(secondAskValueSeed, price);

        vm.prank(alice);
        uint256 firstOrderId = crystal.limitOrder(address(market), false, 0, price, firstAskSize, alice);
        vm.prank(bob);
        uint256 secondOrderId = crystal.limitOrder(address(market), false, 0, price, secondAskSize, bob);

        vm.prank(carol);
        (, uint256 amountOut,) = crystal.marketOrder(
            address(market), true, false, 0, ORDER_TYPES_NORMAL, firstAskSize, price, address(0), carol
        );

        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);
        ICrystal.Order memory firstOrder = crystal.getOrder(address(market), price, firstOrderId);
        ICrystal.Order memory secondOrder = crystal.getOrder(address(market), price, secondOrderId);

        assertEq(amountOut, firstAskSize, "assert amountOut == firstAskSize");
        assertEq(firstOrder.size, 0, "assert firstOrder.size == 0");
        assertEq(secondOrder.size, secondAskSize, "assert secondOrder.size == secondAskSize");
        assertEq(level.size, secondAskSize, "assert level.size == secondAskSize");
    }

    function testFuzzMarketSellConsumesOlderSamePriceBidBeforeNewerBid(
        uint256 quotePerBaseSeed,
        uint256 firstBidSizeSeed,
        uint256 secondBidSizeSeed,
        uint256 baseInSeed
    ) public {
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 firstBidSize = _boundBidSizeForFundedSeller(firstBidSizeSeed, price);
        uint256 secondBidSize = _boundBidSizeForFundedSeller(secondBidSizeSeed, price);
        uint256 minBaseIn = _minBaseForQuote(MARKET_MIN_SIZE, price);
        uint256 maxBaseIn = _minBaseForQuote(firstBidSize / 2, price);
        if (maxBaseIn <= minBaseIn) {
            maxBaseIn = minBaseIn + 1;
        }
        uint256 baseIn = bound(baseInSeed, minBaseIn, maxBaseIn);

        vm.prank(alice);
        uint256 firstOrderId = crystal.limitOrder(address(market), true, 0, price, firstBidSize, alice);
        vm.prank(bob);
        uint256 secondOrderId = crystal.limitOrder(address(market), true, 0, price, secondBidSize, bob);

        uint256 amountOut = _marketSellExactInput(baseIn, price);

        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);
        ICrystal.Order memory firstOrder = crystal.getOrder(address(market), price, firstOrderId);
        ICrystal.Order memory secondOrder = crystal.getOrder(address(market), price, secondOrderId);

        assertGt(amountOut, 0, "assert amountOut > 0");
        assertLt(firstOrder.size, firstBidSize, "assert firstOrder.size < firstBidSize");
        assertGt(firstOrder.size, 0, "assert firstOrder.size > 0");
        assertEq(secondOrder.size, secondBidSize, "assert secondOrder.size == secondBidSize");
        assertEq(level.size, firstOrder.size + secondBidSize, "assert level.size == firstOrder.size + secondBidSize");
    }

    function _boundAskSize(uint256 seed, uint256 price) private view returns (uint256) {
        return bound(seed, _minBaseForQuote(MARKET_MIN_SIZE * 8, price), MAX_FUNDED_ASK_SIZE);
    }

    function _boundBidSize(uint256 seed) private pure returns (uint256) {
        return bound(seed, MARKET_MIN_SIZE * 8, 10_000 * QUOTE_UNIT);
    }

    function _boundBidSizeForFundedSeller(uint256 seed, uint256 price) private view returns (uint256) {
        uint256 maxQuote = _quoteValue(100 ether, price);
        if (maxQuote > 10_000 * QUOTE_UNIT) {
            maxQuote = 10_000 * QUOTE_UNIT;
        }
        return bound(seed, MARKET_MIN_SIZE * 8, maxQuote);
    }

    function _quoteValue(uint256 baseSize, uint256 price) private view returns (uint256) {
        return (baseSize * price) / market.scaleFactor();
    }

    function _marketSellExactInput(uint256 baseIn, uint256 price) private returns (uint256 amountOut) {
        vm.prank(carol);
        (, amountOut,) =
            crystal.marketOrder(address(market), false, true, 0, ORDER_TYPES_NORMAL, baseIn, price, address(0), carol);
    }
}
