// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ICrystalVault } from "../../../contracts/interfaces/ICrystalVault.sol";
import { VaultPropertyBase } from "./VaultPropertyBase.t.sol";

interface IERC20Surface {
    function approve(address spender, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

contract ERC20SurfaceProperties is VaultPropertyBase {
    function testFuzzCrystalMarketLpTransferFromAndAllowanceAccounting(uint256 quoteSeed, uint256 baseSeed) public {
        uint256 amountQuote = _boundLiquidityQuoteAmount(quoteSeed);
        uint256 amountBase = _boundLiquidityBaseForQuote(baseSeed, amountQuote);

        uint256 liquidity = crystal.addLiquidity(address(market), address(this), amountQuote, amountBase, 0, 0);
        uint256 transferAmount = bound(liquidity, 2, liquidity);
        uint256 finiteSpend = transferAmount / 2;

        market.transfer(alice, transferAmount);

        vm.prank(alice);
        market.approve(bob, transferAmount);
        vm.prank(bob);
        market.transferFrom(alice, carol, finiteSpend);

        assertEq(
            market.balanceOf(alice),
            transferAmount - finiteSpend,
            "assert market.balanceOf(alice) == transferAmount - finiteSpend"
        );
        assertEq(market.balanceOf(carol), finiteSpend, "assert market.balanceOf(carol) == finiteSpend");
        assertEq(
            market.allowance(alice, bob),
            transferAmount - finiteSpend,
            "assert market.allowance(alice, bob) == transferAmount - finiteSpend"
        );

        vm.prank(alice);
        market.approve(bob, type(uint256).max);
        vm.prank(bob);
        market.transferFrom(alice, carol, transferAmount - finiteSpend);

        assertEq(market.balanceOf(alice), 0, "assert market.balanceOf(alice) == 0");
        assertEq(market.balanceOf(carol), transferAmount, "assert market.balanceOf(carol) == transferAmount");
        assertEq(
            market.allowance(alice, bob), type(uint256).max, "assert market.allowance(alice, bob) == type(uint256).max"
        );
    }

    function testCrystalMarketMintAndBurnAreRestrictedToCrystal() public {
        uint256 totalSupplyBefore = market.totalSupply();

        vm.expectRevert();
        market.mint(alice, 1);
        vm.expectRevert();
        market.burn(alice, 1);

        vm.prank(address(crystal));
        market.mint(alice, 10);
        assertEq(market.balanceOf(alice), 10, "assert market.balanceOf(alice) == 10");
        assertEq(market.totalSupply(), totalSupplyBefore + 10, "assert market.totalSupply() == totalSupplyBefore + 10");

        vm.prank(address(crystal));
        market.burn(alice, 4);
        assertEq(market.balanceOf(alice), 6, "assert market.balanceOf(alice) == 6");
        assertEq(market.totalSupply(), totalSupplyBefore + 6, "assert market.totalSupply() == totalSupplyBefore + 6");
    }

    function testFuzzCrystalVaultSharesRemainNonTransferable(
        uint256 initialQuoteSeed,
        uint256 initialBaseSeed,
        uint256 quoteDesiredSeed,
        uint256 baseDesiredSeed
    ) public {
        uint256 initialQuote = _boundVaultQuote(initialQuoteSeed);
        uint256 initialBase = _boundVaultBase(initialBaseSeed);
        ICrystalVault vault = _deployVault(alice, initialQuote, initialBase, false, 0);
        address vaultAddress = address(vault);
        (uint256 bobShares,,) = _depositIntoVault(
            bob,
            vaultAddress,
            _boundFollowOnQuote(quoteDesiredSeed, initialQuote),
            _boundFollowOnBase(baseDesiredSeed, initialBase),
            0,
            0
        );
        IERC20Surface shareToken = IERC20Surface(vaultAddress);

        vm.prank(bob);
        shareToken.approve(alice, bobShares);
        vm.prank(bob);
        vm.expectRevert();
        shareToken.transfer(carol, bobShares);
        vm.prank(alice);
        vm.expectRevert();
        shareToken.transferFrom(bob, carol, bobShares);

        assertEq(shareToken.balanceOf(bob), bobShares, "assert shareToken.balanceOf(bob) == bobShares");
        assertEq(shareToken.balanceOf(carol), 0, "assert shareToken.balanceOf(carol) == 0");
        assertEq(shareToken.allowance(bob, alice), bobShares, "assert shareToken.allowance(bob, alice) == bobShares");
    }
}
