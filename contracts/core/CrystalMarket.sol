// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "../interfaces/IERC20.sol";
import {ICrystal} from "../interfaces/ICrystal.sol";

/**
 * @title CrystalMarket
 * @author Crystal Labs
 *
 * @notice
 * Individual market implementation for the Crystal spot protocol.
 *
 * @dev
 * With the exception of the AMM liquidty being tokenized as an ERC-20, the majority of methods are to be delegatecalled by the Crystal contract and cannot be interacted with directly.
 */
contract CrystalMarket {
    /// @notice Address receiving trading fees.
    address private feeRecipient; // public is useless so everything isn't

    /// @notice Commission percentage for referrals.
    uint8 private feeCommission;

    /// @notice Mapping from user id to address (0 is invalid).
    mapping(uint256 => address) private userIdToAddress; // 0 is an invalid userid

    /// @notice Mapping from address to user id.
    mapping(address => uint256) private addressToUserId;

    /// @notice Market configuration keyed by market address.
    mapping(address => ICrystal.Market) private _getMarket;

    /// @notice Activated price bitmaps for ticks.
    mapping(uint256 => uint256) private activated; // marketid << 128 | slotindex

    /// @notice Secondary activated bitmap for higher-level aggregation.
    mapping(uint256 => uint256) private activated2; // marketid << 128 | slotindex

    /// @notice Aggregate liquidity per price level.
    mapping(uint256 => uint256) private priceLevels; // 0 is an invalid price marketid << 128 | price

    /// @notice Order storage keyed by market+price+id or user+cloid.
    mapping(uint256 => uint256) private orders; // 0 is an invalid cloid, valid range 1-1023 mask 0x3FF; marketid << 128 | price << 48 | id or userid << 41 | cloid

    /// @notice Mapping to verify cloid market/price associations.
    mapping(uint256 => uint256) private cloidVerify; // two cloids per slot map market and price, never zero slot 1 << 255 | marketId << 208 | price << 128 | marketId << 80 | price

    /// @notice Internal token balances for router and users.
    mapping(uint256 => mapping(address => uint256)) private tokenBalances;

    /// @notice Claimable fee balances per token and user.
    mapping(address => mapping(address => uint256)) private claimableRewards;

    /// @notice Quote asset token address.
    address public immutable quoteAsset;

    /// @notice Base asset token address.
    address public immutable baseAsset;

    /// @notice Crystal core contract address.
    address public immutable crystal;

    /// @notice Market type identifier.
    uint256 public immutable marketType;

    /// @notice Market scale factor.
    uint256 public immutable scaleFactor;

    /// @notice Tick size for this market.
    uint256 public immutable tickSize;

    /// @notice Maximum price supported by this market.
    uint256 public immutable maxPrice;

    /// @notice Address of the market when delegatecalled.
    address private immutable market; // address of market for when delegate called

    /// @notice Market id (already shifted left 128 bits).
    uint256 private immutable marketId; // 0 is an invalid marketid, is already << 128

    // lp erc20
    /// @notice LP token name.
    string public constant name = "Crystal V2";

    /// @notice LP token symbol.
    string public constant symbol = "CRY-V2";

    /// @notice LP token decimals.
    uint8 public constant decimals = 18;

    /// @notice Total LP token supply.
    uint256 public totalSupply;

    /// @notice LP token balances.
    mapping(address => uint256) public balanceOf;

    /// @notice LP token allowances.
    mapping(address => mapping(address => uint256)) public allowance;

    /// @notice EIP-712 domain separator for permits.
    bytes32 public DOMAIN_SEPARATOR;
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH =
        0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint256) public nonces;

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
    event Transfer(address indexed from, address indexed to, uint256 value);

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
     * @notice Initializes market configuration from the Crystal core contract.
     *
     * @dev Called during deployment to cache parameters and the permit domain separator.
     */
    constructor() {
        (
            quoteAsset,
            baseAsset,
            marketId,
            marketType,
            scaleFactor,
            tickSize,
            maxPrice
        ) = ICrystal(msg.sender).parameters();
        marketId <<= 128;
        scaleFactor = 10 ** scaleFactor;
        market = address(this);
        crystal = msg.sender;
        require(
            quoteAsset != address(0) &&
                baseAsset != address(0) &&
                quoteAsset != baseAsset &&
                maxPrice <= MASK_KEEP_0_80 &&
                tickSize <= MASK_KEEP_0_80 &&
                scaleFactor <= MASK_KEEP_0_112
        );
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes(name)),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );
    }

    /**
     * @notice Internal helper to set ERC20 allowance.
     *
     * @param owner Token owner granting allowance.
     * @param spender Spender address.
     * @param value Allowance amount.
     */
    function _approve(address owner, address spender, uint256 value) internal {
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    /**
     * @notice Internal helper to transfer LP tokens.
     *
     * @param from Sender address.
     * @param to Recipient address.
     * @param value Amount to transfer.
     */
    function _transfer(address from, address to, uint256 value) internal {
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
    }

    /**
     * @notice Mints LP tokens to a recipient.
     *
     * @dev Only callable by the Crystal core contract.
     *
     * @param to Recipient address.
     * @param value Amount to mint.
     */
    function mint(address to, uint256 value) external {
        require(msg.sender == crystal);
        totalSupply += value;
        balanceOf[to] += value;
        emit Transfer(address(0), to, value);
    }

    /**
     * @notice Burns LP tokens from a holder.
     *
     * @dev Only callable by the Crystal core contract.
     *
     * @param from Address whose tokens are burned.
     * @param value Amount to burn.
     */
    function burn(address from, uint256 value) external {
        require(msg.sender == crystal);
        balanceOf[from] -= value;
        totalSupply -= value;
        emit Transfer(from, address(0), value);
    }

    /**
     * @notice Approves a spender for LP tokens.
     *
     * @param spender Spender address.
     * @param value Allowance amount.
     *
     * @return success True if approval succeeded.
     */
    function approve(address spender, uint256 value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    /**
     * @notice Transfers LP tokens.
     *
     * @param to Recipient address.
     * @param value Amount to transfer.
     *
     * @return success True if transfer succeeded.
     */
    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    /**
     * @notice Transfers LP tokens using an allowance.
     *
     * @dev Calls from the core contract or with infinite allowance bypass allowance reduction.
     *
     * @param from Source address.
     * @param to Recipient address.
     * @param value Amount to transfer.
     *
     * @return success True if transfer succeeded.
     */
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool) {
        if (
            allowance[from][msg.sender] != type(uint256).max &&
            msg.sender != crystal
        ) {
            allowance[from][msg.sender] -= value;
        }
        _transfer(from, to, value);
        return true;
    }

    /**
     * @notice Approves via an EIP-2612 signature.
     *
     * @param owner Token owner.
     * @param spender Spender address.
     * @param value Allowance amount.
     * @param deadline Signature expiration timestamp.
     * @param v Signature v value.
     * @param r Signature r value.
     * @param s Signature s value.
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(deadline >= block.timestamp, "expired");
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        PERMIT_TYPEHASH,
                        owner,
                        spender,
                        value,
                        nonces[owner]++,
                        deadline
                    )
                )
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(
            recoveredAddress != address(0) && recoveredAddress == owner,
            "invalid signature"
        );
        _approve(owner, spender, value);
    }

    // ===================================================================================================
    // Above methods are part of the ERC-20 implementation and are to be called directly.
    // Below methods are to be delegatecalled by the Crystal contract and cannot be interacted with.
    // ===================================================================================================

    /**
     * @notice Returns current AMM reserves for the market.
     *
     * @dev Called through delegatecall by the Crystal core contract.
     *
     * @return reserveQuote Quote asset reserve.
     * @return reserveBase Base asset reserve.
     */
    function getReserves()
        external
        payable
        returns (uint112 reserveQuote, uint112 reserveBase)
    {
        ICrystal.Market storage m = _getMarket[market];
        (reserveQuote, reserveBase) = (m.reserveQuote, m.reserveBase);
    }

    /**
     * @notice Seeds launchpad AMM liquidity before normal interaction begins.
     *
     * @dev Only callable while total supply is zero.
     *
     * @param to Recipient of liquidity tokens.
     * @param amountQuoteDesired Quote asset amount to deposit.
     * @param amountBaseDesired Base asset amount to deposit.
     *
     * @return liquidity Liquidity tokens minted.
     */
    function premint(
        address to,
        uint256 amountQuoteDesired,
        uint256 amountBaseDesired
    ) external payable returns (uint256 liquidity) {
        ICrystal.Market storage m = _getMarket[market];
        liquidity = _sqrt(amountQuoteDesired * (amountBaseDesired));
        require(
            marketType == 3 &&
                IERC20(market).totalSupply() == 0 &&
                liquidity != 0 &&
                amountQuoteDesired <= MASK_KEEP_0_112 &&
                amountBaseDesired <= MASK_KEEP_0_112
        );
        IERC20(market).mint(to, liquidity);
        (m.reserveQuote, m.reserveBase) = (
            uint112(amountQuoteDesired),
            uint112(amountBaseDesired)
        );
    }

    /**
     * @notice Adds liquidity to the AMM and mints LP tokens.
     *
     * @dev `options` toggles whether quote/base funds are pulled from the caller or internal router balances.
     *
     * @param to Recipient of LP tokens.
     * @param amountQuoteDesired Desired quote asset amount.
     * @param amountBaseDesired Desired base asset amount.
     * @param amountQuoteMin Minimum quote accepted.
     * @param amountBaseMin Minimum base accepted.
     * @param options Source flags for quote and base transfers.
     *
     * @return liquidity Liquidity tokens minted.
     */
    function addLiquidity(
        address to,
        uint256 amountQuoteDesired,
        uint256 amountBaseDesired,
        uint256 amountQuoteMin,
        uint256 amountBaseMin,
        uint256 options
    ) external payable returns (uint256 liquidity) {
        ICrystal.Market storage m = _getMarket[market];
        (uint256 reserveQuote, uint256 reserveBase) = (
            m.reserveQuote,
            m.reserveBase
        );
        uint256 amountQuote;
        uint256 amountBase;
        uint256 _totalSupply = IERC20(market).totalSupply();
        if (_totalSupply == 0) {
            amountQuote = amountQuoteDesired;
            amountBase = amountBaseDesired;
            liquidity = _sqrt(amountQuote * (amountBase)) - 100000;
            IERC20(market).mint(address(0), 100000);
            require(
                m.highestBid <=
                    ((amountQuote *
                        scaleFactor *
                        10000 *
                        uint256(m.makerRebate) +
                        (amountBase * 9975 * 100000 - 1)) /
                        (amountBase * 9975 * 100000)) &&
                    m.lowestAsk >=
                    ((amountQuote * scaleFactor * 9975 * 100000) /
                        (amountBase * 10000 * uint256(m.makerRebate)))
            );
        } else {
            uint256 amountBaseOptimal = (amountQuoteDesired * reserveBase) /
                reserveQuote;
            if (amountBaseOptimal <= amountBaseDesired) {
                amountQuote = amountQuoteDesired;
                amountBase = amountBaseOptimal;
            } else {
                uint256 amountQuoteOptimal = (amountBaseDesired *
                    reserveQuote) / reserveBase;
                require(amountQuoteOptimal <= amountQuoteDesired);
                amountQuote = amountQuoteOptimal;
                amountBase = amountBaseDesired;
            }
            liquidity = (amountQuote * (_totalSupply)) / reserveQuote <
                (amountBase * (_totalSupply)) / reserveBase
                ? (amountQuote * (_totalSupply)) / reserveQuote
                : (amountBase * (_totalSupply)) / reserveBase;
        }
        reserveQuote += amountQuote;
        reserveBase += amountBase;
        if ((options & 1) == 0) {
            IERC20(quoteAsset).transferFrom(
                msg.sender,
                address(this),
                amountQuote
            );
        } else {
            tokenBalances[0][quoteAsset] -= amountQuote; // checked
        }
        if (((options >> 4) & 1) == 0) {
            IERC20(baseAsset).transferFrom(
                msg.sender,
                address(this),
                amountBase
            );
        } else {
            tokenBalances[0][baseAsset] -= amountBase; // checked
        }
        IERC20(market).mint(to, liquidity);
        require(
            liquidity != 0 &&
                amountQuote >= amountQuoteMin &&
                amountBase >= amountBaseMin &&
                reserveQuote <= MASK_KEEP_0_112 &&
                reserveBase <= MASK_KEEP_0_112 &&
                m.isAMMEnabled == true
        );
        (m.reserveQuote, m.reserveBase) = (
            uint112(reserveQuote),
            uint112(reserveBase)
        );
        emit ICrystal.Sync(market, uint112(reserveQuote), uint112(reserveBase));
        emit ICrystal.Mint(market, msg.sender, amountQuote, amountBase);
    }

    /**
     * @notice Burns LP tokens to withdraw AMM liquidity.
     *
     * @dev `options` controls whether withdrawn funds are transferred externally or credited to internal balances.
     *
     * @param to Recipient address when sending tokens externally.
     * @param liquidity LP tokens to burn.
     * @param amountQuoteMin Minimum quote expected.
     * @param amountBaseMin Minimum base expected.
     * @param options Destination flags for quote and base transfers.
     *
     * @return amountQuote Quote asset returned.
     * @return amountBase Base asset returned.
     */
    function removeLiquidity(
        address to,
        uint256 liquidity,
        uint256 amountQuoteMin,
        uint256 amountBaseMin,
        uint256 options
    ) external payable returns (uint256 amountQuote, uint256 amountBase) {
        ICrystal.Market storage m = _getMarket[market];
        (uint256 reserveQuote, uint256 reserveBase) = (
            m.reserveQuote,
            m.reserveBase
        );
        IERC20(market).transferFrom(msg.sender, address(this), liquidity);

        uint256 _totalSupply = IERC20(market).totalSupply();
        amountQuote = (liquidity * reserveQuote) / _totalSupply;
        amountBase = (liquidity * reserveBase) / _totalSupply;
        IERC20(market).burn(address(this), liquidity);
        if ((options & 1) == 0) {
            IERC20(quoteAsset).transfer(to, amountQuote);
        } else {
            require(
                ((tokenBalances[0][quoteAsset] & MASK_KEEP_0_128) +
                    amountQuote) <= MASK_KEEP_0_128
            );
            tokenBalances[0][quoteAsset] += amountQuote;
        }
        if (((options >> 4) & 1) == 0) {
            IERC20(baseAsset).transfer(to, amountBase);
        } else {
            require(
                ((tokenBalances[0][baseAsset] & MASK_KEEP_0_128) +
                    amountBase) <= MASK_KEEP_0_128
            );
            tokenBalances[0][baseAsset] += amountBase;
        }
        reserveQuote -= uint112(amountQuote); // checked
        reserveBase -= uint112(amountBase); // checked

        require(
            amountQuote >= amountQuoteMin &&
                amountBase >= amountBaseMin &&
                (m.isAMMEnabled == false ||
                    (m.highestBid <=
                        ((reserveQuote *
                            scaleFactor *
                            10000 *
                            uint256(m.makerRebate) +
                            (reserveBase * 9975 * 100000 - 1)) /
                            (reserveBase * 9975 * 100000)) &&
                        m.lowestAsk >=
                        ((reserveQuote * scaleFactor * 9975 * 100000) /
                            (reserveBase * 10000 * uint256(m.makerRebate)))))
        );
        (m.reserveQuote, m.reserveBase) = (
            uint112(reserveQuote),
            uint112(reserveBase)
        );
        emit ICrystal.Sync(market, uint112(reserveQuote), uint112(reserveBase));
        emit ICrystal.Burn(market, msg.sender, amountQuote, amountBase, to);
    }

    /**
     * @notice Computes the integer square root of a value.
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
     * @notice Converts a tick index to its corresponding price.
     *
     * @param t Tick index.
     *
     * @return Price value derived from the tick.
     */
    function _tickToPrice(uint256 t) internal view returns (uint256) {
        unchecked {
            if (t <= 100_000) return t * tickSize;
            uint256 x = t - 10_000;
            return 10 ** (x / 90_000) * (10_000 + (x % 90_000)) * tickSize;
        }
    }

    /**
     * @notice Converts a price to its tick index.
     *
     * @dev Reverts if the price is not aligned to the allowable grid for its range.
     *
     * @param p Price value.
     *
     * @return Tick index for the price.
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
     * @notice Rounds a price to the nearest valid grid value.
     *
     * @param p Raw price.
     * @param roundUp Whether to round up (true) or down (false).
     *
     * @return Price snapped to the valid grid.
     */
    function _toValidPrice(
        uint256 p,
        bool roundUp
    ) internal pure returns (uint256) {
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
     * @notice Finds the next active tick above the provided position within a bitmap slot.
     *
     * @param slot Bitmap of active ticks.
     * @param tick Starting tick.
     *
     * @return Next active tick index.
     */
    function _searchSlotUp(
        uint256 slot,
        uint256 tick
    ) internal pure returns (uint256) {
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
     * @notice Finds the previous active tick at or below the provided position within a bitmap slot.
     *
     * @param slot Bitmap of active ticks.
     * @param tick Starting tick.
     *
     * @return Previous active tick index.
     */
    function _searchSlotDown(
        uint256 slot,
        uint256 tick
    ) internal pure returns (uint256) {
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
     * @notice Solves for quote input needed in a buy to reach a target execution price.
     *
     * @dev Uses binary search over the input size bound by `high`.
     *
     * @param reserveQuote Current quote reserve.
     * @param reserveBase Current base reserve.
     * @param targetPrice Target execution price.
     * @param _scaleFactor Market scale factor.
     * @param makerRebate Maker rebate used in pricing.
     * @param high Upper bound for input search.
     *
     * @return low Minimum input amount that reaches the target price.
     */
    function _exactInputBuySolve(
        uint256 reserveQuote,
        uint256 reserveBase,
        uint256 targetPrice,
        uint256 _scaleFactor,
        uint256 makerRebate,
        uint256 high
    ) internal pure returns (uint256 low) {
        unchecked {
            while (low < high) {
                uint256 mid = (low + high) >> 1;
                uint256 den = 9975 *
                    (reserveBase -
                        ((mid * 9975 * reserveBase) /
                            (reserveQuote * 10000 + mid * 9975)));
                uint256 num = (reserveQuote + mid) * 10000;
                uint256 pMid = (num *
                    _scaleFactor *
                    makerRebate +
                    ((den * 100000) - 1)) / (den * 100000);
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
     * @notice Solves for base output in a buy while respecting a target price.
     *
     * @dev Performs a binary search over the output amount bounded by `high`.
     *
     * @param reserveQuote Current quote reserve.
     * @param reserveBase Current base reserve.
     * @param targetPrice Target execution price.
     * @param _scaleFactor Market scale factor.
     * @param makerRebate Maker rebate used in pricing.
     * @param high Upper bound for output search.
     *
     * @return low Minimum output amount that reaches the target price.
     */
    function _exactOutputBuySolve(
        uint256 reserveQuote,
        uint256 reserveBase,
        uint256 targetPrice,
        uint256 _scaleFactor,
        uint256 makerRebate,
        uint256 high
    ) internal pure returns (uint256 low) {
        unchecked {
            high = high > (reserveBase - 1) ? (reserveBase - 1) : high;
            while (low < high) {
                uint256 mid = (low + high) >> 1;
                uint256 num = (reserveQuote +
                    ((mid * reserveQuote * 10000) /
                        ((reserveBase - mid) * 9975)) +
                    1) * 10000;
                uint256 den = 9975 * (reserveBase - mid);
                uint256 pMid = (num *
                    _scaleFactor *
                    makerRebate +
                    ((den * 100000) - 1)) / (den * 100000);
                if (pMid > targetPrice) {
                    high = mid;
                } else {
                    low = mid + 1;
                }
            }
        }
    }

    /**
     * @notice Solves for base input needed in a sell to reach a target execution price.
     *
     * @dev Uses binary search over the input size bound by `high`.
     *
     * @param reserveQuote Current quote reserve.
     * @param reserveBase Current base reserve.
     * @param targetPrice Target execution price.
     * @param _scaleFactor Market scale factor.
     * @param makerRebate Maker rebate used in pricing.
     * @param high Upper bound for input search.
     *
     * @return low Minimum input amount that reaches the target price.
     */
    function _exactInputSellSolve(
        uint256 reserveQuote,
        uint256 reserveBase,
        uint256 targetPrice,
        uint256 _scaleFactor,
        uint256 makerRebate,
        uint256 high
    ) internal pure returns (uint256 low) {
        unchecked {
            while (low < high) {
                uint256 mid = (low + high) >> 1;
                uint256 num = 9975 *
                    (reserveQuote -
                        ((mid * 9975 * reserveQuote) /
                            (reserveBase * 10000 + mid * 9975)));
                uint256 den = (reserveBase + mid) * 10000;
                uint256 pMid = (num * _scaleFactor * 100000) /
                    (den * makerRebate);
                if (pMid < targetPrice) {
                    high = mid;
                } else {
                    low = mid + 1;
                }
            }
        }
    }

    /**
     * @notice Solves for quote output in a sell while respecting a target price.
     *
     * @dev Performs a binary search over the output amount bounded by `high`.
     *
     * @param reserveQuote Current quote reserve.
     * @param reserveBase Current base reserve.
     * @param targetPrice Target execution price.
     * @param _scaleFactor Market scale factor.
     * @param makerRebate Maker rebate used in pricing.
     * @param high Upper bound for output search.
     *
     * @return low Minimum output amount that reaches the target price.
     */
    function _exactOutputSellSolve(
        uint256 reserveQuote,
        uint256 reserveBase,
        uint256 targetPrice,
        uint256 _scaleFactor,
        uint256 makerRebate,
        uint256 high
    ) internal pure returns (uint256 low) {
        unchecked {
            high = high > (reserveQuote - 1) ? (reserveQuote - 1) : high;
            while (low < high) {
                uint256 mid = (low + high) >> 1;
                uint256 den = (reserveBase +
                    ((mid * reserveBase * 10000) /
                        ((reserveQuote - mid) * 9975)) +
                    1) * 10000;
                uint256 num = 9975 * (reserveQuote - mid);
                uint256 pMid = (num * _scaleFactor * 100000) /
                    (den * makerRebate);
                if (pMid < targetPrice) {
                    high = mid;
                } else {
                    low = mid + 1;
                }
            }
        }
    }

    /**
     * @notice Appends encoded order update data to the in-memory OrdersUpdated buffer.
     *
     * @param logData Encoded order update word to append.
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
     * @notice Settles token debits and credits using external transfers or internal balances.
     *
     * @dev `balanceMode`, `balanceModeOut`, and `balanceModeIn` route debits/credits to external transfers, the router balance, or user internal balances.
     *
     * @param quoteAssetDebt Net quote delta (positive = debit).
     * @param baseAssetDebt Net base delta (positive = debit).
     * @param userId User id for internal accounting.
     * @param balanceMode 0 for external transfers, 1 for internal balances.
     * @param balanceModeOut 0 sends outputs externally, 1 credits the router balance.
     * @param balanceModeIn 0 pulls from msg.sender, 1 pulls from the router balance.
     */
    function _settleBalances(
        int256 quoteAssetDebt,
        int256 baseAssetDebt,
        uint256 userId,
        uint256 balanceMode,
        uint256 balanceModeOut,
        uint256 balanceModeIn
    ) internal {
        unchecked {
            if (balanceMode == 0) {
                // external txfers
                if (balanceModeIn != 0) {
                    if (quoteAssetDebt > 0) {
                        uint256 balance = tokenBalances[0][quoteAsset];
                        if (uint128(balance) < uint256(quoteAssetDebt)) {
                            revert ICrystal.ActionFailed();
                        } else {
                            tokenBalances[0][quoteAsset] =
                                balance -
                                uint256(quoteAssetDebt);
                        }
                    }
                    if (baseAssetDebt > 0) {
                        uint256 balance = tokenBalances[0][baseAsset];
                        if (uint128(balance) < uint256(baseAssetDebt)) {
                            revert ICrystal.ActionFailed();
                        } else {
                            tokenBalances[0][baseAsset] =
                                balance -
                                uint256(baseAssetDebt);
                        }
                    }
                } else {
                    if (quoteAssetDebt > 0) {
                        IERC20(quoteAsset).transferFrom(
                            msg.sender,
                            address(this),
                            uint256(quoteAssetDebt)
                        );
                    }
                    if (baseAssetDebt > 0) {
                        IERC20(baseAsset).transferFrom(
                            msg.sender,
                            address(this),
                            uint256(baseAssetDebt)
                        );
                    }
                }
                if (balanceModeOut != 0) {
                    if (quoteAssetDebt < 0) {
                        require(
                            ((tokenBalances[0][quoteAsset] & MASK_KEEP_0_128) +
                                uint256(-quoteAssetDebt)) <= MASK_KEEP_0_128
                        );
                        tokenBalances[0][quoteAsset] += uint256(
                            -quoteAssetDebt
                        );
                    }
                    if (baseAssetDebt < 0) {
                        require(
                            ((tokenBalances[0][baseAsset] & MASK_KEEP_0_128) +
                                uint256(-baseAssetDebt)) <= MASK_KEEP_0_128
                        );
                        tokenBalances[0][baseAsset] += uint256(-baseAssetDebt);
                    }
                } else {
                    if (quoteAssetDebt < 0) {
                        IERC20(quoteAsset).transfer(
                            msg.sender,
                            uint256(-quoteAssetDebt)
                        );
                    }
                    if (baseAssetDebt < 0) {
                        IERC20(baseAsset).transfer(
                            msg.sender,
                            uint256(-baseAssetDebt)
                        );
                    }
                }
            } else {
                if (balanceMode == 1) {
                    // internal balances
                    if (quoteAssetDebt > 0) {
                        uint256 balance = tokenBalances[userId][quoteAsset];
                        if (uint128(balance) < uint256(quoteAssetDebt)) {
                            revert ICrystal.ActionFailed();
                        } else {
                            tokenBalances[userId][quoteAsset] =
                                balance -
                                uint256(quoteAssetDebt);
                        }
                    } else if (quoteAssetDebt < 0) {
                        require(
                            ((tokenBalances[userId][quoteAsset] &
                                MASK_KEEP_0_128) + uint256(-quoteAssetDebt)) <=
                                MASK_KEEP_0_128
                        );
                        tokenBalances[userId][quoteAsset] += uint256(
                            -quoteAssetDebt
                        );
                    }
                    if (baseAssetDebt > 0) {
                        uint256 balance = tokenBalances[userId][baseAsset];
                        if (uint128(balance) < uint256(baseAssetDebt)) {
                            revert ICrystal.ActionFailed();
                        } else {
                            tokenBalances[userId][baseAsset] =
                                balance -
                                uint256(baseAssetDebt);
                        }
                    } else if (baseAssetDebt < 0) {
                        require(
                            ((tokenBalances[userId][baseAsset] &
                                MASK_KEEP_0_128) + uint256(-baseAssetDebt)) <=
                                MASK_KEEP_0_128
                        );
                        tokenBalances[userId][baseAsset] += uint256(
                            -baseAssetDebt
                        );
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
    function _internalCancel(
        uint256 price,
        uint256 id,
        uint256 size,
        uint256 highestBid,
        uint256 lowestAsk,
        uint256 _order
    ) internal {
        unchecked {
            uint256 _priceLevel = priceLevels[marketId | price];
            _priceLevel -= size; // can't overflow
            if (id == ((_priceLevel >> 205) & MASK_KEEP_0_51)) {
                // if pricelevel fillnext then set to fillafter
                _priceLevel =
                    (_order & (MASK_KEEP_0_51 << 205)) |
                    (_priceLevel & MASK_OUT_205_256);
            } else if (id == ((_priceLevel >> 154) & MASK_KEEP_0_51)) {
                // if pricelevel latest then set latest to fillbefore
                uint256 fillBefore = ((_order >> 154) & MASK_KEEP_0_51);
                uint256 orderpointer = (
                    (fillBefore > MASK_KEEP_0_41)
                        ? fillBefore
                        : marketId | (price << 48) | fillBefore
                );
                orders[orderpointer] =
                    (orders[orderpointer] & MASK_OUT_205_256) |
                    (_order & (MASK_KEEP_0_51 << 205)); // set fillbefores fillafter to fillafter
                _priceLevel =
                    (_priceLevel & MASK_OUT_154_205) |
                    (fillBefore << 154);
            } else {
                uint256 fillBefore = ((_order >> 154) & MASK_KEEP_0_51);
                uint256 fillAfter = ((_order >> 205) & MASK_KEEP_0_51);
                uint256 orderpointer = (
                    (fillBefore > MASK_KEEP_0_41)
                        ? fillBefore
                        : marketId | (price << 48) | fillBefore
                );
                orders[orderpointer] =
                    (orders[orderpointer] & MASK_OUT_205_256) |
                    (fillAfter << 205); // set fillbefores fillafter to fillafter
                orderpointer = (
                    (fillAfter > MASK_KEEP_0_41)
                        ? fillAfter
                        : marketId | (price << 48) | fillAfter
                );
                orders[orderpointer] =
                    (orders[orderpointer] & MASK_OUT_154_205) |
                    (fillBefore << 154); // setfillafters fillbefore to fillbefore
            }
            priceLevels[marketId | price] = _priceLevel;
            if ((_priceLevel & MASK_KEEP_0_112) == 0) {
                uint256 tick = marketType == 0
                    ? (price / tickSize)
                    : _priceToTick(price);
                uint256 slotIndex = tick / 255;
                uint256 slot = activated[marketId | slotIndex] &
                    MASK_OUT_255_256;
                slot &= ~(1 << (tick % 255));
                activated[marketId | slotIndex] = slot | MASK_KEEP_255_256;
                if (slot == 0) {
                    activated2[marketId | (slotIndex / 255)] &= ~(1 <<
                        (slotIndex % 255));
                }
                if (price == lowestAsk) {
                    slot = slot >> tick % 255;
                    if (slot == 0) {
                        uint256 slot2Index = slotIndex / 255;
                        uint256 slot2 = (activated2[marketId | slot2Index] &
                            MASK_OUT_255_256 &
                            ~(1 << (slotIndex % 255))) >> slotIndex % 255;
                        while (slot2 == 0) {
                            ++slot2Index;
                            slot2 =
                                activated2[marketId | slot2Index] &
                                MASK_OUT_255_256;
                            slotIndex = slot2Index * 255;
                        }
                        slotIndex = _searchSlotUp(slot2, slotIndex);
                        slot =
                            activated[marketId | slotIndex] &
                            MASK_OUT_255_256;
                        tick = slotIndex * 255;
                    }
                    tick = _searchSlotUp(slot, tick);
                    _getMarket[market].lowestAsk = uint80(
                        marketType == 0 ? (tick * tickSize) : _tickToPrice(tick)
                    );
                } else if (price == highestBid) {
                    slot = slot & ((1 << (tick % 255)) - 1);
                    if (slot == 0) {
                        uint256 slot2Index = slotIndex / 255;
                        uint256 slot2 = (activated2[marketId | slot2Index] &
                            MASK_OUT_255_256 &
                            ~(1 << (slotIndex % 255))) &
                            ((1 << (slotIndex % 255)) - 1);
                        while (slot2 == 0) {
                            --slot2Index;
                            slot2 =
                                activated2[marketId | slot2Index] &
                                MASK_OUT_255_256;
                        }
                        slotIndex = _searchSlotDown(slot2, slot2Index * 255);
                        slot =
                            activated[marketId | slotIndex] &
                            MASK_OUT_255_256;
                    }
                    tick = _searchSlotDown(slot, slotIndex * 255);
                    _getMarket[market].highestBid = uint80(
                        marketType == 0 ? (tick * tickSize) : _tickToPrice(tick)
                    );
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
    function _getPriceLevels(
        bool isAscending,
        uint256 startPrice,
        uint256 distance,
        uint256 interval,
        uint256 max
    ) internal view {
        unchecked {
            uint256 _maxPrice = maxPrice;
            if (startPrice >= _maxPrice) {
                return;
            }
            uint256 _marketId = marketId;
            uint256 tick = marketType == 0
                ? (startPrice / tickSize)
                : _priceToTick(startPrice);
            startPrice = tick; // turn startprice into starttick
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
            uint256 slot2 = activated2[marketId | slot2Index] &
                MASK_OUT_255_256;
            assembly {
                position := mload(0x40)
                mstore(position, 0x0)
            }
            if (isAscending) {
                // assumes asks for buckets, if it's across bids then just make sure interval is set to 1
                if (
                    startPrice + (distance) >
                    (
                        marketType == 0
                            ? (_maxPrice / tickSize)
                            : _priceToTick(_maxPrice)
                    )
                ) {
                    distance = ((
                        marketType == 0
                            ? (_maxPrice / tickSize)
                            : _priceToTick(_maxPrice)
                    ) - startPrice);
                }
                while (true) {
                    {
                        uint256 _slot = slot >> tick % 255;
                        if (_slot == 0) {
                            uint256 _slot2 = (slot2 &
                                ~(1 << ((slotIndex) % 255))) >> slotIndex % 255;
                            while (_slot2 == 0) {
                                ++slot2Index;
                                slot2 =
                                    activated2[marketId | slot2Index] &
                                    MASK_OUT_255_256;
                                _slot2 = slot2;
                                slotIndex = slot2Index * 255;
                            }
                            slotIndex = _searchSlotUp(_slot2, slotIndex);
                            slot =
                                activated[marketId | slotIndex] &
                                MASK_OUT_255_256;
                            _slot = slot;
                            tick = slotIndex * 255;
                        }
                        tick = _searchSlotUp(_slot, tick);
                        slot &= ~(1 << (tick % 255));
                        if (slot >> tick % 255 == 0) {
                            slot2 &= ~(1 << ((slotIndex) % 255));
                        }
                    }
                    price = marketType == 0
                        ? (tick * tickSize)
                        : _tickToPrice(tick);
                    if (
                        (((price + interval - 1) / interval) * interval) ==
                        bucket
                    ) {
                        assembly {
                            mstore(0x00, or(_marketId, price))
                            mstore(0x20, priceLevels.slot)
                            let length := mload(position)
                            let existing := mload(add(length, position))
                            mstore(
                                add(length, position),
                                add(
                                    existing,
                                    and(
                                        sload(keccak256(0x00, 0x40)),
                                        MASK_KEEP_0_112
                                    )
                                )
                            )
                        }
                    } else {
                        if (max == 0 || (tick >= startPrice + distance)) {
                            break;
                        }
                        --max;
                        bucket = ((price + interval - 1) / interval) * interval; // round up because ask
                        assembly {
                            mstore(0x00, or(_marketId, price))
                            mstore(0x20, priceLevels.slot)
                            let length := mload(position)
                            mstore(
                                add(length, add(position, 0x20)),
                                or(
                                    shl(128, bucket),
                                    and(
                                        sload(keccak256(0x00, 0x40)),
                                        MASK_KEEP_0_112
                                    )
                                )
                            )
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
                        uint256 _slot2 = (slot2 & ~(1 << ((slotIndex) % 255))) &
                            ((1 << (slotIndex % 255)) - 1);
                        while (_slot2 == 0) {
                            --slot2Index;
                            slot2 =
                                activated2[marketId | slot2Index] &
                                MASK_OUT_255_256;
                            _slot2 = slot2;
                        }
                        slotIndex = _searchSlotDown(_slot2, slot2Index * 255);
                        slot =
                            activated[marketId | slotIndex] &
                            MASK_OUT_255_256;
                        _slot = slot;
                    }
                    tick = _searchSlotDown(_slot, slotIndex * 255);
                    slot &= ~(1 << (tick % 255));
                    if (slot & ((1 << (tick % 255)) - 1) == 0) {
                        slot2 &= ~(1 << ((slotIndex) % 255));
                    }
                    price = marketType == 0
                        ? (tick * tickSize)
                        : _tickToPrice(tick);
                    if (((price / interval) * interval) == bucket) {
                        assembly {
                            mstore(0x00, or(_marketId, price))
                            mstore(0x20, priceLevels.slot)
                            let length := mload(position)
                            let existing := mload(add(length, position))
                            mstore(
                                add(length, position),
                                add(
                                    existing,
                                    and(
                                        sload(keccak256(0x00, 0x40)),
                                        MASK_KEEP_0_112
                                    )
                                )
                            )
                        }
                    } else {
                        if (max == 0 || (tick <= startPrice - distance)) {
                            break;
                        }
                        --max;
                        bucket = (price / interval) * interval; // round down because bid
                        assembly {
                            mstore(0x00, or(_marketId, price))
                            mstore(0x20, priceLevels.slot)
                            let length := mload(position)
                            mstore(
                                add(length, add(position, 0x20)),
                                or(
                                    shl(128, bucket),
                                    and(
                                        sload(keccak256(0x00, 0x40)),
                                        MASK_KEEP_0_112
                                    )
                                )
                            )
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
    function getPriceLevels(
        bool isAscending,
        uint256 startPrice,
        uint256 distance,
        uint256 interval,
        uint256 max
    ) external payable returns (bytes memory) {
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
    function getPriceLevelsFromMid(
        uint256 distance,
        uint256 interval,
        uint256 max
    )
        external
        payable
        returns (
            uint256 highestBid,
            uint256 lowestAsk,
            bytes memory,
            bytes memory
        )
    {
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
    function getPrice()
        external
        payable
        returns (uint256 price, uint256 highestBid, uint256 lowestAsk)
    {
        ICrystal.Market storage m = _getMarket[market];
        uint256 count;
        (highestBid, lowestAsk) = (m.highestBid, m.lowestAsk);
        (uint256 reserveQuote, uint256 reserveBase) = m.isAMMEnabled
            ? (m.reserveQuote, m.reserveBase)
            : (0, 0);
        if (reserveQuote != 0) {
            uint256 ammPrice = ((reserveQuote * scaleFactor * 9975 * 100000) /
                (reserveBase * 10000 * uint256(m.makerRebate)));
            ammPrice = marketType == 0
                ? ((ammPrice + tickSize - 1) / tickSize) * tickSize
                : _toValidPrice(ammPrice, true); // get adjusted amm bid
            if (highestBid < ammPrice) {
                highestBid = ammPrice;
            }
            ammPrice = ((reserveQuote *
                scaleFactor *
                10000 *
                uint256(m.makerRebate) +
                (reserveBase * 9975 * 100000 - 1)) /
                (reserveBase * 9975 * 100000));
            ammPrice = marketType == 0
                ? (ammPrice - (ammPrice % tickSize))
                : _toValidPrice(ammPrice, false); // get adjusted amm ask
            if (lowestAsk > ammPrice) {
                lowestAsk = ammPrice;
            }
        }
        price = highestBid;
        if (lowestAsk != maxPrice) {
            // if no asks, it will return the highest bid rather than midpoint
            price += lowestAsk;
            ++count;
        }
        if (highestBid != 0) {
            // if no bids, it will return the lowest ask rather than midpoint
            ++count;
        }
        if (count == 2) {
            uint256 mid = (price + 1) >> 1;
            price = marketType == 0
                ? (mid - (mid % tickSize))
                : _toValidPrice(mid, false);
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
    function getQuote(
        bool isBuy,
        bool isExactInput,
        bool isCompleteFill,
        uint256 size,
        uint256 worstPrice
    ) external payable returns (uint256 amountIn, uint256 amountOut) {
        unchecked {
            ICrystal.Market storage m = _getMarket[market];
            uint256 price;
            if (isBuy) {
                if (isExactInput) {
                    size =
                        (size * uint256(m.takerFee) + uint256(m.takerFee) - 1) /
                        100000;
                }
                if (worstPrice >= maxPrice || worstPrice == 0) {
                    worstPrice = (
                        marketType == 0
                            ? maxPrice - tickSize
                            : _tickToPrice(_priceToTick(maxPrice) - 1)
                    );
                }
                price = m.lowestAsk;
            } else {
                if (!isExactInput) {
                    size =
                        (size * 100000 + uint256(m.takerFee) - 1) /
                        uint256(m.takerFee);
                }
                if (worstPrice == 0) {
                    worstPrice = (marketType == 0 ? tickSize : _tickToPrice(1));
                }
                price = m.highestBid;
            }
            (uint256 reserveQuote, uint256 reserveBase) = m.isAMMEnabled
                ? (m.reserveQuote, m.reserveBase)
                : (0, 0);
            uint256 tick = marketType == 0
                ? (price / tickSize)
                : _priceToTick(price);
            uint256 slot = activated[marketId | (tick / 255)] &
                MASK_OUT_255_256;
            uint256 slot2 = activated2[marketId | ((tick / 255) / 255)] &
                MASK_OUT_255_256;
            while (isExactInput ? size > amountIn : size > amountOut) {
                if (reserveQuote != 0) {
                    uint256 _amountIn = (
                        isBuy ? (price > worstPrice) : (price < worstPrice)
                    )
                        ? worstPrice
                        : price; // stop at either slippage limit or next resting order price
                    uint256 _amountOut;
                    if (
                        isBuy &&
                        _amountIn >
                        (reserveQuote *
                            scaleFactor *
                            10000 *
                            uint256(m.makerRebate) +
                            (reserveBase * 9975 * 100000 - 1)) /
                            (reserveBase * 9975 * 100000)
                    ) {
                        // adjust price in favor of amm because no maker rebate
                        uint256 _sizeLeft = isExactInput
                            ? (size - amountIn)
                            : (size - amountOut);
                        if (isExactInput) {
                            _amountIn = _exactInputBuySolve(
                                reserveQuote,
                                reserveBase,
                                _amountIn,
                                scaleFactor,
                                m.makerRebate,
                                _sizeLeft
                            ); // find optimal amountIn so AMM execution price up to price adjusted for maker rebate
                            if (_sizeLeft < _amountIn) {
                                _amountIn = _sizeLeft; // if amount is greater than _sizeLeft set amount to _sizeLeft and swap all thru amm
                            }
                            _amountOut =
                                (_amountIn * 9975 * reserveBase) /
                                ((reserveQuote * 10000) + (_amountIn * 9975)); // swap
                        } else {
                            _amountOut = _exactOutputBuySolve(
                                reserveQuote,
                                reserveBase,
                                _amountIn,
                                scaleFactor,
                                m.makerRebate,
                                _sizeLeft
                            ); // find optimal amountOut so AMM execution price up to price adjusted for maker rebate
                            if (_sizeLeft < _amountOut) {
                                _amountOut = _sizeLeft; // if amount is greater than _sizeLeft set amount to _sizeLeft and swap all thru amm
                            }
                            _amountIn =
                                (_amountOut * reserveQuote * 10000) /
                                ((reserveBase - _amountOut) * 9975) +
                                1; // swap
                        }
                        reserveQuote += _amountIn; // set reserves
                        reserveBase -= _amountOut;
                    } else if (
                        !isBuy &&
                        _amountIn <
                        (reserveQuote * scaleFactor * 9975 * 100000) /
                            (reserveBase * 10000 * uint256(m.makerRebate))
                    ) {
                        uint256 _sizeLeft = isExactInput
                            ? (size - amountIn)
                            : (size - amountOut);
                        if (isExactInput) {
                            _amountIn = _exactInputSellSolve(
                                reserveQuote,
                                reserveBase,
                                _amountIn,
                                scaleFactor,
                                m.makerRebate,
                                _sizeLeft
                            );
                            if (_sizeLeft < _amountIn) {
                                _amountIn = _sizeLeft;
                            }
                            _amountOut =
                                ((_amountIn * 9975) * reserveQuote) /
                                ((reserveBase * 10000) + (_amountIn * 9975));
                        } else {
                            _amountOut = _exactOutputSellSolve(
                                reserveQuote,
                                reserveBase,
                                _amountIn,
                                scaleFactor,
                                m.makerRebate,
                                _sizeLeft
                            );
                            if (_sizeLeft < _amountOut) {
                                _amountOut = _sizeLeft;
                            }
                            _amountIn =
                                (_amountOut * reserveBase * 10000) /
                                ((reserveQuote - _amountOut) * 9975) +
                                1;
                        }
                        reserveBase += _amountIn;
                        reserveQuote -= _amountOut;
                    } else {
                        _amountIn = 0; // set to 0 if no swap through amm so the next statement doesn't run
                    }
                    if (_amountIn != 0) {
                        uint256 _sizeLeft = isExactInput
                            ? (size - amountIn)
                            : (size - amountOut);
                        amountIn += _amountIn;
                        amountOut += _amountOut;
                        if (
                            _sizeLeft == (isExactInput ? _amountIn : _amountOut)
                        ) {
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
                uint256 sizeLeft = isExactInput
                    ? (size - amountIn)
                    : (size - amountOut);
                uint256 liquidity = priceLevels[marketId | price] &
                    MASK_KEEP_0_112;
                if (
                    isExactInput
                        ? (
                            isBuy
                                ? (liquidity >
                                    (((sizeLeft * uint256(m.makerRebate)) /
                                        100000) * scaleFactor) /
                                        price)
                                : (liquidity >
                                    (((sizeLeft * uint256(m.makerRebate)) /
                                        100000) * price) /
                                        scaleFactor)
                        )
                        : (liquidity > sizeLeft)
                ) {
                    amountOut += (
                        isExactInput
                            ? (
                                isBuy
                                    ? (((sizeLeft * uint256(m.makerRebate)) /
                                        100000) * scaleFactor) / price
                                    : (((sizeLeft * uint256(m.makerRebate)) /
                                        100000) * price) / scaleFactor
                            )
                            : sizeLeft
                    );
                    if (!isExactInput) {
                        sizeLeft = isBuy
                            ? (sizeLeft *
                                price *
                                100000 +
                                (scaleFactor * uint256(m.makerRebate) - 1)) /
                                (scaleFactor * uint256(m.makerRebate))
                            : (sizeLeft *
                                scaleFactor *
                                100000 +
                                (price * uint256(m.makerRebate) - 1)) /
                                (price * uint256(m.makerRebate));
                    }
                    amountIn += sizeLeft;
                    sizeLeft = 0;
                } else {
                    amountIn += (
                        isBuy
                            ? ((((liquidity * price) / scaleFactor) * 100000) /
                                uint256(m.makerRebate))
                            : ((((liquidity * scaleFactor) / price) * 100000) /
                                uint256(m.makerRebate))
                    );
                    amountOut += isBuy ? liquidity : liquidity;
                    sizeLeft -= isExactInput
                        ? (
                            isBuy
                                ? ((((liquidity * price) / scaleFactor) *
                                    100000) / uint256(m.makerRebate))
                                : ((((liquidity * scaleFactor) / price) *
                                    100000) / uint256(m.makerRebate))
                        )
                        : liquidity;
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
                                slot2 =
                                    activated2[marketId | slot2Index] &
                                    MASK_OUT_255_256;
                                _slot2 = slot2;
                                slotIndex = slot2Index * 255;
                            }
                            slotIndex = _searchSlotUp(_slot2, slotIndex);
                            slot =
                                activated[marketId | slotIndex] &
                                MASK_OUT_255_256;
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
                            uint256 _slot2 = slot2 &
                                ((1 << (slotIndex % 255)) - 1);
                            while (_slot2 == 0) {
                                --slot2Index;
                                slot2 =
                                    activated2[marketId | slot2Index] &
                                    MASK_OUT_255_256;
                                _slot2 = slot2;
                            }
                            slotIndex = _searchSlotDown(
                                _slot2,
                                slot2Index * 255
                            );
                            slot =
                                activated[marketId | slotIndex] &
                                MASK_OUT_255_256;
                            _slot = slot;
                        }
                        tick = _searchSlotDown(_slot, slotIndex * 255);
                    }
                    price = marketType == 0
                        ? (tick * tickSize)
                        : _tickToPrice(tick);
                } else {
                    break;
                }
            }
            isBuy
                ? amountIn = (amountIn * 100000) / uint256(m.takerFee)
                : amountOut = (amountOut * uint256(m.takerFee)) / 100000;
            return (amountIn, amountOut);
        }
    }

    /**
     * @notice Executes a market-style order across resting liquidity and the AMM.
     *
     * @dev `orderInfo` encodes side, exactness, STP behavior, balance routing, caller, and optional cloid metadata.
     * @dev `orderInfo` is 256-252 ordertype, 252-248 !isExactInput, 248-244 !isBuy, 244-240 STP, 240-236 !useexternalbalance, 236-232 !fromcaller
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
    function _marketOrder(
        uint256 size,
        uint256 priceAndReferrer,
        uint256 orderInfo
    )
        internal
        returns (
            uint256 amountIn,
            uint256 amountOut,
            uint256 id,
            uint256 settlementDelta
        )
    {
        // settlement delta is debit amt << 128 | credit amt, debit amt is always input asset and credit amt is always output
        unchecked {
            require(size <= MASK_KEEP_0_128);
            ICrystal.Market storage m = _getMarket[market];
            uint256 price;
            if (((orderInfo >> 244) & 1) == 0) {
                // isbuy
                if ((((orderInfo >> 248) & 1) == 0)) {
                    // isexactinput
                    assembly {
                        mstore(0x60, size)
                    }
                    size = (size * uint256(m.takerFee) + 99999) / 100000; // pre adjust size bc taker fee is in quote which is specified, i have no idea why/how/if this math works
                }
                if (
                    (priceAndReferrer & MASK_KEEP_0_80) >= maxPrice ||
                    (priceAndReferrer & MASK_KEEP_0_80) == 0
                ) {
                    priceAndReferrer =
                        (priceAndReferrer & MASK_OUT_0_80) |
                        (
                            marketType == 0
                                ? maxPrice - tickSize
                                : _tickToPrice(_priceToTick(maxPrice) - 1)
                        ); // set worst price to 1 tick worse than max price bc worst price is inclusive
                }
                price = m.lowestAsk;
            } else {
                if ((((orderInfo >> 248) & 1) != 0)) {
                    // !isexactinput
                    size =
                        (size * 100000 + uint256(m.takerFee) - 1) /
                        uint256(m.takerFee); // pre adjust size bc taker fee is in quote which is specified
                }
                if ((priceAndReferrer & MASK_KEEP_0_80) == 0) {
                    priceAndReferrer =
                        (priceAndReferrer & MASK_OUT_0_80) |
                        (marketType == 0 ? tickSize : _tickToPrice(1)); // set worst price to 1 tick bc inclusive
                }
                price = m.highestBid;
            }
            assembly {
                mstore(0x80, 0x0)
            }
            uint256 reserves = m.isAMMEnabled
                ? ((uint256(m.reserveQuote) << 128) | m.reserveBase)
                : 0;
            {
                uint256 tick = marketType == 0
                    ? (price / tickSize)
                    : _priceToTick(price);
                uint256 slot = activated[marketId | (tick / 255)] &
                    MASK_OUT_255_256;
                while (
                    (((orderInfo >> 248) & 1) == 0)
                        ? size > amountIn
                        : size > amountOut
                ) {
                    uint256 sizeLeft = (((orderInfo >> 248) & 1) == 0)
                        ? size - amountIn
                        : size - amountOut;
                    if (reserves != 0) {
                        // skip amm if not initialized
                        (uint256 reserveQuote, uint256 reserveBase) = (
                            reserves >> 128,
                            reserves & MASK_KEEP_0_112
                        );
                        uint256 _amountIn = (
                            (((orderInfo >> 244) & 1) == 0)
                                ? (price > (priceAndReferrer & MASK_KEEP_0_80))
                                : (price < (priceAndReferrer & MASK_KEEP_0_80))
                        )
                            ? (priceAndReferrer & MASK_KEEP_0_80)
                            : price;
                        uint256 _amountOut;
                        if (
                            (((orderInfo >> 244) & 1) == 0) &&
                            _amountIn >
                            (reserveQuote *
                                scaleFactor *
                                10000 *
                                uint256(m.makerRebate) +
                                (reserveBase * 9975 * 100000 - 1)) /
                                (reserveBase * 9975 * 100000)
                        ) {
                            if (((orderInfo >> 248) & 1) == 0) {
                                _amountIn = _exactInputBuySolve(
                                    reserveQuote,
                                    reserveBase,
                                    _amountIn,
                                    scaleFactor,
                                    m.makerRebate,
                                    sizeLeft
                                ); // find optimal amountIn so AMM execution price up to price adjusted for maker rebate
                                if (sizeLeft < _amountIn) {
                                    _amountIn = sizeLeft;
                                }
                                _amountOut =
                                    (_amountIn * 9975 * reserveBase) /
                                    ((reserveQuote * 10000) +
                                        (_amountIn * 9975)); // execute v2 swap
                            } else {
                                _amountOut = _exactOutputBuySolve(
                                    reserveQuote,
                                    reserveBase,
                                    _amountIn,
                                    scaleFactor,
                                    m.makerRebate,
                                    sizeLeft
                                ); // find optimal amountOut so AMM execution price up to price adjusted for maker rebate
                                if (sizeLeft < _amountOut) {
                                    _amountOut = sizeLeft;
                                }
                                _amountIn =
                                    (_amountOut * reserveQuote * 10000) /
                                    ((reserveBase - _amountOut) * 9975) +
                                    1; // execute v2 swap
                            }
                            reserveQuote += _amountIn;
                            reserveBase -= _amountOut;
                            require(
                                reserveQuote <= MASK_KEEP_0_112 &&
                                    reserveBase <= MASK_KEEP_0_112
                            );
                            {
                                uint256 pricememory;
                                assembly {
                                    pricememory := mload(0x80)
                                } // top 128 is start price bottom 128 is end price
                                uint256 endprice = ((reserveQuote *
                                    scaleFactor *
                                    10000 *
                                    uint256(m.makerRebate) +
                                    (reserveBase * 9975 * 100000 - 1)) /
                                    (reserveBase * 9975 * 100000)); // adjust price in favor of amm because no maker rebate
                                endprice = endprice >= maxPrice
                                    ? maxPrice
                                    : endprice <= tickSize
                                        ? tickSize
                                        : marketType == 0
                                            ? (endprice - (endprice % tickSize))
                                            : _toValidPrice(endprice, false); // round down
                                if (pricememory == 0) {
                                    uint256 startprice = (((reserveQuote -
                                        _amountIn) *
                                        scaleFactor *
                                        10000 *
                                        uint256(m.makerRebate) +
                                        ((reserveBase + _amountOut) *
                                            9975 *
                                            100000 -
                                            1)) /
                                        ((reserveBase + _amountOut) *
                                            9975 *
                                            100000));
                                    startprice = startprice >= maxPrice
                                        ? maxPrice
                                        : startprice <= tickSize
                                            ? tickSize
                                            : (
                                                marketType == 0
                                                    ? (startprice -
                                                        (startprice % tickSize))
                                                    : _toValidPrice(
                                                        startprice,
                                                        false
                                                    )
                                            );
                                    pricememory =
                                        (startprice << 128) |
                                        endprice; // set start price if needed, temp undo reserve updates
                                } else {
                                    pricememory =
                                        (pricememory & MASK_OUT_0_128) |
                                        endprice;
                                }
                                assembly {
                                    mstore(0x80, pricememory)
                                }
                            }
                        } else if (
                            (((orderInfo >> 244) & 1) != 0) &&
                            _amountIn <
                            (reserveQuote * scaleFactor * 9975 * 100000) /
                                (reserveBase * 10000 * uint256(m.makerRebate))
                        ) {
                            if (((orderInfo >> 248) & 1) == 0) {
                                _amountIn = _exactInputSellSolve(
                                    reserveQuote,
                                    reserveBase,
                                    _amountIn,
                                    scaleFactor,
                                    m.makerRebate,
                                    sizeLeft
                                );
                                if (sizeLeft < _amountIn) {
                                    _amountIn = sizeLeft;
                                }
                                _amountOut =
                                    ((_amountIn * 9975) * reserveQuote) /
                                    ((reserveBase * 10000) +
                                        (_amountIn * 9975)); // execute v2 swap
                            } else {
                                _amountOut = _exactOutputSellSolve(
                                    reserveQuote,
                                    reserveBase,
                                    _amountIn,
                                    scaleFactor,
                                    m.makerRebate,
                                    sizeLeft
                                );
                                if (sizeLeft < _amountOut) {
                                    _amountOut = sizeLeft;
                                }
                                _amountIn =
                                    (_amountOut * reserveBase * 10000) /
                                    ((reserveQuote - _amountOut) * 9975) +
                                    1; // execute v2 swap
                            }
                            reserveBase += _amountIn;
                            reserveQuote -= _amountOut;
                            require(
                                reserveQuote <= MASK_KEEP_0_112 &&
                                    reserveBase <= MASK_KEEP_0_112
                            );
                            {
                                uint256 pricememory;
                                assembly {
                                    pricememory := mload(0x80)
                                } // top 128 is start price bottom 128 is end price
                                uint256 endprice = ((reserveQuote *
                                    scaleFactor *
                                    9975 *
                                    100000) /
                                    (reserveBase *
                                        10000 *
                                        uint256(m.makerRebate)));
                                endprice = endprice >= maxPrice
                                    ? maxPrice
                                    : endprice <= tickSize
                                        ? tickSize
                                        : marketType == 0
                                            ? ((endprice + tickSize - 1) /
                                                tickSize) * tickSize
                                            : _toValidPrice(endprice, true); // round up
                                if (pricememory == 0) {
                                    uint256 startprice = ((reserveQuote +
                                        _amountOut) *
                                        scaleFactor *
                                        9975 *
                                        100000) /
                                        ((reserveBase - _amountIn) *
                                            10000 *
                                            uint256(m.makerRebate));
                                    startprice = startprice >= maxPrice
                                        ? maxPrice
                                        : startprice <= tickSize
                                            ? tickSize
                                            : marketType == 0
                                                ? ((startprice + tickSize - 1) /
                                                    tickSize) * tickSize
                                                : _toValidPrice(
                                                    startprice,
                                                    true
                                                );
                                    pricememory =
                                        (startprice << 128) |
                                        endprice;
                                } else {
                                    pricememory =
                                        (pricememory & MASK_OUT_0_128) |
                                        endprice;
                                }
                                assembly {
                                    mstore(0x80, pricememory)
                                }
                            }
                        } else {
                            _amountIn = 0;
                        }
                        if (_amountIn != 0) {
                            if (
                                ((settlementDelta >> 128) + _amountIn) <=
                                MASK_KEEP_0_128
                            ) {
                                settlementDelta += (_amountIn << 128);
                            } else {
                                settlementDelta |= (MASK_KEEP_0_128 << 128);
                            }
                            amountIn += _amountIn;
                            amountOut += _amountOut;
                            reserves = (reserveQuote << 128) | reserveBase;
                            if (
                                sizeLeft !=
                                (
                                    (((orderInfo >> 248) & 1) == 0)
                                        ? _amountIn
                                        : _amountOut
                                )
                            ) {
                                sizeLeft -= (
                                    (((orderInfo >> 248) & 1) == 0)
                                        ? _amountIn
                                        : _amountOut
                                );
                            } else {
                                if (
                                    activated[marketId | (tick / 255)] &
                                        MASK_OUT_255_256 !=
                                    slot
                                ) {
                                    // update activated and break if swap is done
                                    activated[marketId | (tick / 255)] =
                                        slot |
                                        MASK_KEEP_255_256;
                                }
                                break;
                            }
                        }
                    }
                    if (
                        (((orderInfo >> 244) & 1) == 0)
                            ? price > (priceAndReferrer & MASK_KEEP_0_80)
                            : price < (priceAndReferrer & MASK_KEEP_0_80)
                    ) {
                        // if worst price (slippage limit) is exceeded
                        sizeLeft = (priceAndReferrer & MASK_KEEP_0_80); // worstPrice
                        if ((orderInfo >> 252) == 1) {
                            revert ICrystal.SlippageExceeded();
                        }
                        if (
                            activated[marketId | (tick / 255)] &
                                MASK_OUT_255_256 !=
                            slot
                        ) {
                            activated[marketId | (tick / 255)] =
                                slot |
                                MASK_KEEP_255_256;
                        }
                        if ((orderInfo >> 252) == 2) {
                            if (reserves != 0) {
                                // set reserves so limit order doesn't fail bc of crossing amm
                                (uint112 reserveQuote, uint112 reserveBase) = (
                                    uint112(reserves >> 128),
                                    uint112(reserves & MASK_KEEP_0_112)
                                );
                                if (
                                    reserveQuote != m.reserveQuote ||
                                    reserveBase != m.reserveBase
                                ) {
                                    (m.reserveQuote, m.reserveBase) = (
                                        reserveQuote,
                                        reserveBase
                                    );
                                    emit ICrystal.Sync(
                                        market,
                                        reserveQuote,
                                        reserveBase
                                    );
                                }
                                reserves = 0; // don't set reserves again later on
                            }
                            tick = orderInfo; // avoid stack too deep
                            (((tick >> 244) & 1) == 0)
                                ? m.lowestAsk = uint80(price)
                                : m.highestBid = uint80(price);
                            slot = (((tick >> 248) & 1) == 0)
                                ? (size - amountIn)
                                : (
                                    (((tick >> 244) & 1) == 0)
                                        ? (((size - amountOut) * sizeLeft) /
                                            scaleFactor)
                                        : (((size - amountOut) * scaleFactor) /
                                            sizeLeft)
                                );
                            if (
                                (((tick >> 248) & 1) == 0) &&
                                (((tick >> 244) & 1) == 0)
                            ) {
                                assembly {
                                    slot := mload(0x60)
                                }
                            }
                            (slot, id) = _limitOrder(
                                (((tick >> 244) & 1) == 0),
                                ((tick >> 236) & 0x1) == 0,
                                sizeLeft,
                                (
                                    (((tick >> 244) & 1) == 0)
                                        ? (((tick >> 248) & 1) == 0)
                                            ? slot -
                                                (amountIn * 100000) /
                                                uint256(m.takerFee)
                                            : slot
                                        : (((tick >> 248) & 1) == 0)
                                            ? slot
                                            : (slot * uint256(m.takerFee)) /
                                                100000
                                ),
                                ((tick >> 160) & MASK_KEEP_0_41),
                                ((tick >> 208) & MASK_KEEP_0_10)
                            );
                            if (
                                ((settlementDelta >> 128) + slot) <=
                                MASK_KEEP_0_128
                            ) {
                                settlementDelta += (slot << 128);
                            } else {
                                settlementDelta |= (MASK_KEEP_0_128 << 128);
                            }
                            if (slot != 0) {
                                // limit order event is written to memory, emitted in outer function
                                _addToOrdersUpdatedEvent(
                                    (LEADING_HEX_2 +
                                        (
                                            (((tick >> 244) & 1) == 0)
                                                ? 0
                                                : LEADING_HEX_1
                                        )) |
                                        (sizeLeft << 168) |
                                        (id << 112) |
                                        slot
                                ); // 8 flag 80 price 56 id 112 size
                            }
                        }
                        break;
                    }
                    uint256 _priceLevel = priceLevels[marketId | price];
                    {
                        uint256 next = (_priceLevel >> 205) & MASK_KEEP_0_51;
                        uint256 _orderInfo = orderInfo; // avoid stack too deep
                        while (
                            (_priceLevel & MASK_KEEP_0_112) != 0 &&
                            sizeLeft != 0 &&
                            !((_orderInfo >> 252) == 3 && gasleft() < 200000)
                        ) {
                            // 200k gas buffer if type 3 order
                            uint256 _order = orders[
                                (
                                    (next > MASK_KEEP_0_41)
                                        ? next
                                        : marketId | (price << 48) | next
                                )
                            ];
                            if (
                                ((_orderInfo >> 240) & 0xF) != 0 &&
                                ((_order >> 113) & MASK_KEEP_0_41) ==
                                ((_orderInfo >> 160) & MASK_KEEP_0_41)
                            ) {
                                // stp is 0 do nothing 1 cancel maker 2 cancel taker 3 cancel both
                                if (((_orderInfo >> 240) & 0x1) != 0) {
                                    // cancel resting
                                    bool isBuy = ((_orderInfo >> 244) & 1) == 0;
                                    uint256 ordersize = (_order &
                                        MASK_KEEP_0_112);
                                    if (next > MASK_KEEP_0_41) {
                                        orders[next] &= MASK_KEEP_113_154;
                                    } else {
                                        delete orders[
                                            marketId | (price << 48) | next
                                        ];
                                    }
                                    _priceLevel -= ordersize; // can't overflow
                                    if (
                                        ((settlementDelta & MASK_KEEP_0_128) +
                                            ordersize) <= MASK_KEEP_0_128
                                    ) {
                                        settlementDelta += ordersize;
                                    } else {
                                        settlementDelta |= MASK_KEEP_0_128;
                                    }
                                    if ((_order & MASK_KEEP_112_113) != 0) {
                                        tokenBalances[
                                            (_order >> 113) & MASK_KEEP_0_41
                                        ][
                                            isBuy ? baseAsset : quoteAsset
                                        ] -= (ordersize << 128); // unlock tokens if internal can't overflow
                                    }
                                    _addToOrdersUpdatedEvent(
                                        (isBuy ? LEADING_HEX_1 : 0) |
                                            (price << 168) |
                                            (next << 112) |
                                            ordersize
                                    ); // 8 flag 80 price 56 id 112 cancel size
                                    next = (_order >> 205) & MASK_KEEP_0_51;
                                }
                                if (((_orderInfo >> 240) & 0xF) == 1) {
                                    continue;
                                } else {
                                    // cancel taker
                                    sizeLeft = 0;
                                    break;
                                }
                            }
                            if (
                                (((_orderInfo >> 248) & 1) == 0)
                                    ? (
                                        (((_orderInfo >> 244) & 1) == 0)
                                            ? ((_order & MASK_KEEP_0_112) >
                                                (((sizeLeft *
                                                    uint256(m.makerRebate)) /
                                                    100000) * scaleFactor) /
                                                    price)
                                            : ((_order & MASK_KEEP_0_112) >
                                                (((sizeLeft *
                                                    uint256(m.makerRebate)) /
                                                    100000) * price) /
                                                    scaleFactor)
                                    )
                                    : ((_order & MASK_KEEP_0_112) > sizeLeft)
                            ) {
                                {
                                    // resting qty is in resting asset
                                    bool isBuy = ((_orderInfo >> 244) & 1) == 0;
                                    uint256 _amountOut = (
                                        (((_orderInfo >> 248) & 1) == 0)
                                            ? (
                                                isBuy
                                                    ? (((sizeLeft *
                                                        uint256(
                                                            m.makerRebate
                                                        )) / 100000) *
                                                        scaleFactor) / price
                                                    : (((sizeLeft *
                                                        uint256(
                                                            m.makerRebate
                                                        )) / 100000) * price) /
                                                        scaleFactor
                                            )
                                            : sizeLeft
                                    ); // output amount for just this swap, round down
                                    amountOut += _amountOut;
                                    if ((((_orderInfo >> 248) & 1) != 0)) {
                                        sizeLeft = isBuy
                                            ? (sizeLeft *
                                                price *
                                                100000 +
                                                (scaleFactor *
                                                    uint256(m.makerRebate) -
                                                    1)) /
                                                (scaleFactor *
                                                    uint256(m.makerRebate))
                                            : (sizeLeft *
                                                scaleFactor *
                                                100000 +
                                                (price *
                                                    uint256(m.makerRebate) -
                                                    1)) /
                                                (price *
                                                    uint256(m.makerRebate)); // transfer to maker amount, round up
                                    }
                                    _priceLevel -= _amountOut; // can't overflow
                                    _order -= _amountOut; // can't overflow
                                    orders[
                                        (
                                            (next > MASK_KEEP_0_41)
                                                ? next
                                                : marketId |
                                                    (price << 48) |
                                                    next
                                        )
                                    ] = _order;
                                    uint256 ownerUserId = (_order >> 113) &
                                        MASK_KEEP_0_41;
                                    address owner = userIdToAddress[
                                        ownerUserId
                                    ];
                                    if (_order & MASK_KEEP_112_113 == 0) {
                                        // maker wants tokens
                                        if (
                                            ((_orderInfo >> 236) & 0x1) == 0 &&
                                            ((_orderInfo >> 232) & 0x1) == 0
                                        ) {
                                            // taker gives tokens
                                            try
                                                IERC20(
                                                    isBuy
                                                        ? quoteAsset
                                                        : baseAsset
                                                ).transferFrom(
                                                        msg.sender,
                                                        owner,
                                                        sizeLeft
                                                    )
                                            {} catch {
                                                uint256 tempSettlementDelta = settlementDelta; // need new var to avoid stack too deep
                                                if (
                                                    ((tempSettlementDelta >>
                                                        128) + sizeLeft) <=
                                                    MASK_KEEP_0_128
                                                ) {
                                                    settlementDelta =
                                                        tempSettlementDelta +
                                                        (sizeLeft << 128);
                                                } else {
                                                    settlementDelta =
                                                        tempSettlementDelta |
                                                        (MASK_KEEP_0_128 <<
                                                            128);
                                                }
                                                if (
                                                    ((tokenBalances[
                                                        ownerUserId
                                                    ][
                                                        isBuy
                                                            ? quoteAsset
                                                            : baseAsset
                                                    ] & MASK_KEEP_0_128) +
                                                        sizeLeft) <=
                                                    MASK_KEEP_0_128
                                                ) {
                                                    tokenBalances[ownerUserId][
                                                        isBuy
                                                            ? quoteAsset
                                                            : baseAsset
                                                    ] += sizeLeft;
                                                } else {
                                                    tokenBalances[ownerUserId][
                                                        isBuy
                                                            ? quoteAsset
                                                            : baseAsset
                                                    ] |= MASK_KEEP_0_128;
                                                }
                                            }
                                        } else {
                                            // taker gives internal balance
                                            uint256 tempSettlementDelta = settlementDelta;
                                            if (
                                                ((tempSettlementDelta >> 128) +
                                                    sizeLeft) <= MASK_KEEP_0_128
                                            ) {
                                                settlementDelta =
                                                    tempSettlementDelta +
                                                    (sizeLeft << 128);
                                            } else {
                                                settlementDelta =
                                                    tempSettlementDelta |
                                                    (MASK_KEEP_0_128 << 128);
                                            }
                                            (bool success, ) = (
                                                isBuy ? quoteAsset : baseAsset
                                            ).call(
                                                    abi.encodeWithSelector(
                                                        0xa9059cbb,
                                                        owner,
                                                        sizeLeft
                                                    )
                                                );
                                            // if transfer fails (like if maker is blacklisted) then credit their internal balance
                                            if (!success) {
                                                if (
                                                    ((tokenBalances[
                                                        ownerUserId
                                                    ][
                                                        isBuy
                                                            ? quoteAsset
                                                            : baseAsset
                                                    ] & MASK_KEEP_0_128) +
                                                        sizeLeft) <=
                                                    MASK_KEEP_0_128
                                                ) {
                                                    tokenBalances[ownerUserId][
                                                        isBuy
                                                            ? quoteAsset
                                                            : baseAsset
                                                    ] += sizeLeft;
                                                } else {
                                                    tokenBalances[ownerUserId][
                                                        isBuy
                                                            ? quoteAsset
                                                            : baseAsset
                                                    ] |= MASK_KEEP_0_128;
                                                }
                                            }
                                        }
                                    } else {
                                        // maker wants internal balance
                                        uint256 tempSettlementDelta = settlementDelta;
                                        if (
                                            ((tempSettlementDelta >> 128) +
                                                sizeLeft) <= MASK_KEEP_0_128
                                        ) {
                                            settlementDelta =
                                                tempSettlementDelta +
                                                (sizeLeft << 128);
                                        } else {
                                            settlementDelta =
                                                tempSettlementDelta |
                                                (MASK_KEEP_0_128 << 128);
                                        }
                                        if (
                                            ((tokenBalances[ownerUserId][
                                                isBuy ? quoteAsset : baseAsset
                                            ] & MASK_KEEP_0_128) + sizeLeft) <=
                                            MASK_KEEP_0_128
                                        ) {
                                            tokenBalances[ownerUserId][
                                                isBuy ? quoteAsset : baseAsset
                                            ] += sizeLeft;
                                        } else {
                                            tokenBalances[ownerUserId][
                                                isBuy ? quoteAsset : baseAsset
                                            ] |= MASK_KEEP_0_128;
                                        }
                                        tokenBalances[ownerUserId][
                                            isBuy ? baseAsset : quoteAsset
                                        ] -= (_amountOut << 128); // unlock maker internal
                                    }
                                    address _market = market;
                                    assembly {
                                        let length := mload(0xc0)
                                        mstore(
                                            add(length, 0xe0),
                                            or(
                                                mul(
                                                    LEADING_HEX_1,
                                                    iszero(isBuy)
                                                ),
                                                or(
                                                    shl(168, price),
                                                    or(
                                                        shl(112, next),
                                                        and(
                                                            MASK_KEEP_0_112,
                                                            _order
                                                        )
                                                    )
                                                )
                                            )
                                        )
                                        mstore(
                                            add(length, 0x100),
                                            or(shl(128, sizeLeft), _amountOut)
                                        )
                                        log3(
                                            add(length, 0xe0),
                                            0x40,
                                            FILL_SIG,
                                            _market,
                                            owner
                                        )
                                        mstore(0x40, add(length, 0xe0))
                                    }
                                }
                                amountIn += sizeLeft;
                                sizeLeft = 0;
                            } else {
                                {
                                    // resting qty is in resting asset
                                    uint256 transferAmount = (((_orderInfo >>
                                        244) & 1) == 0)
                                        ? (((((_order & MASK_KEEP_0_112) *
                                            price) / scaleFactor) * 100000) /
                                            uint256(m.makerRebate))
                                        : (((((_order & MASK_KEEP_0_112) *
                                            scaleFactor) / price) * 100000) /
                                            uint256(m.makerRebate));
                                    amountIn += transferAmount;
                                    uint256 _amountOut = (_order &
                                        MASK_KEEP_0_112);
                                    amountOut += _amountOut;
                                    _priceLevel -= _amountOut;
                                    sizeLeft -= (((_orderInfo >> 248) & 1) == 0)
                                        ? transferAmount
                                        : _amountOut;
                                    uint256 ownerUserId = (_order >> 113) &
                                        MASK_KEEP_0_41;
                                    address owner = userIdToAddress[
                                        ownerUserId
                                    ];
                                    if (_order & MASK_KEEP_112_113 == 0) {
                                        // maker wants tokens
                                        if (
                                            ((_orderInfo >> 236) & 0x1) == 0 &&
                                            ((_orderInfo >> 232) & 0x1) == 0
                                        ) {
                                            // taker gives tokens
                                            try
                                                IERC20(
                                                    (((_orderInfo >> 244) &
                                                        1) == 0)
                                                        ? quoteAsset
                                                        : baseAsset
                                                ).transferFrom(
                                                        msg.sender,
                                                        owner,
                                                        transferAmount
                                                    )
                                            {} catch {
                                                uint256 tempSettlementDelta = settlementDelta;
                                                if (
                                                    ((tempSettlementDelta >>
                                                        128) +
                                                        transferAmount) <=
                                                    MASK_KEEP_0_128
                                                ) {
                                                    settlementDelta =
                                                        tempSettlementDelta +
                                                        (transferAmount << 128);
                                                } else {
                                                    settlementDelta =
                                                        tempSettlementDelta |
                                                        (MASK_KEEP_0_128 <<
                                                            128);
                                                }
                                                if (
                                                    ((tokenBalances[
                                                        ownerUserId
                                                    ][
                                                        (((_orderInfo >> 244) &
                                                            1) == 0)
                                                            ? quoteAsset
                                                            : baseAsset
                                                    ] & MASK_KEEP_0_128) +
                                                        transferAmount) <=
                                                    MASK_KEEP_0_128
                                                ) {
                                                    tokenBalances[ownerUserId][
                                                        (((_orderInfo >> 244) &
                                                            1) == 0)
                                                            ? quoteAsset
                                                            : baseAsset
                                                    ] += transferAmount;
                                                } else {
                                                    tokenBalances[ownerUserId][
                                                        (((_orderInfo >> 244) &
                                                            1) == 0)
                                                            ? quoteAsset
                                                            : baseAsset
                                                    ] |= MASK_KEEP_0_128;
                                                }
                                            }
                                        } else {
                                            // taker gives internal balance
                                            uint256 tempSettlementDelta = settlementDelta;
                                            if (
                                                ((tempSettlementDelta >> 128) +
                                                    transferAmount) <=
                                                MASK_KEEP_0_128
                                            ) {
                                                settlementDelta =
                                                    tempSettlementDelta +
                                                    (transferAmount << 128);
                                            } else {
                                                settlementDelta =
                                                    tempSettlementDelta |
                                                    (MASK_KEEP_0_128 << 128);
                                            }
                                            (bool success, ) = (
                                                (((_orderInfo >> 244) & 1) == 0)
                                                    ? quoteAsset
                                                    : baseAsset
                                            ).call(
                                                    abi.encodeWithSelector(
                                                        0xa9059cbb,
                                                        owner,
                                                        transferAmount
                                                    )
                                                );
                                            // if transfer fails (like if maker is blacklisted) then credit their internal balance
                                            if (!success) {
                                                if (
                                                    ((tokenBalances[
                                                        ownerUserId
                                                    ][
                                                        (((_orderInfo >> 244) &
                                                            1) == 0)
                                                            ? quoteAsset
                                                            : baseAsset
                                                    ] & MASK_KEEP_0_128) +
                                                        transferAmount) <=
                                                    MASK_KEEP_0_128
                                                ) {
                                                    tokenBalances[ownerUserId][
                                                        (((_orderInfo >> 244) &
                                                            1) == 0)
                                                            ? quoteAsset
                                                            : baseAsset
                                                    ] += transferAmount;
                                                } else {
                                                    tokenBalances[ownerUserId][
                                                        (((_orderInfo >> 244) &
                                                            1) == 0)
                                                            ? quoteAsset
                                                            : baseAsset
                                                    ] |= MASK_KEEP_0_128;
                                                }
                                            }
                                        }
                                    } else {
                                        // maker wants internal balance
                                        uint256 tempSettlementDelta = settlementDelta;
                                        if (
                                            ((tempSettlementDelta >> 128) +
                                                transferAmount) <=
                                            MASK_KEEP_0_128
                                        ) {
                                            settlementDelta =
                                                tempSettlementDelta +
                                                (transferAmount << 128);
                                        } else {
                                            settlementDelta =
                                                tempSettlementDelta |
                                                (MASK_KEEP_0_128 << 128);
                                        }
                                        if (
                                            ((tokenBalances[ownerUserId][
                                                (((_orderInfo >> 244) & 1) == 0)
                                                    ? quoteAsset
                                                    : baseAsset
                                            ] & MASK_KEEP_0_128) +
                                                transferAmount) <=
                                            MASK_KEEP_0_128
                                        ) {
                                            tokenBalances[ownerUserId][
                                                (((_orderInfo >> 244) & 1) == 0)
                                                    ? quoteAsset
                                                    : baseAsset
                                            ] += transferAmount;
                                        } else {
                                            tokenBalances[ownerUserId][
                                                (((_orderInfo >> 244) & 1) == 0)
                                                    ? quoteAsset
                                                    : baseAsset
                                            ] |= MASK_KEEP_0_128;
                                        }
                                        tokenBalances[ownerUserId][
                                            (((_orderInfo >> 244) & 1) == 0)
                                                ? baseAsset
                                                : quoteAsset
                                        ] -= (_amountOut << 128); // unlock maker internal
                                    }
                                    address _market = market;
                                    assembly {
                                        let length := mload(0xc0)
                                        mstore(
                                            add(length, 0xe0),
                                            or(
                                                mul(
                                                    LEADING_HEX_1,
                                                    and(shr(244, _orderInfo), 1)
                                                ),
                                                or(
                                                    shl(168, price),
                                                    shl(112, next)
                                                )
                                            )
                                        )
                                        mstore(
                                            add(length, 0x100),
                                            or(
                                                shl(128, transferAmount),
                                                _amountOut
                                            )
                                        )
                                        log3(
                                            add(length, 0xe0),
                                            0x40,
                                            FILL_SIG,
                                            _market,
                                            owner
                                        )
                                        mstore(0x40, add(length, 0xe0))
                                    }
                                }
                                if (next > MASK_KEEP_0_41) {
                                    orders[next] &= MASK_KEEP_113_154;
                                } else {
                                    delete orders[
                                        marketId | (price << 48) | next
                                    ];
                                }
                                next = (_order >> 205) & MASK_KEEP_0_51;
                            }
                        }
                        priceLevels[marketId | price] =
                            (next << 205) |
                            (_priceLevel & MASK_OUT_205_256); // set fillnext to next
                    }
                    assembly {
                        // update start and end price for event
                        let pricememory := mload(0x80) // top 128 is start price bottom 128 is end price
                        switch pricememory
                        case 0 {
                            pricememory := or(shl(128, price), price)
                        }
                        default {
                            pricememory := or(
                                and(pricememory, MASK_OUT_0_128),
                                price
                            ) // set end price
                        }
                        mstore(0x80, pricememory)
                    }
                    if ((_priceLevel & MASK_KEEP_0_112) == 0) {
                        // if price level was fully filled find next one and potentially update activated bitmap
                        slot &= ~(1 << (tick % 255));
                        uint256 slotIndex = tick / 255;
                        if (((orderInfo >> 244) & 1) == 0) {
                            uint256 _slot = slot >> tick % 255;
                            if (
                                _slot == 0 &&
                                ((activated[marketId | slotIndex] &
                                    MASK_OUT_255_256) != slot)
                            ) {
                                activated[marketId | slotIndex] =
                                    slot |
                                    MASK_KEEP_255_256;
                            }
                            if (_slot == 0) {
                                uint256 slot2Index = slotIndex / 255;
                                uint256 slot2 = (activated2[
                                    marketId | slot2Index
                                ] &
                                    MASK_OUT_255_256 &
                                    ~(1 << (slotIndex % 255))) >>
                                    slotIndex %
                                    255;
                                if (slot == 0) {
                                    activated2[marketId | slot2Index] &= ~(1 <<
                                        ((slotIndex) % 255));
                                }
                                while (slot2 == 0) {
                                    ++slot2Index;
                                    slot2 =
                                        activated2[marketId | slot2Index] &
                                        MASK_OUT_255_256;
                                    slotIndex = slot2Index * 255;
                                }
                                slotIndex = _searchSlotUp(slot2, slotIndex);
                                slot =
                                    activated[marketId | slotIndex] &
                                    MASK_OUT_255_256;
                                _slot = slot;
                                tick = slotIndex * 255;
                            }
                            tick = _searchSlotUp(_slot, tick);
                        } else {
                            uint256 _slot = slot & ((1 << (tick % 255)) - 1);
                            if (
                                _slot == 0 &&
                                ((activated[marketId | slotIndex] &
                                    MASK_OUT_255_256) != slot)
                            ) {
                                activated[marketId | slotIndex] =
                                    slot |
                                    MASK_KEEP_255_256;
                            }
                            if (_slot == 0) {
                                uint256 slot2Index = slotIndex / 255;
                                uint256 slot2 = (activated2[
                                    marketId | slot2Index
                                ] &
                                    MASK_OUT_255_256 &
                                    ~(1 << (slotIndex % 255))) &
                                    ((1 << (slotIndex % 255)) - 1);
                                if (slot == 0) {
                                    activated2[marketId | slot2Index] &= ~(1 <<
                                        ((slotIndex) % 255));
                                }
                                while (slot2 == 0) {
                                    --slot2Index;
                                    slot2 =
                                        activated2[marketId | slot2Index] &
                                        MASK_OUT_255_256;
                                }
                                slotIndex = _searchSlotDown(
                                    slot2,
                                    slot2Index * 255
                                );
                                slot =
                                    activated[marketId | slotIndex] &
                                    MASK_OUT_255_256;
                                _slot = slot;
                            }
                            tick = _searchSlotDown(_slot, slotIndex * 255);
                        }
                        price = marketType == 0
                            ? (tick * tickSize)
                            : _tickToPrice(tick);
                    } else {
                        if (
                            activated[marketId | (tick / 255)] &
                                MASK_OUT_255_256 !=
                            slot
                        ) {
                            activated[marketId | (tick / 255)] =
                                slot |
                                MASK_KEEP_255_256;
                        }
                    }
                    if (
                        sizeLeft == 0 ||
                        ((orderInfo >> 252) == 3 && gasleft() < 200000)
                    ) {
                        // 200k gas buffer if type 3 order
                        break;
                    }
                }
            }
            if (amountIn != 0 || amountOut != 0) {
                if (reserves != 0) {
                    // update amm reserves if needed
                    (uint112 reserveQuote, uint112 reserveBase) = (
                        uint112(reserves >> 128),
                        uint112(reserves & MASK_KEEP_0_112)
                    );
                    if (
                        reserveQuote != m.reserveQuote ||
                        reserveBase != m.reserveBase
                    ) {
                        (m.reserveQuote, m.reserveBase) = (
                            reserveQuote,
                            reserveBase
                        );
                        emit ICrystal.Sync(market, reserveQuote, reserveBase);
                    }
                }
                uint256 feeAmount;
                if (((orderInfo >> 244) & 1) == 0) {
                    // fee is always in quote asset
                    feeAmount =
                        (amountIn * 100000) /
                        uint256(m.takerFee) -
                        amountIn;
                    amountIn += feeAmount;
                    if (
                        ((settlementDelta >> 128) + feeAmount) <=
                        MASK_KEEP_0_128
                    ) {
                        settlementDelta += (feeAmount << 128);
                    } else {
                        settlementDelta |= (MASK_KEEP_0_128 << 128);
                    }
                    m.lowestAsk = uint80(price);
                } else {
                    feeAmount =
                        amountOut -
                        (amountOut * uint256(m.takerFee)) /
                        100000;
                    amountOut -= feeAmount;
                    m.highestBid = uint80(price);
                }
                if (address(uint160(priceAndReferrer >> 80)) == address(0)) {
                    uint256 creatorFee;
                    if (marketType == 3) {
                        creatorFee = (feeAmount * m.creatorFeeSplit) / 100;
                        claimableRewards[quoteAsset][m.creator] += creatorFee;
                    }
                    claimableRewards[quoteAsset][feeRecipient] += (feeAmount -
                        creatorFee);
                } else {
                    uint256 amountCommission = (feeAmount * feeCommission) /
                        100;
                    claimableRewards[quoteAsset][
                        address(uint160(priceAndReferrer >> 80))
                    ] += amountCommission;
                    uint256 creatorFee;
                    if (marketType == 3) {
                        creatorFee = (feeAmount * m.creatorFeeSplit) / 100;
                        claimableRewards[quoteAsset][m.creator] += creatorFee;
                    }
                    claimableRewards[quoteAsset][feeRecipient] += (feeAmount -
                        amountCommission -
                        creatorFee);
                }
                assembly {
                    price := mload(0x80)
                }
                emit ICrystal.Trade(
                    market,
                    address(uint160(orderInfo)),
                    ((orderInfo >> 244) & 1) == 0,
                    amountIn,
                    amountOut,
                    price >> 128,
                    price & MASK_KEEP_0_128
                );
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
    function _limitOrder(
        bool isBuy,
        bool isRecieveTokens,
        uint256 price,
        uint256 size,
        uint256 userId,
        uint256 cloid
    ) internal returns (uint256, uint256 id) {
        // cloid being under uint10 is enforced in entry points
        unchecked {
            ICrystal.Market storage m = _getMarket[market];
            if (isBuy) {
                (uint256 highestBid, uint256 lowestAsk) = (
                    m.highestBid,
                    m.lowestAsk
                );
                if (
                    price >= lowestAsk ||
                    (m.isAMMEnabled &&
                        m.reserveQuote != 0 &&
                        price >
                        ((uint256(m.reserveQuote) *
                            scaleFactor *
                            10000 *
                            uint256(m.makerRebate) +
                            (uint256(m.reserveBase) * 9975 * 100000 - 1)) /
                            (uint256(m.reserveBase) * 9975 * 100000))) ||
                    (cloid != 0 &&
                        (orders[(cloid << 41) | userId] & MASK_OUT_113_154) !=
                        0) ||
                    price == 0 ||
                    size <
                    ((m.minSize >> 20) * 10 ** (m.minSize & MASK_KEEP_0_20))
                ) {
                    return (0, 0);
                }
                if (price > highestBid) {
                    m.highestBid = uint80(price);
                }
                if (!isRecieveTokens) {
                    require(
                        ((tokenBalances[userId][quoteAsset] >> 128) + size) <=
                            MASK_KEEP_0_128
                    );
                    tokenBalances[userId][quoteAsset] += (size << 128); // lock tokens if internal
                }
            } else {
                (uint256 highestBid, uint256 lowestAsk) = (
                    m.highestBid,
                    m.lowestAsk
                );
                if (
                    price <= highestBid ||
                    (m.isAMMEnabled &&
                        m.reserveQuote != 0 &&
                        price <
                        ((uint256(m.reserveQuote) *
                            scaleFactor *
                            9975 *
                            100000) /
                            (uint256(m.reserveBase) *
                                10000 *
                                uint256(m.makerRebate)))) ||
                    (cloid != 0 &&
                        (orders[(cloid << 41) | userId] & MASK_OUT_113_154) !=
                        0) ||
                    price >= maxPrice ||
                    ((size * price) / scaleFactor) <
                    ((m.minSize >> 20) * 10 ** (m.minSize & MASK_KEEP_0_20))
                ) {
                    return (0, 0);
                }
                if (price < lowestAsk) {
                    m.lowestAsk = uint80(price);
                }
                if (!isRecieveTokens) {
                    require(
                        ((tokenBalances[userId][baseAsset] >> 128) + size) <=
                            MASK_KEEP_0_128
                    );
                    tokenBalances[userId][baseAsset] += (size << 128); // lock tokens if internal
                }
            }
            uint256 _priceLevel = priceLevels[marketId | price];
            require(
                (size <= MASK_KEEP_0_112) &&
                    ((_priceLevel & MASK_KEEP_0_112) + size) <= MASK_KEEP_0_112
            ); // overflow check, if invalid params are entered could revert instead of silent return
            if (cloid != 0) {
                uint256 orderpointer = ((cloid | 1) << 41) | userId;
                if (cloid & 1 != 0) {
                    cloidVerify[orderpointer] =
                        (cloidVerify[orderpointer] & MASK_OUT_0_128) |
                        ((marketId >> 48) | price);
                } else {
                    cloidVerify[orderpointer] =
                        (cloidVerify[orderpointer] & MASK_KEEP_0_128) |
                        ((marketId << 80) | (price << 128));
                }
                cloid = (cloid << 41) | userId; // cloid to pointer using userid
                if ((_priceLevel & MASK_KEEP_0_112) == 0) {
                    require(price % tickSize == 0);
                    uint256 tick = marketType == 0
                        ? (price / tickSize)
                        : _priceToTick(price);
                    uint256 slot = activated[marketId | (tick / 255)] &
                        MASK_OUT_255_256;
                    activated[marketId | (tick / 255)] =
                        slot |
                        (1 << (tick % 255)) |
                        MASK_KEEP_255_256;
                    if (slot == 0) {
                        activated2[marketId | ((tick / 255) / 255)] |=
                            (1 << ((tick / 255) % 255)) |
                            MASK_KEEP_255_256;
                    }
                    _priceLevel =
                        (cloid << 205) |
                        (_priceLevel & MASK_OUT_205_256); // set fillNext to cloid
                } else {
                    uint256 fillBefore = (_priceLevel >> 154) & MASK_KEEP_0_51;
                    orders[
                        (fillBefore > MASK_KEEP_0_41)
                            ? fillBefore
                            : (marketId | (price << 48) | fillBefore)
                    ] =
                        (cloid << 205) |
                        (orders[
                            (fillBefore > MASK_KEEP_0_41)
                                ? fillBefore
                                : (marketId | (price << 48) | fillBefore)
                        ] & MASK_OUT_205_256); // set fillbefores fillafter to cloid instead of prev native id
                }
                orders[cloid] =
                    ((((_priceLevel >> 113) & MASK_KEEP_0_41) + 1) << 205) |
                    (_priceLevel & (MASK_KEEP_0_51 << 154)) |
                    (userId << 113) |
                    (isRecieveTokens ? 0 : (1 << 112)) |
                    size; // fillAfter to priceLevels latestNativeId+1, fillBefore to latest
                priceLevels[marketId | price] =
                    (cloid << 154) |
                    ((_priceLevel & MASK_OUT_154_205) + size); // latest to cloid and add size
                return (size, cloid);
            } else {
                id = ((_priceLevel >> 113) & MASK_KEEP_0_41) + 1;
                require(id <= MASK_KEEP_0_41); // overflow uint41
                if ((_priceLevel & MASK_KEEP_0_112) == 0) {
                    require(price % tickSize == 0);
                    uint256 tick = marketType == 0
                        ? (price / tickSize)
                        : _priceToTick(price);
                    uint256 slot = activated[marketId | (tick / 255)] &
                        MASK_OUT_255_256;
                    activated[marketId | (tick / 255)] =
                        slot |
                        (1 << (tick % 255)) |
                        MASK_KEEP_255_256;
                    if (slot == 0) {
                        activated2[marketId | ((tick / 255) / 255)] |=
                            (1 << ((tick / 255) % 255)) |
                            MASK_KEEP_255_256;
                    }
                    _priceLevel =
                        (id << 205) |
                        (_priceLevel & MASK_OUT_205_256); // set fillNext to id, sometimes redundant
                }
                orders[marketId | (price << 48) | id] =
                    ((id + 1) << 205) |
                    (_priceLevel & (MASK_KEEP_0_51 << 154)) |
                    (userId << 113) |
                    (isRecieveTokens ? 0 : (1 << 112)) |
                    size; // fillAfter to id+1, fillBefore to latest
                priceLevels[marketId | price] =
                    (id << 154) |
                    (id << 113) |
                    ((_priceLevel & MASK_OUT_113_205) + size); // latest and latestNativeId to id and add size
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
    function _cancelOrder(
        uint256 price,
        uint256 id,
        uint256 userId
    ) internal returns (uint256, uint256 size, bool isBuy) {
        // id is cloid if price is missing
        unchecked {
            ICrystal.Market storage m = _getMarket[market];
            uint256 _order = orders[
                (
                    price != 0
                        ? (marketId | (price << 48) | id)
                        : ((id << 41) | userId)
                )
            ]; // id is not yet pointer
            size = (_order & MASK_KEEP_0_112);
            if (0 == size || userId != ((_order >> 113) & MASK_KEEP_0_41)) {
                return (0, 0, isBuy);
            }
            if (price == 0) {
                price = cloidVerify[((id | 1) << 41) | userId]; // avoid stack too deep, there's no reason to zero out/edit this as it's not needed
                if (id & 1 != 0) {
                    // make sure order is in right market, get price because cloid doesn't come with it
                    if (((price >> 80) & MASK_KEEP_0_48) != (marketId >> 128)) {
                        return (0, 0, isBuy);
                    }
                    price = price & MASK_KEEP_0_80;
                } else {
                    if (
                        ((price >> 208) & MASK_KEEP_0_48) != (marketId >> 128)
                    ) {
                        return (0, 0, isBuy);
                    }
                    price = (price >> 128) & MASK_KEEP_0_80;
                }
                id = (id << 41) | userId; // id to pointer using userid
                orders[id] &= MASK_KEEP_113_154;
            } else {
                delete orders[marketId | (price << 48) | id];
            }
            (uint256 highestBid, uint256 lowestAsk) = (
                m.highestBid,
                m.lowestAsk
            );
            if (price <= highestBid) {
                isBuy = true;
                if ((_order & MASK_KEEP_112_113) != 0) {
                    tokenBalances[userId][quoteAsset] -= (size << 128); // unlock tokens if internal can't overflow
                }
            } else {
                if ((_order & MASK_KEEP_112_113) != 0) {
                    tokenBalances[userId][baseAsset] -= (size << 128); // unlock tokens if internal can't overflow
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
    function _decreaseOrder(
        uint256 price,
        uint256 id,
        uint256 decreaseAmount,
        uint256 userId
    ) internal returns (uint256, uint256 size, bool isBuy) {
        // id is cloid if price is missing
        unchecked {
            ICrystal.Market storage m = _getMarket[market];
            uint256 _order = orders[
                (
                    price != 0
                        ? (marketId | (price << 48) | id)
                        : ((id << 41) | userId)
                )
            ]; // id is not yet pointer
            size = (_order & MASK_KEEP_0_112);
            if (
                0 == size ||
                userId != ((_order >> 113) & MASK_KEEP_0_41) ||
                decreaseAmount > MASK_KEEP_0_112
            ) {
                return (0, 0, isBuy);
            }
            if (price == 0) {
                price = cloidVerify[((id | 1) << 41) | userId]; // avoid stack too deep, there's no reason to zero out/edit this as it's not needed
                if (id & 1 != 0) {
                    // make sure order is in right market, get price because cloid doesn't come with it
                    if (((price >> 80) & MASK_KEEP_0_48) != (marketId >> 128)) {
                        return (0, 0, isBuy);
                    }
                    price = price & MASK_KEEP_0_80;
                } else {
                    if (
                        ((price >> 208) & MASK_KEEP_0_48) != (marketId >> 128)
                    ) {
                        return (0, 0, isBuy);
                    }
                    price = (price >> 128) & MASK_KEEP_0_80;
                }
                id = (id << 41) | userId; // id to pointer using userid
            }
            (uint256 highestBid, uint256 lowestAsk) = (
                m.highestBid,
                m.lowestAsk
            );
            if (price <= highestBid) {
                isBuy = true;
            }
            if (
                (isBuy ? size : ((size * price) / scaleFactor)) <
                (
                    isBuy
                        ? decreaseAmount
                        : ((decreaseAmount * price) / scaleFactor)
                ) +
                    (((m.minSize >> 20) * 10 ** (m.minSize & MASK_KEEP_0_20)))
            ) {
                // cancel if resulting order would be too small
                if ((_order & MASK_KEEP_112_113) != 0) {
                    isBuy
                        ? tokenBalances[userId][quoteAsset] -= (size << 128)
                        : tokenBalances[userId][baseAsset] -= (size << 128); // unlock tokens if internal can't overflow
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
                    isBuy
                        ? tokenBalances[userId][
                            quoteAsset
                        ] -= (decreaseAmount << 128)
                        : tokenBalances[userId][baseAsset] -= (decreaseAmount <<
                        128); // unlock tokens if internal can't overflow
                }
                orders[
                    (id > MASK_KEEP_0_41 ? id : (marketId | (price << 48) | id))
                ] -= decreaseAmount; // can't overflow
                priceLevels[marketId | price] -= decreaseAmount;
                return (price, decreaseAmount << 128, isBuy); // price, decrease amount, isBuy
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
    function _replaceOrder(
        uint256 options,
        uint256 price,
        uint256 id,
        uint256 newPrice,
        uint256 newSize
    ) internal returns (int256 quoteAssetDebt, int256 baseAssetDebt, uint256) {
        unchecked {
            bool isBuy;
            bool isCloid;
            uint256 prevSize;
            uint256 userId = (options & MASK_KEEP_0_41);
            if (price == 0) {
                isCloid = true;
                price = cloidVerify[((id | 1) << 41) | userId]; // avoid stack too deep, there's no reason to zero out/edit this as it's not needed
                if (id & 1 != 0) {
                    // make sure order is in right market, get price because cloid doesn't come with it
                    if (((price >> 80) & MASK_KEEP_0_48) != (marketId >> 128)) {
                        return (0, 0, 0);
                    }
                    price = price & MASK_KEEP_0_80;
                } else {
                    if (
                        ((price >> 208) & MASK_KEEP_0_48) != (marketId >> 128)
                    ) {
                        return (0, 0, 0);
                    }
                    price = (price >> 128) & MASK_KEEP_0_80;
                }
                prevSize = (orders[((id << 41) | userId)] & MASK_KEEP_0_112); // id is not pointer
            } else {
                prevSize = (orders[(marketId | (price << 48) | id)] &
                    MASK_KEEP_0_112); // id is not pointer
            }
            if (price <= _getMarket[market].highestBid) {
                isBuy = true;
            }
            if ((newPrice & MASK_KEEP_0_80) == 0) {
                newPrice += price;
            }
            if (
                (((options >> 48) & 1) != 0) ||
                ((newPrice & MASK_KEEP_0_80) == price && (prevSize > newSize))
            ) {
                if (prevSize <= newSize) {
                    return (0, 0, 0); // no state is changed, can silent return
                }
                (price, prevSize, isBuy) = _decreaseOrder(
                    isCloid ? 0 : price,
                    id,
                    prevSize - newSize,
                    userId
                ); // price is 0 if cloid
                if (isCloid) {
                    id = (id << 41) | userId; // differentiate emitted cloid
                }
                if (prevSize != 0) {
                    if ((prevSize >> 128) == 0) {
                        // cancel
                        isBuy
                            ? quoteAssetDebt -= int256(prevSize)
                            : baseAssetDebt -= int256(prevSize);
                        _addToOrdersUpdatedEvent(
                            (isBuy ? 0 : LEADING_HEX_1) |
                                (price << 168) |
                                (id << 112) |
                                prevSize
                        ); // 3 bits flag 80 price 56 id 112 cancel size
                    } else {
                        isBuy
                            ? quoteAssetDebt -= int256(prevSize >> 128)
                            : baseAssetDebt -= int256(prevSize >> 128);
                        _addToOrdersUpdatedEvent(
                            (LEADING_HEX_4 + (isBuy ? 0 : LEADING_HEX_1)) |
                                (price << 168) |
                                (id << 112) |
                                (prevSize >> 128)
                        ); // 3 bits flag 80 price 56 id 112 decrease size not remaining
                    }
                    return (quoteAssetDebt, baseAssetDebt, id);
                } else {
                    return (0, 0, 0); // no state is changed, can silent return
                }
            } else {
                (price, prevSize, isBuy) = _cancelOrder(
                    (isCloid) ? 0 : price,
                    id,
                    userId
                ); // price is 0 if cloid
                if (isCloid) {
                    id = (id << 41) | userId; // differentiate emitted cloid
                }
                if (prevSize != 0) {
                    isBuy
                        ? quoteAssetDebt -= int256(prevSize)
                        : baseAssetDebt -= int256(prevSize);
                    _addToOrdersUpdatedEvent(
                        (isBuy ? 0 : LEADING_HEX_1) |
                            (price << 168) |
                            (id << 112) |
                            prevSize
                    ); // 3 bits flag 80 price 56 id 112 size
                } else {
                    return (0, 0, 0); // no state is changed, can silent return
                }
                if (isCloid) {
                    id = id >> 41; // back to normal cloid
                } else {
                    id = 0;
                }
                if (newSize == 0) {
                    newSize = prevSize;
                }
                if (((options >> 44) & 1) == 0) {
                    // post only
                    (prevSize, id) = _limitOrder(
                        isBuy,
                        (((options >> 60) & 1) == 0),
                        (newPrice & MASK_KEEP_0_80),
                        newSize,
                        userId,
                        id
                    );
                    if (prevSize != 0) {
                        isBuy
                            ? quoteAssetDebt += int256(prevSize)
                            : baseAssetDebt += int256(prevSize);
                        _addToOrdersUpdatedEvent(
                            (LEADING_HEX_2 + (isBuy ? 0 : LEADING_HEX_1)) |
                                ((newPrice & MASK_KEEP_0_80) << 168) |
                                (id << 112) |
                                prevSize
                        ); // 3 bits flag 80 price 56 id 112 size
                    } else {
                        return (quoteAssetDebt, baseAssetDebt, 0);
                    }
                } else {
                    isCloid = ((options >> 60) & 1) == 0; // avoid stack too deep, true if external balances
                    uint256 settlementDelta;
                    uint256 caller = (options >> 96);
                    uint256 orderInfo = (2 << 252) |
                        (isBuy ? 0 : (1 << 244)) |
                        (1 << 240) |
                        (isCloid ? 0 : (1 << 236)) |
                        (id << 208) |
                        (userId << 160) |
                        caller;
                    (, prevSize, id, settlementDelta) = _marketOrder(
                        newSize,
                        newPrice,
                        orderInfo
                    );
                    if (isBuy) {
                        quoteAssetDebt += int256(settlementDelta >> 128);
                        baseAssetDebt -= int256(
                            prevSize + (settlementDelta & MASK_KEEP_0_128)
                        ); // doesn't overflow because intrinsic is uint128
                    } else {
                        baseAssetDebt += int256(settlementDelta >> 128);
                        quoteAssetDebt -= int256(
                            prevSize + (settlementDelta & MASK_KEEP_0_128)
                        ); // doesn't overflow because intrinsic is uint128
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
    function marketOrder(
        bool isBuy,
        bool isExactInput,
        uint256 options,
        uint256 orderType,
        uint256 size,
        uint256 worstPrice,
        address referrer,
        address user
    )
        external
        payable
        returns (uint256 amountIn, uint256 amountOut, uint256 id)
    {
        unchecked {
            uint256 orderInfo; // options is 0-44 userId 44-54 cloid 56-60 stp 60-64 tointernalbalances 64-68 frominternalbalances 68-72 useinternalbalances
            uint256 userId;
            {
                uint256 orderFlags = ((orderType & 0xF) << 252) |
                    ((isExactInput ? 0 : (1 << 248))) |
                    ((isBuy ? 0 : (1 << 244))) |
                    (((options >> 56) & 0xF) << 240); // ordertype exactinput=0 isbuy=0 stp
                orderInfo =
                    orderFlags |
                    (((options >> 68) & 1) << 236) |
                    (((options >> 64) & 1) << 232) |
                    uint160(user); // useexternalbalance=0 fromcaller=0 add userId 160-208 if internal balance or mtl and cloid if provided 208-218 if mtl and margin enforced elsewhere
                userId = (options & MASK_KEEP_0_41);
                if (userId != 0) {
                    require(userIdToAddress[userId] == user);
                } else {
                    userId = addressToUserId[user];
                    if (userId == 0) {
                        userId = ICrystal(crystal).registerUser(user);
                    }
                }
                orderInfo |= (userId << 160); // add userId to orderInfo
                if (((options >> 44) & MASK_KEEP_0_10) != 0) {
                    // if cloid
                    orderInfo |= (((options >> 44) & MASK_KEEP_0_10) << 208);
                }
            }
            uint256 settlementDelta;
            assembly {
                mstore(0x40, 0xe0) // 0x80 is used by _marketOrder internally to avoid stack too deep
            }
            (amountIn, amountOut, id, settlementDelta) = _marketOrder(
                size,
                (uint160(referrer) << 80) | worstPrice,
                orderInfo
            );
            address _market = market;
            assembly {
                let length := mload(0xc0)
                if gt(length, 0) {
                    mstore(0xa0, 0x20)
                    log3(
                        0xa0,
                        add(length, 0x40),
                        ORDERS_UPDATED_SIG,
                        _market,
                        user
                    )
                }
            }
            address token = isBuy ? quoteAsset : baseAsset;
            if ((settlementDelta >> 128) != 0) {
                // input token for both limit order and maker internal balance fills
                if (((options >> 68) & 1) != 0) {
                    uint256 balance = tokenBalances[userId][token];
                    if (uint128(balance) < (settlementDelta >> 128)) {
                        revert ICrystal.ActionFailed();
                    } else {
                        tokenBalances[userId][token] =
                            balance -
                            (settlementDelta >> 128);
                    }
                } else {
                    // use external balance
                    if (((options >> 64) & 1) != 0) {
                        // use router balance
                        uint256 balance = tokenBalances[0][token];
                        if (uint128(balance) < (settlementDelta >> 128)) {
                            revert ICrystal.ActionFailed();
                        } else {
                            tokenBalances[0][token] =
                                balance -
                                (settlementDelta >> 128);
                        }
                    } else {
                        IERC20(token).transferFrom(
                            msg.sender,
                            address(this),
                            (settlementDelta >> 128)
                        );
                    }
                }
            }
            settlementDelta = (settlementDelta & MASK_KEEP_0_128) + amountOut; // add output to self cancel credit
            token = isBuy ? baseAsset : quoteAsset;
            if (settlementDelta != 0) {
                // output token, stp cancels + amountout
                if (((options >> 68) & 1) != 0) {
                    require(
                        ((tokenBalances[userId][token] & MASK_KEEP_0_128) +
                            settlementDelta) <= MASK_KEEP_0_128
                    );
                    tokenBalances[userId][token] += settlementDelta;
                } else {
                    // use external balance
                    if (((options >> 60) & 1) != 0) {
                        require(
                            ((tokenBalances[0][token] & MASK_KEEP_0_128) +
                                settlementDelta) <= MASK_KEEP_0_128
                        );
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
    function limitOrder(
        bool isBuy,
        uint256 options,
        uint256 price,
        uint256 size,
        address user
    ) external payable returns (uint256 id) {
        // options is 0-41 userId 44-54 cloid 56-60 frominternalbalances 60-64 useinternalbalances
        unchecked {
            uint256 userId = (options & MASK_KEEP_0_41);
            if (userId != 0) {
                // if userId is supplied verify
                require(userIdToAddress[userId] == user);
            } else {
                // get default userId
                userId = addressToUserId[user];
                if (userId == 0) {
                    userId = ICrystal(crystal).registerUser(user);
                }
            }
            bool useExternalBalances = (((options >> 60) & 1) == 0);
            (size, id) = _limitOrder(
                isBuy,
                useExternalBalances,
                price,
                size,
                userId,
                (options >> 44) & MASK_KEEP_0_10
            );
            if (size != 0) {
                // if order success
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
                        IERC20(token).transferFrom(
                            msg.sender,
                            address(this),
                            size
                        );
                    }
                } else {
                    uint256 balance = tokenBalances[userId][token];
                    if (uint128(balance) < size) {
                        revert ICrystal.ActionFailed();
                    } else {
                        tokenBalances[userId][token] = balance - size; // token txfer don't care about locking since done in internal function
                    }
                }
                emit ICrystal.OrdersUpdated(
                    market,
                    user,
                    abi.encodePacked(
                        (isBuy ? LEADING_HEX_2 : LEADING_HEX_3) |
                            (price << 168) |
                            (id << 112) |
                            size
                    )
                ); // if id is a cloid it is already merged w user id
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
    function cancelOrder(
        uint256 options,
        uint256 price,
        uint256 id,
        address user
    ) external payable returns (uint256 size) {
        // options is 0-41 userId 44-48 tointernalbalances 48-52 useinternalbalances
        unchecked {
            bool isBuy;
            uint256 userId = (options & MASK_KEEP_0_41);
            if (userId != 0) {
                // if userId is supplied verify
                require(userIdToAddress[userId] == user);
            } else {
                // get default userId
                userId = addressToUserId[user];
            }
            bool useExternalBalances = (((options >> 48) & 1) == 0);
            bool isCloid = (price == 0); // if price isn't 0 assume it's a normal order
            (price, size, isBuy) = _cancelOrder(price, id, userId); // if no price attached update price
            if (isCloid) {
                id = (id << 41) | userId;
            }
            if (size != 0) {
                // if cancel success
                address token = isBuy ? quoteAsset : baseAsset;
                if (useExternalBalances) {
                    if (((options >> 44) & 1) != 0) {
                        require(
                            ((tokenBalances[0][token] & MASK_KEEP_0_128) +
                                size) <= MASK_KEEP_0_128
                        );
                        tokenBalances[0][token] += size;
                    } else {
                        IERC20(token).transfer(msg.sender, size);
                    }
                } else {
                    require(
                        ((tokenBalances[userId][token] & MASK_KEEP_0_128) +
                            size) <= MASK_KEEP_0_128
                    );
                    tokenBalances[userId][token] += size;
                }
                emit ICrystal.OrdersUpdated(
                    market,
                    user,
                    abi.encodePacked(
                        (isBuy ? 0 : LEADING_HEX_1) |
                            (price << 168) |
                            (id << 112) |
                            size
                    )
                );
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
    function replaceOrder(
        uint256 options,
        uint256 price,
        uint256 id,
        uint256 newPrice,
        uint256 size,
        address referrer,
        address user
    ) external payable returns (uint256 _id) {
        // options is 0-41 userId 44-48 postOnly=0 48-52 isDecrease 52-56 tointernalbalances 56-60 frominternalbalances 60-64 useinternalbalances
        int256 quoteAssetDebt;
        int256 baseAssetDebt;
        uint256 userId = (options & MASK_KEEP_0_41);
        if (userId != 0) {
            // if userId is supplied verify
            require(userIdToAddress[userId] == user);
        } else {
            // get default userId
            userId = addressToUserId[user];
            if (userId == 0) {
                userId = ICrystal(crystal).registerUser(user);
            }
            options = (options & MASK_OUT_0_41) | userId; // add userId to options
        }
        options = (uint160(user) << 96) | (options & MASK_KEEP_0_96);
        newPrice = (uint160(referrer) << 80) | newPrice;
        assembly {
            mstore(0x40, 0xe0) // 0x80 is used by _marketOrder internally to avoid stack too deep
        }
        (quoteAssetDebt, baseAssetDebt, _id) = _replaceOrder(
            options,
            price,
            id,
            newPrice,
            size
        );
        uint256 balanceMode = options; // avoid stack too deep
        _settleBalances(
            quoteAssetDebt,
            baseAssetDebt,
            userId,
            ((balanceMode >> 60) & 1),
            ((balanceMode >> 52) & 1),
            ((balanceMode >> 56) & 1)
        );
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
    function batchOrders(
        ICrystal.Action[] calldata actions,
        uint256 options,
        address referrer,
        address user
    ) external payable {
        // options is 0-41 userId 44-48 tointernalbalances 48-52 frominternalbalances 52-56 useinternalbalances
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
                // if userId is supplied verify
                userId = (options & MASK_KEEP_0_41);
                require(userIdToAddress[userId] == user);
            } else {
                // get default userId
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
                    // cancel, pass either price and id or cloid
                    if (cloid != 0) {
                        (param1, action, isBuy) = _cancelOrder(
                            0,
                            cloid,
                            userId
                        );
                        param2 = (cloid << 41) | userId; // differentiate emitted cloid
                    } else {
                        (param1, action, isBuy) = _cancelOrder(
                            param1,
                            param2,
                            userId
                        );
                    }
                    if (action != 0) {
                        isBuy
                            ? quoteAssetDebt -= int256(action)
                            : baseAssetDebt -= int256(action);
                        _addToOrdersUpdatedEvent(
                            (isBuy ? 0 : LEADING_HEX_1) |
                                (param1 << 168) |
                                (param2 << 112) |
                                action
                        ); // 8 flag 80 price 56 id 112 cancel size
                    } else {
                        if (actions[offset].isRequireSuccess) {
                            revert ICrystal.ActionFailed();
                        }
                    }
                } else if (action == 2 || action == 3) {
                    // limit buy, pass price size and optional cloid
                    (cloid, param2) = _limitOrder(
                        (action & 1) == 0,
                        balanceMode == 0,
                        param1,
                        param2,
                        userId,
                        cloid
                    );
                    if (cloid != 0) {
                        ((action & 1) == 0)
                            ? quoteAssetDebt += int256(cloid)
                            : baseAssetDebt += int256(cloid);
                        _addToOrdersUpdatedEvent(
                            (
                                ((action & 1) == 0)
                                    ? LEADING_HEX_2
                                    : LEADING_HEX_3
                            ) |
                                (param1 << 168) |
                                (param2 << 112) |
                                cloid
                        ); // 8 flag 80 price 56 id 112 size
                    } else {
                        if (actions[offset].isRequireSuccess) {
                            revert ICrystal.ActionFailed();
                        }
                    }
                } else if (action > 3 && action < 12) {
                    // 4 mtl buy 5 mtl sell 6 partial buy 7 partial sell 8 partial buy stop when low gas 9 partial sell stop when low gas 10 complete buy 11 complete sell
                    uint256 settlementDelta;
                    settlementDelta = (uint160(referrer) << 80) | param1; // avoid stack too deep
                    param1 =
                        (uint256(
                            (action < 6)
                                ? 2
                                : (action < 8)
                                    ? 0
                                    : (action < 10)
                                        ? 3
                                        : 1
                        ) << 252) |
                        ((action & 1 != 0) ? (1 << 244) : 0); // reuse to save stack, represents ordertype and isbuy
                    (, param1, , settlementDelta) = _marketOrder(
                        param2,
                        settlementDelta,
                        param1 |
                            (1 << 240) |
                            (balanceMode << 236) |
                            (cloid << 208) |
                            (userId << 160) |
                            uint160(user)
                    );
                    if (action & 1 != 0) {
                        // sell
                        baseAssetDebt += int256(settlementDelta >> 128);
                        quoteAssetDebt -= int256(
                            param1 + (settlementDelta & MASK_KEEP_0_128)
                        ); // doesn't overflow because intrinsic is uint128
                    } else {
                        // buy
                        quoteAssetDebt += int256(settlementDelta >> 128);
                        baseAssetDebt -= int256(
                            param1 + (settlementDelta & MASK_KEEP_0_128)
                        ); // doesn't overflow because intrinsic is uint128
                    }
                } else if (action == 12) {
                    // decrease order, if price then use cloid else use id
                    bool isCloid;
                    if (param1 != 0) {
                        // if price is provided, id is used not cloid
                        cloid = actions[offset].param3;
                        cloid &= MASK_KEEP_0_41; // id is a uint41
                    } else {
                        isCloid = true;
                    }
                    (param1, param2, isBuy) = _decreaseOrder(
                        param1,
                        cloid,
                        param2,
                        userId
                    );
                    if (isCloid) {
                        cloid = (cloid << 41) | userId; // differentiate emitted cloid
                    }
                    if (param2 != 0) {
                        if ((param2 >> 128) == 0) {
                            // cancel
                            isBuy
                                ? quoteAssetDebt -= int256(param2)
                                : baseAssetDebt -= int256(param2);
                            _addToOrdersUpdatedEvent(
                                (isBuy ? 0 : LEADING_HEX_1) |
                                    (param1 << 168) |
                                    (cloid << 112) |
                                    param2
                            ); // 8 flag 80 price 56 id 112 cancel size
                        } else {
                            isBuy
                                ? quoteAssetDebt -= int256(param2 >> 128)
                                : baseAssetDebt -= int256(param2 >> 128);
                            _addToOrdersUpdatedEvent(
                                (LEADING_HEX_4 + (isBuy ? 0 : LEADING_HEX_1)) |
                                    (param1 << 168) |
                                    (cloid << 112) |
                                    (param2 >> 128)
                            ); // 8 flag 80 price 56 id 112 decrease size not remaining size
                        }
                    } else {
                        if (actions[offset].isRequireSuccess) {
                            revert ICrystal.ActionFailed();
                        }
                    }
                }
                ++offset;
            }
            param1 = options; // avoid stack too deep
            param2 = options; // avoid stack too deep
            _settleBalances(
                quoteAssetDebt,
                baseAssetDebt,
                userId,
                balanceMode,
                ((param1 >> 44) & 1),
                ((param2 >> 48) & 1)
            );
            address _market = market;
            assembly {
                let length := mload(0xc0)
                if gt(length, 0) {
                    mstore(0xa0, 0x20)
                    log3(
                        0xa0,
                        add(length, 0x40),
                        ORDERS_UPDATED_SIG,
                        _market,
                        user
                    )
                }
            }
        }
    }

    /**
     * @notice Processes tightly packed batch actions supplied via calldata.
     *
     * @dev First word carries user id and balance flags; subsequent words mirror `batchOrders` encoding.
     * @dev User ID is prevalidated.
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
                userId := and(MASK_KEEP_0_41, userId) // it's a uint41 but encoded like a uint44
            }
            offset += 32;
            while (offset < msg.data.length) {
                assembly {
                    // 4-8 is isRequireSuccess
                    action := calldataload(offset)
                    param1 := and(MASK_KEEP_0_80, shr(112, action)) // 64-144
                    param2 := and(MASK_KEEP_0_112, action) // 144-256
                    cloid := and(MASK_KEEP_0_10, shr(192, action)) // 20-64
                    action := shr(252, action) // 0-4
                }
                if (action == 1) {
                    // cancel, pass either price and id or cloid
                    if (cloid != 0) {
                        (param1, action, isBuy) = _cancelOrder(
                            0,
                            cloid,
                            userId
                        );
                        param2 = (cloid << 41) | userId; // differentiate emitted cloid
                    } else {
                        (param1, action, isBuy) = _cancelOrder(
                            param1,
                            param2,
                            userId
                        );
                    }
                    if (action != 0) {
                        isBuy
                            ? quoteAssetDebt -= int256(action)
                            : baseAssetDebt -= int256(action);
                        _addToOrdersUpdatedEvent(
                            (isBuy ? 0 : LEADING_HEX_1) |
                                (param1 << 168) |
                                (param2 << 112) |
                                action
                        ); // 8 flag 80 price 56 id 112 cancel size
                    } else {
                        assembly {
                            // reuse isBuy as isRequireSuccess
                            isBuy := and(0x1, shr(248, calldataload(offset))) // 4-8
                        }
                        if (isBuy) {
                            revert ICrystal.ActionFailed();
                        }
                    }
                } else if (action == 2 || action == 3) {
                    // limit buy, pass price size and optional cloid
                    (cloid, param2) = _limitOrder(
                        (action & 1) == 0,
                        balanceMode == 0,
                        param1,
                        param2,
                        userId,
                        cloid
                    );
                    if (cloid != 0) {
                        ((action & 1) == 0)
                            ? quoteAssetDebt += int256(cloid)
                            : baseAssetDebt += int256(cloid);
                        _addToOrdersUpdatedEvent(
                            (
                                ((action & 1) == 0)
                                    ? LEADING_HEX_2
                                    : LEADING_HEX_3
                            ) |
                                (param1 << 168) |
                                (param2 << 112) |
                                cloid
                        ); // 8 flag 80 price 56 id 112 size
                    } else {
                        assembly {
                            // reuse isBuy as isRequireSuccess
                            isBuy := and(0x1, shr(248, calldataload(offset))) // 4-8
                        }
                        if (isBuy) {
                            revert ICrystal.ActionFailed();
                        }
                    }
                } else if (action > 3 && action < 12) {
                    // 4 mtl buy 5 mtl sell 6 partial buy 7 partial sell 8 partial buy stop when low gas 9 partial sell stop when low gas 10 complete buy 11 complete sell
                    uint256 settlementDelta;
                    settlementDelta = (uint160(msg.sender) << 80) | param1; // avoid stack too deep
                    param1 =
                        (uint256(
                            (action < 6)
                                ? 2
                                : (action < 8)
                                    ? 0
                                    : (action < 10)
                                        ? 3
                                        : 1
                        ) << 252) |
                        (((action & 1) != 0) ? (1 << 244) : 0); // reuse to save stack, represents ordertype and isbuy
                    (, param1, , settlementDelta) = _marketOrder(
                        param2,
                        settlementDelta,
                        param1 |
                            (1 << 240) |
                            (balanceMode << 236) |
                            (cloid << 208) |
                            (userId << 160) |
                            uint160(msg.sender)
                    );
                    if (action & 1 != 0) {
                        // sell
                        baseAssetDebt += int256(settlementDelta >> 128);
                        quoteAssetDebt -= int256(
                            param1 + (settlementDelta & MASK_KEEP_0_128)
                        ); // doesn't overflow because intrinsic is uint128
                    } else {
                        // buy
                        quoteAssetDebt += int256(settlementDelta >> 128);
                        baseAssetDebt -= int256(
                            param1 + (settlementDelta & MASK_KEEP_0_128)
                        ); // doesn't overflow because intrinsic is uint128
                    }
                } else if (action == 12) {
                    // decrease order, if price then use cloid else use id
                    bool isCloid;
                    if (param1 != 0) {
                        // if price is provided, id is used not cloid
                        assembly {
                            cloid := and(
                                MASK_KEEP_0_41,
                                shr(192, calldataload(offset))
                            ) // id is a uint41, 16-64
                        }
                    } else {
                        isCloid = true;
                    }
                    (param1, param2, isBuy) = _decreaseOrder(
                        param1,
                        cloid,
                        param2,
                        userId
                    );
                    if (isCloid) {
                        cloid = (cloid << 41) | userId; // differentiate emitted cloid
                    }
                    if (param2 != 0) {
                        if ((param2 >> 128) == 0) {
                            // cancel
                            isBuy
                                ? quoteAssetDebt -= int256(param2)
                                : baseAssetDebt -= int256(param2);
                            _addToOrdersUpdatedEvent(
                                (isBuy ? 0 : LEADING_HEX_1) |
                                    (param1 << 168) |
                                    (cloid << 112) |
                                    param2
                            ); // 8 flag 80 price 56 id 112 cancel size
                        } else {
                            isBuy
                                ? quoteAssetDebt -= int256(param2 >> 128)
                                : baseAssetDebt -= int256(param2 >> 128);
                            _addToOrdersUpdatedEvent(
                                (LEADING_HEX_4 + (isBuy ? 0 : LEADING_HEX_1)) |
                                    (param1 << 168) |
                                    (cloid << 112) |
                                    (param2 >> 128)
                            ); // 8 flag 80 price 56 id 112 decrease size not remaining size
                        }
                    } else {
                        assembly {
                            // reuse isBuy as isRequireSuccess
                            isBuy := and(0x1, shr(248, calldataload(offset))) // 4-8
                        }
                        if (isBuy) {
                            revert ICrystal.ActionFailed();
                        }
                    }
                }
                offset += 32;
            }
            _settleBalances(
                quoteAssetDebt,
                baseAssetDebt,
                userId,
                balanceMode,
                0,
                0
            );
            address _market = market;
            assembly {
                let length := mload(0xc0)
                if gt(length, 0) {
                    mstore(0xa0, 0x20)
                    log3(
                        0xa0,
                        add(length, 0x40),
                        ORDERS_UPDATED_SIG,
                        _market,
                        caller()
                    )
                }
            }
        }
    }

    /**
     * @notice Accepts native token transfers.
     */
    receive() external payable {}
}
