// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ICrystal } from "../../../contracts/interfaces/ICrystal.sol";
import { BaseFuzzTest } from "../BaseFuzzTest.t.sol";

contract QuoteFuzzTest is BaseFuzzTest {
    function testFuzzGetQuoteReadsRestingAskLiquidity(
        uint256 quotePerBaseSeed,
        uint256 askSizeSeed,
        uint256 quoteInSeed
    ) public {
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 askSize = _boundPartialAskSize(askSizeSeed, price);
        uint256 quoteIn = _boundPartialQuoteIn(quoteInSeed, askSize, price);

        vm.prank(alice);
        crystal.limitOrder(address(market), false, 0, price, askSize, alice);

        (uint256 amountIn, uint256 amountOut) = crystal.getQuote(address(market), true, true, true, quoteIn, price);

        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);
        assertEq(amountIn, quoteIn, "assert amountIn == quoteIn");
        assertEq(
            amountOut,
            _expectedRestingAskBuyOut(quoteIn, price),
            "assert amountOut == _expectedRestingAskBuyOut(quoteIn, price)"
        );
        assertEq(level.size, askSize, "assert level.size == askSize");
    }

    function testFuzzGetQuoteReadsAmmLiquidity(uint256 reserveQuoteSeed, uint256 reserveBaseSeed, uint256 quoteInSeed)
        public
    {
        uint256 reserveQuote = bound(reserveQuoteSeed, MARKET_MIN_SIZE * 1_000, MAX_LIQUIDITY_QUOTE_FUZZ_AMOUNT);
        uint256 reserveBase = _boundAmmBaseForQuote(reserveBaseSeed, reserveQuote);
        uint256 quoteIn = bound(quoteInSeed, MIN_QUOTE_FUZZ_AMOUNT, reserveQuote / 100);

        crystal.addLiquidity(address(market), address(this), reserveQuote, reserveBase, 0, 0);

        (uint256 amountIn, uint256 amountOut) = crystal.getQuote(address(market), true, true, true, quoteIn, 0);

        ICrystal.MarketInfo memory info = crystal.getMarket(address(market));
        assertEq(amountIn, quoteIn, "assert amountIn == quoteIn");
        assertEq(
            amountOut,
            _expectedAmmBuyOut(quoteIn, reserveQuote, reserveBase),
            "assert amountOut == _expectedAmmBuyOut(quoteIn, reserveQuote, reserveBase)"
        );
        assertEq(info.reserveQuote, reserveQuote, "assert info.reserveQuote == reserveQuote");
        assertEq(info.reserveBase, reserveBase, "assert info.reserveBase == reserveBase");
    }

    function testFuzzGetAmountsOutMatchesDirectBuyQuote(
        uint256 quotePerBaseSeed,
        uint256 askSizeSeed,
        uint256 quoteInSeed
    ) public {
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 askSize = _boundPartialAskSize(askSizeSeed, price);
        uint256 quoteIn = _boundPartialQuoteIn(quoteInSeed, askSize, price);

        vm.prank(alice);
        crystal.limitOrder(address(market), false, 0, price, askSize, alice);

        (, uint256 quoteOut) = crystal.getQuote(address(market), true, true, false, quoteIn, 0);
        (uint256[] memory amounts, bool isPartialFill) = crystal.getAmountsOut(quoteIn, _quoteToBasePath());

        assertFalse(isPartialFill, "assert isPartialFill == false");
        assertEq(amounts.length, 2, "assert amounts.length == 2");
        assertEq(amounts[0], quoteIn, "assert amounts[0] == quoteIn");
        assertEq(amounts[1], quoteOut, "assert amounts[1] == quoteOut");
    }

    function testFuzzGetAmountsInMatchesDirectBuyQuote(
        uint256 quotePerBaseSeed,
        uint256 askSizeSeed,
        uint256 desiredBaseSeed
    ) public {
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 askSize = _boundPartialAskSize(askSizeSeed, price);
        uint256 desiredBaseOut = bound(desiredBaseSeed, _minBaseForQuote(MARKET_MIN_SIZE, price), askSize / 2);

        vm.prank(alice);
        crystal.limitOrder(address(market), false, 0, price, askSize, alice);

        (uint256 quoteIn, uint256 baseOut) = crystal.getQuote(address(market), true, false, true, desiredBaseOut, 0);
        uint256[] memory amounts = crystal.getAmountsIn(desiredBaseOut, _quoteToBasePath());

        assertEq(amounts.length, 2, "assert amounts.length == 2");
        assertEq(amounts[0], quoteIn, "assert amounts[0] == quoteIn");
        assertEq(amounts[1], baseOut, "assert amounts[1] == baseOut");
    }

    function _quoteToBasePath() private view returns (address[] memory path) {
        path = new address[](2);
        path[0] = address(quote);
        path[1] = address(weth);
    }

    function _expectedRestingAskBuyOut(uint256 quoteIn, uint256 price) private view returns (uint256) {
        uint256 takerAdjusted = _takerAdjustedExactInput(quoteIn);
        uint256 makerAdjusted = (takerAdjusted * uint256(MARKET_MAKER_REBATE)) / 100000;
        return (makerAdjusted * market.scaleFactor()) / price;
    }

    function _expectedAmmBuyOut(uint256 quoteIn, uint256 reserveQuote, uint256 reserveBase)
        private
        pure
        returns (uint256)
    {
        uint256 ammAmountIn = _takerAdjustedExactInput(quoteIn);
        return (ammAmountIn * 9975 * reserveBase) / ((reserveQuote * 10000) + (ammAmountIn * 9975));
    }

    function _takerAdjustedExactInput(uint256 amountIn) private pure returns (uint256) {
        return (amountIn * uint256(MARKET_TAKER_FEE) + 99999) / 100000;
    }
}
