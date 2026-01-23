// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {CrystalVault} from "../vaults/CrystalVault.sol";
import {ICrystalVault} from "../interfaces/ICrystalVault.sol";

contract TestVaultDeployer {
    uint16 public maxOrderCap = 100;
    uint40 public maxLockup = 0;

    function deployVault(
        address _crystal,
        address _quoteAsset,
        address _baseAsset,
        address _owner,
        string memory _symbol,
        ICrystalVault.VaultMetaData memory _metadata
    ) external returns (address) {
        CrystalVault vault = new CrystalVault(
            _crystal,
            _quoteAsset,
            _baseAsset,
            _owner,
            _symbol,
            _metadata
        );
        return address(vault);
    }
}
