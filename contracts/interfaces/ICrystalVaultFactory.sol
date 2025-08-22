// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface ICrystalVaultFactory {
    function maxOrderCap() external view returns (uint16);
    function maxLockup() external view returns (uint40);
}