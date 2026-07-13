// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ICrystalVault } from "../../../contracts/interfaces/ICrystalVault.sol";
import { CrystalVaultFactory } from "../../../contracts/vaults/CrystalVaultFactory.sol";
import { BaseTest } from "../BaseTest.t.sol";

contract VaultWithdrawTest is BaseTest {
    CrystalVaultFactory private vaultFactory;

    function setUp() public override {
        super.setUp();

        vaultFactory = new CrystalVaultFactory(address(crystal), CRYSTAL_GOVERNANCE, address(weth), 0, 100, 0);

        _approveVaultFactory(alice);
        _approveVaultFactory(bob);
        _approveVaultFactory(carol);
    }

    function testPartialWithdrawalThroughFactoryBurnsSharesAndReturnsAssets() public {
        address vault = _deployVault(carol, 1_000 * QUOTE_UNIT, 10 ether);
        uint256 bobShares = _depositIntoVault(bob, vault, 500 * QUOTE_UNIT, 5 ether);
        ICrystalVault vaultToken = ICrystalVault(vault);
        uint256 sharesToWithdraw = bobShares / 2;
        uint256 bobQuoteBefore = quote.balanceOf(bob);
        uint256 bobBaseBefore = weth.balanceOf(bob);
        (uint256 expectedQuote, uint256 expectedBase) = vaultFactory.previewWithdrawal(vault, sharesToWithdraw);

        vm.prank(bob);
        (uint256 amountQuote, uint256 amountBase) =
            vaultFactory.withdraw(vault, address(quote), address(weth), sharesToWithdraw, expectedQuote, expectedBase);

        (uint256 quoteBalance, uint256 baseBalance, uint256 availableQuote, uint256 availableBase) =
            vaultToken.getBalances();

        assertEq(amountQuote, expectedQuote, "assert amountQuote == expectedQuote");
        assertEq(amountBase, expectedBase, "assert amountBase == expectedBase");
        assertEq(
            vaultToken.balanceOf(bob),
            bobShares - sharesToWithdraw,
            "assert vaultToken.balanceOf(bob) == bobShares - sharesToWithdraw"
        );
        assertEq(
            quote.balanceOf(bob),
            bobQuoteBefore + amountQuote,
            "assert quote.balanceOf(bob) == bobQuoteBefore + amountQuote"
        );
        assertEq(
            weth.balanceOf(bob), bobBaseBefore + amountBase, "assert weth.balanceOf(bob) == bobBaseBefore + amountBase"
        );
        assertEq(availableQuote, quoteBalance, "assert availableQuote == quoteBalance");
        assertEq(availableBase, baseBalance, "assert availableBase == baseBalance");
        assertFalse(vaultToken.closed(), "assert !vaultToken.closed()");
        assertFalse(vaultToken.locked(), "assert !vaultToken.locked()");
    }

    function testFullOwnerWithdrawalViaCloseReturnsAssetsAndMarksVaultClosed() public {
        uint256 ownerQuoteAmount = 1_200 * QUOTE_UNIT;
        uint256 ownerBaseAmount = 12 ether;
        address vault = _deployVault(carol, ownerQuoteAmount, ownerBaseAmount);
        ICrystalVault vaultToken = ICrystalVault(vault);

        uint256 ownerShares = vaultToken.balanceOf(carol);
        uint256 carolQuoteBefore = quote.balanceOf(carol);
        uint256 carolBaseBefore = weth.balanceOf(carol);
        (uint256 expectedQuote, uint256 expectedBase) = vaultFactory.previewWithdrawal(vault, ownerShares);

        vm.prank(carol);
        (uint256 amountQuote, uint256 amountBase) = vaultFactory.close(vault);

        assertEq(amountQuote, expectedQuote, "assert amountQuote == expectedQuote");
        assertEq(amountBase, expectedBase, "assert amountBase == expectedBase");
        assertEq(vaultToken.balanceOf(carol), 0, "assert vaultToken.balanceOf(carol) == 0");
        assertEq(vaultToken.totalSupply(), 0, "assert vaultToken.totalSupply() == 0");
        assertEq(
            quote.balanceOf(carol),
            carolQuoteBefore + amountQuote,
            "assert quote.balanceOf(carol) == carolQuoteBefore + amountQuote"
        );
        assertEq(
            weth.balanceOf(carol),
            carolBaseBefore + amountBase,
            "assert weth.balanceOf(carol) == carolBaseBefore + amountBase"
        );
        _assertVaultClosedWithNoDeposits(vaultToken);
        _assertFactoryClosed(vault);
    }

    function _assertVaultClosedWithNoDeposits(ICrystalVault vaultToken) private view {
        (uint256 quoteBalance, uint256 baseBalance, uint256 availableQuote, uint256 availableBase) =
            vaultToken.getBalances();

        assertEq(quoteBalance, 0, "assert quoteBalance == 0");
        assertEq(baseBalance, 0, "assert baseBalance == 0");
        assertEq(availableQuote, 0, "assert availableQuote == 0");
        assertEq(availableBase, 0, "assert availableBase == 0");
        assertTrue(vaultToken.closed(), "assert vaultToken.closed()");
        assertTrue(vaultToken.locked(), "assert vaultToken.locked()");
    }

    function _assertFactoryClosed(address vault) private view {
        (,,, uint256 trackedShares,,,, bool factoryLocked, bool factoryClosed,) = vaultFactory.getVault(vault);

        assertEq(trackedShares, 0, "assert trackedShares == 0");
        assertTrue(factoryClosed, "assert factoryClosed");
        assertTrue(factoryLocked, "assert factoryLocked");
    }

    function _approveVaultFactory(address account) private {
        vm.startPrank(account);
        quote.approve(address(vaultFactory), type(uint256).max);
        weth.approve(address(vaultFactory), type(uint256).max);
        vm.stopPrank();
    }

    function _deployVault(address owner, uint256 amountQuote, uint256 amountBase) private returns (address vault) {
        vm.prank(owner);
        vault = vaultFactory.deploy(
            address(quote), address(weth), amountQuote, amountBase, 0, 0, false, _vaultMetadata()
        );
    }

    function _depositIntoVault(address user, address vault, uint256 amountQuote, uint256 amountBase)
        private
        returns (uint256 shares)
    {
        vm.prank(user);
        (shares,,) = vaultFactory.deposit(vault, address(quote), address(weth), amountQuote, amountBase, 0, 0);
    }

    function _vaultMetadata() private pure returns (ICrystalVault.VaultMetaData memory) {
        return ICrystalVault.VaultMetaData({
            name: "Withdraw Vault", description: "Withdrawal focused test vault", social1: "", social2: "", social3: ""
        });
    }
}
