// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Asserts } from "@chimera/Asserts.sol";

import { ICrystal } from "../../../contracts/interfaces/ICrystal.sol";
import { ICrystalVault } from "../../../contracts/interfaces/ICrystalVault.sol";
import { IERC20 } from "../../../contracts/interfaces/IERC20.sol";
import { BeforeAfter } from "./BeforeAfter.sol";

abstract contract Properties is BeforeAfter, Asserts {
    uint256 private constant PRICE_LEVEL_SIZE_OFFSET = 2 ** 128;

    function invariant_governance_tracking() public {
        t(crystal.gov() == currentGovernance, "assert crystal.gov() == currentGovernance");
    }

    function invariant_registered_actor_mapping() public {
        address[] memory suiteActors = _actors();
        for (uint256 i = 0; i < suiteActors.length; i++) {
            uint256 userId = crystal.addressToUserId(suiteActors[i]);
            if (userId == 0) {
                continue;
            }
            t(
                crystal.userIdToAddress(userId) == suiteActors[i],
                "assert crystal.userIdToAddress(userId) == suiteActors[i]"
            );
            gte(crystal.latestUserId(), userId, "assert crystal.latestUserId() >= userId");
        }
    }

    function invariant_user_internal_balances() public {
        address[] memory suiteActors = _actors();
        for (uint256 i = 0; i < suiteActors.length; i++) {
            _assertInternalBalanceTuple(suiteActors[i], address(quote));
            _assertInternalBalanceTuple(suiteActors[i], address(weth));
        }
    }

    function invariant_market_reserve_views() public {
        (uint112 reserveQuote, uint112 reserveBase) = crystal.getReserves(address(market));
        ICrystal.MarketInfo memory info = crystal.getMarket(address(market));

        eq(uint256(reserveQuote), info.reserveQuote, "assert reserveQuote == info.reserveQuote");
        eq(uint256(reserveBase), info.reserveBase, "assert reserveBase == info.reserveBase");
        lte(
            uint256(reserveQuote),
            quote.balanceOf(address(crystal)),
            "assert reserveQuote <= quote.balanceOf(address(crystal))"
        );
        lte(
            uint256(reserveBase),
            weth.balanceOf(address(crystal)),
            "assert reserveBase <= weth.balanceOf(address(crystal))"
        );
        lte(info.highestBid, MARKET_MAX_PRICE, "assert info.highestBid <= MARKET_MAX_PRICE");
        lte(info.lowestAsk, MARKET_MAX_PRICE, "assert info.lowestAsk <= MARKET_MAX_PRICE");
    }

    function invariant_primary_book_spread_validity() public {
        ICrystal.MarketInfo memory info = crystal.getMarket(address(market));

        if (info.highestBid != 0 && info.lowestAsk != 0) {
            lt(info.highestBid, info.lowestAsk, "assert info.highestBid < info.lowestAsk");
        }
    }

    function invariant_market_index_views() public {
        uint256 marketCount = crystal.allMarketsLength();
        gt(marketCount, 0, "assert marketCount > 0");

        if (marketCount > 0) {
            address firstMarket = crystal.allMarkets(0);
            t(firstMarket != address(0), "assert firstMarket != address(0)");
        }

        ICrystal.MarketInfo memory info = crystal.getMarket(address(market));
        t(info.quoteAsset == address(quote), "assert info.quoteAsset == address(quote)");
        t(info.baseAsset == address(weth), "assert info.baseAsset == address(weth)");
        eq(info.scaleFactor, MARKET_SCALE_FACTOR, "assert info.scaleFactor == MARKET_SCALE_FACTOR");
        eq(info.tickSize, MARKET_TICK_SIZE, "assert info.tickSize == MARKET_TICK_SIZE");
        eq(info.maxPrice, MARKET_MAX_PRICE, "assert info.maxPrice == MARKET_MAX_PRICE");

        crystal.getMarketByTokens(address(quote), address(weth));
        crystal.parameters();
    }

    function invariant_price_ladder_views() public {
        address routedMarket = crystal.getMarketByTokens(address(quote), address(weth));
        if (routedMarket != address(market)) {
            return;
        }

        (uint112 reserveQuote, uint112 reserveBase) = crystal.getReserves(address(market));
        if ((reserveQuote == 0) != (reserveBase == 0)) {
            return;
        }

        (uint256 midPrice, uint256 highestBid, uint256 lowestAsk) = crystal.getPrice(address(market));
        lte(midPrice, MARKET_MAX_PRICE, "assert midPrice <= MARKET_MAX_PRICE");
        lte(highestBid, MARKET_MAX_PRICE, "assert highestBid <= MARKET_MAX_PRICE");
        lte(lowestAsk, MARKET_MAX_PRICE, "assert lowestAsk <= MARKET_MAX_PRICE");

        ICrystal.MarketInfo memory info = crystal.getMarket(address(market));
        gte(highestBid, info.highestBid, "assert highestBid >= info.highestBid");
        if (info.lowestAsk != 0 && lowestAsk != 0) {
            lte(lowestAsk, info.lowestAsk, "assert lowestAsk <= info.lowestAsk");
        }

        uint256 startPrice = _price(200);
        uint256 endPrice = _price(1_300);
        uint256 distance = 8_000;
        bytes memory ascendingLevels =
            crystal.getPriceLevels(address(market), true, startPrice, distance, MARKET_TICK_SIZE, 8);
        bytes memory descendingLevels =
            crystal.getPriceLevels(address(market), false, endPrice, distance, MARKET_TICK_SIZE, 8);
        _assertEncodedLevels(ascendingLevels, true, 8);
        _assertEncodedLevels(descendingLevels, false, 8);

        (uint256 midBid, uint256 midAsk, bytes memory bidLevels, bytes memory askLevels) =
            crystal.getPriceLevelsFromMid(address(market), distance, MARKET_TICK_SIZE, 8);
        lte(midBid, MARKET_MAX_PRICE, "assert midBid <= MARKET_MAX_PRICE");
        lte(midAsk, MARKET_MAX_PRICE, "assert midAsk <= MARKET_MAX_PRICE");
        _assertEncodedLevels(bidLevels, false, 8);
        _assertEncodedLevels(askLevels, true, 8);
    }

    function invariant_quote_views_match_paths() public {
        (uint112 reserveQuote, uint112 reserveBase) = crystal.getReserves(address(market));
        if (reserveQuote == 0 || reserveBase == 0) {
            return;
        }

        address routedMarket = crystal.getMarketByTokens(address(quote), address(weth));
        if (routedMarket != address(market)) {
            return;
        }

        address[] memory quoteToBase = _path(address(quote), address(weth));
        uint256 quoteIn = _min(MARKET_MIN_SIZE * 2, uint256(reserveQuote) / 1_000);
        if (quoteIn >= MARKET_MIN_SIZE) {
            try crystal.getQuote(address(market), true, true, false, quoteIn, 0) returns (uint256, uint256) { }
            catch {
                return;
            }

            uint256[] memory amountsOut;
            try crystal.getAmountsOut(quoteIn, quoteToBase) returns (
                uint256[] memory quotedAmountsOut,
                bool
            ) {
                amountsOut = quotedAmountsOut;
            } catch {
                return;
            }
            eq(amountsOut.length, 2, "assert amountsOut.length == 2");
            eq(amountsOut[0], quoteIn, "assert amountsOut[0] == quoteIn");
        }

        uint256 baseOut = _min(1 gwei, uint256(reserveBase) / 1_000);
        if (baseOut > 0) {
            try crystal.getQuote(address(market), true, false, true, baseOut, 0) returns (uint256, uint256) { }
            catch {
                return;
            }

            uint256[] memory amountsIn;
            try crystal.getAmountsIn(baseOut, quoteToBase) returns (uint256[] memory quotedAmountsIn) {
                amountsIn = quotedAmountsIn;
            } catch {
                return;
            }
            eq(amountsIn.length, 2, "assert amountsIn.length == 2");
        }
    }

    function invariant_quote_views_do_not_mutate_and_match_paths() public {
        (uint112 reserveQuoteBefore, uint112 reserveBaseBefore) = crystal.getReserves(address(market));
        address routedMarket = crystal.getMarketByTokens(address(quote), address(weth));
        if (routedMarket == address(0)) {
            return;
        }

        ICrystal.MarketInfo memory routedInfo = crystal.getMarket(routedMarket);
        (uint112 routedReserveQuoteBefore, uint112 routedReserveBaseBefore) = crystal.getReserves(routedMarket);
        if (routedReserveQuoteBefore == 0 || routedReserveBaseBefore == 0) {
            return;
        }

        address[] memory quoteToBase = _path(address(quote), address(weth));
        uint256 quoteIn = _min(routedInfo.minSize * 2, uint256(routedReserveQuoteBefore) / 1_000);
        if (quoteIn >= routedInfo.minSize) {
            _assertExactInputQuotePathParity(routedMarket, quoteIn, quoteToBase, routedInfo.maxPrice);
        }

        uint256 baseOut = _min(1 gwei, uint256(routedReserveBaseBefore) / 1_000);
        if (baseOut > 0) {
            _assertExactOutputQuotePathParity(routedMarket, baseOut, quoteToBase, routedInfo.maxPrice);
        }

        (uint112 reserveQuoteAfter, uint112 reserveBaseAfter) = crystal.getReserves(address(market));
        (uint112 routedReserveQuoteAfter, uint112 routedReserveBaseAfter) = crystal.getReserves(routedMarket);
        eq(reserveQuoteAfter, reserveQuoteBefore, "assert reserveQuoteAfter == reserveQuoteBefore");
        eq(reserveBaseAfter, reserveBaseBefore, "assert reserveBaseAfter == reserveBaseBefore");
        eq(
            routedReserveQuoteAfter,
            routedReserveQuoteBefore,
            "assert routedReserveQuoteAfter == routedReserveQuoteBefore"
        );
        eq(routedReserveBaseAfter, routedReserveBaseBefore, "assert routedReserveBaseAfter == routedReserveBaseBefore");
    }

    function invariant_tracked_orders_match_storage() public {
        for (uint256 i = 0; i < trackedOrders.length; i++) {
            if (!trackedOrders[i].live) {
                continue;
            }

            ICrystal.Order memory order = crystal.getOrder(address(market), trackedOrders[i].price, trackedOrders[i].id);
            if (order.size == 0) {
                continue;
            }

            t(order.market == address(market), "assert order.market == address(market)");
            eq(order.price, trackedOrders[i].price, "assert order.price == trackedOrders[i].price");
            eq(
                order.userId,
                crystal.addressToUserId(trackedOrders[i].owner),
                "assert order.userId == crystal.addressToUserId(trackedOrders[i].owner)"
            );
            t(order.isBuy == trackedOrders[i].isBuy, "assert order.isBuy == trackedOrders[i].isBuy");

            ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), trackedOrders[i].price);
            gte(level.size, order.size, "assert level.size >= order.size");
        }
    }

    function invariant_tracked_orders_respect_market_bounds() public {
        ICrystal.MarketInfo memory info = crystal.getMarket(address(market));
        for (uint256 i = 0; i < trackedOrders.length; i++) {
            if (!trackedOrders[i].live) {
                continue;
            }

            ICrystal.Order memory order = crystal.getOrder(address(market), trackedOrders[i].price, trackedOrders[i].id);
            if (order.size == 0) {
                continue;
            }

            gt(order.price, 0, "assert order.price > 0");
            lt(order.price, info.maxPrice, "assert order.price < info.maxPrice");
            eq(order.price % info.tickSize, 0, "assert order.price % info.tickSize == 0");
        }
    }

    function invariant_cloid_views_match_storage() public {
        address[] memory suiteActors = _actors();
        for (uint256 i = 0; i < suiteActors.length; i++) {
            uint256 userId = crystal.addressToUserId(suiteActors[i]);
            if (userId == 0) {
                continue;
            }

            (uint256[] memory cloids, ICrystal.Order[] memory orders) = crystal.getAllOrdersByCloid(suiteActors[i], 128);
            eq(cloids.length, orders.length, "assert cloids.length == orders.length");

            uint256 maxOrders = cloids.length < 4 ? cloids.length : 4;
            for (uint256 j = 0; j < maxOrders; j++) {
                ICrystal.Order memory byCloid = crystal.getOrderByCloid(userId, cloids[j]);
                eq(byCloid.userId, orders[j].userId, "assert byCloid.userId == orders[j].userId");
                eq(byCloid.price, orders[j].price, "assert byCloid.price == orders[j].price");
                eq(byCloid.size, orders[j].size, "assert byCloid.size == orders[j].size");
                t(byCloid.isBuy == orders[j].isBuy, "assert byCloid.isBuy == orders[j].isBuy");
            }

            for (uint256 cloid = 1; cloid <= 4; cloid++) {
                ICrystal.Order memory order = crystal.getOrderByCloid(userId, cloid);
                if (order.size != 0) {
                    eq(order.userId, userId, "assert order.userId == userId");
                    t(order.market == address(market), "assert order.market == address(market)");
                }
            }
        }
    }

    function invariant_vault_accounting() public {
        for (uint256 i = 0; i < trackedVaults.length; i++) {
            ICrystalVault vault = ICrystalVault(trackedVaults[i]);
            (,,, uint256 totalShares,,,, bool factoryLocked, bool factoryClosed,) =
                vaultFactory.getVault(trackedVaults[i]);
            (uint256 quoteBalance, uint256 baseBalance, uint256 availableQuote, uint256 availableBase) =
                vault.getBalances();
            (uint256 crystalQuote, uint256 crystalQuoteAvailable,) =
                crystal.getDepositedBalance(trackedVaults[i], address(quote));
            (uint256 crystalBase, uint256 crystalBaseAvailable,) =
                crystal.getDepositedBalance(trackedVaults[i], address(weth));

            eq(vault.totalSupply(), totalShares, "assert vault.totalSupply() == totalShares");
            eq(quoteBalance, crystalQuote, "assert quoteBalance == crystalQuote");
            eq(baseBalance, crystalBase, "assert baseBalance == crystalBase");
            lte(availableQuote, quoteBalance, "assert availableQuote <= quoteBalance");
            lte(availableBase, baseBalance, "assert availableBase <= baseBalance");
            lte(crystalQuoteAvailable, crystalQuote, "assert crystalQuoteAvailable <= crystalQuote");
            lte(crystalBaseAvailable, crystalBase, "assert crystalBaseAvailable <= crystalBase");
            t(vault.locked() == factoryLocked, "assert vault.locked() == factoryLocked");
            t(vault.closed() == factoryClosed, "assert vault.closed() == factoryClosed");
        }
    }

    function invariant_vault_risk_bounds() public {
        uint16 maxOrderCap = vaultFactory.maxOrderCap();
        uint40 maxLockup = vaultFactory.maxLockup();

        for (uint256 i = 0; i < trackedVaults.length; i++) {
            ICrystalVault vault = ICrystalVault(trackedVaults[i]);

            lte(vault.orderCap(), maxOrderCap, "assert vault.orderCap() <= maxOrderCap");
            lte(vault.lockup(), maxLockup, "assert vault.lockup() <= maxLockup");
        }
    }

    function invariant_claimable_rewards_are_backed() public {
        address[] memory suiteActors = _actors();
        uint256 totalQuoteRewards;
        uint256 totalWethRewards;
        uint256 totalNativeRewards;

        for (uint256 i = 0; i < suiteActors.length; i++) {
            totalQuoteRewards += crystal.claimableRewards(address(quote), suiteActors[i]);
            totalWethRewards += crystal.claimableRewards(address(weth), suiteActors[i]);
            totalNativeRewards += crystal.claimableRewards(crystal.eth(), suiteActors[i]);
        }

        lte(
            totalQuoteRewards,
            quote.balanceOf(address(crystal)),
            "assert totalQuoteRewards <= quote.balanceOf(address(crystal))"
        );
        lte(
            totalWethRewards,
            weth.balanceOf(address(crystal)),
            "assert totalWethRewards <= weth.balanceOf(address(crystal))"
        );
        lte(totalNativeRewards, address(crystal).balance, "assert totalNativeRewards <= address(crystal).balance");
    }

    function invariant_launchpad_constant_product_metadata() public {
        for (uint256 i = 0; i < trackedLaunchpadTokens.length; i++) {
            (
                uint112 virtualNativeReserve,
                uint112 virtualTokenReserve,
                uint256 k,
                address creator,
                address marketAddress
            ) = crystal.launchpadTokenToMarket(trackedLaunchpadTokens[i]);

            if (virtualNativeReserve == 0 || virtualTokenReserve == 0) {
                eq(uint256(virtualNativeReserve), 0, "assert virtualNativeReserve == 0");
                eq(uint256(virtualTokenReserve), 0, "assert virtualTokenReserve == 0");
                continue;
            }

            gt(uint256(virtualNativeReserve), 0, "assert virtualNativeReserve > 0");
            gt(uint256(virtualTokenReserve), 0, "assert virtualTokenReserve > 0");
            gte(
                uint256(virtualNativeReserve) * uint256(virtualTokenReserve),
                k,
                "assert uint256(virtualNativeReserve) * uint256(virtualTokenReserve) >= k"
            );
            t(creator != address(0), "assert creator != address(0)");
            t(marketAddress != address(0), "assert marketAddress != address(0)");
        }
    }

    function invariant_launchpad_quote_and_token_metadata() public {
        for (uint256 i = 0; i < trackedLaunchpadTokens.length; i++) {
            address token = trackedLaunchpadTokens[i];
            IERC20 launchpadToken = IERC20(token);

            gt(bytes(launchpadToken.name()).length, 0, "assert bytes(launchpadToken.name()).length > 0");
            gt(bytes(launchpadToken.symbol()).length, 0, "assert bytes(launchpadToken.symbol()).length > 0");
            eq(uint256(launchpadToken.decimals()), 18, "assert launchpadToken.decimals() == 18");
            gt(launchpadToken.totalSupply(), 0, "assert launchpadToken.totalSupply() > 0");
            lte(
                launchpadToken.balanceOf(address(crystal)),
                launchpadToken.totalSupply(),
                "assert launchpadToken.balanceOf(address(crystal)) <= launchpadToken.totalSupply()"
            );

            (uint256 virtualNativeReserve, uint256 virtualTokenReserve) = crystal.getVirtualReserves(token);
            if (virtualNativeReserve == 0 || virtualTokenReserve == 0) {
                continue;
            }

            uint256 nativeIn = _min(1 gwei, virtualNativeReserve / 1_000);
            if (nativeIn > 0) {
                (uint256 buyIn, uint256 buyOut,) = crystal.quoteBuy(true, token, nativeIn, 0);
                eq(buyIn, nativeIn, "assert buyIn == nativeIn");
                lte(buyOut, virtualTokenReserve, "assert buyOut <= virtualTokenReserve");

                if (buyOut > 1) {
                    (uint256 exactBuyIn, uint256 exactBuyOut,) = crystal.quoteBuy(false, token, 0, buyOut / 2);
                    gt(exactBuyIn, 0, "assert exactBuyIn > 0");
                    eq(exactBuyOut, buyOut / 2, "assert exactBuyOut == buyOut / 2");
                }
            }

            uint256 tokenIn = _min(1 ether, virtualTokenReserve / 1_000);
            if (tokenIn > 0) {
                (uint256 sellIn, uint256 sellOut) = crystal.quoteSell(true, token, tokenIn, 0);
                eq(sellIn, tokenIn, "assert sellIn == tokenIn");
                lte(sellOut, virtualNativeReserve, "assert sellOut <= virtualNativeReserve");

                if (sellOut > 1) {
                    (uint256 exactSellIn, uint256 exactSellOut) = crystal.quoteSell(false, token, 0, sellOut / 2);
                    gt(exactSellIn, 0, "assert exactSellIn > 0");
                    eq(exactSellOut, sellOut / 2, "assert exactSellOut == sellOut / 2");
                }
            }
        }
    }

    function invariant_launchpad_quote_views_do_not_mutate() public {
        for (uint256 i = 0; i < trackedLaunchpadTokens.length; i++) {
            address token = trackedLaunchpadTokens[i];
            (uint256 nativeBefore, uint256 tokenBefore) = crystal.getVirtualReserves(token);
            if (nativeBefore == 0 || tokenBefore == 0) {
                continue;
            }

            uint256 nativeIn = _min(1 gwei, nativeBefore / 1_000);
            if (nativeIn > 0) {
                crystal.quoteBuy(true, token, nativeIn, 0);
            }

            uint256 tokenIn = _min(1 ether, tokenBefore / 1_000);
            if (tokenIn > 0) {
                crystal.quoteSell(true, token, tokenIn, 0);
            }

            (uint256 nativeAfter, uint256 tokenAfter) = crystal.getVirtualReserves(token);
            eq(nativeAfter, nativeBefore, "assert nativeAfter == nativeBefore");
            eq(tokenAfter, tokenBefore, "assert tokenAfter == tokenBefore");
        }
    }

    function echidna_registered_actor_mapping() public returns (bool) {
        invariant_registered_actor_mapping();
        return true;
    }

    function echidna_governance_tracking() public returns (bool) {
        invariant_governance_tracking();
        return true;
    }

    function echidna_user_internal_balances() public returns (bool) {
        invariant_user_internal_balances();
        return true;
    }

    function echidna_market_reserve_views() public returns (bool) {
        invariant_market_reserve_views();
        return true;
    }

    function echidna_primary_book_spread_validity() public returns (bool) {
        invariant_primary_book_spread_validity();
        return true;
    }

    function echidna_market_index_views() public returns (bool) {
        invariant_market_index_views();
        return true;
    }

    function echidna_price_ladder_views() public returns (bool) {
        invariant_price_ladder_views();
        return true;
    }

    function echidna_quote_views_match_paths() public returns (bool) {
        invariant_quote_views_match_paths();
        return true;
    }

    function echidna_quote_views_do_not_mutate_and_match_paths() public returns (bool) {
        invariant_quote_views_do_not_mutate_and_match_paths();
        return true;
    }

    function echidna_tracked_orders_match_storage() public returns (bool) {
        invariant_tracked_orders_match_storage();
        return true;
    }

    function echidna_tracked_orders_respect_market_bounds() public returns (bool) {
        invariant_tracked_orders_respect_market_bounds();
        return true;
    }

    function echidna_cloid_views_match_storage() public returns (bool) {
        invariant_cloid_views_match_storage();
        return true;
    }

    function echidna_vault_accounting() public returns (bool) {
        invariant_vault_accounting();
        return true;
    }

    function echidna_vault_risk_bounds() public returns (bool) {
        invariant_vault_risk_bounds();
        return true;
    }

    function echidna_claimable_rewards_are_backed() public returns (bool) {
        invariant_claimable_rewards_are_backed();
        return true;
    }

    function echidna_launchpad_constant_product_metadata() public returns (bool) {
        invariant_launchpad_constant_product_metadata();
        return true;
    }

    function echidna_launchpad_quote_and_token_metadata() public returns (bool) {
        invariant_launchpad_quote_and_token_metadata();
        return true;
    }

    function echidna_launchpad_quote_views_do_not_mutate() public returns (bool) {
        invariant_launchpad_quote_views_do_not_mutate();
        return true;
    }

    function _assertInternalBalanceTuple(address account, address token) internal {
        (uint256 totalBalance, uint256 availableBalance, uint256 lockedBalance) = _totalInternal(account, token);
        eq(totalBalance, availableBalance + lockedBalance, "assert totalBalance == availableBalance + lockedBalance");
        lte(availableBalance, totalBalance, "assert availableBalance <= totalBalance");
        lte(lockedBalance, totalBalance, "assert lockedBalance <= totalBalance");
    }

    function _trackedSizeAtPrice(uint256 price) internal view returns (uint256 size) {
        for (uint256 i = 0; i < trackedOrders.length; i++) {
            if (trackedOrders[i].live && trackedOrders[i].price == price) {
                size += trackedOrders[i].size;
            }
        }
    }

    function _assertExactInputQuotePathParity(
        address routedMarket,
        uint256 quoteIn,
        address[] memory quoteToBase,
        uint256 worstPrice
    ) internal {
        (uint256 directIn, uint256 directOut) = crystal.getQuote(routedMarket, true, true, false, quoteIn, worstPrice);
        (uint256[] memory amountsOut, bool isPartialFill) = crystal.getAmountsOut(quoteIn, quoteToBase);
        if (isPartialFill) {
            return;
        }

        lte(_absDiff(directIn, quoteIn), 1, "assert abs(directIn - quoteIn) <= 1");
        eq(amountsOut.length, 2, "assert amountsOut.length == 2");
        eq(amountsOut[0], quoteIn, "assert amountsOut[0] == quoteIn");
        eq(amountsOut[1], directOut, "assert amountsOut[1] == directOut");
    }

    function _assertExactOutputQuotePathParity(
        address routedMarket,
        uint256 baseOut,
        address[] memory quoteToBase,
        uint256 worstPrice
    ) internal {
        uint256 directIn;
        uint256 directOut;
        try crystal.getQuote(routedMarket, true, false, true, baseOut, worstPrice) returns (
            uint256 quotedIn,
            uint256 quotedOut
        ) {
            directIn = quotedIn;
            directOut = quotedOut;
        } catch {
            return;
        }

        uint256[] memory amountsIn;
        try crystal.getAmountsIn(baseOut, quoteToBase) returns (uint256[] memory quotedAmountsIn) {
            amountsIn = quotedAmountsIn;
        } catch {
            return;
        }

        eq(directOut, baseOut, "assert directOut == baseOut");
        eq(amountsIn.length, 2, "assert amountsIn.length == 2");
        eq(amountsIn[0], directIn, "assert amountsIn[0] == directIn");
        eq(amountsIn[1], baseOut, "assert amountsIn[1] == baseOut");
    }

    function _absDiff(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function _assertEncodedLevels(bytes memory encodedLevels, bool isAscending, uint256 maxLevels) internal {
        eq(encodedLevels.length % 32, 0, "assert encodedLevels.length % 32 == 0");
        lte(encodedLevels.length / 32, maxLevels, "assert encodedLevels.length / 32 <= maxLevels");

        uint256 previousPrice;
        for (uint256 i = 0; i < encodedLevels.length / 32; i++) {
            (uint256 price, uint256 size) = _decodeLevel(encodedLevels, i);
            ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);

            if (i > 0 && isAscending) {
                gt(price, previousPrice, "assert price > previousPrice");
            } else if (i > 0) {
                lt(price, previousPrice, "assert price < previousPrice");
            }

            gt(size, 0, "assert size > 0");
            eq(size, level.size, "assert size == level.size");
            previousPrice = price;
        }
    }

    function _decodeLevel(bytes memory encodedLevels, uint256 index)
        internal
        pure
        returns (uint256 price, uint256 size)
    {
        uint256 encoded;
        assembly {
            encoded := mload(add(add(encodedLevels, 32), mul(index, 32)))
        }
        price = encoded / PRICE_LEVEL_SIZE_OFFSET;
        size = encoded % PRICE_LEVEL_SIZE_OFFSET;
    }
}
