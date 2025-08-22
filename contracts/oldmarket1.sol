/* contract CrystalMarket1 { // support for margin, doesn't have to be enabled, dynamic tick size with amm
    struct PriceLevel { 
        uint256 size; // uint112 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF
        // gap uint1 0x1
        uint256 latestNativeId; // uint41 0x1FFFFFFFFFF
        uint256 latest; // uint51 0x7FFFFFFFFFFFF
        uint256 fillNext; // uint51 0x7FFFFFFFFFFFF
    }

    struct InternalOrder { //  bit is if maker wants internal balance (1) or tokens (0) order is stored at either marketid << 128 | price << 48 | id or cloid << 41 | userid; no collision because marketid seperates cloid orders from non cloid, userid prevents cloid collisions, and price n id are always unique
        uint256 size; //uint112 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF
        uint256 orderType; // uint1 0x1
        uint256 userId; // uint41 0x1FFFFFFFFFF
        uint256 fillBefore; // uint51 0x7FFFFFFFFFFFF
        uint256 fillAfter; // uint51 0x7FFFFFFFFFFFF
    }
    
    struct Market {
        uint80 highestBid;
        uint80 lowestAsk;
        uint40 minSize;
        uint24 takerFee;
        uint24 makerRebate;
        bool isAMMEnabled;

        uint112 reserveQuote;
        uint112 reserveBase;
        
        address quoteAsset;
        address baseAsset;
        uint256 marketId;
        uint256 marketType;
        uint256 scaleFactor;
        uint256 tickSize;
        uint256 maxPrice;
        address creator;
        uint8 creatorFeeSplit;
    }

    struct Action {
        bool isRequireSuccess;
        uint256 action;
        uint256 param1; // price
        uint256 param2; // size/id
        uint256 param3; // cloid
    }

    address feeRecipient; // public is useless so everything isn't
    uint8 feeCommission;
    uint8 feeRebate;

    mapping (uint256 => address) userIdToAddress; // 0 is an invalid userid
    mapping (address => uint256) addressToUserId;
    mapping (address => Market) _getMarket;
    mapping (uint256 => uint256) activated; // marketid << 128 | slotindex
    mapping (uint256 => uint256) priceLevels; // 0 is an invalid price marketid << 128 | price
    mapping (uint256 => uint256) orders; // 0 is an invalid cloid, valid range 1-1023 mask 0x3FF; marketid << 128 | price << 48 | id or userid << 41 | cloid
    mapping (uint256 => uint256) cloidVerify; // two cloids per slot map market and price, never zero slot 1 << 255 | marketId << 208 | price << 128 | marketId << 80 | price
    mapping (uint256 => mapping (address => uint256)) tokenBalances;
    mapping (address => mapping (address => uint256)) claimableRewards;

    address public immutable quoteAsset;
    address public immutable baseAsset;
    address public immutable crystal;
    uint256 public immutable marketId; // 0 is an invalid marketid
    address public immutable market;
    uint256 public immutable scaleFactor;
    uint256 public immutable tickSize;
    uint256 public immutable maxPrice;

    event Trade(address indexed market, uint256 indexed userId, address indexed user, bool isBuy, uint256 amountIn, uint256 amountOut, uint256 startPrice, uint256 endPrice);
    event OrdersUpdated(address indexed market, uint256 indexed userId, bytes orderData);
    event OrderFilled(address indexed market, uint256 indexed userId, uint256 fillInfo, uint256 fillAmount) anonymous; // fillinfo is isSell << 252 | price << 168 | id << 112 | remaining size

    error SlippageExceeded();
    error ActionFailed();

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
    event Mint(address indexed market, address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed market, address indexed sender, uint amount0, uint amount1, address indexed to);
    event Sync(address indexed market, uint112 reserve0, uint112 reserve1);

    constructor() {
        uint256 _scaleFactor;
        (quoteAsset, baseAsset, marketId, _scaleFactor, tickSize, maxPrice) = ICrystal(msg.sender).parameters();
        scaleFactor = 10**_scaleFactor;
        market = address(this);
        crystal = msg.sender;
        require(quoteAsset != address(0) && baseAsset != address(0) && quoteAsset != baseAsset && maxPrice <= 0xFFFFFFFFFFFFFFFFFFFF && tickSize <= 0xFFFFFFFFFFFFFFFFFFFF && scaleFactor <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
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

    function _mint(address to, uint256 value) internal {
        totalSupply += value;
        balanceOf[to] += value;
        emit Transfer(address(0), to, value);
    }

    function _burn(address from, uint256 value) internal {
        balanceOf[from] -= value;
        totalSupply -= value;
        emit Transfer(from, address(0), value);
    }

    function _approve(address owner, address spender, uint256 value) private {
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _transfer(address from, address to, uint256 value) private {
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
    }

    function mint(address to, uint256 value) external {
        require(msg.sender == crystal);
        _mint(to, value);
    }

    function burn(address from, uint256 value) external {
        require(msg.sender == crystal);
        _burn(from, value);
    }

    function approve(address spender, uint256 value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external virtual returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external virtual returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max && to != crystal) {
            allowance[from][msg.sender] -= value;
        }
        _transfer(from, to, value);
        return true;
    }

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(deadline >= block.timestamp, 'UniswapV2: EXPIRED');
        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01',
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, 'UniswapV2: INVALID_SIGNATURE');
        _approve(owner, spender, value);
    }

    function getReserves() external view returns (uint112 reserveQuote, uint112 reserveBase) {
        reserveQuote = _getMarket[market].reserveQuote;
        reserveBase = _getMarket[market].reserveBase;
    }
    
    function mint(address to, uint256 amountQuoteDesired, uint256 amountBaseDesired, uint256 amountQuoteMin, uint256 amountBaseMin, address caller) external returns (uint256 liquidity) {
        (uint112 reserveQuote, uint112 reserveBase) = (_getMarket[market].reserveQuote, _getMarket[market].reserveBase);
        uint256 amount0;
        uint256 amount1;
        uint _totalSupply = IERC20(market).totalSupply(); // gas savings, must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {
            amount0 = amountQuoteDesired;
            amount1 = amountBaseDesired;
            liquidity = _sqrt(amount0 * (amount1)) - (1000);
            IERC20(market).mint(address(0), 1000); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            uint256 amountBaseOptimal = (amountQuoteDesired * reserveBase) / reserveQuote;
            if (amountBaseOptimal <= amountBaseDesired) {
                amount0 = amountQuoteDesired;
                amount1 = amountBaseOptimal;
            } else {
                uint256 amountQuoteOptimal = (amountBaseDesired * reserveQuote) / reserveBase;
                require(amountQuoteOptimal <= amountQuoteDesired);
                amount0 = amountQuoteOptimal;
                amount1 = amountBaseDesired;
            }
            liquidity = amount0 * (_totalSupply) / reserveQuote < amount1 * (_totalSupply) / reserveBase ? amount0 * (_totalSupply) / reserveQuote : amount1 * (_totalSupply) / reserveBase;
        }
        require(liquidity > 0 && amount0 >= amountQuoteMin && amount1 >= amountBaseMin && _getMarket[market].isAMMEnabled == true);
        reserveQuote += uint112(amount0);
        reserveBase += uint112(amount1);
        IERC20(quoteAsset).transferFrom(caller, address(this), amount0);
        IERC20(baseAsset).transferFrom(caller, address(this), amount1);
        IERC20(market).mint(to, liquidity);

        require(reserveQuote <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF && reserveBase <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
        _getMarket[market].reserveQuote = reserveQuote;
        _getMarket[market].reserveBase = reserveBase;
        emit Sync(market, reserveQuote, reserveBase);
        emit Mint(market, caller, amount0, amount1);
    }

    function burn(address to, uint256 liquidity, uint256 amountQuoteMin, uint256 amountBaseMin, address caller) external returns (uint256 amount0, uint256 amount1) {
        (uint112 reserveQuote, uint112 reserveBase) = (_getMarket[market].reserveQuote, _getMarket[market].reserveBase);
        IERC20(market).transferFrom(caller, address(this), liquidity);

        uint256 _totalSupply = IERC20(market).totalSupply(); // gas savings, must be defined here since totalSupply can update in _mintFee
        amount0 = liquidity * (reserveQuote) / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = liquidity * (reserveBase) / _totalSupply; // using balances ensures pro-rata distribution
        require(amount0 > 0 && amount1 > 0 && amount0 >= amountQuoteMin && amount1 >= amountBaseMin);
        IERC20(market).burn(address(this), liquidity);
        IERC20(quoteAsset).transfer(to, amount0);
        IERC20(baseAsset).transfer(to, amount1);
        reserveQuote -= uint112(amount0);
        reserveBase -= uint112(amount1);

        require(reserveQuote <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF && reserveBase <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
        _getMarket[market].reserveQuote = reserveQuote;
        _getMarket[market].reserveBase = reserveBase;
        emit Sync(market, reserveQuote, reserveBase);
        emit Burn(market, caller, amount0, amount1, to);
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
    // max is in buckets
    function _getPriceLevels(bool isAscending, uint256 startPrice, uint256 distance, uint256 interval, uint256 max) internal view {
        unchecked {
            uint256 _maxPrice = maxPrice;
            if (startPrice >= _maxPrice) {
                return;
            }
            uint256 _marketId = marketId;
            uint256 tick = _priceToTick(startPrice);
            startPrice = tick; // turn startprice into starttick
            if (!isAscending) {
                ++tick;
            }
            uint256 slotIndex = tick >> 8;
            uint256 slot = activated[(marketId << 128) | slotIndex];
            uint256 price;
            uint256 position;
            uint256 bucket = type(uint256).max;
            assembly {
                position := mload(0x40)
                mstore(position, 0x0)
            }
            uint256 count = 0;
            if (isAscending) {
                if (startPrice + (distance) > _priceToTick(_maxPrice)) {
                    distance = (_priceToTick(_maxPrice) - startPrice);
                }
                while (true) {
                    uint256 _slot = slot >> tick % 256;
                    while (_slot == 0) {
                        ++slotIndex;
                        slot = activated[(marketId << 128) | slotIndex];
                        _slot = slot;
                        tick = slotIndex << 8;
                    }
                    if (_slot & ((1 << 128) - 1) == 0) {_slot >>= 128; tick += 128;}
                    if (_slot & ((1 << 64) - 1) == 0) {_slot >>= 64; tick += 64;}
                    if (_slot & ((1 << 32) - 1) == 0) {_slot >>= 32; tick += 32;}
                    if (_slot & ((1 << 16) - 1) == 0) {_slot >>= 16; tick += 16;}
                    if (_slot & ((1 << 8) - 1) == 0) {_slot >>= 8; tick += 8;}
                    if (_slot & ((1 << 4) - 1) == 0) {_slot >>= 4; tick += 4;}
                    if (_slot & ((1 << 2) - 1) == 0) {_slot >>= 2; tick += 2;}
                    if (_slot & 1 == 0) {++tick;}
                    slot &= ~(1 << (tick % 256));
                    price = _tickToPrice(tick);
                    if ((price / interval * interval) == bucket) {
                        assembly {
                            mstore(0x00, or(shl(128, _marketId), price))
                            mstore(0x20, priceLevels.slot)
                            let length := mload(position)
                            let existing := mload(add(length, position))
                            mstore(add(length, position), add(existing, and(sload(keccak256(0x00, 0x40)), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF)))
                        }
                    }
                    else {
                        bucket = price / interval * interval;
                        ++count;
                        if (count > max && max != 0) {
                            break;
                        }
                        if (tick < startPrice + distance) {
                            assembly {
                                mstore(0x00, or(shl(128, _marketId), price))
                                mstore(0x20, priceLevels.slot)
                                let length := mload(position)
                                mstore(add(length, add(position, 0x20)), or(shl(128, bucket), and(sload(keccak256(0x00, 0x40)), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF)))
                                mstore(position, add(length, 0x20))
                            }
                        }
                        else {
                            break;
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
                        slot = activated[(marketId << 128) | slotIndex];
                        _slot = slot;
                    }
                    tick = slotIndex << 8;
                    if (_slot >= 2 ** 128) {_slot >>= 128; tick += 128;}
                    if (_slot >= 2 ** 64) {_slot >>= 64; tick += 64;}
                    if (_slot >= 2 ** 32) {_slot >>= 32; tick += 32;}
                    if (_slot >= 2 ** 16) {_slot >>= 16; tick += 16;}
                    if (_slot >= 2 ** 8) {_slot >>= 8; tick += 8;}
                    if (_slot >= 2 ** 4) {_slot >>= 4; tick += 4;}
                    if (_slot >= 2 ** 2) {_slot >>= 2; tick += 2;}
                    if (_slot >= 2 ** 1) {++tick;}
                    slot &= ~(1 << (tick % 256));
                    price = _tickToPrice(tick);
                    if ((((price + interval - 1) / interval) * interval) == bucket) {
                        assembly {
                            mstore(0x00, or(shl(128, _marketId), price))
                            mstore(0x20, priceLevels.slot)
                            let length := mload(position)
                            let existing := mload(add(length, position))
                            mstore(add(length, position), add(existing, and(sload(keccak256(0x00, 0x40)), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF)))
                        }
                    }
                    else {
                        bucket = ((price + interval - 1) / interval) * interval;
                        ++count;
                        if (count > max && max != 0) {
                            break;
                        }
                        if (tick > startPrice - distance) {
                            assembly {
                                mstore(0x00, or(shl(128, _marketId), price))
                                mstore(0x20, priceLevels.slot)
                                let length := mload(position)
                                mstore(add(length, add(position, 0x20)), or(shl(128, bucket), and(sload(keccak256(0x00, 0x40)), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF)))
                                mstore(position, add(length, 0x20))
                            }
                        }
                        else {
                            break;
                        }
                    }
                }     
            }
        }
    }

    function getPriceLevels(bool isAscending, uint256 startPrice, uint256 distance, uint256 interval, uint256 max) external view returns (bytes memory) {
        assembly {
            mstore(0x40, 0xa0)
        }
        _getPriceLevels(isAscending, startPrice, distance, interval, max);
        assembly {
            mstore(0x80, 0x20)
            return(0x80, add(mload(0xa0), 0x40))
        }
    }

    function getPriceLevelsFromMid(uint256 distance, uint256 interval, uint256 max) external view returns (uint256 highestBid, uint256 lowestAsk, bytes memory bids, bytes memory asks) {
        Market storage m = _getMarket[market];
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
    // done
    function getPrice() external view returns (uint256 price, uint256 highestBid, uint256 lowestAsk) {
        Market storage m = _getMarket[market];
        uint256 count;
        (highestBid, lowestAsk) = (m.highestBid, m.lowestAsk);
        price = highestBid;
        if (lowestAsk != maxPrice) {
            price += lowestAsk;
            ++count;
        }
        if (highestBid != 0) {
            ++count;
        }
        if (count == 2) {
            price = (price + 1) >> 1;
        }
    }
    // done
    function getQuote(bool isBuy, bool isExactInput, bool isCompleteFill, uint256 size, uint256 worstPrice) external view returns (uint256 amountIn, uint256 amountOut) {
        unchecked {
            Market storage m = _getMarket[market];
            uint256 price;
            (uint256 reserveQuote, uint256 reserveBase) = _getMarket[market].isAMMEnabled ? (_getMarket[market].reserveQuote, _getMarket[market].reserveBase) : (0, 0);
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
                    worstPrice = 1;
                }
                price = m.highestBid;
            }
            uint256 tick = _priceToTick(price);
            uint256 slot = activated[(marketId << 128) | (tick >> 8)];
            while (isExactInput ? size > amountIn : size > amountOut) {
                uint256 sizeLeft = isExactInput ? (size - amountIn) : (size - amountOut);
                if (reserveQuote != 0 && reserveBase != 0) {
                    if (isBuy && ((reserveQuote * scaleFactor * 10000) / (reserveBase * 9975)) < (price * 100000 / m.makerRebate)) {
                        if (isExactInput) {
                            uint256 temp1 = reserveQuote * 10000;
                            uint256 _amountIn = _sqrt(temp1 * reserveBase / scaleFactor * price / 9975) - (temp1 / 9975);
                            if (sizeLeft > _amountIn) {
                                uint256 temp2 = _amountIn * 9975;
                                uint256 _amountOut = (temp2 * reserveBase) / (temp1 + temp2);
                                reserveQuote += _amountIn;
                                reserveBase -= _amountOut;
                                amountIn += _amountIn;
                                amountOut += _amountOut;
                                sizeLeft -= _amountIn;
                            }
                            else {
                                uint256 temp2 = sizeLeft * 9975;
                                uint256 _amountOut = (temp2 * reserveBase) / (temp1 + temp2);
                                reserveQuote += sizeLeft;
                                reserveBase -= _amountOut;
                                amountIn += sizeLeft;
                                amountOut += _amountOut;
                                break;
                            }
                        }
                        else {
                            uint256 temp1 = reserveQuote * 10000;
                            uint256 _amountOut = reserveBase - _sqrt(temp1 * reserveQuote / price * scaleFactor / 9975);
                            if (sizeLeft > _amountOut) {
                                uint256 _amountIn = (_amountOut * temp1) / ((reserveBase - _amountOut) * 9975) + 1;
                                reserveQuote += _amountIn;
                                reserveBase -= _amountOut;
                                amountIn += _amountIn;
                                amountOut += _amountOut;
                                sizeLeft -= _amountOut;
                            }
                            else {
                                uint256 _amountIn = (sizeLeft * temp1) / ((reserveBase - sizeLeft) * 9975) + 1;
                                reserveQuote += _amountIn;
                                reserveBase -= sizeLeft;
                                amountIn += _amountIn;
                                amountOut += sizeLeft;
                                break;
                            }
                        }
                    }
                    else if (!isBuy && ((reserveQuote * scaleFactor * 10000) / (reserveBase * 9975)) > (price * m.makerRebate / 100000)) {
                        if (isExactInput) {
                            uint256 temp1 = reserveBase * 10000;
                            uint256 _amountIn = _sqrt(temp1 * reserveQuote / (price < worstPrice ? worstPrice : price) * scaleFactor / 9975) - (temp1 / 9975);
                            if (sizeLeft > _amountIn) {
                                uint256 temp2 = _amountIn * 9975;
                                uint256 _amountOut = (temp2 * reserveQuote) / (temp1 + temp2);
                                reserveBase += _amountIn;
                                reserveQuote -= _amountOut;
                                amountIn += _amountIn;
                                amountOut += _amountOut;
                                sizeLeft -= _amountIn;
                            }
                            else {
                                uint256 temp2 = sizeLeft * 9975;
                                uint256 _amountOut = (temp2 * reserveQuote) / (temp1 + temp2);
                                reserveBase += sizeLeft;
                                reserveQuote -= _amountOut;
                                amountIn += sizeLeft;
                                amountOut += _amountOut;
                                break;
                            }
                        }
                        else {
                            uint256 temp1 = reserveBase * 10000;
                            uint256 _amountOut = reserveQuote - _sqrt(temp1 * reserveQuote / scaleFactor * (price < worstPrice ? worstPrice : price) / 9975);
                            if (sizeLeft > _amountOut) {
                                uint256 _amountIn = (_amountOut * temp1) / ((reserveQuote - _amountOut) * 9975) + 1;
                                reserveBase += _amountIn;
                                reserveQuote -= _amountOut;
                                amountIn += _amountIn;
                                amountOut += _amountOut;
                                sizeLeft -= _amountOut;
                            }
                            else {
                                uint256 _amountIn = (sizeLeft * temp1) / ((reserveQuote - sizeLeft) * 9975) + 1;
                                reserveBase += _amountIn;
                                reserveQuote -= sizeLeft;
                                amountIn += _amountIn;
                                amountOut += sizeLeft;
                                break;
                            }
                        }
                    }
                }
                if (isBuy ? price > worstPrice : price < worstPrice) {
                    if (isCompleteFill) {
                        revert SlippageExceeded();
                    }
                    else {
                        break;
                    }
                }
                uint256 liquidity = priceLevels[(marketId << 128) | price] & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
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
                            slot = activated[(marketId << 128) | slotIndex];
                            _slot = slot;
                            tick = slotIndex << 8;
                        }
                        if (_slot & ((1 << 128) - 1) == 0) {_slot >>= 128; tick += 128;}
                        if (_slot & ((1 << 64) - 1) == 0) {_slot >>= 64; tick += 64;}
                        if (_slot & ((1 << 32) - 1) == 0) {_slot >>= 32; tick += 32;}
                        if (_slot & ((1 << 16) - 1) == 0) {_slot >>= 16; tick += 16;}
                        if (_slot & ((1 << 8) - 1) == 0) {_slot >>= 8; tick += 8;}
                        if (_slot & ((1 << 4) - 1) == 0) {_slot >>= 4; tick += 4;}
                        if (_slot & ((1 << 2) - 1) == 0) {_slot >>= 2; tick += 2;}
                        if (_slot & 1 == 0) {++tick;}
                    }
                    else {
                        uint256 _slot = slot & ((1 << (tick % 256)) - 1);
                        while (_slot == 0) {
                            --slotIndex;
                            slot = activated[(marketId << 128) | slotIndex];
                            _slot = slot;
                        }
                        tick = slotIndex << 8;
                        if (_slot >= 2 ** 128) {_slot >>= 128; tick += 128;}
                        if (_slot >= 2 ** 64) {_slot >>= 64; tick += 64;}
                        if (_slot >= 2 ** 32) {_slot >>= 32; tick += 32;}
                        if (_slot >= 2 ** 16) {_slot >>= 16; tick += 16;}
                        if (_slot >= 2 ** 8) {_slot >>= 8; tick += 8;}
                        if (_slot >= 2 ** 4) {_slot >>= 4; tick += 4;}
                        if (_slot >= 2 ** 2) {_slot >>= 2; tick += 2;}
                        if (_slot >= 2 ** 1) {++tick;}
                    }
                    price = _tickToPrice(tick);
                }
                else {
                    break;
                }
            }
            isBuy ? amountIn = (amountIn * 100000 + m.takerFee - 1) / m.takerFee : amountOut = amountOut * m.takerFee / 100000;
            return (amountIn, amountOut);
        }
    }
    // done
    function _marketOrder(uint256 size, uint256 priceAndReferrer, uint256 orderInfo) internal returns (uint256 amountIn, uint256 amountOut, uint256 id, uint256 settlementDelta) { // settlement delta is debit amt << 128 | credit amt, already processed
        unchecked {
            Market storage m = _getMarket[market];
            uint256 price;
            uint256 reserves =  _getMarket[market].isAMMEnabled ? ((uint256(_getMarket[market].reserveQuote) << 128) | _getMarket[market].reserveBase) : 0;
            if ((orderInfo >> 244 & 0xF) == 0) {
                if (((orderInfo >> 248 & 0xF) == 0)) { // orderInfo is 256-252 ordertype 252-248 !isExactInput 248-244 !isBuy 244-240 STP 240-236 !useexternalbalance 236-232 !fromcaller
                    size = (size * m.takerFee) / 100000;
                }
                uint256 _maxPrice = maxPrice;
                if ((priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFF) >= _maxPrice) {
                    priceAndReferrer = (priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000000000000000) | (_maxPrice - 1);
                }
                price = m.lowestAsk;
            }
            else {
                if (((orderInfo >> 248 & 0xF) != 0)) { // orderInfo is 256-252 ordertype 252-248 !isExactInput 248-244 !isBuy 244-240 STP 240-236 !useexternalbalance 236-232 !fromcaller
                    size = (size * 100000 + m.takerFee - 1) / m.takerFee;
                }
                if ((priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFF) == 0) {
                    priceAndReferrer += 1;
                }
                price = m.highestBid;
            }
            assembly {
                mstore(0x80, shl(128, price)) // top 128 is start price bottom 128 is end price
            }
            {
                uint256 tick = _priceToTick(price);
                uint256 slot = activated[(marketId << 128) | (tick >> 8)];
                while (((orderInfo >> 248 & 0xF) == 0) ? size > amountIn : size > amountOut) {
                    uint256 sizeLeft = ((orderInfo >> 248 & 0xF) == 0) ? size - amountIn : size - amountOut;
                    {
                        (uint256 reserveQuote, uint256 reserveBase) = (reserves >> 128, reserves & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
                        if (reserveQuote != 0 && reserveBase != 0) {
                            if (((orderInfo >> 244 & 0xF) == 0) && ((reserveQuote * scaleFactor * 10000) / (reserveBase * 9975)) < (price * 100000 / m.makerRebate)) {
                                if ((orderInfo >> 248 & 0xF) == 0) {
                                    uint256 _amountOut = reserveQuote * 10000; // reuse to avoid stack too deep
                                    uint256 worstPrice = (priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFF);
                                    uint256 _amountIn = _sqrt(_amountOut * reserveBase / scaleFactor * (price > worstPrice ? worstPrice : price) / 9975) - (_amountOut / 9975);
                                    if (sizeLeft > _amountIn) {
                                        _amountOut = ((_amountIn * 9975) * reserveBase) / (_amountOut + (_amountIn * 9975));
                                        settlementDelta += _amountIn << 128;
                                        reserveQuote += _amountIn;
                                        reserveBase -= _amountOut;
                                        amountIn += _amountIn;
                                        amountOut += _amountOut;
                                        sizeLeft -= _amountIn;
                                    }
                                    else {
                                        _amountOut = ((sizeLeft * 9975) * reserveBase) / (_amountOut + (sizeLeft * 9975));
                                        settlementDelta += sizeLeft << 128;
                                        reserveQuote += sizeLeft;
                                        reserveBase -= _amountOut;
                                        amountIn += sizeLeft;
                                        amountOut += _amountOut;
                                        reserves = (reserveQuote << 128) | reserveBase;
                                        if (activated[(marketId << 128) | (tick >> 8)] != slot) {
                                            activated[(marketId << 128) | (tick >> 8)] = slot;
                                        }
                                        break;
                                    }
                                }
                                else {
                                    uint256 _amountIn = reserveQuote * 10000; // reuse to avoid stack too deep
                                    uint256 worstPrice = (priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFF);
                                    uint256 _amountOut = reserveBase - _sqrt(_amountIn * reserveQuote / (price > worstPrice ? worstPrice : price) * scaleFactor / 9975);
                                    if (sizeLeft > _amountOut) {
                                        _amountIn = (_amountOut * _amountIn) / ((reserveBase - _amountOut) * 9975) + 1;
                                        settlementDelta += _amountIn << 128;
                                        reserveQuote += _amountIn;
                                        reserveBase -= _amountOut;
                                        amountIn += _amountIn;
                                        amountOut += _amountOut;
                                        sizeLeft -= _amountOut;
                                    }
                                    else {
                                        _amountIn = (sizeLeft * _amountIn) / ((reserveBase - sizeLeft) * 9975) + 1;
                                        settlementDelta += _amountIn << 128;
                                        reserveQuote += _amountIn;
                                        reserveBase -= sizeLeft;
                                        amountIn += _amountIn;
                                        amountOut += sizeLeft;
                                        reserves = (reserveQuote << 128) | reserveBase;
                                        if (activated[(marketId << 128) | (tick >> 8)] != slot) {
                                            activated[(marketId << 128) | (tick >> 8)] = slot;
                                        }
                                        break;
                                    }
                                }
                            }
                            else if (((orderInfo >> 244 & 0xF) != 0) && ((reserveQuote * scaleFactor * 10000) / (reserveBase * 9975)) > (price * m.makerRebate / 100000)) {
                                if ((orderInfo >> 248 & 0xF) == 0) {
                                    uint256 _amountOut = reserveBase * 10000; // reuse to avoid stack too deep
                                    uint256 worstPrice = (priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFF);
                                    uint256 _amountIn = _sqrt(_amountOut * reserveQuote / (price < worstPrice ? worstPrice : price) * scaleFactor / 9975) - (_amountOut / 9975);
                                    if (sizeLeft > _amountIn) {
                                        _amountOut = ((_amountIn * 9975) * reserveQuote) / (_amountOut + (_amountIn * 9975));
                                        settlementDelta += _amountIn << 128;
                                        reserveBase += _amountIn;
                                        reserveQuote -= _amountOut;
                                        amountIn += _amountIn;
                                        amountOut += _amountOut;
                                        sizeLeft -= _amountIn;
                                    }
                                    else {
                                        _amountOut = ((sizeLeft * 9975) * reserveQuote) / (_amountOut + (sizeLeft * 9975));
                                        settlementDelta += sizeLeft << 128;
                                        reserveBase += sizeLeft;
                                        reserveQuote -= _amountOut;
                                        amountIn += sizeLeft;
                                        amountOut += _amountOut;
                                        reserves = (reserveQuote << 128) | reserveBase;
                                        if (activated[(marketId << 128) | (tick >> 8)] != slot) {
                                            activated[(marketId << 128) | (tick >> 8)] = slot;
                                        }
                                        break;
                                    }
                                }
                                else {
                                    uint256 _amountIn = reserveBase * 10000; // reuse to avoid stack too deep
                                    uint256 worstPrice = (priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFF);
                                    uint256 _amountOut = reserveQuote - _sqrt(_amountIn * reserveQuote / scaleFactor * (price < worstPrice ? worstPrice : price) / 9975);
                                    if (sizeLeft > _amountOut) {
                                        _amountIn = (_amountOut * _amountIn) / ((reserveQuote - _amountOut) * 9975) + 1;
                                        settlementDelta += _amountIn << 128;
                                        reserveBase += _amountIn;
                                        reserveQuote -= _amountOut;
                                        amountIn += _amountIn;
                                        amountOut += _amountOut;
                                        sizeLeft -= _amountOut;
                                    }
                                    else {
                                        _amountIn = (sizeLeft * _amountIn) / ((reserveQuote - sizeLeft) * 9975) + 1;
                                        settlementDelta += _amountIn << 128;
                                        reserveBase += _amountIn;
                                        reserveQuote -= sizeLeft;
                                        amountIn += _amountIn;
                                        amountOut += sizeLeft;
                                        reserves = (reserveQuote << 128) | reserveBase;
                                        if (activated[(marketId << 128) | (tick >> 8)] != slot) {
                                            activated[(marketId << 128) | (tick >> 8)] = slot;
                                        }
                                        break;
                                    }
                                }
                            }
                            reserves = (reserveQuote << 128) | reserveBase;
                        }
                    }
                    if (((orderInfo >> 244 & 0xF) == 0) ? price > (priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFF) : price < (priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFF)) {
                        if ((orderInfo >> 252) == 1) {
                            revert SlippageExceeded();
                        }
                        if (activated[(marketId << 128) | (tick >> 8)] != slot) {
                            activated[(marketId << 128) | (tick >> 8)] = slot;
                        }
                        if ((orderInfo >> 252) == 2) {
                            ((orderInfo >> 244 & 0xF) == 0) ? m.lowestAsk = uint80(price) : m.highestBid = uint80(price);
                            slot = ((orderInfo >> 248 & 0xF) == 0) ? (size - amountIn) : (((orderInfo >> 244 & 0xF) == 0) ? ((size - amountOut) * (priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFF) / scaleFactor) : ((size - amountOut) * scaleFactor / (priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFF)));
                            tick = orderInfo;
                            (slot, id) = _limitOrder(((tick >> 244 & 0xF) == 0), (tick >> 236 & 0x1) == 0, (priceAndReferrer & 0xFFFFFFFFFFFFFFFFFFFF), slot, (tick >> 160 & 0x1FFFFFFFFFF), (tick >> 208 & 0x3FF));
                            settlementDelta += (slot << 128);
                            if (slot != 0) { // mtl event is written to memory, emitted in parent
                                assembly {
                                    let length := mload(0xc0)
                                    mstore(add(length, add(0xc0, 0x20)), or(add(0x2000000000000000000000000000000000000000000000000000000000000000,mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(iszero(and(shr(244,orderInfo),0xF))))),or(shl(168,and(0xFFFFFFFFFFFFFFFFFFFF,priceAndReferrer)),or(shl(112,id),slot))))
                                    mstore(0xc0, add(length, 0x20))
                                    mstore(0x40, add(length, add(0xc0, 0x40)))
                                }
                            }
                        }
                        break;
                    }
                    uint256 _priceLevel = priceLevels[(marketId << 128) | price];
                    {
                        uint256 next = (_priceLevel >> 205) & 0x7FFFFFFFFFFFF;
                        uint256 _orderInfo = orderInfo;
                        while ((_priceLevel & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) != 0 && sizeLeft != 0 && !((_orderInfo >> 252) == 3 && gasleft() < 100000)) {
                            uint256 _order = orders[((next > 0x1FFFFFFFFFF) ? next : (marketId << 128) | (price << 48) | next)];
                            if ((_orderInfo >> 240 & 0xF) != 0 && (_order >> 113 & 0x1FFFFFFFFFF) == (_orderInfo >> 160 & 0x1FFFFFFFFFF)) {
                                if (((_orderInfo >> 240) & 0x1) != 0) { // stp is 0 do nothing 1 cancel maker 2 cancel taker 3 cancel both
                                    if (next > 0x1FFFFFFFFFF) {
                                        orders[next] &= 0x00000000000000000000000003FFFFFFFFFE0000000000000000000000000000;
                                    }
                                    else {
                                        delete orders[(marketId << 128) | (price << 48) | next];
                                    }
                                    _priceLevel -= (_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
                                    if ((_orderInfo >> 244 & 0xF) == 0) {
                                        settlementDelta += ((_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF));
                                    }
                                    else {
                                        settlementDelta += ((_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF));
                                    }
                                    if ((_order & 0x0000000000000000000000000000000000010000000000000000000000000000) != 0) {
                                        tokenBalances[_order >> 113 & 0x1FFFFFFFFFF][((_orderInfo >> 244 & 0xF) == 0) ? baseAsset : quoteAsset] -= ((((_orderInfo >> 244 & 0xF) == 0) ? (_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) : (_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF)) << 128); // unlock tokens if internal
                                    }
                                    assembly {
                                        mstore(add(mload(0xc0), add(0xc0, 0x20)), or(mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(and(shr(244, _orderInfo), 0xF))),or(shl(168,price),or(shl(112,next),and(_order, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF)))))
                                        mstore(0xc0, add(mload(0xc0), 0x20))
                                        mstore(0x40, add(mload(0xc0), add(0xc0, 0x20))) // avoid initializing length bc stack too deep
                                    }
                                    next = (_order >> 205) & 0x7FFFFFFFFFFFF;
                                }
                                if (((_orderInfo >> 240) & 0xF) == 1) {
                                    continue;
                                }
                                else {
                                    sizeLeft = 0;
                                    break;
                                }
                            } // should switch over to do operations on resting size
                            if (((_orderInfo >> 248 & 0xF) == 0) ? (((_orderInfo >> 244 & 0xF) == 0) ? ((_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) > (sizeLeft * m.makerRebate / 100000) * scaleFactor / price) : ((_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) > (sizeLeft * m.makerRebate / 100000) * price / scaleFactor)) : ((_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) > sizeLeft)) {
                                uint256 _amountOut;
                                {
                                    _amountOut = (((_orderInfo >> 248 & 0xF) == 0) ? (((_orderInfo >> 244 & 0xF) == 0) ? (sizeLeft * m.makerRebate / 100000) * scaleFactor / price : (sizeLeft * m.makerRebate / 100000) * price / scaleFactor) : sizeLeft); // output amount for just this swap, round down
                                    amountOut += _amountOut;
                                    if (((_orderInfo >> 248 & 0xF) != 0)) {
                                        sizeLeft = ((_orderInfo >> 244 & 0xF) == 0) ? (sizeLeft * price + scaleFactor - 1) / scaleFactor * 100000 / m.makerRebate : (sizeLeft * scaleFactor + price - 1) / price * 100000 / m.makerRebate; // transfer to maker amount, round up
                                    }
                                    _priceLevel -= _amountOut;
                                    _order -= _amountOut;
                                    orders[((next > 0x1FFFFFFFFFF) ? next : (marketId << 128) | (price << 48) | next)] = _order;
                                    if (_order & 0x0000000000000000000000000000000000010000000000000000000000000000 == 0) { // maker wants tokens
                                        address owner = userIdToAddress[_order >> 113 & 0x1FFFFFFFFFF];
                                        if ((_orderInfo >> 236 & 0x1) == 0 && (_orderInfo >> 232 & 0x1) == 0) { // taker gives tokens
                                            IERC20(((_orderInfo >> 244 & 0xF) == 0) ? quoteAsset : baseAsset).transferFrom(address(uint160(_orderInfo)), owner, sizeLeft);
                                        }
                                        else { // taker gives internal balance
                                            settlementDelta += sizeLeft << 128;
                                            IERC20(((_orderInfo >> 244 & 0xF) == 0) ? quoteAsset : baseAsset).transfer(owner, sizeLeft);
                                        }
                                    }
                                    else { // maker wants internal balance
                                        settlementDelta += sizeLeft << 128;
                                        tokenBalances[_order >> 113 & 0x1FFFFFFFFFF][((_orderInfo >> 244 & 0xF) == 0) ? quoteAsset : baseAsset] += sizeLeft;
                                        tokenBalances[_order >> 113 & 0x1FFFFFFFFFF][((_orderInfo >> 244 & 0xF) == 0) ? baseAsset : quoteAsset] -= (_amountOut << 128); // unlock maker internal                       
                                    }
                                }
                                amountIn += sizeLeft;
                                address _market = market;
                                assembly {
                                    let length := mload(0xc0)
                                    mstore(add(length, add(0xc0, 0x20)), or(mul(0x1000000000000000000000000000000000000000000000000000000000000000, iszero(and(shr(244, _orderInfo), 0xF))), or(shl(168, price), or(shl(112, next), and(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF, _order)))))
                                    mstore(add(length, add(0xc0, 0x40)), _amountOut)
                                    log2(add(length, add(0xc0, 0x20)), 0x40, _market, and(0x1FFFFFFFFFF, shr(113, _order))) // anon event (orderfilled)
                                    mstore(0x40, add(length, add(0xc0, 0x20)))
                                }
                                sizeLeft = 0;
                            }
                            else {
                                uint256 transferAmount = ((_orderInfo >> 244 & 0xF) == 0) ? ((((_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) * price / scaleFactor) * 100000) / m.makerRebate) : ((((_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) * scaleFactor / price) * 100000) / m.makerRebate);
                                amountIn += transferAmount; // round up maybe?
                                uint256 _amountOut = (_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
                                amountOut += _amountOut;
                                _priceLevel -= _amountOut;
                                sizeLeft -= ((_orderInfo >> 248 & 0xF) == 0) ? transferAmount : _amountOut;
                                if (_order & 0x0000000000000000000000000000000000010000000000000000000000000000 == 0) { // maker wants tokens
                                    address owner = userIdToAddress[_order >> 113 & 0x1FFFFFFFFFF];
                                    if ((_orderInfo >> 236 & 0x1) == 0 && (_orderInfo >> 232 & 0x1) == 0) { // taker gives tokens
                                        IERC20(((_orderInfo >> 244 & 0xF) == 0) ? quoteAsset : baseAsset).transferFrom(address(uint160(_orderInfo)), owner, transferAmount);
                                    }
                                    else { // taker gives internal balance
                                        settlementDelta += transferAmount << 128;
                                        IERC20(((_orderInfo >> 244 & 0xF) == 0) ? quoteAsset : baseAsset).transfer(owner, transferAmount);
                                    }
                                }
                                else { // maker wants internal balance
                                    settlementDelta += transferAmount << 128;
                                    tokenBalances[_order >> 113 & 0x1FFFFFFFFFF][((_orderInfo >> 244 & 0xF) == 0) ? quoteAsset : baseAsset] += transferAmount;
                                    tokenBalances[_order >> 113 & 0x1FFFFFFFFFF][((_orderInfo >> 244 & 0xF) == 0) ? baseAsset : quoteAsset] -= _amountOut << 128; // unlock maker internal                      
                                }
                                address _market = market;
                                assembly {
                                    let length := mload(0xc0)
                                    mstore(add(length, add(0xc0, 0x20)), or(mul(0x1000000000000000000000000000000000000000000000000000000000000000, iszero(and(shr(244, _orderInfo), 0xF))), or(shl(168, price), shl(112, next))))
                                    mstore(add(length, add(0xc0, 0x40)), and(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF, _order))
                                    log2(add(length, add(0xc0, 0x20)), 0x40, _market, and(0x1FFFFFFFFFF, shr(113, _order))) // anon event (orderfilled)
                                    mstore(0x40, add(length, add(0xc0, 0x20)))
                                }
                                if (next > 0x1FFFFFFFFFF) {
                                    orders[next] &= 0x00000000000000000000000003FFFFFFFFFE0000000000000000000000000000;
                                }
                                else {
                                    delete orders[(marketId << 128) | (price << 48) | next];
                                }
                                next = (_order >> 205) & 0x7FFFFFFFFFFFF;
                            }
                        }
                        priceLevels[(marketId << 128) | price] = (next << 205) | (_priceLevel & 0x0000000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF); // set fillnext to next
                    }
                    assembly {
                        let temp := mload(0x80)
                        temp := or(and(temp, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000000000000000000000000000), price) // set end price
                        mstore(0x80, temp)
                    }
                    if ((_priceLevel & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) == 0) {
                        slot &= ~(1 << (tick % 256));
                        uint256 slotIndex = tick >> 8;
                        if ((orderInfo >> 244 & 0xF) == 0) {
                            uint256 _slot = slot >> tick % 256;
                            if (_slot == 0 && activated[(marketId << 128) | slotIndex] != slot) {
                                activated[(marketId << 128) | slotIndex] = slot;
                            }
                            while (_slot == 0) {
                                ++slotIndex;
                                slot = activated[(marketId << 128) | slotIndex];
                                _slot = slot;
                                tick = slotIndex << 8;
                            }
                            if (_slot & ((1 << 128) - 1) == 0) {_slot >>= 128; tick += 128;}
                            if (_slot & ((1 << 64) - 1) == 0) {_slot >>= 64; tick += 64;}
                            if (_slot & ((1 << 32) - 1) == 0) {_slot >>= 32; tick += 32;}
                            if (_slot & ((1 << 16) - 1) == 0) {_slot >>= 16; tick += 16;}
                            if (_slot & ((1 << 8) - 1) == 0) {_slot >>= 8; tick += 8;}
                            if (_slot & ((1 << 4) - 1) == 0) {_slot >>= 4; tick += 4;}
                            if (_slot & ((1 << 2) - 1) == 0) {_slot >>= 2; tick += 2;}
                            if (_slot & 1 == 0) {++tick;}
                        }
                        else {
                            uint256 _slot = slot & ((1 << (tick % 256)) - 1);
                            if (_slot == 0 && activated[(marketId << 128) | slotIndex] != slot) {
                                activated[(marketId << 128) | slotIndex] = slot;
                            }
                            while (_slot == 0) {
                                --slotIndex;
                                slot = activated[(marketId << 128) | slotIndex];
                                _slot = slot;
                            }
                            tick = slotIndex << 8;
                            if (_slot >= 2 ** 128) {_slot >>= 128; tick += 128;}
                            if (_slot >= 2 ** 64) {_slot >>= 64; tick += 64;}
                            if (_slot >= 2 ** 32) {_slot >>= 32; tick += 32;}
                            if (_slot >= 2 ** 16) {_slot >>= 16; tick += 16;}
                            if (_slot >= 2 ** 8) {_slot >>= 8; tick += 8;}
                            if (_slot >= 2 ** 4) {_slot >>= 4; tick += 4;}
                            if (_slot >= 2 ** 2) {_slot >>= 2; tick += 2;}
                            if (_slot >= 2 ** 1) {++tick;}
                        }
                        price = _tickToPrice(tick);
                    }
                    else {
                        if (activated[(marketId << 128) | (tick >> 8)] != slot) {
                            activated[(marketId << 128) | (tick >> 8)] = slot;
                        }
                    }
                    if (sizeLeft == 0 || ((orderInfo >> 252) == 3 && gasleft() < 100000)) {
                        break;
                    }
                }
            }
            if (amountOut != 0) {
                {   
                    if (reserves != 0) {
                        (uint112 reserveQuote, uint112 reserveBase) = (uint112(reserves >> 128), uint112(reserves & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF));
                        if (reserveQuote != _getMarket[market].reserveQuote || reserveBase != _getMarket[market].reserveBase) {
                            _getMarket[market].reserveQuote = reserveQuote;
                            _getMarket[market].reserveBase = reserveBase;
                            emit Sync(market, reserveQuote, reserveBase);
                        }
                    }
                }
                uint256 feeAmount;
                if ((orderInfo >> 244 & 0xF) == 0) {
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
                    claimableRewards[quoteAsset][feeRecipient] += feeAmount;
                }
                else {
                    uint256 amountCommission = feeAmount * feeCommission / 100;
                    claimableRewards[quoteAsset][address(uint160(priceAndReferrer >> 80))] += amountCommission;
                    uint256 amountRebate = feeAmount * feeRebate / 100;
                    claimableRewards[quoteAsset][address(uint160(orderInfo))] += amountRebate;
                    claimableRewards[quoteAsset][feeRecipient] += (feeAmount - amountCommission - amountRebate);
                }
                assembly {
                    price := mload(0x80)
                }
                emit Trade(market, (orderInfo >> 160) & 0x1FFFFFFFFFF, address(uint160(orderInfo)), (orderInfo >> 244 & 0xF) == 0, amountIn, amountOut, price >> 128, price & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
                return (amountIn, amountOut, id, settlementDelta);
            }
            else {
                return (amountIn, 0, id, settlementDelta);
            }
        }
    }
    // done
    function _limitOrder(bool isBuy, bool isRecieveTokens, uint256 price, uint256 size, uint256 userId, uint256 cloid) internal returns (uint256 _size, uint256 id) { // cloid being under uint10 is enforced in entry points
        unchecked {
            Market storage m = _getMarket[market];
            (uint256 _highestBid, uint256 _lowestAsk) = (m.highestBid, m.lowestAsk);
            if (isBuy) {
                if (price >= _lowestAsk || price == 0 || size < ((m.minSize >> 20) * 10 ** (m.minSize & 0xFFFFF)) || ((orders[(cloid << 41) | userId] & 0xFFFFFFFFFFFFFFFFFFFFFFFFFC0000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFF) != 0)) {
                    return (0, 0);
                }
                if (price > _highestBid) {
                    m.highestBid = uint80(price);
                }
                if (!isRecieveTokens) {
                    tokenBalances[userId][quoteAsset] += (size << 128); // lock tokens if internal
                }
            }
            else {
                if (price <= _highestBid || price >= maxPrice || (size * price / scaleFactor) < ((m.minSize >> 20) * 10 ** (m.minSize & 0xFFFFF)) || ((orders[(cloid << 41) | userId] & 0xFFFFFFFFFFFFFFFFFFFFFFFFFC0000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFF) != 0)) {
                    return (0, 0);
                }
                if (price < _lowestAsk) {
                    m.lowestAsk = uint80(price);
                }
                if (!isRecieveTokens) {
                    tokenBalances[userId][baseAsset] += (size << 128); // lock tokens if internal
                }
            }
            uint256 _priceLevel = priceLevels[(marketId << 128) | price];
            require((size <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) && ((_priceLevel & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) + size) <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF); // overflow check, if invalid params are entered could revert instead of silent return
            if (cloid != 0) {
                if (cloid & 1 == 1) {
                    cloidVerify[((cloid | 1) << 41) | userId] = cloidVerify[((cloid | 1) << 41) | userId] & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000000000000000000000000000 | ((marketId << 80) | price);
                }
                else {
                    cloidVerify[((cloid | 1) << 41) | userId] = cloidVerify[((cloid | 1) << 41) | userId] & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF | ((marketId << 208) | (price << 128));
                }
                cloid = (cloid << 41) | userId; // cloid to pointer using userid
                if ((_priceLevel & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) == 0) {
                    require(price % tickSize == 0);
                    uint256 tick = _priceToTick(price);
                    activated[(marketId << 128) | (tick >> 8)] |= (1 << (tick % 256));
                    _priceLevel =  (cloid << 205) | (_priceLevel & 0x0000000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF); // set fillNext to cloid
                }
                else {
                    uint256 fillBefore = (_priceLevel >> 154) & 0x7FFFFFFFFFFFF;
                    orders[(fillBefore > 0x1FFFFFFFFFF) ? fillBefore : ((marketId << 128) | (price << 48) | fillBefore)] = (cloid << 205) | (orders[(fillBefore > 0x1FFFFFFFFFF) ? fillBefore : ((marketId << 128) | (price << 48) | fillBefore)] & 0x0000000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF); // set fillbefores fillafter to cloid instead of prev native id
                }
                orders[cloid] = (((_priceLevel >> 113 & 0x1FFFFFFFFFF) + 1) << 205) | (_priceLevel & (0x7FFFFFFFFFFFF << 154)) | (userId << 113) | (isRecieveTokens ? 0 : (1 << 112)) | size; // fillAfter to priceLevels latestNativeId+1, fillBefore to latest
                priceLevels[(marketId << 128) | price] = (cloid << 154) | ((_priceLevel & 0xFFFFFFFFFFFFE0000000000003FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) + size); // latest to cloid and add size
                return (size, cloid);
            }
            else {
                id = (_priceLevel >> 113 & 0x1FFFFFFFFFF) + 1;
                require(id <= 0x1FFFFFFFFFF); // overflow uint41
                if ((_priceLevel & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) == 0) {
                    require(price % tickSize == 0);
                    uint256 tick = _priceToTick(price);
                    activated[(marketId << 128) | (tick >> 8)] |= (1 << (tick % 256));
                    _priceLevel = (id << 205) | (_priceLevel & 0x0000000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF); // set fillNext to id, sometimes redundant
                }
                orders[(marketId << 128) | (price << 48) | id] = ((id + 1) << 205) | (_priceLevel & (0x7FFFFFFFFFFFF << 154)) | (userId << 113) | (isRecieveTokens ? 0 : (1 << 112)) | size; // fillAfter to id+1, fillBefore to latest
                priceLevels[(marketId << 128) | price] = (id << 154) | (id << 113) | ((_priceLevel & 0xFFFFFFFFFFFFE00000000000000000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFF) + size); // latest and latestNativeId to id and add size
                return (size, id);
            }
        }       
    }
    // done
    function _cancelOrder(uint256 price, uint256 id, uint256 userId) internal returns (uint256, uint256 size, bool isBuy) { // id is cloid if price is missing
        unchecked {
            Market storage m = _getMarket[market];
            uint256 _order = orders[(price != 0 ? ((marketId << 128) | (price << 48) | id) : ((id << 41) | userId))]; // id is not yet pointer
            size = (_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
            if (0 == size || userId != (_order >> 113 & 0x1FFFFFFFFFF)) {
                return (0, 0, isBuy);
            }
            if (price != 0) {
                delete orders[(marketId << 128) | (price << 48) | id];
            }
            else {
                price = cloidVerify[((id | 1) << 41) | userId]; // avoid stack too deep, there's no reason to zero out/edit this as it's not needed
                if (id & 1 == 1) { // make sure order is in right market, get price because cloid doesn't come with it
                    if (((price >> 80) & 0xFFFFFFFFFFFF) != marketId) {
                        return (0, 0, isBuy);
                    }
                    price = price & 0xFFFFFFFFFFFFFFFFFFFF;
                }
                else {
                    if (((price >> 208) & 0xFFFFFFFFFFFF) != marketId) {
                        return (0, 0, isBuy);
                    }
                    price = (price >> 128) & 0xFFFFFFFFFFFFFFFFFFFF;
                }
                id = (id << 41) | userId; // id to pointer using userid
                orders[id] &= 0x00000000000000000000000003FFFFFFFFFE0000000000000000000000000000;
            }
            (uint256 _highestBid, uint256 _lowestAsk) = (m.highestBid, m.lowestAsk);
            if (price <= _highestBid) {
                isBuy = true;
                if ((_order & 0x0000000000000000000000000000000000010000000000000000000000000000) != 0) {
                    tokenBalances[userId][quoteAsset] -= (size << 128); // unlock tokens if internal
                }
            }
            else {
                if ((_order & 0x0000000000000000000000000000000000010000000000000000000000000000) != 0) {
                    tokenBalances[userId][baseAsset] -= (size << 128); // unlock tokens if internal
                }
            }
            uint256 _priceLevel = priceLevels[(marketId << 128) | price];
            _priceLevel -= size;
            if (id == (_priceLevel >> 205 & 0x7FFFFFFFFFFFF)) { // if pricelevel fillnext then set to fillafter
                _priceLevel = (_order & (0x7FFFFFFFFFFFF << 205)) | (_priceLevel & 0x0000000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
            }
            else if (id == (_priceLevel >> 154 & 0x7FFFFFFFFFFFF)) { // if pricelevel latest then set latest to fillbefore
                uint256 temp = ((((_order >> 154) & 0x7FFFFFFFFFFFF) > 0x1FFFFFFFFFF) ? ((_order >> 154) & 0x7FFFFFFFFFFFF) : (marketId << 128) | (price << 48) | ((_order >> 154) & 0x7FFFFFFFFFFFF));
                orders[temp] = orders[temp] & 0x0000000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF | (_order & (0x7FFFFFFFFFFFF << 205)); // set fillbefores fillafter to fillafter
                _priceLevel = (_priceLevel & 0xFFFFFFFFFFFFE0000000000003FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) | (_order & (0x7FFFFFFFFFFFF << 154));
            }
            else {           
                uint256 temp = (((_order >> 154) & 0x7FFFFFFFFFFFF > 0x1FFFFFFFFFF) ? (_order >> 154) & 0x7FFFFFFFFFFFF : (marketId << 128) | (price << 48) | (_order >> 154) & 0x7FFFFFFFFFFFF);
                orders[temp] = orders[temp] & 0x0000000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF | (_order & (0x7FFFFFFFFFFFF << 205)); // set fillbefores fillafter to fillafter
                temp = ((((_order >> 205) & 0x7FFFFFFFFFFFF) > 0x1FFFFFFFFFF) ? ((_order >> 205) & 0x7FFFFFFFFFFFF) : (marketId << 128) | (price << 48) | ((_order >> 205) & 0x7FFFFFFFFFFFF));
                orders[temp] = orders[temp] & 0xFFFFFFFFFFFFE0000000000003FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF | (_order & (0x7FFFFFFFFFFFF << 154)); // setfillafters fillbefore to fillbefore
            }
            priceLevels[(marketId << 128) | price] = _priceLevel;
            if ((_priceLevel & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) == 0) {
                uint256 tick = _priceToTick(price);
                uint256 slotIndex = tick >> 8;
                uint256 _slot = activated[(marketId << 128) | slotIndex];
                _slot &= ~(1 << (tick % 256));
                activated[(marketId << 128) | slotIndex] = _slot;
                if (price == _lowestAsk) {
                    _slot = _slot >> tick % 256;
                    while (_slot == 0) {
                        ++slotIndex;
                        _slot = activated[(marketId << 128) | slotIndex];
                        tick = slotIndex << 8;
                    }
                    if (_slot & ((1 << 128) - 1) == 0) {_slot >>= 128; tick += 128;}
                    if (_slot & ((1 << 64) - 1) == 0) {_slot >>= 64; tick += 64;}
                    if (_slot & ((1 << 32) - 1) == 0) {_slot >>= 32; tick += 32;}
                    if (_slot & ((1 << 16) - 1) == 0) {_slot >>= 16; tick += 16;}
                    if (_slot & ((1 << 8) - 1) == 0) {_slot >>= 8; tick += 8;}
                    if (_slot & ((1 << 4) - 1) == 0) {_slot >>= 4; tick += 4;}
                    if (_slot & ((1 << 2) - 1) == 0) {_slot >>= 2; tick += 2;}
                    if (_slot & 1 == 0) {++tick;}
                    m.lowestAsk = uint80(_tickToPrice(tick));
                }
                else if (price == _highestBid) {
                    _slot = _slot & ((1 << (tick % 256)) - 1);
                    while (_slot == 0) {
                        --slotIndex;
                        _slot = activated[(marketId << 128) | slotIndex];
                    }
                    tick = slotIndex << 8;
                    if (_slot >= 2 ** 128) {_slot >>= 128; tick += 128;}
                    if (_slot >= 2 ** 64) {_slot >>= 64; tick += 64;}
                    if (_slot >= 2 ** 32) {_slot >>= 32; tick += 32;}
                    if (_slot >= 2 ** 16) {_slot >>= 16; tick += 16;}
                    if (_slot >= 2 ** 8) {_slot >>= 8; tick += 8;}
                    if (_slot >= 2 ** 4) {_slot >>= 4; tick += 4;}
                    if (_slot >= 2 ** 2) {_slot >>= 2; tick += 2;}
                    if (_slot >= 2 ** 1) {++tick;}
                    m.highestBid = uint80(_tickToPrice(tick));
                }
            }
            return (price, size, isBuy);
        }
    }
    // done
    function _decreaseOrder(uint256 price, uint256 id, uint256 decreaseAmount, uint256 userId) internal returns (uint256, uint256 size, bool isBuy) { // id is cloid if price is missing
        unchecked {
            Market storage m = _getMarket[market];
            uint256 _order = orders[(price != 0 ? ((marketId << 128) | (price << 48) | id) : ((id << 41) | userId))]; // id is not yet pointer
            size = (_order & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
            if (0 == size || userId != (_order >> 113 & 0x1FFFFFFFFFF)) {
                return (0, 0, isBuy);
            }
            if (price == 0) {
                price = cloidVerify[((id | 1) << 41) | userId]; // avoid stack too deep, there's no reason to zero out/edit this as it's not needed
                if (id & 1 == 1) { // make sure order is in right market, get price because cloid doesn't come with it
                    if (((price >> 80) & 0xFFFFFFFFFFFF) != marketId) {
                        return (0, 0, isBuy);
                    }
                    price = price & 0xFFFFFFFFFFFFFFFFFFFF;
                }
                else {
                    if (((price >> 208) & 0xFFFFFFFFFFFF) != marketId) {
                        return (0, 0, isBuy);
                    }
                    price = (price >> 128) & 0xFFFFFFFFFFFFFFFFFFFF;
                }
                id = (id << 41) | userId; // id to pointer using userid
            }
            (uint256 _highestBid, uint256 _lowestAsk) = (m.highestBid, m.lowestAsk);
            if (price <= _highestBid) {
                isBuy = true;
            }
            if ((isBuy ? size : (size * price / scaleFactor)) <= (isBuy ? decreaseAmount : (decreaseAmount * price / scaleFactor)) + (((m.minSize >> 20) * 10 ** (m.minSize & 0xFFFFF)))) { // cancel if resulting order would be too small
                if ((_order & 0x0000000000000000000000000000000000010000000000000000000000000000) != 0) {
                    isBuy ? tokenBalances[userId][quoteAsset] -= (size << 128) : tokenBalances[userId][baseAsset] -= (size << 128); // unlock tokens if internal
                }
                if (price != 0) {
                    delete orders[(marketId << 128) | (price << 48) | id];
                }
                else {
                    orders[id] &= 0x00000000000000000000000003FFFFFFFFFE0000000000000000000000000000;
                }
                decreaseAmount = priceLevels[(marketId << 128) | price]; // _priceLevel, avoid stack too deep
                decreaseAmount -= size;
                if (id == (decreaseAmount >> 205 & 0x7FFFFFFFFFFFF)) { // if pricelevel fillnext then set to fillafter
                    decreaseAmount = (_order & (0x7FFFFFFFFFFFF << 205)) | (decreaseAmount & 0x0000000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
                }
                else if (id == (decreaseAmount >> 154 & 0x7FFFFFFFFFFFF)) { // if pricelevel latest then set latest to fillbefore
                    uint256 temp = ((((_order >> 154) & 0x7FFFFFFFFFFFF) > 0x1FFFFFFFFFF) ? ((_order >> 154) & 0x7FFFFFFFFFFFF) : (marketId << 128) | (price << 48) | ((_order >> 154) & 0x7FFFFFFFFFFFF));
                    orders[temp] = orders[temp] & 0x0000000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF | (_order & (0x7FFFFFFFFFFFF << 205)); // set fillbefores fillafter to fillafter
                    decreaseAmount = (decreaseAmount & 0xFFFFFFFFFFFFE0000000000003FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) | (_order & (0x7FFFFFFFFFFFF << 154));
                }
                else {           
                    uint256 temp = (((_order >> 154) & 0x7FFFFFFFFFFFF > 0x1FFFFFFFFFF) ? (_order >> 154) & 0x7FFFFFFFFFFFF : (marketId << 128) | (price << 48) | (_order >> 154) & 0x7FFFFFFFFFFFF);
                    orders[temp] = orders[temp] & 0x0000000000001FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF | (_order & (0x7FFFFFFFFFFFF << 205)); // set fillbefores fillafter to fillafter
                    temp = ((((_order >> 205) & 0x7FFFFFFFFFFFF) > 0x1FFFFFFFFFF) ? ((_order >> 205) & 0x7FFFFFFFFFFFF) : (marketId << 128) | (price << 48) | ((_order >> 205) & 0x7FFFFFFFFFFFF));
                    orders[temp] = orders[temp] & 0xFFFFFFFFFFFFE0000000000003FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF | (_order & (0x7FFFFFFFFFFFF << 154)); // setfillafters fillbefore to fillbefore
                }
                priceLevels[(marketId << 128) | price] = decreaseAmount;
                if ((decreaseAmount & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) == 0) {
                    uint256 tick = _priceToTick(price);
                    uint256 slotIndex = tick >> 8;
                    uint256 _slot = activated[(marketId << 128) | slotIndex];
                    _slot &= ~(1 << (tick % 256));
                    activated[(marketId << 128) | slotIndex] = _slot;
                    if (price == _lowestAsk) {
                        _slot = _slot >> tick % 256;
                        while (_slot == 0) {
                            ++slotIndex;
                            _slot = activated[(marketId << 128) | slotIndex];
                            tick = slotIndex << 8;
                        }
                        if (_slot & ((1 << 128) - 1) == 0) {_slot >>= 128; tick += 128;}
                        if (_slot & ((1 << 64) - 1) == 0) {_slot >>= 64; tick += 64;}
                        if (_slot & ((1 << 32) - 1) == 0) {_slot >>= 32; tick += 32;}
                        if (_slot & ((1 << 16) - 1) == 0) {_slot >>= 16; tick += 16;}
                        if (_slot & ((1 << 8) - 1) == 0) {_slot >>= 8; tick += 8;}
                        if (_slot & ((1 << 4) - 1) == 0) {_slot >>= 4; tick += 4;}
                        if (_slot & ((1 << 2) - 1) == 0) {_slot >>= 2; tick += 2;}
                        if (_slot & 1 == 0) {++tick;}
                        m.lowestAsk = uint80(_tickToPrice(tick));
                    }
                    else if (price == _highestBid) {
                        _slot = _slot & ((1 << (tick % 256)) - 1);
                        while (_slot == 0) {
                            --slotIndex;
                            _slot = activated[(marketId << 128) | slotIndex];
                        }
                        tick = slotIndex << 8;
                        if (_slot >= 2 ** 128) {_slot >>= 128; tick += 128;}
                        if (_slot >= 2 ** 64) {_slot >>= 64; tick += 64;}
                        if (_slot >= 2 ** 32) {_slot >>= 32; tick += 32;}
                        if (_slot >= 2 ** 16) {_slot >>= 16; tick += 16;}
                        if (_slot >= 2 ** 8) {_slot >>= 8; tick += 8;}
                        if (_slot >= 2 ** 4) {_slot >>= 4; tick += 4;}
                        if (_slot >= 2 ** 2) {_slot >>= 2; tick += 2;}
                        if (_slot >= 2 ** 1) {++tick;}
                        m.highestBid = uint80(_tickToPrice(tick));
                    }
                }
                return (price, size, isBuy);
            }
            else {
                if ((_order & 0x0000000000000000000000000000000000010000000000000000000000000000) != 0) {
                    isBuy ? tokenBalances[userId][quoteAsset] -= (decreaseAmount << 128) : tokenBalances[userId][baseAsset] -= (decreaseAmount << 128); // unlock tokens if internal
                }
                orders[(price != 0 ? ((marketId << 128) | (price << 48) | id) : id)] -= decreaseAmount;
                priceLevels[(marketId << 128) | price] -= decreaseAmount;
                return (price, decreaseAmount << 128, isBuy); // price, decrease amount, isBuy
            }
        }
    }
    // done
    function _replaceOrder(uint256 options, uint256 price, uint256 id, uint256 newPrice, uint256 size) internal returns (int256 quoteAssetDebt, int256 baseAssetDebt, uint256) {
        unchecked {
            bool _isBuy;
            bool _isCloid;
            uint256 _size;
            if (price != 0) {
                _size = (orders[((marketId << 128) | (price << 48) | id)] & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF); // id is not pointer
            }
            else {
                _isCloid = true;
                price = cloidVerify[((id | 1) << 41) | (options & 0x1FFFFFFFFFF)]; // avoid stack too deep, there's no reason to zero out/edit this as it's not needed
                if (id & 1 == 1) { // make sure order is in right market, get price because cloid doesn't come with it
                    if (((price >> 80) & 0xFFFFFFFFFFFF) != marketId) {
                        return (0, 0, 0);
                    }
                    price = price & 0xFFFFFFFFFFFFFFFFFFFF;
                }
                else {
                    if (((price >> 208) & 0xFFFFFFFFFFFF) != marketId) {
                        return (0, 0, 0);
                    }
                    price = (price >> 128) & 0xFFFFFFFFFFFFFFFFFFFF;
                }
                _size = (orders[((id << 41) | (options & 0x1FFFFFFFFFF))] & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF); // id is not pointer
            }
            if (price <= _getMarket[market].highestBid) {
                _isBuy = true;
            }
            if (newPrice == 0) {
                newPrice = price;
            }
            if ((((options >> 48) & 0xF) != 0) || (newPrice == price && (_size > size))) {
                (price, _size, _isBuy) = _decreaseOrder(_isCloid ? 0 : price, id, _size - size, (options & 0x1FFFFFFFFFF)); // price is 0 if cloid
                if (_isCloid) {
                    id = (id << 41) | (options & 0x1FFFFFFFFFF); // differentiate emitted cloid
                }
                if (_size != 0) {
                    if ((_size >> 128) == 0) { // cancel
                        if (_isBuy) {
                            quoteAssetDebt -= int256(_size & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
                        }
                        else {
                            baseAssetDebt -= int256(_size & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
                        }
                        assembly {
                            let length := mload(0xc0)
                            mstore(add(length, 0xe0), or(mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(_isBuy)),or(shl(168,price),or(shl(112,id),and(112, _size))))) // 3 bits flag 80 price 56 id 112 cancel size
                            mstore(0xc0, add(length, 0x20))
                            mstore(0x40, add(length, 0x100))
                        }
                    }
                    else {
                        if (_isBuy) {
                            quoteAssetDebt -= int256(_size >> 128);
                        }
                        else {
                            baseAssetDebt -= int256(_size >> 128);
                        }
                        assembly {
                            let length := mload(0xc0)
                            mstore(add(length, 0xe0), or(add(0x4000000000000000000000000000000000000000000000000000000000000000,mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(_isBuy))),or(shl(168,price),or(shl(112,id),shr(128, _size))))) // 3 bits flag 80 price 56 id 112 decrease size not remaining
                            mstore(0xc0, add(length, 0x20))
                            mstore(0x40, add(length, 0x100))
                        }
                    }
                    return (quoteAssetDebt, baseAssetDebt, id);
                }
                else {
                    return (0, 0, 0); // no state is changed, can silent return
                }
            }
            else {
                (price, _size, _isBuy) = _cancelOrder((_isCloid) ? 0 : price, id, (options & 0x1FFFFFFFFFF)); // price is 0 if cloid
                if (_isCloid) {
                    id = (id << 41) | (options & 0x1FFFFFFFFFF); // differentiate emitted cloid
                }
                if (_size != 0) {
                    if (_isBuy) {
                        quoteAssetDebt -= int256(_size);
                    }
                    else {
                        baseAssetDebt -= int256(_size);
                    }
                    assembly {
                        let length := mload(0xc0)
                        mstore(add(length, 0xe0), or(mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(_isBuy)),or(shl(168,price),or(shl(112,id),_size)))) // 3 bits flag 80 price 56 id 112 size
                        mstore(0xc0, add(length, 0x20))
                        mstore(0x40, add(length, 0x100))
                    }
                }
                else {
                    return (0, 0, 0); // no state is changed, can silent return
                }
                if (_isCloid) {
                    id = id >> 41; // back to normal cloid
                }
                if (size == 0) {
                    size = _size;
                }
                if (((options >> 44) & 0xF) == 0) { // post only
                    (_size, id) = _limitOrder(_isBuy, (((options >> 60) & 0xF) == 0), newPrice, size, (options & 0x1FFFFFFFFFF), id);
                    if (_size != 0) {
                        _isBuy ? quoteAssetDebt += int256(_size) : baseAssetDebt += int256(_size);
                        assembly {
                            let length := mload(0xc0)
                            mstore(add(length, 0xe0), or(add(0x2000000000000000000000000000000000000000000000000000000000000000,mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(_isBuy))),or(shl(168,newPrice),or(shl(112,id),_size)))) // 3 bits flag 80 price 56 id 112 size
                            mstore(0xc0, add(length, 0x20))
                            mstore(0x40, add(length, 0x100))
                        }
                    }
                    else {
                        return (quoteAssetDebt, baseAssetDebt, 0);
                    }
                }
                else {
                    _isCloid = ((options >> 60) & 0xF) == 0; // avoid stack too deep, true if external balances
                    uint256 settlementDelta;
                    uint256 referrer = (options >> 96);
                    uint256 orderInfo = (2 << 252) | (_isBuy ? 0 : (1 << 244)) | (1 << 240) | (_isCloid ? 0 : (1 << 236)) | (id << 208) | ((options & 0x1FFFFFFFFFF) << 160) | uint160(msg.sender);
                    (, _size, id, settlementDelta) = _marketOrder(size, (uint160(referrer) << 80) | newPrice, orderInfo);
                    if (_isBuy) {
                        quoteAssetDebt += int256(settlementDelta >> 128);
                        baseAssetDebt -= int256(_size + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                    }
                    else {
                        baseAssetDebt += int256(settlementDelta >> 128);
                        quoteAssetDebt -= int256(_size + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                    }
                }
                return (quoteAssetDebt, baseAssetDebt, id);
            }
        }
    }
    // make sure to keep pricetimepriority, relinking order on partial fill is fine because it's a single fill
    function _placeGridOrder(bool isBuy, uint256 price, uint256 mirroredPrice, uint256 size, uint256 userId) internal returns (uint256 _size, uint256 id) {
    }
    // done, these methods support margin which is managed before/after the call, just set internal balance mode to true
    function marketOrder(bool isBuy, bool isExactInput, uint256 options, uint256 orderType, uint256 size, uint256 worstPrice, address referrer, address caller) external returns (uint256 amountIn, uint256 amountOut, uint256 id) {
        unchecked {
            uint256 orderInfo; // options is 0-44 userId 44-54 cloid 56-60 stp 60-64 tointernalbalances 64-68 frominternalbalances 68-72 useinternalbalances
            uint256 userId;
            {
                uint256 orderFlags = ((orderType & 0xF) << 252) | ((isExactInput ? 0 : (1 << 248))) | ((isBuy ? 0 : (1 << 244))) | (((options >> 56) & 0xF) << 240); // ordertype exactinput=0 isbuy=0 stp
                orderInfo = orderFlags | (((options >> 68) & 0xF) << 236) | (((options >> 64) & 0xF) << 232) | uint160(caller); // useexternalbalance=0 fromcaller=0 add userId 160-208 if internal balance or mtl and cloid if provided 208-218 if mtl and margin enforced elsewhere
                userId = (options & 0x1FFFFFFFFFF);
                if (userId != 0) {
                    require(userIdToAddress[userId] == caller);
                }
                else {
                    userId = addressToUserId[caller];
                    if (userId == 0) {
                        userId = ICrystal(crystal).registerUser();
                    }
                }
                orderInfo |= (userId << 160); // add userId to orderInfo
                if (((options >> 44) & 0x3FF) != 0) { // if cloid
                    orderInfo |= (((options >> 44) & 0x3FF) << 208);
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
                    log3(0xa0, add(length, 0x40), 0xcd726e874e479599fa8abfd7a4ad443b08415d78fb36a088cd0e9c88b249ba66, _market, userId)
                }
            }
            if (isBuy && ((settlementDelta >> 128) != 0)) { // input token for both limit order and maker internal balance fills
                if (((options >> 68) & 0xF) != 0 || ((options >> 64) & 0xF) != 0) {
                    uint256 balance = tokenBalances[userId][quoteAsset];
                    if (uint128(balance) < (settlementDelta >> 128)) {
                        revert ActionFailed();
                    }
                    else {
                        tokenBalances[userId][quoteAsset] = balance - (settlementDelta >> 128);
                    }
                }
                else { // use external balance
                    IERC20(quoteAsset).transferFrom(caller, address(this), (settlementDelta >> 128));
                }
            }
            else if ((settlementDelta >> 128) != 0) {
                if (((options >> 68) & 0xF) != 0 || ((options >> 64) & 0xF) != 0) {
                    uint256 balance = tokenBalances[userId][baseAsset];
                    if (uint128(balance) < (settlementDelta >> 128)) {
                        revert ActionFailed();
                    }
                    else {
                        tokenBalances[userId][baseAsset] = balance - (settlementDelta >> 128);
                    }
                }
                else { // use external balance
                    IERC20(baseAsset).transferFrom(caller, address(this), (settlementDelta >> 128));
                }
            }
            settlementDelta &= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
            settlementDelta += amountOut; // add output to self cancel credit
            if (isBuy && (settlementDelta != 0)) { // output token, stp cancels + amountout
                if (((options >> 68) & 0xF) != 0 || ((options >> 60) & 0xF) != 0) {
                    tokenBalances[userId][baseAsset] += settlementDelta;
                }
                else { // use external balance
                    IERC20(baseAsset).transfer(caller, settlementDelta);
                }
            }
            else if (settlementDelta != 0) {
                if (((options >> 68) & 0xF) != 0 || ((options >> 60) & 0xF) != 0) {
                    tokenBalances[userId][quoteAsset] += settlementDelta;
                }
                else { // use external balance
                    IERC20(quoteAsset).transfer(caller, settlementDelta);
                }
            }
        }
    }
    // done
    function limitOrder(bool isBuy, uint256 options, uint256 price, uint256 size, address caller) external returns (uint256 id) { // options is 0-41 userId 44-54 cloid 56-60 frominternalbalances 60-64 useinternalbalances
        unchecked {
            uint256 userId = (options & 0x1FFFFFFFFFF);
            if (userId != 0) { // if userId is supplied verify
                require(userIdToAddress[userId] == caller);
            }
            else { // get default userId
                userId = addressToUserId[caller];
                if (userId == 0) {
                    userId = ICrystal(crystal).registerUser();
                }
            }
            bool useExternalBalances = (((options >> 60) & 0xF) == 0);
            (size, id) = _limitOrder(isBuy, useExternalBalances, price, size, userId, (options >> 44) & 0x3FF);
            if (size != 0) { // if order success
                if (isBuy) {
                    if (useExternalBalances || ((options >> 56) & 0xF) != 0) {
                        IERC20(quoteAsset).transferFrom(caller, address(this), size);
                    }
                    else {
                        uint256 balance = tokenBalances[userId][quoteAsset];
                        if (uint128(balance) < size) {
                            revert ActionFailed();
                        }
                        else {
                            tokenBalances[userId][quoteAsset] = balance - size; // token txfer don't care about locking since done in internal function
                        }
                    }
                    emit OrdersUpdated(market, userId, abi.encodePacked(0x2000000000000000000000000000000000000000000000000000000000000000 | (price << 168) | (id << 112) | size)); // if id is a cloid it is already merged w user id
                }
                else {
                    if (useExternalBalances || ((options >> 56) & 0xF) != 0) {
                        IERC20(baseAsset).transferFrom(caller, address(this), size);
                    }
                    else {
                        uint256 balance = tokenBalances[userId][baseAsset];
                        if (uint128(balance) < size) {
                            revert ActionFailed();
                        }
                        else {
                            tokenBalances[userId][baseAsset] = balance - size; // token txfer don't care about locking since done in internal function
                        }
                    }
                    emit OrdersUpdated(market, userId, abi.encodePacked(0x3000000000000000000000000000000000000000000000000000000000000000 | (price << 168) | (id << 112) | size)); // if id is a cloid it is already merged w user id
                }
            }
            else {
                revert ActionFailed();
            }
        }
    } 
    // done
    function cancelOrder(uint256 options, uint256 price, uint256 id, address caller) external returns (uint256 size) { // options is 0-41 userId 44-48 tointernalbalances 48-52 useinternalbalances
        unchecked {
            bool isBuy;
            uint256 userId = (options & 0x1FFFFFFFFFF);
            if (userId != 0) { // if userId is supplied verify
                require(userIdToAddress[userId] == caller);
            }
            else { // get default userId
                userId = addressToUserId[caller];
            }
            bool useExternalBalances = (((options >> 48) & 0xF) == 0);
            bool isCloid = (price == 0); // if price isn't 0 assume it's a normal order
            (price, size, isBuy) = _cancelOrder(price, id, userId); // if no price attached update price
            if (isCloid) {
                id = (id << 41) | userId;
            }
            if (size != 0) { // if cancel success
                if (isBuy) {
                    if (useExternalBalances || ((options >> 44) & 0xF) != 0) {
                        IERC20(quoteAsset).transfer(caller, size);
                    }
                    else {
                        tokenBalances[userId][quoteAsset] += size;
                    }
                    emit OrdersUpdated(market, userId, abi.encodePacked((price << 168) | (id << 112) | size));
                }
                else {
                    if (useExternalBalances || ((options >> 44) & 0xF) != 0) {
                        IERC20(baseAsset).transfer(caller, size);
                    }
                    else {
                        tokenBalances[userId][baseAsset] += size;
                    }
                    emit OrdersUpdated(market, userId, abi.encodePacked(0x1000000000000000000000000000000000000000000000000000000000000000  | (price << 168) | (id << 112) | size));
                }
            }
        }
    }
    // replace is useful in that if cancel fails there's no order, will decrease if its best course of action, and also that you can take the proceeds of the cancel as the order size by setting size=0, can also do decrease
    function replaceOrder(uint256 options, uint256 price, uint256 id, uint256 newPrice, uint256 size, address referrer, address caller) external returns (uint256 _id) { // options is 0-41 userId 44-48 postOnly=0 48-52 isDecrease 52-56 tointernalbalances 56-60 frominternalbalances 60-64 useinternalbalances
        int256 quoteAssetDebt;
        int256 baseAssetDebt;
        uint256 userId = (options & 0x1FFFFFFFFFF);
        if (userId != 0) { // if userId is supplied verify
            require(userIdToAddress[userId] == caller);
        }
        else { // get default userId
            userId = addressToUserId[caller];
            options = (options & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE0000000000) | userId; // add userId to options
            if (userId == 0) {
                userId = ICrystal(crystal).registerUser();
            }
        }
        options = (uint160(referrer) << 96) | options;
        assembly {
            mstore(0x40, 0xe0) // 0x80 is used by _marketOrder internally to avoid stack too deep
        }
        (quoteAssetDebt, baseAssetDebt, _id) = _replaceOrder(options, price, id, newPrice, size);
        if (((options >> 60) & 0xF) == 0) { // external txfers
            if (((options >> 56) & 0xF) != 0) {
                if (quoteAssetDebt > 0) {
                    uint256 balance = tokenBalances[userId][quoteAsset];
                    if (uint128(balance) < uint256(quoteAssetDebt)) {
                        revert ActionFailed();
                    }
                    else {
                        tokenBalances[userId][quoteAsset] = balance - uint256(quoteAssetDebt);
                    }
                }
                if (baseAssetDebt > 0) {
                    uint256 balance = tokenBalances[userId][baseAsset];
                    if (uint128(balance) < uint256(baseAssetDebt)) {
                        revert ActionFailed();
                    }
                    else {
                        tokenBalances[userId][baseAsset] = balance - uint256(baseAssetDebt);
                    }
                }
            }
            else {
                if (quoteAssetDebt > 0) {
                    IERC20(quoteAsset).transferFrom(caller, address(this), uint256(quoteAssetDebt));
                }
                if (baseAssetDebt > 0) {
                    IERC20(baseAsset).transferFrom(caller, address(this), uint256(baseAssetDebt));
                }
            }
            if (((options >> 52) & 0xF) != 0) {
                if (quoteAssetDebt < 0) {
                    tokenBalances[userId][quoteAsset] += uint256(-quoteAssetDebt);
                }
                if (baseAssetDebt < 0) {
                    tokenBalances[userId][baseAsset] += uint256(-baseAssetDebt);
                }
            }
            else {
                if (quoteAssetDebt < 0) {
                    IERC20(quoteAsset).transfer(caller, uint256(-quoteAssetDebt));
                }
                if (baseAssetDebt < 0) {
                    IERC20(baseAsset).transfer(caller, uint256(-baseAssetDebt));
                }
            }
        }
        else {
            if (((options >> 60) & 0xF) == 1) { // internal balances
                if (quoteAssetDebt > 0) {
                    uint256 balance = tokenBalances[userId][quoteAsset];
                    if (uint128(balance) < uint256(quoteAssetDebt)) {
                        revert ActionFailed();
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
                        revert ActionFailed();
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
                revert ActionFailed();
            }
        }
        address _market = market;
        assembly {
            let length := mload(0xc0)
            switch gt(length, 0)
            case true {
                mstore(0xa0, 0x20)
                log3(0xa0, add(length, 0x40), 0xcd726e874e479599fa8abfd7a4ad443b08415d78fb36a088cd0e9c88b249ba66, _market, userId)
            }
            default {
                revert(0, 0)
            }
        }
    }
    // done except replace if needed, maybe add bribe endpoint in parent, do margin in balance mode param
    function batchOrders(Action[] calldata actions, uint256 options, address referrer, address caller) external { // options is 0-41 userId 44-48 tointernalbalances 48-52 frominternalbalances 52-56 useinternalbalances
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
            if ((options & 0x1FFFFFFFFFF) != 0) { // if userId is supplied verify
                userId = (options & 0x1FFFFFFFFFF);
                require(userIdToAddress[userId] == caller);
            }
            else { // get default userId
                userId = addressToUserId[caller];
                if (userId == 0) {
                    userId = ICrystal(crystal).registerUser();
                }
            }
            balanceMode = ((options >> 52) & 0xF);
            assembly {
                mstore(0x40, 0xe0)
            }
            while (offset < actions.length) {
                action = actions[offset].action & 0xF;
                param1 = actions[offset].param1 & 0xFFFFFFFFFFFFFFFFFFFF;
                param2 = actions[offset].param2 & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
                cloid = actions[offset].param3 & 0x3FF;
                if (action == 1) { // cancel, pass either price and id or cloid
                    if (cloid != 0) {
                        (param1, action, isBuy) = _cancelOrder(0, cloid, userId);
                        param2 = (cloid << 41) | userId; // differentiate emitted cloid
                    }
                    else {
                        (param1, action, isBuy) = _cancelOrder(param1, param2, userId);
                    }
                    if (action != 0) {
                        if (isBuy) {
                            quoteAssetDebt -= int256(action);
                        }
                        else {
                            baseAssetDebt -= int256(action);
                        }
                        assembly {
                            let length := mload(0xc0)
                            mstore(add(length, 0xe0), or(mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(isBuy)),or(shl(168,param1),or(shl(112,param2),action)))) // 8 flag 80 price 56 id 112 size
                            mstore(0xc0, add(length, 0x20))
                            mstore(0x40, add(length, 0x100))
                        }
                    }
                    else {
                        if (actions[offset].isRequireSuccess) {
                            revert ActionFailed();
                        }
                    }
                }
                else if (action == 2) { // limit buy, pass price size and optional cloid
                    (action, param2) = _limitOrder(true, balanceMode == 0, param1, param2, userId, cloid);
                    if (action != 0) {
                        quoteAssetDebt += int256(action);
                        assembly {
                            let length := mload(0xc0)
                            mstore(add(length, 0xe0), or(0x2000000000000000000000000000000000000000000000000000000000000000,or(shl(168,param1),or(shl(112,param2),action)))) // 8 flag 80 price 56 id 112 size
                            mstore(0xc0, add(length, 0x20))
                            mstore(0x40, add(length, 0x100))
                        }
                    }
                    else {
                        if (actions[offset].isRequireSuccess) {
                            revert ActionFailed();
                        }
                    }
                }
                else if (action == 3) { // limit sell
                    (action, param2) = _limitOrder(false, balanceMode == 0, param1, param2, userId, cloid);
                    if (action != 0) {
                        baseAssetDebt += int256(action);
                        assembly {
                            let length := mload(0xc0)
                            mstore(add(length, 0xe0), or(0x3000000000000000000000000000000000000000000000000000000000000000, or(shl(168,param1),or(shl(112,param2),action)))) // 8 flag 80 price 56 id 112 size
                            mstore(0xc0, add(length, 0x20))
                            mstore(0x40, add(length, 0x100))
                        }
                    }
                    else {
                        if (actions[offset].isRequireSuccess) {
                            revert ActionFailed();
                        }
                    }
                }
                else if (action == 4) { // mtl buy
                    uint256 settlementDelta;
                    settlementDelta = (uint160(referrer) << 80) | param1; // avoid stack too deep
                    ( , action, , settlementDelta) = _marketOrder(param2, settlementDelta, (2 << 252) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    quoteAssetDebt += int256(settlementDelta >> 128);
                    baseAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 5) { // mtl sell
                    uint256 settlementDelta;
                    settlementDelta = (uint160(referrer) << 80) | param1;
                    ( , action, , settlementDelta) = _marketOrder(param2, settlementDelta, (2 << 252) | (1 << 244) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    baseAssetDebt += int256(settlementDelta >> 128);
                    quoteAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 6) { // partialfill buy
                    uint256 settlementDelta;
                    settlementDelta = (uint160(referrer) << 80) | param1;
                    ( , action, , settlementDelta) = _marketOrder(param2, settlementDelta, (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    quoteAssetDebt += int256(settlementDelta >> 128);
                    baseAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 7) { // partialfill sell
                    uint256 settlementDelta;
                    settlementDelta = (uint160(referrer) << 80) | param1;
                    ( , action, , settlementDelta) = _marketOrder(param2, settlementDelta, (1 << 244) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    baseAssetDebt += int256(settlementDelta >> 128);
                    quoteAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 8) { // partial buy terminate when low on remaining gas
                    uint256 settlementDelta;
                    settlementDelta = (uint160(referrer) << 80) | param1;
                    ( , action, , settlementDelta) = _marketOrder(param2, settlementDelta, (3 << 252) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    quoteAssetDebt += int256(settlementDelta >> 128);
                    baseAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 9) { // partial sell terminate when low on remaining gas
                    uint256 settlementDelta;
                    settlementDelta = (uint160(referrer) << 80) | param1;
                    ( , action, , settlementDelta) = _marketOrder(param2, settlementDelta, (3 << 252) | (1 << 244) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    baseAssetDebt += int256(settlementDelta >> 128);
                    quoteAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 10) { // complete fill buy
                    uint256 settlementDelta;
                    settlementDelta = (uint160(referrer) << 80) | param1;
                    ( , action, , settlementDelta) = _marketOrder(param2, settlementDelta, (1 << 252) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    quoteAssetDebt += int256(settlementDelta >> 128);
                    baseAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 11) { // complete fill sell
                    uint256 settlementDelta;
                    settlementDelta = (uint160(referrer) << 80) | param1;
                    ( , action, , settlementDelta) = _marketOrder(param2, settlementDelta, (1 << 252) | (1 << 244) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    baseAssetDebt += int256(settlementDelta >> 128);
                    quoteAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 12) { // decrease order, if price then use cloid else use id
                    bool isCloid;
                    if (param1 != 0) { // if price is provided, id is used not cloid
                        cloid = actions[offset].param3 & 0x1FFFFFFFFFF; // id is a uint41
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
                            if (isBuy) {
                                quoteAssetDebt -= int256(param2 & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
                            }
                            else {
                                baseAssetDebt -= int256(param2 & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
                            }
                            assembly {
                                let length := mload(0xc0)
                                mstore(add(length, 0xe0), or(mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(isBuy)),or(shl(168,param1),or(shl(112,cloid),and(112,param2))))) // 8 flag 80 price 56 id 112 cancel size
                                mstore(0xc0, add(length, 0x20))
                                mstore(0x40, add(length, 0x100))
                            }
                        }
                        else {
                            if (isBuy) {
                                quoteAssetDebt -= int256(param2 >> 128);
                            }
                            else {
                                baseAssetDebt -= int256(param2 >> 128);
                            }
                            assembly {
                                let length := mload(0xc0)
                                mstore(add(length, 0xe0), or(add(0x4000000000000000000000000000000000000000000000000000000000000000,mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(isBuy))),or(shl(168,param1),or(shl(112,cloid),shr(128, param2))))) // 8 flag 80 price 56 id 112 decrease size not remaining size
                                mstore(0xc0, add(length, 0x20))
                                mstore(0x40, add(length, 0x100))
                            }
                        }
                    }
                    else {
                        if (actions[offset].isRequireSuccess) {
                            revert ActionFailed();
                        }
                    }
                }
                offset += 1;
            }
            if (balanceMode == 0) { // external txfers
                if (((options >> 48) & 0xF) != 0) {
                    if (quoteAssetDebt > 0) {
                        uint256 balance = tokenBalances[userId][quoteAsset];
                        if (uint128(balance) < uint256(quoteAssetDebt)) {
                            revert ActionFailed();
                        }
                        else {
                            tokenBalances[userId][quoteAsset] = balance - uint256(quoteAssetDebt);
                        }
                    }
                    if (baseAssetDebt > 0) {
                        uint256 balance = tokenBalances[userId][baseAsset];
                        if (uint128(balance) < uint256(baseAssetDebt)) {
                            revert ActionFailed();
                        }
                        else {
                            tokenBalances[userId][baseAsset] = balance - uint256(baseAssetDebt);
                        }
                    }
                }
                else {
                    if (quoteAssetDebt > 0) {
                        IERC20(quoteAsset).transferFrom(caller, address(this), uint256(quoteAssetDebt));
                    }
                    if (baseAssetDebt > 0) {
                        IERC20(baseAsset).transferFrom(caller, address(this), uint256(baseAssetDebt));
                    }
                }
                if (((options >> 44) & 0xF) != 0) {
                    if (quoteAssetDebt < 0) {
                        tokenBalances[userId][quoteAsset] += uint256(-quoteAssetDebt);
                    }
                    if (baseAssetDebt < 0) {
                        tokenBalances[userId][baseAsset] += uint256(-baseAssetDebt);
                    }
                }
                else {
                    if (quoteAssetDebt < 0) {
                        IERC20(quoteAsset).transfer(caller, uint256(-quoteAssetDebt));
                    }
                    if (baseAssetDebt < 0) {
                        IERC20(baseAsset).transfer(caller, uint256(-baseAssetDebt));
                    }
                }
            }
            else {
                if (balanceMode == 1) { // internal balances
                    if (quoteAssetDebt > 0) {
                        uint256 balance = tokenBalances[userId][quoteAsset];
                        if (uint128(balance) < uint256(quoteAssetDebt)) {
                            revert ActionFailed();
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
                            revert ActionFailed();
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
                    revert ActionFailed();
                }
            }
            address _market = market;
            assembly {
                let length := mload(0xc0)
                if gt(length, 0) {
                    mstore(0xa0, 0x20)
                    log3(0xa0, add(length, 0x40), 0xcd726e874e479599fa8abfd7a4ad443b08415d78fb36a088cd0e9c88b249ba66, _market, userId)
                }
            }
        }
    }
    // done except replace if needed, add bribe endpoint in parent, userid is prevalidated, do margin in balance mode param
    fallback() external {
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
                userId := and(0x1FFFFFFFFFF, userId) // it's a uint41 but encoded like a uint44
            }
            offset += 32;
            while (offset < msg.data.length) {
                assembly { // 4-8 is isRequireSuccess
                    action := calldataload(offset)
                    param1 := and(0xFFFFFFFFFFFFFFFFFFFF, shr(112, action)) // 64-144
                    param2 := and(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF, action) // 144-256
                    cloid := and(0x3FF, shr(192, action)) // 20-64
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
                        if (isBuy) {
                            quoteAssetDebt -= int256(action);
                        }
                        else {
                            baseAssetDebt -= int256(action);
                        }
                        assembly {
                            let length := mload(0xc0)
                            mstore(add(length, 0xe0), or(mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(isBuy)),or(shl(168,param1),or(shl(112,param2),action)))) // 8 flag 80 price 56 id 112 size
                            mstore(0xc0, add(length, 0x20))
                            mstore(0x40, add(length, 0x100))
                        }
                    }
                    else {
                        assembly { // reuse isBuy as isRequireSuccess
                            isBuy := and(0x1, shr(248, calldataload(offset))) // 4-8
                        }
                        if (isBuy) {
                            revert ActionFailed();
                        }
                    }
                }
                else if (action == 2) { // limit buy, pass price size and optional cloid
                    (action, param2) = _limitOrder(true, balanceMode == 0, param1, param2, userId, cloid);
                    if (action != 0) {
                        quoteAssetDebt += int256(action);
                        assembly {
                            let length := mload(0xc0)
                            mstore(add(length, 0xe0), or(0x2000000000000000000000000000000000000000000000000000000000000000,or(shl(168,param1),or(shl(112,param2),action)))) // 8 flag 80 price 56 id 112 size
                            mstore(0xc0, add(length, 0x20))
                            mstore(0x40, add(length, 0x100))
                        }
                    }
                    else {
                        assembly { // reuse isBuy as isRequireSuccess
                            isBuy := and(0x1, shr(248, calldataload(offset))) // 4-8
                        }
                        if (isBuy) {
                            revert ActionFailed();
                        }
                    }
                }
                else if (action == 3) { // limit sell
                    (action, param2) = _limitOrder(false, balanceMode == 0, param1, param2, userId, cloid);
                    if (action != 0) {
                        baseAssetDebt += int256(action);
                        assembly {
                            let length := mload(0xc0)
                            mstore(add(length, 0xe0), or(0x3000000000000000000000000000000000000000000000000000000000000000, or(shl(168,param1),or(shl(112,param2),action)))) // 8 flag 80 price 56 id 112 size
                            mstore(0xc0, add(length, 0x20))
                            mstore(0x40, add(length, 0x100))
                        }
                    }
                    else {
                        assembly { // reuse isBuy as isRequireSuccess
                            isBuy := and(0x1, shr(248, calldataload(offset))) // 4-8
                        }
                        if (isBuy) {
                            revert ActionFailed();
                        }
                    }
                }
                else if (action == 4) { // mtl buy
                    uint256 settlementDelta;
                    ( , action, , settlementDelta) = _marketOrder(param2, (uint160(msg.sender) << 80) | param1, (2 << 252) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    quoteAssetDebt += int256(settlementDelta >> 128);
                    baseAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 5) { // mtl sell
                    uint256 settlementDelta;
                    ( , action, , settlementDelta) = _marketOrder(param2, (uint160(msg.sender) << 80) | param1, (2 << 252) | (1 << 244) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    baseAssetDebt += int256(settlementDelta >> 128);
                    quoteAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 6) { // partialfill buy
                    uint256 settlementDelta;
                    ( , action, , settlementDelta) = _marketOrder(param2, (uint160(msg.sender) << 80) | param1, (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    quoteAssetDebt += int256(settlementDelta >> 128);
                    baseAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 7) { // partialfill sell
                    uint256 settlementDelta;
                    ( , action, , settlementDelta) = _marketOrder(param2, (uint160(msg.sender) << 80) | param1, (1 << 244) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    baseAssetDebt += int256(settlementDelta >> 128);
                    quoteAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 8) { // partial buy terminate when low on remaining gas
                    uint256 settlementDelta;
                    ( , action, , settlementDelta) = _marketOrder(param2, (uint160(msg.sender) << 80) | param1, (3 << 252) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    quoteAssetDebt += int256(settlementDelta >> 128);
                    baseAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 9) { // partial sell terminate when low on remaining gas
                    uint256 settlementDelta;
                    ( , action, , settlementDelta) = _marketOrder(param2, (uint160(msg.sender) << 80) | param1, (3 << 252) | (1 << 244) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    baseAssetDebt += int256(settlementDelta >> 128);
                    quoteAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 10) { // complete fill buy
                    uint256 settlementDelta;
                    ( , action, , settlementDelta) = _marketOrder(param2, (uint160(msg.sender) << 80) | param1, (1 << 252) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    quoteAssetDebt += int256(settlementDelta >> 128);
                    baseAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 11) { // complete fill sell
                    uint256 settlementDelta;
                    ( , action, , settlementDelta) = _marketOrder(param2, (uint160(msg.sender) << 80) | param1, (1 << 252) | (1 << 244) | (1 << 240) | (balanceMode << 236) | (cloid << 200) | (userId << 160) | uint160(msg.sender));
                    baseAssetDebt += int256(settlementDelta >> 128);
                    quoteAssetDebt -= int256(action + (settlementDelta & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)); // doesn't overflow because intrinsic is uint128
                }
                else if (action == 12) { // decrease order, if price then use cloid else use id
                    bool isCloid;
                    if (param1 != 0) { // if price is provided, id is used not cloid
                        assembly {
                            cloid := and(0x1FFFFFFFFFF, shr(192, calldataload(offset))) // id is a uint41, 16-64
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
                            if (isBuy) {
                                quoteAssetDebt -= int256(param2 & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
                            }
                            else {
                                baseAssetDebt -= int256(param2 & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
                            }
                            assembly {
                                let length := mload(0xc0)
                                mstore(add(length, 0xe0), or(mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(isBuy)),or(shl(168,param1),or(shl(112,cloid),and(112,param2))))) // 8 flag 80 price 56 id 112 cancel size
                                mstore(0xc0, add(length, 0x20))
                                mstore(0x40, add(length, 0x100))
                            }
                        }
                        else {
                            if (isBuy) {
                                quoteAssetDebt -= int256(param2 >> 128);
                            }
                            else {
                                baseAssetDebt -= int256(param2 >> 128);
                            }
                            assembly {
                                let length := mload(0xc0)
                                mstore(add(length, 0xe0), or(add(0x4000000000000000000000000000000000000000000000000000000000000000,mul(0x1000000000000000000000000000000000000000000000000000000000000000,iszero(isBuy))),or(shl(168,param1),or(shl(112,cloid),shr(128, param2))))) // 8 flag 80 price 56 id 112 decrease size not remaining size
                                mstore(0xc0, add(length, 0x20))
                                mstore(0x40, add(length, 0x100))
                            }
                        }
                    }
                    else {
                        assembly { // reuse isBuy as isRequireSuccess
                            isBuy := and(0x1, shr(248, calldataload(offset))) // 4-8
                        }
                        if (isBuy) {
                            revert ActionFailed();
                        }
                    }
                }
                offset += 32;
            }
            if (balanceMode == 0) { // external txfers
                if (quoteAssetDebt > 0) {
                    IERC20(quoteAsset).transferFrom(msg.sender, address(this), uint256(quoteAssetDebt));
                }
                else if (quoteAssetDebt < 0) {
                    IERC20(quoteAsset).transfer(msg.sender, uint256(-quoteAssetDebt));
                }
                if (baseAssetDebt > 0) {
                    IERC20(baseAsset).transferFrom(msg.sender, address(this), uint256(baseAssetDebt));
                }
                else if (baseAssetDebt < 0) {
                    IERC20(baseAsset).transfer(msg.sender, uint256(-baseAssetDebt));
                }
            }
            else {
                if (balanceMode == 1) { // internal balances
                    if (quoteAssetDebt > 0) {
                        uint256 balance = tokenBalances[userId][quoteAsset];
                        if (uint128(balance) < uint256(quoteAssetDebt)) {
                            revert ActionFailed();
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
                            revert ActionFailed();
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
                    revert ActionFailed();
                }
            }
            address _market = market;
            assembly {
                let length := mload(0xc0)
                if gt(length, 0) {
                    mstore(0xa0, 0x20)
                    log3(0xa0, add(length, 0x40), 0xcd726e874e479599fa8abfd7a4ad443b08415d78fb36a088cd0e9c88b249ba66, _market, userId)
                }
            }
        }
    }
} */