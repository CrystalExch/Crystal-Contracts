// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ERC20} from "../vaults/CrystalVault.sol";

contract TestVaultERC20 is ERC20 {
    constructor() ERC20("Test", "TEST") {}

    function mint(address to, uint256 value) external {
        _mint(to, value);
    }

    function burn(address from, uint256 value) external {
        _burn(from, value);
    }
}
