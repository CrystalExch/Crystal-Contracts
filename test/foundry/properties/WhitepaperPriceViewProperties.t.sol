// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ICrystal } from "../../../contracts/interfaces/ICrystal.sol";
import { BaseFuzzTest } from "../BaseFuzzTest.t.sol";

contract WhitepaperPriceViewProperties is BaseFuzzTest {
    uint256 private constant PRICE_LEVEL_SIZE_OFFSET = 2 ** 128;

    function testFuzzPriceLevelViewsAreBoundedSortedAndMatchDirectLevels(
        uint256 firstSizeSeed,
        uint256 secondSizeSeed,
        uint256 thirdSizeSeed,
        uint256 fourthSizeSeed,
        uint256 maxSeed
    ) public {
        uint256 maxLevels = bound(maxSeed, 1, 4);

        _seedBidLevel(_price(400), firstSizeSeed);
        _seedBidLevel(_price(500), secondSizeSeed);
        _seedBidLevel(_price(600), thirdSizeSeed);
        _seedBidLevel(_price(700), fourthSizeSeed);

        _assertPriceLevelsView(_price(400), _price(700), true, maxLevels);
        _assertPriceLevelsView(_price(700), _price(400), false, maxLevels);
    }

    function _seedBidLevel(uint256 price, uint256 sizeSeed) private {
        vm.prank(alice);
        crystal.limitOrder(address(market), true, 0, price, _boundBidSize(sizeSeed), alice);
    }

    function _assertPriceLevelsView(uint256 startPrice, uint256 endPrice, bool isAscending, uint256 maxLevels) private {
        uint256 distance = isAscending ? endPrice - startPrice : startPrice - endPrice;
        bytes memory encodedLevels =
            crystal.getPriceLevels(address(market), isAscending, startPrice, distance, MARKET_TICK_SIZE, maxLevels);
        _assertEncodedLevelsBoundedSortedAndMatch(encodedLevels, isAscending, maxLevels);
    }

    function _assertEncodedLevelsBoundedSortedAndMatch(bytes memory encodedLevels, bool isAscending, uint256 maxLevels)
        private
        view
    {
        uint256 levelCount = encodedLevels.length / 32;
        uint256 previousPrice;

        assertEq(encodedLevels.length % 32, 0, "assert encodedLevels.length % 32 == 0");
        assertLe(levelCount, maxLevels, "assert levelCount <= maxLevels");

        for (uint256 i = 0; i < levelCount; i++) {
            uint256 encoded = _encodedWordAt(encodedLevels, i);
            uint256 price = encoded / PRICE_LEVEL_SIZE_OFFSET;
            uint256 size = encoded - (price * PRICE_LEVEL_SIZE_OFFSET);
            ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);

            if (i > 0 && isAscending) {
                assertGt(price, previousPrice, "assert price > previousPrice");
            } else if (i > 0) {
                assertLt(price, previousPrice, "assert price < previousPrice");
            }

            assertGt(size, 0, "assert size > 0");
            assertEq(size, level.size, "assert size == level.size");
            previousPrice = price;
        }
    }

    function _boundBidSize(uint256 seed) private pure returns (uint256) {
        return bound(seed, MARKET_MIN_SIZE * 2, 10_000 * QUOTE_UNIT);
    }

    function _encodedWordAt(bytes memory data, uint256 index) private pure returns (uint256 encoded) {
        assembly {
            encoded := mload(add(add(data, 32), mul(index, 32)))
        }
    }
}
