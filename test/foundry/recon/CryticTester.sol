// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { CryticAsserts } from "@chimera/CryticAsserts.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";

import { TargetFunctions } from "./TargetFunctions.sol";

contract CryticTester is TargetFunctions, CryticAsserts, StdInvariant {
    constructor() payable {
        setup();
        targetContract(address(this));
    }
}
