// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;
import "hardhat/console.sol";

import {CrystalMarket1} from '../markets/CrystalMarket1.sol';

contract CrystalMarket1Factory {
    function deploy(address quoteAsset, address baseAsset, uint256 marketId) external returns (address market) {
        market = address(new CrystalMarket1{salt: keccak256(abi.encode(quoteAsset, baseAsset, marketId))}());
    }
}