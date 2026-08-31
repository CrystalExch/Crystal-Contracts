// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script } from "forge-std/Script.sol";

import { WETH } from "../../../contracts/mocks/TestToken.sol";

contract DeployWETHScript is Script {
    function run() public returns (WETH weth) {
        vm.startBroadcast();
        weth = deploy();
        vm.stopBroadcast();
    }

    function deploy() public returns (WETH weth) {
        weth = new WETH();
    }
}
