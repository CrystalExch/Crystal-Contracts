// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "../BaseTest.t.sol";
import { ICrystalVault } from "../../../contracts/interfaces/ICrystalVault.sol";
import { ICrystalVaultFactory } from "../../../contracts/interfaces/ICrystalVaultFactory.sol";
import { CrystalMath } from "../../../contracts/libraries/CrystalMath.sol";
import { CrystalVaultFactory } from "../../../contracts/vaults/CrystalVaultFactory.sol";

contract VaultDepositTest is BaseTest {
    uint256 private constant FACTORY_MIN_DEPOSIT = 100;
    uint16 private constant FACTORY_MAX_ORDER_CAP = 64;
    uint40 private constant FACTORY_MAX_LOCKUP = 7 days;
    uint40 private constant VAULT_LOCKUP = 1 days;
    uint256 private constant INITIAL_QUOTE_AMOUNT = 10_000 * QUOTE_UNIT;
    uint256 private constant INITIAL_BASE_AMOUNT = 10 ether;
    uint256 private constant SHARES_INDEX = 0;
    uint256 private constant QUOTE_INDEX = 1;
    uint256 private constant BASE_INDEX = 2;

    ICrystalVaultFactory internal vaultFactory;

    function setUp() public override {
        super.setUp();

        vaultFactory = ICrystalVaultFactory(
            address(
                new CrystalVaultFactory(
                    address(crystal),
                    CRYSTAL_GOVERNANCE,
                    address(weth),
                    FACTORY_MIN_DEPOSIT,
                    FACTORY_MAX_ORDER_CAP,
                    FACTORY_MAX_LOCKUP
                )
            )
        );
    }

    function testDeployVaultWithInitialDepositMintsOwnerSharesAndStoresVaultState() public {
        address vaultAddress = _deployVaultFrom(alice, "Initial Deposit Vault");
        uint256 expectedShares = CrystalMath._sqrt(INITIAL_QUOTE_AMOUNT * INITIAL_BASE_AMOUNT);

        _assertStoredVaultState(vaultAddress, expectedShares, "Initial Deposit Vault");
        _assertVaultDeploymentState(vaultAddress, expectedShares);
        _assertInitialVaultBalances(ICrystalVault(vaultAddress));
        _assertFactoryBalance(vaultAddress, alice, expectedShares, INITIAL_QUOTE_AMOUNT, INITIAL_BASE_AMOUNT);
    }

    function testDepositIntoExistingVaultMintsPreviewedSharesAndRefundsUnusedBase() public {
        address vaultAddress = _deployVaultFrom(alice, "Share Mint Vault");
        ICrystalVault vault = ICrystalVault(vaultAddress);
        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 bobQuoteBefore = quote.balanceOf(bob);
        uint256 bobBaseBefore = weth.balanceOf(bob);
        uint256[3] memory preview = _previewDeposit(vaultAddress, 500 * QUOTE_UNIT, 1 ether);

        assertGt(preview[SHARES_INDEX], 0, "assert preview[SHARES_INDEX] > 0");
        assertEq(preview[QUOTE_INDEX], 500 * QUOTE_UNIT, "assert preview[QUOTE_INDEX] == 500 * QUOTE_UNIT");
        assertEq(preview[BASE_INDEX], 0.5 ether, "assert preview[BASE_INDEX] == 0.5 ether");

        uint256[3] memory deposited = _depositFrom(bob, vaultAddress, 500 * QUOTE_UNIT, 1 ether, preview);

        assertEq(
            deposited[SHARES_INDEX], preview[SHARES_INDEX], "assert deposited[SHARES_INDEX] == preview[SHARES_INDEX]"
        );
        assertEq(deposited[QUOTE_INDEX], preview[QUOTE_INDEX], "assert deposited[QUOTE_INDEX] == preview[QUOTE_INDEX]");
        assertEq(deposited[BASE_INDEX], preview[BASE_INDEX], "assert deposited[BASE_INDEX] == preview[BASE_INDEX]");
        assertEq(vault.balanceOf(bob), preview[SHARES_INDEX], "assert vault.balanceOf(bob) == preview[SHARES_INDEX]");
        assertEq(
            vault.totalSupply(),
            totalSupplyBefore + preview[SHARES_INDEX],
            "assert vault.totalSupply() == totalSupplyBefore + preview[SHARES_INDEX]"
        );
        assertEq(
            _storedTotalShares(vaultAddress),
            vault.totalSupply(),
            "assert _storedTotalShares(vaultAddress) == vault.totalSupply()"
        );
        assertEq(
            vault.unlockTimestamp(bob),
            block.timestamp + VAULT_LOCKUP,
            "assert vault.unlockTimestamp(bob) == block.timestamp + VAULT_LOCKUP"
        );
        assertEq(
            quote.balanceOf(bob),
            bobQuoteBefore - preview[QUOTE_INDEX],
            "assert quote.balanceOf(bob) == bobQuoteBefore - preview[QUOTE_INDEX]"
        );
        assertEq(
            weth.balanceOf(bob),
            bobBaseBefore - preview[BASE_INDEX],
            "assert weth.balanceOf(bob) == bobBaseBefore - preview[BASE_INDEX]"
        );

        _assertVaultBalances(vault, preview);
        _assertFactoryBalance(vaultAddress, bob, preview);
    }

    function _assertStoredVaultState(address vaultAddress, uint256 expectedShares, string memory expectedName)
        private
        view
    {
        (
            address storedQuoteAsset,
            address storedBaseAsset,
            address storedOwner,
            uint256 storedTotalShares,
            uint256 storedMaxShares,
            uint40 storedLockup,
            bool storedDecreaseOnWithdraw,
            bool storedLocked,
            bool storedClosed,
            ICrystalVault.VaultMetaData memory storedMetadata
        ) = vaultFactory.getVault(vaultAddress);

        assertEq(vaultFactory.allVaultsLength(), 1, "assert vaultFactory.allVaultsLength() == 1");
        assertEq(vaultFactory.allVaults(0), vaultAddress, "assert vaultFactory.allVaults(0) == vaultAddress");
        assertEq(storedQuoteAsset, address(quote), "assert storedQuoteAsset == address(quote)");
        assertEq(storedBaseAsset, address(weth), "assert storedBaseAsset == address(weth)");
        assertEq(storedOwner, alice, "assert storedOwner == alice");
        assertEq(storedTotalShares, expectedShares, "assert storedTotalShares == expectedShares");
        assertEq(storedMaxShares, 0, "assert storedMaxShares == 0");
        assertEq(storedLockup, VAULT_LOCKUP, "assert storedLockup == VAULT_LOCKUP");
        assertFalse(storedDecreaseOnWithdraw, "assert !storedDecreaseOnWithdraw");
        assertFalse(storedLocked, "assert !storedLocked");
        assertFalse(storedClosed, "assert !storedClosed");
        assertEq(storedMetadata.name, expectedName, "assert storedMetadata.name == expectedName");
    }

    function _assertVaultDeploymentState(address vaultAddress, uint256 expectedShares) private view {
        ICrystalVault vault = ICrystalVault(vaultAddress);
        assertEq(vault.factory(), address(vaultFactory), "assert vault.factory() == address(vaultFactory)");
        assertEq(vault.crystal(), address(crystal), "assert vault.crystal() == address(crystal)");
        assertEq(vault.quoteAsset(), address(quote), "assert vault.quoteAsset() == address(quote)");
        assertEq(vault.baseAsset(), address(weth), "assert vault.baseAsset() == address(weth)");
        assertEq(vault.owner(), alice, "assert vault.owner() == alice");
        assertEq(vault.market(), address(market), "assert vault.market() == address(market)");
        assertEq(vault.lockup(), VAULT_LOCKUP, "assert vault.lockup() == VAULT_LOCKUP");
        assertEq(vault.orderCap(), FACTORY_MAX_ORDER_CAP, "assert vault.orderCap() == FACTORY_MAX_ORDER_CAP");
        assertEq(vault.totalSupply(), expectedShares, "assert vault.totalSupply() == expectedShares");
        assertEq(vault.balanceOf(alice), expectedShares, "assert vault.balanceOf(alice) == expectedShares");
        assertEq(
            vault.unlockTimestamp(alice),
            block.timestamp + VAULT_LOCKUP,
            "assert vault.unlockTimestamp(alice) == block.timestamp + VAULT_LOCKUP"
        );
    }

    function _assertInitialVaultBalances(ICrystalVault vault) private view {
        (uint256 quoteBalance, uint256 baseBalance, uint256 availableQuote, uint256 availableBase) = vault.getBalances();
        assertEq(quoteBalance, INITIAL_QUOTE_AMOUNT, "assert quoteBalance == INITIAL_QUOTE_AMOUNT");
        assertEq(baseBalance, INITIAL_BASE_AMOUNT, "assert baseBalance == INITIAL_BASE_AMOUNT");
        assertEq(availableQuote, INITIAL_QUOTE_AMOUNT, "assert availableQuote == INITIAL_QUOTE_AMOUNT");
        assertEq(availableBase, INITIAL_BASE_AMOUNT, "assert availableBase == INITIAL_BASE_AMOUNT");
    }

    function _deployVaultFrom(address owner, string memory name) private returns (address vault) {
        _approveFactory(owner);

        vm.prank(owner);
        vault = vaultFactory.deploy(
            address(quote),
            address(weth),
            INITIAL_QUOTE_AMOUNT,
            INITIAL_BASE_AMOUNT,
            0,
            VAULT_LOCKUP,
            false,
            _metadata(name)
        );
    }

    function _approveFactory(address account) private {
        vm.startPrank(account);
        quote.approve(address(vaultFactory), type(uint256).max);
        weth.approve(address(vaultFactory), type(uint256).max);
        vm.stopPrank();
    }

    function _previewDeposit(address vault, uint256 quoteDesired, uint256 baseDesired)
        private
        view
        returns (uint256[3] memory preview)
    {
        (preview[SHARES_INDEX], preview[QUOTE_INDEX], preview[BASE_INDEX]) =
            vaultFactory.previewDeposit(vault, quoteDesired, baseDesired);
    }

    function _depositFrom(
        address user,
        address vault,
        uint256 quoteDesired,
        uint256 baseDesired,
        uint256[3] memory preview
    ) private returns (uint256[3] memory deposited) {
        _approveFactory(user);

        vm.prank(user);
        (deposited[SHARES_INDEX], deposited[QUOTE_INDEX], deposited[BASE_INDEX]) = vaultFactory.deposit(
            vault, address(quote), address(weth), quoteDesired, baseDesired, preview[QUOTE_INDEX], preview[BASE_INDEX]
        );
    }

    function _assertVaultBalances(ICrystalVault vault, uint256[3] memory preview) private view {
        (uint256 quoteBalance, uint256 baseBalance,,) = vault.getBalances();
        assertEq(
            quoteBalance,
            INITIAL_QUOTE_AMOUNT + preview[QUOTE_INDEX],
            "assert quoteBalance == INITIAL_QUOTE_AMOUNT + preview[QUOTE_INDEX]"
        );
        assertEq(
            baseBalance,
            INITIAL_BASE_AMOUNT + preview[BASE_INDEX],
            "assert baseBalance == INITIAL_BASE_AMOUNT + preview[BASE_INDEX]"
        );
    }

    function _assertFactoryBalance(address vault, address user, uint256[3] memory preview) private view {
        (uint256 factoryShares, uint256 factoryQuoteAmount, uint256 factoryBaseAmount) =
            vaultFactory.balanceOf(vault, user);
        assertEq(factoryShares, preview[SHARES_INDEX], "assert factoryShares == preview[SHARES_INDEX]");
        assertApproxEqAbs(
            factoryQuoteAmount, preview[QUOTE_INDEX], 1, "assert |factoryQuoteAmount - preview[QUOTE_INDEX]| <= 1"
        );
        assertApproxEqAbs(
            factoryBaseAmount, preview[BASE_INDEX], 1e6, "assert |factoryBaseAmount - preview[BASE_INDEX]| <= 1e6"
        );
    }

    function _assertFactoryBalance(
        address vault,
        address user,
        uint256 expectedShares,
        uint256 expectedQuoteAmount,
        uint256 expectedBaseAmount
    ) private view {
        (uint256 factoryShares, uint256 factoryQuoteAmount, uint256 factoryBaseAmount) =
            vaultFactory.balanceOf(vault, user);
        assertEq(factoryShares, expectedShares, "assert factoryShares == expectedShares");
        assertEq(factoryQuoteAmount, expectedQuoteAmount, "assert factoryQuoteAmount == expectedQuoteAmount");
        assertEq(factoryBaseAmount, expectedBaseAmount, "assert factoryBaseAmount == expectedBaseAmount");
    }

    function _storedTotalShares(address vault) private view returns (uint256 totalShares) {
        (,,, totalShares,,,,,,) = vaultFactory.getVault(vault);
    }

    function _metadata(string memory name) private pure returns (ICrystalVault.VaultMetaData memory) {
        return ICrystalVault.VaultMetaData({
            name: name, description: "Focused vault deposit unit test", social1: "", social2: "", social3: ""
        });
    }
}
