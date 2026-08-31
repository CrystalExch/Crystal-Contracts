// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "../interfaces/IERC20.sol";
import {ICrystal} from "../interfaces/ICrystal.sol";
import {ERC20} from "../libraries/ERC20.sol";
import {CrystalMath as CM} from "../libraries/CrystalMath.sol";
import {CrystalStorage as CS} from "../libraries/CrystalStorage.sol";

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
    address internal feeRecipient;

    /// @notice Percentage of fees that go to referrals.
    uint8 internal feeCommission;

    /**
     * @notice Mapping from user id to address.
     *
     * @dev User id zero is invalid.
     */
    mapping(uint256 => address) internal userIdToAddress;

    /// @notice Links each address to their user ID.
    mapping(address => uint256) internal addressToUserId;

    /// @notice Stores all market configurations, indexed by market address.
    mapping(address => ICrystal.Market) internal _getMarket;

    /**
     * @notice The protocols's internal token balances.
     *
     * @dev Keyed by userId and token address.
     */
    mapping(uint256 => mapping(address => uint256)) internal tokenBalances;

    /**
     * @notice Claimable fee balances per token and user.
     *
     * @dev token => user => amount.
     */
    mapping(address => mapping(address => uint256)) internal claimableRewards;

    /// @notice The quote token for this market (e.g., USDC in a BTC/USDC pair).
    address public immutable quoteAsset;

    /// @notice The base token for this market (e.g., BTC in a BTC/USDC pair).
    address public immutable baseAsset;

    /// @notice Address of the main Crystal contract.
    address public immutable crystal;

    /// @notice What type of market this is.
    uint256 public immutable marketType;

    /// @notice Scaling factor used for price calculations.
    uint256 public immutable scaleFactor;

    /// @notice Minimum price increment allowed for this market.
    uint256 public immutable tickSize;

    /// @notice Highest price this market supports.
    uint256 public immutable maxPrice;

    /// @notice Address of market.
    address internal immutable market;

    /**
     * @notice Market id, max uint48.
     *
     * @dev Already shifted 128 bits left, market id zero is invalid.
     */
    uint256 internal immutable marketId;

    /// @notice Fill event signature.
    uint256 internal constant FILL_SIG = 0xa195980963150be5fcca4acd6a80bf5a9de7f9c862258501b7c705e7d2c2d2f4;

    /// @notice Order update event signature.
    uint256 internal constant ORDERS_UPDATED_SIG = 0x7ebb55d14fb18179d0ee498ab0f21c070fad7368e44487d51cdac53d6f74812c;

    uint256 internal constant MASK_OUT_113_154 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFC0000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 internal constant MASK_OUT_0_128 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000000000000000000000000000;
    uint256 internal constant MASK_OUT_205_256 = 0x0000000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 internal constant MASK_OUT_113_205 = 0xFFFFFFFFFFFFE00000000000000000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 internal constant MASK_OUT_154_205 = 0xFFFFFFFFFFFFE0000000000003FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 internal constant MASK_OUT_0_41 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE0000000000;
    uint256 internal constant MASK_OUT_255_256 = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 internal constant MASK_KEEP_255_256 = 0x8000000000000000000000000000000000000000000000000000000000000000;
    uint256 internal constant MASK_KEEP_112_113 = 0x0000000000000000000000000000000000010000000000000000000000000000;
    uint256 internal constant MASK_KEEP_0_10 = 0x3FF;
    uint256 internal constant MASK_KEEP_0_20 = 0xFFFFF;
    uint256 internal constant MASK_KEEP_0_41 = 0x1FFFFFFFFFF;
    uint256 internal constant MASK_KEEP_0_48 = 0xFFFFFFFFFFFF;
    uint256 internal constant MASK_KEEP_0_51 = 0x7FFFFFFFFFFFF;
    uint256 internal constant MASK_KEEP_0_80 = 0xFFFFFFFFFFFFFFFFFFFF;
    uint256 internal constant MASK_KEEP_0_96 = 0xFFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 internal constant MASK_KEEP_0_112 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 internal constant MASK_KEEP_0_128 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 internal constant LEADING_HEX_1 = 0x1000000000000000000000000000000000000000000000000000000000000000;
    uint256 internal constant LEADING_HEX_2 = 0x2000000000000000000000000000000000000000000000000000000000000000;
    uint256 internal constant LEADING_HEX_3 = 0x3000000000000000000000000000000000000000000000000000000000000000;
    uint256 internal constant LEADING_HEX_4 = 0x4000000000000000000000000000000000000000000000000000000000000000;

    /**
     * @notice Sets up this market with configuration from the main Crystal contract.
     *
     * @dev Gets called during deployment to grab all the market parameters and set up the permit domain separator.
     */
    constructor() ERC20("Crystal V2", "CRY-V2") {
        (quoteAsset, baseAsset, marketId, marketType, scaleFactor, tickSize, maxPrice) = ICrystal(msg.sender).parameters();
        marketId <<= 128;
        scaleFactor = 10 ** scaleFactor;
        market = address(this);
        crystal = msg.sender;
        require(quoteAsset != address(0) && baseAsset != address(0) && quoteAsset != baseAsset && maxPrice <= MASK_KEEP_0_80 && tickSize <= MASK_KEEP_0_80 && scaleFactor <= MASK_KEEP_0_112, ICrystal.InvalidParams());
    }

    /**
     * @notice Creates new LP tokens and sends them to someone.
     *
     * @dev Can only be called by the main Crystal contract.
     *
     * @param to Who gets the newly minted tokens.
     * @param value How many tokens to create.
     */
    function mint(address to, uint256 value) external {
        require(msg.sender == crystal, ICrystal.Unauthorized(msg.sender));
        _mint(to, value);
    }

    /**
     * @notice Destroys LP tokens from someone's balance.
     *
     * @dev Can only be called by the main Crystal contract.
     *
     * @param from Whose tokens we're burning.
     * @param value How many tokens to destroy.
     */
    function burn(address from, uint256 value) external {
        require(msg.sender == crystal, ICrystal.Unauthorized(msg.sender));
        _burn(from, value);
    }

    /**
     * @notice Moves LP tokens on someone else's behalf (requires prior approval).
     *
     * @dev If you have infinite allowance or you're the Crystal contract itself, we skip the allowance check.
     *
     * @param from Who's sending the tokens.
     * @param to Who's receiving the tokens.
     * @param value How many tokens to move.
     *
     * @return success Always returns true.
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
     * @notice Adds encoded order update data to the OrdersUpdated event buffer in memory.
     *
     * @param logData The encoded order update information to append.
     */
    function _addToOrdersUpdatedEvent(uint256 logData) internal pure {
        assembly {
            let length := mload(0xe0)
            mstore(add(length, 0x100), logData)
            mstore(0xe0, add(length, 0x20))
            mstore(0x40, add(length, 0x120))
        }
    }

    /**
     * @notice Checks whether the current resting liquidity can satisfy the remaining taker amount.
     *
     * @param isBuy Whether the taker order is buying the base asset.
     * @param isExactInput Whether `sizeLeft` is denominated in taker input units.
     * @param makerRebate Maker rebate factor used to convert exact-input remainder into output units.
     * @param price Current execution price.
     * @param sizeLeft Remaining taker amount still to execute.
     * @param liquidity Resting liquidity available at the current price level.
     *
     * @return True if the resting liquidity is sufficient to satisfy the remaining taker amount.
     */
    function _canFillRemaining(bool isBuy, bool isExactInput, uint256 makerRebate, uint256 price, uint256 sizeLeft, uint256 liquidity) internal view returns (bool) {
        unchecked {
            if (isExactInput) {
                uint256 adjustedSize = (sizeLeft * makerRebate) / 100000;
                if (isBuy) {
                    return liquidity > (adjustedSize * scaleFactor) / price;
                } else {
                    return liquidity > (adjustedSize * price) / scaleFactor;
                }
            } else {
                return liquidity > sizeLeft;
            }
        }
    }

    /**
     * @notice Handles the actual token transfers for settling trades - either moves real tokens or updates internal balances.
     *
     * @dev The balance mode flags control whether we do external token transfers or just update internal accounting. 0 = external, 1 = internal.
     *
     * @param quoteAssetDebt How much quote asset is owed (positive means you owe, negative means you receive).
     * @param baseAssetDebt How much base asset is owed (positive means you owe, negative means you receive).
     * @param userId Your user ID for internal accounting.
     * @param balanceMode 0 to use external transfers, 1 to use internal balances.
     * @param balanceModeOut 0 to send outputs as real tokens, 1 to credit the router's internal balance.
     * @param balanceModeIn 0 to pull from your wallet, 1 to pull from router's internal balance.
     */
    function _settleBalances(int256 quoteAssetDebt, int256 baseAssetDebt, uint256 userId, uint256 balanceMode, uint256 balanceModeOut, uint256 balanceModeIn) internal {
        unchecked {
            if (balanceMode == 0) { // Settlement via external token transfers
                if (balanceModeIn != 0) {
                    if (quoteAssetDebt > 0) {
                        uint256 balance = tokenBalances[0][quoteAsset];
                        require(uint128(balance) >= uint256(quoteAssetDebt), ICrystal.ActionFailed());
                        tokenBalances[0][quoteAsset] = balance - uint256(quoteAssetDebt);
                    }
                    if (baseAssetDebt > 0) {
                        uint256 balance = tokenBalances[0][baseAsset];
                        require(uint128(balance) >= uint256(baseAssetDebt), ICrystal.ActionFailed());
                        tokenBalances[0][baseAsset] = balance - uint256(baseAssetDebt);
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
                        require(((tokenBalances[0][quoteAsset] & MASK_KEEP_0_128) + uint256(-quoteAssetDebt)) <= MASK_KEEP_0_128, ICrystal.Overflow());
                        tokenBalances[0][quoteAsset] += uint256(-quoteAssetDebt);
                    }
                    if (baseAssetDebt < 0) {
                        require(((tokenBalances[0][baseAsset] & MASK_KEEP_0_128) + uint256(-baseAssetDebt)) <= MASK_KEEP_0_128, ICrystal.Overflow());
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
                require(balanceMode == 1, ICrystal.ActionFailed());
                if (quoteAssetDebt > 0) {
                    uint256 balance = tokenBalances[userId][quoteAsset];
                    require(uint128(balance) >= uint256(quoteAssetDebt), ICrystal.ActionFailed());
                    tokenBalances[userId][quoteAsset] = balance - uint256(quoteAssetDebt);
                } else if (quoteAssetDebt < 0) {
                    require(((tokenBalances[userId][quoteAsset] & MASK_KEEP_0_128) + uint256(-quoteAssetDebt)) <= MASK_KEEP_0_128, ICrystal.Overflow());
                    tokenBalances[userId][quoteAsset] += uint256(-quoteAssetDebt);
                }
                if (baseAssetDebt > 0) {
                    uint256 balance = tokenBalances[userId][baseAsset];
                    require(uint128(balance) >= uint256(baseAssetDebt), ICrystal.ActionFailed());
                    tokenBalances[userId][baseAsset] = balance - uint256(baseAssetDebt);
                } else if (baseAssetDebt < 0) {
                    require(((tokenBalances[userId][baseAsset] & MASK_KEEP_0_128) + uint256(-baseAssetDebt)) <= MASK_KEEP_0_128, ICrystal.Overflow());
                    tokenBalances[userId][baseAsset] += uint256(-baseAssetDebt);
                }
            }
        }
    }

    /**
     * @notice Activates a price level in the orderbook and updates its fillNext pointer.
     *
     * @dev Assumes price is tick-aligned and market state is valid.
     *
     * @param price Order price.
     * @param priceLevel Packed price level data.
     * @param fillNext Order identifier or cloid pointer to set as fillNext.
     *
     * @return Updated packed price level.
     */
    function _activatePriceLevel(uint256 price, uint256 priceLevel, uint256 fillNext) internal returns (uint256) {
        unchecked {
            require(price % tickSize == 0, ICrystal.InvalidParams());
            uint256 tick = marketType == 0 ? (price / tickSize) : CM._priceToTick(price, tickSize);
            (uint256 key, uint256 offset) = CS._getActivated(marketId, tick / 255);
            uint256 slot = CS._readMapping(key, offset, CS.PRICELEVELS_KEY) & MASK_OUT_255_256;
            CS._writeMapping(key, offset, CS.PRICELEVELS_KEY, slot | (1 << (tick % 255)) | MASK_KEEP_255_256);
            if (slot == 0) {
                (key, offset) = CS._getGroups(marketId, (tick / 255) / 255);
                uint256 groupsSlot = CS._readMapping(key, offset, CS.GROUPS_KEY);
                CS._writeMapping(key, offset, CS.GROUPS_KEY, groupsSlot | (1 << ((tick / 255) % 255)) | MASK_KEEP_255_256);
            }
            return (fillNext << 205) | (priceLevel & MASK_OUT_205_256); // Update priceLevel's fillNext pointer to order id
        }
    }

    /**
     * @notice Finds the next active tick at or above the current search position.
     *
     * @dev isWrite is true when invoked through _marketOrder as slot is potentially persisted across multiple calls
     * cachedGroupsSlot is the groups slot passed as a parameter when invoked through getQuote as the groups slot is
     * never written to between calls.
     *
     * @param isWrite Whether the current first-level bitmap word should be persisted before advancing.
     * @param tick Current tick search position.
     * @param slot Cached first-level bitmap word for `slotIndex`.
     * @param slotIndex Index of the current first-level bitmap word.
     * @param cachedGroupsSlot Cached groups bitmap word for the current group index.
     *
     * @return nextTick Next active tick found during the upward search.
     * @return nextSlot Updated first-level bitmap word containing `nextTick`.
     * @return nextSlotIndex Updated first-level bitmap index containing `nextTick`.
     * @return nextCachedGroupsSlot Updated cached groups bitmap word.
     */
    function _searchUp(bool isWrite, uint256 tick, uint256 slot, uint256 slotIndex, uint256 cachedGroupsSlot) internal returns (uint256, uint256, uint256, uint256) {
        unchecked {
            uint256 _slot = slot >> tick % 255;
            (uint256 key, uint256 offset) = CS._getActivated(marketId, slotIndex);
            if (isWrite && _slot == 0 && ((CS._readMapping(key, offset, CS.PRICELEVELS_KEY) & MASK_OUT_255_256) != slot)) {
                CS._writeMapping(key, offset, CS.PRICELEVELS_KEY, slot | MASK_KEEP_255_256);
            }
            if (_slot == 0) {
                uint256 groupsIndex = slotIndex / 255;
                uint256 groupsSlot;
                if (cachedGroupsSlot != 0) {
                    cachedGroupsSlot &= ~(1 << ((slotIndex) % 255));
                    groupsSlot = cachedGroupsSlot >> slotIndex % 255;
                } else {
                    (key, offset) = CS._getGroups(marketId, groupsIndex);
                    groupsSlot = (CS._readMapping(key, offset, CS.GROUPS_KEY) & MASK_OUT_255_256) >> ((slotIndex % 255) + 1) << 1;
                }
                while (groupsSlot == 0) {
                    ++groupsIndex;
                    (key, offset) = CS._getGroups(marketId, groupsIndex);
                    groupsSlot = CS._readMapping(key, offset, CS.GROUPS_KEY) & MASK_OUT_255_256;
                    cachedGroupsSlot = groupsSlot;
                    slotIndex = groupsIndex * 255;
                }
                slotIndex = CM._searchSlotUp(groupsSlot, slotIndex);
                (key, offset) = CS._getActivated(marketId, slotIndex);
                slot = CS._readMapping(key, offset, CS.PRICELEVELS_KEY) & MASK_OUT_255_256;
                _slot = slot;
                tick = slotIndex * 255;
            }
            tick = CM._searchSlotUp(_slot, tick);
            return (tick, slot, slotIndex, cachedGroupsSlot);
        }
    }

    /**
     * @notice Finds the previous active tick strictly below the current search position.
     *
     * @dev isWrite is true when invoked through _marketOrder as slot is potentially persisted across multiple calls
     * cachedGroupsSlot is the groups slot passed as a parameter when invoked through getQuote as the groups slot is
     * never written to between calls.
     *
     * @param isWrite Whether the current first-level bitmap word should be persisted before retreating.
     * @param tick Current tick search position.
     * @param slot Cached first-level bitmap word for `slotIndex`.
     * @param slotIndex Index of the current first-level bitmap word.
     * @param cachedGroupsSlot Cached groups bitmap word for the current group index.
     *
     * @return prevTick Previous active tick found during the downward search.
     * @return prevSlot Updated first-level bitmap word containing `prevTick`.
     * @return prevSlotIndex Updated first-level bitmap index containing `prevTick`.
     * @return prevCachedGroupsSlot Updated cached groups bitmap word.
     */
    function _searchDown(bool isWrite, uint256 tick, uint256 slot, uint256 slotIndex, uint256 cachedGroupsSlot) internal returns (uint256, uint256, uint256, uint256) {
        unchecked {
            uint256 _slot = slot & ((1 << (tick % 255)) - 1);
            (uint256 key, uint256 offset) = CS._getActivated(marketId, slotIndex);
            if (isWrite && _slot == 0 && ((CS._readMapping(key, offset, CS.PRICELEVELS_KEY) & MASK_OUT_255_256) != slot)) {
                CS._writeMapping(key, offset, CS.PRICELEVELS_KEY, slot | MASK_KEEP_255_256);
            }
            if (_slot == 0) {
                uint256 groupsIndex = slotIndex / 255;
                uint256 groupsSlot;
                if (cachedGroupsSlot != 0) {
                    cachedGroupsSlot &= ~(1 << ((slotIndex) % 255));
                    groupsSlot = cachedGroupsSlot & ((1 << (slotIndex % 255)) - 1);
                } else {
                    (key, offset) = CS._getGroups(marketId, groupsIndex);
                    groupsSlot = (CS._readMapping(key, offset, CS.GROUPS_KEY) & MASK_OUT_255_256) & ((1 << (slotIndex % 255)) - 1);
                }
                while (groupsSlot == 0) {
                    --groupsIndex;
                    (key, offset) = CS._getGroups(marketId, groupsIndex);
                    groupsSlot = CS._readMapping(key, offset, CS.GROUPS_KEY) & MASK_OUT_255_256;
                    cachedGroupsSlot = groupsSlot;
                }
                slotIndex = CM._searchSlotDown(groupsSlot, groupsIndex * 255);
                (key, offset) = CS._getActivated(marketId, slotIndex);
                slot = CS._readMapping(key, offset, CS.PRICELEVELS_KEY) & MASK_OUT_255_256;
                _slot = slot;
            }
            tick = CM._searchSlotDown(_slot, slotIndex * 255);
            return (tick, slot, slotIndex, cachedGroupsSlot);
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
     * @param order Packed order data.
     */
    function _internalCancel(uint256 price, uint256 id, uint256 size, uint256 highestBid, uint256 lowestAsk, uint256 order) internal {
        unchecked {
            (uint256 key, uint256 offset) = CS._getPriceLevel(marketType, tickSize, marketId, price);
            uint256 priceLevel = CS._readMapping(key, offset, CS.PRICELEVELS_KEY);
            priceLevel -= size;
            if (id == ((priceLevel >> 205) & MASK_KEEP_0_51)) { // Order is at fillNext position; advance pointer to fillAfter
                priceLevel = (order & (MASK_KEEP_0_51 << 205)) | (priceLevel & MASK_OUT_205_256);
            } else if (id == ((priceLevel >> 154) & MASK_KEEP_0_51)) { // Order is at latest position; revert pointer to fillBefore
                uint256 fillBefore = ((order >> 154) & MASK_KEEP_0_51);
                if (fillBefore > MASK_KEEP_0_41) {
                    (key, offset) = CS._getCloidOrder(fillBefore & MASK_KEEP_0_41, fillBefore >> 41);
                } else {
                    (key, offset) = CS._getOrder(marketId, price, fillBefore);
                }
                priceLevel = (priceLevel & MASK_OUT_154_205) | (fillBefore << 154);
                fillBefore = (order & (MASK_KEEP_0_51 << 205)) | (CS._readMapping(key, offset, CS.ORDERS_KEY) & MASK_OUT_205_256);
                CS._writeMapping(key, offset, CS.ORDERS_KEY, fillBefore); // Update fillBefore order's fillAfter pointer
            } else {
                uint256 fillBefore = ((order >> 154) & MASK_KEEP_0_51);
                uint256 fillAfter = ((order >> 205) & MASK_KEEP_0_51);
                if (fillBefore > MASK_KEEP_0_41) {
                    (key, offset) = CS._getCloidOrder(fillBefore & MASK_KEEP_0_41, fillBefore >> 41);
                } else {
                    (key, offset) = CS._getOrder(marketId, price, fillBefore);
                }
                CS._writeMapping(key, offset, CS.ORDERS_KEY, (fillAfter << 205) | (CS._readMapping(key, offset, CS.ORDERS_KEY) & MASK_OUT_205_256)); // Link fillBefore to fillAfter, bypassing cancelled order
                if (fillAfter > MASK_KEEP_0_41) {
                    (key, offset) = CS._getCloidOrder(fillAfter & MASK_KEEP_0_41, fillAfter >> 41);
                } else {
                    (key, offset) = CS._getOrder(marketId, price, fillAfter);
                }
                CS._writeMapping(key, offset, CS.ORDERS_KEY, (fillBefore << 154) | (CS._readMapping(key, offset, CS.ORDERS_KEY) & MASK_OUT_154_205)); // Link fillAfter to fillBefore, bypassing cancelled order
            }
            (key, offset) = CS._getPriceLevel(marketType, tickSize, marketId, price);
            CS._writeMapping(key, offset, CS.PRICELEVELS_KEY, priceLevel);
            if ((priceLevel & MASK_KEEP_0_112) == 0) {
                uint256 tick = marketType == 0 ? (price / tickSize) : CM._priceToTick(price, tickSize);
                uint256 slotIndex = tick / 255;
                (key, offset) = CS._getActivated(marketId, slotIndex);
                uint256 slot = CS._readMapping(key, offset, CS.PRICELEVELS_KEY) & MASK_OUT_255_256;
                slot &= ~(1 << (tick % 255));
                CS._writeMapping(key, offset, CS.PRICELEVELS_KEY, slot | MASK_KEEP_255_256);
                if (slot == 0) {
                    (key, offset) = CS._getGroups(marketId, slotIndex / 255);
                    CS._writeMapping(key, offset, CS.GROUPS_KEY, CS._readMapping(key, offset, CS.GROUPS_KEY) & ~(1 << (slotIndex % 255)));
                }
                if (price == lowestAsk) {
                    (tick, slot, slotIndex, ) = _searchUp(false, tick, slot, slotIndex, 0);
                    _getMarket[market].lowestAsk = uint80(marketType == 0 ? (tick * tickSize) : CM._tickToPrice(tick, tickSize));
                } else if (price == highestBid) {
                    (tick, slot, slotIndex, ) = _searchDown(false, tick, slot, slotIndex, 0);
                    _getMarket[market].highestBid = uint80(marketType == 0 ? (tick * tickSize) : CM._tickToPrice(tick, tickSize));
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
            if (startPrice >= _maxPrice || startPrice == 0) {
                return;
            }
            uint256 tick = marketType == 0 ? (startPrice / tickSize) : CM._priceToTick(startPrice, tickSize);
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
            uint256 groupsIndex = slotIndex / 255;
            uint256 slot;
            uint256 groupsSlot;
            {
                (uint256 key, uint256 offset) = CS._getActivated(marketId, slotIndex);
                slot = CS._readMapping(key, offset, CS.PRICELEVELS_KEY) & MASK_OUT_255_256;
                (key, offset) = CS._getGroups(marketId, groupsIndex);
                groupsSlot = CS._readMapping(key, offset, CS.GROUPS_KEY) & MASK_OUT_255_256;
            }
            assembly {
                position := mload(0x40)
                mstore(position, 0x0)
            }
            if (isAscending) { // Traverse ask-side price levels in ascending order
                if (startPrice + (distance) > (marketType == 0 ? (_maxPrice / tickSize) : CM._priceToTick(_maxPrice, tickSize))) {
                    distance = ((marketType == 0 ? (_maxPrice / tickSize) : CM._priceToTick(_maxPrice, tickSize)) - startPrice);
                }
                while (true) {
                    {
                        uint256 _slot = slot >> tick % 255;
                        if (_slot == 0) {
                            uint256 _groupsSlot = groupsSlot >> ((slotIndex % 255) + 1) << 1;
                            while (_groupsSlot == 0) {
                                ++groupsIndex;
                                (uint256 key, uint256 offset) = CS._getGroups(marketId, groupsIndex);
                                groupsSlot = CS._readMapping(key, offset, CS.GROUPS_KEY) & MASK_OUT_255_256;
                                _groupsSlot = groupsSlot;
                                slotIndex = groupsIndex * 255;
                            }
                            slotIndex = CM._searchSlotUp(_groupsSlot, slotIndex);
                            (uint256 key, uint256 offset) = CS._getActivated(marketId, slotIndex);
                            slot = CS._readMapping(key, offset, CS.PRICELEVELS_KEY) & MASK_OUT_255_256;
                            _slot = slot;
                            tick = slotIndex * 255;
                        }
                        tick = CM._searchSlotUp(_slot, tick);
                        slot &= ~(1 << (tick % 255));
                        if (slot >> tick % 255 == 0) {
                            groupsSlot &= ~(1 << (slotIndex % 255));
                        }
                    }
                    price = marketType == 0 ? (tick * tickSize) : CM._tickToPrice(tick, tickSize);
                    if (max == 0 || (tick >= startPrice + distance)) {
                        break;
                    }
                    if ((((price + interval - 1) / interval) * interval) == bucket) {
                        (uint256 key, uint256 offset) = CS._getPriceLevel(marketType, tickSize, marketId, price);
                        uint256 priceLevel = CS._readMapping(key, offset, CS.PRICELEVELS_KEY);
                        assembly {
                            let length := mload(position)
                            let existing := mload(add(length, position))
                            mstore(add(length, position), add(existing, and(priceLevel, MASK_KEEP_0_112)))
                        }
                    } else {
                        --max;
                        bucket = ((price + interval - 1) / interval) * interval; // Round up for ask-side aggregation
                        (uint256 key, uint256 offset) = CS._getPriceLevel(marketType, tickSize, marketId, price);
                        uint256 priceLevel = CS._readMapping(key, offset, CS.PRICELEVELS_KEY);
                        assembly {
                            let length := mload(position)
                            mstore(add(length, add(position, 0x20)), or(shl(128, bucket), and(priceLevel, MASK_KEEP_0_112)))
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
                        uint256 _groupsSlot = groupsSlot & ((1 << (slotIndex % 255)) - 1);
                        while (_groupsSlot == 0) {
                            --groupsIndex;
                            (uint256 key, uint256 offset) = CS._getGroups(marketId, groupsIndex);
                            groupsSlot = CS._readMapping(key, offset, CS.GROUPS_KEY) & MASK_OUT_255_256;
                            _groupsSlot = groupsSlot;
                        }
                        slotIndex = CM._searchSlotDown(_groupsSlot, groupsIndex * 255);
                        (uint256 key, uint256 offset) = CS._getActivated(marketId, slotIndex);
                        slot = CS._readMapping(key, offset, CS.PRICELEVELS_KEY) & MASK_OUT_255_256;
                        _slot = slot;
                    }
                    tick = CM._searchSlotDown(_slot, slotIndex * 255);
                    slot &= ~(1 << (tick % 255));
                    if (slot & ((1 << (tick % 255)) - 1) == 0) {
                        groupsSlot &= ~(1 << (slotIndex % 255));
                    }
                    price = marketType == 0 ? (tick * tickSize) : CM._tickToPrice(tick, tickSize);
                    if (max == 0 || (tick <= startPrice - distance)) {
                        break;
                    }
                    if (((price / interval) * interval) == bucket) {
                        (uint256 key, uint256 offset) = CS._getPriceLevel(marketType, tickSize, marketId, price);
                        uint256 priceLevel = CS._readMapping(key, offset, CS.PRICELEVELS_KEY);
                        assembly {
                            let length := mload(position)
                            let existing := mload(add(length, position))
                            mstore(add(length, position), add(existing, and(priceLevel, MASK_KEEP_0_112)))
                        }
                    } else {
                        --max;
                        bucket = (price / interval) * interval; // Round down for bid-side aggregation
                        (uint256 key, uint256 offset) = CS._getPriceLevel(marketType, tickSize, marketId, price);
                        uint256 priceLevel = CS._readMapping(key, offset, CS.PRICELEVELS_KEY);
                        assembly {
                            let length := mload(position)
                            mstore(add(length, add(position, 0x20)), or(shl(128, bucket), and(priceLevel, MASK_KEEP_0_112)))
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
        unchecked {
            ICrystal.Market storage m = _getMarket[market];
            uint256 count;
            (highestBid, lowestAsk) = (m.highestBid, m.lowestAsk);
            (uint256 reserveQuote, uint256 reserveBase) = m.isAMMEnabled ? (m.reserveQuote, m.reserveBase) : (0, 0);
            if (reserveQuote != 0) {
                uint256 ammPrice = ((reserveQuote * scaleFactor * 9975 * 100000) / (reserveBase * 10000 * uint256(m.makerRebate)));
                ammPrice = marketType == 0 ? ((ammPrice + tickSize - 1) / tickSize) * tickSize : CM._toValidPrice(ammPrice, tickSize, true); // Compute adjusted AMM bid price
                if (highestBid < ammPrice) {
                    highestBid = ammPrice;
                }
                ammPrice = ((reserveQuote * scaleFactor * 10000 * uint256(m.makerRebate) + (reserveBase * 9975 * 100000 - 1)) / (reserveBase * 9975 * 100000));
                ammPrice = marketType == 0 ? (ammPrice - (ammPrice % tickSize)) : CM._toValidPrice(ammPrice, tickSize, false); // Compute adjusted AMM ask price
                if (lowestAsk > ammPrice) {
                    lowestAsk = ammPrice;
                }
            }
            price = highestBid;
            if (lowestAsk != maxPrice) { // Return highest bid when no asks exist instead of computing midpoint
                price += lowestAsk;
                ++count;
            }
            if (highestBid != 0) { // Return lowest ask when no bids exist instead of computing midpoint
                ++count;
            }
            if (count == 2) {
                uint256 mid = (price + 1) >> 1;
                price = marketType == 0 ? (mid - (mid % tickSize)) : CM._toValidPrice(mid, tickSize, false);
            }
        }
    }

    /**
     * @notice Quotes a trade against the orderbook and AMM without modifying state.
     *
     * @dev Called as a view function, but delegatecalled sometimes with value so is payable
     * Due to shortcuts in how quotes are calculated (by price level rather than individual order),
     * the quote produced by this function is not directly equivalent to the actual trade result.
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
                    assembly {
                        mstore(0x60, size)
                    }
                    size = (size * uint256(m.takerFee) + 99999) / 100000;
                }
                if (worstPrice >= maxPrice || worstPrice == 0) {
                    worstPrice = (marketType == 0 ? maxPrice - tickSize : CM._tickToPrice(CM._priceToTick(maxPrice, tickSize) - 1, tickSize));
                }
                price = m.lowestAsk;
            } else {
                if (!isExactInput) {
                    size = (size * 100000 + uint256(m.takerFee) - 1) / uint256(m.takerFee);
                }
                if (worstPrice == 0) {
                    worstPrice = (marketType == 0 ? tickSize : CM._tickToPrice(1, tickSize));
                }
                price = m.highestBid;
            }
            (uint256 reserveQuote, uint256 reserveBase) = m.isAMMEnabled ? (m.reserveQuote, m.reserveBase) : (0, 0);
            uint256 tick = marketType == 0 ? (price / tickSize) : CM._priceToTick(price, tickSize);
            uint256 slot;
            uint256 groupsSlot;
            {
                (uint256 key, uint256 offset) = CS._getActivated(marketId, tick / 255);
                slot = CS._readMapping(key, offset, CS.PRICELEVELS_KEY) & MASK_OUT_255_256;
                (key, offset) = CS._getGroups(marketId, (tick / 255) / 255);
                groupsSlot = CS._readMapping(key, offset, CS.GROUPS_KEY) & MASK_OUT_255_256;
            }
            while (isExactInput ? size > amountIn : size > amountOut) {
                uint256 sizeLeft = isExactInput ? (size - amountIn) : (size - amountOut);
                bool _isBuy = isBuy;
                bool _isExactInput = isExactInput;
                if (reserveQuote != 0) {
                    uint256 ammPriceLimit = (_isBuy ? (price > worstPrice) : (price < worstPrice)) ? worstPrice : price;
                    uint256 ammAmountIn;
                    uint256 ammAmountOut;
                    {
                        uint256 adjustedAMMPrice;
                        if (_isBuy) {
                            adjustedAMMPrice = (reserveQuote * scaleFactor * 10000 * uint256(m.makerRebate) + (reserveBase * 9975 * 100000 - 1)) / (reserveBase * 9975 * 100000);
                        } else {
                            adjustedAMMPrice = (reserveQuote * scaleFactor * 9975 * 100000) / (reserveBase * 10000 * uint256(m.makerRebate));
                        }
                        if (_isBuy && ammPriceLimit > adjustedAMMPrice) {
                            if (_isExactInput) {
                                uint256 makerRebate = m.makerRebate;
                                ammAmountIn = CM._exactInputBuySolve(reserveQuote, reserveBase, ammPriceLimit, makerRebate, sizeLeft, scaleFactor); // Compute optimal input for AMM execution (AMM end price matches adjusted orderbook price)
                                ammAmountOut = (ammAmountIn * 9975 * reserveBase) / ((reserveQuote * 10000) + (ammAmountIn * 9975));
                            } else {
                                uint256 makerRebate = m.makerRebate;
                                ammAmountOut = CM._exactOutputBuySolve(reserveQuote, reserveBase, ammPriceLimit, makerRebate, sizeLeft, scaleFactor); // Compute optimal output for AMM execution (AMM end price matches adjusted orderbook price)
                                ammAmountIn = (ammAmountOut * reserveQuote * 10000) / ((reserveBase - ammAmountOut) * 9975) + 1;
                            }
                            reserveQuote += ammAmountIn;
                            reserveBase -= ammAmountOut;
                        } else if (!_isBuy && ammPriceLimit < adjustedAMMPrice) {
                            if (_isExactInput) {
                                uint256 makerRebate = m.makerRebate;
                                ammAmountIn = CM._exactInputSellSolve(reserveQuote, reserveBase, ammPriceLimit, makerRebate, sizeLeft, scaleFactor); // Compute optimal input for AMM execution (AMM end price matches adjusted orderbook price)
                                ammAmountOut = ((ammAmountIn * 9975) * reserveQuote) / ((reserveBase * 10000) + (ammAmountIn * 9975));
                            } else {
                                uint256 makerRebate = m.makerRebate;
                                ammAmountOut = CM._exactOutputSellSolve(reserveQuote, reserveBase, ammPriceLimit, makerRebate, sizeLeft, scaleFactor); // Compute optimal output for AMM execution (AMM end price matches adjusted orderbook price)
                                ammAmountIn = (ammAmountOut * reserveBase * 10000) / ((reserveQuote - ammAmountOut) * 9975) + 1;
                            }
                            reserveBase += ammAmountIn;
                            reserveQuote -= ammAmountOut;
                        } else { // No AMM swap executed; skip subsequent AMM logic
                            ammAmountIn = 0;
                        }
                    }
                    if (ammAmountIn != 0) {
                        amountIn += ammAmountIn;
                        amountOut += ammAmountOut;
                        if (sizeLeft != (_isExactInput ? ammAmountIn : ammAmountOut)) {
                            sizeLeft -= (_isExactInput ? ammAmountIn : ammAmountOut);
                        } else {
                            break;
                        }
                    }
                }
                if (_isBuy ? price > worstPrice : price < worstPrice) {
                    require(!isCompleteFill, ICrystal.SlippageExceeded());
                    break;
                }
                (uint256 key, uint256 offset) = CS._getPriceLevel(marketType, tickSize, marketId, price);
                uint256 liquidity = CS._readMapping(key, offset, CS.PRICELEVELS_KEY) & MASK_KEEP_0_112;
                if (_canFillRemaining(_isBuy, _isExactInput, uint256(m.makerRebate), price, sizeLeft, liquidity)) {
                    if (_isExactInput) {
                        if (_isBuy) {
                            amountOut += (((sizeLeft * uint256(m.makerRebate)) / 100000) * scaleFactor) / price;
                        } else {
                            amountOut += (((sizeLeft * uint256(m.makerRebate)) / 100000) * price) / scaleFactor;
                        }
                    } else {
                        amountOut += sizeLeft;
                        if (_isBuy) {
                            sizeLeft = (sizeLeft * price * 100000 + (scaleFactor * uint256(m.makerRebate) - 1)) / (scaleFactor * uint256(m.makerRebate));
                        } else {
                            sizeLeft = (sizeLeft * scaleFactor * 100000 + (price * uint256(m.makerRebate) - 1)) / (price * uint256(m.makerRebate));
                        }    
                    }
                    amountIn += sizeLeft;
                    sizeLeft = 0;
                } else {
                    if (_isBuy) {
                        amountIn += (((liquidity * price) / scaleFactor) * 100000) / uint256(m.makerRebate);
                    } else {
                        amountIn += (((liquidity * scaleFactor) / price) * 100000) / uint256(m.makerRebate);
                    }
                    amountOut += _isBuy ? liquidity : liquidity;
                    if (_isExactInput) {
                        if (_isBuy) {
                            sizeLeft -= (((liquidity * price) / scaleFactor) * 100000) / uint256(m.makerRebate);
                        } else {
                            sizeLeft -= (((liquidity * scaleFactor) / price) * 100000) / uint256(m.makerRebate);
                        }
                    } else {
                        sizeLeft -= liquidity;
                    }
                    liquidity = 0;
                }
                if (liquidity == 0) {
                    uint256 slotIndex = tick / 255;
                    slot &= ~(1 << (tick % 255));
                    if (_isBuy) {
                        (tick, slot, slotIndex, groupsSlot) = _searchUp(false, tick, slot, slotIndex, groupsSlot);
                    } else {
                        (tick, slot, slotIndex, groupsSlot) = _searchDown(false, tick, slot, slotIndex, groupsSlot);
                    }
                    price = marketType == 0 ? (tick * tickSize) : CM._tickToPrice(tick, tickSize);
                } else {
                    break;
                }
            }
            if (isBuy && isExactInput && size == amountIn) {
                assembly {
                    amountIn := mload(0x60)
                }
            }
            else {
                isBuy ? amountIn = (amountIn * 100000 + uint256(m.takerFee) - 1) / uint256(m.takerFee) : amountOut = (amountOut * uint256(m.takerFee)) / 100000;
            }
            return (amountIn, amountOut);
        }
    }

    /**
     * @notice Shows how much of each token is currently in the AMM pool.
     *
     * @dev Gets called through delegatecall from the main Crystal contract.
     *
     * @return reserveQuote Amount of quote asset in the pool.
     * @return reserveBase Amount of base asset in the pool.
     */
    function getReserves() external payable returns (uint112 reserveQuote, uint112 reserveBase) {
        ICrystal.Market storage m = _getMarket[market];
        (reserveQuote, reserveBase) = (m.reserveQuote, m.reserveBase);
    }

    /**
     * @notice Executes a market-style order across resting liquidity and the AMM.
     *
     * @dev `orderInfo` is 256-252 orderType, 252-248 !isExactInput, 248-244 !isBuy, 244-240 STP, 240-236 !useexternalbalance, 236-232 !fromcaller, 218-208 cloid if needed, 208-160 userId if needed, 160-0 caller address.
     *
     * @param size Input or output amount depending on `orderInfo` flags.
     * @param worstPrice Worst price limit.
     * @param orderInfo Packed flags describing execution options.
     *
     * @return amountIn Total input amount including fees.
     * @return amountOut Total output amount after fees.
     * @return id New order id if a fallback limit order is placed.
     * @return settlementDelta Packed debit (high 128 bits) and credit (low 128 bits) for settlement.
     */
    function _marketOrder(uint256 size, uint256 worstPrice, uint256 orderInfo) internal returns (uint256 amountIn, uint256 amountOut, uint256 id, uint256 settlementDelta) {
        require(size <= MASK_KEEP_0_128, ICrystal.InvalidParams());
        ICrystal.Market storage m = _getMarket[market];
        uint256 price;
        bool isBuy = ((orderInfo >> 244) & 1) == 0;
        bool isExactInput = ((orderInfo >> 248) & 1) == 0;
        if (isBuy) {
            if (isExactInput) {
                assembly { // memory is 0x60 buy exact input price, 0x80 Trade event price, 0xa0 reserves, 0xe0 referrer
                    mstore(0x60, size)
                }
                size = (size * uint256(m.takerFee) + 99999) / 100000; // If input is specified adjust input size to account for taker fee
            }
            if (worstPrice >= maxPrice || worstPrice == 0) {
                worstPrice = (marketType == 0 ? maxPrice - tickSize : CM._tickToPrice(CM._priceToTick(maxPrice, tickSize) - 1, tickSize)); // Default worst price to one tick below max on taker buy orders (inclusive limit)
            }
            price = m.lowestAsk;
        } else {
            if (!isExactInput) {
                size = (size * 100000 + uint256(m.takerFee) - 1) / uint256(m.takerFee); // If output is specified adjust output size to account for taker fee
            }
            if (worstPrice == 0) {
                worstPrice = (marketType == 0 ? tickSize : CM._tickToPrice(1, tickSize)); // Default worst price to minimum tick on taker sell orders (inclusive limit)
            }
            price = m.highestBid;
        }
        {
            uint256 reserves = m.isAMMEnabled ? ((uint256(m.reserveQuote) << 128) | m.reserveBase) : 0;
            assembly { // Set reserves and clear Trade event price in memory
                mstore(0xa0, reserves)
                mstore(0x80, 0x0)
            }
        }
        {
            uint256 tick = marketType == 0 ? (price / tickSize) : CM._priceToTick(price, tickSize);
            uint256 slot;
            {
                (uint256 key, uint256 offset) = CS._getActivated(marketId, tick / 255);
                slot = CS._readMapping(key, offset, CS.PRICELEVELS_KEY) & MASK_OUT_255_256;
            }
            while (isExactInput ? size > amountIn : size > amountOut) {
                uint256 sizeLeft = isExactInput ? size - amountIn : size - amountOut;
                {
                    uint256 reserves;
                    assembly {
                        reserves := mload(0xa0)
                    }
                    if (reserves != 0) { // Skip AMM execution if disabled or missing liquidity
                        uint256 ammPriceLimit = (isBuy ? (price > worstPrice) : (price < worstPrice)) ? worstPrice : price;
                        uint256 ammAmountIn;
                        uint256 ammAmountOut;
                        {
                            (uint256 reserveQuote, uint256 reserveBase) = (reserves >> 128, reserves & MASK_KEEP_0_112);
                            uint256 adjustedAMMPrice;
                            if (isBuy) {
                                adjustedAMMPrice = (reserveQuote * scaleFactor * 10000 * uint256(m.makerRebate) + (reserveBase * 9975 * 100000 - 1)) / (reserveBase * 9975 * 100000);
                            } else {
                                adjustedAMMPrice = (reserveQuote * scaleFactor * 9975 * 100000) / (reserveBase * 10000 * uint256(m.makerRebate));
                            }
                            if (isBuy && ammPriceLimit > adjustedAMMPrice) { // Compare AMM price with orderbook price adjusted for maker rebate
                                if (isExactInput) {
                                    uint256 makerRebate = m.makerRebate;
                                    ammAmountIn = CM._exactInputBuySolve(reserveQuote, reserveBase, ammPriceLimit, makerRebate, sizeLeft, scaleFactor); // Compute optimal input for AMM execution at maker-adjusted price
                                    ammAmountOut = (ammAmountIn * 9975 * reserveBase) / ((reserveQuote * 10000) + (ammAmountIn * 9975)); // Execute Uniswap V2-style swap
                                } else {
                                    uint256 makerRebate = m.makerRebate;
                                    ammAmountOut = CM._exactOutputBuySolve(reserveQuote, reserveBase, ammPriceLimit, makerRebate, sizeLeft, scaleFactor); // Compute optimal output for AMM execution at maker-adjusted price
                                    ammAmountIn = (ammAmountOut * reserveQuote * 10000) / ((reserveBase - ammAmountOut) * 9975) + 1; // Execute Uniswap V2-style swap
                                }
                                reserveQuote += ammAmountIn;
                                reserveBase -= ammAmountOut;
                                require(reserveQuote <= MASK_KEEP_0_112 && reserveBase <= MASK_KEEP_0_112, ICrystal.Overflow());
                                {
                                    uint256 eventPrice;
                                    assembly { // Trade event price: upper 128 bits = start price, lower 128 bits = end price
                                        eventPrice := mload(0x80)
                                    }
                                    uint256 makerRebate = m.makerRebate;
                                    uint256 endPrice = ((reserveQuote * scaleFactor * 10000 * makerRebate + (reserveBase * 9975 * 100000 - 1)) / (reserveBase * 9975 * 100000)); // Adjust price favorably for AMM (no maker rebate)
                                    if (endPrice >= maxPrice) {
                                        endPrice = maxPrice;
                                    } else if (endPrice <= tickSize) {
                                        endPrice = tickSize;
                                    } else {
                                        endPrice = marketType == 0 ? (endPrice - (endPrice % tickSize)) : CM._toValidPrice(endPrice, tickSize, false); // Round down to valid price
                                    }
                                    if (eventPrice == 0) {
                                        uint256 startPrice = (((reserveQuote - ammAmountIn) * scaleFactor * 10000 * makerRebate + ((reserveBase + ammAmountOut) * 9975 * 100000 - 1)) / ((reserveBase + ammAmountOut) * 9975 * 100000));
                                        if (startPrice >= maxPrice) {
                                            startPrice = maxPrice;
                                        } else if (startPrice <= tickSize) {
                                            startPrice = tickSize;
                                        } else {
                                            startPrice = marketType == 0 ? (startPrice - (startPrice % tickSize)) : CM._toValidPrice(startPrice, tickSize, false); // Round down to valid price
                                        }
                                        eventPrice = (startPrice << 128) | endPrice; // Initialize start price using pre-swap reserves
                                    } else {
                                        eventPrice = (eventPrice & MASK_OUT_0_128) | endPrice;
                                    }
                                    assembly {
                                        mstore(0x80, eventPrice)
                                    }
                                }
                            } else if (!isBuy && ammPriceLimit < adjustedAMMPrice) {
                                if (isExactInput) {
                                    uint256 makerRebate = m.makerRebate;
                                    ammAmountIn = CM._exactInputSellSolve(reserveQuote, reserveBase, ammPriceLimit, makerRebate, sizeLeft, scaleFactor);
                                    ammAmountOut = ((ammAmountIn * 9975) * reserveQuote) / ((reserveBase * 10000) + (ammAmountIn * 9975)); // Execute Uniswap V2-style swap
                                } else {
                                    uint256 makerRebate = m.makerRebate;
                                    ammAmountOut = CM._exactOutputSellSolve(reserveQuote, reserveBase, ammPriceLimit, makerRebate, sizeLeft, scaleFactor);
                                    ammAmountIn = (ammAmountOut * reserveBase * 10000) / ((reserveQuote - ammAmountOut) * 9975) + 1; // Execute Uniswap V2-style swap
                                }
                                reserveBase += ammAmountIn;
                                reserveQuote -= ammAmountOut;
                                require(reserveQuote <= MASK_KEEP_0_112 && reserveBase <= MASK_KEEP_0_112, ICrystal.Overflow());
                                {
                                    uint256 eventPrice;
                                    assembly { // Trade event price: upper 128 bits = start price, lower 128 bits = end price
                                        eventPrice := mload(0x80)
                                    }
                                    uint256 makerRebate = m.makerRebate;
                                    uint256 endPrice = ((reserveQuote * scaleFactor * 9975 * 100000) / (reserveBase * 10000 * makerRebate));
                                    if (endPrice >= maxPrice) {
                                        endPrice = maxPrice;
                                    } else if (endPrice <= tickSize) {
                                        endPrice = tickSize;
                                    } else {
                                        endPrice = marketType == 0 ? ((endPrice + tickSize - 1) / tickSize) * tickSize : CM._toValidPrice(endPrice, tickSize, true); // Round up to valid price
                                    }
                                    if (eventPrice == 0) {
                                        uint256 startPrice = ((reserveQuote + ammAmountOut) * scaleFactor * 9975 * 100000) / ((reserveBase - ammAmountIn) * 10000 * makerRebate);
                                        if (startPrice >= maxPrice) {
                                            startPrice = maxPrice;
                                        } else if (startPrice <= tickSize) {
                                            startPrice = tickSize;
                                        } else {
                                            startPrice = marketType == 0 ? ((startPrice + tickSize - 1) / tickSize) * tickSize : CM._toValidPrice(startPrice, tickSize, true); // Round up to valid price
                                        }
                                        eventPrice = (startPrice << 128) | endPrice;
                                    } else {
                                        eventPrice = (eventPrice & MASK_OUT_0_128) | endPrice;
                                    }
                                    assembly {
                                        mstore(0x80, eventPrice)
                                    }
                                }
                            } else {
                                ammAmountIn = 0;
                            }
                            if (ammAmountIn != 0) {
                                uint256 _settlementDelta = settlementDelta; // Avoid stack too deep
                                require(((_settlementDelta >> 128) + ammAmountIn) <= MASK_KEEP_0_128, ICrystal.Overflow());
                                settlementDelta = _settlementDelta + (ammAmountIn << 128);
                                reserves = (reserveQuote << 128) | reserveBase;
                                assembly {
                                    mstore(0xa0, reserves)
                                }
                            }
                        }
                        if (ammAmountIn != 0) { // Moved outside block to avoid stack too deep
                            amountIn += ammAmountIn;
                            amountOut += ammAmountOut;
                            if (sizeLeft != (isExactInput ? ammAmountIn : ammAmountOut)) {
                                sizeLeft -= (isExactInput ? ammAmountIn : ammAmountOut);
                            } else {
                                (uint256 key, uint256 offset) = CS._getActivated(marketId, tick / 255);
                                if (CS._readMapping(key, offset, CS.PRICELEVELS_KEY) & MASK_OUT_255_256 != slot) {
                                    CS._writeMapping(key, offset, CS.PRICELEVELS_KEY, slot | MASK_KEEP_255_256);
                                }
                                break;
                            }
                        }
                    }
                    if (isBuy ? price > worstPrice : price < worstPrice) { // Handle slippage limit exceeded: 0 = Return, 1 = Revert, 2 = Place limit order with remaining size
                        require((orderInfo >> 252) != 1, ICrystal.SlippageExceeded());
                        {
                            (uint256 key, uint256 offset) = CS._getActivated(marketId, tick / 255);
                            if (CS._readMapping(key, offset, CS.PRICELEVELS_KEY) & MASK_OUT_255_256 != slot) {
                                CS._writeMapping(key, offset, CS.PRICELEVELS_KEY, slot | MASK_KEEP_255_256);
                            }
                        }
                        if ((orderInfo >> 252) == 2) {
                            if (reserves != 0) { // Update reserves to prevent limit order from crossing AMM
                                (uint112 reserveQuote, uint112 reserveBase) = (uint112(reserves >> 128), uint112(reserves & MASK_KEEP_0_112));
                                if (reserveQuote != m.reserveQuote || reserveBase != m.reserveBase) {
                                    (m.reserveQuote, m.reserveBase) = (reserveQuote, reserveBase);
                                    emit ICrystal.Sync(market, reserveQuote, reserveBase);
                                }
                                reserves = 0; // Mark reserves as already updated
                                assembly {
                                    mstore(0xa0, reserves)
                                }
                            }
                            isBuy ? m.lowestAsk = uint80(price) : m.highestBid = uint80(price);
                            uint256 limitSize = size; // Avoid stack too deep
                            uint256 limitPrice = worstPrice; // Avoid stack too deep
                            if (isBuy) {
                                if (isExactInput) { // Get original input amount before adjustment for fee
                                    assembly {
                                        limitSize := mload(0x60)
                                    }
                                    uint256 feeAmount = (amountIn * 100000);
                                    feeAmount = (feeAmount + uint256(m.takerFee) - 1) / uint256(m.takerFee);
                                    limitSize -= feeAmount;
                                } else {
                                    limitSize = (((limitSize - amountOut) * limitPrice) / scaleFactor);
                                }
                            } else {
                                if (isExactInput) {
                                    limitSize -= amountIn;
                                } else {
                                    uint256 _amountOut = amountOut; // Avoid stack too deep
                                    limitSize = (((limitSize - _amountOut) * scaleFactor) / limitPrice) * uint256(m.takerFee) / 100000;
                                }
                            }
                            uint256 _orderInfo = orderInfo; // Avoid stack too deep
                            (limitSize, id) = _limitOrder(isBuy, ((_orderInfo >> 236) & 0x1) == 0, limitPrice, limitSize, ((_orderInfo >> 160) & MASK_KEEP_0_41), ((_orderInfo >> 208) & MASK_KEEP_0_10));
                            require(((settlementDelta >> 128) + limitSize) <= MASK_KEEP_0_128, ICrystal.Overflow());
                            settlementDelta += (limitSize << 128);
                            if (limitSize != 0) {
                                _addToOrdersUpdatedEvent((LEADING_HEX_2 + (isBuy ? 0 : LEADING_HEX_1)) | (limitPrice << 168) | (id << 112) | limitSize); // Encoded: 8-bit flag | 80-bit price | 56-bit id | 112-bit size
                            }
                        }
                        break;
                    }
                }
                uint256 priceLevel;
                {
                    (uint256 key, uint256 offset) = CS._getPriceLevel(marketType, tickSize, marketId, price);
                    priceLevel = CS._readMapping(key, offset, CS.PRICELEVELS_KEY);
                }
                {
                    uint256 next = (priceLevel >> 205) & MASK_KEEP_0_51;
                    uint256 _orderInfo = orderInfo; // Avoid stack too deep
                    while ((priceLevel & MASK_KEEP_0_112) != 0 && sizeLeft != 0 && !((_orderInfo >> 252) == 3 && gasleft() < 200000)) { // Require at least 200k gas remaining for type 3 order
                        uint256 order;
                        if (next > MASK_KEEP_0_41) {
                            (uint256 key, uint256 offset) = CS._getCloidOrder(next & MASK_KEEP_0_41, next >> 41);
                            order = CS._readMapping(key, offset, CS.ORDERS_KEY);
                        } else {
                            (uint256 key, uint256 offset) = CS._getOrder(marketId, price, next);
                            order = CS._readMapping(key, offset, CS.ORDERS_KEY);
                        }       
                        if (((_orderInfo >> 240) & 0xF) != 0 && ((order >> 113) & MASK_KEEP_0_41) == ((_orderInfo >> 160) & MASK_KEEP_0_41)) { // Self-trade prevention: 0 = Fill as normal, 1 = Cancel resting and continue taker, 2 = Cancel taker, 3 = Cancel both resting and taker
                            if (((_orderInfo >> 240) & 0x1) != 0) { // Cancel resting order (STP mode 1 or 3)
                                uint256 ordersize = (order & MASK_KEEP_0_112);
                                if (next > MASK_KEEP_0_41) {
                                    uint256 userId = next & MASK_KEEP_0_41;
                                    (uint256 key, uint256 offset) = CS._getCloidOrder(userId, next >> 41);
                                    CS._writeMapping(key, offset, CS.ORDERS_KEY, userId << 113); // Leave owner id intact for canceled cloid order to avoid clearing storage
                                } else {
                                    (uint256 key, uint256 offset) = CS._getOrder(marketId, price, next);
                                    CS._writeMapping(key, offset, CS.ORDERS_KEY, 0); // Clear storage of canceled order
                                }
                                priceLevel -= ordersize;
                                if ((order & MASK_KEEP_112_113) != 0) {
                                    tokenBalances[(order >> 113) & MASK_KEEP_0_41][isBuy ? baseAsset : quoteAsset] -= (ordersize << 128); // Release locked tokens for internal balance orders
                                }
                                _addToOrdersUpdatedEvent((isBuy ? LEADING_HEX_1 : 0) | (price << 168) | (next << 112) | ordersize); // Encoded: 8-bit flag | 80-bit price | 56-bit id | 112-bit cancelled size
                                next = (order >> 205) & MASK_KEEP_0_51;
                                uint256 _settlementDelta = settlementDelta; // Avoid stack too deep
                                require(((_settlementDelta & MASK_KEEP_0_128) + ordersize) <= MASK_KEEP_0_128, ICrystal.Overflow());
                                settlementDelta = _settlementDelta + ordersize;
                            }
                            if (((_orderInfo >> 240) & 0xF) == 1) {
                                continue;
                            } else { // Cancel taker order (STP mode 2 or 3)
                                require((_orderInfo >> 252) != 1, ICrystal.SlippageExceeded());
                                sizeLeft = 0;
                                break;
                            }
                        }
                        if (_canFillRemaining(isBuy, isExactInput, uint256(m.makerRebate), price, sizeLeft, order & MASK_KEEP_0_112)) {
                            {
                                uint256 currentFillAmountOut;
                                {
                                    uint256 adjustedSizeLeft = ((sizeLeft * uint256(m.makerRebate)) / 100000);
                                    if (isExactInput) {
                                        currentFillAmountOut = (isBuy ? (adjustedSizeLeft * scaleFactor) / price : (adjustedSizeLeft * price) / scaleFactor); // Calculate output amount (rounded down)
                                    } else {
                                        currentFillAmountOut = sizeLeft;
                                        uint256 makerRebate = m.makerRebate;
                                        if (isBuy) { // Maker transfer amount (rounded up)
                                            sizeLeft = (sizeLeft * price * 100000 + (scaleFactor * makerRebate - 1)) / (scaleFactor * makerRebate);
                                        } else {
                                            sizeLeft = (sizeLeft * scaleFactor * 100000 + (price * makerRebate - 1)) / (price * makerRebate);
                                        }
                                    }
                                }
                                amountOut += currentFillAmountOut;
                                priceLevel -= currentFillAmountOut;
                                order -= currentFillAmountOut;
                                uint256 ownerUserId = (order >> 113) & MASK_KEEP_0_41;
                                address owner = userIdToAddress[ownerUserId];
                                if (order & MASK_KEEP_112_113 == 0) { // Maker receives external tokens
                                    if (((_orderInfo >> 236) & 0x1) == 0 && ((_orderInfo >> 232) & 0x1) == 0) { // Taker provides external tokens
                                        try IERC20(isBuy ? quoteAsset : baseAsset).transferFrom(msg.sender, owner, sizeLeft) {} catch {
                                            uint256 _settlementDelta = settlementDelta; // Avoid stack too deep
                                            require(((_settlementDelta >> 128) + sizeLeft) <= MASK_KEEP_0_128, ICrystal.Overflow());
                                            settlementDelta = _settlementDelta + (sizeLeft << 128);
                                            bool _isBuy = isBuy; // Avoid stack too deep
                                            if (((tokenBalances[ownerUserId][_isBuy ? quoteAsset : baseAsset] & MASK_KEEP_0_128) + sizeLeft) <= MASK_KEEP_0_128) {
                                                tokenBalances[ownerUserId][_isBuy ? quoteAsset : baseAsset] += sizeLeft;
                                            } else {
                                                tokenBalances[ownerUserId][_isBuy ? quoteAsset : baseAsset] |= MASK_KEEP_0_128;
                                            }
                                        }
                                    } else { // Taker provides from internal balance
                                        uint256 _settlementDelta = settlementDelta; // Avoid stack too deep
                                        require(((_settlementDelta >> 128) + sizeLeft) <= MASK_KEEP_0_128, ICrystal.Overflow());
                                        settlementDelta = _settlementDelta + (sizeLeft << 128);
                                        (bool success, ) = (isBuy ? quoteAsset : baseAsset).call(abi.encodeWithSelector(0xa9059cbb, owner, sizeLeft));
                                        if (!success) { // Fallback: credit internal balance if external transfer fails (e.g., blacklisted maker)
                                            bool _isBuy = isBuy; // Avoid stack too deep
                                            if (((tokenBalances[ownerUserId][_isBuy ? quoteAsset : baseAsset] & MASK_KEEP_0_128) + sizeLeft) <= MASK_KEEP_0_128) {
                                                tokenBalances[ownerUserId][_isBuy ? quoteAsset : baseAsset] += sizeLeft;
                                            } else {
                                                tokenBalances[ownerUserId][_isBuy ? quoteAsset : baseAsset] |= MASK_KEEP_0_128;
                                            }
                                        }
                                    }
                                } else { // Maker receives to internal balance
                                    uint256 _settlementDelta = settlementDelta; // Avoid stack too deep
                                    require(((_settlementDelta >> 128) + sizeLeft) <= MASK_KEEP_0_128, ICrystal.Overflow());
                                    settlementDelta = _settlementDelta + (sizeLeft << 128);
                                    bool _isBuy = isBuy; // Avoid stack too deep
                                    if (((tokenBalances[ownerUserId][_isBuy ? quoteAsset : baseAsset] & MASK_KEEP_0_128) + sizeLeft) <= MASK_KEEP_0_128) {
                                        tokenBalances[ownerUserId][_isBuy ? quoteAsset : baseAsset] += sizeLeft;
                                    } else {
                                        tokenBalances[ownerUserId][_isBuy ? quoteAsset : baseAsset] |= MASK_KEEP_0_128;
                                    }
                                    tokenBalances[ownerUserId][_isBuy ? baseAsset : quoteAsset] -= (currentFillAmountOut << 128); // Release maker's locked internal balance
                                }
                                ownerUserId = (isBuy ? 0 : LEADING_HEX_1) | (price << 168) | (next << 112) | (order & MASK_KEEP_0_112); // fillInfo, avoid stack too deep
                                emit ICrystal.Fill(market, owner, ownerUserId, (sizeLeft << 128) | currentFillAmountOut);
                                assembly {
                                    mstore(0x40, add(mload(0xe0), 0x100))
                                }
                            }
                            if (next > MASK_KEEP_0_41) {
                                (uint256 key, uint256 offset) = CS._getCloidOrder(next & MASK_KEEP_0_41, next >> 41);
                                CS._writeMapping(key, offset, CS.ORDERS_KEY, order);
                            } else {
                                (uint256 key, uint256 offset) = CS._getOrder(marketId, price, next);
                                CS._writeMapping(key, offset, CS.ORDERS_KEY, order);
                            }
                            amountIn += sizeLeft;
                            sizeLeft = 0;
                        } else {
                            {   
                                if (isBuy) { // Add transferAmount to amountIn
                                    amountIn += ((((order & MASK_KEEP_0_112) * price) / scaleFactor) * 100000) / uint256(m.makerRebate);
                                } else {
                                    amountIn += ((((order & MASK_KEEP_0_112) * scaleFactor) / price) * 100000) / uint256(m.makerRebate);
                                }
                                uint256 currentFillAmountOut = (order & MASK_KEEP_0_112);
                                amountOut += currentFillAmountOut;
                                uint256 transferAmount;
                                if (isBuy) {
                                    transferAmount = (((currentFillAmountOut * price) / scaleFactor) * 100000) / uint256(m.makerRebate);
                                } else {
                                    transferAmount = (((currentFillAmountOut * scaleFactor) / price) * 100000) / uint256(m.makerRebate);
                                }
                                priceLevel -= currentFillAmountOut;
                                sizeLeft -= isExactInput ? transferAmount : currentFillAmountOut;
                                address owner = userIdToAddress[(order >> 113) & MASK_KEEP_0_41];
                                if (order & MASK_KEEP_112_113 == 0) { // Maker receives external tokens
                                    if (((_orderInfo >> 236) & 0x1) == 0 && ((_orderInfo >> 232) & 0x1) == 0) { // Taker provides external tokens
                                        try IERC20(isBuy ? quoteAsset : baseAsset).transferFrom(msg.sender, owner, transferAmount) {} catch {
                                            uint256 _settlementDelta = settlementDelta; // Avoid stack too deep
                                            require(((_settlementDelta >> 128) + transferAmount) <= MASK_KEEP_0_128, ICrystal.Overflow());
                                            settlementDelta = _settlementDelta + (transferAmount << 128);
                                            bool _isBuy = isBuy; // Avoid stack too deep
                                            if (((tokenBalances[(order >> 113) & MASK_KEEP_0_41][(_isBuy) ? quoteAsset : baseAsset] & MASK_KEEP_0_128) + transferAmount) <= MASK_KEEP_0_128) {
                                                tokenBalances[(order >> 113) & MASK_KEEP_0_41][(_isBuy) ? quoteAsset : baseAsset] += transferAmount;
                                            } else {
                                                tokenBalances[(order >> 113) & MASK_KEEP_0_41][(_isBuy) ? quoteAsset : baseAsset] |= MASK_KEEP_0_128;
                                            }
                                        }
                                    } else { // Taker provides from internal balance
                                        uint256 _settlementDelta = settlementDelta; // Avoid stack too deep
                                        require(((_settlementDelta >> 128) + transferAmount) <= MASK_KEEP_0_128, ICrystal.Overflow());
                                        settlementDelta = _settlementDelta + (transferAmount << 128);
                                        (bool success, ) = (isBuy ? quoteAsset : baseAsset).call(abi.encodeWithSelector(0xa9059cbb, owner, transferAmount));
                                        if (!success) { // Fallback: credit internal balance if external transfer fails (e.g., blacklisted maker)
                                            bool _isBuy = isBuy; // Avoid stack too deep
                                            if (((tokenBalances[(order >> 113) & MASK_KEEP_0_41][(_isBuy) ? quoteAsset : baseAsset] & MASK_KEEP_0_128) + transferAmount) <= MASK_KEEP_0_128) {
                                                tokenBalances[(order >> 113) & MASK_KEEP_0_41][(_isBuy) ? quoteAsset : baseAsset] += transferAmount;
                                            } else {
                                                tokenBalances[(order >> 113) & MASK_KEEP_0_41][(_isBuy) ? quoteAsset : baseAsset] |= MASK_KEEP_0_128;
                                            }
                                        }
                                    }
                                } else { // Maker receives to internal balance
                                    uint256 _settlementDelta = settlementDelta; // Avoid stack too deep
                                    require(((_settlementDelta >> 128) + transferAmount) <= MASK_KEEP_0_128, ICrystal.Overflow());
                                    settlementDelta = _settlementDelta + (transferAmount << 128);
                                    bool _isBuy = isBuy; // Avoid stack too deep
                                    if (((tokenBalances[(order >> 113) & MASK_KEEP_0_41][(_isBuy) ? quoteAsset : baseAsset] & MASK_KEEP_0_128) + transferAmount) <= MASK_KEEP_0_128) {
                                        tokenBalances[(order >> 113) & MASK_KEEP_0_41][(_isBuy) ? quoteAsset : baseAsset] += transferAmount;
                                    } else {
                                        tokenBalances[(order >> 113) & MASK_KEEP_0_41][(_isBuy) ? quoteAsset : baseAsset] |= MASK_KEEP_0_128;
                                    }
                                    tokenBalances[(order >> 113) & MASK_KEEP_0_41][(_isBuy) ? baseAsset : quoteAsset] -= (currentFillAmountOut << 128); // Release maker's locked internal balance
                                }
                                uint256 fillInfo = (isBuy ? 0 : LEADING_HEX_1) | (price << 168) | (next << 112);
                                emit ICrystal.Fill(market, owner, fillInfo, (transferAmount << 128) | currentFillAmountOut);
                                assembly {
                                    mstore(0x40, add(mload(0xe0), 0x100))
                                }
                            }
                            if (next > MASK_KEEP_0_41) {
                                uint256 userId = next & MASK_KEEP_0_41;
                                (uint256 key, uint256 offset) = CS._getCloidOrder(userId, next >> 41);
                                CS._writeMapping(key, offset, CS.ORDERS_KEY, userId << 113); // Leave owner id intact for filled cloid order to avoid clearing storage
                            } else {
                                (uint256 key, uint256 offset) = CS._getOrder(marketId, price, next);
                                CS._writeMapping(key, offset, CS.ORDERS_KEY, 0); // Clear storage of filled order
                            }
                            next = (order >> 205) & MASK_KEEP_0_51;
                        }
                    }
                    (uint256 key, uint256 offset) = CS._getPriceLevel(marketType, tickSize, marketId, price);
                    CS._writeMapping(key, offset, CS.PRICELEVELS_KEY, (next << 205) | (priceLevel & MASK_OUT_205_256)); // Advance fillNext pointer
                }
                assembly { // Trade event price: upper 128 bits = start price, lower 128 bits = end price
                    let eventPrice := mload(0x80)
                    switch eventPrice
                    case 0 { // Set start price for event if unset
                        eventPrice := or(shl(128, price), price)
                    }
                    default { // Update end price for event
                        eventPrice := or(and(eventPrice, MASK_OUT_0_128), price)
                    }
                    mstore(0x80, eventPrice)
                }
                if ((priceLevel & MASK_KEEP_0_112) == 0) { // Price level exhausted; find next active level and update bitmap if needed
                    uint256 slotIndex = tick / 255;
                    slot &= ~(1 << (tick % 255));
                    if (slot == 0) {
                        (uint256 key, uint256 offset) = CS._getGroups(marketId, slotIndex / 255);
                        CS._writeMapping(key, offset, CS.GROUPS_KEY, CS._readMapping(key, offset, CS.GROUPS_KEY) & ~(1 << (slotIndex % 255)));
                    }
                    if (isBuy) {
                        (tick, slot, slotIndex, ) = _searchUp(true, tick, slot, slotIndex, 0);
                    } else {
                        (tick, slot, slotIndex, ) = _searchDown(true, tick, slot, slotIndex, 0);
                    }
                    price = marketType == 0 ? (tick * tickSize) : CM._tickToPrice(tick, tickSize);
                }
                if (sizeLeft == 0 || ((orderInfo >> 252) == 3 && gasleft() < 200000)) { // If type 3 order and less than 200k gas remaining, exit
                    (uint256 key, uint256 offset) = CS._getActivated(marketId, tick / 255);
                    if (CS._readMapping(key, offset, CS.PRICELEVELS_KEY) & MASK_OUT_255_256 != slot) {
                        CS._writeMapping(key, offset, CS.PRICELEVELS_KEY, slot | MASK_KEEP_255_256);
                    }
                    break;
                }
            }
        }
        if (amountIn != 0 || amountOut != 0) {
            uint256 reserves;
            assembly {
                reserves := mload(0xa0)
            }
            if (reserves != 0) { // Update AMM reserves if modified
                (uint112 reserveQuote, uint112 reserveBase) = (uint112(reserves >> 128), uint112(reserves & MASK_KEEP_0_112));
                if (reserveQuote != m.reserveQuote || reserveBase != m.reserveBase) {
                    (m.reserveQuote, m.reserveBase) = (reserveQuote, reserveBase);
                    emit ICrystal.Sync(market, reserveQuote, reserveBase);
                }
            }
            uint256 feeAmount;
            if (isBuy) { // Trading fees are always denominated in quote asset
                feeAmount = (amountIn * 100000 + uint256(m.takerFee) - 1) / uint256(m.takerFee) - amountIn;
                if (isExactInput && size == amountIn) {
                    assembly {
                        size := mload(0x60)
                    }
                    feeAmount = size - amountIn; // Satisfy the invariant that a complete fill exact input order consumes the specified amount
                }
                amountIn += feeAmount;
                require(((settlementDelta >> 128) + feeAmount) <= MASK_KEEP_0_128, ICrystal.ActionFailed());
                settlementDelta += (feeAmount << 128);
                m.lowestAsk = uint80(price);
            } else {
                feeAmount = amountOut - (amountOut * uint256(m.takerFee)) / 100000;
                amountOut -= feeAmount;
                m.highestBid = uint80(price);
            }
            address refAddress;
            assembly {
                refAddress := mload(0xc0)
            }
            if (refAddress == address(0)) {
                uint256 creatorFee;
                if (marketType == 3) {
                    creatorFee = (feeAmount * m.creatorFeeSplit) / 100;
                    claimableRewards[quoteAsset][m.creator] += creatorFee;
                }
                claimableRewards[quoteAsset][feeRecipient] += (feeAmount - creatorFee);
            } else {
                uint256 amountCommission = (feeAmount * feeCommission) / 100;
                claimableRewards[quoteAsset][refAddress] += amountCommission;
                uint256 creatorFee;
                if (marketType == 3) {
                    creatorFee = (feeAmount * m.creatorFeeSplit) / 100;
                    claimableRewards[quoteAsset][m.creator] += creatorFee;
                }
                claimableRewards[quoteAsset][feeRecipient] += (feeAmount - amountCommission - creatorFee);
            }
            uint256 eventPrice;
            assembly { // Trade event price: upper 128 bits = start price, lower 128 bits = end price
                eventPrice := mload(0x80)
            }
            emit ICrystal.Trade(market, address(uint160(orderInfo)), isBuy, amountIn, amountOut, eventPrice >> 128, eventPrice & MASK_KEEP_0_128);
            return (amountIn, amountOut, id, settlementDelta);
        } else {
            isBuy ? m.lowestAsk = uint80(price) : m.highestBid = uint80(price);
            return (0, 0, id, settlementDelta);
        }
    }

    /**
     * @notice Places a limit order on the orderbook.
     *
     * @dev Validates prices against spread, AMM bounds, cloid uniqueness, and minimum size.
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
        unchecked { // Client order ID (cloid) size previously validated already, 0 is invalid
            {
                ICrystal.Market storage m = _getMarket[market];
                (uint256 highestBid, uint256 lowestAsk) = (m.highestBid, m.lowestAsk);
                bool isExistingCloidOrder;
                if (cloid != 0) {
                    (uint256 key, uint256 offset) = CS._getCloidOrder(userId, cloid);
                    isExistingCloidOrder = (CS._readMapping(key, offset, CS.ORDERS_KEY) & MASK_OUT_113_154) != 0;
                }
                if (isBuy) {
                    bool isBelowMinSize = size < ((m.minSize >> 20) * 10 ** (m.minSize & MASK_KEEP_0_20));
                    if (isExistingCloidOrder || price >= lowestAsk || price == 0 || isBelowMinSize) {
                        return (0, 0);
                    }
                    if (m.isAMMEnabled && m.reserveQuote != 0) {
                        uint256 adjustedAMMPrice = ((uint256(m.reserveQuote) * scaleFactor * 10000 * 100000 + (uint256(m.reserveBase) * 9975 * uint256(m.makerRebate) - 1)) / (uint256(m.reserveBase) * 9975 * uint256(m.makerRebate)));
                        if (price > adjustedAMMPrice) {
                            return (0, 0);
                        }
                    }
                    if (price > highestBid) {
                        m.highestBid = uint80(price);
                    }
                    if (!isRecieveTokens) {
                        require(((tokenBalances[userId][quoteAsset] >> 128) + size) <= MASK_KEEP_0_128, ICrystal.Overflow());
                        tokenBalances[userId][quoteAsset] += (size << 128); // Lock tokens for internal balance orders
                    }
                } else {
                    bool isBelowMinSize = ((size * price) / scaleFactor) < ((m.minSize >> 20) * 10 ** (m.minSize & MASK_KEEP_0_20));
                    if (isExistingCloidOrder || price <= highestBid || price >= maxPrice || isBelowMinSize) {
                        return (0, 0);
                    }
                    if (m.isAMMEnabled && m.reserveQuote != 0) {
                        uint256 adjustedAMMPrice = ((uint256(m.reserveQuote) * scaleFactor * 9975 * uint256(m.makerRebate)) / (uint256(m.reserveBase) * 10000 * 100000));
                        if (price < adjustedAMMPrice) {
                            return (0, 0);
                        }
                    }
                    if (price < lowestAsk) {
                        m.lowestAsk = uint80(price);
                    }
                    if (!isRecieveTokens) {
                        require(((tokenBalances[userId][baseAsset] >> 128) + size) <= MASK_KEEP_0_128, ICrystal.Overflow());
                        tokenBalances[userId][baseAsset] += (size << 128); // Lock tokens for internal balance orders
                    }
                }
            }
            (uint256 key, uint256 offset) = CS._getPriceLevel(marketType, tickSize, marketId, price);
            uint256 priceLevel = CS._readMapping(key, offset, CS.PRICELEVELS_KEY);
            require((price % tickSize == 0) && (size <= MASK_KEEP_0_112) && ((priceLevel & MASK_KEEP_0_112) + size) <= MASK_KEEP_0_112, ICrystal.InvalidParams()); // Bounds check: invalid parameters revert rather than silently fail
            if (cloid != 0) {
                { // Update price and market in storage for cloid
                    (key, offset) = CS._getVerifyCloid(userId, cloid);
                    uint256 verifyCloid = (CS._readMapping(key, offset, CS.ORDERS_KEY) & (cloid & 1 == 0 ? MASK_KEEP_0_128 : MASK_OUT_0_128)) | (cloid & 1 == 0 ? ((marketId << 80) | (price << 128)) : ((marketId >> 48) | price));
                    CS._writeMapping(key, offset, CS.ORDERS_KEY, verifyCloid);
                }
                if ((priceLevel & MASK_KEEP_0_112) == 0) {
                    priceLevel = _activatePriceLevel(price, priceLevel, (cloid << 41) | userId); // Set fillNext pointer to cloid
                } else {
                    uint256 fillBefore = (priceLevel >> 154) & MASK_KEEP_0_51;
                    if (fillBefore > MASK_KEEP_0_41) {
                        uint256 fillBeforeCloid = fillBefore >> 41;
                        (key, offset) = CS._getCloidOrder(fillBefore & MASK_KEEP_0_41, fillBeforeCloid);
                    } else {
                        (key, offset) = CS._getOrder(marketId, price, fillBefore);
                    }
                    fillBefore = (((cloid << 41) | userId) << 205) | (CS._readMapping(key, offset, CS.ORDERS_KEY) & MASK_OUT_205_256);
                    CS._writeMapping(key, offset, CS.ORDERS_KEY, fillBefore); // Update fillBefore's fillAfter to point to cloid
                }
                uint256 order = ((((priceLevel >> 113) & MASK_KEEP_0_41) + 1) << 205) | (priceLevel & (MASK_KEEP_0_51 << 154)) | (userId << 113) | (isRecieveTokens ? 0 : (1 << 112)) | size;
                (key, offset) = CS._getCloidOrder(userId, cloid);
                CS._writeMapping(key, offset, CS.ORDERS_KEY, order); // Set fillAfter to next native ID, fillBefore to latest
                cloid = (cloid << 41) | userId; // Convert cloid to storage pointer with userId
                priceLevel = (cloid << 154) | ((priceLevel & MASK_OUT_154_205) + size); // Update latest pointer to cloid and add to liquidity
                (key, offset) = CS._getPriceLevel(marketType, tickSize, marketId, price);
                CS._writeMapping(key, offset, CS.PRICELEVELS_KEY, priceLevel);
                return (size, cloid);
            } else {
                id = ((priceLevel >> 113) & MASK_KEEP_0_41) + 1;
                require(id <= MASK_KEEP_0_41, ICrystal.InvalidParams());
                if ((priceLevel & MASK_KEEP_0_112) == 0) {
                    priceLevel = _activatePriceLevel(price, priceLevel, id); // Set fillNext pointer to order id
                }
                uint256 order = ((id + 1) << 205) | (priceLevel & (MASK_KEEP_0_51 << 154)) | (userId << 113) | (isRecieveTokens ? 0 : (1 << 112)) | size;
                (key, offset) = CS._getOrder(marketId, price, id);
                CS._writeMapping(key, offset, CS.ORDERS_KEY, order); // Set fillAfter to next native ID, fillBefore to latest
                priceLevel = (id << 154) | (id << 113) | ((priceLevel & MASK_OUT_113_205) + size); // Update latest and latestNativeId, add to liquidity
                (key, offset) = CS._getPriceLevel(marketType, tickSize, marketId, price);
                CS._writeMapping(key, offset, CS.PRICELEVELS_KEY, priceLevel);
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
        unchecked { // Interpret id as cloid when price is zero
            ICrystal.Market storage m = _getMarket[market];
            uint256 order;
            if (price == 0) {
                (uint256 key, uint256 offset) = CS._getCloidOrder(userId, id);
                order = CS._readMapping(key, offset, CS.ORDERS_KEY);
            } else {
                (uint256 key, uint256 offset) = CS._getOrder(marketId, price, id);
                order = CS._readMapping(key, offset, CS.ORDERS_KEY);
            }
            size = (order & MASK_KEEP_0_112);
            if (0 == size || userId != ((order >> 113) & MASK_KEEP_0_41)) {
                return (0, 0, isBuy);
            }
            if (price == 0) {
                (uint256 key, uint256 offset) = CS._getVerifyCloid(userId, id);
                price = CS._readMapping(key, offset, CS.ORDERS_KEY); // Validate cloid belongs to this market and extract price
                if (id & 1 == 0) { // If even, read the higher 128 bits
                    if (((price >> 208) & MASK_KEEP_0_48) != (marketId >> 128) || id >= 1024) {
                        return (0, 0, isBuy);
                    }
                    price = (price >> 128) & MASK_KEEP_0_80;
                } else { // If odd, read the lower 128 bits
                    if (((price >> 80) & MASK_KEEP_0_48) != (marketId >> 128) || id >= 1024) {
                        return (0, 0, isBuy);
                    }
                    price = price & MASK_KEEP_0_80;
                }
                (key, offset) = CS._getCloidOrder(userId, id);
                CS._writeMapping(key, offset, CS.ORDERS_KEY, userId << 113); // Leave owner id intact for canceled cloid order to avoid clearing storage
                id = (id << 41) | userId; // Convert ID to storage pointer with userId
            } else {
                (uint256 key, uint256 offset) = CS._getOrder(marketId, price, id);
                CS._writeMapping(key, offset, CS.ORDERS_KEY, 0); // Clear storage of canceled order
            }
            (uint256 highestBid, uint256 lowestAsk) = (m.highestBid, m.lowestAsk);
            if (price <= highestBid) {
                isBuy = true;
                if ((order & MASK_KEEP_112_113) != 0) {
                    tokenBalances[userId][quoteAsset] -= (size << 128); // Release locked tokens for internal balance
                }
            } else {
                if ((order & MASK_KEEP_112_113) != 0) {
                    tokenBalances[userId][baseAsset] -= (size << 128); // Release locked tokens for internal balance
                }
            }
            _internalCancel(price, id, size, highestBid, lowestAsk, order);
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
        ICrystal.Market storage m = _getMarket[market];
        uint256 order;
        if (price == 0) {
            (uint256 key, uint256 offset) = CS._getCloidOrder(userId, id);
            order = CS._readMapping(key, offset, CS.ORDERS_KEY);
        } else {
            (uint256 key, uint256 offset) = CS._getOrder(marketId, price, id);
            order = CS._readMapping(key, offset, CS.ORDERS_KEY);
        }
        size = (order & MASK_KEEP_0_112);
        if (0 == size || userId != ((order >> 113) & MASK_KEEP_0_41) || decreaseAmount > MASK_KEEP_0_112) {
            return (0, 0, isBuy);
        }
        if (price == 0) {
            (uint256 key, uint256 offset) = CS._getVerifyCloid(userId, id);
            price = CS._readMapping(key, offset, CS.ORDERS_KEY); // Validate cloid belongs to this market and extract price
            if (id & 1 == 0) { // If even, read the higher 128 bits
                if (((price >> 208) & MASK_KEEP_0_48) != (marketId >> 128) || id >= 1024) {
                    return (0, 0, isBuy);
                }
                price = (price >> 128) & MASK_KEEP_0_80;
            } else { // If odd, read the lower 128 bits
                if (((price >> 80) & MASK_KEEP_0_48) != (marketId >> 128) || id >= 1024) {
                    return (0, 0, isBuy);
                }
                price = price & MASK_KEEP_0_80;
            }
            id = (id << 41) | userId; // Convert id to storage pointer so we can later check if cloid
        }
        (uint256 highestBid, uint256 lowestAsk) = (m.highestBid, m.lowestAsk);
        if (price <= highestBid) {
            isBuy = true;
        }
        uint256 quoteOrderSize = (isBuy ? size : ((size * price) / scaleFactor));
        uint256 quoteDecreaseAmount = (isBuy ? decreaseAmount : ((decreaseAmount * price) / scaleFactor)) + (((m.minSize >> 20) * 10 ** (m.minSize & MASK_KEEP_0_20)));
        if (quoteOrderSize < quoteDecreaseAmount) { // Cancel entirely if resulting order size would be dust
            if ((order & MASK_KEEP_112_113) != 0) { // Release locked internal balance tokens if specified
                isBuy ? tokenBalances[userId][quoteAsset] -= (size << 128) : tokenBalances[userId][baseAsset] -= (size << 128);
            }
            if (id > MASK_KEEP_0_41) {
                uint256 cloid = (id >> 41);
                (uint256 key, uint256 offset) = CS._getCloidOrder(userId, cloid);
                uint256 _userId = userId; // Avoid stack too deep
                CS._writeMapping(key, offset, CS.ORDERS_KEY, _userId << 113); // Leave owner id intact for canceled cloid order to avoid clearing storage
            } else {
                uint256 _price = price; // Avoid stack too deep
                uint256 _id = id; // Avoid stack too deep
                (uint256 key, uint256 offset) = CS._getOrder(marketId, _price, _id);
                CS._writeMapping(key, offset, CS.ORDERS_KEY, 0); // Clear storage of canceled order
            }
            _internalCancel(price, id, size, highestBid, lowestAsk, order);
            return (price, size, isBuy);
        } else {
            if ((order & MASK_KEEP_112_113) != 0) { // Release locked internal balance tokens if specified
                isBuy ? tokenBalances[userId][quoteAsset] -= (decreaseAmount << 128) : tokenBalances[userId][baseAsset] -= (decreaseAmount << 128);
            }
            {
                uint256 _price = price; // Avoid stack too deep
                (uint256 key, uint256 offset) = CS._getPriceLevel(marketType, tickSize, marketId, _price);
                uint256 priceLevel = CS._readMapping(key, offset, CS.PRICELEVELS_KEY) - decreaseAmount;
                CS._writeMapping(key, offset, CS.PRICELEVELS_KEY, priceLevel);
            }
            if (id > MASK_KEEP_0_41) {
                uint256 cloid = (id >> 41);
                (uint256 key, uint256 offset) = CS._getCloidOrder(userId, cloid);
                uint256 _decreaseAmount = decreaseAmount; // Avoid stack too deep
                CS._writeMapping(key, offset, CS.ORDERS_KEY, order - _decreaseAmount); // Decrease order size
            } else {
                uint256 _price = price; // Avoid stack too deep
                uint256 _id = id; // Avoid stack too deep
                uint256 _decreaseAmount = decreaseAmount; // Avoid stack too deep
                (uint256 key, uint256 offset) = CS._getOrder(marketId, _price, _id);
                CS._writeMapping(key, offset, CS.ORDERS_KEY, order - _decreaseAmount); // Decrease order size
            }
            return (price, decreaseAmount << 128, isBuy);
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
     * @param newPrice New price.
     * @param newSize New order size (0 to use resting order's remaining size).
     *
     * @return quoteAssetDebt Net quote delta to settle.
     * @return baseAssetDebt Net base delta to settle.
     * @return newId Identifier of the replacement order, or 0 if none.
     */
    function _replaceOrder(uint256 options, uint256 price, uint256 id, uint256 newPrice, uint256 newSize) internal returns (int256 quoteAssetDebt, int256 baseAssetDebt, uint256 newId) {
        unchecked {
            bool isBuy;
            bool isCloid;
            uint256 prevSize;
            uint256 userId = (options & MASK_KEEP_0_41);
            if (price == 0) {
                isCloid = true;
                (uint256 key, uint256 offset) = CS._getVerifyCloid(userId, id);
                price = CS._readMapping(key, offset, CS.ORDERS_KEY); // Validate cloid belongs to this market and extract price
                if (id & 1 == 0) { // If even, read the higher 128 bits
                    if (((price >> 208) & MASK_KEEP_0_48) != (marketId >> 128) || id >= 1024) {
                        return (0, 0, 0);
                    }
                    price = (price >> 128) & MASK_KEEP_0_80;
                } else { // If odd, read the lower 128 bits
                    if (((price >> 80) & MASK_KEEP_0_48) != (marketId >> 128) || id >= 1024) {
                        return (0, 0, 0);
                    }
                    price = price & MASK_KEEP_0_80;
                }
                uint256 _id = id; // Avoid stack too deep
                (key, offset) = CS._getCloidOrder(userId, _id);
                prevSize = (CS._readMapping(key, offset, CS.ORDERS_KEY) & MASK_KEEP_0_112); // Read order size using raw ID
            } else {
                (uint256 key, uint256 offset) = CS._getOrder(marketId, price, id);
                prevSize = (CS._readMapping(key, offset, CS.ORDERS_KEY) & MASK_KEEP_0_112); // Read order size using raw ID
            }
            if (price <= _getMarket[market].highestBid) {
                isBuy = true;
            }
            if (newPrice == 0) {
                newPrice = price;
            }
            if (newSize == 0 && newPrice == price) {
                return (0, 0, 0); // No state change; silent return permitted
            }
            if ((((options >> 48) & 1) != 0) || (newPrice == price && (prevSize > newSize))) {
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
                if (((options >> 44) & 1) == 0) { // Place post-only limit order
                    (prevSize, newId) = _limitOrder(isBuy, (((options >> 60) & 1) == 0), newPrice, newSize, userId, id);
                    if (prevSize != 0) {
                        isBuy ? quoteAssetDebt += int256(prevSize) : baseAssetDebt += int256(prevSize);
                        _addToOrdersUpdatedEvent((LEADING_HEX_2 + (isBuy ? 0 : LEADING_HEX_1)) | (newPrice << 168) | (newId << 112) | prevSize); // Encoded: 3-bit flag | 80-bit price | 56-bit id | 112-bit size
                    } else {
                        return (quoteAssetDebt, baseAssetDebt, 0);
                    }
                } else { // Place market-to-limit order
                    bool useExternalBalances = ((options >> 60) & 1) == 0; // Reuse variable: true indicates external balance mode
                    bool fromInternal = ((options >> 56) & 1) == 0;
                    uint256 orderInfo = (2 << 252) | (isBuy ? 0 : (1 << 244)) | (1 << 240) | (useExternalBalances ? 0 : (1 << 236)) | (fromInternal ? 0 : (1 << 232)) | (id << 208) | (userId << 160) | (options >> 96);
                    uint256 settlementDelta;
                    (, prevSize, newId, settlementDelta) = _marketOrder(newSize, newPrice, orderInfo);
                    if (isBuy) {
                        quoteAssetDebt += int256(settlementDelta >> 128);
                        baseAssetDebt -= int256(prevSize + (settlementDelta & MASK_KEEP_0_128)); // Safe: value bounded by uint128 intrinsic limit
                    } else {
                        baseAssetDebt += int256(settlementDelta >> 128);
                        quoteAssetDebt -= int256(prevSize + (settlementDelta & MASK_KEEP_0_128)); // Safe: value bounded by uint128 intrinsic limit
                    }
                }
                return (quoteAssetDebt, baseAssetDebt, newId);
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
                orderInfo = orderFlags | (((options >> 68) & 1) << 236) | (((options >> 64) & 1) << 232) | uint160(user); // Embed caller address, userId at bits 160-208 for internal/MTL, cloid at 208-218 for MTL
                userId = (options & MASK_KEEP_0_41);
                if (userId != 0) {
                    require(userIdToAddress[userId] == user, ICrystal.Unauthorized(msg.sender));
                } else {
                    userId = addressToUserId[user];
                    if (userId == 0) {
                        userId = ICrystal(crystal).registerUser(user);
                    }
                }
                orderInfo |= (userId << 160); // Embed userId in order info structure
                if (((options >> 44) & MASK_KEEP_0_10) != 0) { // Client order ID (cloid) provided
                    orderInfo |= (((options >> 44) & MASK_KEEP_0_10) << 208);
                }
            }
            uint256 settlementDelta;
            assembly {
                mstore(0xc0, referrer)
                mstore(0x40, 0x100) // Reserve memory; 0x80 used internally by _marketOrder
            }
            (amountIn, amountOut, id, settlementDelta) = _marketOrder(size, worstPrice, orderInfo);
            address token = isBuy ? quoteAsset : baseAsset;
            if ((settlementDelta >> 128) != 0) { // Handle input token for limit order placement, maker fills, and the trade fee for buys
                if (((options >> 68) & 1) != 0) {
                    uint256 balance = tokenBalances[userId][token];
                    require(uint128(balance) >= (settlementDelta >> 128), ICrystal.ActionFailed());
                    tokenBalances[userId][token] = balance - (settlementDelta >> 128);
                } else { // External balance mode: transfer tokens
                    if (((options >> 64) & 1) != 0) { // Use router's internal balance
                        // Use router's internal balance
                        uint256 balance = tokenBalances[0][token];
                        require(uint128(balance) >= (settlementDelta >> 128), ICrystal.ActionFailed());
                        tokenBalances[0][token] = balance - (settlementDelta >> 128);
                    } else {
                        IERC20(token).transferFrom(msg.sender, address(this), (settlementDelta >> 128));
                    }
                }
            }
            settlementDelta = (settlementDelta & MASK_KEEP_0_128) + amountOut; // Accumulate output with self-cancel credit
            token = isBuy ? baseAsset : quoteAsset;
            if (settlementDelta != 0) { // Handle output token: STP cancellations plus trade output
                if (((options >> 68) & 1) != 0) {
                    require(((tokenBalances[userId][token] & MASK_KEEP_0_128) + settlementDelta) <= MASK_KEEP_0_128, ICrystal.Overflow());
                    tokenBalances[userId][token] += settlementDelta;
                } else { // External balance mode: transfer tokens
                    if (((options >> 60) & 1) != 0) {
                        require(((tokenBalances[0][token] & MASK_KEEP_0_128) + settlementDelta) <= MASK_KEEP_0_128, ICrystal.Overflow());
                        tokenBalances[0][token] += settlementDelta;
                    } else {
                        IERC20(token).transfer(msg.sender, settlementDelta);
                    }
                }
            }
            address _market = market;
            assembly {
                let length := mload(0xe0)
                if gt(length, 0) {
                    mstore(0xc0, 0x20)
                    log3(0xc0, add(length, 0x40), ORDERS_UPDATED_SIG, _market, user)
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
        unchecked { // Options encoding: 0-41 userId, 44-54 cloid, 56-60 fromInternal, 60-64 useInternal
            uint256 userId = (options & MASK_KEEP_0_41);
            if (userId != 0) { // Verify provided userId matches caller
                require(userIdToAddress[userId] == user, ICrystal.Unauthorized(msg.sender));
            } else { // Retrieve or create userId for caller
                userId = addressToUserId[user];
                if (userId == 0) {
                    userId = ICrystal(crystal).registerUser(user);
                }
            }
            bool useExternalBalances = (((options >> 60) & 1) == 0);
            (size, id) = _limitOrder(isBuy, useExternalBalances, price, size, userId, (options >> 44) & MASK_KEEP_0_10); // Ensure cloid is uint10
            require(size != 0, ICrystal.ActionFailed());
            address token = isBuy ? quoteAsset : baseAsset;
            if (useExternalBalances) {
                if (((options >> 56) & 1) != 0) {
                    uint256 balance = tokenBalances[0][token];
                    require(uint128(balance) >= size, ICrystal.ActionFailed());
                    tokenBalances[0][token] = balance - size;
                } else {
                    IERC20(token).transferFrom(msg.sender, address(this), size);
                }
            } else {
                uint256 balance = tokenBalances[userId][token];
                require(uint128(balance) >= size, ICrystal.ActionFailed());
                tokenBalances[userId][token] = balance - size; // Direct debit; locking handled in internal function
            }
            emit ICrystal.OrdersUpdated(market, user, abi.encodePacked((isBuy ? LEADING_HEX_2 : LEADING_HEX_3) | (price << 168) | (id << 112) | size)); // Cloid already encoded with userId when applicable
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
        unchecked { // Options encoding: 0-41 userId, 44-48 toInternal, 48-52 useInternal
            bool isBuy;
            uint256 userId = (options & MASK_KEEP_0_41);
            if (userId != 0) { // Verify provided userId matches caller
                require(userIdToAddress[userId] == user, ICrystal.Unauthorized(msg.sender));
            } else { // Retrieve or create userId for caller
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
                        require(((tokenBalances[0][token] & MASK_KEEP_0_128) + size) <= MASK_KEEP_0_128, ICrystal.Overflow());
                        tokenBalances[0][token] += size;
                    } else {
                        IERC20(token).transfer(msg.sender, size);
                    }
                } else {
                    require(((tokenBalances[userId][token] & MASK_KEEP_0_128) + size) <= MASK_KEEP_0_128, ICrystal.Overflow());
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
     * @param newPrice New price.
     * @param size New size (0 to reuse previous size).
     * @param referrer Referrer address for fee sharing.
     * @param user Order owner.
     *
     * @return _id Identifier of the replacement order, or 0 if none.
     */
    function replaceOrder(uint256 options, uint256 price, uint256 id, uint256 newPrice, uint256 size, address referrer, address user) external payable returns (uint256 _id) {
        unchecked { // Options encoding: 0-41 userId, 44-48 postOnly, 48-52 isDecrease, 52-56 toInternal, 56-60 fromInternal, 60-64 useInternal
            int256 quoteAssetDebt;
            int256 baseAssetDebt;
            uint256 userId = (options & MASK_KEEP_0_41);
            if (userId != 0) { // Verify provided userId matches caller
                require(userIdToAddress[userId] == user, ICrystal.Unauthorized(msg.sender));
            } else { // Retrieve or create userId for caller
                userId = addressToUserId[user];
                if (userId == 0) {
                    userId = ICrystal(crystal).registerUser(user);
                }
                options = (options & MASK_OUT_0_41) | userId; // Embed userId in options
            }
            options = (uint256(uint160(user)) << 96) | (options & MASK_KEEP_0_96);
            assembly {
                mstore(0xc0, referrer)
                mstore(0x40, 0x100) // Reserve memory; 0x80 used internally by _marketOrder
            }
            (quoteAssetDebt, baseAssetDebt, _id) = _replaceOrder(options, price, id, newPrice, size);
            uint256 balanceMode = options; // Avoid stack too deep
            _settleBalances(quoteAssetDebt, baseAssetDebt, userId, ((balanceMode >> 60) & 1), ((balanceMode >> 52) & 1), ((balanceMode >> 56) & 1));
            address _market = market;
            assembly {
                let length := mload(0xe0)
                switch gt(length, 0)
                case true {
                    mstore(0xc0, 0x20)
                    log3(0xc0, add(length, 0x40), ORDERS_UPDATED_SIG, _market, user)
                }
                default {
                    revert(0, 0)
                }
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
        unchecked { // Options encoding: 0-41 userId, 44-48 toInternal, 48-52 fromInternal, 52-56 useInternal
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
            if ((options & MASK_KEEP_0_41) != 0) { // Verify provided userId matches caller
                userId = (options & MASK_KEEP_0_41);
                require(userIdToAddress[userId] == user, ICrystal.Unauthorized(msg.sender));
            } else { // Retrieve or create userId for caller
                userId = addressToUserId[user];
                if (userId == 0) {
                    userId = ICrystal(crystal).registerUser(user);
                }
            }
            balanceMode = ((options >> 52) & 1);
            assembly {
                mstore(0xc0, referrer)
                mstore(0x40, 0x100) // Reserve memory; 0x80 used internally by _marketOrder
            }
            while (offset < actions.length) { // An action with invalid parameters always reverts the full transaction
                require(actions[offset].action > 0 && actions[offset].action <= 12 && actions[offset].param1 <= MASK_KEEP_0_80 && actions[offset].param2 <= MASK_KEEP_0_112 && (((actions[offset].action & 0xF) == 12) || (actions[offset].param3 < 1024)), ICrystal.InvalidParams());
                action = actions[offset].action;
                param1 = actions[offset].param1;
                param2 = actions[offset].param2;
                cloid = actions[offset].param3;
                if (action == 1) { // Cancel order; parameters are price, id, and optionally cloid
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
                        require(!actions[offset].isRequireSuccess, ICrystal.ActionFailed());
                    }
                } else if (action == 2 || action == 3) { // Limit buy/sell order: parameters are price, size, and optionally cloid
                    (cloid, param2) = _limitOrder((action & 1) == 0, balanceMode == 0, param1, param2, userId, cloid);
                    if (cloid != 0) {
                        ((action & 1) == 0) ? quoteAssetDebt += int256(cloid) : baseAssetDebt += int256(cloid);
                        _addToOrdersUpdatedEvent((((action & 1) == 0) ? LEADING_HEX_2 : LEADING_HEX_3) | (param1 << 168) | (param2 << 112) | cloid); // Encoded: 8-bit flag | 80-bit price | 56-bit id | 112-bit size
                    } else {
                        require(!actions[offset].isRequireSuccess, ICrystal.ActionFailed());
                    }
                } else if (action > 3 && action < 12) { // Action codes: 4=MTL buy, 5=MTL sell, 6=partial buy, 7=partial sell, 8=partial buy (gas-aware), 9=partial sell (gas-aware), 10=complete buy, 11=complete sell
                    uint256 settlementDelta = (uint256((action < 6) ? 2 : (action < 8) ? 0 : (action < 10) ? 3 : 1) << 252) | ((action & 1 != 0) ? (1 << 244) : 0) | (1 << 240) | (balanceMode << 236) | (((options >> 48) & 1) << 232); // Avoid stack too deep
                    (, param1, , settlementDelta) = _marketOrder(param2, param1, settlementDelta | (cloid << 208) | (userId << 160) | uint160(user)); // Market orders through the batch order endpoint are always exact input
                    if (action & 1 != 0) {
                        baseAssetDebt += int256(settlementDelta >> 128);
                        quoteAssetDebt -= int256(param1 + (settlementDelta & MASK_KEEP_0_128)); // Safe: value bounded by uint128 intrinsic limit
                    } else {
                        quoteAssetDebt += int256(settlementDelta >> 128);
                        baseAssetDebt -= int256(param1 + (settlementDelta & MASK_KEEP_0_128)); // Safe: value bounded by uint128 intrinsic limit
                    }
                } else if (action == 12) { // Decrease order: use native id if price provided, otherwise use cloid
                    bool isCloid;
                    if (param1 != 0) { // Native id path as price is nonzero
                        require(cloid <= MASK_KEEP_0_41, ICrystal.InvalidParams()); // Param3/cloid variable represents the native order id, so uint41 instead of uint10
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
                        require(!actions[offset].isRequireSuccess, ICrystal.ActionFailed());
                    }
                }
                ++offset;
            }
            param1 = options; // Avoid stack too deep
            param2 = options; // Avoid stack too deep
            _settleBalances(quoteAssetDebt, baseAssetDebt, userId, balanceMode, ((param1 >> 44) & 1), ((param2 >> 48) & 1));
            address _market = market;
            assembly {
                let length := mload(0xe0)
                if gt(length, 0) {
                    mstore(0xc0, 0x20)
                    log3(0xc0, add(length, 0x40), ORDERS_UPDATED_SIG, _market, user)
                }
            }
        }
    }

    /**
     * @notice Adds the initial liquidity to a launchpad market's AMM (happens before regular trading starts).
     *
     * @dev Can only be called when the pool has no LP tokens yet.
     *
     * @param to Who gets the LP tokens.
     * @param amountQuoteDesired How much quote asset to add.
     * @param amountBaseDesired How much base asset to add.
     *
     * @return liquidity How many LP tokens were created.
     */
    function premint(address to, uint256 amountQuoteDesired, uint256 amountBaseDesired) external payable returns (uint256 liquidity) {
        ICrystal.Market storage m = _getMarket[market];
        liquidity = CM._sqrt(amountQuoteDesired * (amountBaseDesired));
        require(marketType == 3 && IERC20(market).totalSupply() == 0 && liquidity != 0 && amountQuoteDesired <= MASK_KEEP_0_112 && amountBaseDesired <= MASK_KEEP_0_112, ICrystal.InvalidParams());
        IERC20(market).mint(to, liquidity);
        (m.reserveQuote, m.reserveBase) = (uint112(amountQuoteDesired), uint112(amountBaseDesired));
    }

    /**
     * @notice Adds liquidity to the AMM and gets LP tokens in return.
     *
     * @dev The `options` parameter controls whether we pull funds directly from you or use the router's internal balance.
     *
     * @param to Who receives the LP tokens.
     * @param amountQuoteDesired How much quote asset you want to add.
     * @param amountBaseDesired How much base asset you want to add.
     * @param amountQuoteMin Minimum quote asset you'll accept (slippage protection).
     * @param amountBaseMin Minimum base asset you'll accept (slippage protection).
     * @param options Bit flags controlling where quote and base tokens come from.
     *
     * @return liquidity How many LP tokens you got.
     */
    function addLiquidity(address to, uint256 amountQuoteDesired, uint256 amountBaseDesired, uint256 amountQuoteMin, uint256 amountBaseMin, uint256 options) external payable returns (uint256 liquidity) {
        ICrystal.Market storage m = _getMarket[market];
        (uint256 reserveQuote, uint256 reserveBase) = (m.reserveQuote, m.reserveBase);
        uint256 amountQuote;
        uint256 amountBase;
        uint256 totalSupply = IERC20(market).totalSupply();
        if (totalSupply == 0) {
            amountQuote = amountQuoteDesired;
            amountBase = amountBaseDesired;
        } else {
            uint256 amountBaseOptimal = (amountQuoteDesired * reserveBase) / reserveQuote;
            if (amountBaseOptimal <= amountBaseDesired) {
                amountQuote = amountQuoteDesired;
                amountBase = amountBaseOptimal;
            } else {
                uint256 amountQuoteOptimal = (amountBaseDesired * reserveQuote) / reserveBase;
                amountQuote = amountQuoteOptimal;
                amountBase = amountBaseDesired;
            }
        }
        reserveQuote += amountQuote;
        reserveBase += amountBase;
        require(reserveQuote != 0 && reserveBase != 0 && m.isAMMEnabled == true, ICrystal.SlippageExceeded());
        {
            uint256 ammAsk = ((reserveQuote * scaleFactor * 10000 * 100000 + (reserveBase * 9975 * uint256(m.makerRebate) - 1)) / (reserveBase * 9975 * uint256(m.makerRebate)));
            uint256 ammBid = ((reserveQuote * scaleFactor * 9975 * uint256(m.makerRebate)) / (reserveBase * 10000 * 100000));
            if (m.highestBid > ammAsk) {
                uint256 newReserveBase = (reserveQuote * scaleFactor * 10000 * 100000 - 1) / ((uint256(m.highestBid) - 1) * 9975 * uint256(m.makerRebate));
                ammBid = ((reserveQuote * scaleFactor * 9975 * uint256(m.makerRebate)) / (newReserveBase * 10000 * 100000));
                require(reserveBase - newReserveBase <= amountBase && m.lowestAsk >= ammBid, ICrystal.SlippageExceeded());
                amountBase -= (reserveBase - newReserveBase);
                reserveBase = newReserveBase;
            } else if (m.lowestAsk < ammBid) {
                uint256 newReserveQuote = ((uint256(m.lowestAsk) + 1) * reserveBase * 10000 * 100000 - 1) / (scaleFactor * 9975 * uint256(m.makerRebate));
                ammAsk = ((newReserveQuote * scaleFactor * 10000 * 100000 + (reserveBase * 9975 * uint256(m.makerRebate) - 1)) / (reserveBase * 9975 * uint256(m.makerRebate)));
                require(reserveQuote - newReserveQuote <= amountQuote && m.highestBid <= ammAsk, ICrystal.SlippageExceeded());
                amountQuote -= (reserveQuote - newReserveQuote);
                reserveQuote = newReserveQuote;
            }
        }
        if (totalSupply == 0) {
            liquidity = CM._sqrt(amountQuote * (amountBase)) - 1000;
            IERC20(market).mint(address(0), 1000);
        } else {
            uint256 liquidityIfQuote = (amountQuote * totalSupply) / (reserveQuote - amountQuote);
            uint256 liquidityIfBase = (amountBase * totalSupply) / (reserveBase - amountBase);
            liquidity = CM._min(liquidityIfQuote, liquidityIfBase);
        }
        require(liquidity != 0 && amountQuote >= amountQuoteMin && amountBase >= amountBaseMin && reserveQuote <= MASK_KEEP_0_112 && reserveBase <= MASK_KEEP_0_112, ICrystal.SlippageExceeded());
        (m.reserveQuote, m.reserveBase) = (uint112(reserveQuote), uint112(reserveBase));
        IERC20(market).mint(to, liquidity);
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
        emit ICrystal.Sync(market, uint112(reserveQuote), uint112(reserveBase));
        emit ICrystal.Mint(market, msg.sender, amountQuote, amountBase);
    }

    /**
     * @notice Burns LP tokens to withdraw your share of the AMM pool.
     *
     * @dev The `options` parameter controls whether we send tokens to you directly or credit your internal balance.
     *
     * @param to Who gets the tokens if we're sending them externally.
     * @param liquidity How many LP tokens to burn.
     * @param amountQuoteMin Minimum quote asset you'll accept (slippage protection).
     * @param amountBaseMin Minimum base asset you'll accept (slippage protection).
     * @param options Bit flags controlling where quote and base tokens go.
     *
     * @return amountQuote Quote asset you received.
     * @return amountBase Base asset you received.
     */
    function removeLiquidity(address to, uint256 liquidity, uint256 amountQuoteMin, uint256 amountBaseMin, uint256 options) external payable returns (uint256 amountQuote, uint256 amountBase) {
        ICrystal.Market storage m = _getMarket[market];
        uint256 totalSupply = IERC20(market).totalSupply();
        (uint256 reserveQuote, uint256 reserveBase) = (m.reserveQuote, m.reserveBase);
        IERC20(market).transferFrom(msg.sender, address(this), liquidity);
        IERC20(market).burn(address(this), liquidity);
        amountQuote = (liquidity * reserveQuote) / totalSupply;
        amountBase = (liquidity * reserveBase) / totalSupply;
        reserveQuote -= uint112(amountQuote);
        reserveBase -= uint112(amountBase);
        if (m.isAMMEnabled) {
            uint256 ammAsk = ((reserveQuote * scaleFactor * 10000 * 100000 + (reserveBase * 9975 * uint256(m.makerRebate) - 1)) / (reserveBase * 9975 * uint256(m.makerRebate)));
            uint256 ammBid = ((reserveQuote * scaleFactor * 9975 * uint256(m.makerRebate)) / (reserveBase * 10000 * 100000));
            if (m.highestBid > ammAsk) {
                uint256 newReserveQuote = (((uint256(m.highestBid) - 1) * reserveBase * 9975 * uint256(m.makerRebate)) / (scaleFactor * 10000 * 100000)) + 1;
                ammBid = ((newReserveQuote * scaleFactor * 9975 * uint256(m.makerRebate)) / (reserveBase * 10000 * 100000));
                require(newReserveQuote - reserveQuote <= amountQuote && m.lowestAsk >= ammBid, ICrystal.SlippageExceeded());
                amountQuote -= (newReserveQuote - reserveQuote);
                reserveQuote = newReserveQuote;
            } else if (m.lowestAsk < ammBid) {
                uint256 newReserveBase = ((reserveQuote * scaleFactor * 9975 * uint256(m.makerRebate)) / ((uint256(m.lowestAsk) + 1) * 10000 * 100000)) + 1;
                ammAsk = ((reserveQuote * scaleFactor * 10000 * 100000 + (newReserveBase * 9975 * uint256(m.makerRebate) - 1)) / (newReserveBase * 9975 * uint256(m.makerRebate)));
                require(newReserveBase - reserveBase <= amountBase && m.highestBid <= ammAsk, ICrystal.SlippageExceeded());
                amountBase -= (newReserveBase - reserveBase);
                reserveBase = newReserveBase;
            }
        }
        require(amountQuote >= amountQuoteMin && amountBase >= amountBaseMin, ICrystal.SlippageExceeded());
        (m.reserveQuote, m.reserveBase) = (uint112(reserveQuote), uint112(reserveBase));
        if ((options & 1) == 0) {
            IERC20(quoteAsset).transfer(to, amountQuote);
        } else {
            require(((tokenBalances[0][quoteAsset] & MASK_KEEP_0_128) + amountQuote) <= MASK_KEEP_0_128, ICrystal.Overflow());
            tokenBalances[0][quoteAsset] += amountQuote;
        }
        if (((options >> 4) & 1) == 0) {
            IERC20(baseAsset).transfer(to, amountBase);
        } else {
            require(((tokenBalances[0][baseAsset] & MASK_KEEP_0_128) + amountBase) <= MASK_KEEP_0_128, ICrystal.Overflow());
            tokenBalances[0][baseAsset] += amountBase;
        }
        emit ICrystal.Sync(market, uint112(reserveQuote), uint112(reserveBase));
        emit ICrystal.Burn(market, msg.sender, amountQuote, amountBase, to);
    }

    /**
     * @notice Market maker endpoint for executing batch actions supplied via calldata.
     *
     * @dev The first 32-byte word carries the userId and action count; subsequent words consist of 32-byte actions. `userId` is already validated.
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
                mstore(0xc0, caller())
                mstore(0x40, 0x100) // Reserve memory; 0x80 used internally by _marketOrder
                userId := calldataload(offset)
                balanceMode := shr(44, userId)
                userId := and(MASK_KEEP_0_41, userId) // Extract uint41 userId from uint44 encoding
            }
            offset += 32;
            while (offset < msg.data.length) {
                assembly { // Bits 4-8 encode isRequireSuccess flag
                    action := calldataload(offset)
                    param1 := and(MASK_KEEP_0_80, shr(112, action)) // Extract bits 64-144
                    param2 := and(MASK_KEEP_0_112, action) // Extract bits 144-256
                    cloid := and(MASK_KEEP_0_10, shr(192, action)) // Extract cloid from bits 54-64
                    action := shr(252, action) // Extract action code from bits 0-4
                }
                if (action == 0 || action > 12) { // If invalid action and action must succeed, revert
                    assembly { // Reuse isBuy variable for isRequireSuccess flag
                        isBuy := and(0x1, shr(248, calldataload(offset))) // Extract bit 4-8
                    }
                    require(!isBuy, ICrystal.ActionFailed());
                }
                if (action == 1) { // Cancel order: accepts price + id or cloid
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
                        assembly { // Reuse isBuy variable for isRequireSuccess flag
                            isBuy := and(0x1, shr(248, calldataload(offset))) // Extract bit 4-8
                        }
                        require(!isBuy, ICrystal.ActionFailed());
                    }
                } else if (action == 2 || action == 3) { // Limit buy order: requires price, size; optional cloid
                    (cloid, param2) = _limitOrder((action & 1) == 0, balanceMode == 0, param1, param2, userId, cloid);
                    if (cloid != 0) {
                        ((action & 1) == 0) ? quoteAssetDebt += int256(cloid) : baseAssetDebt += int256(cloid);
                        _addToOrdersUpdatedEvent((((action & 1) == 0) ? LEADING_HEX_2 : LEADING_HEX_3) | (param1 << 168) | (param2 << 112) | cloid); // Encoded: 8-bit flag | 80-bit price | 56-bit id | 112-bit size
                    } else {
                        assembly { // Reuse isBuy variable for isRequireSuccess flag
                            isBuy := and(0x1, shr(248, calldataload(offset))) // Extract bit 4-8
                        }
                        require(!isBuy, ICrystal.ActionFailed());
                    }
                } else if (action > 3 && action < 12) { // Action codes: 4=MTL buy, 5=MTL sell, 6=partial buy, 7=partial sell, 8=partial buy (gas-aware), 9=partial sell (gas-aware), 10=complete buy, 11=complete sell
                    uint256 settlementDelta;
                    {
                        uint256 stp;
                        assembly {
                            stp := and(0x3, shr(248, calldataload(offset))) // Extract STP mode from bits 7-8
                        }
                        if (stp == 0) {
                            stp = 1; // STP mode of 0 is invalid in the fallback, default to 1
                        }
                        settlementDelta = (uint256((action < 6) ? 2 : (action < 8) ? 0 : (action < 10) ? 3 : 1) << 252) | (((action & 1) != 0) ? (1 << 244) : 0) | (stp << 240) | (balanceMode << 236); // Avoid stack too deep
                    }
                    (, param1, , settlementDelta) = _marketOrder(param2, param1, settlementDelta | (1 << 240) | (balanceMode << 236) | (cloid << 208) | (userId << 160) | uint160(msg.sender));
                    if (action & 1 != 0) { // Sell order settlement
                        baseAssetDebt += int256(settlementDelta >> 128);
                        quoteAssetDebt -= int256(param1 + (settlementDelta & MASK_KEEP_0_128)); // Safe: value bounded by uint128 intrinsic limit
                    } else { // Buy order settlement
                        quoteAssetDebt += int256(settlementDelta >> 128);
                        baseAssetDebt -= int256(param1 + (settlementDelta & MASK_KEEP_0_128)); // Safe: value bounded by uint128 intrinsic limit
                    }
                } else if (action == 12) { // Decrease order: use cloid if price provided, otherwise use id
                    bool isCloid;
                    if (param1 != 0) { // Price provided: use native order ID
                        assembly {
                            cloid := and(MASK_KEEP_0_41, shr(192, calldataload(offset))) // Extract uint41 order ID from bits 23-64
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
                        assembly { // Reuse isBuy variable for isRequireSuccess flag
                            isBuy := and(0x1, shr(248, calldataload(offset))) // Extract bit 4-8
                        }
                        require(!isBuy, ICrystal.ActionFailed());
                    }
                }
                offset += 32;
            }
            _settleBalances(quoteAssetDebt, baseAssetDebt, userId, balanceMode, 0, 0);
            address _market = market;
            assembly {
                let length := mload(0xe0)
                if gt(length, 0) {
                    mstore(0xc0, 0x20)
                    log3(0xc0, add(length, 0x40), ORDERS_UPDATED_SIG, _market, caller())
                }
            }
        }
    }

    /**
     * @notice Accepts native token transfers.
     */
    receive() external payable {}
}
