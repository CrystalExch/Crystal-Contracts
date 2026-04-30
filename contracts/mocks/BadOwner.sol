// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC20} from '../interfaces/IERC20.sol';
import {ICrystalVault} from "../interfaces/ICrystalVault.sol";
import {ICrystalVaultFactory} from "../interfaces/ICrystalVaultFactory.sol";

contract BadOwner {
    function approveToken(address token, address spender, uint256 amount) external {
        IERC20(token).approve(spender, amount);
    }

    function deployVault(
        address factory,
        address quoteAsset,
        address baseAsset,
        uint256 amountQuote,
        uint256 amountBase
    ) external payable returns (address) {
        ICrystalVault.VaultMetaData memory metadata = ICrystalVault.VaultMetaData("Test", "Test", "", "", "");
        return ICrystalVaultFactory(factory).deploy{value: msg.value}(
            quoteAsset,
            baseAsset,
            amountQuote,
            amountBase,
            0,
            0,
            true,
            metadata
        );
    }

    function callSweep(address vault) external {
        ICrystalVault(vault).sweep();
    }

    receive() external payable {
        revert();
    }
}
