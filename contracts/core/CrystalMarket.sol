// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "../interfaces/IERC20.sol";
import {ICrystal} from "../interfaces/ICrystal.sol";
import {ERC20} from "../libraries/ERC20.sol";

/**
 * @title CrystalMarket
 * @author Crystal Labs
 *
 * @notice
 * Individual market implementation for the Crystal spot protocol.
 *
 * @dev
 * - The majority of methods are to be delegatecalled by the Crystal contract and cannot be interacted with directly.
 * - The only functions that are directly called are the AMM's liquidity ERC-20 tokens.
 * - All read methods are private as state is held in the core exchange contract.
 * - Storage layout is optimized for gas therefore non-traditional bitmasks are used.
 * - CrystalMarket inherits ERC20 so the relevant state to be delegatecalled starts at slot 8 and beyond.
 */
contract CrystalMarket is ERC20 {
    /// @notice Address receiving trading fees.
    address private feeRecipient;

    /// @notice Percentage of fees that go to referrals
    uint8 private feeCommission;

    /**
     * @notice Mapping from user id to address.
     *
     * @dev User id zero is invalid.
     */
    mapping(uint256 => address) private userIdToAddress;

    /// @notice Links each address to their user ID
    mapping(address => uint256) private addressToUserId;

    /// @notice Stores all market settings, indexed by market address
    mapping(address => ICrystal.Market) private _getMarket;

    /**
     * @notice Activated price bitmaps for ticks.
     *
     * @dev Key is marketId << 128 | slotIndex.
     */
    mapping(uint256 => uint256) private activated;

    /**
     * @notice Secondary activated bitmap for higher-level aggregation.
     *
     * @dev Key is marketId << 128 | slotIndex.
     */
    mapping(uint256 => uint256) private activated2;

    /**
     * @notice Aggregate liquidity per price level.
     *
     * @dev Key is marketId << 128 | price and price zero is invalid.
     */
    mapping(uint256 => uint256) private priceLevels;

    /**
     * @notice Order storage keyed by market+price+id or user+cloid.
     *
     * @dev Cloid zero is invalid with valid range 1–1023 and key layout marketId<<128 | price<<48 | id or userId<<41 | cloid.
     */
    mapping(uint256 => uint256) private orders;

    /**
     * @notice Mapping to verify cloid market and price associations.
     *
     * @dev Two cloids share a slot which is never zero and encodes market and price.
     */
    mapping(uint256 => uint256) private cloidVerify;

    /// @notice The protocols's internal token balances
    mapping(uint256 => mapping(address => uint256)) private tokenBalances;

    /// @notice Tracks fees that users and referrers can claim, organized by token
    mapping(address => mapping(address => uint256)) private claimableRewards;

    /// @notice The quote token for this market (e.g., USDC in a BTC/USDC pair)
    address public immutable quoteAsset;

    /// @notice The base token for this market (e.g., BTC in a BTC/USDC pair)
    address public immutable baseAsset;

    /// @notice Address of the main Crystal contract
    address public immutable crystal;

    /// @notice What type of market this is
    uint256 public immutable marketType;

    /// @notice Scaling factor used for price calculations
    uint256 public immutable scaleFactor;

    /// @notice Minimum price increment allowed for this market
    uint256 public immutable tickSize;

    /// @notice Highest price this market supports
    uint256 public immutable maxPrice;

    /**
     * @notice Address of the market when delegatecalled.
     *
     * @dev Cached self address for delegatecall context.
     */
    address private immutable market;

    /**
     * @notice Market id already shifted left 128 bits.
     *
     * @dev Market id zero is invalid.
     */
    uint256 private immutable marketId;

    uint256 private constant MASK_OUT_113_154 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFC0000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 private constant MASK_OUT_0_128 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000000000000000000000000000;
    uint256 private constant MASK_OUT_205_256 = 0x0000000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 private constant MASK_OUT_113_205 = 0xFFFFFFFFFFFFE00000000000000000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 private constant MASK_OUT_154_205 = 0xFFFFFFFFFFFFE0000000000003FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 private constant MASK_OUT_0_80 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000000000000000;
    uint256 private constant MASK_OUT_0_41 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE0000000000;
    uint256 private constant MASK_OUT_255_256 = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 private constant MASK_KEEP_255_256 = 0x8000000000000000000000000000000000000000000000000000000000000000;
    uint256 private constant MASK_KEEP_113_154 = 0x00000000000000000000000003FFFFFFFFFE0000000000000000000000000000;
    uint256 private constant MASK_KEEP_112_113 = 0x0000000000000000000000000000000000010000000000000000000000000000;
    uint256 private constant MASK_KEEP_0_10 = 0x3FF;
    uint256 private constant MASK_KEEP_0_20 = 0xFFFFF;
    uint256 private constant MASK_KEEP_0_41 = 0x1FFFFFFFFFF;
    uint256 private constant MASK_KEEP_0_48 = 0xFFFFFFFFFFFF;
    uint256 private constant MASK_KEEP_0_51 = 0x7FFFFFFFFFFFF;
    uint256 private constant MASK_KEEP_0_80 = 0xFFFFFFFFFFFFFFFFFFFF;
    uint256 private constant MASK_KEEP_0_96 = 0xFFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 private constant MASK_KEEP_0_112 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 private constant MASK_KEEP_0_128 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 private constant MASK_KEEP_0_256 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 private constant LEADING_HEX_1 = 0x1000000000000000000000000000000000000000000000000000000000000000;
    uint256 private constant LEADING_HEX_2 = 0x2000000000000000000000000000000000000000000000000000000000000000;
    uint256 private constant LEADING_HEX_3 = 0x3000000000000000000000000000000000000000000000000000000000000000;
    uint256 private constant LEADING_HEX_4 = 0x4000000000000000000000000000000000000000000000000000000000000000;
    uint256 private constant FILL_SIG = 0xa195980963150be5fcca4acd6a80bf5a9de7f9c862258501b7c705e7d2c2d2f4;
    uint256 private constant ORDERS_UPDATED_SIG = 0x7ebb55d14fb18179d0ee498ab0f21c070fad7368e44487d51cdac53d6f74812c;

    /**
     * @notice Sets up this market with configuration from the main Crystal contract
     *
     * @dev Gets called during deployment to grab all the market parameters and set up the permit domain separator
     */
    constructor() ERC20("Crystal V2", "CRY-V2") {
        (quoteAsset, baseAsset, marketId, marketType, scaleFactor, tickSize, maxPrice) = ICrystal(msg.sender).parameters();
        marketId <<= 128;
        scaleFactor = 10 ** scaleFactor;
        market = address(this);
        crystal = msg.sender;
        require(quoteAsset != address(0) && baseAsset != address(0) && quoteAsset != baseAsset && maxPrice <= MASK_KEEP_0_80 && tickSize <= MASK_KEEP_0_80 && scaleFactor <= MASK_KEEP_0_112);
    }

    /**
     * @notice Creates new LP tokens and sends them to someone
     *
     * @dev Can only be called by the main Crystal contract
     *
     * @param to Who gets the newly minted tokens
     * @param value How many tokens to create
     */
    function mint(address to, uint256 value) external {
        require(msg.sender == crystal);
        _mint(to, value);
    }

    /**
     * @notice Destroys LP tokens from someone's balance
     *
     * @dev Can only be called by the main Crystal contract
     *
     * @param from Whose tokens we're burning
     * @param value How many tokens to destroy
     */
    function burn(address from, uint256 value) external {
        require(msg.sender == crystal);
        _burn(from, value);
    }

    /**
     * @notice Moves LP tokens on someone else's behalf (requires prior approval)
     *
     * @dev If you have infinite allowance or you're the Crystal contract itself, we skip the allowance check
     *
     * @param from Who's sending the tokens
     * @param to Who's receiving the tokens
     * @param value How many tokens to move
     *
     * @return success Always returns true
     */
    function transferFrom(address from, address to, uint256 value) external override returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max && msg.sender != crystal) {
            allowance[from][msg.sender] -= value;
        }
        _transfer(from, to, value);
        return true;
    }

    // ===================================================================================================
    // Above methods are part of the ERC-20 implementation and are to be called directly.
    // Below methods are to be delegatecalled by the Crystal contract and cannot be interacted with.
    // ===================================================================================================

    /**
     * @notice Shows how much of each token is currently in the AMM pool
     *
     * @dev Gets called through delegatecall from the main Crystal contract
     *
     * @return reserveQuote Amount of quote asset in the pool
     * @return reserveBase Amount of base asset in the pool
     */
    function getReserves() external payable returns (uint112 reserveQuote, uint112 reserveBase) {
        ICrystal.Market storage m = _getMarket[market];
        (reserveQuote, reserveBase) = (m.reserveQuote, m.reserveBase);
    }

    /**
     * @notice Adds the initial liquidity to a launchpad market's AMM (happens before regular trading starts)
     *
     * @dev Can only be called when the pool has no LP tokens yet
     *
     * @param to Who gets the LP tokens
     * @param amountQuoteDesired How much quote asset to add
     * @param amountBaseDesired How much base asset to add
     *
     * @return liquidity How many LP tokens were created
     */
    function premint(address to, uint256 amountQuoteDesired, uint256 amountBaseDesired) external payable returns (uint256 liquidity) {
        ICrystal.Market storage m = _getMarket[market];
        liquidity = _sqrt(amountQuoteDesired * (amountBaseDesired));
        require(marketType == 3 && IERC20(market).totalSupply() == 0 && liquidity != 0 && amountQuoteDesired <= MASK_KEEP_0_112 && amountBaseDesired <= MASK_KEEP_0_112);
        IERC20(market).mint(to, liquidity);
        (m.reserveQuote, m.reserveBase) = (uint112(amountQuoteDesired), uint112(amountBaseDesired));
    }

    /**
     * @notice Adds liquidity to the AMM and gets LP tokens in return
     *
     * @dev The `options` parameter controls whether we pull funds directly from you or use the router's internal balance
     *
     * @param to Who receives the LP tokens
     * @param amountQuoteDesired How much quote asset you want to add
     * @param amountBaseDesired How much base asset you want to add
     * @param amountQuoteMin Minimum quote asset you'll accept (slippage protection)
     * @param amountBaseMin Minimum base asset you'll accept (slippage protection)
     * @param options Bit flags controlling where quote and base tokens come from
     *
     * @return liquidity How many LP tokens you got
     */
    function addLiquidity(address to, uint256 amountQuoteDesired, uint256 amountBaseDesired, uint256 amountQuoteMin, uint256 amountBaseMin, uint256 options) external payable returns (uint256 liquidity) {
        ICrystal.Market storage m = _getMarket[market];
        (uint256 reserveQuote, uint256 reserveBase) = (m.reserveQuote, m.reserveBase);
        uint256 amountQuote;
        uint256 amountBase;
        uint256 _totalSupply = IERC20(market).totalSupply();
        if (_totalSupply == 0) {
            amountQuote = amountQuoteDesired;
            amountBase = amountBaseDesired;
            liquidity = _sqrt(amountQuote * (amountBase)) - 100000;
            IERC20(market).mint(address(0), 100000);
            require(m.highestBid <= ((amountQuote * scaleFactor * 10000 * uint256(m.makerRebate) + (amountBase * 9975 * 100000 - 1)) / (amountBase * 9975 * 100000)) && m.lowestAsk >= ((amountQuote * scaleFactor * 9975 * 100000) / (amountBase * 10000 * uint256(m.makerRebate))));
        } else {
            uint256 amountBaseOptimal = (amountQuoteDesired * reserveBase) / reserveQuote;
            if (amountBaseOptimal <= amountBaseDesired) {
                amountQuote = amountQuoteDesired;
                amountBase = amountBaseOptimal;
            } else {
                uint256 amountQuoteOptimal = (amountBaseDesired * reserveQuote) / reserveBase;
                require(amountQuoteOptimal <= amountQuoteDesired);
                amountQuote = amountQuoteOptimal;
                amountBase = amountBaseDesired;
            }
            liquidity = (amountQuote * (_totalSupply)) / reserveQuote < (amountBase * (_totalSupply)) / reserveBase ? (amountQuote * (_totalSupply)) / reserveQuote : (amountBase * (_totalSupply)) / reserveBase;
        }
        reserveQuote += amountQuote;
        reserveBase += amountBase;
        if ((options & 1) == 0) {
            IERC20(quoteAsset).transferFrom(msg.sender, address(this), amountQuote);
        } else {
            tokenBalances[0][quoteAsset] -= amountQuote;
        }
        if (((options >> 4) & 1) == 0) {
            IERC20(baseAsset).transferFrom(msg.sender, address(this), amountBase);
        } else {
            tokenBalances[0][baseAsset] -= amountBase;
        }
        IERC20(market).mint(to, liquidity);
        require(liquidity != 0 && amountQuote >= amountQuoteMin && amountBase >= amountBaseMin && reserveQuote <= MASK_KEEP_0_112 && reserveBase <= MASK_KEEP_0_112 && m.isAMMEnabled == true);
        (m.reserveQuote, m.reserveBase) = (uint112(reserveQuote), uint112(reserveBase));
        emit ICrystal.Sync(market, uint112(reserveQuote), uint112(reserveBase));
        emit ICrystal.Mint(market, msg.sender, amountQuote, amountBase);
    }

    /**
     * @notice Burns LP tokens to withdraw your share of the AMM pool
     *
     * @dev The `options` parameter controls whether we send tokens to you directly or credit your internal balance
     *
     * @param to Who gets the tokens if we're sending them externally
     * @param liquidity How many LP tokens to burn
     * @param amountQuoteMin Minimum quote asset you'll accept (slippage protection)
     * @param amountBaseMin Minimum base asset you'll accept (slippage protection)
     * @param options Bit flags controlling where quote and base tokens go
     *
     * @return amountQuote Quote asset you received
     * @return amountBase Base asset you received
     */
    function removeLiquidity(address to, uint256 liquidity, uint256 amountQuoteMin, uint256 amountBaseMin, uint256 options) external payable returns (uint256 amountQuote, uint256 amountBase) {
        ICrystal.Market storage m = _getMarket[market];
        (uint256 reserveQuote, uint256 reserveBase) = (m.reserveQuote, m.reserveBase);
        IERC20(market).transferFrom(msg.sender, address(this), liquidity);

        uint256 _totalSupply = IERC20(market).totalSupply();
        amountQuote = (liquidity * reserveQuote) / _totalSupply;
        amountBase = (liquidity * reserveBase) / _totalSupply;
        IERC20(market).burn(address(this), liquidity);
        if ((options & 1) == 0) {
            IERC20(quoteAsset).transfer(to, amountQuote);
        } else {
            require(((tokenBalances[0][quoteAsset] & MASK_KEEP_0_128) + amountQuote) <= MASK_KEEP_0_128);
            tokenBalances[0][quoteAsset] += amountQuote;
        }
        if (((options >> 4) & 1) == 0) {
            IERC20(baseAsset).transfer(to, amountBase);
        } else {
            require(((tokenBalances[0][baseAsset] & MASK_KEEP_0_128) + amountBase) <= MASK_KEEP_0_128);
            tokenBalances[0][baseAsset] += amountBase;
        }
        reserveQuote -= uint112(amountQuote);
        reserveBase -= uint112(amountBase);
        require(amountQuote >= amountQuoteMin && amountBase >= amountBaseMin && (m.isAMMEnabled == false || (m.highestBid <= ((reserveQuote * scaleFactor * 10000 * uint256(m.makerRebate) + (reserveBase * 9975 * 100000 - 1)) / (reserveBase * 9975 * 100000)) && m.lowestAsk >= ((reserveQuote * scaleFactor * 9975 * 100000) / (reserveBase * 10000 * uint256(m.makerRebate))))));
        (m.reserveQuote, m.reserveBase) = (uint112(reserveQuote), uint112(reserveBase));
        emit ICrystal.Sync(market, uint112(reserveQuote), uint112(reserveBase));
        emit ICrystal.Burn(market, msg.sender, amountQuote, amountBase, to);
    }

    /**
     * @notice Calculates the square root of a number (rounded down to nearest integer)
     *
     * @param y The number to find the square root of
     *
     * @return z The square root, rounded down
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
     * @notice Converts a tick number into its actual price value
     *
     * @param t The tick index
     *
     * @return The price that corresponds to this tick
     */
    function _tickToPrice(uint256 t) internal view returns (uint256) {
        unchecked {
            if (t <= 100_000) return t * tickSize;
            uint256 x = t - 10_000;
            return 10 ** (x / 90_000) * (10_000 + (x % 90_000)) * tickSize;
        }
    }

    /**
     * @notice Converts a price into its tick index
     *
     * @dev Will revert if the price doesn't line up with the allowed price grid for that range
     *
     * @param p The price value
     *
     * @return The tick index for this price
     */
    function _priceToTick(uint256 p) internal view returns (uint256) {
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
     * @notice Snaps a price to the nearest valid price on the grid
     *
     * @param p Raw price.
     * @param roundUp Whether to round up or down.
     *
     * @return The price adjusted to fit the valid grid
     */
    function _toValidPrice(uint256 p, bool roundUp) internal pure returns (uint256) {
        unchecked {
            uint256 d;
            if (p <= 100_000) return p;
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
            return roundUp ? ((p + d - 1) / d) * d : (p / d) * d;
        }
    }

    /**
     * @notice Searches upward through a bitmap to find the next tick that has active orders
     *
     * @param slot The bitmap containing tick activity flags
     * @param tick Where to start searching from
     *
     * @return The next active tick we found
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
     * @notice Searches downward through a bitmap to find the previous tick that has active orders
     *
     * @param slot The bitmap containing tick activity flags
     * @param tick Where to start searching from
     *
     * @return The previous active tick we found
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
     * @notice Figures out how much quote asset you need to spend on a buy to hit a specific execution price
     *
     * @dev Uses binary search to find the answer, with `high` as the maximum we'll search up to
     *
     * @param reserveQuote Current quote asset in the AMM
     * @param reserveBase Current base asset in the AMM
     * @param targetPrice The execution price you want to reach
     * @param _scaleFactor The market's price scaling factor
     * @param makerRebate Maker rebate that affects the price
     * @param high Maximum input amount to consider
     *
     * @return low Minimum quote amount needed to hit your target price
     */
    function _exactInputBuySolve(uint256 reserveQuote, uint256 reserveBase, uint256 targetPrice, uint256 _scaleFactor, uint256 makerRebate, uint256 high) internal pure returns (uint256 low) {
        unchecked {
            while (low < high) {
                uint256 mid = (low + high) >> 1;
                uint256 den = 9975 * (reserveBase - ((mid * 9975 * reserveBase) / (reserveQuote * 10000 + mid * 9975)));
                uint256 num = (reserveQuote + mid) * 10000;
                uint256 pMid = (num * _scaleFactor * makerRebate + ((den * 100000) - 1)) / (den * 100000);
                if (pMid > targetPrice) {
                    high = mid;
                } else {
                    low = mid + 1;
                }
            }
            return low;
        }
    }

    /**
     * @notice Figures out how much base asset you'll get from a buy at a specific execution price
     *
     * @dev Uses binary search to find the answer, maxing out at `high`
     *
     * @param reserveQuote Current quote asset in the AMM
     * @param reserveBase Current base asset in the AMM
     * @param targetPrice The execution price you want
     * @param _scaleFactor The market's price scaling factor
     * @param makerRebate Maker rebate that affects the price
     * @param high Maximum output amount to consider
     *
     * @return low Minimum base amount you'll get at your target price
     */
    function _exactOutputBuySolve(uint256 reserveQuote, uint256 reserveBase, uint256 targetPrice, uint256 _scaleFactor, uint256 makerRebate, uint256 high) internal pure returns (uint256 low) {
        unchecked {
            high = high > (reserveBase - 1) ? (reserveBase - 1) : high;
            while (low < high) {
                uint256 mid = (low + high) >> 1;
                uint256 num = (reserveQuote + ((mid * reserveQuote * 10000) / ((reserveBase - mid) * 9975)) + 1) * 10000;
                uint256 den = 9975 * (reserveBase - mid);
                uint256 pMid = (num * _scaleFactor * makerRebate + ((den * 100000) - 1)) / (den * 100000);
                if (pMid > targetPrice) {
                    high = mid;
                } else {
                    low = mid + 1;
                }
            }
        }
    }

    /**
     * @notice Figures out how much base asset you need to sell to hit a specific execution price
     *
     * @dev Uses binary search to find the answer, with `high` as the maximum
     *
     * @param reserveQuote Current quote asset in the AMM
     * @param reserveBase Current base asset in the AMM
     * @param targetPrice The execution price you want to reach
     * @param _scaleFactor The market's price scaling factor
     * @param makerRebate Maker rebate that affects the price
     * @param high Maximum input amount to consider
     *
     * @return low Minimum base amount needed to hit your target price
     */
    function _exactInputSellSolve(uint256 reserveQuote, uint256 reserveBase, uint256 targetPrice, uint256 _scaleFactor, uint256 makerRebate, uint256 high) internal pure returns (uint256 low) {
        unchecked {
            while (low < high) {
                uint256 mid = (low + high) >> 1;
                uint256 num = 9975 * (reserveQuote - ((mid * 9975 * reserveQuote) / (reserveBase * 10000 + mid * 9975)));
                uint256 den = (reserveBase + mid) * 10000;
                uint256 pMid = (num * _scaleFactor * 100000) / (den * makerRebate);
                if (pMid < targetPrice) {
                    high = mid;
                } else {
                    low = mid + 1;
                }
            }
        }
    }

    /**
     * @notice Figures out how much quote asset you'll get from a sell at a specific execution price
     *
     * @dev Uses binary search to find the answer, maxing out at `high`
     *
     * @param reserveQuote Current quote asset in the AMM
     * @param reserveBase Current base asset in the AMM
     * @param targetPrice The execution price you want
     * @param _scaleFactor The market's price scaling factor
     * @param makerRebate Maker rebate that affects the price
     * @param high Maximum output amount to consider
     *
     * @return low Minimum quote amount you'll get at your target price
     */
    function _exactOutputSellSolve(uint256 reserveQuote, uint256 reserveBase, uint256 targetPrice, uint256 _scaleFactor, uint256 makerRebate, uint256 high) internal pure returns (uint256 low) {
        unchecked {
            high = high > (reserveQuote - 1) ? (reserveQuote - 1) : high;
            while (low < high) {
                uint256 mid = (low + high) >> 1;
                uint256 den = (reserveBase + ((mid * reserveBase * 10000) / ((reserveQuote - mid) * 9975)) + 1) * 10000;
                uint256 num = 9975 * (reserveQuote - mid);
                uint256 pMid = (num * _scaleFactor * 100000) / (den * makerRebate);
                if (pMid < targetPrice) {
                    high = mid;
                } else {
                    low = mid + 1;
                }
            }
        }
    }

    /**
     * @notice Adds encoded order update data to the OrdersUpdated event buffer in memory
     *
     * @param logData The encoded order update information to append
     */
    function _addToOrdersUpdatedEvent(uint256 logData) internal pure {
        assembly {
            let length := mload(0xc0)
            mstore(add(length, 0xe0), logData)
            mstore(0xc0, add(length, 0x20))
            mstore(0x40, add(length, 0x100))
        }
    }

    /**
     * @notice Handles the actual token transfers for settling trades - either moves real tokens or updates internal balances
     *
     * @dev The balance mode flags control whether we do external token transfers or just update internal accounting. 0 = external, 1 = internal
     *
     * @param quoteAssetDebt How much quote asset is owed (positive means you owe, negative means you receive)
     * @param baseAssetDebt How much base asset is owed (positive means you owe, negative means you receive)
     * @param userId Your user ID for internal accounting
     * @param balanceMode 0 to use external transfers, 1 to use internal balances
     * @param balanceModeOut 0 to send outputs as real tokens, 1 to credit the router's internal balance
     * @param balanceModeIn 0 to pull from your wallet, 1 to pull from router's internal balance
     */
    function _settleBalances(int256 quoteAssetDebt, int256 baseAssetDebt, uint256 userId, uint256 balanceMode, uint256 balanceModeOut, uint256 balanceModeIn) internal {
        unchecked {
            if (balanceMode == 0) {
                // Settlement via external token transfers
                if (balanceModeIn != 0) {
                    if (quoteAssetDebt > 0) {
                        uint256 balance = tokenBalances[0][quoteAsset];
                        if (uint128(balance) < uint256(quoteAssetDebt)) {
                            revert ICrystal.ActionFailed();
                        } else {
                            tokenBalances[0][quoteAsset] = balance - uint256(quoteAssetDebt);
                        }
                    }
                    if (baseAssetDebt > 0) {
                        uint256 balance = tokenBalances[0][baseAsset];
                        if (uint128(balance) < uint256(baseAssetDebt)) {
                            revert ICrystal.ActionFailed();
                        } else {
                            tokenBalances[0][baseAsset] = balance - uint256(baseAssetDebt);
                        }
                    }
                } else {
                    if (quoteAssetDebt > 0) {
                        IERC20(quoteAsset).transferFrom(msg.sender, address(this), uint256(quoteAssetDebt));
                    }
                    if (baseAssetDebt > 0) {
                        IERC20(baseAsset).transferFrom(msg.sender, address(this), uint256(baseAssetDebt));
                    }
                }
                if (balanceModeOut != 0) {
                    if (quoteAssetDebt < 0) {
                        require(((tokenBalances[0][quoteAsset] & MASK_KEEP_0_128) + uint256(-quoteAssetDebt)) <= MASK_KEEP_0_128);
                        tokenBalances[0][quoteAsset] += uint256(-quoteAssetDebt);
                    }
                    if (baseAssetDebt < 0) {
                        require(((tokenBalances[0][baseAsset] & MASK_KEEP_0_128) + uint256(-baseAssetDebt)) <= MASK_KEEP_0_128);
                        tokenBalances[0][baseAsset] += uint256(-baseAssetDebt);
                    }
                } else {
                    if (quoteAssetDebt < 0) {
                        IERC20(quoteAsset).transfer(msg.sender, uint256(-quoteAssetDebt));
                    }
                    if (baseAssetDebt < 0) {
                        IERC20(baseAsset).transfer(msg.sender, uint256(-baseAssetDebt));
                    }
                }
            } else {
                if (balanceMode == 1) {
                    // Settlement via user internal balance accounting
                    if (quoteAssetDebt > 0) {
                        uint256 balance = tokenBalances[userId][quoteAsset];
                        if (uint128(balance) < uint256(quoteAssetDebt)) {
                            revert ICrystal.ActionFailed();
                        } else {
                            tokenBalances[userId][quoteAsset] = balance - uint256(quoteAssetDebt);
                        }
                    } else if (quoteAssetDebt < 0) {
                        require(((tokenBalances[userId][quoteAsset] & MASK_KEEP_0_128) + uint256(-quoteAssetDebt)) <= MASK_KEEP_0_128);
                        tokenBalances[userId][quoteAsset] += uint256(-quoteAssetDebt);
                    }
                    if (baseAssetDebt > 0) {
                        uint256 balance = tokenBalances[userId][baseAsset];
                        if (uint128(balance) < uint256(baseAssetDebt)) {
                            revert ICrystal.ActionFailed();
                        } else {
                            tokenBalances[userId][baseAsset] = balance - uint256(baseAssetDebt);
                        }
                    } else if (baseAssetDebt < 0) {
                        require(((tokenBalances[userId][baseAsset] & MASK_KEEP_0_128) + uint256(-baseAssetDebt)) <= MASK_KEEP_0_128);
                        tokenBalances[userId][baseAsset] += uint256(-baseAssetDebt);
                    }
                } else {
                    revert ICrystal.ActionFailed();
                }
            }
        }
    }

    /**
     * @notice Removes an order from book data structures and updates top-of-book state.
     *
     * @dev Assumes caller has already validated ownership and unlocked funds.
     *
     * @param price Order price.
     * @param id Order identifier or cloid pointer.
     * @param size Order size to remove.
     * @param highestBid Current highest bid.
     * @param lowestAsk Current lowest ask.
     * @param _order Packed order data.
     */
    function _internalCancel(uint256 price, uint256 id, uint256 size, uint256 highestBid, uint256 lowestAsk, uint256 _order) internal {
        unchecked {
            uint256 _priceLevel = priceLevels[marketId | price];
            _priceLevel -= size;
            if (id == ((_priceLevel >> 205) & MASK_KEEP_0_51)) {
                // Order is at fillNext position; advance pointer to fillAfter
                _priceLevel = (_order & (MASK_KEEP_0_51 << 205)) | (_priceLevel & MASK_OUT_205_256);
            } else if (id == ((_priceLevel >> 154) & MASK_KEEP_0_51)) {
                // Order is at latest position; revert pointer to fillBefore
                uint256 fillBefore = ((_order >> 154) & MASK_KEEP_0_51);
                uint256 orderpointer = ((fillBefore > MASK_KEEP_0_41) ? fillBefore : marketId | (price << 48) | fillBefore);
                orders[orderpointer] = (orders[orderpointer] & MASK_OUT_205_256) | (_order & (MASK_KEEP_0_51 << 205)); // Update fillBefore order's fillAfter pointer
                _priceLevel = (_priceLevel & MASK_OUT_154_205) | (fillBefore << 154);
            } else {
                uint256 fillBefore = ((_order >> 154) & MASK_KEEP_0_51);
                uint256 fillAfter = ((_order >> 205) & MASK_KEEP_0_51);
                uint256 orderpointer = ((fillBefore > MASK_KEEP_0_41) ? fillBefore : marketId | (price << 48) | fillBefore);
                orders[orderpointer] = (orders[orderpointer] & MASK_OUT_205_256) | (fillAfter << 205); // Link fillBefore to fillAfter, bypassing cancelled order
                orderpointer = ((fillAfter > MASK_KEEP_0_41) ? fillAfter : marketId | (price << 48) | fillAfter);
                orders[orderpointer] = (orders[orderpointer] & MASK_OUT_154_205) | (fillBefore << 154); // Link fillAfter to fillBefore, bypassing cancelled order
            }
            priceLevels[marketId | price] = _priceLevel;
            if ((_priceLevel & MASK_KEEP_0_112) == 0) {
                uint256 tick = marketType == 0 ? (price / tickSize) : _priceToTick(price);
                uint256 slotIndex = tick / 255;
                uint256 slot = activated[marketId | slotIndex] & MASK_OUT_255_256;
                slot &= ~(1 << (tick % 255));
                activated[marketId | slotIndex] = slot | MASK_KEEP_255_256;
                if (slot == 0) {
                    activated2[marketId | (slotIndex / 255)] &= ~(1 << (slotIndex % 255));
                }
                if (price == lowestAsk) {
                    slot = slot >> tick % 255;
                    if (slot == 0) {
                        uint256 slot2Index = slotIndex / 255;
                        uint256 slot2 = (activated2[marketId | slot2Index] & MASK_OUT_255_256 & ~(1 << (slotIndex % 255))) >> slotIndex % 255;
                        while (slot2 == 0) {
                            ++slot2Index;
                            slot2 = activated2[marketId | slot2Index] & MASK_OUT_255_256;
                            slotIndex = slot2Index * 255;
                        }
                        slotIndex = _searchSlotUp(slot2, slotIndex);
                        slot = activated[marketId | slotIndex] & MASK_OUT_255_256;
                        tick = slotIndex * 255;
                    }
                    tick = _searchSlotUp(slot, tick);
                    _getMarket[market].lowestAsk = uint80(marketType == 0 ? (tick * tickSize) : _tickToPrice(tick));
                } else if (price == highestBid) {
                    slot = slot & ((1 << (tick % 255)) - 1);
                    if (slot == 0) {
                        uint256 slot2Index = slotIndex / 255;
                        uint256 slot2 = (activated2[marketId | slot2Index] & MASK_OUT_255_256 & ~(1 << (slotIndex % 255))) & ((1 << (slotIndex % 255)) - 1);
                        while (slot2 == 0) {
                            --slot2Index;
                            slot2 = activated2[marketId | slot2Index] & MASK_OUT_255_256;
                        }
                        slotIndex = _searchSlotDown(slot2, slot2Index * 255);
                        slot = activated[marketId | slotIndex] & MASK_OUT_255_256;
                    }
                    tick = _searchSlotDown(slot, slotIndex * 255);
                    _getMarket[market].highestBid = uint80(marketType == 0 ? (tick * tickSize) : _tickToPrice(tick));
                }
            }
        }
    }

    /**
     * @notice Aggregates liquidity buckets starting from a price in ascending or descending order.
     *
     * @dev Writes encoded buckets into scratch memory for public getters.
     *
     * @param isAscending True to walk asks upward, false to walk bids downward.
     * @param startPrice Starting price for traversal.
     * @param distance Maximum distance from the start price in ticks.
     * @param interval Bucket interval size.
     * @param max Maximum number of buckets to return (0 = unlimited).
     */
    function _getPriceLevels(bool isAscending, uint256 startPrice, uint256 distance, uint256 interval, uint256 max) internal view {
        unchecked {
            uint256 _maxPrice = maxPrice;
            if (startPrice >= _maxPrice) {
                return;
            }
            uint256 _marketId = marketId;
            uint256 tick = marketType == 0 ? (startPrice / tickSize) : _priceToTick(startPrice);
            startPrice = tick; // Convert price to tick index for traversal
            if (!isAscending) {
                ++tick;
            }
            if (max == 0) {
                max = type(uint256).max;
            }
            uint256 price;
            uint256 position;
            uint256 bucket = type(uint256).max;
            uint256 slotIndex = tick / 255;
            uint256 slot = activated[marketId | slotIndex] & MASK_OUT_255_256;
            uint256 slot2Index = slotIndex / 255;
            uint256 slot2 = activated2[marketId | slot2Index] & MASK_OUT_255_256;
            assembly {
                position := mload(0x40)
                mstore(position, 0x0)
            }
            if (isAscending) {
                // Traverse ask-side price levels in ascending order
                if (startPrice + (distance) > (marketType == 0 ? (_maxPrice / tickSize) : _priceToTick(_maxPrice))) {
                    distance = ((marketType == 0 ? (_maxPrice / tickSize) : _priceToTick(_maxPrice)) - startPrice);
                }
                while (true) {
                    {
                        uint256 _slot = slot >> tick % 255;
                        if (_slot == 0) {
                            uint256 _slot2 = (slot2 & ~(1 << ((slotIndex) % 255))) >> slotIndex % 255;
                            while (_slot2 == 0) {
                                ++slot2Index;
                                slot2 = activated2[marketId | slot2Index] & MASK_OUT_255_256;
                                _slot2 = slot2;
                                slotIndex = slot2Index * 255;
                            }
                            slotIndex = _searchSlotUp(_slot2, slotIndex);
                            slot = activated[marketId | slotIndex] & MASK_OUT_255_256;
                            _slot = slot;
                            tick = slotIndex * 255;
                        }
                        tick = _searchSlotUp(_slot, tick);
                        slot &= ~(1 << (tick % 255));
                        if (slot >> tick % 255 == 0) {
                            slot2 &= ~(1 << ((slotIndex) % 255));
                        }
                    }
                    price = marketType == 0 ? (tick * tickSize) : _tickToPrice(tick);
                    if ((((price + interval - 1) / interval) * interval) == bucket) {
                        assembly {
                            mstore(0x00, or(_marketId, price))
                            mstore(0x20, priceLevels.slot)
                            let length := mload(position)
                            let existing := mload(add(length, position))
                            mstore(add(length, position), add(existing, and(sload(keccak256(0x00, 0x40)), MASK_KEEP_0_112)))
                        }
                    } else {
                        if (max == 0 || (tick >= startPrice + distance)) {
                            break;
                        }
                        --max;
                        bucket = ((price + interval - 1) / interval) * interval; // Round up for ask-side aggregation
                        assembly {
                            mstore(0x00, or(_marketId, price))
                            mstore(0x20, priceLevels.slot)
                            let length := mload(position)
                            mstore(add(length, add(position, 0x20)), or(shl(128, bucket), and(sload(keccak256(0x00, 0x40)), MASK_KEEP_0_112)))
                            mstore(position, add(length, 0x20))
                        }
                    }
                }
            } else {
                if (distance > startPrice) {
                    distance = startPrice;
                }
                while (true) {
                    uint256 _slot = slot & ((1 << (tick % 255)) - 1);
                    if (_slot == 0) {
                        uint256 _slot2 = (slot2 & ~(1 << ((slotIndex) % 255))) & ((1 << (slotIndex % 255)) - 1);
                        while (_slot2 == 0) {
                            --slot2Index;
                            slot2 = activated2[marketId | slot2Index] & MASK_OUT_255_256;
                            _slot2 = slot2;
                        }
                        slotIndex = _searchSlotDown(_slot2, slot2Index * 255);
                        slot = activated[marketId | slotIndex] & MASK_OUT_255_256;
                        _slot = slot;
                    }
                    tick = _searchSlotDown(_slot, slotIndex * 255);
                    slot &= ~(1 << (tick % 255));
                    if (slot & ((1 << (tick % 255)) - 1) == 0) {
                        slot2 &= ~(1 << ((slotIndex) % 255));
                    }
                    price = marketType == 0 ? (tick * tickSize) : _tickToPrice(tick);
                    if (((price / interval) * interval) == bucket) {
                        assembly {
                            mstore(0x00, or(_marketId, price))
                            mstore(0x20, priceLevels.slot)
                            let length := mload(position)
                            let existing := mload(add(length, position))
                            mstore(add(length, position), add(existing, and(sload(keccak256(0x00, 0x40)), MASK_KEEP_0_112)))
                        }
                    } else {
                        if (max == 0 || (tick <= startPrice - distance)) {
                            break;
                        }
                        --max;
                        bucket = (price / interval) * interval; // Round down for bid-side aggregation
                        assembly {
                            mstore(0x00, or(_marketId, price))
                            mstore(0x20, priceLevels.slot)
                            let length := mload(position)
                            mstore(add(length, add(position, 0x20)), or(shl(128, bucket), and(sload(keccak256(0x00, 0x40)), MASK_KEEP_0_112)))
                            mstore(position, add(length, 0x20))
                        }
                    }
                }
            }
        }
    }

    /**
     * @notice Returns aggregated orderbook liquidity starting from a price.
     *
     * @param isAscending True to walk asks upward, false to walk bids downward.
     * @param startPrice Starting price for traversal.
     * @param distance Maximum distance from the start price in ticks.
     * @param interval Bucket interval size.
     * @param max Maximum number of buckets to return (0 = unlimited).
     *
     * @return data Encoded price level buckets.
     */
    function getPriceLevels(bool isAscending, uint256 startPrice, uint256 distance, uint256 interval, uint256 max) external payable returns (bytes memory) {
        assembly {
            mstore(0x40, 0xa0)
        }
        _getPriceLevels(isAscending, startPrice, distance, interval, max);
        assembly {
            mstore(0x80, 0x20)
            return(0x80, add(mload(0xa0), 0x40))
        }
    }

    /**
     * @notice Returns bid and ask liquidity buckets around the current mid price.
     *
     * @param distance Number of ticks to scan on each side.
     * @param interval Bucket interval size.
     * @param max Maximum buckets per side (0 = unlimited).
     *
     * @return highestBid Current best bid.
     * @return lowestAsk Current best ask.
     * @return bids Encoded bid buckets.
     * @return asks Encoded ask buckets.
     */
    function getPriceLevelsFromMid(uint256 distance, uint256 interval, uint256 max) external payable returns (uint256 highestBid, uint256 lowestAsk, bytes memory, bytes memory) {
        ICrystal.Market storage m = _getMarket[market];
        uint256 length;
        (highestBid, lowestAsk) = (m.highestBid, m.lowestAsk);
        assembly {
            mstore(0x40, 0x100)
        }
        _getPriceLevels(false, highestBid, distance, interval, max);
        assembly {
            length := mload(0x100)
            mstore(0x40, add(length, 0x120))
        }
        _getPriceLevels(true, lowestAsk, distance, interval, max);
        assembly {
            mstore(0x80, highestBid)
            mstore(0xa0, lowestAsk)
            mstore(0xc0, 0x80)
            mstore(0xe0, add(0xa0, length))
            return(0x80, add(0xc0, add(length, mload(add(length, 0x120)))))
        }
    }

    /**
     * @notice Computes the midpoint price including AMM adjustments.
     *
     * @return price Rounded midpoint price.
     * @return highestBid Best bid considering orderbook and AMM.
     * @return lowestAsk Best ask considering orderbook and AMM.
     */
    function getPrice() external payable returns (uint256 price, uint256 highestBid, uint256 lowestAsk) {
        ICrystal.Market storage m = _getMarket[market];
        uint256 count;
        (highestBid, lowestAsk) = (m.highestBid, m.lowestAsk);
        (uint256 reserveQuote, uint256 reserveBase) = m.isAMMEnabled ? (m.reserveQuote, m.reserveBase) : (0, 0);
        if (reserveQuote != 0) {
            uint256 ammPrice = ((reserveQuote * scaleFactor * 9975 * 100000) / (reserveBase * 10000 * uint256(m.makerRebate)));
            ammPrice = marketType == 0 ? ((ammPrice + tickSize - 1) / tickSize) * tickSize : _toValidPrice(ammPrice, true); // Compute adjusted AMM bid price
            if (highestBid < ammPrice) {
                highestBid = ammPrice;
            }
            ammPrice = ((reserveQuote * scaleFactor * 10000 * uint256(m.makerRebate) + (reserveBase * 9975 * 100000 - 1)) / (reserveBase * 9975 * 100000));
            ammPrice = marketType == 0 ? (ammPrice - (ammPrice % tickSize)) : _toValidPrice(ammPrice, false); // Compute adjusted AMM ask price
            if (lowestAsk > ammPrice) {
                lowestAsk = ammPrice;
            }
        }
        price = highestBid;
        if (lowestAsk != maxPrice) {
            // Return highest bid when no asks exist instead of computing midpoint
            price += lowestAsk;
            ++count;
        }
        if (highestBid != 0) {
            // Return lowest ask when no bids exist instead of computing midpoint
            ++count;
        }
        if (count == 2) {
            uint256 mid = (price + 1) >> 1;
            price = marketType == 0 ? (mid - (mid % tickSize)) : _toValidPrice(mid, false);
        }
    }

    /**
     * @notice Quotes a trade against the orderbook and AMM without modifying state.
     *
     * @dev Mirrors execution behavior including taker fee and maker rebate adjustments.
     * @dev View function, but delegatecalled w/value, so needs to be payable.
     *
     * @param isBuy True for buy, false for sell.
     * @param isExactInput True if `size` is an input amount, false if it is output.
     * @param isCompleteFill Whether to revert when price limits are exceeded.
     * @param size Input or output amount depending on `isExactInput`.
     * @param worstPrice Inclusive worst price limit.
     *
     * @return amountIn Required input amount.
     * @return amountOut Expected output amount.
     */
    function getQuote(bool isBuy, bool isExactInput, bool isCompleteFill, uint256 size, uint256 worstPrice) external payable returns (uint256 amountIn, uint256 amountOut) {
        unchecked {
            ICrystal.Market storage m = _getMarket[market];
            uint256 price;
            if (isBuy) {
                if (isExactInput) {
                    size = (size * uint256(m.takerFee) + uint256(m.takerFee) - 1) / 100000;
                }
                if (worstPrice >= maxPrice || worstPrice == 0) {
                    worstPrice = (marketType == 0 ? maxPrice - tickSize : _tickToPrice(_priceToTick(maxPrice) - 1));
                }
                price = m.lowestAsk;
            } else {
                if (!isExactInput) {
                    size = (size * 100000 + uint256(m.takerFee) - 1) / uint256(m.takerFee);
                }
                if (worstPrice == 0) {
                    worstPrice = (marketType == 0 ? tickSize : _tickToPrice(1));
                }
                price = m.highestBid;
            }
            (uint256 reserveQuote, uint256 reserveBase) = m.isAMMEnabled ? (m.reserveQuote, m.reserveBase) : (0, 0);
            uint256 tick = marketType == 0 ? (price / tickSize) : _priceToTick(price);
            uint256 slot = activated[marketId | (tick / 255)] & MASK_OUT_255_256;
            uint256 slot2 = activated2[marketId | ((tick / 255) / 255)] & MASK_OUT_255_256;
            while (isExactInput ? size > amountIn : size > amountOut) {
                if (reserveQuote != 0) {
                    uint256 _amountIn = (isBuy ? (price > worstPrice) : (price < worstPrice)) ? worstPrice : price; // Bound by slippage limit or next resting order price
                    uint256 _amountOut;
                    if (isBuy && _amountIn > (reserveQuote * scaleFactor * 10000 * uint256(m.makerRebate) + (reserveBase * 9975 * 100000 - 1)) / (reserveBase * 9975 * 100000)) {
                        // Adjust execution price for AMM (no maker rebate applies)
                        uint256 _sizeLeft = isExactInput ? (size - amountIn) : (size - amountOut);
                        if (isExactInput) {
                            _amountIn = _exactInputBuySolve(reserveQuote, reserveBase, _amountIn, scaleFactor, m.makerRebate, _sizeLeft); // Compute optimal input for AMM execution at target price
                            if (_sizeLeft < _amountIn) {
                                _amountIn = _sizeLeft; // Cap at remaining size; execute entirely via AMM
                            }
                            _amountOut = (_amountIn * 9975 * reserveBase) / ((reserveQuote * 10000) + (_amountIn * 9975));
                        } else {
                            _amountOut = _exactOutputBuySolve(reserveQuote, reserveBase, _amountIn, scaleFactor, m.makerRebate, _sizeLeft); // Compute optimal output for AMM execution at target price
                            if (_sizeLeft < _amountOut) {
                                _amountOut = _sizeLeft; // Cap at remaining size; execute entirely via AMM
                            }
                            _amountIn = (_amountOut * reserveQuote * 10000) / ((reserveBase - _amountOut) * 9975) + 1;
                        }
                        reserveQuote += _amountIn;
                        reserveBase -= _amountOut;
                    } else if (!isBuy && _amountIn < (reserveQuote * scaleFactor * 9975 * 100000) / (reserveBase * 10000 * uint256(m.makerRebate))) {
                        uint256 _sizeLeft = isExactInput ? (size - amountIn) : (size - amountOut);
                        if (isExactInput) {
                            _amountIn = _exactInputSellSolve(reserveQuote, reserveBase, _amountIn, scaleFactor, m.makerRebate, _sizeLeft);
                            if (_sizeLeft < _amountIn) {
                                _amountIn = _sizeLeft;
                            }
                            _amountOut = ((_amountIn * 9975) * reserveQuote) / ((reserveBase * 10000) + (_amountIn * 9975));
                        } else {
                            _amountOut = _exactOutputSellSolve(reserveQuote, reserveBase, _amountIn, scaleFactor, m.makerRebate, _sizeLeft);
                            if (_sizeLeft < _amountOut) {
                                _amountOut = _sizeLeft;
                            }
                            _amountIn = (_amountOut * reserveBase * 10000) / ((reserveQuote - _amountOut) * 9975) + 1;
                        }
                        reserveBase += _amountIn;
                        reserveQuote -= _amountOut;
                    } else {
                        _amountIn = 0; // No AMM swap executed; skip subsequent AMM logic
                    }
                    if (_amountIn != 0) {
                        uint256 _sizeLeft = isExactInput ? (size - amountIn) : (size - amountOut);
                        amountIn += _amountIn;
                        amountOut += _amountOut;
                        if (_sizeLeft == (isExactInput ? _amountIn : _amountOut)) {
                            break;
                        }
                    }
                }
                if (isBuy ? price > worstPrice : price < worstPrice) {
                    if (isCompleteFill) {
                        revert ICrystal.SlippageExceeded();
                    } else {
                        break;
                    }
                }
                uint256 sizeLeft = isExactInput ? (size - amountIn) : (size - amountOut);
                uint256 liquidity = priceLevels[marketId | price] & MASK_KEEP_0_112;
                if (isExactInput ? (isBuy ? (liquidity > (((sizeLeft * uint256(m.makerRebate)) / 100000) * scaleFactor) / price) : (liquidity > (((sizeLeft * uint256(m.makerRebate)) / 100000) * price) / scaleFactor)) : (liquidity > sizeLeft)) {
                    amountOut += (isExactInput ? (isBuy ? (((sizeLeft * uint256(m.makerRebate)) / 100000) * scaleFactor) / price : (((sizeLeft * uint256(m.makerRebate)) / 100000) * price) / scaleFactor) : sizeLeft);
                    if (!isExactInput) {
                        sizeLeft = isBuy ? (sizeLeft * price * 100000 + (scaleFactor * uint256(m.makerRebate) - 1)) / (scaleFactor * uint256(m.makerRebate)) : (sizeLeft * scaleFactor * 100000 + (price * uint256(m.makerRebate) - 1)) / (price * uint256(m.makerRebate));
                    }
                    amountIn += sizeLeft;
                    sizeLeft = 0;
                } else {
                    amountIn += (isBuy ? ((((liquidity * price) / scaleFactor) * 100000) / uint256(m.makerRebate)) : ((((liquidity * scaleFactor) / price) * 100000) / uint256(m.makerRebate)));
                    amountOut += isBuy ? liquidity : liquidity;
                    sizeLeft -= isExactInput ? (isBuy ? ((((liquidity * price) / scaleFactor) * 100000) / uint256(m.makerRebate)) : ((((liquidity * scaleFactor) / price) * 100000) / uint256(m.makerRebate))) : liquidity;
                    liquidity = 0;
                }
                if (liquidity == 0) {
                    slot &= ~(1 << (tick % 255));
                    if (isBuy) {
                        uint256 slotIndex = tick / 255;
                        uint256 _slot = slot >> tick % 255;
                        if (_slot == 0) {
                            uint256 slot2Index = slotIndex / 255;
                            slot2 &= ~(1 << ((slotIndex) % 255));
                            uint256 _slot2 = slot2 >> slotIndex % 255;
                            while (_slot2 == 0) {
                                ++slot2Index;
                                slot2 = activated2[marketId | slot2Index] & MASK_OUT_255_256;
                                _slot2 = slot2;
                                slotIndex = slot2Index * 255;
                            }
                            slotIndex = _searchSlotUp(_slot2, slotIndex);
                            slot = activated[marketId | slotIndex] & MASK_OUT_255_256;
                            _slot = slot;
                            tick = slotIndex * 255;
                        }
                        tick = _searchSlotUp(_slot, tick);
                    } else {
                        uint256 slotIndex = tick / 255;
                        uint256 _slot = slot & ((1 << (tick % 255)) - 1);
                        if (_slot == 0) {
                            uint256 slot2Index = slotIndex / 255;
                            slot2 &= ~(1 << ((slotIndex) % 255));
                            uint256 _slot2 = slot2 & ((1 << (slotIndex % 255)) - 1);
                            while (_slot2 == 0) {
                                --slot2Index;
                                slot2 = activated2[marketId | slot2Index] & MASK_OUT_255_256;
                                _slot2 = slot2;
                            }
                            slotIndex = _searchSlotDown(_slot2, slot2Index * 255);
                            slot = activated[marketId | slotIndex] & MASK_OUT_255_256;
                            _slot = slot;
                        }
                        tick = _searchSlotDown(_slot, slotIndex * 255);
                    }
                    price = marketType == 0 ? (tick * tickSize) : _tickToPrice(tick);
                } else {
                    break;
                }
            }
            isBuy ? amountIn = (amountIn * 100000) / uint256(m.takerFee) : amountOut = (amountOut * uint256(m.takerFee)) / 100000;
            return (amountIn, amountOut);
        }
    }

    /**
     * @notice Executes a market-style order across resting liquidity and the AMM.
     *
     * @dev `orderInfo` encodes side, exactness, STP behavior, balance routing, caller, and optional cloid metadata.
     * @dev `orderInfo` is 256-252 orderType, 252-248 !isExactInput, 248-244 !isBuy, 244-240 STP, 240-236 !useexternalbalance, 236-232 !fromcaller
     *
     * @param size Input or output amount depending on `orderInfo` flags.
     * @param priceAndReferrer Worst price limit (low 80 bits) plus optional referrer address.
     * @param orderInfo Packed flags describing execution options.
     *
     * @return amountIn Total input amount including fees.
     * @return amountOut Total output amount after fees.
     * @return id New order id if a fallback limit order is placed.
     * @return settlementDelta Packed debit (high 128 bits) and credit (low 128 bits) for settlement.
     */
    function _marketOrder(uint256 size, uint256 priceAndReferrer, uint256 orderInfo) internal returns (uint256 amountIn, uint256 amountOut, uint256 id, uint256 settlementDelta) {
        // Settlement delta encoding: (debit << 128) | credit; debit = input asset, credit = output asset
        unchecked {
            require(size <= MASK_KEEP_0_128);
            ICrystal.Market storage m = _getMarket[market];
            uint256 price;
            if (((orderInfo >> 244) & 1) == 0) {
                if ((((orderInfo >> 248) & 1) == 0)) {
                    // Exact input mode: adjust size for taker fee
                    assembly {
                        mstore(0x60, size)
                    }
                    size = (size * uint256(m.takerFee) + 99999) / 100000; // Pre-adjust for taker fee applied to quote asset
                }
                if ((priceAndReferrer & MASK_KEEP_0_80) >= maxPrice || (priceAndReferrer & MASK_KEEP_0_80) == 0) {
                    priceAndReferrer = (priceAndReferrer & MASK_OUT_0_80) | (marketType == 0 ? maxPrice - tickSize : _tickToPrice(_priceToTick(maxPrice) - 1)); // Default worst price to one tick below max (inclusive limit)
                }
                price = m.lowestAsk;
            } else {
                if ((((orderInfo >> 248) & 1) != 0)) {
                    // Exact output mode: adjust size for taker fee
                    size = (size * 100000 + uint256(m.takerFee) - 1) / uint256(m.takerFee); // Pre-adjust for taker fee applied to quote asset
                }
                if ((priceAndReferrer & MASK_KEEP_0_80) == 0) {
                    priceAndReferrer = (priceAndReferrer & MASK_OUT_0_80) | (marketType == 0 ? tickSize : _tickToPrice(1)); // Default worst price to minimum tick (inclusive limit)
                }
                price = m.highestBid;
            }
            assembly {
                mstore(0x80, 0x0)
            }
            uint256 reserves = m.isAMMEnabled ? ((uint256(m.reserveQuote) << 128) | m.reserveBase) : 0;
            {
                uint256 tick = marketType == 0 ? (price / tickSize) : _priceToTick(price);
                uint256 slot = activated[marketId | (tick / 255)] & MASK_OUT_255_256;
                while ((((orderInfo >> 248) & 1) == 0) ? size > amountIn : size > amountOut) {
                    uint256 sizeLeft = (((orderInfo >> 248) & 1) == 0) ? size - amountIn : size - amountOut;
                    if (reserves != 0) {
                        // Skip AMM execution if pool not initialized
                        (uint256 reserveQuote, uint256 reserveBase) = (reserves >> 128, reserves & MASK_KEEP_0_112);
                        uint256 _amountIn = ((((orderInfo >> 244) & 1) == 0) ? (price > (priceAndReferrer & MASK_KEEP_0_80)) : (price < (priceAndReferrer & MASK_KEEP_0_80))) ? (priceAndReferrer & MASK_KEEP_0_80) : price;
                        uint256 _amountOut;
                        if ((((orderInfo >> 244) & 1) == 0) && _amountIn > (reserveQuote * scaleFactor * 10000 * uint256(m.makerRebate) + (reserveBase * 9975 * 100000 - 1)) / (reserveBase * 9975 * 100000)) {
                            if (((orderInfo >> 248) & 1) == 0) {
                                _amountIn = _exactInputBuySolve(reserveQuote, reserveBase, _amountIn, scaleFactor, m.makerRebate, sizeLeft); // Compute optimal input for AMM execution at maker-adjusted price
                                if (sizeLeft < _amountIn) {
                                    _amountIn = sizeLeft;
                                }
                                _amountOut = (_amountIn * 9975 * reserveBase) / ((reserveQuote * 10000) + (_amountIn * 9975)); // Execute Uniswap V2-style swap
                            } else {
                                _amountOut = _exactOutputBuySolve(reserveQuote, reserveBase, _amountIn, scaleFactor, m.makerRebate, sizeLeft); // Compute optimal output for AMM execution at maker-adjusted price
                                if (sizeLeft < _amountOut) {
                                    _amountOut = sizeLeft;
                                }
                                _amountIn = (_amountOut * reserveQuote * 10000) / ((reserveBase - _amountOut) * 9975) + 1; // Execute Uniswap V2-style swap
                            }
                            reserveQuote += _amountIn;
                            reserveBase -= _amountOut;
                            require(reserveQuote <= MASK_KEEP_0_112 && reserveBase <= MASK_KEEP_0_112);
                            {
                                uint256 pricememory;
                                assembly {
                                    pricememory := mload(0x80)
                                } // Price memory: upper 128 bits = start price, lower 128 bits = end price
                                uint256 endprice = ((reserveQuote * scaleFactor * 10000 * uint256(m.makerRebate) + (reserveBase * 9975 * 100000 - 1)) / (reserveBase * 9975 * 100000)); // Adjust price favorably for AMM (no maker rebate)
                                endprice = endprice >= maxPrice ? maxPrice : endprice <= tickSize ? tickSize : marketType == 0 ? (endprice - (endprice % tickSize)) : _toValidPrice(endprice, false); // Round down to valid tick
                                if (pricememory == 0) {
                                    uint256 startprice = (((reserveQuote - _amountIn) * scaleFactor * 10000 * uint256(m.makerRebate) + ((reserveBase + _amountOut) * 9975 * 100000 - 1)) / ((reserveBase + _amountOut) * 9975 * 100000));
                                    startprice = startprice >= maxPrice ? maxPrice : startprice <= tickSize ? tickSize : (marketType == 0 ? (startprice - (startprice % tickSize)) : _toValidPrice(startprice, false));
                                    pricememory = (startprice << 128) | endprice; // Initialize start price using pre-swap reserves
                                } else {
                                    pricememory = (pricememory & MASK_OUT_0_128) | endprice;
                                }
                                assembly {
                                    mstore(0x80, pricememory)
                                }
                            }
                        } else if ((((orderInfo >> 244) & 1) != 0) && _amountIn < (reserveQuote * scaleFactor * 9975 * 100000) / (reserveBase * 10000 * uint256(m.makerRebate))) {
                            if (((orderInfo >> 248) & 1) == 0) {
                                _amountIn = _exactInputSellSolve(reserveQuote, reserveBase, _amountIn, scaleFactor, m.makerRebate, sizeLeft);
                                if (sizeLeft < _amountIn) {
                                    _amountIn = sizeLeft;
                                }
                                _amountOut = ((_amountIn * 9975) * reserveQuote) / ((reserveBase * 10000) + (_amountIn * 9975)); // Execute Uniswap V2-style swap
                            } else {
                                _amountOut = _exactOutputSellSolve(reserveQuote, reserveBase, _amountIn, scaleFactor, m.makerRebate, sizeLeft);
                                if (sizeLeft < _amountOut) {
                                    _amountOut = sizeLeft;
                                }
                                _amountIn = (_amountOut * reserveBase * 10000) / ((reserveQuote - _amountOut) * 9975) + 1; // Execute Uniswap V2-style swap
                            }
                            reserveBase += _amountIn;
                            reserveQuote -= _amountOut;
                            require(reserveQuote <= MASK_KEEP_0_112 && reserveBase <= MASK_KEEP_0_112);
                            {
                                uint256 pricememory;
                                assembly {
                                    pricememory := mload(0x80)
                                } // Price memory: upper 128 bits = start price, lower 128 bits = end price
                                uint256 endprice = ((reserveQuote * scaleFactor * 9975 * 100000) / (reserveBase * 10000 * uint256(m.makerRebate)));
                                endprice = endprice >= maxPrice ? maxPrice : endprice <= tickSize ? tickSize : marketType == 0 ? ((endprice + tickSize - 1) / tickSize) * tickSize : _toValidPrice(endprice, true); // Round up to valid tick
                                if (pricememory == 0) {
                                    uint256 startprice = ((reserveQuote + _amountOut) * scaleFactor * 9975 * 100000) / ((reserveBase - _amountIn) * 10000 * uint256(m.makerRebate));
                                    startprice = startprice >= maxPrice ? maxPrice : startprice <= tickSize ? tickSize : marketType == 0 ? ((startprice + tickSize - 1) / tickSize) * tickSize : _toValidPrice(startprice, true);
                                    pricememory = (startprice << 128) | endprice;
                                } else {
                                    pricememory = (pricememory & MASK_OUT_0_128) | endprice;
                                }
                                assembly {
                                    mstore(0x80, pricememory)
                                }
                            }
                        } else {
                            _amountIn = 0;
                        }
                        if (_amountIn != 0) {
                            if (((settlementDelta >> 128) + _amountIn) <= MASK_KEEP_0_128) {
                                settlementDelta += (_amountIn << 128);
                            } else {
                                settlementDelta |= (MASK_KEEP_0_128 << 128);
                            }
                            amountIn += _amountIn;
                            amountOut += _amountOut;
                            reserves = (reserveQuote << 128) | reserveBase;
                            if (sizeLeft != ((((orderInfo >> 248) & 1) == 0) ? _amountIn : _amountOut)) {
                                sizeLeft -= ((((orderInfo >> 248) & 1) == 0) ? _amountIn : _amountOut);
                            } else {
                                if (activated[marketId | (tick / 255)] & MASK_OUT_255_256 != slot) {
                                    // Persist activated bitmap changes and exit swap loop
                                    activated[marketId | (tick / 255)] = slot | MASK_KEEP_255_256;
                                }
                                break;
                            }
                        }
                    }
                    if ((((orderInfo >> 244) & 1) == 0) ? price > (priceAndReferrer & MASK_KEEP_0_80) : price < (priceAndReferrer & MASK_KEEP_0_80)) {
                        // Slippage limit exceeded; handle fallback behavior
                        sizeLeft = (priceAndReferrer & MASK_KEEP_0_80); // Extract worst price for limit order
                        if ((orderInfo >> 252) == 1) {
                            revert ICrystal.SlippageExceeded();
                        }
                        if (activated[marketId | (tick / 255)] & MASK_OUT_255_256 != slot) {
                            activated[marketId | (tick / 255)] = slot | MASK_KEEP_255_256;
                        }
                        if ((orderInfo >> 252) == 2) {
                            if (reserves != 0) {
                                // Commit reserves to prevent limit order from crossing AMM
                                (uint112 reserveQuote, uint112 reserveBase) = (uint112(reserves >> 128), uint112(reserves & MASK_KEEP_0_112));
                                if (reserveQuote != m.reserveQuote || reserveBase != m.reserveBase) {
                                    (m.reserveQuote, m.reserveBase) = (reserveQuote, reserveBase);
                                    emit ICrystal.Sync(market, reserveQuote, reserveBase);
                                }
                                reserves = 0; // Mark reserves as already persisted
                            }
                            tick = orderInfo; // Avoid stack too deep
                            (((tick >> 244) & 1) == 0) ? m.lowestAsk = uint80(price) : m.highestBid = uint80(price);
                            slot = (((tick >> 248) & 1) == 0) ? (size - amountIn) : ((((tick >> 244) & 1) == 0) ? (((size - amountOut) * sizeLeft) / scaleFactor) : (((size - amountOut) * scaleFactor) / sizeLeft));
                            if ((((tick >> 248) & 1) == 0) && (((tick >> 244) & 1) == 0)) {
                                assembly {
                                    slot := mload(0x60)
                                }
                            }
                            (slot, id) = _limitOrder((((tick >> 244) & 1) == 0), ((tick >> 236) & 0x1) == 0, sizeLeft, ((((tick >> 244) & 1) == 0) ? (((tick >> 248) & 1) == 0) ? slot - (amountIn * 100000) / uint256(m.takerFee) : slot : (((tick >> 248) & 1) == 0) ? slot : (slot * uint256(m.takerFee)) / 100000), ((tick >> 160) & MASK_KEEP_0_41), ((tick >> 208) & MASK_KEEP_0_10));
                            if (((settlementDelta >> 128) + slot) <= MASK_KEEP_0_128) {
                                settlementDelta += (slot << 128);
                            } else {
                                settlementDelta |= (MASK_KEEP_0_128 << 128);
                            }
                            if (slot != 0) {
                                // Buffer limit order event data for emission in outer function
                                _addToOrdersUpdatedEvent((LEADING_HEX_2 + ((((tick >> 244) & 1) == 0) ? 0 : LEADING_HEX_1)) | (sizeLeft << 168) | (id << 112) | slot); // Encoded: 8-bit flag | 80-bit price | 56-bit id | 112-bit size
                            }
                        }
                        break;
                    }
                    uint256 _priceLevel = priceLevels[marketId | price];
                    {
                        uint256 next = (_priceLevel >> 205) & MASK_KEEP_0_51;
                        uint256 _orderInfo = orderInfo; // Avoid stack too deep
                        while ((_priceLevel & MASK_KEEP_0_112) != 0 && sizeLeft != 0 && !((_orderInfo >> 252) == 3 && gasleft() < 200000)) {
                            // Reserve 200k gas for type 3 order completion
                            uint256 _order = orders[((next > MASK_KEEP_0_41) ? next : marketId | (price << 48) | next)];
                            if (((_orderInfo >> 240) & 0xF) != 0 && ((_order >> 113) & MASK_KEEP_0_41) == ((_orderInfo >> 160) & MASK_KEEP_0_41)) {
                                // Self-trade prevention: 0=none, 1=cancel maker, 2=cancel taker, 3=cancel both
                                if (((_orderInfo >> 240) & 0x1) != 0) {
                                    // Cancel resting order (STP mode 1 or 3)
                                    bool isBuy = ((_orderInfo >> 244) & 1) == 0;
                                    uint256 ordersize = (_order & MASK_KEEP_0_112);
                                    if (next > MASK_KEEP_0_41) {
                                        orders[next] &= MASK_KEEP_113_154;
                                    } else {
                                        delete orders[marketId | (price << 48) | next];
                                    }
                                    _priceLevel -= ordersize;
                                    if (((settlementDelta & MASK_KEEP_0_128) + ordersize) <= MASK_KEEP_0_128) {
                                        settlementDelta += ordersize;
                                    } else {
                                        settlementDelta |= MASK_KEEP_0_128;
                                    }
                                    if ((_order & MASK_KEEP_112_113) != 0) {
                                        tokenBalances[(_order >> 113) & MASK_KEEP_0_41][isBuy ? baseAsset : quoteAsset] -= (ordersize << 128); // Release locked tokens for internal balance orders
                                    }
                                    _addToOrdersUpdatedEvent((isBuy ? LEADING_HEX_1 : 0) | (price << 168) | (next << 112) | ordersize); // Encoded: 8-bit flag | 80-bit price | 56-bit id | 112-bit cancelled size
                                    next = (_order >> 205) & MASK_KEEP_0_51;
                                }
                                if (((_orderInfo >> 240) & 0xF) == 1) {
                                    continue;
                                } else {
                                    // Cancel taker order (STP mode 2 or 3)
                                    sizeLeft = 0;
                                    break;
                                }
                            }
                            if ((((_orderInfo >> 248) & 1) == 0) ? ((((_orderInfo >> 244) & 1) == 0) ? ((_order & MASK_KEEP_0_112) > (((sizeLeft * uint256(m.makerRebate)) / 100000) * scaleFactor) / price) : ((_order & MASK_KEEP_0_112) > (((sizeLeft * uint256(m.makerRebate)) / 100000) * price) / scaleFactor)) : ((_order & MASK_KEEP_0_112) > sizeLeft)) {
                                {
                                    // Resting order quantity denominated in resting asset
                                    bool isBuy = ((_orderInfo >> 244) & 1) == 0;
                                    uint256 _amountOut = ((((_orderInfo >> 248) & 1) == 0) ? (isBuy ? (((sizeLeft * uint256(m.makerRebate)) / 100000) * scaleFactor) / price : (((sizeLeft * uint256(m.makerRebate)) / 100000) * price) / scaleFactor) : sizeLeft); // Calculate output amount (rounded down)
                                    amountOut += _amountOut;
                                    if ((((_orderInfo >> 248) & 1) != 0)) {
                                        sizeLeft = isBuy ? (sizeLeft * price * 100000 + (scaleFactor * uint256(m.makerRebate) - 1)) / (scaleFactor * uint256(m.makerRebate)) : (sizeLeft * scaleFactor * 100000 + (price * uint256(m.makerRebate) - 1)) / (price * uint256(m.makerRebate)); // Maker transfer amount (rounded up)
                                    }
                                    _priceLevel -= _amountOut;
                                    _order -= _amountOut;
                                    orders[((next > MASK_KEEP_0_41) ? next : marketId | (price << 48) | next)] = _order;
                                    uint256 ownerUserId = (_order >> 113) & MASK_KEEP_0_41;
                                    address owner = userIdToAddress[ownerUserId];
                                    if (_order & MASK_KEEP_112_113 == 0) {
                                        // Maker receives external tokens
                                        if (((_orderInfo >> 236) & 0x1) == 0 && ((_orderInfo >> 232) & 0x1) == 0) {
                                            // Taker provides external tokens
                                            try IERC20(isBuy ? quoteAsset : baseAsset).transferFrom(msg.sender, owner, sizeLeft) {} catch {
                                                uint256 tempSettlementDelta = settlementDelta; // Avoid stack too deep
                                                if (((tempSettlementDelta >> 128) + sizeLeft) <= MASK_KEEP_0_128) {
                                                    settlementDelta = tempSettlementDelta + (sizeLeft << 128);
                                                } else {
                                                    settlementDelta = tempSettlementDelta | (MASK_KEEP_0_128 << 128);
                                                }
                                                if (((tokenBalances[ownerUserId][isBuy ? quoteAsset : baseAsset] & MASK_KEEP_0_128) + sizeLeft) <= MASK_KEEP_0_128) {
                                                    tokenBalances[ownerUserId][isBuy ? quoteAsset : baseAsset] += sizeLeft;
                                                } else {
                                                    tokenBalances[ownerUserId][isBuy ? quoteAsset : baseAsset] |= MASK_KEEP_0_128;
                                                }
                                            }
                                        } else {
                                            // Taker provides from internal balance
                                            uint256 tempSettlementDelta = settlementDelta; // Avoid stack too deep
                                            if (((tempSettlementDelta >> 128) + sizeLeft) <= MASK_KEEP_0_128) {
                                                settlementDelta = tempSettlementDelta + (sizeLeft << 128);
                                            } else {
                                                settlementDelta = tempSettlementDelta | (MASK_KEEP_0_128 << 128);
                                            }
                                            (bool success, ) = (isBuy ? quoteAsset : baseAsset).call(abi.encodeWithSelector(0xa9059cbb, owner, sizeLeft));
                                            // Fallback: credit internal balance if external transfer fails (e.g., blacklisted maker)
                                            if (!success) {
                                                if (((tokenBalances[ownerUserId][isBuy ? quoteAsset : baseAsset] & MASK_KEEP_0_128) + sizeLeft) <= MASK_KEEP_0_128) {
                                                    tokenBalances[ownerUserId][isBuy ? quoteAsset : baseAsset] += sizeLeft;
                                                } else {
                                                    tokenBalances[ownerUserId][isBuy ? quoteAsset : baseAsset] |= MASK_KEEP_0_128;
                                                }
                                            }
                                        }
                                    } else {
                                        // Maker receives to internal balance
                                        uint256 tempSettlementDelta = settlementDelta; // Avoid stack too deep
                                        if (((tempSettlementDelta >> 128) + sizeLeft) <= MASK_KEEP_0_128) {
                                            settlementDelta = tempSettlementDelta + (sizeLeft << 128);
                                        } else {
                                            settlementDelta = tempSettlementDelta | (MASK_KEEP_0_128 << 128);
                                        }
                                        if (((tokenBalances[ownerUserId][isBuy ? quoteAsset : baseAsset] & MASK_KEEP_0_128) + sizeLeft) <= MASK_KEEP_0_128) {
                                            tokenBalances[ownerUserId][isBuy ? quoteAsset : baseAsset] += sizeLeft;
                                        } else {
                                            tokenBalances[ownerUserId][isBuy ? quoteAsset : baseAsset] |= MASK_KEEP_0_128;
                                        }
                                        tokenBalances[ownerUserId][isBuy ? baseAsset : quoteAsset] -= (_amountOut << 128); // Release maker's locked internal balance
                                    }
                                    address _market = market;
                                    assembly {
                                        let length := mload(0xc0)
                                        mstore(add(length, 0xe0), or(mul(LEADING_HEX_1, iszero(isBuy)), or(shl(168, price), or(shl(112, next), and(MASK_KEEP_0_112, _order)))))
                                        mstore(add(length, 0x100), or(shl(128, sizeLeft), _amountOut))
                                        log3(add(length, 0xe0), 0x40, FILL_SIG, _market, owner)
                                        mstore(0x40, add(length, 0xe0))
                                    }
                                }
                                amountIn += sizeLeft;
                                sizeLeft = 0;
                            } else {
                                {
                                    // Resting order quantity denominated in resting asset
                                    uint256 transferAmount = (((_orderInfo >> 244) & 1) == 0) ? (((((_order & MASK_KEEP_0_112) * price) / scaleFactor) * 100000) / uint256(m.makerRebate)) : (((((_order & MASK_KEEP_0_112) * scaleFactor) / price) * 100000) / uint256(m.makerRebate));
                                    amountIn += transferAmount;
                                    uint256 _amountOut = (_order & MASK_KEEP_0_112);
                                    amountOut += _amountOut;
                                    _priceLevel -= _amountOut;
                                    sizeLeft -= (((_orderInfo >> 248) & 1) == 0) ? transferAmount : _amountOut;
                                    uint256 ownerUserId = (_order >> 113) & MASK_KEEP_0_41;
                                    address owner = userIdToAddress[ownerUserId];
                                    if (_order & MASK_KEEP_112_113 == 0) {
                                        // Maker receives external tokens
                                        if (((_orderInfo >> 236) & 0x1) == 0 && ((_orderInfo >> 232) & 0x1) == 0) {
                                            // Taker provides external tokens
                                            try IERC20((((_orderInfo >> 244) & 1) == 0) ? quoteAsset : baseAsset).transferFrom(msg.sender, owner, transferAmount) {} catch {
                                                uint256 tempSettlementDelta = settlementDelta; // Avoid stack too deep
                                                if (((tempSettlementDelta >> 128) + transferAmount) <= MASK_KEEP_0_128) {
                                                    settlementDelta = tempSettlementDelta + (transferAmount << 128);
                                                } else {
                                                    settlementDelta = tempSettlementDelta | (MASK_KEEP_0_128 << 128);
                                                }
                                                if (((tokenBalances[ownerUserId][(((_orderInfo >> 244) & 1) == 0) ? quoteAsset : baseAsset] & MASK_KEEP_0_128) + transferAmount) <= MASK_KEEP_0_128) {
                                                    tokenBalances[ownerUserId][(((_orderInfo >> 244) & 1) == 0) ? quoteAsset : baseAsset] += transferAmount;
                                                } else {
                                                    tokenBalances[ownerUserId][(((_orderInfo >> 244) & 1) == 0) ? quoteAsset : baseAsset] |= MASK_KEEP_0_128;
                                                }
                                            }
                                        } else {
                                            // Taker provides from internal balance
                                            uint256 tempSettlementDelta = settlementDelta; // Avoid stack too deep
                                            if (((tempSettlementDelta >> 128) + transferAmount) <= MASK_KEEP_0_128) {
                                                settlementDelta = tempSettlementDelta + (transferAmount << 128);
                                            } else {
                                                settlementDelta = tempSettlementDelta | (MASK_KEEP_0_128 << 128);
                                            }
                                            (bool success, ) = ((((_orderInfo >> 244) & 1) == 0) ? quoteAsset : baseAsset).call(abi.encodeWithSelector(0xa9059cbb, owner, transferAmount));
                                            // Fallback: credit internal balance if external transfer fails (e.g., blacklisted maker)
                                            if (!success) {
                                                if (((tokenBalances[ownerUserId][(((_orderInfo >> 244) & 1) == 0) ? quoteAsset : baseAsset] & MASK_KEEP_0_128) + transferAmount) <= MASK_KEEP_0_128) {
                                                    tokenBalances[ownerUserId][(((_orderInfo >> 244) & 1) == 0) ? quoteAsset : baseAsset] += transferAmount;
                                                } else {
                                                    tokenBalances[ownerUserId][(((_orderInfo >> 244) & 1) == 0) ? quoteAsset : baseAsset] |= MASK_KEEP_0_128;
                                                }
                                            }
                                        }
                                    } else {
                                        // Maker receives to internal balance
                                        uint256 tempSettlementDelta = settlementDelta; // Avoid stack too deep
                                        if (((tempSettlementDelta >> 128) + transferAmount) <= MASK_KEEP_0_128) {
                                            settlementDelta = tempSettlementDelta + (transferAmount << 128);
                                        } else {
                                            settlementDelta = tempSettlementDelta | (MASK_KEEP_0_128 << 128);
                                        }
                                        if (((tokenBalances[ownerUserId][(((_orderInfo >> 244) & 1) == 0) ? quoteAsset : baseAsset] & MASK_KEEP_0_128) + transferAmount) <= MASK_KEEP_0_128) {
                                            tokenBalances[ownerUserId][(((_orderInfo >> 244) & 1) == 0) ? quoteAsset : baseAsset] += transferAmount;
                                        } else {
                                            tokenBalances[ownerUserId][(((_orderInfo >> 244) & 1) == 0) ? quoteAsset : baseAsset] |= MASK_KEEP_0_128;
                                        }
                                        tokenBalances[ownerUserId][(((_orderInfo >> 244) & 1) == 0) ? baseAsset : quoteAsset] -= (_amountOut << 128); // Release maker's locked internal balance
                                    }
                                    address _market = market;
                                    assembly {
                                        let length := mload(0xc0)
                                        mstore(add(length, 0xe0), or(mul(LEADING_HEX_1, and(shr(244, _orderInfo), 1)), or(shl(168, price), shl(112, next))))
                                        mstore(add(length, 0x100), or(shl(128, transferAmount), _amountOut))
                                        log3(add(length, 0xe0), 0x40, FILL_SIG, _market, owner)
                                        mstore(0x40, add(length, 0xe0))
                                    }
                                }
                                if (next > MASK_KEEP_0_41) {
                                    orders[next] &= MASK_KEEP_113_154;
                                } else {
                                    delete orders[marketId | (price << 48) | next];
                                }
                                next = (_order >> 205) & MASK_KEEP_0_51;
                            }
                        }
                        priceLevels[marketId | price] = (next << 205) | (_priceLevel & MASK_OUT_205_256); // Advance fillNext pointer
                    }
                    assembly {
                        // Update price range for Fill event emission
                        let pricememory := mload(0x80) // Upper 128 bits = start price, lower 128 bits = end price
                        switch pricememory
                        case 0 {
                            pricememory := or(shl(128, price), price)
                        }
                        default {
                            pricememory := or(and(pricememory, MASK_OUT_0_128), price) // Update end price for event
                        }
                        mstore(0x80, pricememory)
                    }
                    if ((_priceLevel & MASK_KEEP_0_112) == 0) {
                        // Price level exhausted; find next active level and update bitmap if needed
                        slot &= ~(1 << (tick % 255));
                        uint256 slotIndex = tick / 255;
                        if (((orderInfo >> 244) & 1) == 0) {
                            uint256 _slot = slot >> tick % 255;
                            if (_slot == 0 && ((activated[marketId | slotIndex] & MASK_OUT_255_256) != slot)) {
                                activated[marketId | slotIndex] = slot | MASK_KEEP_255_256;
                            }
                            if (_slot == 0) {
                                uint256 slot2Index = slotIndex / 255;
                                uint256 slot2 = (activated2[marketId | slot2Index] & MASK_OUT_255_256 & ~(1 << (slotIndex % 255))) >> slotIndex % 255;
                                if (slot == 0) {
                                    activated2[marketId | slot2Index] &= ~(1 << ((slotIndex) % 255));
                                }
                                while (slot2 == 0) {
                                    ++slot2Index;
                                    slot2 = activated2[marketId | slot2Index] & MASK_OUT_255_256;
                                    slotIndex = slot2Index * 255;
                                }
                                slotIndex = _searchSlotUp(slot2, slotIndex);
                                slot = activated[marketId | slotIndex] & MASK_OUT_255_256;
                                _slot = slot;
                                tick = slotIndex * 255;
                            }
                            tick = _searchSlotUp(_slot, tick);
                        } else {
                            uint256 _slot = slot & ((1 << (tick % 255)) - 1);
                            if (_slot == 0 && ((activated[marketId | slotIndex] & MASK_OUT_255_256) != slot)) {
                                activated[marketId | slotIndex] = slot | MASK_KEEP_255_256;
                            }
                            if (_slot == 0) {
                                uint256 slot2Index = slotIndex / 255;
                                uint256 slot2 = (activated2[marketId | slot2Index] & MASK_OUT_255_256 & ~(1 << (slotIndex % 255))) & ((1 << (slotIndex % 255)) - 1);
                                if (slot == 0) {
                                    activated2[marketId | slot2Index] &= ~(1 << ((slotIndex) % 255));
                                }
                                while (slot2 == 0) {
                                    --slot2Index;
                                    slot2 = activated2[marketId | slot2Index] & MASK_OUT_255_256;
                                }
                                slotIndex = _searchSlotDown(slot2, slot2Index * 255);
                                slot = activated[marketId | slotIndex] & MASK_OUT_255_256;
                                _slot = slot;
                            }
                            tick = _searchSlotDown(_slot, slotIndex * 255);
                        }
                        price = marketType == 0 ? (tick * tickSize) : _tickToPrice(tick);
                    } else {
                        if (activated[marketId | (tick / 255)] & MASK_OUT_255_256 != slot) {
                            activated[marketId | (tick / 255)] = slot | MASK_KEEP_255_256;
                        }
                    }
                    if (sizeLeft == 0 || ((orderInfo >> 252) == 3 && gasleft() < 200000)) {
                        // Reserve 200k gas for type 3 order completion
                        break;
                    }
                }
            }
            if (amountIn != 0 || amountOut != 0) {
                if (reserves != 0) {
                    // Persist AMM reserve updates if modified
                    (uint112 reserveQuote, uint112 reserveBase) = (uint112(reserves >> 128), uint112(reserves & MASK_KEEP_0_112));
                    if (reserveQuote != m.reserveQuote || reserveBase != m.reserveBase) {
                        (m.reserveQuote, m.reserveBase) = (reserveQuote, reserveBase);
                        emit ICrystal.Sync(market, reserveQuote, reserveBase);
                    }
                }
                uint256 feeAmount;
                if (((orderInfo >> 244) & 1) == 0) {
                    // Trading fees denominated in quote asset
                    feeAmount = (amountIn * 100000) / uint256(m.takerFee) - amountIn;
                    amountIn += feeAmount;
                    if (((settlementDelta >> 128) + feeAmount) <= MASK_KEEP_0_128) {
                        settlementDelta += (feeAmount << 128);
                    } else {
                        settlementDelta |= (MASK_KEEP_0_128 << 128);
                    }
                    m.lowestAsk = uint80(price);
                } else {
                    feeAmount = amountOut - (amountOut * uint256(m.takerFee)) / 100000;
                    amountOut -= feeAmount;
                    m.highestBid = uint80(price);
                }
                if (address(uint160(priceAndReferrer >> 80)) == address(0)) {
                    uint256 creatorFee;
                    if (marketType == 3) {
                        creatorFee = (feeAmount * m.creatorFeeSplit) / 100;
                        claimableRewards[quoteAsset][m.creator] += creatorFee;
                    }
                    claimableRewards[quoteAsset][feeRecipient] += (feeAmount - creatorFee);
                } else {
                    uint256 amountCommission = (feeAmount * feeCommission) / 100;
                    claimableRewards[quoteAsset][address(uint160(priceAndReferrer >> 80))] += amountCommission;
                    uint256 creatorFee;
                    if (marketType == 3) {
                        creatorFee = (feeAmount * m.creatorFeeSplit) / 100;
                        claimableRewards[quoteAsset][m.creator] += creatorFee;
                    }
                    claimableRewards[quoteAsset][feeRecipient] += (feeAmount - amountCommission - creatorFee);
                }
                assembly {
                    price := mload(0x80)
                }
                emit ICrystal.Trade(market, address(uint160(orderInfo)), ((orderInfo >> 244) & 1) == 0, amountIn, amountOut, price >> 128, price & MASK_KEEP_0_128);
                return (amountIn, amountOut, id, settlementDelta);
            } else {
                return (0, 0, id, settlementDelta);
            }
        }
    }

    /**
     * @notice Places a limit order on the orderbook.
     *
     * @dev Validates prices against spread, AMM bounds, cloid uniqueness, and minimum size. `isRecieveTokens` toggles whether maker proceeds are sent externally or kept in internal balances.
     *
     * @param isBuy True for bids, false for asks.
     * @param isRecieveTokens True to receive proceeds as token transfers, false to use internal balances.
     * @param price Limit price.
     * @param size Order size (quote for bids, base for asks).
     * @param userId User id placing the order.
     * @param cloid Optional client order id.
     *
     * @return orderSize Final size placed.
     * @return id Assigned order identifier (native id or cloid pointer).
     */
    function _limitOrder(bool isBuy, bool isRecieveTokens, uint256 price, uint256 size, uint256 userId, uint256 cloid) internal returns (uint256, uint256 id) {
        // Client order ID (cloid) validated as uint10 at entry points
        unchecked {
            ICrystal.Market storage m = _getMarket[market];
            if (isBuy) {
                (uint256 highestBid, uint256 lowestAsk) = (m.highestBid, m.lowestAsk);
                if (price >= lowestAsk || (m.isAMMEnabled && m.reserveQuote != 0 && price > ((uint256(m.reserveQuote) * scaleFactor * 10000 * uint256(m.makerRebate) + (uint256(m.reserveBase) * 9975 * 100000 - 1)) / (uint256(m.reserveBase) * 9975 * 100000))) || (cloid != 0 && (orders[(cloid << 41) | userId] & MASK_OUT_113_154) != 0) || price == 0 || size < ((m.minSize >> 20) * 10 ** (m.minSize & MASK_KEEP_0_20))) {
                    return (0, 0);
                }
                if (price > highestBid) {
                    m.highestBid = uint80(price);
                }
                if (!isRecieveTokens) {
                    require(((tokenBalances[userId][quoteAsset] >> 128) + size) <= MASK_KEEP_0_128);
                    tokenBalances[userId][quoteAsset] += (size << 128); // Lock tokens for internal balance orders
                }
            } else {
                (uint256 highestBid, uint256 lowestAsk) = (m.highestBid, m.lowestAsk);
                if (price <= highestBid || (m.isAMMEnabled && m.reserveQuote != 0 && price < ((uint256(m.reserveQuote) * scaleFactor * 9975 * 100000) / (uint256(m.reserveBase) * 10000 * uint256(m.makerRebate)))) || (cloid != 0 && (orders[(cloid << 41) | userId] & MASK_OUT_113_154) != 0) || price >= maxPrice || ((size * price) / scaleFactor) < ((m.minSize >> 20) * 10 ** (m.minSize & MASK_KEEP_0_20))) {
                    return (0, 0);
                }
                if (price < lowestAsk) {
                    m.lowestAsk = uint80(price);
                }
                if (!isRecieveTokens) {
                    require(((tokenBalances[userId][baseAsset] >> 128) + size) <= MASK_KEEP_0_128);
                    tokenBalances[userId][baseAsset] += (size << 128); // Lock tokens for internal balance orders
                }
            }
            uint256 _priceLevel = priceLevels[marketId | price];
            require((size <= MASK_KEEP_0_112) && ((_priceLevel & MASK_KEEP_0_112) + size) <= MASK_KEEP_0_112); // Bounds check: invalid parameters revert rather than silently fail
            if (cloid != 0) {
                uint256 orderpointer = ((cloid | 1) << 41) | userId;
                if (cloid & 1 != 0) {
                    cloidVerify[orderpointer] = (cloidVerify[orderpointer] & MASK_OUT_0_128) | ((marketId >> 48) | price);
                } else {
                    cloidVerify[orderpointer] = (cloidVerify[orderpointer] & MASK_KEEP_0_128) | ((marketId << 80) | (price << 128));
                }
                cloid = (cloid << 41) | userId; // Convert cloid to storage pointer with userId
                if ((_priceLevel & MASK_KEEP_0_112) == 0) {
                    require(price % tickSize == 0);
                    uint256 tick = marketType == 0 ? (price / tickSize) : _priceToTick(price);
                    uint256 slot = activated[marketId | (tick / 255)] & MASK_OUT_255_256;
                    activated[marketId | (tick / 255)] = slot | (1 << (tick % 255)) | MASK_KEEP_255_256;
                    if (slot == 0) {
                        activated2[marketId | ((tick / 255) / 255)] |= (1 << ((tick / 255) % 255)) | MASK_KEEP_255_256;
                    }
                    _priceLevel = (cloid << 205) | (_priceLevel & MASK_OUT_205_256); // Set fillNext pointer to cloid
                } else {
                    uint256 fillBefore = (_priceLevel >> 154) & MASK_KEEP_0_51;
                    orders[(fillBefore > MASK_KEEP_0_41) ? fillBefore : (marketId | (price << 48) | fillBefore)] = (cloid << 205) | (orders[(fillBefore > MASK_KEEP_0_41) ? fillBefore : (marketId | (price << 48) | fillBefore)] & MASK_OUT_205_256); // Update fillBefore's fillAfter to point to cloid
                }
                orders[cloid] = ((((_priceLevel >> 113) & MASK_KEEP_0_41) + 1) << 205) | (_priceLevel & (MASK_KEEP_0_51 << 154)) | (userId << 113) | (isRecieveTokens ? 0 : (1 << 112)) | size; // Set fillAfter to next native ID, fillBefore to latest
                priceLevels[marketId | price] = (cloid << 154) | ((_priceLevel & MASK_OUT_154_205) + size); // Update latest pointer to cloid and add to liquidity
                return (size, cloid);
            } else {
                id = ((_priceLevel >> 113) & MASK_KEEP_0_41) + 1;
                require(id <= MASK_KEEP_0_41); // Validate order ID fits in uint41
                if ((_priceLevel & MASK_KEEP_0_112) == 0) {
                    require(price % tickSize == 0);
                    uint256 tick = marketType == 0 ? (price / tickSize) : _priceToTick(price);
                    uint256 slot = activated[marketId | (tick / 255)] & MASK_OUT_255_256;
                    activated[marketId | (tick / 255)] = slot | (1 << (tick % 255)) | MASK_KEEP_255_256;
                    if (slot == 0) {
                        activated2[marketId | ((tick / 255) / 255)] |= (1 << ((tick / 255) % 255)) | MASK_KEEP_255_256;
                    }
                    _priceLevel = (id << 205) | (_priceLevel & MASK_OUT_205_256); // Set fillNext pointer to order ID
                }
                orders[marketId | (price << 48) | id] = ((id + 1) << 205) | (_priceLevel & (MASK_KEEP_0_51 << 154)) | (userId << 113) | (isRecieveTokens ? 0 : (1 << 112)) | size; // Set fillAfter to next ID, fillBefore to latest
                priceLevels[marketId | price] = (id << 154) | (id << 113) | ((_priceLevel & MASK_OUT_113_205) + size); // Update latest and latestNativeId, add to liquidity
                return (size, id);
            }
        }
    }

    /**
     * @notice Cancels an existing order and unlocks its funds.
     *
     * @dev Supports both native ids and cloIds; ownership is verified via `userId`.
     *
     * @param price Order price (0 when cancelling by cloid).
     * @param id Order id or cloid.
     * @param userId User id owning the order.
     *
     * @return priceResolved Price used for cancellation.
     * @return size Amount cancelled.
     * @return isBuy True if the cancelled order was a bid.
     */
    function _cancelOrder(uint256 price, uint256 id, uint256 userId) internal returns (uint256, uint256 size, bool isBuy) {
        // Interpret id as cloid when price is zero
        unchecked {
            ICrystal.Market storage m = _getMarket[market];
            uint256 _order = orders[(price != 0 ? (marketId | (price << 48) | id) : ((id << 41) | userId))]; // ID not yet converted to storage pointer
            size = (_order & MASK_KEEP_0_112);
            if (0 == size || userId != ((_order >> 113) & MASK_KEEP_0_41)) {
                return (0, 0, isBuy);
            }
            if (price == 0) {
                price = cloidVerify[((id | 1) << 41) | userId]; // Retrieve price from cloid verification mapping
                if (id & 1 != 0) {
                    // Validate cloid belongs to this market and extract price
                    if (((price >> 80) & MASK_KEEP_0_48) != (marketId >> 128)) {
                        return (0, 0, isBuy);
                    }
                    price = price & MASK_KEEP_0_80;
                } else {
                    if (((price >> 208) & MASK_KEEP_0_48) != (marketId >> 128)) {
                        return (0, 0, isBuy);
                    }
                    price = (price >> 128) & MASK_KEEP_0_80;
                }
                id = (id << 41) | userId; // Convert ID to storage pointer with userId
                orders[id] &= MASK_KEEP_113_154;
            } else {
                delete orders[marketId | (price << 48) | id];
            }
            (uint256 highestBid, uint256 lowestAsk) = (m.highestBid, m.lowestAsk);
            if (price <= highestBid) {
                isBuy = true;
                if ((_order & MASK_KEEP_112_113) != 0) {
                    tokenBalances[userId][quoteAsset] -= (size << 128); // Release locked tokens for internal balance
                }
            } else {
                if ((_order & MASK_KEEP_112_113) != 0) {
                    tokenBalances[userId][baseAsset] -= (size << 128); // Release locked tokens for internal balance
                }
            }
            _internalCancel(price, id, size, highestBid, lowestAsk, _order);
            return (price, size, isBuy);
        }
    }

    /**
     * @notice Decreases the size of an order or cancels it if the remainder would be below minimum size.
     *
     * @param price Order price (0 when referencing a cloid).
     * @param id Order id or cloid.
     * @param decreaseAmount Amount to reduce.
     * @param userId User id owning the order.
     *
     * @return priceResolved Price used for the update.
     * @return size Encoded delta (raw size when cancelled, or decrease amount << 128 for partial reductions).
     * @return isBuy True if the order is a bid.
     */
    function _decreaseOrder(uint256 price, uint256 id, uint256 decreaseAmount, uint256 userId) internal returns (uint256, uint256 size, bool isBuy) {
        // Interpret id as cloid when price is zero
        unchecked {
            ICrystal.Market storage m = _getMarket[market];
            uint256 _order = orders[(price != 0 ? (marketId | (price << 48) | id) : ((id << 41) | userId))]; // ID not yet converted to storage pointer
            size = (_order & MASK_KEEP_0_112);
            if (0 == size || userId != ((_order >> 113) & MASK_KEEP_0_41) || decreaseAmount > MASK_KEEP_0_112) {
                return (0, 0, isBuy);
            }
            if (price == 0) {
                price = cloidVerify[((id | 1) << 41) | userId]; // Retrieve price from cloid verification mapping
                if (id & 1 != 0) {
                    // Validate cloid belongs to this market and extract price
                    if (((price >> 80) & MASK_KEEP_0_48) != (marketId >> 128)) {
                        return (0, 0, isBuy);
                    }
                    price = price & MASK_KEEP_0_80;
                } else {
                    if (((price >> 208) & MASK_KEEP_0_48) != (marketId >> 128)) {
                        return (0, 0, isBuy);
                    }
                    price = (price >> 128) & MASK_KEEP_0_80;
                }
                id = (id << 41) | userId; // Convert ID to storage pointer with userId
            }
            (uint256 highestBid, uint256 lowestAsk) = (m.highestBid, m.lowestAsk);
            if (price <= highestBid) {
                isBuy = true;
            }
            if ((isBuy ? size : ((size * price) / scaleFactor)) < (isBuy ? decreaseAmount : ((decreaseAmount * price) / scaleFactor)) + (((m.minSize >> 20) * 10 ** (m.minSize & MASK_KEEP_0_20)))) {
                // Cancel entirely if resulting order size would be dust
                if ((_order & MASK_KEEP_112_113) != 0) {
                    isBuy ? tokenBalances[userId][quoteAsset] -= (size << 128) : tokenBalances[userId][baseAsset] -= (size << 128); // Release locked internal balance tokens
                }
                if (id > MASK_KEEP_0_41) {
                    orders[id] &= MASK_KEEP_113_154;
                } else {
                    delete orders[marketId | (price << 48) | id];
                }
                _internalCancel(price, id, size, highestBid, lowestAsk, _order);
                return (price, size, isBuy);
            } else {
                if ((_order & MASK_KEEP_112_113) != 0) {
                    isBuy ? tokenBalances[userId][quoteAsset] -= (decreaseAmount << 128) : tokenBalances[userId][baseAsset] -= (decreaseAmount << 128); // Release locked internal balance tokens
                }
                orders[(id > MASK_KEEP_0_41 ? id : (marketId | (price << 48) | id))] -= decreaseAmount;
                priceLevels[marketId | price] -= decreaseAmount;
                return (price, decreaseAmount << 128, isBuy); // Return order details for settlement
            }
        }
    }

    /**
     * @notice Cancels or adjusts an order then optionally reposts it or executes as a taker trade.
     *
     * @dev `options` controls balance routing, post-only, decrease behavior, and carries user/referrer context.
     *
     * @param options Packed flags including user id and balance modes.
     * @param price Existing order price (0 when referencing a cloid).
     * @param id Existing order id or cloid.
     * @param newPrice New price (low 80 bits) optionally combined with a referrer.
     * @param newSize New order size (0 to reuse previous size).
     *
     * @return quoteAssetDebt Net quote delta to settle.
     * @return baseAssetDebt Net base delta to settle.
     * @return newId Identifier of the replacement order, or 0 if none.
     */
    function _replaceOrder(uint256 options, uint256 price, uint256 id, uint256 newPrice, uint256 newSize) internal returns (int256 quoteAssetDebt, int256 baseAssetDebt, uint256) {
        unchecked {
            bool isBuy;
            bool isCloid;
            uint256 prevSize;
            uint256 userId = (options & MASK_KEEP_0_41);
            if (price == 0) {
                isCloid = true;
                price = cloidVerify[((id | 1) << 41) | userId]; // Retrieve price from cloid verification mapping
                if (id & 1 != 0) {
                    // Validate cloid belongs to this market and extract price
                    if (((price >> 80) & MASK_KEEP_0_48) != (marketId >> 128)) {
                        return (0, 0, 0);
                    }
                    price = price & MASK_KEEP_0_80;
                } else {
                    if (((price >> 208) & MASK_KEEP_0_48) != (marketId >> 128)) {
                        return (0, 0, 0);
                    }
                    price = (price >> 128) & MASK_KEEP_0_80;
                }
                prevSize = (orders[((id << 41) | userId)] & MASK_KEEP_0_112); // Read order size using raw ID
            } else {
                prevSize = (orders[(marketId | (price << 48) | id)] & MASK_KEEP_0_112); // Read order size using raw ID
            }
            if (price <= _getMarket[market].highestBid) {
                isBuy = true;
            }
            if ((newPrice & MASK_KEEP_0_80) == 0) {
                newPrice += price;
            }
            if ((((options >> 48) & 1) != 0) || ((newPrice & MASK_KEEP_0_80) == price && (prevSize > newSize))) {
                if (prevSize <= newSize) {
                    return (0, 0, 0); // No state change; silent return permitted
                }
                (price, prevSize, isBuy) = _decreaseOrder(isCloid ? 0 : price, id, prevSize - newSize, userId); // Price is zero for cloid-based lookups
                if (isCloid) {
                    id = (id << 41) | userId; // Encode cloid with userId for event emission
                }
                if (prevSize != 0) {
                    if ((prevSize >> 128) == 0) {
                        isBuy ? quoteAssetDebt -= int256(prevSize) : baseAssetDebt -= int256(prevSize);
                        _addToOrdersUpdatedEvent((isBuy ? 0 : LEADING_HEX_1) | (price << 168) | (id << 112) | prevSize); // Encoded: 3-bit flag | 80-bit price | 56-bit id | 112-bit cancelled size
                    } else {
                        isBuy ? quoteAssetDebt -= int256(prevSize >> 128) : baseAssetDebt -= int256(prevSize >> 128);
                        _addToOrdersUpdatedEvent((LEADING_HEX_4 + (isBuy ? 0 : LEADING_HEX_1)) | (price << 168) | (id << 112) | (prevSize >> 128)); // Encoded: 3-bit flag | 80-bit price | 56-bit id | 112-bit decreased amount
                    }
                    return (quoteAssetDebt, baseAssetDebt, id);
                } else {
                    return (0, 0, 0); // No state change; silent return permitted
                }
            } else {
                (price, prevSize, isBuy) = _cancelOrder((isCloid) ? 0 : price, id, userId); // Price is zero for cloid-based lookups
                if (isCloid) {
                    id = (id << 41) | userId; // Encode cloid with userId for event emission
                }
                if (prevSize != 0) {
                    isBuy ? quoteAssetDebt -= int256(prevSize) : baseAssetDebt -= int256(prevSize);
                    _addToOrdersUpdatedEvent((isBuy ? 0 : LEADING_HEX_1) | (price << 168) | (id << 112) | prevSize); // Encoded: 3-bit flag | 80-bit price | 56-bit id | 112-bit size
                } else {
                    return (0, 0, 0); // No state change; silent return permitted
                }
                if (isCloid) {
                    id = id >> 41; // Restore original cloid from encoded form
                } else {
                    id = 0;
                }
                if (newSize == 0) {
                    newSize = prevSize;
                }
                if (((options >> 44) & 1) == 0) {
                    // Post-only order placement
                    (prevSize, id) = _limitOrder(isBuy, (((options >> 60) & 1) == 0), (newPrice & MASK_KEEP_0_80), newSize, userId, id);
                    if (prevSize != 0) {
                        isBuy ? quoteAssetDebt += int256(prevSize) : baseAssetDebt += int256(prevSize);
                        _addToOrdersUpdatedEvent((LEADING_HEX_2 + (isBuy ? 0 : LEADING_HEX_1)) | ((newPrice & MASK_KEEP_0_80) << 168) | (id << 112) | prevSize); // Encoded: 3-bit flag | 80-bit price | 56-bit id | 112-bit size
                    } else {
                        return (quoteAssetDebt, baseAssetDebt, 0);
                    }
                } else {
                    isCloid = ((options >> 60) & 1) == 0; // Reuse variable: true indicates external balance mode
                    uint256 settlementDelta;
                    uint256 caller = (options >> 96);
                    uint256 orderInfo = (2 << 252) | (isBuy ? 0 : (1 << 244)) | (1 << 240) | (isCloid ? 0 : (1 << 236)) | (id << 208) | (userId << 160) | caller;
                    (, prevSize, id, settlementDelta) = _marketOrder(newSize, newPrice, orderInfo);
                    if (isBuy) {
                        quoteAssetDebt += int256(settlementDelta >> 128);
                        baseAssetDebt -= int256(prevSize + (settlementDelta & MASK_KEEP_0_128)); // Safe: value bounded by uint128 intrinsic limit
                    } else {
                        baseAssetDebt += int256(settlementDelta >> 128);
                        quoteAssetDebt -= int256(prevSize + (settlementDelta & MASK_KEEP_0_128)); // Safe: value bounded by uint128 intrinsic limit
                    }
                }
                return (quoteAssetDebt, baseAssetDebt, id);
            }
        }
    }

    /**
     * @notice Executes a market order using internal or external balances.
     *
     * @dev `options` encodes balance routing, STP behavior, and optional cloid/user identifiers.
     *
     * @param isBuy True for buy, false for sell.
     * @param isExactInput True if `size` is an input amount, false if it is output.
     * @param options Packed flags for balance sources/destinations and identifiers.
     * @param orderType Execution type (IOC/MTL/partial/complete).
     * @param size Input or output amount depending on `isExactInput`.
     * @param worstPrice Inclusive worst price limit.
     * @param referrer Optional referrer for fee sharing.
     * @param user User executing the order.
     *
     * @return amountIn Total input amount including fees.
     * @return amountOut Total output amount after fees.
     * @return id New order id if a fallback limit order was placed.
     */
    function marketOrder(bool isBuy, bool isExactInput, uint256 options, uint256 orderType, uint256 size, uint256 worstPrice, address referrer, address user) external payable returns (uint256 amountIn, uint256 amountOut, uint256 id) {
        unchecked {
            uint256 orderInfo; // Options encoding: 0-44 userId, 44-54 cloid, 56-60 stp, 60-64 toInternal, 64-68 fromInternal, 68-72 useInternal
            uint256 userId;
            {
                uint256 orderFlags = ((orderType & 0xF) << 252) | ((isExactInput ? 0 : (1 << 248))) | ((isBuy ? 0 : (1 << 244))) | (((options >> 56) & 0xF) << 240); // Encode order type: exactInput=0, isBuy=0, with STP mode
                orderInfo = orderFlags | (((options >> 68) & 1) << 236) | (((options >> 64) & 1) << 232) | uint160(user); // Embed caller address; userId at bits 160-208 for internal/MTL, cloid at 208-218 for MTL
                userId = (options & MASK_KEEP_0_41);
                if (userId != 0) {
                    require(userIdToAddress[userId] == user);
                } else {
                    userId = addressToUserId[user];
                    if (userId == 0) {
                        userId = ICrystal(crystal).registerUser(user);
                    }
                }
                orderInfo |= (userId << 160); // Embed userId in order info structure
                if (((options >> 44) & MASK_KEEP_0_10) != 0) {
                    // Client order ID (cloid) provided
                    orderInfo |= (((options >> 44) & MASK_KEEP_0_10) << 208);
                }
            }
            uint256 settlementDelta;
            assembly {
                mstore(0x40, 0xe0) // Reserve memory; 0x80 used internally by _marketOrder
            }
            (amountIn, amountOut, id, settlementDelta) = _marketOrder(size, (uint160(referrer) << 80) | worstPrice, orderInfo);
            address _market = market;
            assembly {
                let length := mload(0xc0)
                if gt(length, 0) {
                    mstore(0xa0, 0x20)
                    log3(0xa0, add(length, 0x40), ORDERS_UPDATED_SIG, _market, user)
                }
            }
            address token = isBuy ? quoteAsset : baseAsset;
            if ((settlementDelta >> 128) != 0) {
                // Handle input token for limit order placement and maker fills
                if (((options >> 68) & 1) != 0) {
                    uint256 balance = tokenBalances[userId][token];
                    if (uint128(balance) < (settlementDelta >> 128)) {
                        revert ICrystal.ActionFailed();
                    } else {
                        tokenBalances[userId][token] = balance - (settlementDelta >> 128);
                    }
                } else {
                    // External balance mode: transfer tokens
                    if (((options >> 64) & 1) != 0) {
                        // Use router's internal balance
                        uint256 balance = tokenBalances[0][token];
                        if (uint128(balance) < (settlementDelta >> 128)) {
                            revert ICrystal.ActionFailed();
                        } else {
                            tokenBalances[0][token] = balance - (settlementDelta >> 128);
                        }
                    } else {
                        IERC20(token).transferFrom(msg.sender, address(this), (settlementDelta >> 128));
                    }
                }
            }
            settlementDelta = (settlementDelta & MASK_KEEP_0_128) + amountOut; // Accumulate output with self-cancel credit
            token = isBuy ? baseAsset : quoteAsset;
            if (settlementDelta != 0) {
                // Handle output token: STP cancellations plus trade output
                if (((options >> 68) & 1) != 0) {
                    require(((tokenBalances[userId][token] & MASK_KEEP_0_128) + settlementDelta) <= MASK_KEEP_0_128);
                    tokenBalances[userId][token] += settlementDelta;
                } else {
                    // External balance mode: transfer tokens
                    if (((options >> 60) & 1) != 0) {
                        require(((tokenBalances[0][token] & MASK_KEEP_0_128) + settlementDelta) <= MASK_KEEP_0_128);
                        tokenBalances[0][token] += settlementDelta;
                    } else {
                        IERC20(token).transfer(msg.sender, settlementDelta);
                    }
                }
            }
        }
    }

    /**
     * @notice Places a limit order using internal or external balances.
     *
     * @param isBuy True for bids, false for asks.
     * @param options Packed flags for user id, cloid, and balance routing.
     * @param price Limit price.
     * @param size Order size.
     * @param user Order owner.
     *
     * @return id Assigned order identifier (native id or cloid pointer).
     */
    function limitOrder(bool isBuy, uint256 options, uint256 price, uint256 size, address user) external payable returns (uint256 id) {
        // Options encoding: 0-41 userId, 44-54 cloid, 56-60 fromInternal, 60-64 useInternal
        unchecked {
            uint256 userId = (options & MASK_KEEP_0_41);
            if (userId != 0) {
                // Verify provided userId matches caller
                require(userIdToAddress[userId] == user);
            } else {
                // Retrieve or create userId for caller
                userId = addressToUserId[user];
                if (userId == 0) {
                    userId = ICrystal(crystal).registerUser(user);
                }
            }
            bool useExternalBalances = (((options >> 60) & 1) == 0);
            (size, id) = _limitOrder(isBuy, useExternalBalances, price, size, userId, (options >> 44) & MASK_KEEP_0_10);
            if (size != 0) {
                address token = isBuy ? quoteAsset : baseAsset;
                if (useExternalBalances) {
                    if (((options >> 56) & 1) != 0) {
                        uint256 balance = tokenBalances[0][token];
                        if (uint128(balance) < size) {
                            revert ICrystal.ActionFailed();
                        } else {
                            tokenBalances[0][token] = balance - size;
                        }
                    } else {
                        IERC20(token).transferFrom(msg.sender, address(this), size);
                    }
                } else {
                    uint256 balance = tokenBalances[userId][token];
                    if (uint128(balance) < size) {
                        revert ICrystal.ActionFailed();
                    } else {
                        tokenBalances[userId][token] = balance - size; // Direct debit; locking handled in internal function
                    }
                }
                emit ICrystal.OrdersUpdated(market, user, abi.encodePacked((isBuy ? LEADING_HEX_2 : LEADING_HEX_3) | (price << 168) | (id << 112) | size)); // Cloid already encoded with userId when applicable
            } else {
                revert ICrystal.ActionFailed();
            }
        }
    }

    /**
     * @notice Cancels an order and returns locked funds to the chosen balance destination.
     *
     * @param options Packed flags for user id and balance destination.
     * @param price Order price (0 when cancelling by cloid).
     * @param id Order id or cloid.
     * @param user Order owner.
     *
     * @return size Amount released.
     */
    function cancelOrder(uint256 options, uint256 price, uint256 id, address user) external payable returns (uint256 size) {
        // Options encoding: 0-41 userId, 44-48 toInternal, 48-52 useInternal
        unchecked {
            bool isBuy;
            uint256 userId = (options & MASK_KEEP_0_41);
            if (userId != 0) {
                // Verify provided userId matches caller
                require(userIdToAddress[userId] == user);
            } else {
                // Retrieve or create userId for caller
                userId = addressToUserId[user];
            }
            bool useExternalBalances = (((options >> 48) & 1) == 0);
            bool isCloid = (price == 0); // Zero price indicates cloid-based lookup
            (price, size, isBuy) = _cancelOrder(price, id, userId); // Execute cancel; returns resolved price
            if (isCloid) {
                id = (id << 41) | userId;
            }
            if (size != 0) {
                address token = isBuy ? quoteAsset : baseAsset;
                if (useExternalBalances) {
                    if (((options >> 44) & 1) != 0) {
                        require(((tokenBalances[0][token] & MASK_KEEP_0_128) + size) <= MASK_KEEP_0_128);
                        tokenBalances[0][token] += size;
                    } else {
                        IERC20(token).transfer(msg.sender, size);
                    }
                } else {
                    require(((tokenBalances[userId][token] & MASK_KEEP_0_128) + size) <= MASK_KEEP_0_128);
                    tokenBalances[userId][token] += size;
                }
                emit ICrystal.OrdersUpdated(market, user, abi.encodePacked((isBuy ? 0 : LEADING_HEX_1) | (price << 168) | (id << 112) | size));
            }
        }
    }

    /**
     * @notice Replaces or decreases an existing order and settles resulting balance deltas.
     *
     * @dev Replace is useful in that if cancel fails there's no order, will decrease if its best course of action, and also that you can take the proceeds of the cancel as the order size by setting size = 0, can also do decrease.
     *
     * @param options Packed flags for user id and balance routing.
     * @param price Existing order price (0 when using a cloid).
     * @param id Existing order id or cloid.
     * @param newPrice New price (may embed referrer).
     * @param size New size (0 to reuse previous size).
     * @param referrer Referrer address for fee sharing.
     * @param user Order owner.
     *
     * @return _id Identifier of the replacement order, or 0 if none.
     */
    function replaceOrder(uint256 options, uint256 price, uint256 id, uint256 newPrice, uint256 size, address referrer, address user) external payable returns (uint256 _id) {
        // Options encoding: 0-41 userId, 44-48 postOnly, 48-52 isDecrease, 52-56 toInternal, 56-60 fromInternal, 60-64 useInternal
        int256 quoteAssetDebt;
        int256 baseAssetDebt;
        uint256 userId = (options & MASK_KEEP_0_41);
        if (userId != 0) {
            // Verify provided userId matches caller
            require(userIdToAddress[userId] == user);
        } else {
            // Retrieve or create userId for caller
            userId = addressToUserId[user];
            if (userId == 0) {
                userId = ICrystal(crystal).registerUser(user);
            }
            options = (options & MASK_OUT_0_41) | userId; // Embed userId in options
        }
        options = (uint160(user) << 96) | (options & MASK_KEEP_0_96);
        newPrice = (uint160(referrer) << 80) | newPrice;
        assembly {
            mstore(0x40, 0xe0) // Reserve memory; 0x80 used internally by _marketOrder
        }
        (quoteAssetDebt, baseAssetDebt, _id) = _replaceOrder(options, price, id, newPrice, size);
        uint256 balanceMode = options; // Avoid stack too deep
        _settleBalances(quoteAssetDebt, baseAssetDebt, userId, ((balanceMode >> 60) & 1), ((balanceMode >> 52) & 1), ((balanceMode >> 56) & 1));
        address _market = market;
        assembly {
            let length := mload(0xc0)
            switch gt(length, 0)
            case true {
                mstore(0xa0, 0x20)
                log3(0xa0, add(length, 0x40), ORDERS_UPDATED_SIG, _market, user)
            }
            default {
                revert(0, 0)
            }
        }
    }

    /**
     * @notice Executes a batch of order actions with shared settlement.
     *
     * @dev Processes actions sequentially; `options` controls balance routing for the batch.
     *
     * @param actions Array of encoded actions to execute.
     * @param options Packed flags for user id and balance routing.
     * @param referrer Referrer address used for market orders.
     * @param user Caller associated with the actions.
     */
    function batchOrders(ICrystal.Action[] calldata actions, uint256 options, address referrer, address user) external payable {
        // Options encoding: 0-41 userId, 44-48 toInternal, 48-52 fromInternal, 52-56 useInternal
        unchecked {
            uint256 userId;
            uint256 offset;
            uint256 action;
            uint256 param1;
            uint256 param2;
            uint256 cloid;
            bool isBuy;
            uint256 balanceMode;
            int256 quoteAssetDebt;
            int256 baseAssetDebt;
            if ((options & MASK_KEEP_0_41) != 0) {
                // Verify provided userId matches caller
                userId = (options & MASK_KEEP_0_41);
                require(userIdToAddress[userId] == user);
            } else {
                // Retrieve or create userId for caller
                userId = addressToUserId[user];
                if (userId == 0) {
                    userId = ICrystal(crystal).registerUser(user);
                }
            }
            balanceMode = ((options >> 52) & 1);
            assembly {
                mstore(0x40, 0xe0)
            }
            while (offset < actions.length) {
                action = actions[offset].action & 0xF;
                param1 = actions[offset].param1 & MASK_KEEP_0_80;
                param2 = actions[offset].param2 & MASK_KEEP_0_112;
                cloid = actions[offset].param3 & MASK_KEEP_0_10;
                if (action == 1) {
                    // Cancel order: accepts price+id or cloid
                    if (cloid != 0) {
                        (param1, action, isBuy) = _cancelOrder(0, cloid, userId);
                        param2 = (cloid << 41) | userId; // Encode cloid with userId for event emission
                    } else {
                        (param1, action, isBuy) = _cancelOrder(param1, param2, userId);
                    }
                    if (action != 0) {
                        isBuy ? quoteAssetDebt -= int256(action) : baseAssetDebt -= int256(action);
                        _addToOrdersUpdatedEvent((isBuy ? 0 : LEADING_HEX_1) | (param1 << 168) | (param2 << 112) | action); // Encoded: 8-bit flag | 80-bit price | 56-bit id | 112-bit cancelled size
                    } else {
                        if (actions[offset].isRequireSuccess) {
                            revert ICrystal.ActionFailed();
                        }
                    }
                } else if (action == 2 || action == 3) {
                    // Limit buy order: requires price, size; optional cloid
                    (cloid, param2) = _limitOrder((action & 1) == 0, balanceMode == 0, param1, param2, userId, cloid);
                    if (cloid != 0) {
                        ((action & 1) == 0) ? quoteAssetDebt += int256(cloid) : baseAssetDebt += int256(cloid);
                        _addToOrdersUpdatedEvent((((action & 1) == 0) ? LEADING_HEX_2 : LEADING_HEX_3) | (param1 << 168) | (param2 << 112) | cloid); // Encoded: 8-bit flag | 80-bit price | 56-bit id | 112-bit size
                    } else {
                        if (actions[offset].isRequireSuccess) {
                            revert ICrystal.ActionFailed();
                        }
                    }
                } else if (action > 3 && action < 12) {
                    // Action codes: 4=MTL buy, 5=MTL sell, 6=partial buy, 7=partial sell, 8=partial buy (gas-aware), 9=partial sell (gas-aware), 10=complete buy, 11=complete sell
                    uint256 settlementDelta;
                    settlementDelta = (uint160(referrer) << 80) | param1; // Avoid stack too deep
                    param1 = (uint256((action < 6) ? 2 : (action < 8) ? 0 : (action < 10) ? 3 : 1) << 252) | ((action & 1 != 0) ? (1 << 244) : 0); // Encode order type and direction flags
                    (, param1, , settlementDelta) = _marketOrder(param2, settlementDelta, param1 | (1 << 240) | (balanceMode << 236) | (cloid << 208) | (userId << 160) | uint160(user));
                    if (action & 1 != 0) {
                        baseAssetDebt += int256(settlementDelta >> 128);
                        quoteAssetDebt -= int256(param1 + (settlementDelta & MASK_KEEP_0_128)); // Safe: value bounded by uint128 intrinsic limit
                    } else {
                        quoteAssetDebt += int256(settlementDelta >> 128);
                        baseAssetDebt -= int256(param1 + (settlementDelta & MASK_KEEP_0_128)); // Safe: value bounded by uint128 intrinsic limit
                    }
                } else if (action == 12) {
                    // Decrease order: use cloid if price provided, otherwise use id
                    bool isCloid;
                    if (param1 != 0) {
                        // Price provided: use native order ID
                        cloid = actions[offset].param3;
                        cloid &= MASK_KEEP_0_41; // Mask to uint41 order ID
                    } else {
                        isCloid = true;
                    }
                    (param1, param2, isBuy) = _decreaseOrder(param1, cloid, param2, userId);
                    if (isCloid) {
                        cloid = (cloid << 41) | userId; // Encode cloid with userId for event emission
                    }
                    if (param2 != 0) {
                        if ((param2 >> 128) == 0) {
                            isBuy ? quoteAssetDebt -= int256(param2) : baseAssetDebt -= int256(param2);
                            _addToOrdersUpdatedEvent((isBuy ? 0 : LEADING_HEX_1) | (param1 << 168) | (cloid << 112) | param2); // Encoded: 8-bit flag | 80-bit price | 56-bit id | 112-bit cancelled size
                        } else {
                            isBuy ? quoteAssetDebt -= int256(param2 >> 128) : baseAssetDebt -= int256(param2 >> 128);
                            _addToOrdersUpdatedEvent((LEADING_HEX_4 + (isBuy ? 0 : LEADING_HEX_1)) | (param1 << 168) | (cloid << 112) | (param2 >> 128)); // Encoded: 8-bit flag | 80-bit price | 56-bit id | 112-bit decreased amount
                        }
                    } else {
                        if (actions[offset].isRequireSuccess) {
                            revert ICrystal.ActionFailed();
                        }
                    }
                }
                ++offset;
            }
            param1 = options; // Avoid stack too deep
            param2 = options; // Avoid stack too deep
            _settleBalances(quoteAssetDebt, baseAssetDebt, userId, balanceMode, ((param1 >> 44) & 1), ((param2 >> 48) & 1));
            address _market = market;
            assembly {
                let length := mload(0xc0)
                if gt(length, 0) {
                    mstore(0xa0, 0x20)
                    log3(0xa0, add(length, 0x40), ORDERS_UPDATED_SIG, _market, user)
                }
            }
        }
    }

    /**
     * @notice Processes tightly packed batch actions supplied via calldata.
     *
     * @dev The first 32-byte word carries the userId and action count; subsequent words consist of 32-byte actions.
     * @dev userId is prevalidated.
     */
    fallback() external payable {
        unchecked {
            uint256 userId;
            uint256 offset;
            uint256 action;
            uint256 param1;
            uint256 param2;
            uint256 cloid;
            bool isBuy;
            uint256 balanceMode;
            int256 quoteAssetDebt;
            int256 baseAssetDebt;
            assembly {
                mstore(0x40, 0xe0)
                userId := calldataload(offset)
                balanceMode := shr(44, userId)
                userId := and(MASK_KEEP_0_41, userId) // Extract uint41 userId from uint44 encoding
            }
            offset += 32;
            while (offset < msg.data.length) {
                assembly {
                    // Bits 4-8 encode isRequireSuccess flag
                    action := calldataload(offset)
                    param1 := and(MASK_KEEP_0_80, shr(112, action)) // Extract bits 64-144
                    param2 := and(MASK_KEEP_0_112, action) // Extract bits 144-256
                    cloid := and(MASK_KEEP_0_10, shr(192, action)) // Extract cloid from bits 20-64
                    action := shr(252, action) // Extract action code from bits 0-4
                }
                if (action == 1) {
                    // Cancel order: accepts price+id or cloid
                    if (cloid != 0) {
                        (param1, action, isBuy) = _cancelOrder(0, cloid, userId);
                        param2 = (cloid << 41) | userId; // Encode cloid with userId for event emission
                    } else {
                        (param1, action, isBuy) = _cancelOrder(param1, param2, userId);
                    }
                    if (action != 0) {
                        isBuy ? quoteAssetDebt -= int256(action) : baseAssetDebt -= int256(action);
                        _addToOrdersUpdatedEvent((isBuy ? 0 : LEADING_HEX_1) | (param1 << 168) | (param2 << 112) | action); // Encoded: 8-bit flag | 80-bit price | 56-bit id | 112-bit cancelled size
                    } else {
                        assembly {
                            // Reuse isBuy variable for isRequireSuccess flag
                            isBuy := and(0x1, shr(248, calldataload(offset))) // Extract bit 4-8
                        }
                        if (isBuy) {
                            revert ICrystal.ActionFailed();
                        }
                    }
                } else if (action == 2 || action == 3) {
                    // Limit buy order: requires price, size; optional cloid
                    (cloid, param2) = _limitOrder((action & 1) == 0, balanceMode == 0, param1, param2, userId, cloid);
                    if (cloid != 0) {
                        ((action & 1) == 0) ? quoteAssetDebt += int256(cloid) : baseAssetDebt += int256(cloid);
                        _addToOrdersUpdatedEvent((((action & 1) == 0) ? LEADING_HEX_2 : LEADING_HEX_3) | (param1 << 168) | (param2 << 112) | cloid); // Encoded: 8-bit flag | 80-bit price | 56-bit id | 112-bit size
                    } else {
                        assembly {
                            // Reuse isBuy variable for isRequireSuccess flag
                            isBuy := and(0x1, shr(248, calldataload(offset))) // Extract bit 4-8
                        }
                        if (isBuy) {
                            revert ICrystal.ActionFailed();
                        }
                    }
                } else if (action > 3 && action < 12) {
                    // Action codes: 4=MTL buy, 5=MTL sell, 6=partial buy, 7=partial sell, 8=partial buy (gas-aware), 9=partial sell (gas-aware), 10=complete buy, 11=complete sell
                    uint256 settlementDelta;
                    settlementDelta = (uint160(msg.sender) << 80) | param1; // Avoid stack too deep
                    param1 = (uint256((action < 6) ? 2 : (action < 8) ? 0 : (action < 10) ? 3 : 1) << 252) | (((action & 1) != 0) ? (1 << 244) : 0); // Avoid stack too deep
                    (, param1, , settlementDelta) = _marketOrder(param2, settlementDelta, param1 | (1 << 240) | (balanceMode << 236) | (cloid << 208) | (userId << 160) | uint160(msg.sender));
                    if (action & 1 != 0) {
                        // Sell order settlement
                        baseAssetDebt += int256(settlementDelta >> 128);
                        quoteAssetDebt -= int256(param1 + (settlementDelta & MASK_KEEP_0_128)); // Safe: value bounded by uint128 intrinsic limit
                    } else {
                        // Buy order settlement
                        quoteAssetDebt += int256(settlementDelta >> 128);
                        baseAssetDebt -= int256(param1 + (settlementDelta & MASK_KEEP_0_128)); // Safe: value bounded by uint128 intrinsic limit
                    }
                } else if (action == 12) {
                    // Decrease order: use cloid if price provided, otherwise use id
                    bool isCloid;
                    if (param1 != 0) {
                        // Price provided: use native order ID
                        assembly {
                            cloid := and(MASK_KEEP_0_41, shr(192, calldataload(offset))) // Extract uint41 order ID from bits 16-64
                        }
                    } else {
                        isCloid = true;
                    }
                    (param1, param2, isBuy) = _decreaseOrder(param1, cloid, param2, userId);
                    if (isCloid) {
                        cloid = (cloid << 41) | userId; // Encode cloid with userId for event emission
                    }
                    if (param2 != 0) {
                        if ((param2 >> 128) == 0) {
                            isBuy ? quoteAssetDebt -= int256(param2) : baseAssetDebt -= int256(param2);
                            _addToOrdersUpdatedEvent((isBuy ? 0 : LEADING_HEX_1) | (param1 << 168) | (cloid << 112) | param2); // Encoded: 8-bit flag | 80-bit price | 56-bit id | 112-bit cancelled size
                        } else {
                            isBuy ? quoteAssetDebt -= int256(param2 >> 128) : baseAssetDebt -= int256(param2 >> 128);
                            _addToOrdersUpdatedEvent((LEADING_HEX_4 + (isBuy ? 0 : LEADING_HEX_1)) | (param1 << 168) | (cloid << 112) | (param2 >> 128)); // Encoded: 8-bit flag | 80-bit price | 56-bit id | 112-bit decreased amount
                        }
                    } else {
                        assembly {
                            // Reuse isBuy variable for isRequireSuccess flag
                            isBuy := and(0x1, shr(248, calldataload(offset))) // Extract bit 4-8
                        }
                        if (isBuy) {
                            revert ICrystal.ActionFailed();
                        }
                    }
                }
                offset += 32;
            }
            _settleBalances(quoteAssetDebt, baseAssetDebt, userId, balanceMode, 0, 0);
            address _market = market;
            assembly {
                let length := mload(0xc0)
                if gt(length, 0) {
                    mstore(0xa0, 0x20)
                    log3(0xa0, add(length, 0x40), ORDERS_UPDATED_SIG, _market, caller())
                }
            }
        }
    }

    /**
     * @notice Accepts native token transfers.
     */
    receive() external payable {}
}
