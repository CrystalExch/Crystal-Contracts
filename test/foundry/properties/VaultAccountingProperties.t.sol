// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ICrystalVault } from "../../../contracts/interfaces/ICrystalVault.sol";
import { ICrystalVaultFactory } from "../../../contracts/interfaces/ICrystalVaultFactory.sol";
import { CrystalMath } from "../../../contracts/libraries/CrystalMath.sol";
import { CrystalVaultFactory } from "../../../contracts/vaults/CrystalVaultFactory.sol";
import { VaultPropertyBase } from "./VaultPropertyBase.t.sol";

contract VaultAccountingProperties is VaultPropertyBase {
    struct AccountingSnapshot {
        uint256 totalSupply;
        uint256 factoryShares;
        uint256 userQuote;
        uint256 userBase;
        uint256 quoteBalance;
        uint256 baseBalance;
        uint256 availableQuote;
        uint256 availableBase;
    }

    function testFuzzPreviewDepositMatchesActualDepositAndUpdatesAccounting(
        uint256 initialQuoteSeed,
        uint256 initialBaseSeed,
        uint256 quoteDesiredSeed,
        uint256 baseDesiredSeed
    ) public {
        uint256 initialQuote = _boundVaultQuote(initialQuoteSeed);
        uint256 initialBase = _boundVaultBase(initialBaseSeed);
        ICrystalVault vault = _deployVault(alice, initialQuote, initialBase, false, 0);
        address vaultAddress = address(vault);
        uint256 quoteDesired = _boundFollowOnQuote(quoteDesiredSeed, initialQuote);
        uint256 baseDesired = _boundFollowOnBase(baseDesiredSeed, initialBase);
        AccountingSnapshot memory beforeSnapshot = _snapshot(vault, bob);
        uint256[3] memory preview = _previewDeposit(vaultAddress, quoteDesired, baseDesired);
        uint256[3] memory actual;

        assertGt(preview[SHARES_INDEX], 0, "assert preview[SHARES_INDEX] > 0");

        (actual[SHARES_INDEX], actual[QUOTE_INDEX], actual[BASE_INDEX]) =
            _depositIntoVault(bob, vaultAddress, quoteDesired, baseDesired, preview[QUOTE_INDEX], preview[BASE_INDEX]);

        assertEq(actual[SHARES_INDEX], preview[SHARES_INDEX], "assert actual[SHARES_INDEX] == preview[SHARES_INDEX]");
        assertEq(actual[QUOTE_INDEX], preview[QUOTE_INDEX], "assert actual[QUOTE_INDEX] == preview[QUOTE_INDEX]");
        assertEq(actual[BASE_INDEX], preview[BASE_INDEX], "assert actual[BASE_INDEX] == preview[BASE_INDEX]");
        assertEq(vault.balanceOf(bob), actual[SHARES_INDEX], "assert vault.balanceOf(bob) == actual[SHARES_INDEX]");
        assertEq(
            vault.totalSupply(),
            beforeSnapshot.totalSupply + actual[SHARES_INDEX],
            "assert vault.totalSupply() == beforeSnapshot.totalSupply + actual[SHARES_INDEX]"
        );
        assertEq(
            _storedTotalShares(vaultAddress),
            beforeSnapshot.factoryShares + actual[SHARES_INDEX],
            "assert _storedTotalShares(vaultAddress) == beforeSnapshot.factoryShares + actual[SHARES_INDEX]"
        );
        assertEq(
            quote.balanceOf(bob),
            beforeSnapshot.userQuote - actual[QUOTE_INDEX],
            "assert quote.balanceOf(bob) == beforeSnapshot.userQuote - actual[QUOTE_INDEX]"
        );
        assertEq(
            weth.balanceOf(bob),
            beforeSnapshot.userBase - actual[BASE_INDEX],
            "assert weth.balanceOf(bob) == beforeSnapshot.userBase - actual[BASE_INDEX]"
        );

        AccountingSnapshot memory afterSnapshot = _snapshot(vault, bob);

        assertEq(
            afterSnapshot.quoteBalance,
            beforeSnapshot.quoteBalance + actual[QUOTE_INDEX],
            "assert afterSnapshot.quoteBalance == beforeSnapshot.quoteBalance + actual[QUOTE_INDEX]"
        );
        assertEq(
            afterSnapshot.baseBalance,
            beforeSnapshot.baseBalance + actual[BASE_INDEX],
            "assert afterSnapshot.baseBalance == beforeSnapshot.baseBalance + actual[BASE_INDEX]"
        );
        assertEq(
            afterSnapshot.availableQuote,
            beforeSnapshot.availableQuote + actual[QUOTE_INDEX],
            "assert afterSnapshot.availableQuote == beforeSnapshot.availableQuote + actual[QUOTE_INDEX]"
        );
        assertEq(
            afterSnapshot.availableBase,
            beforeSnapshot.availableBase + actual[BASE_INDEX],
            "assert afterSnapshot.availableBase == beforeSnapshot.availableBase + actual[BASE_INDEX]"
        );
        _assertCrystalBalance(vaultAddress, address(quote), afterSnapshot.quoteBalance, afterSnapshot.availableQuote);
        _assertCrystalBalance(vaultAddress, address(weth), afterSnapshot.baseBalance, afterSnapshot.availableBase);
    }

    function testFuzzPreviewWithdrawalMatchesActualWithdrawalAndUpdatesAccounting(
        uint256 initialQuoteSeed,
        uint256 initialBaseSeed,
        uint256 quoteDesiredSeed,
        uint256 baseDesiredSeed,
        uint256 sharesSeed
    ) public {
        uint256 initialQuote = _boundVaultQuote(initialQuoteSeed);
        uint256 initialBase = _boundVaultBase(initialBaseSeed);
        ICrystalVault vault = _deployVault(alice, initialQuote, initialBase, false, 0);
        address vaultAddress = address(vault);
        uint256 quoteDesired = _boundFollowOnQuote(quoteDesiredSeed, initialQuote);
        uint256 baseDesired = _boundFollowOnBase(baseDesiredSeed, initialBase);
        (uint256 bobShares,,) = _depositIntoVault(bob, vaultAddress, quoteDesired, baseDesired, 0, 0);
        uint256 sharesToWithdraw = bound(sharesSeed, 1, bobShares);
        AccountingSnapshot memory beforeSnapshot = _snapshot(vault, bob);
        (uint256 expectedQuote, uint256 expectedBase) = _previewWithdrawal(vaultAddress, sharesToWithdraw);

        (uint256 quoteOut, uint256 baseOut) =
            _withdrawFromVault(bob, vaultAddress, sharesToWithdraw, expectedQuote, expectedBase);

        assertEq(quoteOut, expectedQuote, "assert quoteOut == expectedQuote");
        assertEq(baseOut, expectedBase, "assert baseOut == expectedBase");
        assertEq(
            vault.balanceOf(bob),
            bobShares - sharesToWithdraw,
            "assert vault.balanceOf(bob) == bobShares - sharesToWithdraw"
        );
        assertEq(
            vault.totalSupply(),
            beforeSnapshot.totalSupply - sharesToWithdraw,
            "assert vault.totalSupply() == beforeSnapshot.totalSupply - sharesToWithdraw"
        );
        assertEq(
            _storedTotalShares(vaultAddress),
            beforeSnapshot.factoryShares - sharesToWithdraw,
            "assert _storedTotalShares(vaultAddress) == beforeSnapshot.factoryShares - sharesToWithdraw"
        );
        assertEq(
            quote.balanceOf(bob),
            beforeSnapshot.userQuote + quoteOut,
            "assert quote.balanceOf(bob) == beforeSnapshot.userQuote + quoteOut"
        );
        assertEq(
            weth.balanceOf(bob),
            beforeSnapshot.userBase + baseOut,
            "assert weth.balanceOf(bob) == beforeSnapshot.userBase + baseOut"
        );

        AccountingSnapshot memory afterSnapshot = _snapshot(vault, bob);

        assertEq(
            afterSnapshot.quoteBalance,
            beforeSnapshot.quoteBalance - quoteOut,
            "assert afterSnapshot.quoteBalance == beforeSnapshot.quoteBalance - quoteOut"
        );
        assertEq(
            afterSnapshot.baseBalance,
            beforeSnapshot.baseBalance - baseOut,
            "assert afterSnapshot.baseBalance == beforeSnapshot.baseBalance - baseOut"
        );
        assertEq(
            afterSnapshot.availableQuote,
            beforeSnapshot.availableQuote - quoteOut,
            "assert afterSnapshot.availableQuote == beforeSnapshot.availableQuote - quoteOut"
        );
        assertEq(
            afterSnapshot.availableBase,
            beforeSnapshot.availableBase - baseOut,
            "assert afterSnapshot.availableBase == beforeSnapshot.availableBase - baseOut"
        );
        _assertCrystalBalance(vaultAddress, address(quote), afterSnapshot.quoteBalance, afterSnapshot.availableQuote);
        _assertCrystalBalance(vaultAddress, address(weth), afterSnapshot.baseBalance, afterSnapshot.availableBase);
    }

    function testFuzzPreviewFunctionsAreCallerIndependentAndNonMutating(
        uint256 initialQuoteSeed,
        uint256 initialBaseSeed,
        uint256 quoteDesiredSeed,
        uint256 baseDesiredSeed,
        uint256 sharesSeed
    ) public {
        uint256 initialQuote = _boundVaultQuote(initialQuoteSeed);
        uint256 initialBase = _boundVaultBase(initialBaseSeed);
        ICrystalVault vault = _deployVault(alice, initialQuote, initialBase, false, 0);
        uint256 quoteDesired = _boundFollowOnQuote(quoteDesiredSeed, initialQuote);
        uint256 baseDesired = _boundFollowOnBase(baseDesiredSeed, initialBase);
        uint256 shares = bound(sharesSeed, 1, vault.totalSupply());
        AccountingSnapshot memory beforeSnapshot = _snapshot(vault, address(0));

        {
            vm.prank(alice);
            (uint256 aliceShares, uint256 aliceQuote, uint256 aliceBase) =
                vault.previewDeposit(quoteDesired, baseDesired);
            vm.prank(bob);
            (uint256 bobShares, uint256 bobQuote, uint256 bobBase) = vault.previewDeposit(quoteDesired, baseDesired);

            assertEq(aliceShares, bobShares, "assert aliceShares == bobShares");
            assertEq(aliceQuote, bobQuote, "assert aliceQuote == bobQuote");
            assertEq(aliceBase, bobBase, "assert aliceBase == bobBase");
        }

        {
            vm.prank(carol);
            (uint256 carolQuoteOut, uint256 carolBaseOut) = vault.previewWithdrawal(shares);
            vm.prank(bob);
            (uint256 bobQuoteOut, uint256 bobBaseOut) = vault.previewWithdrawal(shares);

            assertEq(carolQuoteOut, bobQuoteOut, "assert carolQuoteOut == bobQuoteOut");
            assertEq(carolBaseOut, bobBaseOut, "assert carolBaseOut == bobBaseOut");
        }

        AccountingSnapshot memory afterSnapshot = _snapshot(vault, address(0));

        assertEq(
            vault.totalSupply(), beforeSnapshot.totalSupply, "assert vault.totalSupply() == beforeSnapshot.totalSupply"
        );
        assertEq(
            afterSnapshot.quoteBalance,
            beforeSnapshot.quoteBalance,
            "assert afterSnapshot.quoteBalance == beforeSnapshot.quoteBalance"
        );
        assertEq(
            afterSnapshot.baseBalance,
            beforeSnapshot.baseBalance,
            "assert afterSnapshot.baseBalance == beforeSnapshot.baseBalance"
        );
        assertEq(
            afterSnapshot.availableQuote,
            beforeSnapshot.availableQuote,
            "assert afterSnapshot.availableQuote == beforeSnapshot.availableQuote"
        );
        assertEq(
            afterSnapshot.availableBase,
            beforeSnapshot.availableBase,
            "assert afterSnapshot.availableBase == beforeSnapshot.availableBase"
        );
    }

    function testFuzzDepositWithdrawRoundTripDoesNotCreateFreeAssets(
        uint256 initialQuoteSeed,
        uint256 initialBaseSeed,
        uint256 quoteDesiredSeed,
        uint256 baseDesiredSeed
    ) public {
        uint256 initialQuote = _boundVaultQuote(initialQuoteSeed);
        uint256 initialBase = _boundVaultBase(initialBaseSeed);
        ICrystalVault vault = _deployVault(alice, initialQuote, initialBase, false, 0);
        address vaultAddress = address(vault);
        uint256 quoteDesired = _boundFollowOnQuote(quoteDesiredSeed, initialQuote);
        uint256 baseDesired = _boundFollowOnBase(baseDesiredSeed, initialBase);
        uint256 bobQuoteBefore = quote.balanceOf(bob);
        uint256 bobBaseBefore = weth.balanceOf(bob);

        (uint256 sharesMinted,,) = _depositIntoVault(bob, vaultAddress, quoteDesired, baseDesired, 0, 0);
        (uint256 expectedQuote, uint256 expectedBase) = _previewWithdrawal(vaultAddress, sharesMinted);
        _withdrawFromVault(bob, vaultAddress, sharesMinted, expectedQuote, expectedBase);

        assertEq(vault.balanceOf(bob), 0, "assert vault.balanceOf(bob) == 0");
        assertLe(quote.balanceOf(bob), bobQuoteBefore, "assert quote.balanceOf(bob) <= bobQuoteBefore");
        assertLe(weth.balanceOf(bob), bobBaseBefore, "assert weth.balanceOf(bob) <= bobBaseBefore");
    }

    function testMaxSharesCapRejectsExcessDeposit() public {
        ICrystalVault vault = _deployVault(alice, 1_000 * QUOTE_UNIT, 20 ether, false, 0);
        address vaultAddress = address(vault);
        uint256 currentTotalSupply = vault.totalSupply();

        vm.prank(alice);
        vaultFactory.changeMaxShares(vaultAddress, currentTotalSupply);

        _approveVaultFactory(bob);
        vm.prank(bob);
        vm.expectRevert();
        vaultFactory.deposit(vaultAddress, address(quote), address(weth), 100 * QUOTE_UNIT, 2 ether, 0, 0);
    }

    function testWithdrawalRespectsLockupUntilTimestamp() public {
        vaultFactory = ICrystalVaultFactory(
            address(
                new CrystalVaultFactory(
                    address(crystal), CRYSTAL_GOVERNANCE, address(weth), 0, PROPERTY_MAX_ORDER_CAP, 1 days
                )
            )
        );
        ICrystalVault vault = _deployVault(alice, 1_000 * QUOTE_UNIT, 20 ether, false, 1 days);
        address vaultAddress = address(vault);
        (uint256 bobShares,,) = _depositIntoVault(bob, vaultAddress, 100 * QUOTE_UNIT, 2 ether, 0, 0);

        vm.prank(bob);
        vm.expectRevert();
        vaultFactory.withdraw(vaultAddress, address(quote), address(weth), bobShares, 0, 0);

        vm.warp(block.timestamp + 1 days);
        (uint256 expectedQuote, uint256 expectedBase) = _previewWithdrawal(vaultAddress, bobShares);
        (uint256 quoteOut, uint256 baseOut) =
            _withdrawFromVault(bob, vaultAddress, bobShares, expectedQuote, expectedBase);

        assertEq(quoteOut, expectedQuote, "assert quoteOut == expectedQuote");
        assertEq(baseOut, expectedBase, "assert baseOut == expectedBase");
    }

    function testOwnerMinimumShareRequirementRejectsLargeUserDeposit() public {
        ICrystalVault vault = _deployVault(alice, 1_000 * QUOTE_UNIT, 20 ether, false, 0);
        address vaultAddress = address(vault);

        _approveVaultFactory(bob);
        vm.prank(bob);
        vm.expectRevert();
        vaultFactory.deposit(vaultAddress, address(quote), address(weth), 30_000 * QUOTE_UNIT, 600 ether, 0, 0);
    }

    function testFuzzOwnerCloseReturnsAllAssetsAndClosesVault(uint256 initialQuoteSeed, uint256 initialBaseSeed)
        public
    {
        uint256 initialQuote = _boundVaultQuote(initialQuoteSeed);
        uint256 initialBase = _boundVaultBase(initialBaseSeed);
        ICrystalVault vault = _deployVault(alice, initialQuote, initialBase, false, 0);
        address vaultAddress = address(vault);
        uint256 ownerShares = vault.balanceOf(alice);
        uint256 aliceQuoteBefore = quote.balanceOf(alice);
        uint256 aliceBaseBefore = weth.balanceOf(alice);
        (uint256 expectedQuote, uint256 expectedBase) = _previewWithdrawal(vaultAddress, ownerShares);

        vm.prank(alice);
        (uint256 quoteOut, uint256 baseOut) = vaultFactory.close(vaultAddress);

        assertEq(quoteOut, expectedQuote, "assert quoteOut == expectedQuote");
        assertEq(baseOut, expectedBase, "assert baseOut == expectedBase");
        assertEq(vault.balanceOf(alice), 0, "assert vault.balanceOf(alice) == 0");
        assertEq(vault.totalSupply(), 0, "assert vault.totalSupply() == 0");
        assertEq(
            quote.balanceOf(alice),
            aliceQuoteBefore + quoteOut,
            "assert quote.balanceOf(alice) == aliceQuoteBefore + quoteOut"
        );
        assertEq(
            weth.balanceOf(alice),
            aliceBaseBefore + baseOut,
            "assert weth.balanceOf(alice) == aliceBaseBefore + baseOut"
        );
        assertTrue(vault.closed(), "assert vault.closed()");
        assertTrue(vault.locked(), "assert vault.locked()");
        assertEq(_storedTotalShares(vaultAddress), 0, "assert _storedTotalShares(vaultAddress) == 0");
    }

    function testFuzzInitialShareMintingUsesGeometricMean(uint256 initialQuoteSeed, uint256 initialBaseSeed) public {
        uint256 initialQuote = _boundVaultQuote(initialQuoteSeed);
        uint256 initialBase = _boundVaultBase(initialBaseSeed);
        ICrystalVault vault = _deployVault(alice, initialQuote, initialBase, false, 0);
        uint256 expectedShares = CrystalMath._sqrt(initialQuote * initialBase);

        assertEq(vault.totalSupply(), expectedShares, "assert vault.totalSupply() == expectedShares");
        assertEq(vault.balanceOf(alice), expectedShares, "assert vault.balanceOf(alice) == expectedShares");
    }

    function _snapshot(ICrystalVault vault, address user) private view returns (AccountingSnapshot memory snapshot) {
        snapshot.totalSupply = vault.totalSupply();
        snapshot.factoryShares = _storedTotalShares(address(vault));
        snapshot.userQuote = quote.balanceOf(user);
        snapshot.userBase = weth.balanceOf(user);
        (snapshot.quoteBalance, snapshot.baseBalance, snapshot.availableQuote, snapshot.availableBase) =
            _vaultBalanceTuple(vault);
    }
}
