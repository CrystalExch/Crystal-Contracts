// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { FoundryAsserts } from "@chimera/FoundryAsserts.sol";
import { Test } from "forge-std/Test.sol";

import { TargetFunctions } from "./TargetFunctions.sol";

contract CryticToFoundry is Test, TargetFunctions, FoundryAsserts {
    function setUp() public {
        setup();
        targetContract(address(this));
    }

    function test_crytic_reproducer_quote_views_do_not_mutate_and_match_paths() public {
        crystal_internal_balance_market_buy(0, 58_295_508_403);
        crystal_market_buy_exact_output(264_709_472_002_006_064_519);
        invariant_quote_views_do_not_mutate_and_match_paths();
    }

    function test_crytic_reproducer_tracked_orders_respect_market_bounds() public {
        crystal_payable_multibatch_sell_limit(798, 0);
        crystal_swap_exact_quote_for_eth_public(0);
        invariant_tracked_orders_respect_market_bounds();
    }
}
