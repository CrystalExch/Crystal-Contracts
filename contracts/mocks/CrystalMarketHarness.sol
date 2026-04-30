// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ICrystal} from "../interfaces/ICrystal.sol";
import {CrystalMath as CM} from "../libraries/CrystalMath.sol";
import {CrystalStorage as CS} from "../libraries/CrystalStorage.sol";
import {CrystalMarket} from "../core/CrystalMarket.sol";

/// @notice Test harness for CrystalMarket that exposes internal functions for testing
/// @dev Storage variables are private in CrystalMarket, so we access them via assembly
/// @dev CrystalMarket inherits ERC20 which uses slots 0-6, so CrystalMarket storage starts at slot 7
contract CrystalMarketHarness is CrystalMarket {
    // Storage slot indices (ERC20 uses slots 0-6, CrystalMarket starts at 7)
    // slot 7: feeRecipient + feeCommission (packed)
    // slot 8: userIdToAddress mapping
    // slot 9: addressToUserId mapping
    // slot 10: _getMarket mapping
    // slot 11: tokenBalances mapping

    /// @notice Expose _priceToTick for direct testing of price range branches
    function exposed_priceToTick(uint256 p) external view returns (uint256) {
        return CM._priceToTick(p, tickSize);
    }

    /// @notice Expose _toValidPrice for direct testing
    function exposed_toValidPrice(uint256 p, bool roundUp) external pure returns (uint256) {
        return CM._toValidPrice(p, roundUp);
    }

    /// @notice Expose _tickToPrice for direct testing
    function exposed_tickToPrice(uint256 tick) external view returns (uint256) {
        return CM._tickToPrice(tick, tickSize);
    }

    /// @notice Expose _sqrt for direct testing
    function exposed_sqrt(uint256 y) external pure returns (uint256) {
        return CM._sqrt(y);
    }

    /// @notice Expose exact input/output AMM solvers for direct testing
    function exposed_exactInputBuySolve(
        uint256 reserveQuote,
        uint256 reserveBase,
        uint256 targetPrice,
        uint256 scaleFactor,
        uint256 makerRebate,
        uint256 high
    ) external pure returns (uint256) {
        return CM._exactInputBuySolve(
            reserveQuote,
            reserveBase,
            targetPrice,
            makerRebate,
            high,
            scaleFactor
        );
    }

    function exposed_exactOutputBuySolve(
        uint256 reserveQuote,
        uint256 reserveBase,
        uint256 targetPrice,
        uint256 scaleFactor,
        uint256 makerRebate,
        uint256 high
    ) external pure returns (uint256) {
        return CM._exactOutputBuySolve(
            reserveQuote,
            reserveBase,
            targetPrice,
            makerRebate,
            high,
            scaleFactor
        );
    }

    function exposed_exactInputSellSolve(
        uint256 reserveQuote,
        uint256 reserveBase,
        uint256 targetPrice,
        uint256 scaleFactor,
        uint256 makerRebate,
        uint256 high
    ) external pure returns (uint256) {
        return CM._exactInputSellSolve(
            reserveQuote,
            reserveBase,
            targetPrice,
            makerRebate,
            high,
            scaleFactor
        );
    }

    function exposed_exactOutputSellSolve(
        uint256 reserveQuote,
        uint256 reserveBase,
        uint256 targetPrice,
        uint256 scaleFactor,
        uint256 makerRebate,
        uint256 high
    ) external pure returns (uint256) {
        return CM._exactOutputSellSolve(
            reserveQuote,
            reserveBase,
            targetPrice,
            makerRebate,
            high,
            scaleFactor
        );
    }

    /// @notice Expose balance settlement for branch coverage
    function exposed_settleBalances(
        int256 quoteAssetDebt,
        int256 baseAssetDebt,
        uint256 userId,
        uint256 balanceMode,
        uint256 balanceModeOut,
        uint256 balanceModeIn
    ) external {
        _settleBalances(
            quoteAssetDebt,
            baseAssetDebt,
            userId,
            balanceMode,
            balanceModeOut,
            balanceModeIn
        );
    }

    /// @notice Expose core orderbook actions for branch coverage
    function exposed_limitOrder(
        bool isBuy,
        bool isRecieveTokens,
        uint256 price,
        uint256 size,
        uint256 userId,
        uint256 cloid
    ) external returns (uint256, uint256) {
        return _limitOrder(isBuy, isRecieveTokens, price, size, userId, cloid);
    }

    function exposed_cancelOrder(
        uint256 price,
        uint256 id,
        uint256 userId
    ) external returns (uint256, uint256, bool) {
        return _cancelOrder(price, id, userId);
    }

    function exposed_decreaseOrder(
        uint256 price,
        uint256 id,
        uint256 decreaseAmount,
        uint256 userId
    ) external returns (uint256, uint256, bool) {
        return _decreaseOrder(price, id, decreaseAmount, userId);
    }

    function exposed_replaceOrder(
        uint256 options,
        uint256 price,
        uint256 id,
        uint256 newPrice,
        uint256 newSize
    ) external returns (int256, int256, uint256) {
        assembly {
            mstore(0x40, 0xe0)
        }
        return _replaceOrder(options, price, id, newPrice, newSize);
    }

    function exposed_marketOrder(
        uint256 size,
        uint256 priceAndReferrer,
        uint256 orderInfo
    ) external returns (uint256, uint256, uint256, uint256) {
        assembly {
            mstore(0x40, 0xe0)
        }
        return _marketOrder(size, priceAndReferrer, orderInfo);
    }

    /// @notice Expose _searchSlotUp for testing
    function exposed_searchSlotUp(uint256 slot, uint256 tick) external pure returns (uint256) {
        return CM._searchSlotUp(slot, tick);
    }

    /// @notice Expose _searchSlotDown for testing
    function exposed_searchSlotDown(uint256 slot, uint256 tick) external pure returns (uint256) {
        return CM._searchSlotDown(slot, tick);
    }

    /// @notice Get the tickSize immutable
    function getTickSize() external view returns (uint256) {
        return tickSize;
    }

    /// @notice Get the scaleFactor immutable
    function getScaleFactor() external view returns (uint256) {
        return scaleFactor;
    }

    /// @notice Get the maxPrice immutable
    function getMaxPrice() external view returns (uint256) {
        return maxPrice;
    }

    /// @notice Get the marketType immutable
    function getMarketType() external view returns (uint256) {
        return marketType;
    }

    /// @notice Direct setter for token balances using assembly (for overflow testing)
    /// @dev tokenBalances is at slot 16
    function setTokenBalance(uint256 userId, address token, uint256 bal) external {
        bytes32 slot = keccak256(abi.encode(token, keccak256(abi.encode(userId, uint256(11)))));
        assembly {
            sstore(slot, bal)
        }
    }

    /// @notice Get token balance using assembly
    function getTokenBalance(uint256 userId, address token) external view returns (uint256 bal) {
        bytes32 slot = keccak256(abi.encode(token, keccak256(abi.encode(userId, uint256(11)))));
        assembly {
            bal := sload(slot)
        }
    }

    /// @notice Set activated slot using assembly
    function setActivatedSlot(uint256 key, uint256 value) external {
        CS._writeMapping((key & MASK_OUT_0_128) | ((((key & MASK_KEEP_0_128) + 1) * 256 - 1) >> 7), (((key & MASK_KEEP_0_128) + 1) * 256 - 1) & 127, CS.PRICELEVELS_KEY, value);
    }

    /// @notice Get activated slot
    function getActivatedSlot(uint256 key) external view returns (uint256 value) {
        value = CS._readMapping((key & MASK_OUT_0_128) | ((((key & MASK_KEEP_0_128) + 1) * 256 - 1) >> 7), (((key & MASK_KEEP_0_128) + 1) * 256 - 1) & 127, CS.PRICELEVELS_KEY);
    }

    /// @notice Set groups slot using assembly
    function setGroupsSlot(uint256 key, uint256 value) external {
        CS._writeMapping((key & MASK_OUT_0_128) | ((key & MASK_KEEP_0_128) >> 7), (key & MASK_KEEP_0_128) & 127, CS.GROUPS_KEY, value);
    }

    /// @notice Set priceLevels using assembly
    function setPriceLevel(uint256 key, uint256 value) external {
        CS._writeMapping((key & MASK_OUT_0_128) | ((((key & MASK_KEEP_0_128) << 8) / 255) >> 7), (((key & MASK_KEEP_0_128) << 8) / 255) & 127, CS.PRICELEVELS_KEY, value);
    }

    /// @notice Get priceLevel
    function getPriceLevel(uint256 key) external view returns (uint256 value) {
        value = CS._readMapping((key & MASK_OUT_0_128) | ((((key & MASK_KEEP_0_128) << 8) / 255) >> 7), (((key & MASK_KEEP_0_128) << 8) / 255) & 127, CS.PRICELEVELS_KEY);
    }

    /// @notice Set core market state for this harness address
    /// @dev _getMarket is at slot 10; only updates slot0/slot1 fields used in tests
    function setMarketState(
        uint80 highestBid,
        uint80 lowestAsk,
        uint40 minSize,
        uint24 takerFee,
        uint24 makerRebate,
        bool isAMMEnabled,
        uint112 reserveQuote,
        uint112 reserveBase
    ) external {
        bytes32 baseSlot = keccak256(abi.encode(address(this), uint256(10)));
        uint256 slot0 = uint256(highestBid) |
            (uint256(lowestAsk) << 80) |
            (uint256(minSize) << 160) |
            (uint256(takerFee) << 200) |
            (uint256(makerRebate) << 224) |
            (isAMMEnabled ? (1 << 248) : 0);
        uint256 slot1 = uint256(reserveQuote) | (uint256(reserveBase) << 112);
        assembly {
            sstore(baseSlot, slot0)
            sstore(add(baseSlot, 1), slot1)
        }
    }

    /// @notice Set userIdToAddress mapping
    /// @dev userIdToAddress is at slot 8
    function setUserIdToAddress(uint256 userId, address user) external {
        bytes32 slot = keccak256(abi.encode(userId, uint256(8)));
        assembly {
            sstore(slot, user)
        }
    }

    /// @notice Set addressToUserId mapping
    /// @dev addressToUserId is at slot 9
    function setAddressToUserId(address user, uint256 userId) external {
        bytes32 slot = keccak256(abi.encode(user, uint256(9)));
        assembly {
            sstore(slot, userId)
        }
    }
}
