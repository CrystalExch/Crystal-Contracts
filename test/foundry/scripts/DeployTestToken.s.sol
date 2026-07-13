// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script } from "forge-std/Script.sol";

import { TestToken } from "../../../contracts/mocks/TestToken.sol";

contract DeployTestTokenScript is Script {
    struct TokenConfig {
        string name;
        string symbol;
        uint8 decimals;
    }

    function run() public returns (TestToken token) {
        vm.startBroadcast();
        token = deploy(_tokenConfigFromEnv());
        vm.stopBroadcast();
    }

    function deploy(TokenConfig memory config) public returns (TestToken token) {
        token = new TestToken(config.name, config.symbol, config.decimals);
    }

    function _tokenConfigFromEnv() private view returns (TokenConfig memory) {
        return TokenConfig({
            name: vm.envString("TEST_TOKEN_NAME"),
            symbol: vm.envString("TEST_TOKEN_SYMBOL"),
            decimals: uint8(vm.envUint("TEST_TOKEN_DECIMALS"))
        });
    }
}
