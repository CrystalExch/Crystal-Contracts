// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title CrystalMath
 * @author Crystal Labs
 *
 * @notice Math library for the Crystal spot protocol.
 */
library CrystalMath {
    /**
     * @notice Computes the integer square root of the input.
     *
     * @dev Used during initial share minting.
     *
     * @param y Input value.
     *
     * @return z Floor of the square root.
     */
    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        unchecked {
            if (y > 3) {
                z = y;
                uint x = (y >> 1) + 1;
                while (x < z) {
                    z = x;
                    x = (y / x + x) >> 1;
                }
            } else if (y != 0) {
                z = 1;
            }
        }
    }

    /**
     * @notice Returns the smaller of two values.
     *
     * @param a First value.
     * @param b Second value.
     *
     * @return Minimum of `a` and `b`.
     */
    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @notice Converts a tick number into its actual price value.
     *
     * @param t The tick index.
     *
     * @return The price that corresponds to this tick.
     */
    function _tickToPrice(uint256 t, uint256 tickSize) internal pure returns (uint256) {
        unchecked {
            if (t <= 100_000) return t * tickSize;
            uint256 x = t - 10_000;
            return 10 ** (x / 90_000) * (10_000 + (x % 90_000)) * tickSize;
        }
    }

    /**
     * @notice Converts a price into its tick index.
     *
     * @dev Will revert if the price doesn't line up with the allowed price grid for that range.
     *
     * @param p The price value.
     * @param tickSize The market's tick size.
     *
     * @return The tick index for this price.
     */
    function _priceToTick(uint256 p, uint256 tickSize) internal pure returns (uint256) {
        unchecked {
            p /= tickSize;
            if (p <= 100_000) return p;
            else if (p < 1_000_000) {
                if (p % 10 != 0) revert();
                return 90_000 + p / 10;
            } else if (p < 10_000_000) {
                if (p % 100 != 0) revert();
                return 180_000 + p / 100;
            } else if (p < 100_000_000) {
                if (p % 1_000 != 0) revert();
                return 270_000 + p / 1_000;
            } else if (p < 1_000_000_000) {
                if (p % 10_000 != 0) revert();
                return 360_000 + p / 10_000;
            } else if (p < 10_000_000_000) {
                if (p % 100_000 != 0) revert();
                return 450_000 + p / 100_000;
            } else if (p < 100_000_000_000) {
                if (p % 1_000_000 != 0) revert();
                return 540_000 + p / 1_000_000;
            } else if (p < 1_000_000_000_000) {
                if (p % 10_000_000 != 0) revert();
                return 630_000 + p / 10_000_000;
            } else if (p < 10_000_000_000_000) {
                if (p % 100_000_000 != 0) revert();
                return 720_000 + p / 100_000_000;
            } else if (p < 100_000_000_000_000) {
                if (p % 1_000_000_000 != 0) revert();
                return 810_000 + p / 1_000_000_000;
            } else if (p <= 1_000_000_000_000_000) {
                if (p % 10_000_000_000 != 0) revert();
                return 900_000 + p / 10_000_000_000;
            }
            revert();
        }
    }

    /**
     * @notice Snaps a price to the nearest valid price on the grid.
     *
     * @param p Raw price.
     * @param tickSize THe market's tick size.
     * @param roundUp Whether to round up or down.
     *
     * @return The price adjusted to fit the valid grid.
     */
    function _toValidPrice(uint256 p, uint256 tickSize, bool roundUp) internal pure returns (uint256) {
        unchecked {
            p = roundUp ? (p + tickSize - 1) / tickSize : p / tickSize;
            uint256 d;
            if (p <= 100_000) return p * tickSize;
            else if (p < 1_000_000) d = 10;
            else if (p < 10_000_000) d = 100;
            else if (p < 100_000_000) d = 1_000;
            else if (p < 1_000_000_000) d = 10_000;
            else if (p < 10_000_000_000) d = 100_000;
            else if (p < 100_000_000_000) d = 1_000_000;
            else if (p < 1_000_000_000_000) d = 10_000_000;
            else if (p < 10_000_000_000_000) d = 100_000_000;
            else if (p < 100_000_000_000_000) d = 1_000_000_000;
            else if (p <= 1_000_000_000_000_000) d = 10_000_000_000;
            else revert();
            return (roundUp ? (p + d - 1) / d : p / d) * d * tickSize;
        }
    }

    /**
     * @notice Searches upward through a bitmap to find the next tick that has active orders.
     *
     * @param slot The bitmap containing tick activity flags.
     * @param tick Where to start searching from.
     *
     * @return The next active tick we found.
     */
    function _searchSlotUp(uint256 slot, uint256 tick) internal pure returns (uint256) {
        unchecked {
            if (slot & ((1 << 128) - 1) == 0) {
                slot >>= 128;
                tick += 128;
            }
            if (slot & ((1 << 64) - 1) == 0) {
                slot >>= 64;
                tick += 64;
            }
            if (slot & ((1 << 32) - 1) == 0) {
                slot >>= 32;
                tick += 32;
            }
            if (slot & ((1 << 16) - 1) == 0) {
                slot >>= 16;
                tick += 16;
            }
            if (slot & ((1 << 8) - 1) == 0) {
                slot >>= 8;
                tick += 8;
            }
            if (slot & ((1 << 4) - 1) == 0) {
                slot >>= 4;
                tick += 4;
            }
            if (slot & ((1 << 2) - 1) == 0) {
                slot >>= 2;
                tick += 2;
            }
            if (slot & 1 == 0) {
                ++tick;
            }
            return tick;
        }
    }

    /**
     * @notice Searches downward through a bitmap to find the previous tick that has active orders.
     *
     * @param slot The bitmap containing tick activity flags.
     * @param tick Where to start searching from.
     *
     * @return The previous active tick we found.
     */
    function _searchSlotDown(uint256 slot, uint256 tick) internal pure returns (uint256) {
        unchecked {
            if (slot >= 2 ** 128) {
                slot >>= 128;
                tick += 128;
            }
            if (slot >= 2 ** 64) {
                slot >>= 64;
                tick += 64;
            }
            if (slot >= 2 ** 32) {
                slot >>= 32;
                tick += 32;
            }
            if (slot >= 2 ** 16) {
                slot >>= 16;
                tick += 16;
            }
            if (slot >= 2 ** 8) {
                slot >>= 8;
                tick += 8;
            }
            if (slot >= 2 ** 4) {
                slot >>= 4;
                tick += 4;
            }
            if (slot >= 2 ** 2) {
                slot >>= 2;
                tick += 2;
            }
            if (slot >= 2 ** 1) {
                ++tick;
            }
            return tick;
        }
    }

    /**
     * @notice Figures out how much quote asset you need to spend on a buy to hit a specific execution price.
     *
     * @dev Uses binary search to find the answer, with `high` as the maximum we'll search up to.
     *
     * @param reserveQuote Current quote asset in the AMM.
     * @param reserveBase Current base asset in the AMM.
     * @param targetPrice The execution price you want to reach.
     * @param makerRebate Maker rebate that affects the price.
     * @param high Maximum input amount to consider.
     *
     * @return low Largest quote amount that does not cross the target price.
     */
    function _exactInputBuySolve(uint256 reserveQuote, uint256 reserveBase, uint256 targetPrice, uint256 makerRebate, uint256 high, uint256 scaleFactor) internal pure returns (uint256 low) {
        unchecked {
            while (low < high) {
                uint256 mid = low + ((high - low + 1) >> 1);
                uint256 den = 9975 * (reserveBase - ((mid * 9975 * reserveBase) / (reserveQuote * 10000 + mid * 9975)));
                uint256 num = (reserveQuote + mid) * 10000;
                uint256 pMid = (num * scaleFactor * makerRebate + ((den * 100000) - 1)) / (den * 100000);
                if (pMid <= targetPrice) {
                    low = mid;
                } else {
                    high = mid - 1;
                }
            }
            return low;
        }
    }

    /**
     * @notice Figures out how much base asset you'll get from a buy at a specific execution price.
     *
     * @dev Uses binary search to find the answer, maxing out at `high`.
     *
     * @param reserveQuote Current quote asset in the AMM.
     * @param reserveBase Current base asset in the AMM.
     * @param targetPrice The execution price you want.
     * @param makerRebate Maker rebate that affects the price.
     * @param high Maximum output amount to consider.
     *
     * @return low Largest base amount that does not cross the target price.
     */
    function _exactOutputBuySolve(uint256 reserveQuote, uint256 reserveBase, uint256 targetPrice, uint256 makerRebate, uint256 high, uint256 scaleFactor) internal pure returns (uint256 low) {
        unchecked {
            high = high > (reserveBase - 1) ? (reserveBase - 1) : high;
            while (low < high) {
                uint256 mid = low + ((high - low + 1) >> 1);
                uint256 num = (reserveQuote + ((mid * reserveQuote * 10000) / ((reserveBase - mid) * 9975)) + 1) * 10000;
                uint256 den = 9975 * (reserveBase - mid);
                uint256 pMid = (num * scaleFactor * makerRebate + ((den * 100000) - 1)) / (den * 100000);
                if (pMid <= targetPrice) {
                    low = mid;
                } else {
                    high = mid - 1;
                }
            }
        }
    }

    /**
     * @notice Figures out how much base asset you need to sell to hit a specific execution price.
     *
     * @dev Uses binary search to find the answer, with `high` as the maximum.
     *
     * @param reserveQuote Current quote asset in the AMM.
     * @param reserveBase Current base asset in the AMM.
     * @param targetPrice The execution price you want to reach.
     * @param makerRebate Maker rebate that affects the price.
     * @param high Maximum input amount to consider.
     *
     * @return low Largest base amount that does not cross the target price.
     */
    function _exactInputSellSolve(uint256 reserveQuote, uint256 reserveBase, uint256 targetPrice, uint256 makerRebate, uint256 high, uint256 scaleFactor) internal pure returns (uint256 low) {
        unchecked {
            while (low < high) {
                uint256 mid = low + ((high - low + 1) >> 1);
                uint256 num = 9975 * (reserveQuote - ((mid * 9975 * reserveQuote) / (reserveBase * 10000 + mid * 9975)));
                uint256 den = (reserveBase + mid) * 10000;
                uint256 pMid = (num * scaleFactor * 100000) / (den * makerRebate);
                if (pMid >= targetPrice) {
                    low = mid;
                } else {
                    high = mid - 1;
                }
            }
        }
    }

    /**
     * @notice Figures out how much quote asset you'll get from a sell at a specific execution price.
     *
     * @dev Uses binary search to find the answer, maxing out at `high`.
     *
     * @param reserveQuote Current quote asset in the AMM.
     * @param reserveBase Current base asset in the AMM.
     * @param targetPrice The execution price you want.
     * @param makerRebate Maker rebate that affects the price.
     * @param high Maximum output amount to consider.
     *
     * @return low Largest quote amount that does not cross the target price.
     */
    function _exactOutputSellSolve(uint256 reserveQuote, uint256 reserveBase, uint256 targetPrice, uint256 makerRebate, uint256 high, uint256 scaleFactor) internal pure returns (uint256 low) {
        unchecked {
            high = high > (reserveQuote - 1) ? (reserveQuote - 1) : high;
            while (low < high) {
                uint256 mid = low + ((high - low + 1) >> 1);
                uint256 den = (reserveBase + ((mid * reserveBase * 10000) / ((reserveQuote - mid) * 9975)) + 1) * 10000;
                uint256 num = 9975 * (reserveQuote - mid);
                uint256 pMid = (num * scaleFactor * 100000) / (den * makerRebate);
                if (pMid >= targetPrice) {
                    low = mid;
                } else {
                    high = mid - 1;
                }
            }
        }
    }
}