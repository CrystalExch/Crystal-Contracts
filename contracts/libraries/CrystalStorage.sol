// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CrystalMath as CM} from "../libraries/CrystalMath.sol";

/**
 * @title CrystalStorage
 * @author Crystal Labs
 *
 * @notice Storage library for the Crystal spot protocol.
 */
library CrystalStorage {
    /// @notice Base mapping slot for both cloid and non-cloid resting limit orders.
    uint256 internal constant ORDERS_KEY = 0x100;

    /// @notice Base mapping slot for price levels and the activated bitmap.
    uint256 internal constant PRICELEVELS_KEY = 0x200;

    /// @notice Base mapping slot for the groups bitmap.
    uint256 internal constant GROUPS_KEY = 0x300;

    /**
     * @notice Reads a word from a namespaced mapping layout.
     *
     * @dev Computes `keccak256(abi.encode(key, slot)) + offset` and loads the resulting storage word.
     *
     * @param key Primary mapping key or namespace root.
     * @param offset Word offset from the computed mapping slot.
     * @param slot Base storage slot used to namespace the mapping.
     *
     * @return value Storage word loaded from the derived location.
     */
    function _readMapping(uint256 key, uint256 offset, uint256 slot) internal view returns (uint256 value) {
        assembly {
            mstore(0x00, key)
            mstore(0x20, slot)
            value := sload(add(keccak256(0x00, 0x40), offset))
        }
    }

    /**
     * @notice Writes a word to a namespaced mapping layout.
     *
     * @dev Computes `keccak256(abi.encode(key, slot)) + offset` and stores `data` at the resulting storage word.
     *
     * @param key Primary mapping key or namespace root.
     * @param offset Word offset from the computed mapping slot.
     * @param slot Base storage slot used to namespace the mapping.
     * @param data Value to store at the derived location.
     */
    function _writeMapping(uint256 key, uint256 offset, uint256 slot, uint256 data) internal {
        assembly {
            mstore(0x00, key)
            mstore(0x20, slot)
            sstore(add(keccak256(0x00, 0x40), offset), data)
        }
    }
    
    /**
     * @notice Computes the storage locator for a cloid-backed resting order word.
     *
     * @param userId User identifier owning the cloid order.
     * @param cloid Client order identifier.
     *
     * @return key Primary mapping key or namespace root for the order word.
     * @return offset Word offset from the derived mapping root.
     */
    function _getCloidOrder(uint256 userId, uint256 cloid) internal pure returns (uint256 key, uint256 offset) {
        unchecked {
            require(cloid != 0 && userId <= type(uint128).max && cloid <= type(uint16).max);
            uint256 cloidPairIndex = (cloid - 1) >> 1;
            key = userId << 128 | (cloidPairIndex / 42);
            offset = (cloidPairIndex % 42) * 3 + ((cloid & 1) == 0 ? 1 : 0);
        }
    }

    /**
     * @notice Computes the storage locator for the shared verification word of a cloid pair.
     *
     * @param userId User identifier owning the cloid pair bucket.
     * @param cloid Client order identifier whose pair verification word should be read.
     *
     * @return key Primary mapping key or namespace root for the verification word.
     * @return offset Word offset from the derived mapping root.
     */
    function _getVerifyCloid(uint256 userId, uint256 cloid) internal pure returns (uint256 key, uint256 offset) {
        unchecked {
            require(cloid != 0 && userId <= type(uint128).max && cloid <= type(uint16).max);
            uint256 cloidPairIndex = (cloid - 1) >> 1;
            key = userId << 128 | (cloidPairIndex / 42);
            offset = (cloidPairIndex % 42) * 3 + 2;
        }
    }

    /**
     * @notice Computes the storage locator for a native resting order word.
     *
     * @param marketId Market identifier already shifted into its storage key domain.
     * @param price Price level containing the native order.
     * @param id Native order identifier.
     *
     * @return key Primary mapping key or namespace root for the order word.
     * @return offset Word offset from the derived mapping root.
     */
    function _getOrder(uint256 marketId, uint256 price, uint256 id) internal pure returns (uint256 key, uint256 offset) {
        unchecked {
            require(price <= type(uint80).max && id <= type(uint48).max);
            key = marketId | (price << 48) | (id >> 7);
            offset = id & 127;
        }
    }

    /**
     * @notice Computes the storage locator for the packed price-level word of a given price.
     *
     * @param marketType Market type used to determine tick conversion.
     * @param tickSize Tick size used to derive the logical tick index.
     * @param marketId Market identifier already shifted into its storage key domain.
     * @param price Price whose level should be located.
     *
     * @return key Primary mapping key or namespace root for the price-level word.
     * @return offset Word offset from the derived mapping root.
     */
    function _getPriceLevel(uint256 marketType, uint256 tickSize, uint256 marketId, uint256 price) internal pure returns (uint256 key, uint256 offset) {
        unchecked {
            require(price <= type(uint80).max && (price % tickSize) == 0);
            uint256 tick = marketType == 0 ? (price / tickSize) : CM._priceToTick(price, tickSize);
            uint256 priceLevelIndex = (tick << 8) / 255;
            key = marketId | (priceLevelIndex >> 7);
            offset = priceLevelIndex & 127;
        }
    }

    /**
     * @notice Computes the storage locator for a first-level activated bitmap word.
     *
     * @param marketId Market identifier already shifted into its storage key domain.
     * @param slotIndex First-level bitmap word index.
     *
     * @return key Primary mapping key or namespace root for the bitmap word.
     * @return offset Word offset from the derived mapping root.
     */
    function _getActivated(uint256 marketId, uint256 slotIndex) internal pure returns (uint256 key, uint256 offset) {
        unchecked {
            uint256 tickIndex = ((slotIndex + 1) * 256 - 1);
            require(tickIndex <= type(uint128).max);
            key = marketId | (tickIndex >> 7);
            offset = tickIndex & 127;
        }
    }

    /**
     * @notice Computes the storage locator for a second-level groups bitmap word.
     *
     * @param marketId Market identifier already shifted into its storage key domain.
     * @param groupsIndex Second-level bitmap word index.
     *
     * @return key Primary mapping key or namespace root for the groups bitmap word.
     * @return offset Word offset from the derived mapping root.
     */
    function _getGroups(uint256 marketId, uint256 groupsIndex) internal pure returns (uint256 key, uint256 offset) {
        unchecked {
            require(groupsIndex <= type(uint128).max);
            key = marketId | (groupsIndex >> 7);
            offset = groupsIndex & 127;
        }
    }
}
