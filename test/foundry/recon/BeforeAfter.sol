// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Setup } from "./Setup.sol";

abstract contract BeforeAfter is Setup {
    struct Vars {
        uint112 reserveQuote;
        uint112 reserveBase;
        uint256 latestUserId;
        uint256 trackedOrderCount;
        uint256 trackedVaultCount;
    }

    Vars internal _before;
    Vars internal _after;

    modifier updateGhosts() {
        __before();
        _;
        __after();
    }

    function __before() internal {
        (_before.reserveQuote, _before.reserveBase) = crystal.getReserves(address(market));
        _before.latestUserId = crystal.latestUserId();
        _before.trackedOrderCount = trackedOrders.length;
        _before.trackedVaultCount = trackedVaults.length;
    }

    function __after() internal {
        (_after.reserveQuote, _after.reserveBase) = crystal.getReserves(address(market));
        _after.latestUserId = crystal.latestUserId();
        _after.trackedOrderCount = trackedOrders.length;
        _after.trackedVaultCount = trackedVaults.length;
    }
}
