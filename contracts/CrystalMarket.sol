// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC20} from './interfaces/IERC20.sol';
import {ICrystal} from './interfaces/ICrystal.sol';

contract CrystalMarket {
    address private feeRecipient; // public is useless so everything isn't
    uint8 private feeCommission;
    uint8 private feeRebate;

    mapping (uint256 => address) private userIdToAddress; // 0 is an invalid userid
    mapping (address => uint256) private addressToUserId;
    mapping (address => ICrystal.Market) private _getMarket;
    mapping (uint256 => uint256) private activated; // marketid << 128 | slotindex
    mapping (uint256 => uint256) private priceLevels; // 0 is an invalid price marketid << 128 | price
    mapping (uint256 => uint256) private orders; // 0 is an invalid cloid, valid range 1-1023 mask 0x3FF; marketid << 128 | price << 48 | id or userid << 41 | cloid
    mapping (uint256 => uint256) private cloidVerify; // two cloids per slot map market and price, never zero slot 1 << 255 | marketId << 208 | price << 128 | marketId << 80 | price
    mapping (uint256 => mapping (address => uint256)) private tokenBalances;
    mapping (address => mapping (address => uint256)) private claimableRewards;

    address public immutable quoteAsset;
    address public immutable baseAsset;
    address public immutable crystal;
    uint256 public immutable marketType;
    uint256 public immutable scaleFactor;
    uint256 public immutable tickSize;
    uint256 public immutable maxPrice;
    address private immutable market; // address of market for when delegate called
    uint256 private immutable marketId; // 0 is an invalid marketid, is already << 128
    // lp erc20
    string public constant name = 'Crystal V2';
    string public constant symbol = 'CRY-V2';
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    bytes32 public DOMAIN_SEPARATOR;
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint256) public nonces;

    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);

    uint256 private constant MASK_OUT_113_154 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFC0000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 private constant MASK_OUT_0_128 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000000000000000000000000000;
    uint256 private constant MASK_OUT_205_256 = 0x0000000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 private constant MASK_OUT_113_205 = 0xFFFFFFFFFFFFE00000000000000000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 private constant MASK_OUT_154_205 = 0xFFFFFFFFFFFFE0000000000003FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 private constant MASK_OUT_0_80 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000000000000000;
    uint256 private constant MASK_OUT_0_41 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE0000000000;
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
    uint256 private constant LEADING_HEX_1 = 0x1000000000000000000000000000000000000000000000000000000000000000;
    uint256 private constant LEADING_HEX_2 = 0x2000000000000000000000000000000000000000000000000000000000000000;
    uint256 private constant LEADING_HEX_3 = 0x3000000000000000000000000000000000000000000000000000000000000000;
    uint256 private constant LEADING_HEX_4 = 0x4000000000000000000000000000000000000000000000000000000000000000;
    uint256 private constant FILL_SIG = 0xa195980963150be5fcca4acd6a80bf5a9de7f9c862258501b7c705e7d2c2d2f4;
    uint256 private constant ORDERS_UPDATED_SIG = 0x7ebb55d14fb18179d0ee498ab0f21c070fad7368e44487d51cdac53d6f74812c;

    constructor() {
        (quoteAsset, baseAsset, marketId, marketType, scaleFactor, tickSize, maxPrice) = ICrystal(msg.sender).parameters();
        marketId <<= 128;
        scaleFactor = 10 ** scaleFactor;
        market = address(this);
        crystal = msg.sender;
        require(quoteAsset != address(0) && baseAsset != address(0) && quoteAsset != baseAsset && maxPrice <= MASK_KEEP_0_80 && tickSize <= MASK_KEEP_0_80 && scaleFactor <= MASK_KEEP_0_112);
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes(name)),
                keccak256(bytes('1')),
                chainId,
                address(this)
            )
        );
    }

    function _approve(address owner, address spender, uint256 value) internal {
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _transfer(address from, address to, uint256 value) internal {
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
    }

    function mint(address to, uint256 value) external {
        require(msg.sender == crystal);
        totalSupply += value;
        balanceOf[to] += value;
        emit Transfer(address(0), to, value);
    }

    function burn(address from, uint256 value) external {
        require(msg.sender == crystal);
        balanceOf[from] -= value;
        totalSupply -= value;
        emit Transfer(from, address(0), value);
    }

    function approve(address spender, uint256 value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max && msg.sender != crystal) {
            allowance[from][msg.sender] -= value;
        }
        _transfer(from, to, value);
        return true;
    }

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(deadline >= block.timestamp, 'expired');
        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01',
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, 'invalid signature');
        _approve(owner, spender, value);
    }
    // methods above are to be called as an erc20, methods below are to be delegatecalled as part of crystal
    function getReserves() external payable returns (uint112 reserveQuote, uint112 reserveBase) {
        ICrystal.Market storage m = _getMarket[market];
        (reserveQuote, reserveBase) = (m.reserveQuote, m.reserveBase);
    }
    // premint is called to migrate launchpad liquidity, market can't be interacted with prior
    function premint(address to, uint256 amountQuoteDesired, uint256 amountBaseDesired) external payable returns (uint256 liquidity) { 
        ICrystal.Market storage m = _getMarket[market];
        liquidity = _sqrt(amountQuoteDesired * (amountBaseDesired)) - 1000;
        require(marketType == 3 && IERC20(market).totalSupply() == 0 && liquidity != 0 && amountQuoteDesired <= MASK_KEEP_0_112 && amountBaseDesired <= MASK_KEEP_0_112);
        IERC20(market).mint(address(0), 1000);
        IERC20(market).mint(to, liquidity);
        (m.reserveQuote, m.reserveBase) = (uint112(amountQuoteDesired), uint112(amountBaseDesired));
    }

    function addLiquidity(address to, uint256 amountQuoteDesired, uint256 amountBaseDesired, uint256 amountQuoteMin, uint256 amountBaseMin, uint256 options) external payable returns (uint256 liquidity) {
        ICrystal.Market storage m = _getMarket[market];
        (uint112 reserveQuote, uint112 reserveBase) = (m.reserveQuote, m.reserveBase);
        uint256 amountQuote;
        uint256 amountBase;
        uint256 _totalSupply = IERC20(market).totalSupply();
        if (_totalSupply == 0) {
            amountQuote = amountQuoteDesired;
            amountBase = amountBaseDesired;
            liquidity = _sqrt(amountQuote * (amountBase)) - 1000;
            IERC20(market).mint(address(0), 1000);
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
            liquidity = amountQuote * (_totalSupply) / reserveQuote < amountBase * (_totalSupply) / reserveBase ? amountQuote * (_totalSupply) / reserveQuote : amountBase * (_totalSupply) / reserveBase;
        }
        reserveQuote += uint112(amountQuote);
        reserveBase += uint112(amountBase);
        if ((options & 1) == 0) {
            IERC20(quoteAsset).transferFrom(msg.sender, address(this), amountQuote);
        }
        else {
            tokenBalances[0][quoteAsset] -= amountQuote; // checked
        }
        if ((options >> 4 & 1) == 0) {
            IERC20(baseAsset).transferFrom(msg.sender, address(this), amountBase);
        }
        else {
            tokenBalances[0][baseAsset] -= amountBase; // checked
        }
        IERC20(market).mint(to, liquidity);
        require(liquidity != 0 && amountQuote >= amountQuoteMin && amountBase >= amountBaseMin && reserveQuote <= MASK_KEEP_0_112 && reserveBase <= MASK_KEEP_0_112 && m.isAMMEnabled == true);
        (m.reserveQuote, m.reserveBase) = (reserveQuote, reserveBase);
        emit ICrystal.Sync(market, reserveQuote, reserveBase);
        emit ICrystal.Mint(market, msg.sender, amountQuote, amountBase);
    }

    function removeLiquidity(address to, uint256 liquidity, uint256 amountQuoteMin, uint256 amountBaseMin, uint256 options) external payable returns (uint256 amountQuote, uint256 amountBase) {
        ICrystal.Market storage m = _getMarket[market];
        (uint112 reserveQuote, uint112 reserveBase) = (m.reserveQuote, m.reserveBase);
        IERC20(market).transferFrom(msg.sender, address(this), liquidity);

        uint256 _totalSupply = IERC20(market).totalSupply();
        amountQuote = liquidity * reserveQuote / _totalSupply;
        amountBase = liquidity * reserveBase / _totalSupply;
        IERC20(market).burn(address(this), liquidity);
        if ((options & 1) == 0) {
            IERC20(quoteAsset).transfer(to, amountQuote);
        }
        else {
            tokenBalances[0][quoteAsset] += amountQuote;
        }
        if ((options >> 4 & 1) == 0) {
            IERC20(baseAsset).transfer(to, amountBase);
        }
        else {
            tokenBalances[0][baseAsset] += amountBase;
        }
        reserveQuote -= uint112(amountQuote); // checked
        reserveBase -= uint112(amountBase); // checked

        require(amountQuote >= amountQuoteMin && amountBase >= amountBaseMin);
        (m.reserveQuote, m.reserveBase) = (reserveQuote, reserveBase);
        emit ICrystal.Sync(market, reserveQuote, reserveBase);
        emit ICrystal.Burn(market, msg.sender, amountQuote, amountBase, to);
    }

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

    function _tickToPrice(uint256 t) internal view returns (uint256) {
        unchecked {
            if (t <= 100_000) return t * tickSize;
            uint256 x = t - 10_000;
            return 10 ** (x / 90_000) * (10_000 + (x % 90_000)) * tickSize;
        }
    }

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

    function _searchSlotUp(uint256 slot, uint256 tick) internal pure returns (uint256) {
        unchecked {
            if (slot & ((1 << 128) - 1) == 0) {slot >>= 128; tick += 128;}
            if (slot & ((1 << 64) - 1) == 0) {slot >>= 64; tick += 64;}
            if (slot & ((1 << 32) - 1) == 0) {slot >>= 32; tick += 32;}
            if (slot & ((1 << 16) - 1) == 0) {slot >>= 16; tick += 16;}
            if (slot & ((1 << 8) - 1) == 0) {slot >>= 8; tick += 8;}
            if (slot & ((1 << 4) - 1) == 0) {slot >>= 4; tick += 4;}
            if (slot & ((1 << 2) - 1) == 0) {slot >>= 2; tick += 2;}
            if (slot & 1 == 0) {++tick;}
            return tick;
        }
    }

    function _searchSlotDown(uint256 slot, uint256 tick) internal pure returns (uint256) {
        unchecked {
            if (slot >= 2 ** 128) {slot >>= 128; tick += 128;}
            if (slot >= 2 ** 64) {slot >>= 64; tick += 64;}
            if (slot >= 2 ** 32) {slot >>= 32; tick += 32;}
            if (slot >= 2 ** 16) {slot >>= 16; tick += 16;}
            if (slot >= 2 ** 8) {slot >>= 8; tick += 8;}
            if (slot >= 2 ** 4) {slot >>= 4; tick += 4;}
            if (slot >= 2 ** 2) {slot >>= 2; tick += 2;}
            if (slot >= 2 ** 1) {++tick;}
            return tick;
        }
    }

    function _addToOrdersUpdatedEvent(uint256 logData) internal {
        assembly {
            let length := mload(0xc0)
            mstore(add(length, 0xe0), logData)
            mstore(0xc0, add(length, 0x20))
            mstore(0x40, add(length, 0x100))
        }
    }

    function _settleBalances(int256 quoteAssetDebt, int256 baseAssetDebt, uint256 userId, uint256 balanceMode, uint256 balanceModeOut, uint256 balanceModeIn) internal {
        unchecked {
            if (balanceMode == 0) { // external txfers
                if (balanceModeIn != 0) {
                    if (quoteAssetDebt > 0) {
                        uint256 balance = tokenBalances[0][quoteAsset];
                        if (uint128(balance) < uint256(quoteAssetDebt)) {
                            revert ICrystal.ActionFailed();
                        }
                        else {
                            tokenBalances[0][quoteAsset] = balance - uint256(quoteAssetDebt);
                        }
                    }
                    if (baseAssetDebt > 0) {
                        uint256 balance = tokenBalances[0][baseAsset];
                        if (uint128(balance) < uint256(baseAssetDebt)) {
                            revert ICrystal.ActionFailed();
                        }
                        else {
                            tokenBalances[0][baseAsset] = balance - uint256(baseAssetDebt);
                        }
                    }
                }
                else {
                    if (quoteAssetDebt > 0) {
                        IERC20(quoteAsset).transferFrom(msg.sender, address(this), uint256(quoteAssetDebt));
                    }
                    if (baseAssetDebt > 0) {
                        IERC20(baseAsset).transferFrom(msg.sender, address(this), uint256(baseAssetDebt));
                    }
                }
                if (balanceModeOut != 0) {
                    if (quoteAssetDebt < 0) {
                        tokenBalances[0][quoteAsset] += uint256(-quoteAssetDebt);
                    }
                    if (baseAssetDebt < 0) {
                        tokenBalances[0][baseAsset] += uint256(-baseAssetDebt);
                    }
                }
                else {
                    if (quoteAssetDebt < 0) {
                        IERC20(quoteAsset).transfer(msg.sender, uint256(-quoteAssetDebt));
                    }
                    if (baseAssetDebt < 0) {
                        IERC20(baseAsset).transfer(msg.sender, uint256(-baseAssetDebt));
                    }
                }
            }
            else {
                if (balanceMode == 1) { // internal balances
                    if (quoteAssetDebt > 0) {
                        uint256 balance = tokenBalances[userId][quoteAsset];
                        if (uint128(balance) < uint256(quoteAssetDebt)) {
                            revert ICrystal.ActionFailed();
                        }
                        else {
                            tokenBalances[userId][quoteAsset] = balance - uint256(quoteAssetDebt);
                        }
                    }
                    else if (quoteAssetDebt < 0) {
                        tokenBalances[userId][quoteAsset] += uint256(-quoteAssetDebt);
                    }
                    if (baseAssetDebt > 0) {
                        uint256 balance = tokenBalances[userId][baseAsset];
                        if (uint128(balance) < uint256(baseAssetDebt)) {
                            revert ICrystal.ActionFailed();
                        }
                        else {
                            tokenBalances[userId][baseAsset] = balance - uint256(baseAssetDebt);
                        }
                    }
                    else if (baseAssetDebt < 0) {
                        tokenBalances[userId][baseAsset] += uint256(-baseAssetDebt);
                    }
                }
                else {
                    revert ICrystal.ActionFailed();
                }
            }
        }
    }

    function _internalCancel(uint256 price, uint256 id, uint256 size, uint256 highestBid, uint256 lowestAsk, uint256 _order) internal {
        unchecked {
            uint256 _priceLevel = priceLevels[marketId | price];
            _priceLevel -= size; // can't overflow
            if (id == (_priceLevel >> 205 & MASK_KEEP_0_51)) { // if pricelevel fillnext then set to fillafter
                _priceLevel = (_order & (MASK_KEEP_0_51 << 205)) | (_priceLevel & MASK_OUT_205_256);
            }
            else if (id == (_priceLevel >> 154 & MASK_KEEP_0_51)) { // if pricelevel latest then set latest to fillbefore
                uint256 fillBefore = ((_order >> 154) & MASK_KEEP_0_51);
                uint256 orderpointer = ((fillBefore > MASK_KEEP_0_41) ? fillBefore : marketId | (price << 48) | fillBefore);
                orders[orderpointer] = (orders[orderpointer] & MASK_OUT_205_256) | (_order & (MASK_KEEP_0_51 << 205)); // set fillbefores fillafter to fillafter
                _priceLevel = (_priceLevel & MASK_OUT_154_205) | (fillBefore << 154);
            }
            else {
                uint256 fillBefore = ((_order >> 154) & MASK_KEEP_0_51);
                uint256 fillAfter = ((_order >> 205) & MASK_KEEP_0_51);
                uint256 orderpointer = ((fillBefore > MASK_KEEP_0_41) ? fillBefore : marketId | (price << 48) | fillBefore);
                orders[orderpointer] = (orders[orderpointer] & MASK_OUT_205_256) | (fillAfter << 205); // set fillbefores fillafter to fillafter
                orderpointer = ((fillAfter > MASK_KEEP_0_41) ? fillAfter : marketId | (price << 48) | fillAfter);
                orders[orderpointer] = (orders[orderpointer] & MASK_OUT_154_205) | (fillBefore << 154); // setfillafters fillbefore to fillbefore
            }
            priceLevels[marketId | price] = _priceLevel;
            if ((_priceLevel & MASK_KEEP_0_112) == 0) {
                uint256 tick = marketType == 0 ? (price / tickSize) : _priceToTick(price);
                uint256 slotIndex = tick >> 8;
                uint256 slot = activated[marketId | slotIndex];
                slot &= ~(1 << (tick % 256));
                activated[marketId | slotIndex] = slot;
                if (price == lowestAsk) {
                    slot = slot >> tick % 256;
                    while (slot == 0) {
                        ++slotIndex;
                        slot = activated[marketId | slotIndex];
                        tick = slotIndex << 8;
                    }
                    tick = _searchSlotUp(slot, tick);
                    _getMarket[market].lowestAsk = uint80(marketType == 0 ? (tick * tickSize) : _tickToPrice(tick));
                }
                else if (price == highestBid) {
                    slot = slot & ((1 << (tick % 256)) - 1);
                    while (slot == 0) {
                        --slotIndex;
                        slot = activated[marketId | slotIndex];
                    }
                    tick = _searchSlotDown(slot, slotIndex << 8);
                    _getMarket[market].highestBid = uint80(marketType == 0 ? (tick * tickSize) : _tickToPrice(tick));
                }
            }
        }
    }

    function _mulDiv(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        uint256 prod0;
        uint256 prod1;
        assembly {
            let mm := mulmod(a, b, not(0))
            prod0 := mul(a, b)
            prod1 := sub(sub(mm, prod0), lt(mm, prod0))
        }
        if (prod1 == 0) {
            require(denominator > 0);
            assembly {
                result := div(prod0, denominator)
            }
            return result;
        }
        require(denominator > prod1);
        uint256 remainder;
        assembly {
            remainder := mulmod(a, b, denominator)
        }
        assembly {
            prod1 := sub(prod1, gt(remainder, prod0))
            prod0 := sub(prod0, remainder)
        }
        uint256 twos = denominator & (~denominator + 1);
        assembly {
            denominator := div(denominator, twos)
        }
        assembly {
            prod0 := div(prod0, twos)
        }
        assembly {
            twos := add(div(sub(0, twos), twos), 1)
        }
        prod0 |= prod1 * twos;
        uint256 inv = (3 * denominator) ^ 2;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;

        result = prod0 * inv;
        return result;
    }

    function _mulDivRoundingUp(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        result = _mulDiv(a, b, denominator);
        if (mulmod(a, b, denominator) > 0) {
            require(result < type(uint256).max);
            result++;
        }
    }
    // max is a limit on price buckets returned
    function _getPriceLevels(bool isAscending, uint256 startPrice, uint256 distance, uint256 interval, uint256 max) internal view {
        unchecked {
            uint256 _maxPrice = maxPrice;
            if (startPrice >= _maxPrice) {
                return;
            }
            uint256 _marketId = marketId;
            uint256 tick = marketType == 0 ? (startPrice / tickSize) : _priceToTick(startPrice);
            startPrice = tick; // turn startprice into starttick
            if (!isAscending) {
                ++tick;
            }
            uint256 count;
            uint256 price;
            uint256 position;
            uint256 bucket = type(uint256).max;
            uint256 slotIndex = tick >> 8;
            uint256 slot = activated[marketId | slotIndex];
            assembly {
                position := mload(0x40)
                mstore(position, 0x0)
            }
            if (isAscending) { // assumes asks for buckets, if it's across bids then just make sure interval is set to 1
                if (startPrice + (distance) > (marketType == 0 ? (_maxPrice / tickSize) : _priceToTick(_maxPrice))) {
                    distance = ((marketType == 0 ? (_maxPrice / tickSize) : _priceToTick(_maxPrice)) - startPrice);
                }
                while (true) {
                    uint256 _slot = slot >> tick % 256;
                    while (_slot == 0) {
                        ++slotIndex;
                        slot = activated[marketId | slotIndex];
                        _slot = slot;
                        tick = slotIndex << 8;
                    }
                    tick = _searchSlotUp(_slot, tick);
                    slot &= ~(1 << (tick % 256));
                    price = marketType == 0 ? (tick * tickSize) : _tickToPrice(tick);
                    if ((((price + interval - 1) / interval) * interval) == bucket) {
                        assembly {
                            mstore(0x00, or(_marketId, price))
                            mstore(0x20, priceLevels.slot)
                            let length := mload(position)
                            let existing := mload(add(length, position))
                            mstore(add(length, position), add(existing, and(sload(keccak256(0x00, 0x40)), MASK_KEEP_0_112)))
                        }
                    }
                    else {
                        ++count;
                        if (count > max && max != 0 || (tick >= startPrice + distance)) {
                            break;
                        }
                        bucket = ((price + interval - 1) / interval) * interval; // round up because ask
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
            else {
                if (distance > startPrice) {
                    distance = startPrice;
                }
                while (true) {
                    uint256 _slot = slot & ((1 << (tick % 256)) - 1);
                    while (_slot == 0) {
                        --slotIndex;
                        slot = activated[marketId | slotIndex];
                        _slot = slot;
                    }
                    tick = _searchSlotDown(_slot, slotIndex << 8);
                    slot &= ~(1 << (tick % 256));
                    price = marketType == 0 ? (tick * tickSize) : _tickToPrice(tick);
                    if ((price / interval * interval) == bucket) {
                        assembly {
                            mstore(0x00, or(_marketId, price))
                            mstore(0x20, priceLevels.slot)
                            let length := mload(position)
                            let existing := mload(add(length, position))
                            mstore(add(length, position), add(existing, and(sload(keccak256(0x00, 0x40)), MASK_KEEP_0_112)))
                        }
                    }
                    else {
                        ++count;
                        if (count > max && max != 0 || (tick <= startPrice - distance)) {
                            break;
                        }
                        bucket = price / interval * interval; // round down because bid
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

    function getPriceLevels(bool isAscending, uint256 startPrice, uint256 distance, uint256 interval, uint256 max) external payable returns (bytes memory) {
        assembly { mstore(0x40, 0xa0) }
        _getPriceLevels(isAscending, startPrice, distance, interval, max);
        assembly {
            mstore(0x80, 0x20)
            return(0x80, add(mload(0xa0), 0x40))
        }
    }

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

    function getPrice() external payable returns (uint256 price, uint256 highestBid, uint256 lowestAsk) {
        ICrystal.Market storage m = _getMarket[market];
        uint256 count;
        (highestBid, lowestAsk) = (m.highestBid, m.lowestAsk);
        (uint256 reserveQuote, uint256 reserveBase) = m.isAMMEnabled ? (m.reserveQuote, m.reserveBase) : (0, 0);
        if (reserveQuote != 0) {
            uint256 ammPrice = ((reserveQuote * scaleFactor * 9975 * 100000 + (reserveBase * 10000 * m.makerRebate - 1)) / (reserveBase * 10000 * m.makerRebate));
            ammPrice = marketType == 0 ? ((ammPrice + tickSize - 1) / tickSize) * tickSize : _toValidPrice(ammPrice, true); // get adjusted amm bid
            if (highestBid < ammPrice) {
                highestBid = ammPrice;
            }
            ammPrice = ((reserveQuote * scaleFactor * 10000 * m.makerRebate) / (reserveBase * 9975 * 100000));
            ammPrice = marketType == 0 ? (ammPrice - (ammPrice % tickSize)) : _toValidPrice(ammPrice, false); // get adjusted amm ask
            if (lowestAsk > ammPrice) {
                lowestAsk = ammPrice;
            }
        }
        price = highestBid;
        if (lowestAsk != maxPrice) { // if no asks, it will return the highest bid rather than midpoint
            price += lowestAsk;
            ++count;
        }
        if (highestBid != 0) { // if no bids, it will return the lowest ask rather than midpoint
            ++count;
        }
        if (count == 2) {
            price = (price + 1) >> 1;
        }
    }

    function getQuote(bool isBuy, bool isExactInput, bool isCompleteFill, uint256 size, uint256 worstPrice) external payable returns (uint256 amountIn, uint256 amountOut) {
        unchecked {
            ICrystal.Market storage m = _getMarket[market];
            uint256 price;
            if (isBuy) {
                if (isExactInput) { // orderInfo is 256-252 ordertype 252-248 !isExactInput 248-244 !isBuy 244-240 STP 240-236 !useexternalbalance 236-232 !fromcaller
                    size = (size * m.takerFee) / 100000;
                }
                uint256 _maxPrice = maxPrice;
                if (worstPrice >= _maxPrice) {
                    worstPrice = _maxPrice - 1;
                }
                price = m.lowestAsk;
            }
            else {
                if (!isExactInput) {
                    size = (size * 100000 + m.takerFee - 1) / m.takerFee;
                }
                if (worstPrice == 0) {
                    ++worstPrice;
                }
                price = m.highestBid;
            }
            (uint256 reserveQuote, uint256 reserveBase) = m.isAMMEnabled ? (m.reserveQuote, m.reserveBase) : (0, 0);
            uint256 tick = marketType == 0 ? (price / tickSize) : _priceToTick(price);
            uint256 slot = activated[marketId | (tick >> 8)];
            while (isExactInput ? size > amountIn : size > amountOut) {
                uint256 sizeLeft = isExactInput ? (size - amountIn) : (size - amountOut);
                if (reserveQuote != 0) {
                    uint256 _amountIn = isBuy ? (price > worstPrice ? worstPrice : price) : (price < worstPrice ? worstPrice : price); // stop at either slippage limit or next resting order price
                    uint256 _amountOut = _amountIn; // set both so one can be used as a temp variable
                    if (isBuy && (reserveQuote * scaleFactor * 10000 * m.makerRebate) < (_amountIn * (reserveBase * 9975 * 100000))) { // adjust price in favor of amm because no maker rebate
                        if (isExactInput) {
                            _amountOut = reserveQuote * 10000; // reuse to avoid stack too deep
                            _amountIn = _sqrt(_mulDiv((_amountOut / 9975) * reserveBase * 100000, (_amountIn * 9975 / 10000), m.makerRebate * scaleFactor)) - (_amountOut / 9975); // find optimal amountIn so AMM execution price up to price adjusted for maker rebate
                            if (sizeLeft < _amountIn) {
                                _amountIn = sizeLeft; // if amount is greater than sizeleft set amount to sizeleft and swap all thru amm
                            }
                            _amountOut = (_amountIn * 9975 * reserveBase) / (_amountOut + (_amountIn * 9975)); // swap
                        }
                        else {
                            _amountIn = reserveQuote * 10000; // reuse to avoid stack too deep
                            _amountOut = reserveBase - _sqrt(_mulDivRoundingUp(_amountIn * reserveBase * m.makerRebate, scaleFactor, (_amountOut * 9975 / 10000) * (100000 * 9975))); // find optimal amountOut so AMM execution price up to price adjusted for maker rebate
                            if (sizeLeft < _amountOut) {
                                _amountOut = sizeLeft; // if amount is greater than sizeleft set amount to sizeleft and swap all thru amm
                            }
                            _amountIn = (_amountOut * _amountIn) / ((reserveBase - _amountOut) * 9975); // swap
                        }
                        reserveQuote += _amountIn; // set reserves
                        reserveBase -= _amountOut;
                    }
                    else if (!isBuy && (reserveQuote * scaleFactor * 9975 * 100000) > (_amountIn * (reserveBase * 10000 * m.makerRebate))) {
                        if (isExactInput) {
                            _amountOut = reserveBase * 10000; // reuse to avoid stack too deep
                            _amountIn = _sqrt(_mulDiv((_amountOut / 9975) * reserveQuote * 100000, scaleFactor, (_amountIn * 10000 / 9975) * m.makerRebate)) - (_amountOut / 9975);
                            if (sizeLeft < _amountIn) {
                                _amountIn = sizeLeft;
                            }
                            _amountOut = ((_amountIn * 9975) * reserveQuote) / (_amountOut + (_amountIn * 9975));
                        }
                        else {
                            _amountIn = reserveBase * 10000; // reuse to avoid stack too deep
                            _amountOut = reserveQuote - _sqrt(_mulDivRoundingUp(_amountIn * reserveQuote * m.makerRebate, (_amountOut * 10000 / 9975), scaleFactor * (100000 * 9975)));
                            if (sizeLeft < _amountOut) {
                                _amountOut = sizeLeft;
                            }
                            _amountIn = (_amountOut * _amountIn) / ((reserveQuote - _amountOut) * 9975);
                        }
                        reserveBase += _amountIn;
                        reserveQuote -= _amountOut;
                    }
                    else {
                        _amountIn = 0; // set to 0 if no swap through amm so the next statement doesn't run
                    }
                    if (_amountIn != 0) {
                        amountIn += _amountIn;
                        amountOut += _amountOut;
                        if (sizeLeft != (isExactInput ? _amountIn : _amountOut)) { // deduct from sizeleft but if full swap then break
                            sizeLeft -= (isExactInput ? _amountIn : _amountOut);
                        }
                        else {
                            break;
                        }
                    }
                }
                if (isBuy ? price > worstPrice : price < worstPrice) {
                    if (isCompleteFill) {
                        revert ICrystal.SlippageExceeded();
                    }
                    else {
                        break;
                    }
                }
                uint256 liquidity = priceLevels[marketId | price] & MASK_KEEP_0_112;
                if (isExactInput ? (isBuy ? (liquidity > (sizeLeft * m.makerRebate / 100000) * scaleFactor / price) : (liquidity > (sizeLeft * m.makerRebate / 100000) * price / scaleFactor)) : (liquidity > sizeLeft)) {
                    amountOut += (isExactInput ? (isBuy ? (sizeLeft * m.makerRebate / 100000) * scaleFactor / price : (sizeLeft * m.makerRebate / 100000) * price / scaleFactor) : sizeLeft);
                    if (!isExactInput) {
                        sizeLeft = isBuy ? (sizeLeft * price + scaleFactor - 1) / scaleFactor * 100000 / m.makerRebate : (sizeLeft * scaleFactor + price - 1) / price * 100000 / m.makerRebate;
                    }
                    amountIn += sizeLeft;
                    sizeLeft = 0;
                }
                else {
                    uint256 _amountIn = (isBuy ? (((liquidity * price / scaleFactor) * 100000) / m.makerRebate) : (((liquidity * scaleFactor / price) * 100000) / m.makerRebate));
                    amountIn += _amountIn;
                    amountOut += isBuy ? liquidity : liquidity;
                    sizeLeft -= isExactInput ? _amountIn : liquidity;
                    liquidity = 0;
                }
                if (liquidity == 0) {
                    slot &= ~(1 << (tick % 256));
                    uint256 slotIndex = tick >> 8;
                    if (isBuy) {
                        uint256 _slot = slot >> tick % 256;
                        while (_slot == 0) {
                            ++slotIndex;
                            slot = activated[marketId | slotIndex];
                            _slot = slot;
                            tick = slotIndex << 8;
                        }
                        tick = _searchSlotUp(_slot, tick);
                    }
                    else {
                        uint256 _slot = slot & ((1 << (tick % 256)) - 1);
                        while (_slot == 0) {
                            --slotIndex;
                            slot = activated[marketId | slotIndex];
                            _slot = slot;
                        }
                        tick = _searchSlotDown(_slot, slotIndex << 8);
                    }
                    price = marketType == 0 ? (tick * tickSize) : _tickToPrice(tick);
                }
                else {
                    break;
                }
            }
            isBuy ? amountIn = (amountIn * 100000 + m.takerFee - 1) / m.takerFee : amountOut = amountOut * m.takerFee / 100000;
            return (amountIn, amountOut);
        }
    }
    // orderInfo is 256-252 ordertype 252-248 !isExactInput 248-244 !isBuy 244-240 STP 240-236 !useexternalbalance 236-232 !fromcaller
    function _marketOrder(uint256 size, uint256 priceAndReferrer, uint256 orderInfo) internal returns (uint256 amountIn, uint256 amountOut, uint256 id, uint256 settlementDelta) { // settlement delta is debit amt << 128 | credit amt, debit amt is always input asset and credit amt is always output
        unchecked {
            ICrystal.Market storage m = _getMarket[market];
            uint256 price;
            if ((orderInfo >> 244 & 1) == 0) { // isbuy
                if (((orderInfo >> 248 & 1) == 0)) { // isexactinput
                    size = (size * m.takerFee) / 100000; // pre adjust size bc taker fee is in quote which is specified
                }
                if ((priceAndReferrer & MASK_KEEP_0_80) >= maxPrice) {
                    priceAndReferrer = (priceAndReferrer & MASK_OUT_0_80) | (marketType == 0 ? maxPrice - tickSize : _tickToPrice(_priceToTick(maxPrice) - 1)); // set worst price to 1 tick worse than max price bc worst price is inclusive
                }
                price = m.lowestAsk;
            }
            else {
                if (((orderInfo >> 248 & 1) != 0)) { // !isexactinput
                    size = (size * 100000 + m.takerFee - 1) / m.takerFee; // pre adjust size bc taker fee is in quote which is specified
                }
                if ((priceAndReferrer & MASK_KEEP_0_80) == 0) {
                    priceAndReferrer = (priceAndReferrer & MASK_OUT_0_80) | (marketType == 0 ? tickSize : _tickToPrice(1)); // set worst price to 1 tick bc inclusive
                }
                price = m.highestBid;
            }
            uint256 reserves = m.isAMMEnabled ? ((uint256(m.reserveQuote) << 128) | m.reserveBase) : 0;
            {
                uint256 tick = marketType == 0 ? (price / tickSize) : _priceToTick(price);
                uint256 slot = activated[marketId | (tick >> 8)];
                while (((orderInfo >> 248 & 1) == 0) ? size > amountIn : size > amountOut) {
                    uint256 sizeLeft = ((orderInfo >> 248 & 1) == 0) ? size - amountIn : size - amountOut;
                    if (reserves != 0) { // skip amm if not initialized
                        (uint256 reserveQuote, uint256 reserveBase) = (reserves >> 128, reserves & MASK_KEEP_0_112);
                        uint256 _amountIn = (((orderInfo >> 244 & 1) == 0) ? (price > (priceAndReferrer & MASK_KEEP_0_80)) : (price < (priceAndReferrer & MASK_KEEP_0_80))) ? (priceAndReferrer & MASK_KEEP_0_80) : price;
                        uint256 _amountOut = _amountIn; // set both to price, overwrite the one that isn't needed later on
                        if (((orderInfo >> 244 & 1) == 0) && (reserveQuote * scaleFactor * 10000 * m.makerRebate) < (_amountIn * (reserveBase * 9975 * 100000))) {
                            if ((orderInfo >> 248 & 1) == 0) {
                                _amountOut = reserveQuote * 10000; // reuse to avoid stack too deep
                                _amountIn = _sqrt(_mulDiv((_amountOut / 9975) * reserveBase * 100000, (_amountIn * 9975 / 10000), m.makerRebate * scaleFactor)) - (_amountOut / 9975); // find optimal amountIn so AMM execution price up to price adjusted for maker rebate
                                if (sizeLeft < _amountIn) {
                                    _amountIn = sizeLeft;
                                }
                                _amountOut = ((_amountIn * 9975) * reserveBase) / (_amountOut + (_amountIn * 9975)); // execute v2 swap
                            }
                            else {
                                _amountIn = reserveQuote * 10000; // reuse to avoid stack too deep
                                _amountOut = reserveBase - _sqrt(_mulDivRoundingUp(_amountIn * reserveBase * m.makerRebate, scaleFactor, (_amountOut * 9975 / 10000) * (100000 * 9975))); // find optimal amountOut so AMM execution price up to price adjusted for maker rebate
                                if (sizeLeft < _amountOut) {
                                    _amountOut = sizeLeft;
                                }
                                _amountIn = (_amountOut * _amountIn) / ((reserveBase - _amountOut) * 9975); // execute v2 swap
                            }
                            reserveQuote += _amountIn;
                            reserveBase -= _amountOut;
                            {
                                uint256 pricememory;
                                assembly { pricememory := mload(0x80) } // top 128 is start price bottom 128 is end price 
                                uint256 endprice = ((reserveQuote * scaleFactor * 10000 * m.makerRebate) / (reserveBase * 9975 * 100000)); // adjust price in favor of amm because no maker rebate
                                endprice = marketType == 0 ? (endprice - (endprice % tickSize)) : _toValidPrice(endprice, false); // round down
                                if (pricememory == 0) {
                                    uint256 startprice = (((reserveQuote - _amountIn) * scaleFactor * 10000 * m.makerRebate) / ((reserveBase + _amountOut) * 9975 * 100000));
                                    startprice = marketType == 0 ? (startprice - (startprice % tickSize)) : _toValidPrice(startprice, false);
                                    pricememory = (startprice << 128) | endprice; // set start price if needed, temp undo reserve updates
                                }
                                else {
                                    pricememory = (pricememory & MASK_OUT_0_128) | endprice;
                                }
                                assembly { mstore(0x80, pricememory) }
                            }
                        }
                        else if (((orderInfo >> 244 & 1) != 0) && (reserveQuote * scaleFactor * 9975 * 100000) > (_amountIn * (reserveBase * 10000 * m.makerRebate))) {
                            if ((orderInfo >> 248 & 1) == 0) {
                                _amountOut = reserveBase * 10000; // reuse to avoid stack too deep
                                _amountIn = _sqrt(_mulDiv((_amountOut / 9975) * reserveQuote * 100000, scaleFactor, (_amountIn * 10000 / 9975) * m.makerRebate)) - (_amountOut / 9975);
                                if (sizeLeft < _amountIn) {
                                    _amountIn = sizeLeft;
                                }
                                _amountOut = ((_amountIn * 9975) * reserveQuote) / (_amountOut + (_amountIn * 9975)); // execute v2 swap
                            }
                            else {
                                _amountIn = reserveBase * 10000; // reuse to avoid stack too deep
                                _amountOut = reserveQuote - _sqrt(_mulDivRoundingUp(_amountIn * reserveQuote * m.makerRebate, (_amountOut * 10000 / 9975), scaleFactor * (100000 * 9975)));
                                if (sizeLeft < _amountOut) {
                                    _amountOut = sizeLeft;
                                }
                                _amountIn = (_amountOut * _amountIn) / ((reserveQuote - _amountOut) * 9975); // execute v2 swap
                            }
                            reserveBase += _amountIn;
                            reserveQuote -= _amountOut;
                            {
                                uint256 pricememory;
                                assembly { pricememory := mload(0x80) } // top 128 is start price bottom 128 is end price 
                                uint256 endprice = ((reserveQuote * scaleFactor * 9975 * 100000 + (reserveBase * 10000 * m.makerRebate - 1)) / (reserveBase * 10000 * m.makerRebate));
                                endprice = marketType == 0 ? ((endprice + tickSize - 1) / tickSize) * tickSize : _toValidPrice(endprice, true); // round up
                                if (pricememory == 0) {
                                    uint256 startprice = (((reserveQuote + _amountOut) * scaleFactor * 9975 * 100000 + ((reserveBase - _amountIn) * 10000 * m.makerRebate - 1)) / ((reserveBase - _amountIn) * 10000 * m.makerRebate));
                                    startprice = marketType == 0 ? ((endprice + tickSize - 1) / tickSize) * tickSize : _toValidPrice(startprice, true);
                                    pricememory = (startprice << 128) | endprice;
                                }
                                else {
                                    pricememory = (pricememory & MASK_OUT_0_128) | endprice;
                                }
                                assembly { mstore(0x80, pricememory) }
                            }
                        }
                        else {
                            _amountIn = 0;
                        }
                        if (_amountIn != 0) {
                            settlementDelta += _amountIn << 128;
                            amountIn += _amountIn;
                            amountOut += _amountOut;
                            reserves = (reserveQuote << 128) | reserveBase;
                            if (sizeLeft != (((orderInfo >> 248 & 1) == 0) ? _amountIn : _amountOut)) {
                                sizeLeft -= (((orderInfo >> 248 & 1) == 0) ? _amountIn : _amountOut);
                            }
                            else {
                                if (activated[marketId | (tick >> 8)] != slot) { // update activated and break if swap is done
                                    activated[marketId | (tick >> 8)] = slot;
                                }
                                break;
                            }
                        }
                    }
                    if (((orderInfo >> 244 & 1) == 0) ? price > (priceAndReferrer & MASK_KEEP_0_80) : price < (priceAndReferrer & MASK_KEEP_0_80)) { // if worst price (slippage limit) is exceeded
                        sizeLeft = (priceAndReferrer & MASK_KEEP_0_80); // worstPrice
                        if ((orderInfo >> 252) == 1) {
                            revert ICrystal.SlippageExceeded();
                        }
                        if (activated[marketId | (tick >> 8)] != slot) {
                            activated[marketId | (tick >> 8)] = slot;
                        }
                        if ((orderInfo >> 252) == 2) {
                            if (reserves != 0) { // set reserves so limit order doesn't fail bc of crossing amm
                                (uint112 reserveQuote, uint112 reserveBase) = (uint112(reserves >> 128), uint112(reserves & MASK_KEEP_0_112));
                                if (reserveQuote != m.reserveQuote || reserveBase != m.reserveBase) {
                                    (m.reserveQuote, m.reserveBase) = (reserveQuote, reserveBase);
                                    emit ICrystal.Sync(market, reserveQuote, reserveBase);
                                }
                                reserves = 0; // don't set reserves again later on
                            }
                            tick = orderInfo; // avoid stack too deep
                            ((tick >> 244 & 1) == 0) ? m.lowestAsk = uint80(price) : m.highestBid = uint80(price);
                            slot = ((tick >> 248 & 1) == 0) ? (size - amountIn) : (((tick >> 244 & 1) == 0) ? ((size - amountOut) * sizeLeft / scaleFactor) : ((size - amountOut) * scaleFactor / sizeLeft));
                            (slot, id) = _limitOrder(((tick >> 244 & 1) == 0), (tick >> 236 & 0x1) == 0, sizeLeft, (((tick >> 244 & 1) == 0) ? ((tick >> 248 & 1) == 0) ? (slot * 100000 + m.takerFee - 1) / m.takerFee : slot : ((tick >> 248 & 1) == 0) ? slot : (slot * m.takerFee) / 100000), (tick >> 160 & MASK_KEEP_0_41), (tick >> 208 & MASK_KEEP_0_10));
                            settlementDelta += (slot << 128);
                            if (slot != 0) { // limit order event is written to memory, emitted in outer function
                                _addToOrdersUpdatedEvent((LEADING_HEX_2 + (((tick >> 244 & 1) == 0) ? 0 : LEADING_HEX_1)) | (sizeLeft << 168) | (id << 112) | slot); // 8 flag 80 price 56 id 112 size
                            }
                        }
                        break;
                    }
                    uint256 _priceLevel = priceLevels[marketId | price];
                    {
                        uint256 next = (_priceLevel >> 205) & MASK_KEEP_0_51;
                        uint256 _orderInfo = orderInfo; // avoid stack too deep
                        while ((_priceLevel & MASK_KEEP_0_112) != 0 && sizeLeft != 0 && !((_orderInfo >> 252) == 3 && gasleft() < 200000)) { // 200k gas buffer if type 3 order
                            uint256 _order = orders[((next > MASK_KEEP_0_41) ? next : marketId | (price << 48) | next)];
                            if ((_orderInfo >> 240 & 0xF) != 0 && (_order >> 113 & MASK_KEEP_0_41) == (_orderInfo >> 160 & MASK_KEEP_0_41)) { // stp is 0 do nothing 1 cancel maker 2 cancel taker 3 cancel both
                                if (((_orderInfo >> 240) & 0x1) != 0) { // cancel resting
                                    bool isBuy = (_orderInfo >> 244 & 1) == 0;
                                    uint256 ordersize = (_order & MASK_KEEP_0_112);
                                    if (next > MASK_KEEP_0_41) {
                                        orders[next] &= MASK_KEEP_113_154;
                                    }
                                    else {
                                        delete orders[marketId | (price << 48) | next];
                                    }
                                    _priceLevel -= ordersize; // can't overflow
                                    if (isBuy) {
                                        settlementDelta += ordersize;
                                    }
                                    else {
                                        settlementDelta += ordersize;
                                    }
                                    if ((_order & MASK_KEEP_112_113) != 0) {
                                        tokenBalances[_order >> 113 & MASK_KEEP_0_41][isBuy ? baseAsset : quoteAsset] -= (ordersize << 128); // unlock tokens if internal can't overflow
                                    }
                                    _addToOrdersUpdatedEvent((isBuy ? LEADING_HEX_1 : 0) | (price << 168) | (next << 112) | ordersize); // 8 flag 80 price 56 id 112 cancel size
                                    next = (_order >> 205) & MASK_KEEP_0_51;
                                }
                                if (((_orderInfo >> 240) & 0xF) == 1) {
                                    continue;
                                }
                                else { // cancel taker
                                    sizeLeft = 0;
                                    break;
                                }
                            }
                            if (((_orderInfo >> 248 & 1) == 0) ? (((_orderInfo >> 244 & 1) == 0) ? ((_order & MASK_KEEP_0_112) > (sizeLeft * m.makerRebate / 100000) * scaleFactor / price) : ((_order & MASK_KEEP_0_112) > (sizeLeft * m.makerRebate / 100000) * price / scaleFactor)) : ((_order & MASK_KEEP_0_112) > sizeLeft)) {
                                { // resting qty is in resting asset
                                    bool isBuy = (_orderInfo >> 244 & 1) == 0;
                                    uint256 _amountOut = (((_orderInfo >> 248 & 1) == 0) ? (isBuy ? (sizeLeft * m.makerRebate / 100000) * scaleFactor / price : (sizeLeft * m.makerRebate / 100000) * price / scaleFactor) : sizeLeft); // output amount for just this swap, round down
                                    amountOut += _amountOut;
                                    if (((_orderInfo >> 248 & 1) != 0)) {
                                        sizeLeft = isBuy ? (sizeLeft * price + scaleFactor - 1) / scaleFactor * 100000 / m.makerRebate : (sizeLeft * scaleFactor + price - 1) / price * 100000 / m.makerRebate; // transfer to maker amount, round up
                                    }
                                    _priceLevel -= _amountOut; // can't overflow
                                    _order -= _amountOut; // can't overflow
                                    orders[((next > MASK_KEEP_0_41) ? next : marketId | (price << 48) | next)] = _order;
                                    uint256 ownerUserId = _order >> 113 & MASK_KEEP_0_41;
                                    address owner = userIdToAddress[ownerUserId];
                                    if (_order & MASK_KEEP_112_113 == 0) { // maker wants tokens
                                        if ((_orderInfo >> 236 & 0x1) == 0 && (_orderInfo >> 232 & 0x1) == 0) { // taker gives tokens
                                            IERC20(isBuy ? quoteAsset : baseAsset).transferFrom(msg.sender, owner, sizeLeft);
                                        }
                                        else { // taker gives internal balance
                                            settlementDelta += sizeLeft << 128;
                                            IERC20(isBuy ? quoteAsset : baseAsset).transfer(owner, sizeLeft);
                                        }
                                    }
                                    else { // maker wants internal balance
                                        settlementDelta += sizeLeft << 128;
                                        tokenBalances[ownerUserId][isBuy ? quoteAsset : baseAsset] += sizeLeft;
                                        tokenBalances[ownerUserId][isBuy ? baseAsset : quoteAsset] -= (_amountOut << 128); // unlock maker internal                       
                                    }
                                    address _market = market;
                                    assembly {
                                        let length := mload(0xc0)
                                        mstore(add(length, 0xe0), or(mul(LEADING_HEX_1, iszero(isBuy)), or(shl(168, price), or(shl(112, next), and(MASK_KEEP_0_112, _order)))))
                                        mstore(add(length, 0x100), _amountOut)
                                        log3(add(length, 0xe0), 0x40, FILL_SIG, _market, owner)
                                        mstore(0x40, add(length, 0xe0))
                                    }
                                }
                                amountIn += sizeLeft;
                                sizeLeft = 0;
                            }
                            else {
                                { // resting qty is in resting asset
                                    uint256 transferAmount = ((_orderInfo >> 244 & 1) == 0) ? ((((_order & MASK_KEEP_0_112) * price / scaleFactor) * 100000) / m.makerRebate) : ((((_order & MASK_KEEP_0_112) * scaleFactor / price) * 100000) / m.makerRebate);
                                    amountIn += transferAmount;
                                    uint256 _amountOut = (_order & MASK_KEEP_0_112);
                                    amountOut += _amountOut;
                                    _priceLevel -= _amountOut;
                                    sizeLeft -= ((_orderInfo >> 248 & 1) == 0) ? transferAmount : _amountOut;
                                    uint256 ownerUserId = _order >> 113 & MASK_KEEP_0_41;
                                    address owner = userIdToAddress[ownerUserId];
                                    if (_order & MASK_KEEP_112_113 == 0) { // maker wants tokens
                                        if ((_orderInfo >> 236 & 0x1) == 0 && (_orderInfo >> 232 & 0x1) == 0) { // taker gives tokens
                                            IERC20(((_orderInfo >> 244 & 1) == 0) ? quoteAsset : baseAsset).transferFrom(msg.sender, owner, transferAmount);
                                        }
                                        else { // taker gives internal balance
                                            settlementDelta += transferAmount << 128;
                                            IERC20(((_orderInfo >> 244 & 1) == 0) ? quoteAsset : baseAsset).transfer(owner, transferAmount);
                                        }
                                    }
                                    else { // maker wants internal balance
                                        settlementDelta += transferAmount << 128;
                                        tokenBalances[ownerUserId][((_orderInfo >> 244 & 1) == 0) ? quoteAsset : baseAsset] += transferAmount;
                                        tokenBalances[ownerUserId][((_orderInfo >> 244 & 1) == 0) ? baseAsset : quoteAsset] -= _amountOut << 128; // unlock maker internal                      
                                    }
                                    address _market = market;
                                    assembly {
                                        let length := mload(0xc0)
                                        mstore(add(length, 0xe0), or(mul(LEADING_HEX_1, and(shr(244, _orderInfo), 1)), or(shl(168, price), shl(112, next))))
                                        mstore(add(length, 0x100), and(MASK_KEEP_0_112, _order))
                                        log3(add(length, 0xe0), 0x40, FILL_SIG, _market, owner)
                                        mstore(0x40, add(length, 0xe0))
                                    }
                                }
                                if (next > MASK_KEEP_0_41) {
                                    orders[next] &= MASK_KEEP_113_154;
                                }
                                else {
                                    delete orders[marketId | (price << 48) | next];
                                }
                                next = (_order >> 205) & MASK_KEEP_0_51;
                            }
                        }
                        priceLevels[marketId | price] = (next << 205) | (_priceLevel & MASK_OUT_205_256); // set fillnext to next
                    }
                    assembly { // update start and end price for event
                        let pricememory := mload(0x80) // top 128 is start price bottom 128 is end price
                        switch pricememory
                        case 0 {
                            pricememory := or(shl(128, price), price)
                        }
                        default {
                            pricememory := or(and(pricememory, MASK_OUT_0_128), price) // set end price
                        }
                        mstore(0x80, pricememory)
                    }
                    if ((_priceLevel & MASK_KEEP_0_112) == 0) { // if price level was fully filled find next one and potentially update activated bitmap
                        slot &= ~(1 << (tick % 256));
                        uint256 slotIndex = tick >> 8;
                        if ((orderInfo >> 244 & 1) == 0) {
                            uint256 _slot = slot >> tick % 256;
                            if (_slot == 0 && activated[marketId | slotIndex] != slot) {
                                activated[marketId | slotIndex] = slot;
                            }
                            while (_slot == 0) {
                                ++slotIndex;
                                slot = activated[marketId | slotIndex];
                                _slot = slot;
                                tick = slotIndex << 8;
                            }
                            tick = _searchSlotUp(_slot, tick);
                        }
                        else {
                            uint256 _slot = slot & ((1 << (tick % 256)) - 1);
                            if (_slot == 0 && activated[marketId | slotIndex] != slot) {
                                activated[marketId | slotIndex] = slot;
                            }
                            while (_slot == 0) {
                                --slotIndex;
                                slot = activated[marketId | slotIndex];
                                _slot = slot;
                            }
                            tick = _searchSlotDown(_slot, slotIndex << 8);
                        }
                        price = marketType == 0 ? (tick * tickSize) : _tickToPrice(tick);
                    }
                    else {
                        if (activated[marketId | (tick >> 8)] != slot) {
                            activated[marketId | (tick >> 8)] = slot;
                        }
                    }
                    if (sizeLeft == 0 || ((orderInfo >> 252) == 3 && gasleft() < 200000)) { // 200k gas buffer if type 3 order
                        break;
                    }
                }
            }
            if (amountIn != 0 || amountOut != 0) {
                if (reserves != 0) { // update amm reserves if needed
                    (uint112 reserveQuote, uint112 reserveBase) = (uint112(reserves >> 128), uint112(reserves & MASK_KEEP_0_112));
                    if (reserveQuote != m.reserveQuote || reserveBase != m.reserveBase) {
                        (m.reserveQuote, m.reserveBase) = (reserveQuote, reserveBase);
                        emit ICrystal.Sync(market, reserveQuote, reserveBase);
                    }
                }
                uint256 feeAmount;
                if ((orderInfo >> 244 & 1) == 0) { // fee is always in quote asset
                    feeAmount = (amountIn * 100000 + m.takerFee - 1) / m.takerFee - amountIn;
                    amountIn += feeAmount;
                    settlementDelta += (feeAmount << 128);
                    m.lowestAsk = uint80(price);
                }
                else {
                    feeAmount = amountOut - amountOut * m.takerFee / 100000;
                    amountOut -= feeAmount;
                    m.highestBid = uint80(price);
                }
                if (address(uint160(priceAndReferrer >> 80)) == address(0)) {
                    uint256 creatorFee;
                    if (marketType == 3) {
                        creatorFee = feeAmount * m.creatorFeeSplit / 100;
                        claimableRewards[quoteAsset][m.creator] += creatorFee;
                    }
                    claimableRewards[quoteAsset][feeRecipient] += (feeAmount - creatorFee);
                }
                else {
                    uint256 amountCommission = feeAmount * feeCommission / 100;
                    claimableRewards[quoteAsset][address(uint160(priceAndReferrer >> 80))] += amountCommission;
                    uint256 amountRebate = feeAmount * feeRebate / 100;
                    claimableRewards[quoteAsset][address(uint160(orderInfo))] += amountRebate;
                    uint256 creatorFee;
                    if (marketType == 3) {
                        creatorFee = feeAmount * m.creatorFeeSplit / 100;
                        claimableRewards[quoteAsset][m.creator] += creatorFee;
                    }
                    claimableRewards[quoteAsset][feeRecipient] += (feeAmount - amountCommission - amountRebate - creatorFee);
                }
                assembly { price := mload(0x80) }
                emit ICrystal.Trade(market, address(uint160(orderInfo)), (orderInfo >> 244 & 1) == 0, amountIn, amountOut, price >> 128, price & MASK_KEEP_0_128);
                return (amountIn, amountOut, id, settlementDelta);
            }
            else {
                return (0, 0, id, settlementDelta);
            }
        }
    }

    function _limitOrder(bool isBuy, bool isRecieveTokens, uint256 price, uint256 size, uint256 userId, uint256 cloid) internal returns (uint256, uint256 id) { // cloid being under uint10 is enforced in entry points
        unchecked {
            ICrystal.Market storage m = _getMarket[market];
            if (isBuy) {
                (uint256 highestBid, uint256 lowestAsk) = (m.highestBid, m.lowestAsk);
                if (price >= lowestAsk || (m.isAMMEnabled && m.reserveQuote != 0 && price >= ((m.reserveQuote * scaleFactor * 10000) / (m.reserveBase * 9975) * m.makerRebate / 100000)) || (cloid != 0 && (orders[(cloid << 41) | userId] & MASK_OUT_113_154) != 0) || price == 0 || size < ((m.minSize >> 20) * 10 ** (m.minSize & MASK_KEEP_0_20))) {
                    return (0, 0);
                }
                if (price > highestBid) {
                    m.highestBid = uint80(price);
                }
                if (!isRecieveTokens) {
                    tokenBalances[userId][quoteAsset] += (size << 128); // lock tokens if internal
                }
            }
            else {
                (uint256 highestBid, uint256 lowestAsk) = (m.highestBid, m.lowestAsk);
                if (price <= highestBid || (m.isAMMEnabled && m.reserveQuote != 0 && price <= ((m.reserveQuote * scaleFactor * 9975) / (m.reserveBase * 10000) * 100000 / m.makerRebate)) || (cloid != 0 && (orders[(cloid << 41) | userId] & MASK_OUT_113_154) != 0) || price >= maxPrice || (size * price / scaleFactor) < ((m.minSize >> 20) * 10 ** (m.minSize & MASK_KEEP_0_20))) {
                    return (0, 0);
                }
                if (price < lowestAsk) {
                    m.lowestAsk = uint80(price);
                }
                if (!isRecieveTokens) {
                    tokenBalances[userId][baseAsset] += (size << 128); // lock tokens if internal
                }
            }
            uint256 _priceLevel = priceLevels[marketId | price];
            require((size <= MASK_KEEP_0_112) && ((_priceLevel & MASK_KEEP_0_112) + size) <= MASK_KEEP_0_112); // overflow check, if invalid params are entered could revert ICrystal.instead of silent return
            if (cloid != 0) {
                uint256 orderpointer = ((cloid | 1) << 41) | userId;
                if (cloid & 1 != 0) {
                    cloidVerify[orderpointer] = cloidVerify[orderpointer] & MASK_OUT_0_128 | ((marketId >> 48) | price);
                }
                else {
                    cloidVerify[orderpointer] = cloidVerify[orderpointer] & MASK_KEEP_0_128 | ((marketId << 80) | (price << 128));
                }
                cloid = (cloid << 41) | userId; // cloid to pointer using userid
                if ((_priceLevel & MASK_KEEP_0_112) == 0) {
                    require(price % tickSize == 0);
                    uint256 tick = marketType == 0 ? (price / tickSize) : _priceToTick(price);
                    activated[marketId | (tick >> 8)] |= (1 << (tick % 256));
                    _priceLevel = (cloid << 205) | (_priceLevel & MASK_OUT_205_256); // set fillNext to cloid
                }
                else {
                    uint256 fillBefore = (_priceLevel >> 154) & MASK_KEEP_0_51;
                    orders[(fillBefore > MASK_KEEP_0_41) ? fillBefore : (marketId | (price << 48) | fillBefore)] = (cloid << 205) | (orders[(fillBefore > MASK_KEEP_0_41) ? fillBefore : (marketId | (price << 48) | fillBefore)] & MASK_OUT_205_256); // set fillbefores fillafter to cloid instead of prev native id
                }
                orders[cloid] = (((_priceLevel >> 113 & MASK_KEEP_0_41) + 1) << 205) | (_priceLevel & (MASK_KEEP_0_51 << 154)) | (userId << 113) | (isRecieveTokens ? 0 : (1 << 112)) | size; // fillAfter to priceLevels latestNativeId+1, fillBefore to latest
                priceLevels[marketId | price] = (cloid << 154) | ((_priceLevel & MASK_OUT_154_205) + size); // latest to cloid and add size
                return (size, cloid);
            }
            else {
                id = (_priceLevel >> 113 & MASK_KEEP_0_41) + 1;
                require(id <= MASK_KEEP_0_41); // overflow uint41
                if ((_priceLevel & MASK_KEEP_0_112) == 0) {
                    require(price % tickSize == 0);
                    uint256 tick = marketType == 0 ? (price / tickSize) : _priceToTick(price);
                    activated[marketId | (tick >> 8)] |= (1 << (tick % 256));
                    _priceLevel = (id << 205) | (_priceLevel & MASK_OUT_205_256); // set fillNext to id, sometimes redundant
                }
                orders[marketId | (price << 48) | id] = ((id + 1) << 205) | (_priceLevel & (MASK_KEEP_0_51 << 154)) | (userId << 113) | (isRecieveTokens ? 0 : (1 << 112)) | size; // fillAfter to id+1, fillBefore to latest
                priceLevels[marketId | price] = (id << 154) | (id << 113) | ((_priceLevel & MASK_OUT_113_205) + size); // latest and latestNativeId to id and add size
                return (size, id);
            }
        }       
    }

    function _cancelOrder(uint256 price, uint256 id, uint256 userId) internal returns (uint256, uint256 size, bool isBuy) { // id is cloid if price is missing
        unchecked {
            ICrystal.Market storage m = _getMarket[market];
            uint256 _order = orders[(price != 0 ? (marketId | (price << 48) | id) : ((id << 41) | userId))]; // id is not yet pointer
            size = (_order & MASK_KEEP_0_112);
            if (0 == size || userId != (_order >> 113 & MASK_KEEP_0_41)) {
                return (0, 0, isBuy);
            }
            if (price == 0) {
                price = cloidVerify[((id | 1) << 41) | userId]; // avoid stack too deep, there's no reason to zero out/edit this as it's not needed
                if (id & 1 != 0) { // make sure order is in right market, get price because cloid doesn't come with it
                    if (((price >> 80) & MASK_KEEP_0_48) != (marketId >> 128)) {
                        return (0, 0, isBuy);
                    }
                    price = price & MASK_KEEP_0_80;
                }
                else {
                    if (((price >> 208) & MASK_KEEP_0_48) != (marketId >> 128)) {
                        return (0, 0, isBuy);
                    }
                    price = (price >> 128) & MASK_KEEP_0_80;
                }
                id = (id << 41) | userId; // id to pointer using userid
                orders[id] &= MASK_KEEP_113_154;
            }
            else {
                delete orders[marketId | (price << 48) | id];
            }
            (uint256 highestBid, uint256 lowestAsk) = (m.highestBid, m.lowestAsk);
            if (price <= highestBid) {
                isBuy = true;
                if ((_order & MASK_KEEP_112_113) != 0) {
                    tokenBalances[userId][quoteAsset] -= (size << 128); // unlock tokens if internal can't overflow
                }
            }
            else {
                if ((_order & MASK_KEEP_112_113) != 0) {
                    tokenBalances[userId][baseAsset] -= (size << 128); // unlock tokens if internal can't overflow
                }
            }
            _internalCancel(price, id, size, highestBid, lowestAsk, _order);
            return (price, size, isBuy);
        }
    }

    function _decreaseOrder(uint256 price, uint256 id, uint256 decreaseAmount, uint256 userId) internal returns (uint256, uint256 size, bool isBuy) { // id is cloid if price is missing
        unchecked {
            ICrystal.Market storage m = _getMarket[market];
            uint256 _order = orders[(price != 0 ? (marketId | (price << 48) | id) : ((id << 41) | userId))]; // id is not yet pointer
            size = (_order & MASK_KEEP_0_112);
            if (0 == size || userId != (_order >> 113 & MASK_KEEP_0_41)) {
                return (0, 0, isBuy);
            }
            if (price == 0) {
                price = cloidVerify[((id | 1) << 41) | userId]; // avoid stack too deep, there's no reason to zero out/edit this as it's not needed
                if (id & 1 != 0) { // make sure order is in right market, get price because cloid doesn't come with it
                    if (((price >> 80) & MASK_KEEP_0_48) != (marketId >> 128)) {
                        return (0, 0, isBuy);
                    }
                    price = price & MASK_KEEP_0_80;
                }
                else {
                    if (((price >> 208) & MASK_KEEP_0_48) != (marketId >> 128)) {
                        return (0, 0, isBuy);
                    }
                    price = (price >> 128) & MASK_KEEP_0_80;
                }
                id = (id << 41) | userId; // id to pointer using userid
            }
            (uint256 highestBid, uint256 lowestAsk) = (m.highestBid, m.lowestAsk);
            if (price <= highestBid) {
                isBuy = true;
            }
            if ((isBuy ? size : (size * price / scaleFactor)) < (isBuy ? decreaseAmount : (decreaseAmount * price / scaleFactor)) + (((m.minSize >> 20) * 10 ** (m.minSize & MASK_KEEP_0_20)))) { // cancel if resulting order would be too small
                if ((_order & MASK_KEEP_112_113) != 0) {
                    isBuy ? tokenBalances[userId][quoteAsset] -= (size << 128) : tokenBalances[userId][baseAsset] -= (size << 128); // unlock tokens if internal can't overflow
                }
                if (id > MASK_KEEP_0_41) {
                    orders[id] &= MASK_KEEP_113_154;
                }
                else {
                    delete orders[marketId | (price << 48) | id];
                }
                _internalCancel(price, id, size, highestBid, lowestAsk, _order);
                return (price, size, isBuy);
            }
            else {
                if ((_order & MASK_KEEP_112_113) != 0) {
                    isBuy ? tokenBalances[userId][quoteAsset] -= (decreaseAmount << 128) : tokenBalances[userId][baseAsset] -= (decreaseAmount << 128); // unlock tokens if internal can't overflow
                }
                orders[(id > MASK_KEEP_0_41 ? id : (marketId | (price << 48) | id))] -= decreaseAmount; // can't overflow
                priceLevels[marketId | price] -= decreaseAmount;
                return (price, decreaseAmount << 128, isBuy); // price, decrease amount, isBuy
            }
        }
    }

    function _replaceOrder(uint256 options, uint256 price, uint256 id, uint256 newPrice, uint256 newSize) internal returns (int256 quoteAssetDebt, int256 baseAssetDebt, uint256) {
        unchecked {
            bool isBuy;
            bool isCloid;
            uint256 prevSize;
            uint256 userId = (options & MASK_KEEP_0_41);
            if (price == 0) {
                isCloid = true;
                price = cloidVerify[((id | 1) << 41) | userId]; // avoid stack too deep, there's no reason to zero out/edit this as it's not needed
                if (id & 1 != 0) { // make sure order is in right market, get price because cloid doesn't come with it
                    if (((price >> 80) & MASK_KEEP_0_48) != (marketId >> 128)) {
                        return (0, 0, 0);
                    }
                    price = price & MASK_KEEP_0_80;
                }
                else {
                    if (((price >> 208) & MASK_KEEP_0_48) != (marketId >> 128)) {
                        return (0, 0, 0);
                    }
                    price = (price >> 128) & MASK_KEEP_0_80;
                }
                prevSize = (orders[((id << 41) | userId)] & MASK_KEEP_0_112); // id is not pointer
            }
            else {
                prevSize = (orders[(marketId | (price << 48) | id)] & MASK_KEEP_0_112); // id is not pointer
            }
            if (price <= _getMarket[market].highestBid) {
                isBuy = true;
            }
            if ((newPrice & MASK_KEEP_0_80) == 0) {
                newPrice += price;
            }
            if ((((options >> 48) & 1) != 0) || ((newPrice & MASK_KEEP_0_80) == price && (prevSize > newSize))) {
                (price, prevSize, isBuy) = _decreaseOrder(isCloid ? 0 : price, id, prevSize - newSize, userId); // price is 0 if cloid
                if (isCloid) {
                    id = (id << 41) | userId; // differentiate emitted cloid
                }
                if (prevSize != 0) {
                    if ((prevSize >> 128) == 0) { // cancel
                        isBuy ? quoteAssetDebt -= int256(prevSize) : baseAssetDebt -= int256(prevSize);
                        _addToOrdersUpdatedEvent((isBuy ? 0 : LEADING_HEX_1) | (price << 168) | (id << 112) | prevSize); // 3 bits flag 80 price 56 id 112 cancel size
                    }
                    else {
                        isBuy ? quoteAssetDebt -= int256(prevSize >> 128) : baseAssetDebt -= int256(prevSize >> 128);
                        _addToOrdersUpdatedEvent((LEADING_HEX_4 + (isBuy ? 0 : LEADING_HEX_1)) | (price << 168) | (id << 112) | (prevSize >> 128)); // 3 bits flag 80 price 56 id 112 decrease size not remaining
                    }
                    return (quoteAssetDebt, baseAssetDebt, id);
                }
                else {
                    return (0, 0, 0); // no state is changed, can silent return
                }
            }
            else {
                (price, prevSize, isBuy) = _cancelOrder((isCloid) ? 0 : price, id, userId); // price is 0 if cloid
                if (isCloid) {
                    id = (id << 41) | userId; // differentiate emitted cloid
                }
                if (prevSize != 0) {
                    isBuy ? quoteAssetDebt -= int256(prevSize) : baseAssetDebt -= int256(prevSize);
                    _addToOrdersUpdatedEvent((isBuy ? 0 : LEADING_HEX_1) | (price << 168) | (id << 112) | prevSize); // 3 bits flag 80 price 56 id 112 size
                }
                else {
                    return (0, 0, 0); // no state is changed, can silent return
                }
                if (isCloid) {
                    id = id >> 41; // back to normal cloid
                }
                else {
                    id = 0;
                }
                if (newSize == 0) {
                    newSize = prevSize;
                }
                if (((options >> 44) & 1) == 0) { // post only
                    (prevSize, id) = _limitOrder(isBuy, (((options >> 60) & 1) == 0), (newPrice & MASK_KEEP_0_80), newSize, userId, id);
                    if (prevSize != 0) {
                        isBuy ? quoteAssetDebt += int256(prevSize) : baseAssetDebt += int256(prevSize);
                        _addToOrdersUpdatedEvent((LEADING_HEX_2 + (isBuy ? 0 : LEADING_HEX_1)) | ((newPrice & MASK_KEEP_0_80) << 168) | (id << 112) | prevSize); // 3 bits flag 80 price 56 id 112 size
                    }
                    else {
                        return (quoteAssetDebt, baseAssetDebt, 0);
                    }
                }
                else {
                    isCloid = ((options >> 60) & 1) == 0; // avoid stack too deep, true if external balances
                    uint256 settlementDelta;
                    uint256 caller = (options >> 96);
                    uint256 orderInfo = (2 << 252) | (isBuy ? 0 : (1 << 244)) | (1 << 240) | (isCloid ? 0 : (1 << 236)) | (id << 208) | (userId << 160) | caller;
                    (, prevSize, id, settlementDelta) = _marketOrder(newSize, newPrice, orderInfo);
                    if (isBuy) {
                        quoteAssetDebt += int256(settlementDelta >> 128);
                        baseAssetDebt -= int256(prevSize + (settlementDelta & MASK_KEEP_0_128)); // doesn't overflow because intrinsic is uint128
                    }
                    else {
                        baseAssetDebt += int256(settlementDelta >> 128);
                        quoteAssetDebt -= int256(prevSize + (settlementDelta & MASK_KEEP_0_128)); // doesn't overflow because intrinsic is uint128
                    }
                }
                return (quoteAssetDebt, baseAssetDebt, id);
            }
        }
    }

    function marketOrder(bool isBuy, bool isExactInput, uint256 options, uint256 orderType, uint256 size, uint256 worstPrice, address referrer, address user) external payable returns (uint256 amountIn, uint256 amountOut, uint256 id) {
        unchecked {
            uint256 orderInfo; // options is 0-44 userId 44-54 cloid 56-60 stp 60-64 tointernalbalances 64-68 frominternalbalances 68-72 useinternalbalances
            uint256 userId;
            {
                uint256 orderFlags = ((orderType & 0xF) << 252) | ((isExactInput ? 0 : (1 << 248))) | ((isBuy ? 0 : (1 << 244))) | (((options >> 56) & 0xF) << 240); // ordertype exactinput=0 isbuy=0 stp
                orderInfo = orderFlags | (((options >> 68) & 1) << 236) | (((options >> 64) & 1) << 232) | uint160(user); // useexternalbalance=0 fromcaller=0 add userId 160-208 if internal balance or mtl and cloid if provided 208-218 if mtl and margin enforced elsewhere
                userId = (options & MASK_KEEP_0_41);
                if (userId != 0) {
                    require(userIdToAddress[userId] == user);
                }
                else {
                    userId = addressToUserId[user];
                    if (userId == 0) {
                        userId = ICrystal(crystal).registerUser(user);
                    }
                }
                orderInfo |= (userId << 160); // add userId to orderInfo
                if (((options >> 44) & MASK_KEEP_0_10) != 0) { // if cloid
                    orderInfo |= (((options >> 44) & MASK_KEEP_0_10) << 208);
                }
            }
            uint256 settlementDelta;
            assembly {
                mstore(0x40, 0xe0) // 0x80 is used by _marketOrder internally to avoid stack too deep
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
            if ((settlementDelta >> 128) != 0) { // input token for both limit order and maker internal balance fills
                if (((options >> 68) & 1) != 0) {
                    uint256 balance = tokenBalances[userId][token];
                    if (uint128(balance) < (settlementDelta >> 128)) {
                        revert ICrystal.ActionFailed();
                    }
                    else {
                        tokenBalances[userId][token] = balance - (settlementDelta >> 128);
                    }
                }
                else { // use external balance
                    if (((options >> 64) & 1) != 0) { // use router balance
                        uint256 balance = tokenBalances[0][token];
                        if (uint128(balance) < (settlementDelta >> 128)) {
                            revert ICrystal.ActionFailed();
                        }
                        else {
                            tokenBalances[0][token] = balance - (settlementDelta >> 128);
                        }
                    }
                    else {
                        IERC20(token).transferFrom(msg.sender, address(this), (settlementDelta >> 128));
                    }
                }
            }
            settlementDelta &= MASK_KEEP_0_128;
            settlementDelta += amountOut; // add output to self cancel credit
            token = isBuy ? baseAsset : quoteAsset;
            if (settlementDelta != 0) { // output token, stp cancels + amountout
                if (((options >> 68) & 1) != 0) {
                    tokenBalances[userId][token] += settlementDelta;
                }
                else { // use external balance
                    if (((options >> 60) & 1) != 0) {
                        tokenBalances[0][token] += settlementDelta;
                    }
                    else {
                        IERC20(token).transfer(msg.sender, settlementDelta);
                    }
                }
            }
        }
    }

    function limitOrder(bool isBuy, uint256 options, uint256 price, uint256 size, address user) external payable returns (uint256 id) { // options is 0-41 userId 44-54 cloid 56-60 frominternalbalances 60-64 useinternalbalances
        unchecked {
            uint256 userId = (options & MASK_KEEP_0_41);
            if (userId != 0) { // if userId is supplied verify
                require(userIdToAddress[userId] == user);
            }
            else { // get default userId
                userId = addressToUserId[user];
                if (userId == 0) {
                    userId = ICrystal(crystal).registerUser(user);
                }
            }
            bool useExternalBalances = (((options >> 60) & 1) == 0);
            (size, id) = _limitOrder(isBuy, useExternalBalances, price, size, userId, (options >> 44) & MASK_KEEP_0_10);
            if (size != 0) { // if order success
                address token = isBuy ? quoteAsset : baseAsset;
                if (useExternalBalances) {
                    if (((options >> 56) & 1) != 0) {
                        uint256 balance = tokenBalances[0][token];
                        if (uint128(balance) < size) {
                            revert ICrystal.ActionFailed();
                        }
                        else {
                            tokenBalances[0][token] = balance - size;
                        }
                    }
                    else {
                        IERC20(token).transferFrom(msg.sender, address(this), size);
                    }
                }
                else {
                    uint256 balance = tokenBalances[userId][token];
                    if (uint128(balance) < size) {
                        revert ICrystal.ActionFailed();
                    }
                    else {
                        tokenBalances[userId][token] = balance - size; // token txfer don't care about locking since done in internal function
                    }
                }
                emit ICrystal.OrdersUpdated(market, user, abi.encodePacked((isBuy ? LEADING_HEX_2 : LEADING_HEX_3) | (price << 168) | (id << 112) | size)); // if id is a cloid it is already merged w user id
            }
            else {
                revert ICrystal.ActionFailed();
            }
        }
    } 

    function cancelOrder(uint256 options, uint256 price, uint256 id, address user) external payable returns (uint256 size) { // options is 0-41 userId 44-48 tointernalbalances 48-52 useinternalbalances
        unchecked {
            bool isBuy;
            uint256 userId = (options & MASK_KEEP_0_41);
            if (userId != 0) { // if userId is supplied verify
                require(userIdToAddress[userId] == user);
            }
            else { // get default userId
                userId = addressToUserId[user];
            }
            bool useExternalBalances = (((options >> 48) & 1) == 0);
            bool isCloid = (price == 0); // if price isn't 0 assume it's a normal order
            (price, size, isBuy) = _cancelOrder(price, id, userId); // if no price attached update price
            if (isCloid) {
                id = (id << 41) | userId;
            }
            if (size != 0) { // if cancel success
                address token = isBuy ? quoteAsset : baseAsset;
                if (useExternalBalances) {
                    if (((options >> 44) & 1) != 0) {
                        tokenBalances[0][token] += size;
                    }
                    else {
                        IERC20(token).transfer(msg.sender, size);
                    }
                }
                else {
                    tokenBalances[userId][token] += size;
                }
                emit ICrystal.OrdersUpdated(market, user, abi.encodePacked((isBuy ? 0 : LEADING_HEX_1) | (price << 168) | (id << 112) | size));
            }
        }
    }
    // replace is useful in that if cancel fails there's no order, will decrease if its best course of action, and also that you can take the proceeds of the cancel as the order size by setting size=0, can also do decrease
    function replaceOrder(uint256 options, uint256 price, uint256 id, uint256 newPrice, uint256 size, address referrer, address user) external payable returns (uint256 _id) { // options is 0-41 userId 44-48 postOnly=0 48-52 isDecrease 52-56 tointernalbalances 56-60 frominternalbalances 60-64 useinternalbalances
        int256 quoteAssetDebt;
        int256 baseAssetDebt;
        uint256 userId = (options & MASK_KEEP_0_41);
        if (userId != 0) { // if userId is supplied verify
            require(userIdToAddress[userId] == user);
        }
        else { // get default userId
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
        (quoteAssetDebt, baseAssetDebt, _id) = _replaceOrder(options, price, id, newPrice, size);
        uint256 balanceMode = options; // avoid stack too deep
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

    function batchOrders(ICrystal.Action[] calldata actions, uint256 options, address referrer, address user) external payable { // options is 0-41 userId 44-48 tointernalbalances 48-52 frominternalbalances 52-56 useinternalbalances
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
            if ((options & MASK_KEEP_0_41) != 0) { // if userId is supplied verify
                userId = (options & MASK_KEEP_0_41);
                require(userIdToAddress[userId] == user);
            }
            else { // get default userId
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
                if (action == 1) { // cancel, pass either price and id or cloid
                    if (cloid != 0) {
                        (param1, action, isBuy) = _cancelOrder(0, cloid, userId);
                        param2 = (cloid << 41) | userId; // differentiate emitted cloid
                    }
                    else {
                        (param1, action, isBuy) = _cancelOrder(param1, param2, userId);
                    }
                    if (action != 0) {
                        isBuy ? quoteAssetDebt -= int256(action) : baseAssetDebt -= int256(action);
                        _addToOrdersUpdatedEvent((isBuy ? 0 : LEADING_HEX_1) | (param1 << 168) | (param2 << 112) | action); // 8 flag 80 price 56 id 112 cancel size
                    }
                    else {
                        if (actions[offset].isRequireSuccess) {
                            revert ICrystal.ActionFailed();
                        }
                    }
                }
                else if (action == 2 || action == 3) { // limit buy, pass price size and optional cloid
                    (cloid, param2) = _limitOrder((action & 1) == 0, balanceMode == 0, param1, param2, userId, cloid);
                    if (cloid != 0) {
                        ((action & 1) == 0) ? quoteAssetDebt += int256(cloid) : baseAssetDebt += int256(cloid);
                        _addToOrdersUpdatedEvent(((action & 1) == 0) ? LEADING_HEX_2 : LEADING_HEX_3 | (param1 << 168) | (param2 << 112) | cloid); // 8 flag 80 price 56 id 112 size
                    }
                    else {
                        if (actions[offset].isRequireSuccess) {
                            revert ICrystal.ActionFailed();
                        }
                    }
                }
                else if (action > 3 && action < 12) { // 4 mtl buy 5 mtl sell 6 partial buy 7 partial sell 8 partial buy stop when low gas 9 partial sell stop when low gas 10 complete buy 11 complete sell
                    uint256 settlementDelta;
                    settlementDelta = (uint160(referrer) << 80) | param1; // avoid stack too deep
                    param1 = (((action < 6) ? 2 : (action < 8) ? 0 : (action < 10) ? 3 : 1) << 252) | ((action & 1 != 0) ? (1 << 244) : 0); // reuse to save stack, represents ordertype and isbuy
                    ( , param1, , settlementDelta) = _marketOrder(param2, settlementDelta, param1 | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(user));
                    if (action & 1 != 0) { // sell
                        baseAssetDebt += int256(settlementDelta >> 128);
                        quoteAssetDebt -= int256(param1 + (settlementDelta & MASK_KEEP_0_128)); // doesn't overflow because intrinsic is uint128
                    }
                    else { // buy
                        quoteAssetDebt += int256(settlementDelta >> 128);
                        baseAssetDebt -= int256(param1 + (settlementDelta & MASK_KEEP_0_128)); // doesn't overflow because intrinsic is uint128
                    }
                }
                else if (action == 12) { // decrease order, if price then use cloid else use id
                    bool isCloid;
                    if (param1 != 0) { // if price is provided, id is used not cloid
                        cloid = actions[offset].param3;
                        cloid &= MASK_KEEP_0_41; // id is a uint41
                    }
                    else {
                        isCloid = true;
                    }
                    (param1, param2, isBuy) = _decreaseOrder(param1, cloid, param2, userId);
                    if (isCloid) {
                        cloid = (cloid << 41) | userId; // differentiate emitted cloid
                    }
                    if (param2 != 0) {
                        if ((param2 >> 128) == 0) { // cancel
                            isBuy ? quoteAssetDebt -= int256(param2) : baseAssetDebt -= int256(param2);
                            _addToOrdersUpdatedEvent((isBuy ? 0 : LEADING_HEX_1) | (param1 << 168) | (cloid << 112) | param2); // 8 flag 80 price 56 id 112 cancel size
                        }
                        else {
                            isBuy ? quoteAssetDebt -= int256(param2 >> 128) : baseAssetDebt -= int256(param2 >> 128);
                            _addToOrdersUpdatedEvent((LEADING_HEX_4 + (isBuy ? 0 : LEADING_HEX_1)) | (param1 << 168) | (cloid << 112) | (param2 >> 128)); // 8 flag 80 price 56 id 112 decrease size not remaining size
                        }
                    }
                    else {
                        if (actions[offset].isRequireSuccess) {
                            revert ICrystal.ActionFailed();
                        }
                    }
                }
                ++offset;
            }
            param1 = options; // avoid stack too deep
            param2 = options; // avoid stack too deep
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
    // userid is prevalidated
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
                assembly { // 4-8 is isRequireSuccess
                    action := calldataload(offset)
                    param1 := and(MASK_KEEP_0_80, shr(112, action)) // 64-144
                    param2 := and(MASK_KEEP_0_112, action) // 144-256
                    cloid := and(MASK_KEEP_0_10, shr(192, action)) // 20-64
                    action := shr(252, action) // 0-4
                }
                if (action == 1) { // cancel, pass either price and id or cloid
                    if (cloid != 0) {
                        (param1, action, isBuy) = _cancelOrder(0, cloid, userId);
                        param2 = (cloid << 41) | userId; // differentiate emitted cloid
                    }
                    else {
                        (param1, action, isBuy) = _cancelOrder(param1, param2, userId);
                    }
                    if (action != 0) {
                        isBuy ? quoteAssetDebt -= int256(action) : baseAssetDebt -= int256(action);
                        _addToOrdersUpdatedEvent((isBuy ? 0 : LEADING_HEX_1) | (param1 << 168) | (param2 << 112) | action); // 8 flag 80 price 56 id 112 cancel size
                    }
                    else {
                        assembly { // reuse isBuy as isRequireSuccess
                            isBuy := and(0x1, shr(248, calldataload(offset))) // 4-8
                        }
                        if (isBuy) {
                            revert ICrystal.ActionFailed();
                        }
                    }
                }
                else if (action == 2 || action == 3) { // limit buy, pass price size and optional cloid
                    (cloid, param2) = _limitOrder((action & 1) == 0, balanceMode == 0, param1, param2, userId, cloid);
                    if (cloid != 0) {
                        ((action & 1) == 0) ? quoteAssetDebt += int256(cloid) : baseAssetDebt += int256(cloid);
                        _addToOrdersUpdatedEvent(((action & 1) == 0) ? LEADING_HEX_2 : LEADING_HEX_3 | (param1 << 168) | (param2 << 112) | cloid); // 8 flag 80 price 56 id 112 size
                    }
                    else {
                        assembly { // reuse isBuy as isRequireSuccess
                            isBuy := and(0x1, shr(248, calldataload(offset))) // 4-8
                        }
                        if (isBuy) {
                            revert ICrystal.ActionFailed();
                        }
                    }
                }
                else if (action > 3 && action < 12) { // 4 mtl buy 5 mtl sell 6 partial buy 7 partial sell 8 partial buy stop when low gas 9 partial sell stop when low gas 10 complete buy 11 complete sell
                    uint256 settlementDelta;
                    settlementDelta = (uint160(msg.sender) << 80) | param1; // avoid stack too deep
                    param1 = (((action < 6) ? 2 : (action < 8) ? 0 : (action < 10) ? 3 : 1) << 252) | ((action & 1 != 0) ? (1 << 244) : 0); // reuse to save stack, represents ordertype and isbuy
                    ( , param1, , settlementDelta) = _marketOrder(param2, settlementDelta, param1 | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    if (action & 1 != 0) { // sell
                        baseAssetDebt += int256(settlementDelta >> 128);
                        quoteAssetDebt -= int256(param1 + (settlementDelta & MASK_KEEP_0_128)); // doesn't overflow because intrinsic is uint128
                    }
                    else { // buy
                        quoteAssetDebt += int256(settlementDelta >> 128);
                        baseAssetDebt -= int256(param1 + (settlementDelta & MASK_KEEP_0_128)); // doesn't overflow because intrinsic is uint128
                    }
                }
                else if (action == 12) { // decrease order, if price then use cloid else use id
                    bool isCloid;
                    if (param1 != 0) { // if price is provided, id is used not cloid
                        assembly {
                            cloid := and(MASK_KEEP_0_41, shr(192, calldataload(offset))) // id is a uint41, 16-64
                        }
                    }
                    else {
                        isCloid = true;
                    }
                    (param1, param2, isBuy) = _decreaseOrder(param1, cloid, param2, userId);
                    if (isCloid) {
                        cloid = (cloid << 41) | userId; // differentiate emitted cloid
                    }
                    if (param2 != 0) {
                        if ((param2 >> 128) == 0) { // cancel
                            isBuy ? quoteAssetDebt -= int256(param2) : baseAssetDebt -= int256(param2);
                            _addToOrdersUpdatedEvent((isBuy ? 0 : LEADING_HEX_1) | (param1 << 168) | (cloid << 112) | param2); // 8 flag 80 price 56 id 112 cancel size
                        }
                        else {
                            isBuy ? quoteAssetDebt -= int256(param2 >> 128) : baseAssetDebt -= int256(param2 >> 128);
                            _addToOrdersUpdatedEvent((LEADING_HEX_4 + (isBuy ? 0 : LEADING_HEX_1)) | (param1 << 168) | (cloid << 112) | (param2 >> 128)); // 8 flag 80 price 56 id 112 decrease size not remaining size
                        }
                    }
                    else {
                        assembly { // reuse isBuy as isRequireSuccess
                            isBuy := and(0x1, shr(248, calldataload(offset))) // 4-8
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
}
