// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC20} from '../interfaces/IERC20.sol';
import {IWETH} from '../interfaces/IWETH.sol';
import {ICrystalVault} from '../interfaces/ICrystalVault.sol';
import {CrystalVault} from './CrystalVault.sol';
import {ICrystalVaultFactory} from '../interfaces/ICrystalVaultFactory.sol';

contract CrystalVaultFactory {
    address public immutable weth; 
    address public immutable eth = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public gov;
    address public crystal;
    address[] public allVaults;
    mapping (address => ICrystalVaultFactory.Vault) public getVault;
    mapping (address => uint256) public minSize;
    uint256 public minDeposit; // min deposit
    uint16 public maxOrderCap;
    uint40 public maxLockup;

    constructor(address _crystal, address _gov, address _weth, uint256 _minDeposit, uint256 _maxOrderCap, uint256 _lockup) {
        crystal = _crystal;
        gov = _gov;
        weth = _weth;
        minDeposit = _minDeposit;
        maxOrderCap = uint16(_maxOrderCap);
        maxLockup = uint40(_lockup);
    }

    function _createVault(
        address quoteAsset,
        address baseAsset,
        uint256 maxShares,
        uint40 lockup,
        bool decreaseOnWithdraw,
        string memory symbol,
        ICrystalVault.VaultMetaData memory metadata
    ) private returns (address vault) {
        require(quoteAsset != address(0));
        vault = address(new CrystalVault(
            crystal,
            quoteAsset,
            baseAsset,
            msg.sender,
            symbol,
            metadata
        ));
        IERC20(quoteAsset).approve(vault, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        IERC20(baseAsset).approve(vault, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        if (lockup != 0) {
            ICrystalVault(vault).changeLockup(lockup);
            getVault[vault].lockup = lockup;
        }
        else {
            lockup = maxLockup;
        }
        if (maxShares != 0) {
            ICrystalVault(vault).changeMaxShares(maxShares);
        }
        if (decreaseOnWithdraw) {
            ICrystalVault(vault).changeDecreaseOnWithdraw(decreaseOnWithdraw);
        }
        getVault[vault] = ICrystalVaultFactory.Vault(quoteAsset, baseAsset, msg.sender, 0, maxShares, lockup, decreaseOnWithdraw, false, false, metadata);
        allVaults.push(vault);
        emit ICrystalVaultFactory.VaultDeployed(vault, quoteAsset, baseAsset, msg.sender, maxShares, lockup, decreaseOnWithdraw, metadata);
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

    function deploy(address quoteAsset, address baseAsset, uint256 amountQuote, uint256 amountBase, uint256 maxShares, uint256 lockup, bool decreaseOnWithdraw, ICrystalVault.VaultMetaData memory metadata) external payable returns (address vault) {
        if (minSize[quoteAsset == eth ? weth : quoteAsset] != 0) { // make sure first deposit isn't dust
            require(amountQuote > minSize[quoteAsset == eth ? weth : quoteAsset]);
        } else {
            require(amountQuote > minDeposit);
        }

        if (minSize[baseAsset == eth ? weth : baseAsset] != 0) {
            require(amountBase > minSize[baseAsset == eth ? weth : baseAsset]);
        } else {
            require(amountBase > minDeposit);
        }
        string memory symbol = string.concat("CLV-", IERC20(baseAsset == eth ? weth : baseAsset).symbol(), IERC20(quoteAsset == eth ? weth : quoteAsset).symbol());

        vault = _createVault(quoteAsset == eth ? weth : quoteAsset, baseAsset == eth ? weth : baseAsset, maxShares, uint40(lockup), decreaseOnWithdraw, symbol, metadata);

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
        emit ICrystalVaultFactory.Deposit(vault, msg.sender, shares, amountQuote, amountBase);
        assembly {
            tstore(0x0, 0)
        }
    }

    function withdraw(address vault, address quoteAsset, address baseAsset, uint256 shares, uint256 amountQuoteMin, uint256 amountBaseMin) external returns (uint256 amountQuote, uint256 amountBase) {
        assembly {
            if tload(0x0) { revert(0, 0) }
            tstore(0x0, 1)
        }
        ICrystalVaultFactory.Vault storage vaultInfo = getVault[vault];
        require(vaultInfo.quoteAsset == (quoteAsset == eth ? weth : quoteAsset) && vaultInfo.baseAsset == (baseAsset == eth ? weth : baseAsset));
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
        if (IERC20(vault).balanceOf(vaultInfo.owner) == 0 && !vaultInfo.closed) { // has to be owner full withdraw causing vault to close
            if (!vaultInfo.locked) {
                vaultInfo.locked = true;
                emit ICrystalVaultFactory.Locked(vault);
            }
            vaultInfo.closed = true;
            emit ICrystalVaultFactory.Closed(vault);
        }
        vaultInfo.totalShares = totalShares;
        emit ICrystalVaultFactory.Withdraw(vault, msg.sender, shares, amountQuote, amountBase);
        assembly {
            tstore(0x0, 0)
        }
    }

    function lock(address vault) external {
        require(msg.sender == ICrystalVault(vault).owner());
        ICrystalVault(vault).lock();
        getVault[vault].locked = true;
        emit ICrystalVaultFactory.Locked(vault);
    }

    function unlock(address vault) external {
        require(msg.sender == ICrystalVault(vault).owner());
        ICrystalVault(vault).unlock();
        getVault[vault].locked = false;
        emit ICrystalVaultFactory.Unlocked(vault);
    }

    function close(address vault) external returns (uint256 amountQuote, uint256 amountBase) {
        require(msg.sender == ICrystalVault(vault).owner());
        ICrystalVaultFactory.Vault storage vaultInfo = getVault[vault];
        uint256 shares = ICrystalVault(vault).balanceOf(msg.sender);
        (amountQuote, amountBase) = ICrystalVault(vault).withdraw(msg.sender, shares, 0, 0);
        IERC20(vaultInfo.quoteAsset).transfer(msg.sender, amountQuote);
        IERC20(vaultInfo.baseAsset).transfer(msg.sender, amountBase);
        uint256 totalShares = ICrystalVault(vault).totalSupply();
        if (totalShares == 0 && !vaultInfo.closed) { // has to be owner full withdraw causing vault to close
            if (!vaultInfo.locked) {
                vaultInfo.locked = true;
                emit ICrystalVaultFactory.Locked(vault);
            }
            vaultInfo.closed = true;
            emit ICrystalVaultFactory.Closed(vault);
        }
        vaultInfo.totalShares = totalShares;
        emit ICrystalVaultFactory.Withdraw(vault, msg.sender, shares, amountQuote, amountBase);
    }

    function changeMaxShares(address vault, uint256 newMaxShares) external {
        require(msg.sender == ICrystalVault(vault).owner());
        ICrystalVault(vault).changeMaxShares(newMaxShares);
        getVault[vault].maxShares = newMaxShares;
        emit ICrystalVaultFactory.MaxSharesChanged(vault, newMaxShares);
    }

    function changeLockup(address vault, uint40 newLockup) external {
        require(msg.sender == ICrystalVault(vault).owner());
        ICrystalVault(vault).changeLockup(newLockup);
        getVault[vault].lockup = newLockup;
        emit ICrystalVaultFactory.LockupChanged(vault, newLockup);
    }

    function changeOrderCap(address vault, uint16 newCap) external {
        require(msg.sender == ICrystalVault(vault).owner());
        ICrystalVault(vault).changeOrderCap(newCap);
    }

    function changeDecreaseOnWithdraw(address vault, bool newDecrease) external {
        require(msg.sender == ICrystalVault(vault).owner());
        ICrystalVault(vault).changeDecreaseOnWithdraw(newDecrease);
        emit ICrystalVaultFactory.DecreaseOnWithdrawChanged(vault, newDecrease);
    }

    function changeMarket(address vault) external {
        require(msg.sender == ICrystalVault(vault).owner());
        ICrystalVault(vault).changeMarket();
    }

    function claimFees(address vault) external {
        require(msg.sender == ICrystalVault(vault).owner());
        ICrystalVault(vault).claimFees();
    }

    function clearCloidSlots(address vault, uint256 userId, uint256[] calldata ids) external {
        require(msg.sender == ICrystalVault(vault).owner());
        ICrystalVault(vault).clearCloidSlots(userId, ids);
    }

    receive() external payable {}
}