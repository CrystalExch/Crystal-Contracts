// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ICrystal } from "../../../contracts/interfaces/ICrystal.sol";

library CrystalDeploymentConfig {
    struct CrystalConfig {
        address weth;
        address governance;
        address feeRecipient;
        uint8 feeCommission;
        uint256 feeClaimDuration;
        ICrystal.LaunchpadParams launchpadParams;
    }
}
