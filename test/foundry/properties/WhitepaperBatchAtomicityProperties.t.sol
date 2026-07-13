// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ICrystal } from "../../../contracts/interfaces/ICrystal.sol";
import { BaseFuzzTest } from "../BaseFuzzTest.t.sol";

contract WhitepaperBatchAtomicityProperties is BaseFuzzTest {
    uint256 private constant INVALID_ACTION = uint256(BatchAction.DecreaseOrder) + 1;

    struct BalanceSnapshot {
        uint256 walletQuote;
        uint256 totalQuote;
        uint256 availableQuote;
        uint256 lockedQuote;
    }

    function testFuzzRequiredFailureRollsBackEarlierSuccessfulBatchAction(uint256 quotePerBaseSeed, uint256 sizeSeed)
        public
    {
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 size = bound(sizeSeed, MARKET_MIN_SIZE * 2, DEPOSIT_QUOTE_AMOUNT / 2);
        BalanceSnapshot memory beforeSnapshot = _quoteSnapshot(alice);
        ICrystal.Action[] memory actions = new ICrystal.Action[](2);
        actions[0] = _action(uint256(BatchAction.BuyLimit), true, price, size, 0);
        actions[1] = _action(uint256(BatchAction.CompleteBuy), true, price, 2 ether, 0);

        vm.prank(alice);
        vm.expectRevert();
        crystal.batchOrders(address(market), actions, 0, block.timestamp, address(0), alice);

        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);

        assertEq(level.size, 0, "assert level.size == 0");
        _assertQuoteSnapshot(alice, beforeSnapshot);
    }

    function testFuzzNonRequiredFailureDoesNotBlockLaterBatchActions(
        uint256 lowQuotePerBaseSeed,
        uint256 highQuotePerBaseSeed,
        uint256 firstSizeSeed,
        uint256 secondSizeSeed
    ) public {
        (uint256 firstPrice, uint256 secondPrice) = _boundOrderedPrices(lowQuotePerBaseSeed, highQuotePerBaseSeed);
        uint256 firstSize = bound(firstSizeSeed, MARKET_MIN_SIZE * 2, DEPOSIT_QUOTE_AMOUNT / 4);
        uint256 secondSize = bound(secondSizeSeed, MARKET_MIN_SIZE * 2, DEPOSIT_QUOTE_AMOUNT / 4);
        ICrystal.Action[] memory actions = new ICrystal.Action[](3);
        actions[0] = _action(uint256(BatchAction.BuyLimit), true, firstPrice, firstSize, 0);
        actions[1] = _action(uint256(BatchAction.SellLimit), false, 0, 0, 0);
        actions[2] = _action(uint256(BatchAction.BuyLimit), true, secondPrice, secondSize, 0);

        vm.prank(alice);
        crystal.batchOrders(address(market), actions, 0, block.timestamp, address(0), alice);

        ICrystal.PriceLevel memory firstLevel = crystal.getPriceLevel(address(market), firstPrice);
        ICrystal.PriceLevel memory secondLevel = crystal.getPriceLevel(address(market), secondPrice);

        assertEq(firstLevel.size, firstSize, "assert firstLevel.size == firstSize");
        assertEq(secondLevel.size, secondSize, "assert secondLevel.size == secondSize");
    }

    function _action(uint256 actionId, bool isRequireSuccess, uint256 param1, uint256 param2, uint256 param3)
        private
        pure
        returns (ICrystal.Action memory action)
    {
        action = ICrystal.Action({
            isRequireSuccess: isRequireSuccess, action: actionId, param1: param1, param2: param2, param3: param3
        });
    }

    function _quoteSnapshot(address user) private view returns (BalanceSnapshot memory snapshot) {
        snapshot.walletQuote = quote.balanceOf(user);
        (snapshot.totalQuote, snapshot.availableQuote, snapshot.lockedQuote) =
            crystal.getDepositedBalance(user, address(quote));
    }

    function _assertQuoteSnapshot(address user, BalanceSnapshot memory expected) private view {
        (uint256 totalQuote, uint256 availableQuote, uint256 lockedQuote) =
            crystal.getDepositedBalance(user, address(quote));

        assertEq(quote.balanceOf(user), expected.walletQuote, "assert quote.balanceOf(user) == expected.walletQuote");
        assertEq(totalQuote, expected.totalQuote, "assert totalQuote == expected.totalQuote");
        assertEq(availableQuote, expected.availableQuote, "assert availableQuote == expected.availableQuote");
        assertEq(lockedQuote, expected.lockedQuote, "assert lockedQuote == expected.lockedQuote");
    }
}
