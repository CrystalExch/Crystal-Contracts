// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;
import "hardhat/console.sol";

import {CrystalMarket0} from '../markets/CrystalMarket0.sol';

contract CrystalMarket0Factory {
    function deploy(address quoteAsset, address baseAsset, uint256 marketId) external returns (address market) {
        market = address(new CrystalMarket0{salt: keccak256(abi.encode(quoteAsset, baseAsset, marketId))}());
    }
}