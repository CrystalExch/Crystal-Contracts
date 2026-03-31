// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC20} from '../interfaces/IERC20.sol';

interface IVault {
    function sweep() external;
}

struct VaultMetaData {
    string name;
    string description;
    string social1;
    string social2;
    string social3;
}

interface IVaultFactory {
    function deploy(
        address quoteAsset,
        address baseAsset,
        uint256 amountQuote,
        uint256 amountBase,
        uint256 maxShares,
        uint40 lockup,
        bool decreaseOnWithdraw,
        VaultMetaData memory metadata
    ) external payable returns (address vault);
}

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
        VaultMetaData memory metadata = VaultMetaData("Test", "Test", "", "", "");
        return IVaultFactory(factory).deploy{value: msg.value}(
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
        IVault(vault).sweep();
    }

    receive() external payable {
        revert();
    }
}
