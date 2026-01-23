// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {CrystalMarketHarness} from "./CrystalMarketHarness.sol";

/// @notice Mock Crystal contract for deploying CrystalMarketHarness in tests
/// @dev Implements just enough of ICrystal interface for CrystalMarket constructor
contract MockCrystalForHarness {
    address public quoteAsset;
    address public baseAsset;
    uint256 public marketId;
    uint256 public marketType;
    uint256 public scaleFactor;
    uint256 public tickSize;
    uint256 public maxPrice;

    CrystalMarketHarness public harness;

    /// @notice Returns parameters for CrystalMarket constructor
    function parameters() external view returns (
        address,
        address,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256
    ) {
        return (quoteAsset, baseAsset, marketId, marketType, scaleFactor, tickSize, maxPrice);
    }

    /// @notice Deploy a CrystalMarketHarness with the specified parameters
    function deployHarness(
        address _quoteAsset,
        address _baseAsset,
        uint256 _marketId,
        uint256 _marketType,
        uint256 _scaleFactor,
        uint256 _tickSize,
        uint256 _maxPrice
    ) external returns (address) {
        quoteAsset = _quoteAsset;
        baseAsset = _baseAsset;
        marketId = _marketId;
        marketType = _marketType;
        scaleFactor = _scaleFactor;
        tickSize = _tickSize;
        maxPrice = _maxPrice;

        harness = new CrystalMarketHarness();
        return address(harness);
    }
}
