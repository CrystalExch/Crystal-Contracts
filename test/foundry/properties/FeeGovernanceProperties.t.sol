// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ICrystal } from "../../../contracts/interfaces/ICrystal.sol";
import { BaseFuzzTest } from "../BaseFuzzTest.t.sol";

contract FeeGovernanceProperties is BaseFuzzTest {
    struct OrderAndBalanceSnapshot {
        uint256 orderSize;
        uint256 totalQuote;
        uint256 availableQuote;
        uint256 lockedQuote;
        uint256 totalBase;
        uint256 availableBase;
        uint256 lockedBase;
    }

    function setUp() public override {
        super.setUp();
        _registerAndDeposit(carol);
    }

    function testFuzzMakerSettlementAndRewardsDoNotExceedTakerInput(uint256 quotePerBaseSeed, uint256 askSizeSeed)
        public
    {
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 askSize = _boundAskSize(askSizeSeed, price);
        uint256 makerQuoteBefore = quote.balanceOf(alice);
        uint256 feeRecipientRewardsBefore = crystal.claimableRewards(address(quote), address(this));
        uint256 referrerRewardsBefore = crystal.claimableRewards(address(quote), carol);

        vm.prank(alice);
        crystal.limitOrder(address(market), false, 0, price, askSize, alice);

        vm.prank(bob);
        (uint256 amountIn, uint256 amountOut,) =
            crystal.marketOrder(address(market), true, false, 0, ORDER_TYPES_NORMAL, askSize, price, carol, bob);

        uint256 makerQuoteDelta = quote.balanceOf(alice) - makerQuoteBefore;
        uint256 feeRecipientRewardsDelta =
            crystal.claimableRewards(address(quote), address(this)) - feeRecipientRewardsBefore;
        uint256 referrerRewardsDelta = crystal.claimableRewards(address(quote), carol) - referrerRewardsBefore;
        uint256 minimumMakerQuote = _quoteValue(amountOut, price);

        assertEq(amountOut, askSize, "assert amountOut == askSize");
        assertGe(makerQuoteDelta, minimumMakerQuote, "assert makerQuoteDelta >= minimumMakerQuote");
        assertLe(
            makerQuoteDelta + feeRecipientRewardsDelta + referrerRewardsDelta,
            amountIn,
            "assert makerQuoteDelta + feeRecipientRewardsDelta + referrerRewardsDelta <= amountIn"
        );
    }

    function testFuzzGovernanceMarketParamChangeDoesNotMutateExistingOrderOrBalances(
        uint256 quotePerBaseSeed,
        uint256 sizeSeed,
        uint256 feeSeed
    ) public {
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 size = bound(sizeSeed, MARKET_MIN_SIZE * 2, DEPOSIT_QUOTE_AMOUNT / 2);

        vm.prank(alice);
        uint256 orderId = crystal.limitOrder(address(market), true, 0, price, size, alice);

        OrderAndBalanceSnapshot memory beforeSnapshot = _snapshot(alice, price, orderId);
        uint24 newTakerFee = uint24(99_900 + (feeSeed % 80));
        uint24 newMakerRebate = uint24(99_900 + ((feeSeed / 97) % 80));

        vm.prank(CRYSTAL_GOVERNANCE);
        crystal.changeMarketParams(address(market), MARKET_MIN_SIZE, newTakerFee, newMakerRebate, true, false);

        OrderAndBalanceSnapshot memory afterSnapshot = _snapshot(alice, price, orderId);
        ICrystal.MarketInfo memory info = crystal.getMarket(address(market));

        assertEq(
            afterSnapshot.orderSize,
            beforeSnapshot.orderSize,
            "assert afterSnapshot.orderSize == beforeSnapshot.orderSize"
        );
        assertEq(
            afterSnapshot.totalQuote,
            beforeSnapshot.totalQuote,
            "assert afterSnapshot.totalQuote == beforeSnapshot.totalQuote"
        );
        assertEq(
            afterSnapshot.availableQuote,
            beforeSnapshot.availableQuote,
            "assert afterSnapshot.availableQuote == beforeSnapshot.availableQuote"
        );
        assertEq(
            afterSnapshot.lockedQuote,
            beforeSnapshot.lockedQuote,
            "assert afterSnapshot.lockedQuote == beforeSnapshot.lockedQuote"
        );
        assertEq(info.takerFee, newTakerFee, "assert info.takerFee == newTakerFee");
        assertEq(info.makerRebate, newMakerRebate, "assert info.makerRebate == newMakerRebate");
    }

    function testUnauthorizedGovernanceCallRevertsWithoutBalanceMutation() public {
        (uint256 totalQuoteBefore, uint256 availableQuoteBefore, uint256 lockedQuoteBefore) =
            crystal.getDepositedBalance(alice, address(quote));

        vm.prank(alice);
        vm.expectRevert();
        crystal.changeGov(alice);

        (uint256 totalQuoteAfter, uint256 availableQuoteAfter, uint256 lockedQuoteAfter) =
            crystal.getDepositedBalance(alice, address(quote));

        assertEq(totalQuoteAfter, totalQuoteBefore, "assert totalQuoteAfter == totalQuoteBefore");
        assertEq(availableQuoteAfter, availableQuoteBefore, "assert availableQuoteAfter == availableQuoteBefore");
        assertEq(lockedQuoteAfter, lockedQuoteBefore, "assert lockedQuoteAfter == lockedQuoteBefore");
        assertEq(crystal.gov(), CRYSTAL_GOVERNANCE, "assert crystal.gov() == CRYSTAL_GOVERNANCE");
    }

    function testFuzzClaimFeesTransfersExactlyAndClearsRewards(uint256 amountSeed) public {
        uint256 amount = bound(amountSeed, MARKET_MIN_SIZE, 10_000 * QUOTE_UNIT);
        address[] memory tokens = _tokens(address(quote));
        uint256[] memory amounts = _amounts(amount);
        quote.mint(address(this), amount);
        quote.approve(address(crystal), amount);
        crystal.addClaimableFee(alice, tokens, amounts);

        uint256 bobQuoteBefore = quote.balanceOf(bob);

        vm.prank(alice);
        uint256[] memory claimed = crystal.claimFees(bob, tokens);

        assertEq(claimed.length, 1, "assert claimed.length == 1");
        assertEq(claimed[0], amount, "assert claimed[0] == amount");
        assertEq(
            quote.balanceOf(bob), bobQuoteBefore + amount, "assert quote.balanceOf(bob) == bobQuoteBefore + amount"
        );
        assertEq(
            crystal.claimableRewards(address(quote), alice),
            0,
            "assert crystal.claimableRewards(address(quote), alice) == 0"
        );
    }

    function testExpiredFeeClaimsOnlyExecuteAfterDeadline() public {
        uint256 amount = 1_000 * QUOTE_UNIT;
        address[] memory tokens = _tokens(address(quote));
        uint256[] memory amounts = _amounts(amount);
        quote.mint(address(this), amount);
        quote.approve(address(crystal), amount);
        crystal.addClaimableFee(alice, tokens, amounts);

        vm.prank(CRYSTAL_GOVERNANCE);
        crystal.queueClaimExpiredFees(alice, tokens);

        vm.prank(CRYSTAL_GOVERNANCE);
        vm.expectRevert();
        crystal.executeClaimExpiredFees(alice);

        vm.warp(block.timestamp + FEE_CLAIM_DURATION + 1);
        vm.prank(CRYSTAL_GOVERNANCE);
        uint256[] memory claimed = crystal.executeClaimExpiredFees(alice);

        assertEq(claimed.length, 1, "assert claimed.length == 1");
        assertEq(claimed[0], amount, "assert claimed[0] == amount");
        assertEq(
            crystal.claimableRewards(address(quote), alice),
            0,
            "assert crystal.claimableRewards(address(quote), alice) == 0"
        );
    }

    function _snapshot(address user, uint256 price, uint256 orderId)
        private
        view
        returns (OrderAndBalanceSnapshot memory snapshot)
    {
        ICrystal.Order memory order = crystal.getOrder(address(market), price, orderId);
        snapshot.orderSize = order.size;
        (snapshot.totalQuote, snapshot.availableQuote, snapshot.lockedQuote) =
            crystal.getDepositedBalance(user, address(quote));
        (snapshot.totalBase, snapshot.availableBase, snapshot.lockedBase) =
            crystal.getDepositedBalance(user, address(weth));
    }

    function _boundAskSize(uint256 seed, uint256 price) private view returns (uint256) {
        return bound(seed, _minBaseForQuote(MARKET_MIN_SIZE * 8, price), 100 ether);
    }

    function _quoteValue(uint256 baseSize, uint256 price) private view returns (uint256) {
        return (baseSize * price) / market.scaleFactor();
    }

    function _tokens(address token) private pure returns (address[] memory tokens) {
        tokens = new address[](1);
        tokens[0] = token;
    }

    function _amounts(uint256 amount) private pure returns (uint256[] memory amounts) {
        amounts = new uint256[](1);
        amounts[0] = amount;
    }
}
