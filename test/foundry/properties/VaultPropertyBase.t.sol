// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ICrystalVault } from "../../../contracts/interfaces/ICrystalVault.sol";
import { ICrystalVaultFactory } from "../../../contracts/interfaces/ICrystalVaultFactory.sol";
import { CrystalVaultFactory } from "../../../contracts/vaults/CrystalVaultFactory.sol";
import { BaseFuzzTest } from "../BaseFuzzTest.t.sol";

abstract contract VaultPropertyBase is BaseFuzzTest {
    struct VaultBalances {
        uint256 quoteBalance;
        uint256 baseBalance;
        uint256 availableQuote;
        uint256 availableBase;
    }

    uint16 internal constant PROPERTY_MAX_ORDER_CAP = 100;
    uint40 internal constant PROPERTY_MAX_LOCKUP = 0;
    uint256 internal constant SHARES_INDEX = 0;
    uint256 internal constant QUOTE_INDEX = 1;
    uint256 internal constant BASE_INDEX = 2;

    ICrystalVaultFactory internal vaultFactory;

    function setUp() public virtual override {
        super.setUp();

        vaultFactory = ICrystalVaultFactory(
            address(
                new CrystalVaultFactory(
                    address(crystal), CRYSTAL_GOVERNANCE, address(weth), 0, PROPERTY_MAX_ORDER_CAP, PROPERTY_MAX_LOCKUP
                )
            )
        );
    }

    function _deployVault(
        address owner,
        uint256 amountQuote,
        uint256 amountBase,
        bool decreaseOnWithdraw,
        uint40 lockup
    ) internal returns (ICrystalVault vault) {
        return _deployVault(owner, amountQuote, amountBase, 0, decreaseOnWithdraw, lockup);
    }

    function _deployVault(
        address owner,
        uint256 amountQuote,
        uint256 amountBase,
        uint256 maxShares,
        bool decreaseOnWithdraw,
        uint40 lockup
    ) internal returns (ICrystalVault vault) {
        _approveVaultFactory(owner);

        vm.prank(owner);
        vault = ICrystalVault(
            vaultFactory.deploy(
                address(quote),
                address(weth),
                amountQuote,
                amountBase,
                maxShares,
                lockup,
                decreaseOnWithdraw,
                _metadata()
            )
        );
    }

    function _depositIntoVault(
        address user,
        address vault,
        uint256 amountQuoteDesired,
        uint256 amountBaseDesired,
        uint256 amountQuoteMin,
        uint256 amountBaseMin
    ) internal returns (uint256 shares, uint256 amountQuote, uint256 amountBase) {
        _approveVaultFactory(user);

        vm.prank(user);
        return vaultFactory.deposit(
            vault, address(quote), address(weth), amountQuoteDesired, amountBaseDesired, amountQuoteMin, amountBaseMin
        );
    }

    function _withdrawFromVault(
        address user,
        address vault,
        uint256 shares,
        uint256 amountQuoteMin,
        uint256 amountBaseMin
    ) internal returns (uint256 amountQuote, uint256 amountBase) {
        vm.prank(user);
        return vaultFactory.withdraw(vault, address(quote), address(weth), shares, amountQuoteMin, amountBaseMin);
    }

    function _previewDeposit(address vault, uint256 quoteDesired, uint256 baseDesired)
        internal
        view
        returns (uint256[3] memory preview)
    {
        (preview[SHARES_INDEX], preview[QUOTE_INDEX], preview[BASE_INDEX]) =
            vaultFactory.previewDeposit(vault, quoteDesired, baseDesired);
    }

    function _previewWithdrawal(address vault, uint256 shares)
        internal
        view
        returns (uint256 amountQuote, uint256 amountBase)
    {
        return vaultFactory.previewWithdrawal(vault, shares);
    }

    function _executeVaultAction(
        ICrystalVault vault,
        address owner,
        BatchAction action,
        uint256 cloid,
        uint256 param1,
        uint256 param2
    ) internal {
        vm.prank(owner);
        vault.execute(_singleVaultAction(action, cloid, param1, param2), 0);
    }

    function _singleVaultAction(BatchAction action, uint256 cloid, uint256 param1, uint256 param2)
        internal
        pure
        returns (ICrystalVault.Action[] memory actions)
    {
        actions = new ICrystalVault.Action[](1);
        actions[0] = ICrystalVault.Action({
            requireSuccess: true, action: uint256(action), param1: param1, param2: param2, cloid: cloid
        });
    }

    function _vaultBalanceTuple(ICrystalVault vault)
        internal
        view
        returns (uint256 quoteBalance, uint256 baseBalance, uint256 availableQuote, uint256 availableBase)
    {
        return vault.getBalances();
    }

    function _vaultBalances(ICrystalVault vault) internal view returns (VaultBalances memory balances) {
        (balances.quoteBalance, balances.baseBalance, balances.availableQuote, balances.availableBase) =
            vault.getBalances();
    }

    function _storedTotalShares(address vault) internal view returns (uint256 totalShares) {
        (,,, totalShares,,,,,,) = vaultFactory.getVault(vault);
    }

    function _boundVaultQuote(uint256 amount) internal pure returns (uint256) {
        return bound(amount, MARKET_MIN_SIZE * 20, 100_000 * QUOTE_UNIT);
    }

    function _boundVaultBase(uint256 amount) internal pure returns (uint256) {
        return bound(amount, 20 ether, 1_000 ether);
    }

    function _boundFollowOnQuote(uint256 amount, uint256 initialQuote) internal pure returns (uint256) {
        return bound(amount, MARKET_MIN_SIZE * 2, initialQuote);
    }

    function _boundFollowOnBase(uint256 amount, uint256 initialBase) internal pure returns (uint256) {
        return bound(amount, 2 ether, initialBase);
    }

    function _assertCrystalBalance(address account, address token, uint256 expectedTotal, uint256 expectedAvailable)
        internal
        view
    {
        (uint256 totalBalance, uint256 availableBalance, uint256 lockedBalance) =
            crystal.getDepositedBalance(account, token);

        assertEq(totalBalance, expectedTotal, "assert totalBalance == expectedTotal");
        assertEq(availableBalance, expectedAvailable, "assert availableBalance == expectedAvailable");
        assertEq(
            lockedBalance,
            expectedTotal - expectedAvailable,
            "assert lockedBalance == expectedTotal - expectedAvailable"
        );
    }

    function _approveVaultFactory(address account) internal {
        vm.startPrank(account);
        quote.approve(address(vaultFactory), type(uint256).max);
        weth.approve(address(vaultFactory), type(uint256).max);
        vm.stopPrank();
    }

    function _metadata() internal pure returns (ICrystalVault.VaultMetaData memory) {
        return ICrystalVault.VaultMetaData({
            name: "Property Vault", description: "Foundry accounting properties", social1: "", social2: "", social3: ""
        });
    }
}
