// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ICrystalVault } from "../../../contracts/interfaces/ICrystalVault.sol";
import { ICrystalVaultFactory } from "../../../contracts/interfaces/ICrystalVaultFactory.sol";
import { CrystalMath } from "../../../contracts/libraries/CrystalMath.sol";
import { CrystalVaultFactory } from "../../../contracts/vaults/CrystalVaultFactory.sol";
import { BaseFuzzTest } from "../BaseFuzzTest.t.sol";

contract VaultDepositFuzzTest is BaseFuzzTest {
    uint256 private constant FACTORY_MIN_DEPOSIT = 100;
    uint16 private constant FACTORY_MAX_ORDER_CAP = 64;
    uint40 private constant FACTORY_MAX_LOCKUP = 7 days;
    uint40 private constant VAULT_LOCKUP = 1 days;
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

    function testFuzzDeployVaultWithInitialDepositMintsOwnerSharesAndStoresVaultState(
        uint256 initialQuoteSeed,
        uint256 initialBaseSeed,
        uint256 nameSeed
    ) public {
        uint256 initialQuoteAmount = _boundVaultQuote(initialQuoteSeed);
        uint256 initialBaseAmount = _boundVaultBase(initialBaseSeed);
        string memory vaultName = string.concat("Initial Deposit Vault ", vm.toString(bound(nameSeed, 0, 1_000_000)));
        address vaultAddress = _deployVaultFrom(alice, vaultName, initialQuoteAmount, initialBaseAmount);
        uint256 expectedShares = CrystalMath._sqrt(initialQuoteAmount * initialBaseAmount);

        _assertStoredVaultState(vaultAddress, expectedShares, vaultName);
        _assertVaultDeploymentState(vaultAddress, expectedShares);
        _assertInitialVaultBalances(ICrystalVault(vaultAddress), initialQuoteAmount, initialBaseAmount);
        _assertFactoryBalance(vaultAddress, alice, expectedShares, initialQuoteAmount, initialBaseAmount);
    }

    function testFuzzDepositIntoExistingVaultMintsPreviewedSharesAndRefundsUnusedBase(
        uint256 initialQuoteSeed,
        uint256 initialBaseSeed,
        uint256 quoteDesiredSeed,
        uint256 baseDesiredSeed
    ) public {
        uint256 initialQuoteAmount = _boundVaultQuote(initialQuoteSeed);
        uint256 initialBaseAmount = _boundVaultBase(initialBaseSeed);
        address vaultAddress = _deployVaultFrom(alice, "Share Mint Vault", initialQuoteAmount, initialBaseAmount);
        ICrystalVault vault = ICrystalVault(vaultAddress);
        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 bobQuoteBefore = quote.balanceOf(bob);
        uint256 bobBaseBefore = weth.balanceOf(bob);
        uint256 quoteDesired =
            bound(quoteDesiredSeed, _minFollowOn(initialQuoteAmount, MARKET_MIN_SIZE), initialQuoteAmount);
        uint256 baseDesired =
            bound(baseDesiredSeed, _minFollowOn(initialBaseAmount, MIN_ETH_FUZZ_AMOUNT), initialBaseAmount);
        uint256[3] memory preview = _previewDeposit(vaultAddress, quoteDesired, baseDesired);
        (uint256 expectedQuote, uint256 expectedBase) =
            _expectedDepositAmounts(initialQuoteAmount, initialBaseAmount, quoteDesired, baseDesired);

        assertGt(preview[SHARES_INDEX], 0, "assert preview[SHARES_INDEX] > 0");
        assertEq(preview[QUOTE_INDEX], expectedQuote, "assert preview[QUOTE_INDEX] == expectedQuote");
        assertEq(preview[BASE_INDEX], expectedBase, "assert preview[BASE_INDEX] == expectedBase");

        uint256[3] memory deposited = _depositFrom(bob, vaultAddress, quoteDesired, baseDesired, preview);

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

        _assertVaultBalances(vault, initialQuoteAmount, initialBaseAmount, preview);
        _assertFactoryBalance(vaultAddress, bob, preview[SHARES_INDEX]);
    }

    function testFuzzDepositIntoExistingVaultReturnsPreviewedSharesQuoteAndBase(
        uint256 initialQuoteSeed,
        uint256 initialBaseSeed,
        uint256 quoteDesiredSeed,
        uint256 baseDesiredSeed
    ) public {
        uint256 initialQuoteAmount = _boundVaultQuote(initialQuoteSeed);
        uint256 initialBaseAmount = _boundVaultBase(initialBaseSeed);
        address vaultAddress = _deployVaultFrom(alice, "Share Mint Vault", initialQuoteAmount, initialBaseAmount);
        uint256 quoteDesired =
            bound(quoteDesiredSeed, _minFollowOn(initialQuoteAmount, MARKET_MIN_SIZE), initialQuoteAmount);
        uint256 baseDesired =
            bound(baseDesiredSeed, _minFollowOn(initialBaseAmount, MIN_ETH_FUZZ_AMOUNT), initialBaseAmount);
        uint256[3] memory preview = _previewDeposit(vaultAddress, quoteDesired, baseDesired);

        assertGt(preview[SHARES_INDEX], 0, "assert preview[SHARES_INDEX] > 0");

        uint256[3] memory deposited = _depositFrom(bob, vaultAddress, quoteDesired, baseDesired, preview);

        assertEq(
            deposited[SHARES_INDEX], preview[SHARES_INDEX], "assert deposited[SHARES_INDEX] == preview[SHARES_INDEX]"
        );
        assertEq(deposited[QUOTE_INDEX], preview[QUOTE_INDEX], "assert deposited[QUOTE_INDEX] == preview[QUOTE_INDEX]");
        assertEq(deposited[BASE_INDEX], preview[BASE_INDEX], "assert deposited[BASE_INDEX] == preview[BASE_INDEX]");
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

    function _assertInitialVaultBalances(ICrystalVault vault, uint256 initialQuoteAmount, uint256 initialBaseAmount)
        private
        view
    {
        (uint256 quoteBalance, uint256 baseBalance, uint256 availableQuote, uint256 availableBase) = vault.getBalances();
        assertEq(quoteBalance, initialQuoteAmount, "assert quoteBalance == initialQuoteAmount");
        assertEq(baseBalance, initialBaseAmount, "assert baseBalance == initialBaseAmount");
        assertEq(availableQuote, initialQuoteAmount, "assert availableQuote == initialQuoteAmount");
        assertEq(availableBase, initialBaseAmount, "assert availableBase == initialBaseAmount");
    }

    function _deployVaultFrom(address owner, string memory name, uint256 amountQuote, uint256 amountBase)
        private
        returns (address vault)
    {
        _approveFactory(owner);

        vm.prank(owner);
        vault = vaultFactory.deploy(
            address(quote), address(weth), amountQuote, amountBase, 0, VAULT_LOCKUP, false, _metadata(name)
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

    function _assertVaultBalances(
        ICrystalVault vault,
        uint256 initialQuoteAmount,
        uint256 initialBaseAmount,
        uint256[3] memory preview
    ) private view {
        (uint256 quoteBalance, uint256 baseBalance,,) = vault.getBalances();
        assertEq(
            quoteBalance,
            initialQuoteAmount + preview[QUOTE_INDEX],
            "assert quoteBalance == initialQuoteAmount + preview[QUOTE_INDEX]"
        );
        assertEq(
            baseBalance,
            initialBaseAmount + preview[BASE_INDEX],
            "assert baseBalance == initialBaseAmount + preview[BASE_INDEX]"
        );
    }

    function _assertFactoryBalance(address vault, address user, uint256 expectedShares) private view {
        (uint256 factoryShares, uint256 factoryQuoteAmount, uint256 factoryBaseAmount) =
            vaultFactory.balanceOf(vault, user);
        (uint256 expectedQuoteAmount, uint256 expectedBaseAmount) =
            vaultFactory.previewWithdrawal(vault, expectedShares);
        assertEq(factoryShares, expectedShares, "assert factoryShares == expectedShares");
        assertEq(factoryQuoteAmount, expectedQuoteAmount, "assert factoryQuoteAmount == expectedQuoteAmount");
        assertEq(factoryBaseAmount, expectedBaseAmount, "assert factoryBaseAmount == expectedBaseAmount");
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

    function _expectedDepositAmounts(
        uint256 initialQuoteAmount,
        uint256 initialBaseAmount,
        uint256 quoteDesired,
        uint256 baseDesired
    ) private pure returns (uint256 amountQuote, uint256 amountBase) {
        uint256 amountBaseOptimal = (quoteDesired * initialBaseAmount) / initialQuoteAmount;
        if (amountBaseOptimal <= baseDesired) {
            amountQuote = quoteDesired;
            amountBase = amountBaseOptimal;
        } else {
            uint256 amountQuoteOptimal = (baseDesired * initialQuoteAmount) / initialBaseAmount;
            amountQuote = amountQuoteOptimal;
            amountBase = baseDesired;
        }
    }

    function _storedTotalShares(address vault) private view returns (uint256 totalShares) {
        (,,, totalShares,,,,,,) = vaultFactory.getVault(vault);
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

    function _metadata(string memory name) private pure returns (ICrystalVault.VaultMetaData memory) {
        return ICrystalVault.VaultMetaData({
            name: name, description: "Focused vault deposit unit test", social1: "", social2: "", social3: ""
        });
    }
}
