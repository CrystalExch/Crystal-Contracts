// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC20} from '../interfaces/IERC20.sol';

interface IVaultFactory {
    function deposit(address vault, address quoteAsset, address baseAsset, uint256 amountQuoteDesired, uint256 amountBaseDesired, uint256 amountQuoteMin, uint256 amountBaseMin) external payable returns (uint256 shares, uint256 amountQuote, uint256 amountBase);
    function withdraw(address vault, address quoteAsset, address baseAsset, uint256 shares, uint256 amountQuoteMin, uint256 amountBaseMin) external returns (uint256 amountQuote, uint256 amountBase);
}

/// @notice Contract that rejects ETH transfers - used for testing ETH transfer failure branches
contract ETHRejecter {
    function approveToken(address token, address spender, uint256 amount) external {
        IERC20(token).approve(spender, amount);
    }

    function depositToVault(
        address factory,
        address vault,
        address quoteAsset,
        address baseAsset,
        uint256 amountQuote,
        uint256 amountBase
    ) external payable {
        IVaultFactory(factory).deposit{value: msg.value}(
            vault, quoteAsset, baseAsset, amountQuote, amountBase, 0, 0
        );
    }

    function withdrawFromVault(
        address factory,
        address vault,
        address quoteAsset,
        address baseAsset,
        uint256 shares
    ) external {
        // Transfer shares to this contract first if needed
        IVaultFactory(factory).withdraw(vault, quoteAsset, baseAsset, shares, 0, 0);
    }

    // No receive() or fallback() - will reject ETH transfers
}

/// @notice Contract that can toggle ETH rejection - accepts ETH during deposit, rejects during withdraw
contract ETHToggler {
    bool public rejectETH;

    function setRejectETH(bool _reject) external {
        rejectETH = _reject;
    }

    function approveToken(address token, address spender, uint256 amount) external {
        IERC20(token).approve(spender, amount);
    }

    function depositToVault(
        address factory,
        address vault,
        address quoteAsset,
        address baseAsset,
        uint256 amountQuote,
        uint256 amountBase
    ) external payable {
        IVaultFactory(factory).deposit{value: msg.value}(
            vault, quoteAsset, baseAsset, amountQuote, amountBase, 0, 0
        );
    }

    function withdrawFromVault(
        address factory,
        address vault,
        address quoteAsset,
        address baseAsset,
        uint256 shares
    ) external {
        IVaultFactory(factory).withdraw(vault, quoteAsset, baseAsset, shares, 0, 0);
    }

    receive() external payable {
        require(!rejectETH, "ETH rejected");
    }
}

/// @notice Contract that attempts reentrancy attack on VaultFactory
contract ReentrancyAttacker {
    address public factory;
    address public vault;
    address public quoteAsset;
    address public baseAsset;
    bool public attackDeposit;
    bool public attacked;

    function setup(address _factory, address _vault, address _quoteAsset, address _baseAsset) external {
        factory = _factory;
        vault = _vault;
        quoteAsset = _quoteAsset;
        baseAsset = _baseAsset;
    }

    function setAttackDeposit(bool _attackDeposit) external {
        attackDeposit = _attackDeposit;
    }

    function approveToken(address token, address spender, uint256 amount) external {
        IERC20(token).approve(spender, amount);
    }

    function attackDepositReentrancy(uint256 amountQuote, uint256 amountBase) external payable {
        attackDeposit = true;
        attacked = false;
        IVaultFactory(factory).deposit{value: msg.value}(
            vault, quoteAsset, baseAsset, amountQuote, amountBase, 0, 0
        );
    }

    function attackWithdrawReentrancy(uint256 shares) external {
        attackDeposit = false;
        attacked = false;
        IVaultFactory(factory).withdraw(vault, quoteAsset, baseAsset, shares, 0, 0);
    }

    receive() external payable {
        if (!attacked) {
            attacked = true;
            if (attackDeposit) {
                // Try to reenter deposit during ETH refund callback
                try IVaultFactory(factory).deposit{value: 0}(
                    vault, quoteAsset, baseAsset, 1, 1, 0, 0
                ) {} catch {}
            } else {
                // Try to reenter withdraw during ETH transfer callback
                try IVaultFactory(factory).withdraw(
                    vault, quoteAsset, baseAsset, 1, 0, 0
                ) {} catch {}
            }
        }
    }
}
