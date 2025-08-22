// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;
import "hardhat/console.sol";

import {CrystalMarket2} from '../markets/CrystalMarket2.sol';

contract CrystalMarket2Factory {
    function deploy(address quoteAsset, address baseAsset, uint256 marketId) external returns (address market) {
        market = address(new CrystalMarket2{salt: keccak256(abi.encode(quoteAsset, baseAsset, marketId))}());
    }
}