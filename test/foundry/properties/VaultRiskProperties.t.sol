// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ICrystal } from "../../../contracts/interfaces/ICrystal.sol";
import { ICrystalVault } from "../../../contracts/interfaces/ICrystalVault.sol";
import { VaultPropertyBase } from "./VaultPropertyBase.t.sol";

contract VaultRiskProperties is VaultPropertyBase {
    function testOrderCapRejectsExcessActiveOrdersWithoutMovingBalances() public {
        ICrystalVault vault = _deployVault(alice, 20_000 * QUOTE_UNIT, 200 ether, false, 0);
        address vaultAddress = address(vault);
        uint256 firstPrice = _price(500);
        uint256 excessPrice = _price(600);
        uint256 firstSize = 2_000 * QUOTE_UNIT;
        uint256 excessSize = 3_000 * QUOTE_UNIT;

        vm.prank(alice);
        vaultFactory.changeOrderCap(vaultAddress, 2);

        _executeVaultAction(vault, alice, BatchAction.BuyLimit, 1, firstPrice, firstSize);
        VaultBalances memory beforeExcessOrder = _vaultBalances(vault);

        vm.prank(alice);
        vm.expectRevert();
        vault.execute(_singleVaultAction(BatchAction.BuyLimit, 2, excessPrice, excessSize), 0);

        VaultBalances memory afterExcessOrder = _vaultBalances(vault);
        ICrystal.PriceLevel memory excessLevel = crystal.getPriceLevel(address(market), excessPrice);

        assertEq(
            afterExcessOrder.quoteBalance,
            beforeExcessOrder.quoteBalance,
            "assert afterExcessOrder.quoteBalance == beforeExcessOrder.quoteBalance"
        );
        assertEq(
            afterExcessOrder.availableQuote,
            beforeExcessOrder.availableQuote,
            "assert afterExcessOrder.availableQuote == beforeExcessOrder.availableQuote"
        );
        assertEq(excessLevel.size, 0, "assert excessLevel.size == 0");
    }

    function testMaxLockupRejectsExcessLockupWithoutMovingBalances() public {
        vm.prank(CRYSTAL_GOVERNANCE);
        vaultFactory.changeMaxLockup(1 days);

        ICrystalVault vault = _deployVault(alice, 20_000 * QUOTE_UNIT, 200 ether, false, 1 days);
        address vaultAddress = address(vault);
        VaultBalances memory beforeChange = _vaultBalances(vault);

        vm.prank(alice);
        vm.expectRevert();
        vaultFactory.changeLockup(vaultAddress, 2 days);

        VaultBalances memory afterChange = _vaultBalances(vault);

        assertEq(
            afterChange.quoteBalance,
            beforeChange.quoteBalance,
            "assert afterChange.quoteBalance == beforeChange.quoteBalance"
        );
        assertEq(
            afterChange.baseBalance,
            beforeChange.baseBalance,
            "assert afterChange.baseBalance == beforeChange.baseBalance"
        );
        assertEq(vault.lockup(), 1 days, "assert vault.lockup() == 1 days");
    }

    function testVaultAndEoaLimitOrdersUseSameCollateralSemantics() public {
        ICrystalVault vault = _deployVault(alice, 20_000 * QUOTE_UNIT, 200 ether, false, 0);
        address vaultAddress = address(vault);
        uint256 price = _price(500);
        uint256 size = 2_000 * QUOTE_UNIT;
        _executeInternalLimitOrder(bob, BatchAction.BuyLimit, price, size);
        _executeVaultAction(vault, alice, BatchAction.BuyLimit, 1, price, size);

        (uint256 bobTotal, uint256 bobAvailable, uint256 bobLocked) = crystal.getDepositedBalance(bob, address(quote));
        (uint256 vaultTotal, uint256 vaultAvailable, uint256 vaultLocked) =
            crystal.getDepositedBalance(vaultAddress, address(quote));
        ICrystal.Order memory vaultOrder = crystal.getOrderByCloid(crystal.addressToUserId(vaultAddress), 1);

        assertEq(bobTotal - bobAvailable, size, "assert bobTotal - bobAvailable == size");
        assertEq(vaultTotal - vaultAvailable, size, "assert vaultTotal - vaultAvailable == size");
        assertEq(bobLocked, size, "assert bobLocked == size");
        assertEq(vaultLocked, size, "assert vaultLocked == size");
        assertEq(vaultOrder.size, size, "assert vaultOrder.size == size");
    }

    function _singleAction(BatchAction action, uint256 param1, uint256 param2, uint256 param3)
        private
        pure
        returns (ICrystal.Action[] memory actions)
    {
        actions = new ICrystal.Action[](1);
        actions[0] = ICrystal.Action({
            isRequireSuccess: true, action: uint256(action), param1: param1, param2: param2, param3: param3
        });
    }

    function _executeInternalLimitOrder(address user, BatchAction action, uint256 price, uint256 size) private {
        _executeFallbackAs(
            user,
            abi.encodePacked(_batchHeader(BATCH_BALANCE_MODE_INTERNAL, 1), _limitAction(action, true, 0, price, size))
        );
    }

    function _batchHeader(uint256 balanceMode, uint256 actionCount) private view returns (bytes32) {
        return bytes32(
            (balanceMode << BATCH_BALANCE_MODE_SHIFT) | (actionCount << BATCH_ACTION_COUNT_SHIFT)
                | uint160(address(market))
        );
    }

    function _limitAction(BatchAction action, bool requireSuccess, uint256 cloid, uint256 price, uint256 size)
        private
        pure
        returns (bytes32)
    {
        return bytes32(
            (uint256(action) << BATCH_ACTION_SHIFT) | (requireSuccess ? (uint256(1) << BATCH_REQUIRE_SUCCESS_SHIFT) : 0)
                | ((cloid & BATCH_CLOID_MASK) << BATCH_CLOID_SHIFT)
                | ((price & BATCH_PARAM1_MASK) << BATCH_PARAM1_SHIFT) | (size & BATCH_PARAM2_MASK)
        );
    }

    function _executeFallbackAs(address caller, bytes memory data) private {
        vm.prank(caller);
        (bool success, bytes memory returnData) = address(crystal).call(data);
        if (!success) {
            assembly {
                revert(add(returnData, 32), mload(returnData))
            }
        }
    }
}
