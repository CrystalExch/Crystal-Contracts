// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface IVault {
    function sweep() external;
}

contract BadOwner {
    function callSweep(address vault) external {
        IVault(vault).sweep();
    }

    receive() external payable {
        revert();
    }
}
