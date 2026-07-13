// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Crystal} from "../core/Crystal.sol";
import {ICrystal} from "../interfaces/ICrystal.sol";

/// @notice Test harness for Crystal that exposes internal functions for testing.
contract CrystalHarness is Crystal {
    constructor(
        address _weth,
        address _gov,
        address _feeRecipient,
        uint8 _feeCommission,
        uint256 _feeClaimDuration,
        ICrystal.LaunchpadParams memory _launchpadParams
    ) Crystal(_weth, _gov, _feeRecipient, _feeCommission, _feeClaimDuration, _launchpadParams) {}

    /// @notice Test function to set market by tokens.
    function setMarketByTokens(address token0, address token1, address market) external {
        getMarketByTokens[token0][token1] = market;
    }

    /// @notice Test function to clear launchpad market (simulate graduated state).
    function clearLaunchpadMarket(address token) external {
        delete launchpadTokenToMarket[token];
    }

    /// @notice Test function to set up a launchpad market.
    function setupPartialLaunchpadMarket(
        address token,
        address market,
        uint112 virtualNativeReserve,
        uint112 virtualTokenReserve,
        uint256 k
    ) external {
        launchpadTokenToMarket[token] = ICrystal.LaunchpadMarket({
            virtualNativeReserve: virtualNativeReserve,
            virtualTokenReserve: virtualTokenReserve,
            k: k,
            creator: msg.sender,
            market: market,
            createTimestamp: uint88(block.timestamp)
        });
    }
    
    /// @notice Set claimable rewards for testing.
    function setClaimableRewards(address token, address user, uint256 amount) external {
        claimableRewards[token][user] = amount;
    }

    /// @notice Set market mappings for testing (without private storage access).
    function setMarketMappings(address market, uint256 marketId) external {
        marketIdToMarket[marketId] = market;
        allMarkets.push(market);
    }

    /// @notice Set pending closed market timestamp.
    function setPendingClosedMarket(address market, uint256 timestamp) external {
        pendingClosedMarkets[market] = timestamp;
    }

    /// @notice Set launchpad createTimestamp for testing.
    function setLaunchpadCreateTimestamp(address token, uint88 timestamp) external {
        launchpadTokenToMarket[token].createTimestamp = timestamp;
    }

    /// @notice Get placeholder address.
    function getPlaceholder() external pure returns (address) {
        return 0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC;
    }
}
