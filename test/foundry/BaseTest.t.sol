// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { Deploy } from "./Deploy.t.sol";

abstract contract BaseTest is Test, Deploy {
    uint256 internal constant QUOTE_UNIT = 1e6;
    uint256 internal constant MINT_QUOTE_AMOUNT = 1_000_000_000 * QUOTE_UNIT;
    uint256 internal constant DEPOSIT_QUOTE_AMOUNT = 100_000 * QUOTE_UNIT;
    uint256 internal constant DEPOSIT_WETH_AMOUNT = 1_000e18;
    uint256 internal constant ORDER_TYPES_NORMAL = 0;

    enum BatchAction {
        None,
        CancelOrder,
        BuyLimit,
        SellLimit,
        MarketToLimitBuy,
        MarketToLimitSell,
        PartialBuy,
        PartialSell,
        GasAwarePartialBuy,
        GasAwarePartialSell,
        CompleteBuy,
        CompleteSell,
        DecreaseOrder
    }

    uint256 internal constant BATCH_BALANCE_MODE_EXTERNAL = 0;
    uint256 internal constant BATCH_BALANCE_MODE_INTERNAL = 1;
    uint256 internal constant BATCH_ACTION_SHIFT = 252;
    uint256 internal constant BATCH_REQUIRE_SUCCESS_SHIFT = 248;
    uint256 internal constant BATCH_CLOID_SHIFT = 192;
    uint256 internal constant BATCH_PARAM1_SHIFT = 112;
    uint256 internal constant BATCH_ACTION_COUNT_SHIFT = 160;
    uint256 internal constant BATCH_BALANCE_MODE_SHIFT = 252;
    uint256 internal constant BATCH_CLOID_MASK = (uint256(1) << 10) - 1;
    uint256 internal constant BATCH_PARAM1_MASK = type(uint80).max;
    uint256 internal constant BATCH_PARAM2_MASK = type(uint112).max;

    address internal constant alice = address(0x2000);
    address internal constant bob = address(0x3000);
    address internal constant carol = address(0x4000);

    receive() external payable { }

    function setUp() public virtual {

        deploy();
        
        _fundAndApprove(address(this));
        _fundAndApprove(alice);
        _fundAndApprove(bob);
        _fundAndApprove(carol);

        _registerAndDeposit(alice);
        _registerAndDeposit(bob);
    }

    function _fundAndApprove(address account) internal {
        quote.mint(account, MINT_QUOTE_AMOUNT);
        vm.deal(account, 10_000 ether);

        vm.startPrank(account);
        weth.deposit{ value: 5_000 ether }();
        quote.approve(address(crystal), type(uint256).max);
        weth.approve(address(crystal), type(uint256).max);
        vm.stopPrank();
    }

    function _registerAndDeposit(address account) internal {
        vm.startPrank(account);
        crystal.registerUser(account);
        crystal.deposit(address(quote), DEPOSIT_QUOTE_AMOUNT);
        crystal.deposit(address(weth), DEPOSIT_WETH_AMOUNT);
        vm.stopPrank();
    }

    function _price(uint256 quotePerBase) internal view returns (uint256) {
        uint256 scaleFactor = market.scaleFactor();
        uint256 quoteScale = 10 ** (18 - quote.decimals());
        return quotePerBase * (scaleFactor / quoteScale);
    }
}
