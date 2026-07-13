// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ICrystal } from "../../../contracts/interfaces/ICrystal.sol";
import { ICrystalVault } from "../../../contracts/interfaces/ICrystalVault.sol";
import { VaultPropertyBase } from "./VaultPropertyBase.t.sol";

contract VaultOrderbookAccountingProperties is VaultPropertyBase {
    function testFuzzBuyLimitLocksQuoteWithoutChangingTotalBalance(
        uint256 initialQuoteSeed,
        uint256 initialBaseSeed,
        uint256 quotePerBaseSeed,
        uint256 sizeSeed
    ) public {
        uint256 initialQuote = _boundVaultQuote(initialQuoteSeed);
        uint256 initialBase = _boundVaultBase(initialBaseSeed);
        ICrystalVault vault = _deployVault(alice, initialQuote, initialBase, false, 0);
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 size = bound(sizeSeed, MARKET_MIN_SIZE * 2, initialQuote / 2);
        VaultBalances memory beforeBalances = _vaultBalances(vault);

        _executeVaultAction(vault, alice, BatchAction.BuyLimit, 1, price, size);

        VaultBalances memory afterBalances = _vaultBalances(vault);
        (uint256 totalQuote, uint256 availableQuote, uint256 lockedQuote) =
            crystal.getDepositedBalance(address(vault), address(quote));
        ICrystal.Order memory order = crystal.getOrderByCloid(crystal.addressToUserId(address(vault)), 1);

        assertEq(order.isBuy, true, "assert order.isBuy == true");
        assertEq(order.size, size, "assert order.size == size");
        assertEq(
            afterBalances.quoteBalance,
            beforeBalances.quoteBalance,
            "assert afterBalances.quoteBalance == beforeBalances.quoteBalance"
        );
        assertEq(
            afterBalances.baseBalance,
            beforeBalances.baseBalance,
            "assert afterBalances.baseBalance == beforeBalances.baseBalance"
        );
        assertEq(
            afterBalances.availableQuote,
            beforeBalances.availableQuote - size,
            "assert afterBalances.availableQuote == beforeBalances.availableQuote - size"
        );
        assertEq(
            afterBalances.availableBase,
            beforeBalances.availableBase,
            "assert afterBalances.availableBase == beforeBalances.availableBase"
        );
        assertEq(totalQuote, afterBalances.quoteBalance, "assert totalQuote == afterBalances.quoteBalance");
        assertEq(availableQuote, afterBalances.availableQuote, "assert availableQuote == afterBalances.availableQuote");
        assertEq(lockedQuote, size, "assert lockedQuote == size");
    }

    function testFuzzSellLimitLocksBaseWithoutChangingTotalBalance(
        uint256 initialQuoteSeed,
        uint256 initialBaseSeed,
        uint256 quotePerBaseSeed,
        uint256 sizeSeed
    ) public {
        uint256 initialQuote = _boundVaultQuote(initialQuoteSeed);
        uint256 initialBase = _boundVaultBase(initialBaseSeed);
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 minSize = _minBaseForQuote(MARKET_MIN_SIZE * 2, price);
        ICrystalVault vault = _deployVault(alice, initialQuote, initialBase, false, 0);
        uint256 size = bound(sizeSeed, minSize, initialBase / 2);
        VaultBalances memory beforeBalances = _vaultBalances(vault);

        _executeVaultAction(vault, alice, BatchAction.SellLimit, 1, price, size);

        VaultBalances memory afterBalances = _vaultBalances(vault);
        (uint256 totalBase, uint256 availableBase, uint256 lockedBase) =
            crystal.getDepositedBalance(address(vault), address(weth));
        ICrystal.Order memory order = crystal.getOrderByCloid(crystal.addressToUserId(address(vault)), 1);

        assertEq(order.isBuy, false, "assert order.isBuy == false");
        assertEq(order.size, size, "assert order.size == size");
        assertEq(
            afterBalances.quoteBalance,
            beforeBalances.quoteBalance,
            "assert afterBalances.quoteBalance == beforeBalances.quoteBalance"
        );
        assertEq(
            afterBalances.baseBalance,
            beforeBalances.baseBalance,
            "assert afterBalances.baseBalance == beforeBalances.baseBalance"
        );
        assertEq(
            afterBalances.availableQuote,
            beforeBalances.availableQuote,
            "assert afterBalances.availableQuote == beforeBalances.availableQuote"
        );
        assertEq(
            afterBalances.availableBase,
            beforeBalances.availableBase - size,
            "assert afterBalances.availableBase == beforeBalances.availableBase - size"
        );
        assertEq(totalBase, afterBalances.baseBalance, "assert totalBase == afterBalances.baseBalance");
        assertEq(availableBase, afterBalances.availableBase, "assert availableBase == afterBalances.availableBase");
        assertEq(lockedBase, size, "assert lockedBase == size");
    }

    function testFuzzCancelAndDecreaseReleaseCorrectLockedAsset(uint256 buyDecreaseSeed, uint256 sellDecreaseSeed)
        public
    {
        ICrystalVault vault = _deployVault(alice, 20_000 * QUOTE_UNIT, 200 ether, false, 0);
        uint256 buyPrice = _price(500);
        uint256 sellPrice = _price(600);
        uint256 buySize = 4_000 * QUOTE_UNIT;
        uint256 sellSize = 40 ether;
        uint256 buyDecrease = bound(buyDecreaseSeed, MARKET_MIN_SIZE, buySize / 2);
        uint256 sellDecrease = bound(sellDecreaseSeed, _minBaseForQuote(MARKET_MIN_SIZE, sellPrice), sellSize / 2);

        _executeVaultAction(vault, alice, BatchAction.BuyLimit, 1, buyPrice, buySize);
        _executeVaultAction(vault, alice, BatchAction.SellLimit, 2, sellPrice, sellSize);

        _executeVaultAction(vault, alice, BatchAction.DecreaseOrder, 1, 0, buyDecrease);
        _executeVaultAction(vault, alice, BatchAction.DecreaseOrder, 2, 0, sellDecrease);

        (,, uint256 lockedQuoteAfterDecrease) = crystal.getDepositedBalance(address(vault), address(quote));
        (,, uint256 lockedBaseAfterDecrease) = crystal.getDepositedBalance(address(vault), address(weth));
        ICrystal.Order memory buyOrder = crystal.getOrderByCloid(crystal.addressToUserId(address(vault)), 1);
        ICrystal.Order memory sellOrder = crystal.getOrderByCloid(crystal.addressToUserId(address(vault)), 2);

        assertEq(buyOrder.size, buySize - buyDecrease, "assert buyOrder.size == buySize - buyDecrease");
        assertEq(sellOrder.size, sellSize - sellDecrease, "assert sellOrder.size == sellSize - sellDecrease");
        assertEq(
            lockedQuoteAfterDecrease, buySize - buyDecrease, "assert lockedQuoteAfterDecrease == buySize - buyDecrease"
        );
        assertEq(
            lockedBaseAfterDecrease,
            sellSize - sellDecrease,
            "assert lockedBaseAfterDecrease == sellSize - sellDecrease"
        );

        _executeVaultAction(vault, alice, BatchAction.CancelOrder, 1, 0, 0);
        _executeVaultAction(vault, alice, BatchAction.CancelOrder, 2, 0, 0);

        (,, uint256 lockedQuoteAfterCancel) = crystal.getDepositedBalance(address(vault), address(quote));
        (,, uint256 lockedBaseAfterCancel) = crystal.getDepositedBalance(address(vault), address(weth));

        assertEq(lockedQuoteAfterCancel, 0, "assert lockedQuoteAfterCancel == 0");
        assertEq(lockedBaseAfterCancel, 0, "assert lockedBaseAfterCancel == 0");
    }

    function testFuzzMixedOrdersTrackIndependentLockedBalances(
        uint256 lowQuotePerBaseSeed,
        uint256 highQuotePerBaseSeed,
        uint256 buySizeSeed,
        uint256 sellSizeSeed
    ) public {
        ICrystalVault vault = _deployVault(alice, 20_000 * QUOTE_UNIT, 200 ether, false, 0);
        (uint256 buyPrice, uint256 sellPrice) = _boundOrderedPrices(lowQuotePerBaseSeed, highQuotePerBaseSeed);
        uint256 buySize = bound(buySizeSeed, MARKET_MIN_SIZE * 2, 10_000 * QUOTE_UNIT);
        uint256 sellSize = bound(sellSizeSeed, _minBaseForQuote(MARKET_MIN_SIZE * 2, sellPrice), 100 ether);

        _executeVaultAction(vault, alice, BatchAction.BuyLimit, 1, buyPrice, buySize);
        _executeVaultAction(vault, alice, BatchAction.SellLimit, 2, sellPrice, sellSize);

        (uint256 totalQuote, uint256 availableQuote, uint256 lockedQuote) =
            crystal.getDepositedBalance(address(vault), address(quote));
        (uint256 totalBase, uint256 availableBase, uint256 lockedBase) =
            crystal.getDepositedBalance(address(vault), address(weth));

        assertEq(totalQuote, 20_000 * QUOTE_UNIT, "assert totalQuote == 20_000 * QUOTE_UNIT");
        assertEq(totalBase, 200 ether, "assert totalBase == 200 ether");
        assertEq(availableQuote, totalQuote - buySize, "assert availableQuote == totalQuote - buySize");
        assertEq(availableBase, totalBase - sellSize, "assert availableBase == totalBase - sellSize");
        assertEq(lockedQuote, buySize, "assert lockedQuote == buySize");
        assertEq(lockedBase, sellSize, "assert lockedBase == sellSize");
    }

    function testFuzzWithdrawWithDecreaseTrueProportionallyReducesActiveOrders(
        uint256 quotePerBaseSeed,
        uint256 sharesSeed
    ) public {
        ICrystalVault vault = _deployVault(alice, 20_000 * QUOTE_UNIT, 200 ether, true, 0);
        address vaultAddress = address(vault);
        (uint256 bobShares,,) = _depositIntoVault(bob, vaultAddress, 20_000 * QUOTE_UNIT, 200 ether, 0, 0);
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 buySize = 8_000 * QUOTE_UNIT;
        uint256 sharesToWithdraw = bound(sharesSeed, 1, bobShares / 2);

        _executeVaultAction(vault, alice, BatchAction.BuyLimit, 1, price, buySize);

        (uint256 quoteBalanceBefore,,,) = _vaultBalanceTuple(vault);
        (uint256 amountQuote, uint256 amountBase) = _previewWithdrawal(vaultAddress, sharesToWithdraw);
        uint256 expectedDecrease = (buySize * amountQuote + quoteBalanceBefore - 1) / quoteBalanceBefore;

        _withdrawFromVault(bob, vaultAddress, sharesToWithdraw, amountQuote, amountBase);

        ICrystal.Order memory order = crystal.getOrderByCloid(crystal.addressToUserId(vaultAddress), 1);
        (,, uint256 lockedQuoteAfter) = crystal.getDepositedBalance(vaultAddress, address(quote));

        assertEq(order.size, buySize - expectedDecrease, "assert order.size == buySize - expectedDecrease");
        assertEq(lockedQuoteAfter, buySize - expectedDecrease, "assert lockedQuoteAfter == buySize - expectedDecrease");
    }

    function testWithdrawWithDecreaseFalseOnlyReducesNeededLockedLiquidity() public {
        ICrystalVault vault = _deployVault(alice, 20_000 * QUOTE_UNIT, 200 ether, false, 0);
        address vaultAddress = address(vault);
        (uint256 bobShares,,) = _depositIntoVault(bob, vaultAddress, 20_000 * QUOTE_UNIT, 200 ether, 0, 0);
        uint256 buySize = 30_000 * QUOTE_UNIT;

        _executeVaultAction(vault, alice, BatchAction.BuyLimit, 1, _price(500), buySize);

        (uint256 quoteBalanceBefore,, uint256 availableQuoteBefore,) = _vaultBalanceTuple(vault);
        (uint256 amountQuote, uint256 amountBase) = _previewWithdrawal(vaultAddress, bobShares);
        uint256 excessQuote = amountQuote > availableQuoteBefore ? amountQuote - availableQuoteBefore : 0;
        uint256 lockedQuoteBefore = quoteBalanceBefore - availableQuoteBefore;
        uint256 expectedDecrease = (buySize * excessQuote + lockedQuoteBefore - 1) / lockedQuoteBefore;

        _withdrawFromVault(bob, vaultAddress, bobShares, amountQuote, amountBase);

        ICrystal.Order memory order = crystal.getOrderByCloid(crystal.addressToUserId(vaultAddress), 1);
        (,, uint256 lockedQuoteAfter) = crystal.getDepositedBalance(vaultAddress, address(quote));

        assertGt(excessQuote, 0, "assert excessQuote > 0");
        assertEq(order.size, buySize - expectedDecrease, "assert order.size == buySize - expectedDecrease");
        assertEq(lockedQuoteAfter, buySize - expectedDecrease, "assert lockedQuoteAfter == buySize - expectedDecrease");
    }
}
