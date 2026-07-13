// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ICrystalVault} from "../interfaces/ICrystalVault.sol";

interface ICrystalVaultFactory {
    struct Vault {
        address quoteAsset;
        address baseAsset;
        address owner;
        uint256 totalShares;
        uint256 maxShares;
        uint40 lockup;
        bool decreaseOnWithdraw;
        bool locked;
        bool closed;
        ICrystalVault.VaultMetaData metadata;
    }

    event VaultDeployed(address indexed vault, address quoteAsset, address baseAsset, address owner, uint256 maxShares, uint256 lockup, bool decreaseOnWithdraw, ICrystalVault.VaultMetaData metadata);
    event Deposit(address indexed vault, address indexed sender, uint256 shares, uint256 quoteAmount, uint256 baseAmount);
    event Withdraw(address indexed vault, address indexed sender, uint256 shares, uint256 quoteAmount, uint256 baseAmount);
    event MaxSharesChanged(address indexed vault, uint256 maxShares);
    event LockupChanged(address indexed vault, uint256 lockup);
    event DecreaseOnWithdrawChanged(address indexed vault, bool newDecrease);
    event Locked(address indexed vault);
    event Unlocked(address indexed vault);
    event Closed(address indexed vault);

    error SizeBelowMin();

    function weth() external view returns (address);

    function eth() external view returns (address);

    function gov() external view returns (address);

    function crystal() external view returns (address);

    function allVaults(uint256) external view returns (address);

    function allVaultsLength() external view returns (uint256);

    function getVault(address vault) external view returns (address quoteAsset, address baseAsset, address owner, uint256 totalShares, uint256 maxShares, uint40 lockup, bool decreaseOnWithdraw, bool locked, bool closed, ICrystalVault.VaultMetaData memory metadata);

    function minDeposit(address token) external view returns (uint256);

    function globalMinDeposit() external view returns (uint256);

    function maxOrderCap() external view returns (uint16);

    function maxLockup() external view returns (uint40);

    function changeGov(address newGov) external;

    function changeMaxOrderCap(uint16 newCap) external;

    function changeMaxLockup(uint40 newLockup) external;

    function changeGlobalMinDeposit(uint256 newGlobalMinDeposit) external;

    function changeMinDeposit(address token, uint256 newMinSize) external;

    function deploy(
        address quoteAsset,
        address baseAsset,
        uint256 amountQuote,
        uint256 amountBase,
        uint256 maxShares,
        uint40 lockup,
        bool decreaseOnWithdraw,
        ICrystalVault.VaultMetaData memory metadata
    ) external payable returns (address vault);

    function previewDeposit(address vault, uint256 amountQuoteDesired, uint256 amountBaseDesired) external view returns (uint256 shares, uint256 amountQuote, uint256 amountBase);

    function previewWithdrawal(address vault, uint256 shares) external view returns (uint256 amountQuote, uint256 amountBase);

    function balanceOf(address vault, address user) external view returns (uint256 shares, uint256 amountQuote, uint256 amountBase);

    function deposit(
        address vault,
        address quoteAsset,
        address baseAsset,
        uint256 amountQuoteDesired,
        uint256 amountBaseDesired,
        uint256 amountQuoteMin,
        uint256 amountBaseMin
    ) external payable returns (uint256 shares, uint256 amountQuote, uint256 amountBase);

    function withdraw(
        address vault,
        address quoteAsset,
        address baseAsset,
        uint256 shares,
        uint256 amountQuoteMin,
        uint256 amountBaseMin
    ) external returns (uint256 amountQuote, uint256 amountBase);

    function lock(address vault) external;

    function unlock(address vault) external;

    function close(address vault) external returns (uint256 amountQuote, uint256 amountBase);

    function changeMaxShares(address vault, uint256 newMaxShares) external;

    function changeLockup(address vault, uint40 newLockup) external;

    function changeOrderCap(address vault, uint16 newCap) external;

    function changeDecreaseOnWithdraw(address vault, bool newDecrease) external;

    function changeMarket(address vault) external;

    function claimFees(address vault, address[] calldata tokens) external;

    function clearCloidSlots(address vault, uint256 userId, uint256[] calldata ids) external;
}
