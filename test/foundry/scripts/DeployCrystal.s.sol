// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script } from "forge-std/Script.sol";

import { Crystal } from "../../../contracts/core/Crystal.sol";
import { ICrystal } from "../../../contracts/interfaces/ICrystal.sol";
import { CrystalDeploymentConfig } from "./CrystalDeploymentConfig.sol";

contract DeployCrystalScript is Script {
    function run() public returns (Crystal crystal) {
        vm.startBroadcast();
        crystal = deploy(_crystalConfigFromEnv());
        vm.stopBroadcast();
    }

    function deploy(CrystalDeploymentConfig.CrystalConfig memory config) public returns (Crystal crystal) {
        crystal = new Crystal(
            config.weth,
            config.governance,
            config.feeRecipient,
            config.feeCommission,
            config.feeClaimDuration,
            config.launchpadParams
        );
    }

    function _crystalConfigFromEnv() private view returns (CrystalDeploymentConfig.CrystalConfig memory) {
        return CrystalDeploymentConfig.CrystalConfig({
            weth: vm.envAddress("CRYSTAL_WETH"),
            governance: vm.envAddress("CRYSTAL_GOVERNANCE"),
            feeRecipient: vm.envAddress("CRYSTAL_FEE_RECIPIENT"),
            feeCommission: uint8(vm.envUint("CRYSTAL_FEE_COMMISSION")),
            feeClaimDuration: vm.envUint("CRYSTAL_FEE_CLAIM_DURATION"),
            launchpadParams: ICrystal.LaunchpadParams({
                launchpadInitialNativeSupply: uint112(vm.envUint("CRYSTAL_LAUNCHPAD_INITIAL_NATIVE_SUPPLY")),
                launchpadFee: vm.envUint("CRYSTAL_LAUNCHPAD_FEE"),
                launchpadCreatorFeeSplit: vm.envUint("CRYSTAL_LAUNCHPAD_CREATOR_FEE_SPLIT"),
                graduatedMinSize: vm.envUint("CRYSTAL_GRADUATED_MIN_SIZE"),
                graduatedTakerFee: vm.envUint("CRYSTAL_GRADUATED_TAKER_FEE"),
                graduatedMakerRebate: vm.envUint("CRYSTAL_GRADUATED_MAKER_REBATE"),
                graduatedCreatorFeeSplit: vm.envUint("CRYSTAL_GRADUATED_CREATOR_FEE_SPLIT")
            })
        });
    }
}
