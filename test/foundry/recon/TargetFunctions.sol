// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { vm } from "@chimera/Hevm.sol";

import { ICrystal } from "../../../contracts/interfaces/ICrystal.sol";
import { ICrystalVault } from "../../../contracts/interfaces/ICrystalVault.sol";
import { IERC20 } from "../../../contracts/interfaces/IERC20.sol";
import { Properties } from "./Properties.sol";

interface ICrystalTokenPermitMetadata {
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

interface ICrystalSlotWriter {
    function writeCloidSlots(uint256 userId, uint256[] calldata ids) external;
    function writeSlots(address market, uint256[] calldata buyIds, uint256[] calldata sellIds) external;
}

abstract contract TargetFunctions is Properties {
    function manager_switch_actor(uint256 actorSeed) public updateGhosts {
        address[] memory suiteActors = _getActors();
        _switchActor(actorSeed % suiteActors.length);
    }

    function manager_switch_current_governance() public updateGhosts {
        address[] memory suiteActors = _getActors();
        for (uint256 i = 0; i < suiteActors.length; i++) {
            if (suiteActors[i] == currentGovernance) {
                _switchActor(i);
                return;
            }
        }
    }

    function manager_switch_asset(uint256 assetSeed) public updateGhosts {
        address[] memory suiteAssets = _getAssets();
        _switchAsset(assetSeed % suiteAssets.length);
    }

    function manager_warp_forward(uint256 secondsSeed) public updateGhosts {
        vm.warp(block.timestamp + between(secondsSeed, 1, 400 days));
    }

    function crystal_deposit_quote(uint256 amountSeed) public updateGhosts asActor {
        address actor = _getActor();
        uint256 walletBalance = quote.balanceOf(actor);
        if (walletBalance < MARKET_MIN_SIZE) {
            return;
        }

        uint256 amount = between(amountSeed, MARKET_MIN_SIZE, _min(walletBalance, MAX_TARGET_QUOTE));
        crystal.deposit(address(quote), amount);
    }

    function crystal_deposit_weth(uint256 amountSeed) public updateGhosts asActor {
        address actor = _getActor();
        uint256 walletBalance = weth.balanceOf(actor);
        if (walletBalance < 1 gwei) {
            return;
        }

        uint256 amount = between(amountSeed, 1 gwei, _min(walletBalance, MAX_TARGET_BASE));
        crystal.deposit(address(weth), amount);
    }

    function crystal_deposit_native(uint256 amountSeed) public updateGhosts asActor {
        address actor = _getActor();
        if (actor.balance < 1 gwei) {
            return;
        }

        uint256 amount = between(amountSeed, 1 gwei, _min(actor.balance, 100 ether));
        crystal.deposit{ value: amount }(crystal.eth(), amount);
    }

    function crystal_withdraw_quote(uint256 amountSeed) public updateGhosts asActor {
        address actor = _getActor();
        uint256 availableBalance = _available(actor, address(quote));
        if (availableBalance == 0) {
            return;
        }

        uint256 amount = amountSeed % (availableBalance + 1);
        crystal.withdraw(actor, address(quote), amount);
    }

    function crystal_withdraw_weth(uint256 amountSeed) public updateGhosts asActor {
        address actor = _getActor();
        uint256 availableBalance = _available(actor, address(weth));
        if (availableBalance == 0) {
            return;
        }

        uint256 amount = amountSeed % (availableBalance + 1);
        crystal.withdraw(actor, address(weth), amount);
    }

    function crystal_withdraw_native(uint256 amountSeed) public updateGhosts asActor {
        address actor = _getActor();
        uint256 availableBalance = _available(actor, address(weth));
        if (availableBalance == 0) {
            return;
        }

        uint256 amount = amountSeed % (availableBalance + 1);
        crystal.withdraw(actor, crystal.eth(), amount);
    }

    function crystal_place_buy_limit(uint256 priceSeed, uint256 sizeSeed) public updateGhosts asActor {
        address actor = _getActor();
        uint256 availableQuote = _available(actor, address(quote));
        if (availableQuote < MARKET_MIN_SIZE || !_canTrackOrder()) {
            return;
        }

        (uint256 price, bool ok) = _nonCrossingBid(priceSeed);
        if (!ok) {
            return;
        }

        uint256 size = between(sizeSeed, MARKET_MIN_SIZE, _min(availableQuote, MAX_TARGET_QUOTE));
        uint256 orderId = crystal.limitOrder(address(market), true, 0, price, size, actor);
        _recordOrder(actor, true, price, orderId, size);
    }

    function crystal_place_sell_limit(uint256 priceSeed, uint256 sizeSeed) public updateGhosts asActor {
        address actor = _getActor();
        uint256 availableBase = _available(actor, address(weth));
        (uint256 price, bool ok) = _nonCrossingAsk(priceSeed);
        if (!ok || !_canTrackOrder()) {
            return;
        }

        uint256 minBase = _minBaseForQuote(MARKET_MIN_SIZE, price);
        if (availableBase < minBase || minBase > MAX_TARGET_BASE) {
            return;
        }

        uint256 size = between(sizeSeed, minBase, _min(availableBase, MAX_TARGET_BASE));
        uint256 orderId = crystal.limitOrder(address(market), false, 0, price, size, actor);
        _recordOrder(actor, false, price, orderId, size);
    }

    function crystal_batch_buy_limit(uint256 priceSeed, uint256 sizeSeed) public updateGhosts asActor {
        address actor = _getActor();
        uint256 availableQuote = _available(actor, address(quote));
        if (availableQuote < MARKET_MIN_SIZE || !_canTrackOrder()) {
            return;
        }

        (uint256 price, bool ok) = _nonCrossingBid(priceSeed);
        if (!ok) {
            return;
        }

        uint256 size = between(sizeSeed, MARKET_MIN_SIZE, _min(availableQuote, MAX_TARGET_QUOTE));
        ICrystal.Action[] memory actions = _singleAction(BatchAction.BuyLimit, price, size, 0);

        crystal.batchOrders(address(market), actions, 0, block.timestamp, address(0), actor);
        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);
        _recordOrder(actor, true, price, level.latestNativeId, size);
    }

    function crystal_batch_sell_limit(uint256 priceSeed, uint256 sizeSeed) public updateGhosts asActor {
        address actor = _getActor();
        uint256 availableBase = _available(actor, address(weth));
        (uint256 price, bool ok) = _nonCrossingAsk(priceSeed);
        if (!ok || !_canTrackOrder()) {
            return;
        }

        uint256 minBase = _minBaseForQuote(MARKET_MIN_SIZE, price);
        if (availableBase < minBase || minBase > MAX_TARGET_BASE) {
            return;
        }

        uint256 size = between(sizeSeed, minBase, _min(availableBase, MAX_TARGET_BASE));
        ICrystal.Action[] memory actions = _singleAction(BatchAction.SellLimit, price, size, 0);

        crystal.batchOrders(address(market), actions, 0, block.timestamp, address(0), actor);
        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);
        _recordOrder(actor, false, price, level.latestNativeId, size);
    }

    function crystal_batch_user_id_buy_limit(uint256 priceSeed, uint256 sizeSeed) public updateGhosts asActor {
        address actor = _getActor();
        uint256 userId = crystal.addressToUserId(actor);
        uint256 availableQuote = _available(actor, address(quote));
        if (userId == 0 || availableQuote < MARKET_MIN_SIZE || !_canTrackOrder()) {
            return;
        }

        (uint256 price, bool ok) = _nonCrossingBid(priceSeed);
        if (!ok) {
            return;
        }

        uint256 size = between(sizeSeed, MARKET_MIN_SIZE, _min(availableQuote, MAX_TARGET_QUOTE));
        ICrystal.Action[] memory actions = _singleAction(BatchAction.BuyLimit, price, size, 0);

        crystal.batchOrders(address(market), actions, userId, block.timestamp + 1, address(0), actor);
        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);
        _recordOrder(actor, true, price, level.latestNativeId, size);
    }

    function crystal_cancel_order(uint256 orderSeed) public updateGhosts asActor {
        address actor = _getActor();
        (bool found, uint256 index) = _selectLiveOrderFor(actor, orderSeed);
        if (!found) {
            return;
        }

        TrackedOrder memory tracked = trackedOrders[index];
        crystal.cancelOrder(address(market), 0, tracked.price, tracked.id, actor);
        trackedOrders[index].live = false;
        trackedOrders[index].size = 0;
        _syncTrackedOrders();
    }

    function crystal_cancel_order_to_internal_balance(uint256 orderSeed) public updateGhosts asActor {
        address actor = _getActor();
        (bool found, uint256 index) = _selectLiveOrderFor(actor, orderSeed);
        if (!found) {
            return;
        }

        TrackedOrder memory tracked = trackedOrders[index];
        crystal.cancelOrder(address(market), 1 << 68, tracked.price, tracked.id, actor);
        trackedOrders[index].live = false;
        trackedOrders[index].size = 0;
        _syncTrackedOrders();
    }

    function crystal_replace_order(uint256 orderSeed, uint256 priceSeed) public updateGhosts asActor {
        address actor = _getActor();
        (bool found, uint256 index) = _selectLiveOrderFor(actor, orderSeed);
        if (!found) {
            return;
        }

        TrackedOrder memory tracked = trackedOrders[index];
        (uint256 newPrice, bool ok) = tracked.isBuy ? _nonCrossingBid(priceSeed) : _nonCrossingAsk(priceSeed);
        if (!ok || newPrice == tracked.price) {
            return;
        }
        if (!tracked.isBuy && _quoteValue(tracked.size, newPrice) < MARKET_MIN_SIZE) {
            return;
        }

        uint256 replacementId = crystal.replaceOrder(
            address(market), 0, tracked.price, tracked.id, newPrice, tracked.size, address(0), actor
        );
        trackedOrders[index].live = false;
        _recordOrder(actor, tracked.isBuy, newPrice, replacementId, tracked.size);
        _syncTrackedOrders();
    }

    function crystal_decrease_order(uint256 orderSeed, uint256 amountSeed) public updateGhosts asActor {
        address actor = _getActor();
        (bool found, uint256 index) = _selectLiveOrderFor(actor, orderSeed);
        if (!found) {
            return;
        }

        TrackedOrder memory tracked = trackedOrders[index];
        uint256 minRemaining = tracked.isBuy ? MARKET_MIN_SIZE : _minBaseForQuote(MARKET_MIN_SIZE, tracked.price);
        if (tracked.size <= minRemaining) {
            return;
        }

        uint256 decreaseAmount = between(amountSeed, 1, tracked.size - minRemaining);
        ICrystal.Action[] memory actions =
            _singleAction(BatchAction.DecreaseOrder, tracked.price, decreaseAmount, tracked.id);

        crystal.batchOrders(address(market), actions, 0, block.timestamp, address(0), actor);
        _syncTrackedOrders();
    }

    function crystal_batch_cancel_order(uint256 orderSeed) public updateGhosts asActor {
        address actor = _getActor();
        (bool found, uint256 index) = _selectLiveOrderFor(actor, orderSeed);
        if (!found) {
            return;
        }

        TrackedOrder memory tracked = trackedOrders[index];
        ICrystal.Action[] memory actions = _singleAction(BatchAction.CancelOrder, tracked.price, tracked.id, 0);

        crystal.batchOrders(address(market), actions, 0, block.timestamp, address(0), actor);
        trackedOrders[index].live = false;
        trackedOrders[index].size = 0;
        _syncTrackedOrders();
    }

    function crystal_batch_cancel_cloid_order(uint256 orderSeed) public updateGhosts asActor {
        address actor = _getActor();
        (bool found, uint256 index) = _selectLiveCloidOrderFor(actor, orderSeed);
        if (!found) {
            return;
        }

        TrackedOrder memory tracked = trackedOrders[index];
        ICrystal.Action[] memory actions = _singleAction(BatchAction.CancelOrder, 0, 0, tracked.cloid);

        crystal.batchOrders(address(market), actions, 0, block.timestamp, address(0), actor);
        trackedOrders[index].live = false;
        trackedOrders[index].size = 0;
        _syncTrackedOrders();
    }

    function crystal_batch_decrease_cloid_order(uint256 orderSeed, uint256 amountSeed) public updateGhosts asActor {
        address actor = _getActor();
        (bool found, uint256 index) = _selectLiveCloidOrderFor(actor, orderSeed);
        if (!found) {
            return;
        }

        TrackedOrder memory tracked = trackedOrders[index];
        uint256 minRemaining = tracked.isBuy ? MARKET_MIN_SIZE : _minBaseForQuote(MARKET_MIN_SIZE, tracked.price);
        if (tracked.size <= minRemaining) {
            return;
        }

        uint256 decreaseAmount = between(amountSeed, 1, tracked.size - minRemaining);
        ICrystal.Action[] memory actions = _singleAction(BatchAction.DecreaseOrder, 0, decreaseAmount, tracked.cloid);

        crystal.batchOrders(address(market), actions, 0, block.timestamp, address(0), actor);
        _syncTrackedOrders();
    }

    function crystal_market_buy(uint256 amountSeed) public updateGhosts asActor {
        address actor = _getActor();
        ICrystal.MarketInfo memory info = crystal.getMarket(address(market));
        uint256 availableQuote = _available(actor, address(quote));
        if (info.lowestAsk == 0 || info.lowestAsk >= MARKET_MAX_PRICE || availableQuote < MARKET_MIN_SIZE) {
            return;
        }

        uint256 amountIn = between(amountSeed, MARKET_MIN_SIZE, _min(availableQuote, MAX_TARGET_QUOTE));
        crystal.marketOrder(
            address(market), true, true, 0, ORDER_TYPES_NORMAL, amountIn, info.lowestAsk, address(0), actor
        );
        _syncTrackedOrders();
    }

    function crystal_market_buy_with_referrer(uint256 amountSeed) public updateGhosts asActor {
        address actor = _getActor();
        ICrystal.MarketInfo memory info = crystal.getMarket(address(market));
        uint256 availableQuote = _available(actor, address(quote));
        if (info.lowestAsk == 0 || availableQuote < MARKET_MIN_SIZE) {
            return;
        }

        uint256 amountIn = between(amountSeed, MARKET_MIN_SIZE, _min(availableQuote, MAX_TARGET_QUOTE));
        crystal.marketOrder(
            address(market), true, true, 0, ORDER_TYPES_NORMAL, amountIn, info.lowestAsk, _secondaryActor(actor), actor
        );
        _syncTrackedOrders();
    }

    function crystal_market_sell(uint256 amountSeed) public updateGhosts asActor {
        address actor = _getActor();
        ICrystal.MarketInfo memory info = crystal.getMarket(address(market));
        uint256 availableBase = _available(actor, address(weth));
        if (info.highestBid == 0) {
            return;
        }

        uint256 minBase = _minBaseForQuote(MARKET_MIN_SIZE, info.highestBid);
        if (availableBase < minBase || minBase > MAX_TARGET_BASE) {
            return;
        }

        uint256 amountIn = between(amountSeed, minBase, _min(availableBase, MAX_TARGET_BASE));
        crystal.marketOrder(
            address(market), false, true, 0, ORDER_TYPES_NORMAL, amountIn, info.highestBid, address(0), actor
        );
        _syncTrackedOrders();
    }

    function crystal_market_sell_with_referrer(uint256 amountSeed) public updateGhosts asActor {
        address actor = _getActor();
        ICrystal.MarketInfo memory info = crystal.getMarket(address(market));
        uint256 availableBase = _available(actor, address(weth));
        if (info.highestBid == 0) {
            return;
        }

        uint256 minBase = _minBaseForQuote(MARKET_MIN_SIZE, info.highestBid);
        if (availableBase < minBase || minBase > MAX_TARGET_BASE) {
            return;
        }

        uint256 amountIn = between(amountSeed, minBase, _min(availableBase, MAX_TARGET_BASE));
        crystal.marketOrder(
            address(market),
            false,
            true,
            0,
            ORDER_TYPES_NORMAL,
            amountIn,
            info.highestBid,
            _secondaryActor(actor),
            actor
        );
        _syncTrackedOrders();
    }

    function crystal_market_buy_exact_output(uint256 amountSeed) public updateGhosts asActor {
        address actor = _getActor();
        ICrystal.MarketInfo memory info = crystal.getMarket(address(market));
        if (info.lowestAsk == 0 || _available(actor, address(quote)) < MARKET_MIN_SIZE) {
            return;
        }

        uint256 minBase = _minBaseForQuote(MARKET_MIN_SIZE, info.lowestAsk);
        if (minBase == 0 || minBase > MAX_TARGET_BASE) {
            return;
        }

        uint256 amountOut = between(amountSeed, minBase, MAX_TARGET_BASE);
        crystal.marketOrder(
            address(market), true, false, 0, ORDER_TYPES_NORMAL, amountOut, info.lowestAsk, address(0), actor
        );
        _syncTrackedOrders();
    }

    function crystal_market_sell_exact_output(uint256 amountSeed) public updateGhosts asActor {
        address actor = _getActor();
        ICrystal.MarketInfo memory info = crystal.getMarket(address(market));
        uint256 availableBase = _available(actor, address(weth));
        if (info.highestBid == 0 || availableBase == 0) {
            return;
        }

        uint256 maxQuoteOut = _quoteValue(_min(availableBase, MAX_TARGET_BASE), info.highestBid);
        if (maxQuoteOut < MARKET_MIN_SIZE) {
            return;
        }

        uint256 amountOut = between(amountSeed, MARKET_MIN_SIZE, _min(maxQuoteOut, MAX_TARGET_QUOTE));
        crystal.marketOrder(
            address(market), false, false, 0, ORDER_TYPES_NORMAL, amountOut, info.highestBid, address(0), actor
        );
        _syncTrackedOrders();
    }

    function crystal_add_liquidity(uint256 quoteSeed, uint256 baseSeed) public updateGhosts asActor {
        address actor = _getActor();
        uint256 quoteWallet = quote.balanceOf(actor);
        uint256 baseWallet = weth.balanceOf(actor);
        if (quoteWallet < MARKET_MIN_SIZE * 20) {
            return;
        }

        uint256 amountQuote = between(quoteSeed, MARKET_MIN_SIZE * 20, _min(quoteWallet, MAX_TARGET_QUOTE));
        uint256 minBase = _minBaseForQuote(amountQuote, MARKET_MAX_PRICE);
        if (baseWallet < minBase || minBase > MAX_TARGET_BASE) {
            return;
        }

        uint256 amountBase = between(baseSeed, minBase, _min(baseWallet, MAX_TARGET_BASE));
        crystal.addLiquidity(address(market), actor, amountQuote, amountBase, 0, 0);
    }

    function crystal_add_liquidity_eth_base(uint256 quoteSeed, uint256 baseSeed) public updateGhosts asActor {
        address actor = _getActor();
        uint256 quoteWallet = quote.balanceOf(actor);
        if (quoteWallet < MARKET_MIN_SIZE * 20 || actor.balance < 1 gwei) {
            return;
        }

        uint256 amountQuote = between(quoteSeed, MARKET_MIN_SIZE * 20, _min(quoteWallet, MAX_TARGET_QUOTE));
        uint256 minBase = _minBaseForQuote(amountQuote, MARKET_MAX_PRICE);
        if (minBase == 0 || minBase > MAX_TARGET_BASE || actor.balance < minBase) {
            return;
        }

        uint256 amountBase = between(baseSeed, minBase, _min(actor.balance, MAX_TARGET_BASE));
        crystal.addLiquidity{ value: amountBase }(address(market), actor, amountQuote, amountBase, 0, 0);
    }

    function crystal_remove_liquidity(uint256 liquiditySeed) public updateGhosts asActor {
        address actor = _getActor();
        uint256 liquidity = market.balanceOf(actor);
        if (liquidity == 0) {
            return;
        }

        uint256 amount = between(liquiditySeed, 1, liquidity);
        crystal.removeLiquidity(address(market), actor, amount, 0, 0);
    }

    function crystal_remove_liquidity_eth(uint256 liquiditySeed) public updateGhosts asActor {
        address actor = _getActor();
        uint256 liquidity = market.balanceOf(actor);
        if (liquidity == 0) {
            return;
        }

        uint256 amount = between(liquiditySeed, 1, liquidity);
        crystal.removeLiquidityETH(address(market), actor, amount, 0, 0);
    }

    function crystal_swap_quote_for_weth(uint256 amountSeed) public updateGhosts asActor {
        address actor = _getActor();
        (uint112 reserveQuote, uint112 reserveBase) = crystal.getReserves(address(market));
        uint256 walletBalance = quote.balanceOf(actor);
        if (reserveQuote == 0 || reserveBase == 0 || walletBalance < MARKET_MIN_SIZE) {
            return;
        }

        uint256 maxIn = _min(walletBalance, uint256(reserveQuote) / 100);
        if (maxIn < MARKET_MIN_SIZE) {
            return;
        }

        uint256 amountIn = between(amountSeed, MARKET_MIN_SIZE, maxIn);
        address[] memory path = _path(address(quote), address(weth));
        (uint256[] memory amounts, bool isPartialFill) = crystal.getAmountsOut(amountIn, path);
        if (isPartialFill || amounts.length != 2 || amounts[1] == 0) {
            return;
        }

        crystal.swapExactTokensForTokens(amountIn, amounts[1], path, actor, block.timestamp, address(0));
    }

    function crystal_swap_quote_for_exact_weth(uint256 amountSeed) public updateGhosts asActor {
        address actor = _getActor();
        (uint112 reserveQuote, uint112 reserveBase) = crystal.getReserves(address(market));
        uint256 walletBalance = quote.balanceOf(actor);
        if (reserveQuote == 0 || reserveBase == 0 || walletBalance < MARKET_MIN_SIZE) {
            return;
        }

        uint256 amountIn = _min(walletBalance, uint256(reserveQuote) / 100);
        if (amountIn < MARKET_MIN_SIZE) {
            return;
        }

        address[] memory path = _path(address(quote), address(weth));
        (uint256[] memory amounts, bool isPartialFill) = crystal.getAmountsOut(amountIn, path);
        if (isPartialFill || amounts.length != 2 || amounts[1] == 0) {
            return;
        }
        uint256 amountOut = between(amountSeed, 1, amounts[1]);

        crystal.swapTokensForExactTokens(amountOut, amountIn, path, actor, block.timestamp, address(0));
    }

    function crystal_swap_weth_for_quote(uint256 amountSeed) public updateGhosts asActor {
        address actor = _getActor();
        (uint112 reserveQuote, uint112 reserveBase) = crystal.getReserves(address(market));
        uint256 walletBalance = weth.balanceOf(actor);
        if (reserveQuote == 0 || reserveBase == 0 || walletBalance == 0) {
            return;
        }

        uint256 maxIn = _min(walletBalance, uint256(reserveBase) / 100);
        if (maxIn == 0) {
            return;
        }

        uint256 amountIn = between(amountSeed, 1, maxIn);
        address[] memory path = _path(address(weth), address(quote));
        (uint256[] memory amounts, bool isPartialFill) = crystal.getAmountsOut(amountIn, path);
        if (isPartialFill || amounts.length != 2 || amounts[1] == 0) {
            return;
        }

        crystal.swapExactTokensForTokens(amountIn, amounts[1], path, actor, block.timestamp, address(0));
    }

    function crystal_swap_weth_for_exact_quote(uint256 amountSeed) public updateGhosts asActor {
        address actor = _getActor();
        (uint112 reserveQuote, uint112 reserveBase) = crystal.getReserves(address(market));
        uint256 walletBalance = weth.balanceOf(actor);
        if (reserveQuote == 0 || reserveBase == 0 || walletBalance == 0) {
            return;
        }

        uint256 amountIn = _min(walletBalance, uint256(reserveBase) / 100);
        if (amountIn == 0) {
            return;
        }

        address[] memory path = _path(address(weth), address(quote));
        (uint256[] memory amounts, bool isPartialFill) = crystal.getAmountsOut(amountIn, path);
        if (isPartialFill || amounts.length != 2 || amounts[1] == 0) {
            return;
        }
        uint256 amountOut = between(amountSeed, 1, amounts[1]);

        crystal.swapTokensForExactTokens(amountOut, amountIn, path, actor, block.timestamp, address(0));
    }

    function crystal_swap_exact_quote_for_weth_public(uint256 amountSeed) public updateGhosts asActor {
        address actor = _getActor();
        uint256 walletQuote = quote.balanceOf(actor);
        if (walletQuote < MARKET_MIN_SIZE) {
            return;
        }

        uint256 amountIn = between(amountSeed, MARKET_MIN_SIZE, _min(walletQuote, MARKET_MIN_SIZE * 20));
        address[] memory path = _path(address(quote), address(weth));
        (uint256[] memory amounts, bool isPartialFill) = crystal.getAmountsOut(amountIn, path);
        if (isPartialFill || amounts.length != 2 || amounts[1] == 0) {
            return;
        }

        crystal.swapExactTokensForTokens(amountIn, amounts[1], path, actor, block.timestamp, address(0));
    }

    function crystal_swap_quote_for_exact_weth_public(uint256 amountSeed) public updateGhosts asActor {
        address actor = _getActor();
        uint256 walletQuote = quote.balanceOf(actor);
        if (walletQuote < MARKET_MIN_SIZE) {
            return;
        }

        uint256 probeIn = _min(walletQuote, MARKET_MIN_SIZE * 20);
        address[] memory path = _path(address(quote), address(weth));
        (uint256[] memory amounts, bool isPartialFill) = crystal.getAmountsOut(probeIn, path);
        if (isPartialFill || amounts.length != 2 || amounts[1] <= 1) {
            return;
        }

        uint256 amountOut = between(amountSeed, 1, amounts[1] / 2);
        uint256[] memory amountsIn = crystal.getAmountsIn(amountOut, path);
        if (amountsIn.length != 2 || amountsIn[0] > walletQuote) {
            return;
        }

        crystal.swapTokensForExactTokens(amountOut, amountsIn[0], path, actor, block.timestamp, address(0));
    }

    function crystal_swap_exact_eth_for_quote_public(uint256 amountSeed) public updateGhosts asActor {
        address actor = _getActor();
        if (actor.balance < 1 gwei) {
            return;
        }

        uint256 amountIn = between(amountSeed, 1 gwei, _min(actor.balance, 5 ether));
        address[] memory path = _path(crystal.eth(), address(quote));
        (uint256[] memory amounts, bool isPartialFill) = crystal.getAmountsOut(amountIn, path);
        if (isPartialFill || amounts.length != 2 || amounts[1] == 0) {
            return;
        }

        crystal.swapExactETHForTokens{ value: amountIn }(amounts[1], path, actor, block.timestamp, address(0));
    }

    function crystal_swap_exact_quote_for_eth_public(uint256 amountSeed) public updateGhosts asActor {
        address actor = _getActor();
        uint256 walletQuote = quote.balanceOf(actor);
        if (walletQuote < MARKET_MIN_SIZE) {
            return;
        }

        uint256 amountIn = between(amountSeed, MARKET_MIN_SIZE, _min(walletQuote, MARKET_MIN_SIZE * 20));
        address[] memory path = _path(address(quote), crystal.eth());
        (uint256[] memory amounts, bool isPartialFill) = crystal.getAmountsOut(amountIn, path);
        if (isPartialFill || amounts.length != 2 || amounts[1] == 0) {
            return;
        }

        crystal.swapExactTokensForETH(amountIn, amounts[1], path, actor, block.timestamp, address(0));
    }

    function crystal_swap_eth_for_exact_quote_public(uint256 amountSeed) public updateGhosts asActor {
        address actor = _getActor();
        if (actor.balance < 1 gwei) {
            return;
        }

        uint256 probeIn = between(amountSeed, 1 gwei, _min(actor.balance, 5 ether));
        address[] memory path = _path(crystal.eth(), address(quote));
        (uint256[] memory amounts, bool isPartialFill) = crystal.getAmountsOut(probeIn, path);
        if (isPartialFill || amounts.length != 2 || amounts[1] <= 1) {
            return;
        }

        uint256 amountOut = between(amountSeed / 7, 1, amounts[1] / 2);
        uint256[] memory amountsIn = crystal.getAmountsIn(amountOut, path);
        if (amountsIn.length != 2 || amountsIn[0] + 1 gwei > actor.balance) {
            return;
        }

        crystal.swapETHForExactTokens{ value: amountsIn[0] + 1 gwei }(
            amountOut, path, actor, block.timestamp, address(0)
        );
    }

    function crystal_swap_quote_for_exact_eth_public(uint256 amountSeed) public updateGhosts asActor {
        address actor = _getActor();
        uint256 walletQuote = quote.balanceOf(actor);
        if (walletQuote < MARKET_MIN_SIZE) {
            return;
        }

        uint256 probeIn = _min(walletQuote, MARKET_MIN_SIZE * 20);
        address[] memory path = _path(address(quote), crystal.eth());
        (uint256[] memory amounts, bool isPartialFill) = crystal.getAmountsOut(probeIn, path);
        if (isPartialFill || amounts.length != 2 || amounts[1] <= 1) {
            return;
        }

        uint256 amountOut = between(amountSeed, 1, amounts[1] / 2);
        uint256[] memory amountsIn = crystal.getAmountsIn(amountOut, path);
        if (amountsIn.length != 2 || amountsIn[0] > walletQuote) {
            return;
        }

        crystal.swapTokensForExactETH(amountOut, amountsIn[0], path, actor, block.timestamp, address(0));
    }

    function crystal_governance_change_gov(uint256 actorSeed) public updateGhosts asActor {
        if (_getActor() != currentGovernance) {
            return;
        }

        address[] memory suiteActors = _actors();
        address newGov = suiteActors[actorSeed % suiteActors.length];
        if (newGov == currentGovernance) {
            return;
        }

        crystal.changeGov(newGov);
        currentGovernance = newGov;
    }

    function crystal_governance_change_fee_recipient() public updateGhosts asActor {
        if (_getActor() != currentGovernance) {
            return;
        }

        crystal.changeFeeRecipient(address(this));
    }

    function crystal_governance_change_fee_claim_duration(uint256 paramSeed) public updateGhosts asActor {
        if (_getActor() != currentGovernance) {
            return;
        }

        crystal.changeFeeClaimDuration(1 hours + (paramSeed % 7 days));
    }

    function crystal_governance_change_ref_fee_commission(uint256 paramSeed) public updateGhosts asActor {
        if (_getActor() != currentGovernance) {
            return;
        }

        crystal.changeRefFeeCommission(uint8(paramSeed % 100));
    }

    function crystal_governance_change_market_params(uint256 paramSeed) public updateGhosts asActor {
        if (_getActor() != currentGovernance) {
            return;
        }

        uint256 minSize = MARKET_MIN_SIZE + (paramSeed % MARKET_MIN_SIZE);
        uint24 takerFee = uint24(99_900 + (paramSeed % 80));
        uint24 makerRebate = uint24(99_900 + ((paramSeed / 97) % 90));
        crystal.changeMarketParams(address(market), minSize, takerFee, makerRebate, true, true);
    }

    function crystal_governance_change_market_creator_fee(uint256 paramSeed) public updateGhosts asActor {
        if (_getActor() != currentGovernance) {
            return;
        }

        crystal.changeMarketCreatorFee(address(market), address(this), paramSeed % 100);
    }

    function crystal_governance_change_launchpad_params() public updateGhosts asActor {
        if (_getActor() != currentGovernance) {
            return;
        }

        crystal.changeLaunchpadParams(
            ICrystal.LaunchpadParams({
                launchpadInitialNativeSupply: LAUNCHPAD_INITIAL_NATIVE_SUPPLY,
                launchpadFee: LAUNCHPAD_FEE,
                launchpadCreatorFeeSplit: LAUNCHPAD_CREATOR_FEE_SPLIT,
                graduatedMinSize: GRADUATED_MIN_SIZE,
                graduatedTakerFee: GRADUATED_TAKER_FEE,
                graduatedMakerRebate: GRADUATED_MAKER_REBATE,
                graduatedCreatorFeeSplit: GRADUATED_CREATOR_FEE_SPLIT
            })
        );
    }

    function crystal_governance_claim_locked_reserves() public updateGhosts asActor {
        if (_getActor() != currentGovernance) {
            return;
        }

        try crystal.claimLockedReserves(address(market)) {} catch {}
    }

    function crystal_governance_uncanonicalize_market(uint256 paramSeed) public updateGhosts asActor {
        if (_getActor() != currentGovernance) {
            return;
        }

        uint256 minSize = MARKET_MIN_SIZE + (paramSeed % MARKET_MIN_SIZE);
        uint24 takerFee = uint24(99_900 + (paramSeed % 80));
        uint24 makerRebate = uint24(99_900 + ((paramSeed / 97) % 90));

        crystal.changeMarketParams(address(market), minSize, takerFee, makerRebate, true, false);
    }

    function crystal_governance_add_canonical_deployer(uint256 seed) public updateGhosts asActor {
        if (_getActor() != currentGovernance) {
            return;
        }

        address deployer = address(uint160(0xC0DE0000 + (seed % 1_000_000)));
        crystal.addCanonicalDeployer(deployer);
    }

    function crystal_governance_remove_canonical_deployer(uint256 seed) public updateGhosts asActor {
        if (_getActor() != currentGovernance) {
            return;
        }

        address deployer = address(uint160(0xC0DE0000 + (seed % 1_000_000)));
        if (!crystal.isCanonicalDeployer(deployer)) {
            return;
        }

        crystal.removeCanonicalDeployer(deployer);
    }

    function crystal_governance_deploy_market(uint256 seed) public updateGhosts asActor {
        if (_getActor() != currentGovernance) {
            return;
        }
        if (extraAssetsDeployed >= 32) {
            return;
        }

        extraAssetsDeployed++;
        address asset = _newAsset(18);
        bool nativePair = seed % 2 == 0;
        crystal.deploy(
            true,
            nativePair ? crystal.eth() : address(quote),
            nativePair ? asset : crystal.eth(),
            MARKET_TYPE_LOGARITHMIC_AMM,
            MARKET_SCALE_FACTOR,
            MARKET_TICK_SIZE,
            MARKET_MAX_PRICE,
            MARKET_MIN_SIZE,
            MARKET_TAKER_FEE,
            MARKET_MAKER_REBATE
        );
    }

    function crystal_governance_deploy_type3_market() public updateGhosts asActor {
        if (_getActor() != currentGovernance || trackedFreshMarkets.length >= MAX_TRACKED_FRESH_MARKETS) {
            return;
        }

        address freshMarket = crystal.deploy(
            true,
            address(quote),
            address(weth),
            3,
            MARKET_SCALE_FACTOR,
            MARKET_TICK_SIZE,
            MARKET_MAX_PRICE,
            MARKET_MIN_SIZE,
            MARKET_TAKER_FEE,
            MARKET_MAKER_REBATE
        );
        _recordFreshMarket(freshMarket);
    }

    function crystal_governance_deploy_canonical_book_market(uint256 seed) public updateGhosts asActor {
        if (_getActor() != currentGovernance || extraAssetsDeployed >= 32) {
            return;
        }

        extraAssetsDeployed++;
        address asset = _newAsset(18);
        crystal.deploy(
            true,
            address(quote),
            asset,
            1 + (seed % 2),
            MARKET_SCALE_FACTOR,
            MARKET_TICK_SIZE,
            MARKET_MAX_PRICE,
            MARKET_MIN_SIZE,
            MARKET_TAKER_FEE,
            MARKET_MAKER_REBATE
        );
    }

    function crystal_fresh_market_add_liquidity(uint256 marketSeed, uint256 quoteSeed, uint256 baseSeed)
        public
        updateGhosts
        asActor
    {
        if (trackedFreshMarkets.length == 0) {
            return;
        }

        address actor = _getActor();
        uint256 quoteWallet = quote.balanceOf(actor);
        uint256 baseWallet = weth.balanceOf(actor);
        if (quoteWallet < MARKET_MIN_SIZE || baseWallet == 0) {
            return;
        }

        uint256 amountQuote = between(quoteSeed, MARKET_MIN_SIZE, _min(quoteWallet, MAX_TARGET_QUOTE));
        uint256 amountBase = between(baseSeed, 1, _min(baseWallet, MAX_TARGET_BASE));
        crystal.addLiquidity(_trackedFreshMarket(marketSeed), actor, amountQuote, amountBase, 0, 0);
    }

    function crystal_fresh_market_remove_liquidity(uint256 marketSeed, uint256 liquiditySeed)
        public
        updateGhosts
        asActor
    {
        if (trackedFreshMarkets.length == 0) {
            return;
        }

        address actor = _getActor();
        address freshMarket = _trackedFreshMarket(marketSeed);
        uint256 liquidity = IERC20(freshMarket).balanceOf(actor);
        if (liquidity == 0) {
            return;
        }

        uint256 amount = between(liquiditySeed, 1, liquidity);
        crystal.removeLiquidity(freshMarket, actor, amount, 0, 0);
    }

    function crystal_fresh_market_market_buy(uint256 marketSeed, uint256 amountSeed) public updateGhosts asActor {
        if (trackedFreshMarkets.length == 0) {
            return;
        }

        address actor = _getActor();
        uint256 availableQuote = _available(actor, address(quote));
        if (availableQuote < MARKET_MIN_SIZE) {
            return;
        }

        uint256 amountIn = between(amountSeed, MARKET_MIN_SIZE, _min(availableQuote, MAX_TARGET_QUOTE));
        crystal.marketOrder(
            _trackedFreshMarket(marketSeed),
            true,
            true,
            0,
            ORDER_TYPES_NORMAL,
            amountIn,
            MARKET_MAX_PRICE,
            address(0),
            actor
        );
    }

    function crystal_fresh_market_market_sell(uint256 marketSeed, uint256 amountSeed) public updateGhosts asActor {
        if (trackedFreshMarkets.length == 0) {
            return;
        }

        address actor = _getActor();
        uint256 availableBase = _available(actor, address(weth));
        if (availableBase == 0) {
            return;
        }

        uint256 amountIn = between(amountSeed, 1, _min(availableBase, MAX_TARGET_BASE));
        crystal.marketOrder(
            _trackedFreshMarket(marketSeed), false, true, 0, ORDER_TYPES_NORMAL, amountIn, 0, address(0), actor
        );
    }

    function crystal_governance_claim_fresh_market_locked_reserves(uint256 marketSeed) public updateGhosts asActor {
        if (_getActor() != currentGovernance || trackedFreshMarkets.length == 0) {
            return;
        }

        try crystal.claimLockedReserves(_trackedFreshMarket(marketSeed)) {} catch {}
    }

    function crystal_governance_queue_claim_expired_fees(uint256 actorSeed) public updateGhosts asActor {
        if (_getActor() != currentGovernance) {
            return;
        }

        address[] memory suiteActors = _actors();
        address actor = suiteActors[actorSeed % suiteActors.length];
        address[] memory feeTokens = _tokens(address(quote), address(weth));

        crystal.queueClaimExpiredFees(actor, feeTokens);
    }

    function crystal_governance_execute_claim_expired_fees(uint256 actorSeed) public updateGhosts asActor {
        if (_getActor() != currentGovernance) {
            return;
        }

        address[] memory suiteActors = _actors();
        address actor = suiteActors[actorSeed % suiteActors.length];
        crystal.executeClaimExpiredFees(actor);
    }

    function crystal_admin_add_claimable_token_fees(uint256 actorSeed, uint256 amountSeed) public updateGhosts asActor {
        if (_getActor() != address(this)) {
            return;
        }

        address[] memory suiteActors = _actors();
        address actor = suiteActors[actorSeed % suiteActors.length];
        uint256 quoteBalance = quote.balanceOf(address(this));
        uint256 baseBalance = weth.balanceOf(address(this));
        if (quoteBalance < MARKET_MIN_SIZE || baseBalance < 1 gwei) {
            return;
        }

        uint256 amountQuote = between(amountSeed, MARKET_MIN_SIZE, _min(quoteBalance, 5_000 * 1e6));
        uint256 amountBase = between(amountSeed / 2, 1 gwei, _min(baseBalance, 5 ether));
        address[] memory feeTokens = _tokens(address(quote), address(weth));
        uint256[] memory feeAmounts = _amounts(amountQuote, amountBase);

        crystal.addClaimableFee(actor, feeTokens, feeAmounts);
    }

    function crystal_admin_add_claimable_native_fee(uint256 actorSeed, uint256 amountSeed) public updateGhosts asActor {
        if (_getActor() != address(this)) {
            return;
        }

        address[] memory suiteActors = _actors();
        address actor = suiteActors[actorSeed % suiteActors.length];
        if (address(this).balance < 1 gwei) {
            return;
        }

        uint256 amountBase = between(amountSeed, 1 gwei, _min(address(this).balance, 5 ether));
        address[] memory ethToken = new address[](1);
        ethToken[0] = crystal.eth();
        uint256[] memory ethAmount = new uint256[](1);
        ethAmount[0] = amountBase;
        crystal.addClaimableFee{ value: amountBase }(actor, ethToken, ethAmount);
    }

    function crystal_claim_token_fees() public updateGhosts asActor {
        address actor = _getActor();
        address[] memory feeTokens = _tokens(address(quote), address(weth));
        crystal.claimFees(actor, feeTokens);
    }

    function crystal_claim_native_fees() public updateGhosts asActor {
        address actor = _getActor();
        address[] memory ethToken = new address[](1);
        ethToken[0] = crystal.eth();
        crystal.claimFees(actor, ethToken);
    }

    function crystal_register_actor(uint256 seed) public updateGhosts asActor {
        address actor = _getActor();
        if (crystal.addressToUserId(actor) == 0) {
            crystal.registerUser(actor);
        }
        seed;
    }

    function crystal_approve_forwarder() public updateGhosts asActor {
        crystal.approveForwarder(RECON_FORWARDER);
    }

    function crystal_remove_forwarder() public updateGhosts asActor {
        crystal.removeForwarder(RECON_FORWARDER);
    }

    function crystal_multibatch_orders(uint256 priceSeed, uint256 sizeSeed) public updateGhosts asActor {
        address actor = _getActor();
        uint256 availableQuote = _available(actor, address(quote));
        if (availableQuote < MARKET_MIN_SIZE || !_canTrackOrder()) {
            return;
        }

        (uint256 price, bool ok) = _nonCrossingBid(priceSeed);
        if (!ok) {
            return;
        }

        uint256 size = between(sizeSeed, MARKET_MIN_SIZE, _min(availableQuote, MAX_TARGET_QUOTE));
        ICrystal.Batch[] memory batches = new ICrystal.Batch[](1);
        batches[0] = ICrystal.Batch({
            market: address(market), actions: _singleAction(BatchAction.BuyLimit, price, size, 0), options: 0
        });

        crystal.multiBatchOrders(batches, block.timestamp, address(0));
        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);
        _recordOrder(actor, true, price, level.latestNativeId, size);
    }

    function crystal_router_deposit_quote(uint256 amountSeed) public updateGhosts asActor {
        address actor = _getActor();
        uint256 quoteWallet = quote.balanceOf(actor);
        if (quoteWallet < MARKET_MIN_SIZE) {
            return;
        }

        uint256 quoteAmount = between(amountSeed, MARKET_MIN_SIZE, _min(quoteWallet, MAX_TARGET_QUOTE));
        crystal.routerDeposit(address(quote), quoteAmount);
    }

    function crystal_router_deposit_native(uint256 amountSeed) public updateGhosts asActor {
        address actor = _getActor();
        if (actor.balance < 1 gwei) {
            return;
        }

        uint256 ethAmount = between(amountSeed, 1 gwei, _min(actor.balance, 20 ether));
        crystal.routerDeposit{ value: ethAmount }(crystal.eth(), ethAmount);
    }

    function crystal_router_withdraw_quote(uint256 amountSeed) public updateGhosts asActor {
        address actor = _getActor();
        uint256 availableBalance = _available(actor, address(quote));
        if (availableBalance == 0) {
            return;
        }

        uint256 amount = amountSeed % (availableBalance + 1);
        crystal.routerWithdraw(actor, address(quote), amount);
    }

    function crystal_router_withdraw_native(uint256 amountSeed) public updateGhosts asActor {
        address actor = _getActor();
        uint256 availableBalance = _available(actor, address(weth));
        if (availableBalance == 0) {
            return;
        }

        uint256 amount = amountSeed % (availableBalance + 1);
        crystal.routerWithdraw(actor, crystal.eth(), amount);
    }

    function crystal_direct_swap_quote_for_weth(uint256 amountSeed) public updateGhosts asActor {
        address actor = _getActor();
        (uint112 reserveQuote, uint112 reserveBase) = crystal.getReserves(address(market));
        uint256 walletQuote = quote.balanceOf(actor);
        if (reserveQuote == 0 || reserveBase == 0 || walletQuote < MARKET_MIN_SIZE) {
            return;
        }

        uint256 maxIn = _min(walletQuote, uint256(reserveQuote) / 100);
        if (maxIn < MARKET_MIN_SIZE) {
            return;
        }

        uint256 amountIn = between(amountSeed, MARKET_MIN_SIZE, maxIn);
        crystal.swap(
            true, address(quote), address(weth), ORDER_TYPES_NORMAL, amountIn, 0, block.timestamp + 1, address(0)
        );
    }

    function crystal_direct_swap_weth_for_quote(uint256 amountSeed) public updateGhosts asActor {
        address actor = _getActor();
        (uint112 reserveQuote, uint112 reserveBase) = crystal.getReserves(address(market));
        uint256 walletBase = weth.balanceOf(actor);
        if (reserveQuote == 0 || reserveBase == 0 || walletBase == 0) {
            return;
        }

        uint256 maxIn = _min(walletBase, uint256(reserveBase) / 100);
        if (maxIn == 0) {
            return;
        }

        uint256 amountIn = between(amountSeed, 1, maxIn);
        crystal.swap(
            true, address(weth), address(quote), ORDER_TYPES_NORMAL, amountIn, 0, block.timestamp + 1, address(0)
        );
    }

    function crystal_direct_swap_eth_for_quote(uint256 amountSeed) public updateGhosts asActor {
        address actor = _getActor();
        (uint112 reserveQuote, uint112 reserveBase) = crystal.getReserves(address(market));
        if (reserveQuote == 0 || reserveBase == 0 || actor.balance < 1 gwei) {
            return;
        }

        uint256 amountIn = between(amountSeed, 1 gwei, _min(actor.balance, 10 ether));
        crystal.swap{ value: amountIn }(
            true, crystal.eth(), address(quote), ORDER_TYPES_NORMAL, amountIn, 0, block.timestamp + 1, address(0)
        );
    }

    function crystal_direct_swap_quote_for_eth(uint256 amountSeed) public updateGhosts asActor {
        address actor = _getActor();
        (uint112 reserveQuote, uint112 reserveBase) = crystal.getReserves(address(market));
        uint256 walletQuote = quote.balanceOf(actor);
        if (reserveQuote == 0 || reserveBase == 0 || walletQuote < MARKET_MIN_SIZE) {
            return;
        }

        uint256 maxIn = _min(walletQuote, uint256(reserveQuote) / 100);
        if (maxIn < MARKET_MIN_SIZE) {
            return;
        }

        uint256 amountIn = between(amountSeed, MARKET_MIN_SIZE, maxIn);
        crystal.swap(
            true, address(quote), crystal.eth(), ORDER_TYPES_NORMAL, amountIn, 0, block.timestamp + 1, address(0)
        );
    }

    function crystal_direct_swap_exact_weth_out(uint256 amountSeed) public updateGhosts asActor {
        address actor = _getActor();
        uint256 walletQuote = quote.balanceOf(actor);
        if (walletQuote < MARKET_MIN_SIZE) {
            return;
        }

        address[] memory path = _path(address(quote), address(weth));
        uint256 quotedInput = _min(walletQuote, MAX_TARGET_QUOTE);
        (uint256[] memory amounts, bool isPartialFill) = crystal.getAmountsOut(quotedInput, path);
        if (isPartialFill || amounts.length != 2 || amounts[1] <= 1) {
            return;
        }

        uint256 amountOut = between(amountSeed, 1, amounts[1] / 2);
        crystal.swap(
            false, address(quote), address(weth), ORDER_TYPES_NORMAL, amountOut, 0, block.timestamp + 1, address(0)
        );
    }

    function crystal_direct_swap_exact_quote_out_from_eth(uint256 amountSeed) public updateGhosts asActor {
        address actor = _getActor();
        if (actor.balance < 1 gwei) {
            return;
        }

        address[] memory path = _path(crystal.eth(), address(quote));
        uint256 ethProbe = between(amountSeed, 1 gwei, _min(actor.balance, 10 ether));
        (uint256[] memory amounts, bool isPartialFill) = crystal.getAmountsOut(ethProbe, path);
        if (isPartialFill || amounts.length != 2 || amounts[1] <= 1) {
            return;
        }

        uint256 amountOut = between(amountSeed / 7, 1, amounts[1] / 2);
        uint256[] memory amountsIn = crystal.getAmountsIn(amountOut, path);
        if (amountsIn.length != 2 || amountsIn[0] + 1 gwei > actor.balance) {
            return;
        }

        crystal.swap{ value: amountsIn[0] + 1 gwei }(
            false, crystal.eth(), address(quote), ORDER_TYPES_NORMAL, amountOut, 0, block.timestamp + 1, address(0)
        );
    }

    function crystal_wrapper_place_buy_limit(uint256 priceSeed, uint256 sizeSeed) public updateGhosts asActor {
        address actor = _getActor();
        uint256 walletQuote = quote.balanceOf(actor);
        if (walletQuote < MARKET_MIN_SIZE || !_canTrackOrder()) {
            return;
        }

        (uint256 bidPrice, bool bidOk) = _nonCrossingBid(priceSeed);
        if (!bidOk) {
            return;
        }

        uint256 size = between(sizeSeed, MARKET_MIN_SIZE, _min(walletQuote, MAX_TARGET_QUOTE));
        uint256 orderId = crystal.placeLimitOrder(address(quote), address(weth), bidPrice, size, block.timestamp + 1);
        _recordOrderWithTokens(actor, true, bidPrice, orderId, size, address(quote), address(weth));
    }

    function crystal_wrapper_place_sell_limit(uint256 priceSeed, uint256 sizeSeed) public updateGhosts asActor {
        address actor = _getActor();
        uint256 walletBase = weth.balanceOf(actor);
        (uint256 askPrice, bool askOk) = _nonCrossingAsk(priceSeed);
        if (!askOk || !_canTrackOrder()) {
            return;
        }

        uint256 minBase = _minBaseForQuote(MARKET_MIN_SIZE, askPrice);
        if (walletBase < minBase || minBase > MAX_TARGET_BASE) {
            return;
        }

        uint256 size = between(sizeSeed, minBase, _min(walletBase, MAX_TARGET_BASE));
        uint256 orderId = crystal.placeLimitOrder(address(weth), address(quote), askPrice, size, block.timestamp + 1);
        _recordOrderWithTokens(actor, false, askPrice, orderId, size, address(weth), address(quote));
    }

    function crystal_wrapper_place_eth_sell_limit(uint256 priceSeed, uint256 sizeSeed) public updateGhosts asActor {
        address actor = _getActor();
        (uint256 askPrice, bool askOk) = _nonCrossingAsk(priceSeed);
        if (!askOk || !_canTrackOrder()) {
            return;
        }

        uint256 minBase = _minBaseForQuote(MARKET_MIN_SIZE, askPrice);
        if (minBase == 0 || minBase > MAX_TARGET_BASE || actor.balance < minBase) {
            return;
        }

        uint256 size = between(sizeSeed, minBase, _min(actor.balance, MAX_TARGET_BASE));
        uint256 orderId =
            crystal.placeLimitOrder{ value: size }(crystal.eth(), address(quote), askPrice, size, block.timestamp + 1);
        _recordOrderWithTokens(actor, false, askPrice, orderId, size, crystal.eth(), address(quote));
    }

    function crystal_wrapper_cancel_live_order(uint256 orderSeed) public updateGhosts asActor {
        address actor = _getActor();
        (bool found, uint256 index) = _selectLiveOrderFor(actor, orderSeed);
        if (!found) {
            return;
        }

        TrackedOrder storage order = trackedOrders[index];
        crystal.cancelLimitOrder(order.tokenIn, order.tokenOut, order.price, order.id, block.timestamp + 1);
        order.live = false;
        order.size = 0;
    }

    function crystal_wrapper_replace_live_order(uint256 orderSeed, uint256 priceSeed) public updateGhosts asActor {
        address actor = _getActor();
        (bool found, uint256 index) = _selectLiveOrderFor(actor, orderSeed);
        if (!found) {
            return;
        }

        TrackedOrder memory order = trackedOrders[index];
        (uint256 newPrice, bool ok) = order.isBuy ? _nonCrossingBid(priceSeed) : _nonCrossingAsk(priceSeed);
        if (!ok || newPrice == order.price) {
            return;
        }

        uint256 replacementId = crystal.replaceLimitOrder(
            false,
            false,
            order.tokenIn,
            order.tokenOut,
            order.price,
            order.id,
            newPrice,
            order.size,
            block.timestamp + 1,
            address(0)
        );
        _recordOrder(actor, order.isBuy, newPrice, replacementId, order.size);
        _syncTrackedOrders();
    }

    function crystal_swap_exact_tokens_for_tokens_to_recipient(uint256 recipientSeed, uint256 amountSeed)
        public
        updateGhosts
        asActor
    {
        address actor = _getActor();
        address recipient = _recipient(actor, recipientSeed);
        uint256 walletQuote = quote.balanceOf(actor);
        (uint112 reserveQuote, uint112 reserveBase) = crystal.getReserves(address(market));
        if (walletQuote < MARKET_MIN_SIZE || reserveQuote == 0 || reserveBase == 0) {
            return;
        }

        uint256 maxIn = _min(walletQuote, uint256(reserveQuote) / 100);
        if (maxIn < MARKET_MIN_SIZE) {
            return;
        }

        uint256 amountIn = between(amountSeed, MARKET_MIN_SIZE, maxIn);
        address[] memory path = _path(address(quote), address(weth));
        (uint256[] memory amounts, bool isPartialFill) = crystal.getAmountsOut(amountIn, path);
        if (isPartialFill || amounts.length != 2 || amounts[1] == 0) {
            return;
        }

        crystal.swapExactTokensForTokens(amountIn, amounts[1], path, recipient, block.timestamp + 1, address(0));
    }

    function crystal_swap_tokens_for_exact_tokens_to_recipient(uint256 recipientSeed, uint256 amountSeed)
        public
        updateGhosts
        asActor
    {
        address actor = _getActor();
        address recipient = _recipient(actor, recipientSeed);
        uint256 walletQuote = quote.balanceOf(actor);
        (uint112 reserveQuote, uint112 reserveBase) = crystal.getReserves(address(market));
        if (walletQuote < MARKET_MIN_SIZE || reserveQuote == 0 || reserveBase == 0) {
            return;
        }

        uint256 quotedInput = _min(walletQuote, uint256(reserveQuote) / 100);
        if (quotedInput < MARKET_MIN_SIZE) {
            return;
        }

        address[] memory path = _path(address(quote), address(weth));
        (uint256[] memory amounts, bool isPartialFill) = crystal.getAmountsOut(quotedInput, path);
        if (isPartialFill || amounts.length != 2 || amounts[1] <= 1) {
            return;
        }

        uint256 amountOut = between(amountSeed, 1, amounts[1] / 2);
        uint256[] memory amountsIn = crystal.getAmountsIn(amountOut, path);
        if (amountsIn.length != 2 || amountsIn[0] > walletQuote) {
            return;
        }

        crystal.swapTokensForExactTokens(amountOut, amountsIn[0], path, recipient, block.timestamp + 1, address(0));
    }

    function crystal_swap_exact_eth_for_tokens_to_recipient(uint256 recipientSeed, uint256 amountSeed)
        public
        updateGhosts
        asActor
    {
        address actor = _getActor();
        address recipient = _recipient(actor, recipientSeed);
        if (actor.balance < 1 gwei) {
            return;
        }

        uint256 ethIn = between(amountSeed, 1 gwei, _min(actor.balance, 10 ether));
        address[] memory path = _path(crystal.eth(), address(quote));
        (uint256[] memory amounts, bool isPartialFill) = crystal.getAmountsOut(ethIn, path);
        if (isPartialFill || amounts.length != 2 || amounts[1] == 0) {
            return;
        }

        crystal.swapExactETHForTokens{ value: ethIn }(amounts[1], path, recipient, block.timestamp + 1, address(0));
    }

    function crystal_swap_eth_for_exact_tokens_refund(uint256 recipientSeed, uint256 amountSeed)
        public
        updateGhosts
        asActor
    {
        address actor = _getActor();
        address recipient = _recipient(actor, recipientSeed);
        if (actor.balance < 1 gwei) {
            return;
        }

        uint256 ethProbe = between(amountSeed, 1 gwei, _min(actor.balance, 10 ether));
        address[] memory path = _path(crystal.eth(), address(quote));
        (uint256[] memory amounts, bool isPartialFill) = crystal.getAmountsOut(ethProbe, path);
        if (isPartialFill || amounts.length != 2 || amounts[1] <= 1) {
            return;
        }

        uint256 amountOut = between(amountSeed / 7, 1, amounts[1] / 2);
        uint256[] memory amountsIn = crystal.getAmountsIn(amountOut, path);
        if (amountsIn.length != 2 || amountsIn[0] + 1 gwei > actor.balance) {
            return;
        }

        crystal.swapETHForExactTokens{ value: amountsIn[0] + 1 gwei }(
            amountOut, path, recipient, block.timestamp + 1, address(0)
        );
    }

    function crystal_swap_exact_tokens_for_eth_to_recipient(uint256 recipientSeed, uint256 amountSeed)
        public
        updateGhosts
        asActor
    {
        address actor = _getActor();
        address recipient = _recipient(actor, recipientSeed);
        uint256 walletQuote = quote.balanceOf(actor);
        (uint112 reserveQuote, uint112 reserveBase) = crystal.getReserves(address(market));
        if (walletQuote < MARKET_MIN_SIZE || reserveQuote == 0 || reserveBase == 0) {
            return;
        }

        uint256 maxIn = _min(walletQuote, uint256(reserveQuote) / 100);
        if (maxIn < MARKET_MIN_SIZE) {
            return;
        }

        uint256 amountIn = between(amountSeed, MARKET_MIN_SIZE, maxIn);
        address[] memory path = _path(address(quote), crystal.eth());
        (uint256[] memory amounts, bool isPartialFill) = crystal.getAmountsOut(amountIn, path);
        if (isPartialFill || amounts.length != 2 || amounts[1] == 0) {
            return;
        }

        crystal.swapExactTokensForETH(amountIn, amounts[1], path, recipient, block.timestamp + 1, address(0));
    }

    function crystal_swap_tokens_for_exact_eth_to_recipient(uint256 recipientSeed, uint256 amountSeed)
        public
        updateGhosts
        asActor
    {
        address actor = _getActor();
        address recipient = _recipient(actor, recipientSeed);
        uint256 walletQuote = quote.balanceOf(actor);
        (uint112 reserveQuote, uint112 reserveBase) = crystal.getReserves(address(market));
        if (walletQuote < MARKET_MIN_SIZE || reserveQuote == 0 || reserveBase == 0) {
            return;
        }

        uint256 quotedInput = _min(walletQuote, uint256(reserveQuote) / 100);
        if (quotedInput < MARKET_MIN_SIZE) {
            return;
        }

        address[] memory path = _path(address(quote), crystal.eth());
        (uint256[] memory amounts, bool isPartialFill) = crystal.getAmountsOut(quotedInput, path);
        if (isPartialFill || amounts.length != 2 || amounts[1] <= 1) {
            return;
        }

        uint256 amountOut = between(amountSeed / 3, 1, amounts[1] / 2);
        uint256[] memory amountsIn = crystal.getAmountsIn(amountOut, path);
        if (amountsIn.length != 2 || amountsIn[0] > walletQuote) {
            return;
        }

        crystal.swapTokensForExactETH(amountOut, amountsIn[0], path, recipient, block.timestamp + 1, address(0));
    }

    function crystal_user_id_limit_order(uint256 priceSeed, uint256 sizeSeed) public updateGhosts asActor {
        address actor = _getActor();
        uint256 userId = crystal.addressToUserId(actor);
        if (userId == 0) {
            return;
        }

        uint256 availableQuote = _available(actor, address(quote));
        (uint256 bidPrice, bool bidOk) = _nonCrossingBid(priceSeed);
        if (bidOk && availableQuote >= MARKET_MIN_SIZE) {
            uint256 quoteSize = between(sizeSeed, MARKET_MIN_SIZE, _min(availableQuote, MAX_TARGET_QUOTE));
            uint256 id = crystal.limitOrder(address(market), true, userId, bidPrice, quoteSize, actor);
            _recordOrder(actor, true, bidPrice, id, quoteSize);
        }
        _syncTrackedOrders();
    }

    function crystal_user_id_market_order(uint256 sizeSeed) public updateGhosts asActor {
        address actor = _getActor();
        uint256 userId = crystal.addressToUserId(actor);
        if (userId == 0) {
            return;
        }

        uint256 availableQuote = _available(actor, address(quote));
        ICrystal.MarketInfo memory info = crystal.getMarket(address(market));
        if (info.lowestAsk != 0 && availableQuote >= MARKET_MIN_SIZE) {
            uint256 marketSize = between(sizeSeed / 3, MARKET_MIN_SIZE, _min(availableQuote, MAX_TARGET_QUOTE));
            crystal.marketOrder(
                address(market), true, true, userId, ORDER_TYPES_NORMAL, marketSize, info.lowestAsk, address(0), actor
            );
        }
        _syncTrackedOrders();
    }

    function crystal_internal_balance_buy_limit(uint256 priceSeed, uint256 sizeSeed) public updateGhosts asActor {
        address actor = _getActor();
        uint256 availableQuote = _available(actor, address(quote));
        if (availableQuote < MARKET_MIN_SIZE) {
            return;
        }

        (uint256 bidPrice, bool bidOk) = _nonCrossingBid(priceSeed);
        if (!bidOk) {
            return;
        }

        uint256 quoteSize = between(sizeSeed, MARKET_MIN_SIZE, _min(availableQuote, MAX_TARGET_QUOTE));
        uint256 cloidOption = (1 + (priceSeed % 1_023)) << 44;
        uint256 orderId = crystal.limitOrder(address(market), true, cloidOption | (1 << 44), bidPrice, quoteSize, actor);
        _recordOrder(actor, true, bidPrice, orderId, quoteSize);
        _syncTrackedOrders();
    }

    function crystal_internal_balance_sell_limit(uint256 priceSeed, uint256 sizeSeed) public updateGhosts asActor {
        address actor = _getActor();
        uint256 availableBase = _available(actor, address(weth));
        (uint256 askPrice, bool askOk) = _nonCrossingAsk(priceSeed + 19);
        uint256 minBase = _minBaseForQuote(MARKET_MIN_SIZE, askPrice);
        if (!askOk || minBase == 0 || availableBase < minBase || minBase > MAX_TARGET_BASE) {
            return;
        }

        uint256 baseSize = between(sizeSeed / 3, minBase, _min(availableBase, MAX_TARGET_BASE));
        uint256 cloidOption = (1 + (priceSeed % 1_023)) << 44;
        uint256 orderId = crystal.limitOrder(address(market), false, cloidOption | (1 << 44), askPrice, baseSize, actor);
        _recordOrder(actor, false, askPrice, orderId, baseSize);
        _syncTrackedOrders();
    }

    function crystal_internal_balance_market_buy(uint256 priceSeed, uint256 sizeSeed) public updateGhosts asActor {
        address actor = _getActor();
        ICrystal.MarketInfo memory info = crystal.getMarket(address(market));
        uint256 cloidOption = (1 + (priceSeed % 1_023)) << 44;

        if (info.lowestAsk == 0) {
            return;
        }

        uint256 availableQuote = _available(actor, address(quote));
        if (availableQuote < MARKET_MIN_SIZE) {
            return;
        }

        uint256 amountIn = between(sizeSeed, MARKET_MIN_SIZE, _min(availableQuote, MAX_TARGET_QUOTE));
        crystal.marketOrder(
            address(market),
            true,
            true,
            cloidOption | (1 << 44),
            ORDER_TYPES_NORMAL,
            amountIn,
            info.lowestAsk,
            address(0),
            actor
        );
        _syncTrackedOrders();
    }

    function crystal_internal_balance_market_sell(uint256 priceSeed, uint256 sizeSeed) public updateGhosts asActor {
        address actor = _getActor();
        ICrystal.MarketInfo memory info = crystal.getMarket(address(market));
        if (info.highestBid == 0) {
            return;
        }

        uint256 availableBase = _available(actor, address(weth));
        if (availableBase == 0) {
            return;
        }

        uint256 marketBase = between(sizeSeed, 1, _min(availableBase, MAX_TARGET_BASE));
        uint256 cloidOption = (1 + (priceSeed % 1_023)) << 44;
        crystal.marketOrder(
            address(market),
            false,
            true,
            cloidOption | (1 << 44),
            ORDER_TYPES_NORMAL,
            marketBase,
            info.highestBid,
            address(0),
            actor
        );
        _syncTrackedOrders();
    }

    function crystal_limit_buy_from_internal_balance(uint256 priceSeed, uint256 sizeSeed) public updateGhosts asActor {
        address actor = _getActor();
        uint256 availableQuote = _available(actor, address(quote));
        if (availableQuote < MARKET_MIN_SIZE || !_canTrackOrder()) {
            return;
        }

        (uint256 bidPrice, bool bidOk) = _nonCrossingBid(priceSeed);
        if (!bidOk) {
            return;
        }

        uint256 quoteSize = between(sizeSeed, MARKET_MIN_SIZE, _min(availableQuote, MAX_TARGET_QUOTE));
        uint256 orderId = crystal.limitOrder(address(market), true, 1 << 68, bidPrice, quoteSize, actor);
        _recordOrder(actor, true, bidPrice, orderId, quoteSize);
        _syncTrackedOrders();
    }

    function crystal_limit_sell_from_internal_balance(uint256 priceSeed, uint256 sizeSeed) public updateGhosts asActor {
        address actor = _getActor();
        uint256 availableBase = _available(actor, address(weth));
        (uint256 askPrice, bool askOk) = _nonCrossingAsk(priceSeed);
        if (!askOk || !_canTrackOrder()) {
            return;
        }

        uint256 minBase = _minBaseForQuote(MARKET_MIN_SIZE, askPrice);
        if (availableBase < minBase || minBase > MAX_TARGET_BASE) {
            return;
        }

        uint256 baseSize = between(sizeSeed, minBase, _min(availableBase, MAX_TARGET_BASE));
        uint256 orderId = crystal.limitOrder(address(market), false, 1 << 68, askPrice, baseSize, actor);
        _recordOrder(actor, false, askPrice, orderId, baseSize);
        _syncTrackedOrders();
    }

    function crystal_market_buy_from_internal_balance(uint256 sizeSeed) public updateGhosts asActor {
        address actor = _getActor();
        ICrystal.MarketInfo memory info = crystal.getMarket(address(market));
        uint256 availableQuote = _available(actor, address(quote));
        if (info.lowestAsk == 0 || availableQuote < MARKET_MIN_SIZE) {
            return;
        }

        uint256 amountIn = between(sizeSeed, MARKET_MIN_SIZE, _min(availableQuote, MAX_TARGET_QUOTE));
        crystal.marketOrder(
            address(market), true, true, 1 << 68, ORDER_TYPES_NORMAL, amountIn, info.lowestAsk, address(0), actor
        );
        _syncTrackedOrders();
    }

    function crystal_market_sell_from_internal_balance(uint256 sizeSeed) public updateGhosts asActor {
        address actor = _getActor();
        ICrystal.MarketInfo memory info = crystal.getMarket(address(market));
        if (info.highestBid == 0) {
            return;
        }

        uint256 availableBase = _available(actor, address(weth));
        uint256 minBase = _minBaseForQuote(MARKET_MIN_SIZE, info.highestBid);
        if (availableBase < minBase || minBase > MAX_TARGET_BASE) {
            return;
        }

        uint256 amountIn = between(sizeSeed, minBase, _min(availableBase, MAX_TARGET_BASE));
        crystal.marketOrder(
            address(market), false, true, 1 << 68, ORDER_TYPES_NORMAL, amountIn, info.highestBid, address(0), actor
        );
        _syncTrackedOrders();
    }

    function crystal_maker_internal_settlement_limit(uint256 priceSeed, uint256 sizeSeed) public updateGhosts asActor {
        address actor = _getActor();
        uint256 availableBase = _available(actor, address(weth));
        (uint256 askPrice, bool askOk) = _nonCrossingAsk(priceSeed);
        uint256 minBase = _minBaseForQuote(MARKET_MIN_SIZE, askPrice);
        if (!askOk || availableBase < minBase || minBase > MAX_TARGET_BASE) {
            return;
        }

        uint256 size = between(sizeSeed, minBase, _min(availableBase, MAX_TARGET_BASE));
        uint256 orderId = crystal.limitOrder(address(market), false, 1 << 60, askPrice, size, actor);
        _recordOrder(actor, false, askPrice, orderId, size);
        _syncTrackedOrders();
    }

    function crystal_cloid_buy_limit(uint256 priceSeed, uint256 sizeSeed) public updateGhosts asActor {
        address actor = _getActor();
        uint256 availableQuote = _available(actor, address(quote));
        if (availableQuote < MARKET_MIN_SIZE || !_canTrackOrder()) {
            return;
        }

        (uint256 bidPrice, bool bidOk) = _nonCrossingBid(priceSeed);
        if (!bidOk) {
            return;
        }

        uint256 size = between(sizeSeed, MARKET_MIN_SIZE, _min(availableQuote, MAX_TARGET_QUOTE));
        uint256 cloid = 1 + (priceSeed % 1_023);
        uint256 orderId = crystal.limitOrder(address(market), true, cloid << 44, bidPrice, size, actor);
        _recordOrderWithCloid(actor, true, bidPrice, orderId, cloid, size);
        _syncTrackedOrders();
    }

    function crystal_cloid_sell_limit(uint256 priceSeed, uint256 sizeSeed) public updateGhosts asActor {
        address actor = _getActor();
        uint256 availableBase = _available(actor, address(weth));

        (uint256 askPrice, bool askOk) = _nonCrossingAsk(priceSeed);
        if (!askOk || !_canTrackOrder()) {
            return;
        }

        uint256 minBase = _minBaseForQuote(MARKET_MIN_SIZE, askPrice);
        if (availableBase < minBase || minBase > MAX_TARGET_BASE) {
            return;
        }

        uint256 size = between(sizeSeed, minBase, _min(availableBase, MAX_TARGET_BASE));
        uint256 cloid = 1 + (priceSeed % 1_023);
        uint256 orderId = crystal.limitOrder(address(market), false, cloid << 44, askPrice, size, actor);
        _recordOrderWithCloid(actor, false, askPrice, orderId, cloid, size);
        _syncTrackedOrders();
    }

    function crystal_batch_cloid_buy_limit(uint256 priceSeed, uint256 sizeSeed) public updateGhosts asActor {
        address actor = _getActor();
        uint256 availableQuote = _available(actor, address(quote));
        if (availableQuote < MARKET_MIN_SIZE || !_canTrackOrder()) {
            return;
        }

        (uint256 bidPrice, bool bidOk) = _nonCrossingBid(priceSeed);
        if (!bidOk) {
            return;
        }

        uint256 size = between(sizeSeed, MARKET_MIN_SIZE, _min(availableQuote, MAX_TARGET_QUOTE));
        uint256 cloid = 1 + (priceSeed % 1_023);
        crystal.batchOrders(
            address(market),
            _singleAction(BatchAction.BuyLimit, bidPrice, size, cloid),
            0,
            block.timestamp,
            address(0),
            actor
        );
        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), bidPrice);
        _recordOrderWithCloid(actor, true, bidPrice, level.latestNativeId, cloid, size);
        _syncTrackedOrders();
    }

    function crystal_batch_cloid_sell_limit(uint256 priceSeed, uint256 sizeSeed) public updateGhosts asActor {
        address actor = _getActor();
        uint256 availableBase = _available(actor, address(weth));
        (uint256 askPrice, bool askOk) = _nonCrossingAsk(priceSeed);
        if (!askOk || !_canTrackOrder()) {
            return;
        }

        uint256 minBase = _minBaseForQuote(MARKET_MIN_SIZE, askPrice);
        if (availableBase < minBase || minBase > MAX_TARGET_BASE) {
            return;
        }

        uint256 size = between(sizeSeed, minBase, _min(availableBase, MAX_TARGET_BASE));
        uint256 cloid = 1 + (priceSeed % 1_023);
        crystal.batchOrders(
            address(market),
            _singleAction(BatchAction.SellLimit, askPrice, size, cloid),
            0,
            block.timestamp,
            address(0),
            actor
        );
        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), askPrice);
        _recordOrderWithCloid(actor, false, askPrice, level.latestNativeId, cloid, size);
        _syncTrackedOrders();
    }

    function crystal_write_cloid_slots(uint256 firstSeed, uint256 secondSeed) public updateGhosts asActor {
        uint256 userId = crystal.addressToUserId(_getActor());
        if (userId == 0) {
            return;
        }

        uint256[] memory ids = new uint256[](3);
        ids[0] = 1 + (firstSeed % 1_023);
        ids[1] = 1 + (secondSeed % 1_023);
        ids[2] = 1_024 + (firstSeed % 32);
        ICrystalSlotWriter(address(crystal)).writeCloidSlots(userId, ids);
    }

    function crystal_clear_cloid_slots(uint256 firstSeed, uint256 secondSeed) public updateGhosts asActor {
        uint256 userId = crystal.addressToUserId(_getActor());
        if (userId == 0) {
            return;
        }

        uint256[] memory ids = new uint256[](2);
        ids[0] = 1 + (firstSeed % 1_023);
        ids[1] = 1 + (secondSeed % 1_023);
        crystal.clearCloidSlots(userId, ids);
    }

    function crystal_write_market_slots(uint256 bidSeed, uint256 askSeed) public updateGhosts asActor {
        uint256[] memory bidIds = new uint256[](2);
        uint256[] memory askIds = new uint256[](2);
        bidIds[0] = 1 + (bidSeed % 1_023);
        bidIds[1] = 1_024 + (bidSeed % 32);
        askIds[0] = 1 + (askSeed % 1_023);
        askIds[1] = 1_024 + (askSeed % 32);
        ICrystalSlotWriter(address(crystal)).writeSlots(address(market), bidIds, askIds);
    }

    function crystal_lp_approve_secondary(uint256 amountSeed) public updateGhosts asActor {
        address actor = _getActor();
        address spender = _secondaryActor(actor);
        uint256 liquidity = market.balanceOf(actor);
        if (liquidity == 0) {
            return;
        }

        uint256 amount = between(amountSeed, 1, liquidity);
        market.approve(spender, amount);
    }

    function crystal_lp_transfer_from_secondary(uint256 amountSeed) public updateGhosts asActor {
        address spender = _getActor();
        address owner = _secondaryActor(spender);
        uint256 allowance = market.allowance(owner, spender);
        uint256 balance = market.balanceOf(owner);
        uint256 maxAmount = _min(allowance, balance);
        if (maxAmount == 0) {
            return;
        }

        uint256 amount = between(amountSeed, 1, maxAmount);
        market.transferFrom(owner, spender, amount);
    }

    function launchpad_token_transfer_from_secondary(uint256 tokenSeed, uint256 amountSeed)
        public
        updateGhosts
        asActor
    {
        if (trackedLaunchpadTokens.length == 0) {
            return;
        }

        address spender = _getActor();
        address owner = _secondaryActor(spender);
        address token = _trackedLaunchpadToken(tokenSeed);
        uint256 allowance = IERC20(token).allowance(owner, spender);
        uint256 balance = IERC20(token).balanceOf(owner);
        uint256 maxAmount = _min(allowance, balance);
        if (maxAmount == 0) {
            return;
        }

        uint256 amount = between(amountSeed, 1, maxAmount);
        IERC20(token).transferFrom(owner, spender, amount);
    }

    function launchpad_token_transfer(uint256 tokenSeed, uint256 amountSeed, uint256 recipientSeed)
        public
        updateGhosts
        asActor
    {
        if (trackedLaunchpadTokens.length == 0) {
            return;
        }

        address actor = _getActor();
        address token = _trackedLaunchpadToken(tokenSeed);
        uint256 tokenBalance = IERC20(token).balanceOf(actor);
        if (tokenBalance == 0) {
            return;
        }

        uint256 transferAmount = between(amountSeed, 1, tokenBalance);
        IERC20(token).transfer(_recipient(actor, recipientSeed), transferAmount);
    }

    function launchpad_token_approve_secondary(uint256 tokenSeed, uint256 amountSeed) public updateGhosts asActor {
        if (trackedLaunchpadTokens.length == 0) {
            return;
        }

        address actor = _getActor();
        address token = _trackedLaunchpadToken(tokenSeed);
        uint256 tokenBalance = IERC20(token).balanceOf(actor);
        if (tokenBalance == 0) {
            return;
        }

        uint256 spendAmount = between(amountSeed, 1, tokenBalance);
        IERC20(token).approve(_secondaryActor(actor), spendAmount);
    }

    function launchpad_token_approve_crystal(uint256 tokenSeed, uint256 amountSeed) public updateGhosts asActor {
        if (trackedLaunchpadTokens.length == 0) {
            return;
        }

        address actor = _getActor();
        address token = _trackedLaunchpadToken(tokenSeed);
        uint256 tokenBalance = IERC20(token).balanceOf(actor);
        if (tokenBalance == 0) {
            return;
        }

        uint256 spendAmount = between(amountSeed, 1, tokenBalance);
        IERC20(token).approve(address(crystal), spendAmount);
    }

    function launchpad_token_permit(uint256 tokenSeed, uint256 valueSeed) public updateGhosts asActor {
        if (trackedLaunchpadTokens.length == 0) {
            return;
        }

        address spender = _getActor();
        address token = _trackedLaunchpadToken(tokenSeed);
        uint256 value = valueSeed % (MAX_TARGET_QUOTE * 1e12);
        uint256 deadline = block.timestamp + 30 days;
        _permitSignerApproval(token, spender, value, deadline);
    }

    function _permitSignerApproval(address token, address spender, uint256 value, uint256 deadline) internal {
        uint256 nonce = IERC20(token).nonces(permitSigner);
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                permitSigner,
                spender,
                value,
                nonce,
                deadline
            )
        );
        bytes32 digest =
            keccak256(abi.encodePacked("\x19\x01", ICrystalTokenPermitMetadata(token).DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PERMIT_SIGNER_KEY, digest);

        IERC20(token).permit(permitSigner, spender, value, deadline, v, r, s);
    }

    function launchpad_token_permit_signer_transfer_from(uint256 tokenSeed, uint256 amountSeed, uint256 recipientSeed)
        public
        updateGhosts
        asActor
    {
        if (trackedLaunchpadTokens.length == 0) {
            return;
        }

        address spender = _getActor();
        address token = _trackedLaunchpadToken(tokenSeed);
        uint256 allowance = IERC20(token).allowance(permitSigner, spender);
        uint256 balance = IERC20(token).balanceOf(permitSigner);
        uint256 maxAmount = _min(allowance, balance);
        if (maxAmount == 0) {
            return;
        }

        uint256 amount = between(amountSeed, 1, maxAmount);
        IERC20(token).transferFrom(permitSigner, _recipient(spender, recipientSeed), amount);
    }

    function crystal_payable_batch_sell_limit(uint256 priceSeed, uint256 sizeSeed) public updateGhosts asActor {
        address actor = _getActor();
        if (actor.balance < 1 gwei || !_canTrackOrder()) {
            return;
        }

        (uint256 askPrice, bool askOk) = _nonCrossingAsk(priceSeed);
        if (!askOk) {
            return;
        }

        uint256 minBase = _minBaseForQuote(MARKET_MIN_SIZE, askPrice);
        if (minBase == 0 || minBase > MAX_TARGET_BASE || actor.balance < minBase) {
            return;
        }

        uint256 size = between(sizeSeed, minBase, _min(actor.balance, MAX_TARGET_BASE));
        crystal.batchOrders{ value: size + 1 gwei }(
            address(market),
            _singleAction(BatchAction.SellLimit, askPrice, size, 0),
            1 << 48,
            block.timestamp + 1,
            address(0),
            actor
        );
        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), askPrice);
        _recordOrder(actor, false, askPrice, level.latestNativeId, size);
    }

    function crystal_payable_multibatch_sell_limit(uint256 priceSeed, uint256 sizeSeed) public updateGhosts asActor {
        address actor = _getActor();
        if (actor.balance < 1 gwei || !_canTrackOrder()) {
            return;
        }

        (uint256 askPrice, bool askOk) = _nonCrossingAsk(priceSeed);
        if (!askOk) {
            return;
        }

        uint256 minBase = _minBaseForQuote(MARKET_MIN_SIZE, askPrice);
        if (minBase == 0 || minBase > MAX_TARGET_BASE || actor.balance < minBase) {
            return;
        }

        uint256 size = between(sizeSeed, minBase, _min(actor.balance, MAX_TARGET_BASE));
        ICrystal.Batch[] memory batches = new ICrystal.Batch[](1);
        batches[0] = ICrystal.Batch({
            market: address(market), actions: _singleAction(BatchAction.SellLimit, askPrice, size, 0), options: 1 << 48
        });
        crystal.multiBatchOrders{ value: size + 1 gwei }(batches, block.timestamp + 1, address(0));
        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), askPrice);
        _recordOrder(actor, false, askPrice, level.latestNativeId, size);
    }

    function crystal_batch_market_to_limit_buy(uint256 priceSeed, uint256 sizeSeed) public updateGhosts asActor {
        address actor = _getActor();
        uint256 walletQuote = quote.balanceOf(actor);
        ICrystal.MarketInfo memory info = crystal.getMarket(address(market));
        if (info.lowestAsk == 0 || walletQuote < MARKET_MIN_SIZE || !_canTrackOrder()) {
            return;
        }

        uint256 price = _min(MARKET_MAX_PRICE, info.lowestAsk + (priceSeed % _price(250)));
        uint256 size = between(sizeSeed, MARKET_MIN_SIZE, _min(walletQuote, MAX_TARGET_QUOTE));
        crystal.batchOrders(
            address(market),
            _singleAction(BatchAction.MarketToLimitBuy, price, size, 0),
            0,
            block.timestamp + 1,
            address(0),
            actor
        );
        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);
        _recordOrder(actor, true, price, level.latestNativeId, size);
    }

    function crystal_batch_market_to_limit_sell(uint256 priceSeed, uint256 sizeSeed) public updateGhosts asActor {
        address actor = _getActor();
        ICrystal.MarketInfo memory info = crystal.getMarket(address(market));
        if (info.highestBid == 0 || !_canTrackOrder()) {
            return;
        }

        uint256 price = info.highestBid;
        if (priceSeed % 2 == 0 && price > MARKET_TICK_SIZE) {
            price -= 1;
        }
        uint256 minBase = _minBaseForQuote(MARKET_MIN_SIZE, price);
        if (minBase == 0 || minBase > MAX_TARGET_BASE) {
            return;
        }

        uint256 walletBase = weth.balanceOf(actor);
        if (walletBase < minBase) {
            return;
        }

        uint256 size = between(sizeSeed, minBase, _min(walletBase, MAX_TARGET_BASE));
        crystal.batchOrders(
            address(market),
            _singleAction(BatchAction.MarketToLimitSell, price, size, 0),
            0,
            block.timestamp + 1,
            address(0),
            actor
        );
        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);
        _recordOrder(actor, false, price, level.latestNativeId, size);
    }

    function crystal_batch_partial_buy(uint256 priceSeed, uint256 sizeSeed) public updateGhosts asActor {
        _batchBuyTakerAction(BatchAction.PartialBuy, priceSeed, sizeSeed);
    }

    function crystal_batch_gas_aware_partial_buy(uint256 priceSeed, uint256 sizeSeed) public updateGhosts asActor {
        _batchBuyTakerAction(BatchAction.GasAwarePartialBuy, priceSeed, sizeSeed);
    }

    function crystal_batch_complete_buy(uint256 priceSeed, uint256 sizeSeed) public updateGhosts asActor {
        _batchBuyTakerAction(BatchAction.CompleteBuy, priceSeed, sizeSeed);
    }

    function crystal_batch_partial_sell(uint256 priceSeed, uint256 sizeSeed) public updateGhosts asActor {
        _batchSellTakerAction(BatchAction.PartialSell, priceSeed, sizeSeed);
    }

    function crystal_batch_gas_aware_partial_sell(uint256 priceSeed, uint256 sizeSeed) public updateGhosts asActor {
        _batchSellTakerAction(BatchAction.GasAwarePartialSell, priceSeed, sizeSeed);
    }

    function crystal_batch_complete_sell(uint256 priceSeed, uint256 sizeSeed) public updateGhosts asActor {
        _batchSellTakerAction(BatchAction.CompleteSell, priceSeed, sizeSeed);
    }

    function _batchBuyTakerAction(BatchAction action, uint256 priceSeed, uint256 sizeSeed) internal {
        address actor = _getActor();
        ICrystal.MarketInfo memory info = crystal.getMarket(address(market));
        if (info.lowestAsk == 0 || quote.balanceOf(actor) < MARKET_MIN_SIZE) {
            return;
        }

        uint256 quoteIn = between(sizeSeed / 13, MARKET_MIN_SIZE, _min(quote.balanceOf(actor), MAX_TARGET_QUOTE));
        if (priceSeed % 2 == 0) {
            quoteIn = _min(quoteIn, MARKET_MIN_SIZE * 2);
        }
        if (quoteIn < MARKET_MIN_SIZE) {
            return;
        }
        crystal.batchOrders(
            address(market),
            _singleAction(action, info.lowestAsk, quoteIn, 0),
            0,
            block.timestamp + 1,
            address(0),
            actor
        );
        _syncTrackedOrders();
    }

    function crystal_batch_buy_limit_from_internal_balance(uint256 priceSeed, uint256 sizeSeed)
        public
        updateGhosts
        asActor
    {
        address actor = _getActor();
        uint256 userId = crystal.addressToUserId(actor);
        uint256 availableQuote = _available(actor, address(quote));
        if (userId == 0 || availableQuote < MARKET_MIN_SIZE || !_canTrackOrder()) {
            return;
        }

        (uint256 price, bool ok) = _nonCrossingBid(priceSeed);
        if (!ok) {
            return;
        }

        uint256 size = between(sizeSeed, MARKET_MIN_SIZE, _min(availableQuote, MAX_TARGET_QUOTE));
        crystal.batchOrders(
            address(market),
            _singleAction(BatchAction.BuyLimit, price, size, 0),
            userId | (1 << 44),
            block.timestamp,
            address(0),
            actor
        );
        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);
        _recordOrder(actor, true, price, level.latestNativeId, size);
        _syncTrackedOrders();
    }

    function crystal_batch_sell_limit_from_internal_balance(uint256 priceSeed, uint256 sizeSeed)
        public
        updateGhosts
        asActor
    {
        address actor = _getActor();
        uint256 userId = crystal.addressToUserId(actor);
        uint256 availableBase = _available(actor, address(weth));
        (uint256 price, bool ok) = _nonCrossingAsk(priceSeed);
        if (userId == 0 || !ok || !_canTrackOrder()) {
            return;
        }

        uint256 minBase = _minBaseForQuote(MARKET_MIN_SIZE, price);
        if (availableBase < minBase || minBase > MAX_TARGET_BASE) {
            return;
        }

        uint256 size = between(sizeSeed, minBase, _min(availableBase, MAX_TARGET_BASE));
        crystal.batchOrders(
            address(market),
            _singleAction(BatchAction.SellLimit, price, size, 0),
            userId | (1 << 44),
            block.timestamp,
            address(0),
            actor
        );
        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);
        _recordOrder(actor, false, price, level.latestNativeId, size);
        _syncTrackedOrders();
    }

    function _batchSellTakerAction(BatchAction action, uint256 priceSeed, uint256 sizeSeed) internal {
        address actor = _getActor();
        ICrystal.MarketInfo memory info = crystal.getMarket(address(market));
        if (info.highestBid == 0 || weth.balanceOf(actor) == 0) {
            return;
        }

        uint256 minBase = _minBaseForQuote(MARKET_MIN_SIZE, info.highestBid);
        if (minBase == 0 || minBase > MAX_TARGET_BASE || weth.balanceOf(actor) < minBase) {
            return;
        }

        uint256 maxBaseIn =
            _min(_minBaseForQuote(MARKET_MIN_SIZE * 3, info.highestBid), _min(weth.balanceOf(actor), MAX_TARGET_BASE));
        if (maxBaseIn < minBase) {
            return;
        }

        uint256 baseIn = between(sizeSeed / 17, minBase, maxBaseIn);
        crystal.batchOrders(
            address(market),
            _singleAction(action, info.highestBid, baseIn, 0),
            0,
            block.timestamp + 1,
            address(0),
            actor
        );
        _syncTrackedOrders();
    }

    function vault_deploy(uint256 quoteSeed, uint256 baseSeed, uint256 metadataSeed) public updateGhosts asActor {
        if (trackedVaults.length >= MAX_TRACKED_VAULTS) {
            return;
        }

        address actor = _getActor();
        uint256 quoteWallet = quote.balanceOf(actor);
        uint256 baseWallet = weth.balanceOf(actor);
        if (quoteWallet < MARKET_MIN_SIZE || baseWallet < 1 gwei) {
            return;
        }

        uint256 amountQuote = between(quoteSeed, MARKET_MIN_SIZE, _min(quoteWallet, MAX_TARGET_QUOTE));
        uint256 amountBase = between(baseSeed, 1 gwei, _min(baseWallet, MAX_TARGET_BASE));
        _deployVault(amountQuote, amountBase, metadataSeed);
    }

    function _deployVault(uint256 amountQuote, uint256 amountBase, uint256 metadataSeed) internal {
        _recordVault(
            vaultFactory.deploy(
                address(quote), address(weth), amountQuote, amountBase, 0, 0, false, _metadata(metadataSeed)
            )
        );
    }

    function vault_deposit(uint256 vaultSeed, uint256 quoteSeed, uint256 baseSeed) public updateGhosts asActor {
        if (trackedVaults.length == 0) {
            return;
        }

        address actor = _getActor();
        address vault = _trackedVault(vaultSeed);
        ICrystalVault vaultToken = ICrystalVault(vault);
        if (vaultToken.locked() || vaultToken.closed()) {
            return;
        }

        uint256 quoteWallet = quote.balanceOf(actor);
        uint256 baseWallet = weth.balanceOf(actor);
        if (quoteWallet < MARKET_MIN_SIZE || baseWallet < 1 gwei) {
            return;
        }

        uint256 quoteDesired = between(quoteSeed, MARKET_MIN_SIZE, _min(quoteWallet, MAX_TARGET_QUOTE));
        uint256 baseDesired = between(baseSeed, 1 gwei, _min(baseWallet, MAX_TARGET_BASE));
        (uint256 shares, uint256 quoteAmount, uint256 baseAmount) =
            vaultFactory.previewDeposit(vault, quoteDesired, baseDesired);
        if (shares == 0) {
            return;
        }
        vaultFactory.deposit(vault, address(quote), address(weth), quoteDesired, baseDesired, quoteAmount, baseAmount);
    }

    function vault_withdraw(uint256 vaultSeed, uint256 shareSeed) public updateGhosts asActor {
        if (trackedVaults.length == 0) {
            return;
        }

        address actor = _getActor();
        address vault = _trackedVault(vaultSeed);
        ICrystalVault vaultToken = ICrystalVault(vault);
        uint256 shares = vaultToken.balanceOf(actor);
        if (shares == 0 || vaultToken.closed()) {
            return;
        }

        uint256 sharesToWithdraw = between(shareSeed, 1, shares);
        (uint256 quoteAmount, uint256 baseAmount) = vaultFactory.previewWithdrawal(vault, sharesToWithdraw);
        vaultFactory.withdraw(vault, address(quote), address(weth), sharesToWithdraw, quoteAmount, baseAmount);
    }

    function vault_close(uint256 vaultSeed) public updateGhosts asActor {
        if (trackedVaults.length == 0) {
            return;
        }

        address vault = _trackedVault(vaultSeed);
        ICrystalVault vaultToken = ICrystalVault(vault);
        if (vaultToken.closed() || vaultToken.owner() != _getActor()) {
            return;
        }

        vaultFactory.close(vault);
    }

    function vault_change_max_shares(uint256 vaultSeed, uint256 paramSeed) public updateGhosts asActor {
        if (trackedVaults.length == 0) {
            return;
        }

        address vault = _trackedVault(vaultSeed);
        ICrystalVault vaultToken = ICrystalVault(vault);
        if (vaultToken.owner() != _getActor()) {
            return;
        }

        vaultFactory.changeMaxShares(vault, MARKET_MIN_SIZE * (2 + (paramSeed % 128)));
    }

    function vault_change_lockup(uint256 vaultSeed, uint256 paramSeed) public updateGhosts asActor {
        if (trackedVaults.length == 0) {
            return;
        }

        address vault = _trackedVault(vaultSeed);
        ICrystalVault vaultToken = ICrystalVault(vault);
        if (vaultToken.owner() != _getActor()) {
            return;
        }

        vaultFactory.changeLockup(vault, uint40(paramSeed % 3 days));
    }

    function vault_change_order_cap(uint256 vaultSeed, uint256 paramSeed) public updateGhosts asActor {
        if (trackedVaults.length == 0) {
            return;
        }

        address vault = _trackedVault(vaultSeed);
        ICrystalVault vaultToken = ICrystalVault(vault);
        if (vaultToken.owner() != _getActor()) {
            return;
        }

        vaultFactory.changeOrderCap(vault, uint16(1 + (paramSeed % VAULT_MAX_ORDER_CAP)));
    }

    function vault_change_decrease_on_withdraw(uint256 vaultSeed, uint256 paramSeed) public updateGhosts asActor {
        if (trackedVaults.length == 0) {
            return;
        }

        address vault = _trackedVault(vaultSeed);
        ICrystalVault vaultToken = ICrystalVault(vault);
        if (vaultToken.owner() != _getActor()) {
            return;
        }

        vaultFactory.changeDecreaseOnWithdraw(vault, paramSeed % 2 == 0);
    }

    function vault_lock(uint256 vaultSeed) public updateGhosts asActor {
        if (trackedVaults.length == 0) {
            return;
        }

        address vault = _trackedVault(vaultSeed);
        ICrystalVault vaultToken = ICrystalVault(vault);
        if (vaultToken.owner() != _getActor() || vaultToken.locked()) {
            return;
        }

        vaultFactory.lock(vault);
    }

    function vault_unlock(uint256 vaultSeed) public updateGhosts asActor {
        if (trackedVaults.length == 0) {
            return;
        }

        address vault = _trackedVault(vaultSeed);
        ICrystalVault vaultToken = ICrystalVault(vault);
        if (vaultToken.owner() != _getActor() || !vaultToken.locked()) {
            return;
        }

        vaultFactory.unlock(vault);
    }

    function vault_change_market(uint256 vaultSeed) public updateGhosts asActor {
        if (trackedVaults.length == 0) {
            return;
        }

        address vault = _trackedVault(vaultSeed);
        ICrystalVault vaultToken = ICrystalVault(vault);
        if (vaultToken.owner() != _getActor()) {
            return;
        }

        vaultFactory.changeMarket(vault);
    }

    function vault_claim_fees(uint256 vaultSeed) public updateGhosts asActor {
        if (trackedVaults.length == 0) {
            return;
        }

        address vault = _trackedVault(vaultSeed);
        ICrystalVault vaultToken = ICrystalVault(vault);
        if (vaultToken.owner() != _getActor()) {
            return;
        }

        address[] memory feeTokens = _tokens(vaultToken.quoteAsset(), vaultToken.baseAsset());
        vaultFactory.claimFees(vault, feeTokens);
    }

    function vault_clear_cloid_slots(uint256 vaultSeed, uint256 paramSeed) public updateGhosts asActor {
        if (trackedVaults.length == 0) {
            return;
        }

        address vault = _trackedVault(vaultSeed);
        ICrystalVault vaultToken = ICrystalVault(vault);
        if (vaultToken.owner() != _getActor()) {
            return;
        }

        uint256[] memory ids = new uint256[](2);
        ids[0] = 1 + (paramSeed % 32);
        ids[1] = 64 + (paramSeed % 64);
        vaultFactory.clearCloidSlots(vault, crystal.addressToUserId(vault), ids);
    }

    function launchpad_create_token(uint256 metadataSeed) public updateGhosts asActor {
        if (trackedLaunchpadTokens.length >= MAX_TRACKED_LAUNCHPAD_TOKENS) {
            return;
        }

        address actor = _getActor();
        if (actor.balance < LAUNCHPAD_FEE) {
            return;
        }

        string memory suffix = _smallUintString(metadataSeed % 1_000_000);
        address token = crystal.createToken{ value: LAUNCHPAD_FEE }(
            string.concat("Recon Token ", suffix),
            string.concat("RT", suffix),
            "recon",
            "stateful invariant token",
            "",
            "",
            "",
            ""
        );
        _recordLaunchpadToken(token);
    }

    function launchpad_buy(uint256 tokenSeed, uint256 amountSeed) public updateGhosts asActor {
        if (trackedLaunchpadTokens.length == 0) {
            return;
        }

        address actor = _getActor();
        address token = _trackedLaunchpadToken(tokenSeed);
        if (actor.balance < 1 gwei) {
            return;
        }

        uint256 amountIn = between(amountSeed, 1 gwei, _min(actor.balance, SETUP_ETH_BALANCE));
        crystal.buy{ value: amountIn }(true, token, amountIn, 0);
    }

    function launchpad_sell(uint256 tokenSeed, uint256 amountSeed) public updateGhosts asActor {
        if (trackedLaunchpadTokens.length == 0) {
            return;
        }

        address actor = _getActor();
        address token = _trackedLaunchpadToken(tokenSeed);
        uint256 tokenBalance = IERC20(token).balanceOf(actor);
        if (tokenBalance == 0) {
            return;
        }

        uint256 amountIn = between(amountSeed, 1, tokenBalance);
        crystal.sell(true, token, amountIn, 0);
    }

    function launchpad_buy_exact_output(uint256 tokenSeed, uint256 amountSeed, uint256 outputSeed)
        public
        updateGhosts
        asActor
    {
        if (trackedLaunchpadTokens.length == 0) {
            return;
        }

        address actor = _getActor();
        address token = _trackedLaunchpadToken(tokenSeed);
        if (actor.balance < 1 gwei) {
            return;
        }

        uint256 nativeProbe = between(amountSeed, 1 gwei, _min(actor.balance, 10 ether));
        (, uint256 quotedTokens,) = crystal.quoteBuy(true, token, nativeProbe, 0);
        if (quotedTokens <= 1) {
            return;
        }

        uint256 desiredOut = between(outputSeed, 1, quotedTokens / 2);
        (uint256 neededNative,,) = crystal.quoteBuy(false, token, 0, desiredOut);
        if (neededNative == 0 || neededNative > actor.balance) {
            return;
        }

        crystal.buy{ value: neededNative }(false, token, neededNative, desiredOut);
    }

    function launchpad_quote_buy(uint256 tokenSeed, uint256 amountSeed) public updateGhosts asActor {
        if (trackedLaunchpadTokens.length == 0) {
            return;
        }

        address token = _trackedLaunchpadToken(tokenSeed);
        uint256 amountIn = between(amountSeed, 1 gwei, SETUP_ETH_BALANCE);
        crystal.quoteBuy(true, token, amountIn, 0);
    }

    function launchpad_quote_buy_exact_output(uint256 tokenSeed, uint256 amountSeed) public updateGhosts asActor {
        if (trackedLaunchpadTokens.length == 0) {
            return;
        }

        address token = _trackedLaunchpadToken(tokenSeed);
        (, uint256 virtualTokenReserve) = crystal.getVirtualReserves(token);
        uint256 maxOut = virtualTokenReserve == 0 ? MAX_TARGET_BASE : _min(virtualTokenReserve, MAX_TARGET_BASE);
        if (maxOut == 0) {
            return;
        }

        uint256 amountOut = between(amountSeed, 1, maxOut);
        crystal.quoteBuy(false, token, 0, amountOut);
    }

    function launchpad_quote_sell(uint256 tokenSeed, uint256 amountSeed) public updateGhosts asActor {
        if (trackedLaunchpadTokens.length == 0) {
            return;
        }

        address token = _trackedLaunchpadToken(tokenSeed);
        (, uint256 virtualTokenReserve) = crystal.getVirtualReserves(token);
        uint256 maxIn = virtualTokenReserve == 0 ? MAX_TARGET_BASE : _min(virtualTokenReserve, MAX_TARGET_BASE);
        if (maxIn == 0) {
            return;
        }

        uint256 amountIn = between(amountSeed, 1, maxIn);
        crystal.quoteSell(true, token, amountIn, 0);
    }

    function launchpad_quote_sell_exact_output(uint256 tokenSeed, uint256 amountSeed) public updateGhosts asActor {
        if (trackedLaunchpadTokens.length == 0) {
            return;
        }

        address token = _trackedLaunchpadToken(tokenSeed);
        (uint256 virtualNativeReserve,) = crystal.getVirtualReserves(token);
        uint256 maxOut = virtualNativeReserve == 0 ? MAX_TARGET_BASE : _min(virtualNativeReserve, MAX_TARGET_BASE);
        if (maxOut == 0) {
            return;
        }

        uint256 amountOut = between(amountSeed, 1, maxOut);
        crystal.quoteSell(false, token, 0, amountOut);
    }

    function launchpad_sell_exact_output(uint256 tokenSeed, uint256 amountSeed) public updateGhosts asActor {
        if (trackedLaunchpadTokens.length == 0) {
            return;
        }

        address actor = _getActor();
        address token = _trackedLaunchpadToken(tokenSeed);
        uint256 tokenBalance = IERC20(token).balanceOf(actor);
        if (tokenBalance == 0) {
            return;
        }

        uint256 probeIn = between(amountSeed, 1, tokenBalance);
        (, uint256 maxNativeOut) = crystal.quoteSell(true, token, probeIn, 0);
        if (maxNativeOut <= 1) {
            return;
        }

        uint256 nativeOut = between(amountSeed / 7, 1, _min(maxNativeOut, 1 ether));
        (uint256 exactTokenIn, uint256 exactNativeOut) = crystal.quoteSell(false, token, 0, nativeOut);
        if (exactTokenIn == 0 || exactTokenIn > tokenBalance || exactNativeOut == 0) {
            return;
        }

        crystal.sell(false, token, exactTokenIn, exactNativeOut);
    }
}
