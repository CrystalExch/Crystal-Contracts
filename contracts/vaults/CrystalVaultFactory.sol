// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;
import "hardhat/console.sol";

import {IERC20} from '../interfaces/IERC20.sol';
import {IWETH} from '../interfaces/IWETH.sol';
import {ICrystalVault} from '../interfaces/ICrystalVault.sol';
import {CrystalVault} from './CrystalVault.sol';

contract CrystalVaultFactory {
    struct Vault {
        address vault;
        address quoteAsset;
        address baseAsset;
        address owner;
        uint256 totalShares;
        uint256 maxShares;
        uint40 lockup;
        bool locked;
        bool closed;
        VaultMetaData metadata;
    }

    struct VaultMetaData {
        string name;
        string description;
        string social1;
        string social2;
        string social3;  
    }

    address public immutable weth; 
    address public immutable eth = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public gov;
    address public crystal;
    address[] public allVaults;
    mapping (address => Vault) public getVault;
    mapping (address => uint256) public minSize;
    uint256 public defaultQuoteMin; // min deposit, is already divided by deciamls
    uint256 public defaultBaseMin; // anti rounding error, raw value
    uint16 public maxOrderCap;
    uint40 public maxLockup;

    event VaultDeployed(address indexed vault, address quoteAsset, address baseAsset, address owner, string name, string desc, string social1, string social2, string social3);
    event Deposit(address indexed vault, address indexed sender, uint256 shares, uint256 quoteAmount, uint256 baseAmount);
    event Withdraw(address indexed vault, address indexed sender, uint256 shares, uint256 quoteAmount, uint256 baseAmount);
    event MaxSharesChanged(address indexed vault, uint256 maxShares);
    event LockupChanged(address indexed vault, uint256 lockup);
    event Locked(address indexed vault);
    event Unlocked(address indexed vault);
    event Closed(address indexed vault);

    constructor(address _crystal, address _gov, address _weth, uint256 _defaultQuoteMin, uint256 _defaultBaseMin, uint256 _maxOrderCap, uint256 _lockup) {
        crystal = _crystal;
        gov = _gov;
        weth = _weth;
        defaultQuoteMin = _defaultQuoteMin;
        defaultBaseMin = _defaultBaseMin;
        maxOrderCap = uint16(_maxOrderCap);
        maxLockup = uint40(_lockup);
    }

    function _createVault(
        address quoteAsset,
        address baseAsset,
        string memory name,
        string memory symbol,
        string memory description,
        string memory social1,
        string memory social2,
        string memory social3
    ) private returns (address vault) {
        require(quoteAsset != address(0));
        vault = address(new CrystalVault(
            crystal,
            quoteAsset,
            baseAsset,
            msg.sender,
            name,
            symbol,
            description,
            social1,
            social2,
            social3
        ));
        IERC20(quoteAsset).approve(vault, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        IERC20(baseAsset).approve(vault, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        getVault[vault] = Vault(vault, quoteAsset, baseAsset, msg.sender, 0, 0, maxLockup, false, false, VaultMetaData(name, description, social1, social2, social3));
        allVaults.push(vault);
        emit VaultDeployed(vault, quoteAsset, baseAsset, msg.sender, name, description, social1, social2, social3);
    }

    function changeGov(address newGov) external {
        require(msg.sender == gov);
        gov = newGov;
    }

    function changeMaxOrderCap(uint256 newCap) external {
        require(msg.sender == gov);
        maxOrderCap = uint16(newCap);
    }

    function changeMaxLockup(uint256 newLockup) external {
        require(msg.sender == gov);
        maxLockup = uint40(newLockup);
    }

    function changeTokenMinSize(address token, uint256 newMinSize) external {
        require(msg.sender == gov);
        minSize[token] = newMinSize;
    }

    function deploy(address quoteAsset, address baseAsset, uint256 amountQuote, uint256 amountBase, string memory name, string memory description, string memory social1, string memory social2, string memory social3) external payable returns (address vault) {
        if (minSize[quoteAsset == eth ? weth : quoteAsset] != 0) { // make sure first deposit isn't dust
            require(amountQuote > minSize[quoteAsset == eth ? weth : quoteAsset]);
        } else {
            require(amountQuote > defaultQuoteMin * 10 ** IERC20(quoteAsset == eth ? weth : quoteAsset).decimals());
        }

        if (minSize[baseAsset] != 0) {
            require(amountBase > minSize[baseAsset]);
        } else {
            require(amountBase > defaultBaseMin);
        }
        string memory symbol = string.concat("CLV-", IERC20(baseAsset).symbol(), IERC20(quoteAsset == eth ? weth : quoteAsset).symbol());

        vault = _createVault(quoteAsset == eth ? weth : quoteAsset, baseAsset == eth ? weth : baseAsset, name, symbol, description, social1, social2, social3);

        deposit(vault, quoteAsset, baseAsset, amountQuote, amountBase, 0, 0);
    }

    function allVaultsLength() external view returns (uint256) {
        return allVaults.length;
    }

    function previewDeposit(address vault, uint256 amountQuoteDesired, uint256 amountBaseDesired) external view returns (uint256 shares, uint256 amountQuote, uint256 amountBase) {
        return ICrystalVault(vault).previewDeposit(amountQuoteDesired, amountBaseDesired);
    }

    function previewWithdrawal(address vault, uint256 shares) external view returns (uint256 amountQuote, uint256 amountBase) {
        return ICrystalVault(vault).previewWithdrawal(shares);
    }

    function balanceOf(address vault, address user) external view returns (uint256 shares, uint256 amountQuote, uint256 amountBase) {
        shares = ICrystalVault(vault).balanceOf(user);
        (amountQuote, amountBase) = ICrystalVault(vault).previewWithdrawal(shares);
    }

    function deposit(address vault, address quoteAsset, address baseAsset, uint256 amountQuoteDesired, uint256 amountBaseDesired, uint256 amountQuoteMin, uint256 amountBaseMin) public payable returns (uint256 shares, uint256 amountQuote, uint256 amountBase) {
        assembly {
            if tload(0x0) { revert(0, 0) }
            tstore(0x0, 1)
        }
        require(getVault[vault].quoteAsset == (quoteAsset == eth ? weth : quoteAsset) && getVault[vault].baseAsset == (baseAsset == eth ? weth : baseAsset));
        if (quoteAsset == eth) {
            IWETH(weth).deposit{value: msg.value}();
        } else {
            IERC20(quoteAsset).transferFrom(msg.sender, address(this), amountQuoteDesired);
        }
        if (baseAsset == eth) {
            IWETH(weth).deposit{value: msg.value}();
        } else {
            IERC20(baseAsset).transferFrom(msg.sender, address(this), amountBaseDesired);
        }
        (shares, amountQuote, amountBase) = ICrystalVault(vault).deposit(msg.sender, amountQuoteDesired, amountBaseDesired, amountQuoteMin, amountBaseMin);
        if (quoteAsset == eth) {
            IWETH(weth).withdraw(msg.value-amountQuote);
            (bool success, ) = msg.sender.call{value : msg.value-amountQuote}("");
            require(success);
        } else {
            IERC20(quoteAsset).transfer(msg.sender, amountQuoteDesired - amountQuote);
        }
        if (baseAsset == eth) {
            IWETH(weth).withdraw(msg.value-amountBase);
            (bool success, ) = msg.sender.call{value : msg.value-amountBase}("");
            require(success);
        } else {
            IERC20(baseAsset).transfer(msg.sender, amountBaseDesired - amountBase);
        }
        getVault[vault].totalShares += shares;
        emit Deposit(vault, msg.sender, shares, amountQuote, amountBase);
        assembly {
            tstore(0x0, 0)
        }
    }

    function withdraw(address vault, address quoteAsset, address baseAsset, uint256 shares, uint256 amountQuoteMin, uint256 amountBaseMin) external returns (uint256 amountQuote, uint256 amountBase) {
        assembly {
            if tload(0x0) { revert(0, 0) }
            tstore(0x0, 1)
        }
        require(getVault[vault].quoteAsset == (quoteAsset == eth ? weth : quoteAsset) && getVault[vault].baseAsset == (baseAsset == eth ? weth : baseAsset));
        (amountQuote, amountBase) = ICrystalVault(vault).withdraw(msg.sender, shares, amountQuoteMin, amountBaseMin);
        if (quoteAsset == eth) {
            IWETH(weth).withdraw(amountQuote);
            (bool success, ) = msg.sender.call{value : amountQuote}("");
            require(success);
        } else {
            IERC20(quoteAsset).transfer(msg.sender, amountQuote);
        }
        if (baseAsset == eth) {
            IWETH(weth).withdraw(amountBase);
            (bool success, ) = msg.sender.call{value : amountBase}("");
            require(success);
        } else {
            IERC20(baseAsset).transfer(msg.sender, amountBase);
        }
        uint256 totalShares = ICrystalVault(vault).totalSupply();
        if (totalShares == 0 && !getVault[vault].closed) { // has to be owner full withdraw causing vault to close
            if (!getVault[vault].locked) {
                getVault[vault].locked = true;
                emit Locked(vault);
            }
            getVault[vault].closed = true;
            emit Closed(vault);
        }
        getVault[vault].totalShares = totalShares;
        emit Withdraw(vault, msg.sender, shares, amountQuote, amountBase);
        assembly {
            tstore(0x0, 0)
        }
    }

    function lock(address vault) external {
        require(msg.sender == ICrystalVault(vault).owner());
        ICrystalVault(vault).lock();
        getVault[vault].locked = true;
        emit Locked(vault);
    }

    function unlock(address vault) external {
        require(msg.sender == ICrystalVault(vault).owner());
        ICrystalVault(vault).unlock();
        getVault[vault].locked = false;
        emit Unlocked(vault);
    }

    function close(address vault) external returns (uint256 amountQuote, uint256 amountBase) {
        require(msg.sender == ICrystalVault(vault).owner());
        Vault memory vaultInfo = getVault[vault];
        uint256 shares = ICrystalVault(vault).balanceOf(msg.sender);
        (amountQuote, amountBase) = ICrystalVault(vault).withdraw(msg.sender, shares, 0, 0);
        IERC20(vaultInfo.quoteAsset).transfer(msg.sender, amountQuote);
        IERC20(vaultInfo.baseAsset).transfer(msg.sender, amountBase);
        uint256 totalShares = ICrystalVault(vault).totalSupply();
        if (totalShares == 0 && !getVault[vault].closed) { // has to be owner full withdraw causing vault to close
            if (!getVault[vault].locked) {
                getVault[vault].locked = true;
                emit Locked(vault);
            }
            getVault[vault].closed = true;
            emit Closed(vault);
        }
        getVault[vault].totalShares = totalShares;
        emit Withdraw(vault, msg.sender, shares, amountQuote, amountBase);
    }

    function changeMaxShares(address vault, uint256 newMaxShares) external {
        require(msg.sender == ICrystalVault(vault).owner());
        ICrystalVault(vault).changeMaxShares(newMaxShares);
        getVault[vault].maxShares = newMaxShares;
        emit MaxSharesChanged(vault, newMaxShares);
    }

    function changeLockup(address vault, uint40 newLockup) external {
        require(msg.sender == ICrystalVault(vault).owner());
        ICrystalVault(vault).changeLockup(newLockup);
        getVault[vault].lockup = newLockup;
        emit LockupChanged(vault, newLockup);
    }

    function changeOrderCap(address vault, uint16 newCap) external {
        require(msg.sender == ICrystalVault(vault).owner());
        ICrystalVault(vault).changeOrderCap(newCap);
    }

    function changeDecreaseOnWithdraw(address vault, bool newDecrease) external {
        require(msg.sender == ICrystalVault(vault).owner());
        ICrystalVault(vault).changeDecreaseOnWithdraw(newDecrease);
    }

    function changeMarket(address vault, address newMarket) external {
        require(msg.sender == ICrystalVault(vault).owner());
        ICrystalVault(vault).changeMarket(newMarket);
    }

    function claimFees(address vault) external {
        require(msg.sender == ICrystalVault(vault).owner());
        ICrystalVault(vault).claimFees();
    }

    function clearCloidSlots(address vault, uint256 userId, uint256[] calldata ids) external {
        require(msg.sender == ICrystalVault(vault).owner());
        ICrystalVault(vault).clearCloidSlots(userId, ids);
    }
}