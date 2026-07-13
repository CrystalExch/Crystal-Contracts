// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ICrystalVault } from "../../../contracts/interfaces/ICrystalVault.sol";
import { CrystalVaultFactory } from "../../../contracts/vaults/CrystalVaultFactory.sol";
import { BaseTest } from "../BaseTest.t.sol";

contract VaultLifecycleTest is BaseTest {
    uint256 private constant INITIAL_QUOTE_AMOUNT = 1_000 * QUOTE_UNIT;
    uint256 private constant INITIAL_BASE_AMOUNT = 1 ether;
    uint16 private constant VAULT_MAX_ORDER_CAP = 100;

    CrystalVaultFactory private vaultFactory;

    function setUp() public override {
        super.setUp();
        vaultFactory =
            new CrystalVaultFactory(address(crystal), CRYSTAL_GOVERNANCE, address(weth), 100, VAULT_MAX_ORDER_CAP, 0);
    }

    function testLockUnlockRestoresDeposits() public {
        ICrystalVault vault = _deployVault(alice);

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

        _approveVaultFactory(bob);
        vm.prank(bob);
        (uint256 shares, uint256 quoteAmount, uint256 baseAmount) = vaultFactory.deposit(
            address(vault), address(quote), address(weth), INITIAL_QUOTE_AMOUNT, INITIAL_BASE_AMOUNT, 0, 0
        );

        assertGt(shares, 0, "assert shares > 0");
        assertEq(quoteAmount, INITIAL_QUOTE_AMOUNT, "assert quoteAmount == INITIAL_QUOTE_AMOUNT");
        assertEq(baseAmount, INITIAL_BASE_AMOUNT, "assert baseAmount == INITIAL_BASE_AMOUNT");
        assertEq(vault.balanceOf(bob), shares, "assert vault.balanceOf(bob) == shares");
    }

    function testCloseReturnsOwnerAssetsAndMarksVaultClosed() public {
        ICrystalVault vault = _deployVault(alice);
        uint256 ownerShares = vault.balanceOf(alice);
        uint256 ownerQuoteBefore = quote.balanceOf(alice);
        uint256 ownerWethBefore = weth.balanceOf(alice);

        vm.prank(alice);
        (uint256 quoteAmount, uint256 baseAmount) = vaultFactory.close(address(vault));

        (uint256 factoryTotalShares, bool factoryLocked, bool factoryClosed) = _factoryLifecycle(address(vault));
        assertEq(quoteAmount, INITIAL_QUOTE_AMOUNT, "assert quoteAmount == INITIAL_QUOTE_AMOUNT");
        assertEq(baseAmount, INITIAL_BASE_AMOUNT, "assert baseAmount == INITIAL_BASE_AMOUNT");
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

    function testSweepTransfersEthBalanceToOwner() public {
        ICrystalVault vault = _deployVault(alice);
        uint256 sweepAmount = 0.25 ether;

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

    function _deployVault(address owner) private returns (ICrystalVault vault) {
        _approveVaultFactory(owner);

        vm.prank(owner);
        vault = ICrystalVault(
            vaultFactory.deploy(
                address(quote), address(weth), INITIAL_QUOTE_AMOUNT, INITIAL_BASE_AMOUNT, 0, 0, false, _metadata()
            )
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

    function _metadata() private pure returns (ICrystalVault.VaultMetaData memory) {
        return ICrystalVault.VaultMetaData({
            name: "Lifecycle Vault", description: "Focused lifecycle controls", social1: "", social2: "", social3: ""
        });
    }
}
