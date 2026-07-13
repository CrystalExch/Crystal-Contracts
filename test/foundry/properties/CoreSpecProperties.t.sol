// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ICrystal } from "../../../contracts/interfaces/ICrystal.sol";
import { BaseFuzzTest } from "../BaseFuzzTest.t.sol";

contract CoreSpecProperties is BaseFuzzTest {
    uint256 private constant MAX_FUNDED_ASK_SIZE = 100 ether;

    struct QuoteBalanceSnapshot {
        uint256 walletQuote;
        uint256 totalQuote;
        uint256 availableQuote;
        uint256 lockedQuote;
    }

    function setUp() public override {
        super.setUp();
        _registerAndDeposit(carol);
    }

    function testFuzzUserBuyLimitLocksQuoteWithoutChangingTotalBalance(uint256 quotePerBaseSeed, uint256 sizeSeed)
        public
    {
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 size = bound(sizeSeed, MARKET_MIN_SIZE * 2, DEPOSIT_QUOTE_AMOUNT / 2);
        QuoteBalanceSnapshot memory beforeSnapshot = _quoteSnapshot(alice);
        _executeInternalLimitOrder(alice, BatchAction.BuyLimit, price, size);

        QuoteBalanceSnapshot memory afterSnapshot = _quoteSnapshot(alice);

        assertEq(
            afterSnapshot.walletQuote,
            beforeSnapshot.walletQuote,
            "assert afterSnapshot.walletQuote == beforeSnapshot.walletQuote"
        );
        assertEq(
            afterSnapshot.totalQuote,
            beforeSnapshot.totalQuote,
            "assert afterSnapshot.totalQuote == beforeSnapshot.totalQuote"
        );
        assertEq(
            afterSnapshot.availableQuote,
            beforeSnapshot.availableQuote - size,
            "assert afterSnapshot.availableQuote == beforeSnapshot.availableQuote - size"
        );
        assertEq(
            afterSnapshot.lockedQuote,
            beforeSnapshot.lockedQuote + size,
            "assert afterSnapshot.lockedQuote == beforeSnapshot.lockedQuote + size"
        );
    }

    function testFuzzUserSellLimitLocksBaseWithoutChangingTotalBalance(uint256 quotePerBaseSeed, uint256 sizeSeed)
        public
    {
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 size = _boundAskSize(sizeSeed, price);
        (uint256 totalBaseBefore, uint256 availableBaseBefore, uint256 lockedBaseBefore) =
            crystal.getDepositedBalance(alice, address(weth));
        _executeInternalLimitOrder(alice, BatchAction.SellLimit, price, size);

        (uint256 totalBaseAfter, uint256 availableBaseAfter, uint256 lockedBaseAfter) =
            crystal.getDepositedBalance(alice, address(weth));

        assertEq(totalBaseAfter, totalBaseBefore, "assert totalBaseAfter == totalBaseBefore");
        assertEq(
            availableBaseAfter, availableBaseBefore - size, "assert availableBaseAfter == availableBaseBefore - size"
        );
        assertEq(lockedBaseAfter, lockedBaseBefore + size, "assert lockedBaseAfter == lockedBaseBefore + size");
    }

    function testFuzzWithdrawCannotSpendLockedQuote(
        uint256 quotePerBaseSeed,
        uint256 sizeSeed,
        uint256 extraWithdrawSeed
    ) public {
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 size = bound(sizeSeed, MARKET_MIN_SIZE * 2, DEPOSIT_QUOTE_AMOUNT / 2);
        _executeInternalLimitOrder(alice, BatchAction.BuyLimit, price, size);

        QuoteBalanceSnapshot memory beforeSnapshot = _quoteSnapshot(alice);
        assertGt(beforeSnapshot.lockedQuote, 0, "assert beforeSnapshot.lockedQuote > 0");
        uint256 extra = bound(extraWithdrawSeed, 1, beforeSnapshot.lockedQuote);

        vm.prank(alice);
        vm.expectRevert();
        crystal.withdraw(alice, address(quote), beforeSnapshot.availableQuote + extra);

        _assertQuoteSnapshot(alice, beforeSnapshot);
    }

    function testFuzzGetQuotePredictsMarketBuyAndDoesNotMutate(
        uint256 quotePerBaseSeed,
        uint256 askSizeSeed,
        uint256 quoteInSeed
    ) public {
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 askSize = _boundAskSize(askSizeSeed, price);
        uint256 askQuoteValue = _quoteValue(askSize, price);
        uint256 quoteIn = bound(quoteInSeed, MARKET_MIN_SIZE, askQuoteValue / 2);

        vm.prank(alice);
        crystal.limitOrder(address(market), false, 0, price, askSize, alice);

        QuoteBalanceSnapshot memory aliceBeforeQuote = _quoteSnapshot(alice);
        QuoteBalanceSnapshot memory bobBeforeQuote = _quoteSnapshot(bob);
        ICrystal.PriceLevel memory levelBeforeQuote = crystal.getPriceLevel(address(market), price);

        (uint256 quotedIn, uint256 quotedOut) = crystal.getQuote(address(market), true, true, false, quoteIn, price);

        ICrystal.PriceLevel memory levelAfterQuote = crystal.getPriceLevel(address(market), price);
        assertLe(_absDiff(quotedIn, quoteIn), 1, "assert abs(quotedIn - quoteIn) <= 1");
        assertEq(levelAfterQuote.size, levelBeforeQuote.size, "assert levelAfterQuote.size == levelBeforeQuote.size");
        _assertQuoteSnapshot(alice, aliceBeforeQuote);
        _assertQuoteSnapshot(bob, bobBeforeQuote);

        _assertMarketBuyMatchesQuote(quoteIn, price, quotedIn, quotedOut);
    }

    function testFuzzCloidCanBeReusedAfterCompleteFill(uint256 quotePerBaseSeed, uint256 askSizeSeed) public {
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 askSize = _boundAskSize(askSizeSeed, price);
        uint256 cloid = 7;

        vm.prank(alice);
        crystal.limitOrder(address(market), false, cloid << 44, price, askSize, alice);

        vm.prank(bob);
        (, uint256 amountOut,) =
            crystal.marketOrder(address(market), true, false, 0, ORDER_TYPES_NORMAL, askSize, price, address(0), bob);

        ICrystal.Order memory filledOrder = crystal.getOrderByCloid(crystal.addressToUserId(alice), cloid);
        uint256 newAskSize = askSize / 2;

        vm.prank(alice);
        crystal.limitOrder(address(market), false, cloid << 44, price, newAskSize, alice);

        ICrystal.Order memory reusedOrder = crystal.getOrderByCloid(crystal.addressToUserId(alice), cloid);

        assertEq(amountOut, askSize, "assert amountOut == askSize");
        assertEq(filledOrder.size, 0, "assert filledOrder.size == 0");
        assertEq(reusedOrder.size, newAskSize, "assert reusedOrder.size == newAskSize");
        assertEq(reusedOrder.price, price, "assert reusedOrder.price == price");
    }

    function testFuzzAmmFillsBeforeWorseBookAsk(uint256 askSizeSeed, uint256 quoteInSeed) public {
        uint256 ammQuote = 300_000 * QUOTE_UNIT;
        uint256 ammBase = 300 ether;
        uint256 bookPrice = _price(2_000);
        uint256 askSize = _boundAskSize(askSizeSeed, bookPrice);
        uint256 quoteIn = bound(quoteInSeed, MARKET_MIN_SIZE, 10_000 * QUOTE_UNIT);

        crystal.addLiquidity(address(market), address(this), ammQuote, ammBase, 0, 0);

        vm.prank(alice);
        crystal.limitOrder(address(market), false, 0, bookPrice, askSize, alice);

        (uint112 reserveQuoteBefore, uint112 reserveBaseBefore) = crystal.getReserves(address(market));

        vm.prank(bob);
        crystal.marketOrder(
            address(market), true, true, 0, ORDER_TYPES_NORMAL, quoteIn, MARKET_MAX_PRICE, address(0), bob
        );

        (uint112 reserveQuoteAfter, uint112 reserveBaseAfter) = crystal.getReserves(address(market));
        ICrystal.PriceLevel memory levelAfter = crystal.getPriceLevel(address(market), bookPrice);

        assertEq(levelAfter.size, askSize, "assert levelAfter.size == askSize");
        assertGt(reserveQuoteAfter, reserveQuoteBefore, "assert reserveQuoteAfter > reserveQuoteBefore");
        assertLt(reserveBaseAfter, reserveBaseBefore, "assert reserveBaseAfter < reserveBaseBefore");
    }

    function testFuzzAmmReserveViewsAgreeAfterAddSwapRemove(uint256 quoteSeed, uint256 baseSeed, uint256 swapSeed)
        public
    {
        quoteSeed;
        baseSeed;
        uint256 amountQuote = 300_000 * QUOTE_UNIT;
        uint256 amountBase = 300 ether;
        uint256 liquidity = crystal.addLiquidity(address(market), address(this), amountQuote, amountBase, 0, 0);
        _assertReserveViewsAgree();

        uint256 amountIn = bound(swapSeed, MARKET_MIN_SIZE * 10, amountQuote / 20);
        address[] memory path = _path(address(quote), address(weth));
        (uint256[] memory amountsOut, bool isPartialFill) = crystal.getAmountsOut(amountIn, path);
        if (isPartialFill) {
            return;
        }
        assertGt(amountsOut[1], 0, "assert amountsOut[1] > 0");
        crystal.swapExactTokensForTokens(amountIn, 0, path, address(this), block.timestamp, address(0));
        _assertReserveViewsAgree();

        crystal.removeLiquidity(address(market), address(this), liquidity / 2, 0, 0);
        _assertReserveViewsAgree();
    }

    function testFuzzRouterQuoteMatchesDirectMarketQuoteAndDoesNotMutate(uint256 quoteSeed) public {
        crystal.addLiquidity(address(market), address(this), 300_000 * QUOTE_UNIT, 300 ether, 0, 0);
        uint256 amountIn = bound(quoteSeed, MARKET_MIN_SIZE, 10_000 * QUOTE_UNIT);
        address[] memory path = _path(address(quote), address(weth));
        (uint112 reserveQuoteBefore, uint112 reserveBaseBefore) = crystal.getReserves(address(market));

        (uint256 directIn, uint256 directOut) =
            crystal.getQuote(address(market), true, true, false, amountIn, MARKET_MAX_PRICE);
        (uint256[] memory amountsOut, bool isPartialFill) = crystal.getAmountsOut(amountIn, path);

        (uint112 reserveQuoteAfter, uint112 reserveBaseAfter) = crystal.getReserves(address(market));

        assertLe(_absDiff(directIn, amountIn), 1, "assert abs(directIn - amountIn) <= 1");
        assertEq(amountsOut[0], amountIn, "assert amountsOut[0] == amountIn");
        if (!isPartialFill) {
            assertEq(amountsOut[1], directOut, "assert amountsOut[1] == directOut");
        }
        assertEq(reserveQuoteAfter, reserveQuoteBefore, "assert reserveQuoteAfter == reserveQuoteBefore");
        assertEq(reserveBaseAfter, reserveBaseBefore, "assert reserveBaseAfter == reserveBaseBefore");
    }

    function testFuzzInvalidRouterPathRevertsWithoutChangingReserves(uint256 amountSeed) public {
        uint256 amountIn = _boundQuoteAmount(amountSeed);
        address[] memory invalidPath = new address[](1);
        invalidPath[0] = address(quote);
        (uint112 reserveQuoteBefore, uint112 reserveBaseBefore) = crystal.getReserves(address(market));

        vm.expectRevert();
        crystal.swapExactTokensForTokens(amountIn, 0, invalidPath, alice, block.timestamp, address(0));

        (uint112 reserveQuoteAfter, uint112 reserveBaseAfter) = crystal.getReserves(address(market));

        assertEq(reserveQuoteAfter, reserveQuoteBefore, "assert reserveQuoteAfter == reserveQuoteBefore");
        assertEq(reserveBaseAfter, reserveBaseBefore, "assert reserveBaseAfter == reserveBaseBefore");
    }

    function _assertReserveViewsAgree() private {
        (uint112 reserveQuote, uint112 reserveBase) = crystal.getReserves(address(market));
        ICrystal.MarketInfo memory info = crystal.getMarket(address(market));

        assertEq(uint256(reserveQuote), info.reserveQuote, "assert reserveQuote == info.reserveQuote");
        assertEq(uint256(reserveBase), info.reserveBase, "assert reserveBase == info.reserveBase");
    }

    function _singleAction(BatchAction action, uint256 param1, uint256 param2, uint256 param3)
        private
        pure
        returns (ICrystal.Action[] memory actions)
    {
        actions = new ICrystal.Action[](1);
        actions[0] = ICrystal.Action({
            isRequireSuccess: true, action: uint256(action), param1: param1, param2: param2, param3: param3
        });
    }

    function _executeInternalLimitOrder(address user, BatchAction action, uint256 price, uint256 size) private {
        _executeFallbackAs(
            user,
            abi.encodePacked(_batchHeader(BATCH_BALANCE_MODE_INTERNAL, 1), _limitAction(action, true, 0, price, size))
        );
    }

    function _batchHeader(uint256 balanceMode, uint256 actionCount) private view returns (bytes32) {
        return bytes32(
            (balanceMode << BATCH_BALANCE_MODE_SHIFT) | (actionCount << BATCH_ACTION_COUNT_SHIFT)
                | uint160(address(market))
        );
    }

    function _limitAction(BatchAction action, bool requireSuccess, uint256 cloid, uint256 price, uint256 size)
        private
        pure
        returns (bytes32)
    {
        return bytes32(
            (uint256(action) << BATCH_ACTION_SHIFT) | (requireSuccess ? (uint256(1) << BATCH_REQUIRE_SUCCESS_SHIFT) : 0)
                | ((cloid & BATCH_CLOID_MASK) << BATCH_CLOID_SHIFT)
                | ((price & BATCH_PARAM1_MASK) << BATCH_PARAM1_SHIFT) | (size & BATCH_PARAM2_MASK)
        );
    }

    function _executeFallbackAs(address caller, bytes memory data) private {
        vm.prank(caller);
        (bool success, bytes memory returnData) = address(crystal).call(data);
        if (!success) {
            assembly {
                revert(add(returnData, 32), mload(returnData))
            }
        }
    }

    function _assertMarketBuyMatchesQuote(uint256 quoteIn, uint256 price, uint256 quotedIn, uint256 quotedOut) private {
        vm.prank(bob);
        (uint256 amountIn, uint256 amountOut,) =
            crystal.marketOrder(address(market), true, true, 0, ORDER_TYPES_NORMAL, quoteIn, price, address(0), bob);

        assertEq(amountIn, quotedIn, "assert amountIn == quotedIn");
        assertEq(amountOut, quotedOut, "assert amountOut == quotedOut");
    }

    function _quoteSnapshot(address user) private view returns (QuoteBalanceSnapshot memory snapshot) {
        snapshot.walletQuote = quote.balanceOf(user);
        (snapshot.totalQuote, snapshot.availableQuote, snapshot.lockedQuote) =
            crystal.getDepositedBalance(user, address(quote));
    }

    function _assertQuoteSnapshot(address user, QuoteBalanceSnapshot memory expected) private view {
        QuoteBalanceSnapshot memory actual = _quoteSnapshot(user);

        assertEq(actual.walletQuote, expected.walletQuote, "assert actual.walletQuote == expected.walletQuote");
        assertEq(actual.totalQuote, expected.totalQuote, "assert actual.totalQuote == expected.totalQuote");
        assertEq(
            actual.availableQuote, expected.availableQuote, "assert actual.availableQuote == expected.availableQuote"
        );
        assertEq(actual.lockedQuote, expected.lockedQuote, "assert actual.lockedQuote == expected.lockedQuote");
    }

    function _boundAskSize(uint256 seed, uint256 price) private view returns (uint256) {
        return bound(seed, _minBaseForQuote(MARKET_MIN_SIZE * 8, price), MAX_FUNDED_ASK_SIZE);
    }

    function _quoteValue(uint256 baseSize, uint256 price) private view returns (uint256) {
        return (baseSize * price) / market.scaleFactor();
    }

    function _path(address tokenIn, address tokenOut) private pure returns (address[] memory path) {
        path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
    }

    function _absDiff(uint256 a, uint256 b) private pure returns (uint256) {
        return a > b ? a - b : b - a;
    }
}
