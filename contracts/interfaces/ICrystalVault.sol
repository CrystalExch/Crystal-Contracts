// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ICrystalVault {
    struct Action {
        bool requireSuccess;
        uint256 action;
        uint256 param1;
        uint256 param2;
        uint256 cloid;
    }

    struct VaultMetaData {
        string name;
        string description;
        string social1;
        string social2;
        string social3;
    }

    function balanceOf(address owner) external view returns (uint);

    function crystal() external view returns (address);

    function quoteAsset() external view returns (address);

    function baseAsset() external view returns (address);

    function owner() external view returns (address);

    function factory() external view returns (address);

    function totalSupply() external view returns (uint256);

    function maxShares() external view returns (uint256);

    function lastDepositTimestamp(address user) external view returns (uint256);

    function description() external view returns (string memory);

    function market() external view returns (address);

    function orderCap() external view returns (uint16);

    function lockup() external view returns (uint40);

    function locked() external view returns (bool);

    function closed() external view returns (bool);

    function getBalances() external view returns (uint256 quoteBalance, uint256 baseBalance, uint256 availableBalanceQuote, uint256 availableBalanceBase);

    function lock() external;

    function unlock() external;

    function changeMaxShares(uint256 _maxShares) external;

    function changeMarket() external;

    function changeOrderCap(uint16 newCap) external;

    function changeDecreaseOnWithdraw(bool newDecrease) external;

    function changeLockup(uint40 newLockup) external;

    function claimFees() external;

    function clearCloidSlots(uint256 userId, uint256[] calldata ids) external;

    function previewDeposit(uint256 amountQuoteDesired, uint256 amountBaseDesired) external view returns (uint256 shares, uint256 amountQuote, uint256 amountBase);

    function previewWithdrawal(uint256 shares) external view returns (uint256 amountQuote, uint256 amountBase);

    function deposit(address user, uint256 amountQuoteDesired, uint256 amountBaseDesired, uint256 amountQuoteMin, uint256 amountBaseMin) external returns (uint256 shares, uint256 amountQuote, uint256 amountBase);

    function withdraw(address user, uint256 shares, uint256 amountQuoteMin, uint256 amountBaseMin) external returns (uint256 amountQuote, uint256 amountBase);

    function execute(Action[] calldata actions) external returns (bytes memory);
}
