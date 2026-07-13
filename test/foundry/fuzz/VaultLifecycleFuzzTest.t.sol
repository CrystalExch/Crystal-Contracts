// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ICrystalVault } from "../../../contracts/interfaces/ICrystalVault.sol";
import { CrystalVaultFactory } from "../../../contracts/vaults/CrystalVaultFactory.sol";
import { BaseFuzzTest } from "../BaseFuzzTest.t.sol";

contract VaultLifecycleFuzzTest is BaseFuzzTest {
    uint16 private constant VAULT_MAX_ORDER_CAP = 100;

    CrystalVaultFactory private vaultFactory;

    function setUp() public override {
        super.setUp();
        vaultFactory =
            new CrystalVaultFactory(address(crystal), CRYSTAL_GOVERNANCE, address(weth), 100, VAULT_MAX_ORDER_CAP, 0);
    }

    function testFuzzLockUnlockRestoresDeposits(
        uint256 initialQuoteSeed,
        uint256 initialBaseSeed,
        uint256 depositQuoteSeed
    ) public {
        uint256 initialQuote = _boundVaultQuote(initialQuoteSeed);
        uint256 initialBase = _boundVaultBase(initialBaseSeed);
        ICrystalVault vault = _deployVault(alice, initialQuote, initialBase);

        vm.prank(alice);
        vaultFactory.lock(address(vault));

        (, bool factoryLocked, bool factoryClosed) = _factoryLifecycle(address(vault));
        assertTrue(vault.locked(), "assert vault.locked()");
        assertTrue(factoryLocked, "assert factoryLocked");
        assertFalse(factoryClosed, "assert !factoryClosed");

        vm.prank(alice);
        vaultFactory.unlock(address(vault));

        (, factoryLocked, factoryClosed) = _factoryLifecycle(address(vault));
        assertFalse(vault.locked(), "assert !vault.locked()");
        assertFalse(factoryLocked, "assert !factoryLocked");
        assertFalse(factoryClosed, "assert !factoryClosed");

        uint256 depositQuote = bound(depositQuoteSeed, _minFollowOn(initialQuote, MARKET_MIN_SIZE), initialQuote);
        uint256 depositBase = (depositQuote * initialBase) / initialQuote;
        _approveVaultFactory(bob);
        vm.prank(bob);
        (uint256 shares, uint256 quoteAmount, uint256 baseAmount) =
            vaultFactory.deposit(address(vault), address(quote), address(weth), depositQuote, depositBase, 0, 0);

        assertGt(shares, 0, "assert shares > 0");
        assertEq(quoteAmount, depositQuote, "assert quoteAmount == depositQuote");
        assertEq(baseAmount, depositBase, "assert baseAmount == depositBase");
        assertEq(vault.balanceOf(bob), shares, "assert vault.balanceOf(bob) == shares");
    }

    function testFuzzCloseReturnsOwnerAssetsAndMarksVaultClosed(uint256 initialQuoteSeed, uint256 initialBaseSeed)
        public
    {
        uint256 initialQuote = _boundVaultQuote(initialQuoteSeed);
        uint256 initialBase = _boundVaultBase(initialBaseSeed);
        ICrystalVault vault = _deployVault(alice, initialQuote, initialBase);
        uint256 ownerShares = vault.balanceOf(alice);
        uint256 ownerQuoteBefore = quote.balanceOf(alice);
        uint256 ownerWethBefore = weth.balanceOf(alice);

        vm.prank(alice);
        (uint256 quoteAmount, uint256 baseAmount) = vaultFactory.close(address(vault));

        (uint256 factoryTotalShares, bool factoryLocked, bool factoryClosed) = _factoryLifecycle(address(vault));
        assertEq(quoteAmount, initialQuote, "assert quoteAmount == initialQuote");
        assertEq(baseAmount, initialBase, "assert baseAmount == initialBase");
        assertEq(
            quote.balanceOf(alice),
            ownerQuoteBefore + quoteAmount,
            "assert quote.balanceOf(alice) == ownerQuoteBefore + quoteAmount"
        );
        assertEq(
            weth.balanceOf(alice),
            ownerWethBefore + baseAmount,
            "assert weth.balanceOf(alice) == ownerWethBefore + baseAmount"
        );
        assertEq(vault.balanceOf(alice), 0, "assert vault.balanceOf(alice) == 0");
        assertEq(vault.totalSupply(), 0, "assert vault.totalSupply() == 0");
        assertEq(factoryTotalShares, 0, "assert factoryTotalShares == 0");
        assertTrue(ownerShares > 0, "assert ownerShares > 0");
        assertTrue(vault.locked(), "assert vault.locked()");
        assertTrue(vault.closed(), "assert vault.closed()");
        assertTrue(factoryLocked, "assert factoryLocked");
        assertTrue(factoryClosed, "assert factoryClosed");
    }

    function testFuzzSweepTransfersEthBalanceToOwner(
        uint256 initialQuoteSeed,
        uint256 initialBaseSeed,
        uint256 sweepAmountSeed
    ) public {
        ICrystalVault vault = _deployVault(alice, _boundVaultQuote(initialQuoteSeed), _boundVaultBase(initialBaseSeed));
        uint256 sweepAmount = _boundEthAmount(sweepAmountSeed);

        (bool sent,) = address(vault).call{ value: sweepAmount }("");
        assertTrue(sent, "assert sent");

        uint256 ownerBalanceBefore = alice.balance;

        vm.prank(alice);
        vault.sweep();

        assertEq(address(vault).balance, 0, "assert address(vault).balance == 0");
        assertEq(
            alice.balance, ownerBalanceBefore + sweepAmount, "assert alice.balance == ownerBalanceBefore + sweepAmount"
        );
    }

    function _deployVault(address owner, uint256 amountQuote, uint256 amountBase)
        private
        returns (ICrystalVault vault)
    {
        _approveVaultFactory(owner);

        vm.prank(owner);
        vault = ICrystalVault(
            vaultFactory.deploy(address(quote), address(weth), amountQuote, amountBase, 0, 0, false, _metadata())
        );
    }

    function _approveVaultFactory(address account) private {
        vm.startPrank(account);
        quote.approve(address(vaultFactory), type(uint256).max);
        weth.approve(address(vaultFactory), type(uint256).max);
        vm.stopPrank();
    }

    function _factoryLifecycle(address vault) private view returns (uint256 totalShares, bool locked, bool closed) {
        (,,, totalShares,,,, locked, closed,) = vaultFactory.getVault(vault);
    }

    function _boundVaultQuote(uint256 amount) private pure returns (uint256) {
        return bound(amount, MARKET_MIN_SIZE, 100_000 * QUOTE_UNIT);
    }

    function _boundVaultBase(uint256 amount) private pure returns (uint256) {
        return bound(amount, MIN_ETH_FUZZ_AMOUNT, 1_000 ether);
    }

    function _minFollowOn(uint256 amount, uint256 floorAmount) private pure returns (uint256) {
        uint256 minAmount = amount / 100;
        return minAmount < floorAmount ? floorAmount : minAmount;
    }

    function _metadata() private pure returns (ICrystalVault.VaultMetaData memory) {
        return ICrystalVault.VaultMetaData({
            name: "Lifecycle Vault", description: "Focused lifecycle controls", social1: "", social2: "", social3: ""
        });
    }
}
