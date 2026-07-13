// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { CrystalMath } from "../../contracts/libraries/CrystalMath.sol";
import { BaseTest } from "./BaseTest.t.sol";

abstract contract BaseFuzzTest is BaseTest {
    uint256 internal constant MIN_QUOTE_FUZZ_AMOUNT = MARKET_MIN_SIZE;
    uint256 internal constant MAX_QUOTE_FUZZ_AMOUNT = 10_000_000 * QUOTE_UNIT;
    uint256 internal constant MAX_LIQUIDITY_QUOTE_FUZZ_AMOUNT = 100_000_000 * QUOTE_UNIT;
    uint256 internal constant MAX_BASE_FUZZ_AMOUNT = 1_000 ether;
    uint256 internal constant MAX_LIQUIDITY_BASE_FUZZ_AMOUNT = 1_000 ether;
    uint256 internal constant MIN_ETH_FUZZ_AMOUNT = 1 gwei;
    uint256 internal constant MAX_ETH_FUZZ_AMOUNT = 1_000 ether;
    uint256 internal constant MIN_QUOTE_PER_BASE = 2;
    uint256 internal constant MAX_QUOTE_PER_BASE = 999_999;

    function _boundQuoteAmount(uint256 amount) internal pure returns (uint256) {
        return bound(amount, MIN_QUOTE_FUZZ_AMOUNT, MAX_QUOTE_FUZZ_AMOUNT);
    }

    function _boundLiquidityQuoteAmount(uint256 amount) internal pure returns (uint256) {
        return bound(amount, MIN_QUOTE_FUZZ_AMOUNT, MAX_LIQUIDITY_QUOTE_FUZZ_AMOUNT);
    }

    function _boundInternalQuoteAmount(uint256 amount) internal pure returns (uint256) {
        return bound(amount, MIN_QUOTE_FUZZ_AMOUNT, DEPOSIT_QUOTE_AMOUNT);
    }

    function _boundEthAmount(uint256 amount) internal pure returns (uint256) {
        return bound(amount, MIN_ETH_FUZZ_AMOUNT, MAX_ETH_FUZZ_AMOUNT);
    }

    function _boundLiquidityBaseAmount(uint256 amount) internal pure returns (uint256) {
        return bound(amount, MIN_ETH_FUZZ_AMOUNT, MAX_LIQUIDITY_BASE_FUZZ_AMOUNT);
    }

    function _boundLiquidityBaseForQuote(uint256 amount, uint256 quoteAmount) internal view returns (uint256) {
        uint256 minBase = _minBaseForQuote(quoteAmount, MARKET_MAX_PRICE) + 1;
        if (minBase < MIN_ETH_FUZZ_AMOUNT) {
            minBase = MIN_ETH_FUZZ_AMOUNT;
        }
        return bound(amount, minBase, MAX_LIQUIDITY_BASE_FUZZ_AMOUNT);
    }

    function _boundAmmBaseForQuote(uint256 amount, uint256 quoteAmount) internal view returns (uint256) {
        uint256 minBase = _minBaseForQuote(quoteAmount, _price(500_000));
        return bound(amount, minBase, MAX_LIQUIDITY_BASE_FUZZ_AMOUNT);
    }

    function _boundQuotePerBase(uint256 quotePerBase) internal pure returns (uint256) {
        return bound(quotePerBase, MIN_QUOTE_PER_BASE, MAX_QUOTE_PER_BASE);
    }

    function _boundPrice(uint256 quotePerBase) internal view returns (uint256) {
        return CrystalMath._toValidPrice(_price(_boundQuotePerBase(quotePerBase)), false);
    }

    function _boundDifferentPrices(uint256 oldQuotePerBase, uint256 newQuotePerBase)
        internal
        view
        returns (uint256 price, uint256 newPrice)
    {
        price = _boundPrice(oldQuotePerBase);
        newPrice = _boundPrice(newQuotePerBase);
        if (newPrice == price) {
            uint256 oldBound = _boundQuotePerBase(oldQuotePerBase);
            uint256 newBound = oldBound + 100 <= MAX_QUOTE_PER_BASE ? oldBound + 100 : oldBound - 100;
            newPrice = CrystalMath._toValidPrice(_price(newBound), false);
        }
    }

    function _boundOrderedPrices(uint256 lowQuotePerBaseSeed, uint256 highQuotePerBaseSeed)
        internal
        view
        returns (uint256 lowPrice, uint256 highPrice)
    {
        uint256 lowQuotePerBase = bound(lowQuotePerBaseSeed, MIN_QUOTE_PER_BASE, MAX_QUOTE_PER_BASE - 100);
        uint256 highQuotePerBase = bound(highQuotePerBaseSeed, lowQuotePerBase + 100, MAX_QUOTE_PER_BASE);
        lowPrice = CrystalMath._toValidPrice(_price(lowQuotePerBase), false);
        highPrice = CrystalMath._toValidPrice(_price(highQuotePerBase), false);
        if (highPrice <= lowPrice) {
            highPrice = CrystalMath._toValidPrice(_price(lowQuotePerBase + 100), false);
        }
    }

    function _minBaseForQuote(uint256 quoteAmount, uint256 price) internal view returns (uint256) {
        return (quoteAmount * market.scaleFactor() + price - 1) / price;
    }

    function _boundSellSize(uint256 size, uint256 price) internal view returns (uint256) {
        return bound(size, _minBaseForQuote(MARKET_MIN_SIZE, price), MAX_BASE_FUZZ_AMOUNT);
    }

    function _boundInternalSellSize(uint256 size, uint256 price) internal view returns (uint256) {
        return bound(size, _minBaseForQuote(MARKET_MIN_SIZE, price), DEPOSIT_WETH_AMOUNT);
    }

    function _boundPartialAskSize(uint256 size, uint256 price) internal view returns (uint256) {
        return bound(size, _minBaseForQuote(MARKET_MIN_SIZE * 4, price), MAX_BASE_FUZZ_AMOUNT);
    }

    function _boundPartialBidSize(uint256 size) internal pure returns (uint256) {
        return bound(size, MARKET_MIN_SIZE * 4, MAX_QUOTE_FUZZ_AMOUNT);
    }

    function _boundPartialQuoteIn(uint256 amount, uint256 askSize, uint256 price) internal view returns (uint256) {
        uint256 fullQuote = (askSize * price) / market.scaleFactor();
        return bound(amount, MARKET_MIN_SIZE, fullQuote / 2);
    }

    function _boundPartialBaseIn(uint256 amount, uint256 bidSize, uint256 price) internal view returns (uint256) {
        uint256 minBase = _minBaseForQuote(MARKET_MIN_SIZE, price);
        uint256 maxBase = ((bidSize * market.scaleFactor()) / price) / 2;
        if (maxBase > MAX_BASE_FUZZ_AMOUNT) {
            maxBase = MAX_BASE_FUZZ_AMOUNT;
        }
        return bound(amount, minBase, maxBase);
    }

    function _boundFreshUser(uint256 seed) internal pure returns (address) {
        uint256 userIndex = bound(seed, 0, 3);
        if (userIndex == 0) {
            return alice;
        }
        if (userIndex == 1) {
            return bob;
        }
        if (userIndex == 2) {
            return carol;
        }
        return CRYSTAL_GOVERNANCE;
    }
}
