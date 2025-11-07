// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC20} from '../interfaces/IERC20.sol';
import {ICrystal} from '../interfaces/ICrystal.sol';
import {ICrystalVault} from '../interfaces/ICrystalVault.sol';
import {ICrystalVaultFactory} from '../interfaces/ICrystalVaultFactory.sol';

contract ERC20 {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    bytes32 public DOMAIN_SEPARATOR;
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint256) public nonces;

    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes(_name)),
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

    function approve(address spender, uint256 value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external virtual returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external virtual returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
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
}

contract CrystalVault is ERC20 {
    mapping(address => uint) public lastDepositTimestamp;
    uint256 public maxShares;
    address public market;
    uint40 public lockup;
    uint16 public orderCap;
    bool public decrease;
    bool public locked;
    bool public closed;
    ICrystalVault.VaultMetaData public metadata;
    address public immutable crystal;
    address public immutable quoteAsset;
    address public immutable baseAsset;
    address public immutable owner;
    address public immutable factory;

    constructor(address _crystal, address _quoteAsset, address _baseAsset, address _owner, string memory _symbol, ICrystalVault.VaultMetaData memory _metadata) ERC20(_metadata.name, _symbol) {
        crystal = _crystal;
        metadata = _metadata;
        market = ICrystal(crystal).getMarketByTokens(_quoteAsset, _baseAsset);
        require(ICrystal(crystal).getMarket(market).quoteAsset == _quoteAsset); // min owner deposit is enforced in factory, valid market is enforced here aswell
        quoteAsset = _quoteAsset;
        baseAsset = _baseAsset;
        owner = _owner;
        factory = msg.sender;
        orderCap = ICrystalVaultFactory(factory).maxOrderCap();
        lockup = ICrystalVaultFactory(factory).maxLockup();
        ICrystal(crystal).registerUser(address(this));
        IERC20(quoteAsset).approve(crystal, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        IERC20(baseAsset).approve(crystal, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
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

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function getBalances() public view returns (uint256 quoteBalance, uint256 baseBalance, uint256 availableBalanceQuote, uint256 availableBalanceBase) {
        (quoteBalance, availableBalanceQuote, ) = ICrystal(crystal).getDepositedBalance(address(this), quoteAsset);
        (baseBalance, availableBalanceBase, ) = ICrystal(crystal).getDepositedBalance(address(this), baseAsset);
    }
    
    function transfer(address, uint) external pure override returns (bool) {
        revert();
    }

    function transferFrom(address, address, uint) external pure override returns (bool) {
        revert();
    }

    function lock() external {
        require((factory == msg.sender) && locked == false);
        locked = true;
    }

    function unlock() external {
        require((factory == msg.sender) && locked == true && closed == false);
        locked = false;
    }

    function changeMaxShares(uint256 _maxShares) external {
        require(factory == msg.sender);
        maxShares = _maxShares;
    }

    function changeMarket() external {
        require(factory == msg.sender);
        cancelAll();
        address newMarket = ICrystal(crystal).getMarketByTokens(quoteAsset, baseAsset);
        require(ICrystal(crystal).getMarket(newMarket).quoteAsset == quoteAsset); // min owner deposit is enforced in factory, valid market is enforced here aswell
        market = newMarket;
    }

    function changeOrderCap(uint16 newCap) external {
        uint256 maxOrderCap = ICrystalVaultFactory(factory).maxOrderCap();
        require(factory == msg.sender && newCap <= maxOrderCap);
        (uint256[] memory cloids, ) = ICrystal(crystal).getAllOrdersByCloid(address(this), orderCap);
        for (uint256 i = 0; i < cloids.length; ++i) {
            require(newCap > cloids[i]);
        }
        orderCap = newCap;
    }

    function changeDecreaseOnWithdraw(bool newDecrease) external {
        require(factory == msg.sender);
        decrease = newDecrease;
    }

    function changeLockup(uint40 newLockup) external {
        uint256 maxLockup = ICrystalVaultFactory(factory).maxLockup();
        require(factory == msg.sender && newLockup <= maxLockup);
        lockup = newLockup;
    }

    function claimFees() external {
        require(factory == msg.sender);
        address[] memory tokens = new address[](2);
        tokens[0] = quoteAsset;
        tokens[1] = baseAsset;
        ICrystal(crystal).claimFees(owner, tokens);
    }

    function clearCloidSlots(uint256 userId, uint256[] calldata ids) external {
        require(factory == msg.sender);
        ICrystal(crystal).clearCloidSlots(userId, ids);
    }

    function previewDeposit(uint256 amountQuoteDesired, uint256 amountBaseDesired) external view returns (uint256 shares, uint256 amountQuote, uint256 amountBase) {
        (uint256 quoteBalance, uint256 baseBalance, , ) = getBalances();
        if (totalSupply == 0) {
            amountQuote = amountQuoteDesired;
            amountBase = amountBaseDesired;
            shares = _sqrt(amountQuote * amountBase);
        } else {
            uint256 amountBaseOptimal = (amountQuoteDesired * baseBalance) / quoteBalance;
            if (amountBaseOptimal <= amountBaseDesired) {
                amountQuote = amountQuoteDesired;
                amountBase = amountBaseOptimal;
            } else {
                uint256 amountQuoteOptimal = (amountBaseDesired * quoteBalance) / baseBalance;
                require(amountQuoteOptimal <= amountQuoteDesired);
                amountQuote = amountQuoteOptimal;
                amountBase = amountBaseDesired;
            }
            shares = _min((amountQuote * totalSupply) / quoteBalance, (amountBase * totalSupply) / baseBalance);
        }
    }

    function previewWithdrawal(uint256 shares) external view returns (uint256 amountQuote, uint256 amountBase) {
        (uint256 quoteBalance, uint256 baseBalance, , ) = getBalances();
        amountQuote = (quoteBalance * shares) / totalSupply;
        amountBase = (baseBalance * shares) / totalSupply;
    }

    function deposit(address user, uint256 amountQuoteDesired, uint256 amountBaseDesired, uint256 amountQuoteMin, uint256 amountBaseMin) external returns (uint256 shares, uint256 amountQuote, uint256 amountBase) {
        require(factory == msg.sender && !locked && amountQuoteDesired != 0 && amountBaseDesired != 0);
        (uint256 quoteBalance, uint256 baseBalance, , ) = getBalances();

        if (totalSupply == 0) {
            amountQuote = amountQuoteDesired;
            amountBase = amountBaseDesired;
            shares = _sqrt(amountQuote * amountBase);
        } else {
            uint256 amountBaseOptimal = (amountQuoteDesired * baseBalance) / quoteBalance;
            if (amountBaseOptimal <= amountBaseDesired) {
                amountQuote = amountQuoteDesired;
                amountBase = amountBaseOptimal;
            } else {
                uint256 amountQuoteOptimal = (amountBaseDesired * quoteBalance) / baseBalance;
                require(amountQuoteOptimal <= amountQuoteDesired);
                amountQuote = amountQuoteOptimal;
                amountBase = amountBaseDesired;
            }
            shares = _min((amountQuote * totalSupply) / quoteBalance, (amountBase * totalSupply) / baseBalance);
        }

        require(amountQuote >= amountQuoteMin && amountBase >= amountBaseMin && shares != 0 && (maxShares == 0 || totalSupply + shares <= maxShares));

        IERC20(quoteAsset).transferFrom(msg.sender, address(this), amountQuote);
        IERC20(baseAsset).transferFrom(msg.sender, address(this), amountBase);
        ICrystal(crystal).deposit(quoteAsset, amountQuote);
        ICrystal(crystal).deposit(baseAsset, amountBase);

        _mint(user, shares);
        lastDepositTimestamp[user] = block.timestamp;
        require(balanceOf[owner] * 20 > totalSupply);
    }

    function withdraw(address user, uint256 shares, uint256 amountQuoteMin, uint256 amountBaseMin) external returns (uint256 amountQuote, uint256 amountBase) {
        require(factory == msg.sender && shares != 0 && shares <= balanceOf[user] && lastDepositTimestamp[user] + lockup <= block.timestamp);
        (uint256 quoteBalance, uint256 baseBalance, uint256 availableQuote, uint256 availableBase) = getBalances();
        amountQuote = (quoteBalance * shares) / totalSupply;
        amountBase = (baseBalance * shares) / totalSupply;
        require(amountQuote >= amountQuoteMin && amountBase >= amountBaseMin);
        _burn(user, shares);
        if (user == owner && !closed) {
            if (balanceOf[owner] == 0) {
                cancelAll();
                (quoteBalance, baseBalance, availableQuote, availableBase) = getBalances();
                closed = true;
                if (!locked) {
                    locked = true;
                }
            }
            else {
                require(balanceOf[owner] * 20 > totalSupply);
            }
        }
        if (decrease) {
            (uint256[] memory cloids, ICrystal.Order[] memory orders) = ICrystal(crystal).getAllOrdersByCloid(address(this), orderCap);
            bytes32[] memory data = new bytes32[](cloids.length + 1);
            data[0] = bytes32(1 << 252 | cloids.length << 160 | uint160(market));
            ICrystal.Order memory order;
            uint256 cloid;
            for (uint256 i; i < cloids.length; ++i) {
                order = orders[i];
                cloid = cloids[i];
                if (order.isBuy) {
                    if (((quoteBalance - availableQuote) * amountQuote / quoteBalance) >= (amountQuote > availableQuote ? (amountQuote - availableQuote) : 0)) { // decrease proportionally
                        data[i + 1] = bytes32((12 << 252) |
                        ((cloid & 0x3FF) << 192) |
                        ((order.size * amountQuote + quoteBalance - 1) / quoteBalance) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF);    
                    }
                    else { // decrease to make enough available
                        data[i + 1] = bytes32((12 << 252) |
                        ((cloid & 0x3FF) << 192) |
                        ((order.size * (amountQuote > availableQuote ? (amountQuote - availableQuote) : 0) + (quoteBalance - availableQuote) - 1) / (quoteBalance - availableQuote)) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
                    }
                }
                else {
                    if (((baseBalance - availableBase) * amountBase / baseBalance) >= (amountBase > availableBase ? (amountBase - availableBase) : 0)) { // decrease proportionally
                        data[i + 1] = bytes32((12 << 252) |
                        ((cloid & 0x3FF) << 192) |
                        ((order.size * amountBase + baseBalance - 1) / baseBalance) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF);    
                    }
                    else { // decrease to make enough available
                        data[i + 1] = bytes32((12 << 252) |
                        ((cloid & 0x3FF) << 192) |
                        ((order.size * (amountBase > availableBase ? (amountBase - availableBase) : 0) + (baseBalance - availableBase) - 1) / (baseBalance - availableBase)) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
                    }
                }
            }
            (bool success, bytes memory returnData) = crystal.call(abi.encodePacked(data));
            if (!success) {
                assembly {
                    revert(add(returnData, 32), mload(returnData))
                }
            }
        }
        else if (amountQuote > availableQuote || amountBase > availableBase) {
            (uint256[] memory cloids, ICrystal.Order[] memory orders) = ICrystal(crystal).getAllOrdersByCloid(address(this), orderCap);
            bytes32[] memory data = new bytes32[](cloids.length + 1);
            ICrystal.Order memory order;
            uint256 cloid;
            uint256 excessQuote = amountQuote > availableQuote ? (amountQuote - availableQuote) : 0;
            uint256 excessBase = amountBase > availableBase ? (amountBase - availableBase) : 0;
            uint256 lockedQuote = quoteBalance - availableQuote;
            uint256 lockedBase = baseBalance - availableBase;
            uint256 idx;
            for (uint256 i; i < cloids.length; ++i) {
                order = orders[i];
                cloid = cloids[i];
                if (order.isBuy && excessQuote != 0) {
                    data[++idx] = bytes32((12 << 252) |
                    ((cloid & 0x3FF) << 192) |
                    ((order.size * excessQuote + lockedQuote - 1) / lockedQuote) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
                }
                else if (!order.isBuy && excessBase != 0) {
                    data[++idx] = bytes32((12 << 252) |
                    ((cloid & 0x3FF) << 192) |
                    ((order.size * excessBase + lockedBase - 1) / lockedBase) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
                }
            }
            data[0] = bytes32(1 << 252 | idx << 160 | uint160(market));
            idx += 1;
            assembly { mstore(data, idx) }
            (bool success, bytes memory returnData) = crystal.call(abi.encodePacked(data));
            if (!success) {
                assembly {
                    revert(add(returnData, 32), mload(returnData))
                }
            }
        }
        if (amountQuote > 0) {
            ICrystal(crystal).withdraw(msg.sender, quoteAsset, amountQuote);
        }
        if (amountBase > 0) {
            ICrystal(crystal).withdraw(msg.sender, baseAsset, amountBase);
        }
    }

    function cancelAll() public {
        require(msg.sender == owner || msg.sender == factory);
        (uint256[] memory cloids, ) = ICrystal(crystal).getAllOrdersByCloid(address(this), orderCap);
        bytes32[] memory data = new bytes32[](cloids.length + 1);
        uint256 cloid;
        data[0] = bytes32(1 << 252 | cloids.length << 160 | uint160(market));
        for (uint256 i; i < cloids.length; ++i) {
            cloid = cloids[i];
            uint256 word = (1 << 252) | ((cloid & 0x3FF) << 192);
            data[i + 1] = bytes32(word);
        }
        (bool success, bytes memory returnData) = crystal.call(abi.encodePacked(data));
        if (!success) {
            assembly {
                revert(add(returnData, 32), mload(returnData))
            }
        }
    }

    function sweep() external {
        require(msg.sender == owner);
        msg.sender.call{value: address(this).balance}('');
    }

    function execute(ICrystalVault.Action[] calldata actions, uint256 bid) external payable {
        require(msg.sender == owner && actions.length < 0xFFF && !closed && bid < 0xFFFFFFFFFFFFFFFFFFFF);
        bytes32[] memory data = new bytes32[](actions.length + 1);
        ICrystalVault.Action memory action;
        data[0] = bytes32(1 << 252 | bid << 172 | actions.length << 160 | uint160(market));
        for (uint256 i; i < actions.length; ++i) {
            action = actions[i];
            if (
                action.action == 2 ||
                action.action == 3 ||
                action.action == 4 ||
                action.action == 5
            ) {
                require(action.cloid != 0 && action.cloid < orderCap);
            }
            data[i+1] = bytes32((action.action << 252) |
                (action.requireSuccess ? (1 << 248) : 0) |
                ((action.cloid & 0x3FF) << 192) |
                ((action.param1 & 0xFFFFFFFFFFFFFFFFFFFF) << 112) |
                action.param2 & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
        }
        (bool success, bytes memory returnData) = crystal.call{value: bid}(abi.encodePacked(data));
        if (!success) {
            assembly {
                revert(add(returnData, 32), mload(returnData))
            }
        }
    }

    receive() external payable {}
}