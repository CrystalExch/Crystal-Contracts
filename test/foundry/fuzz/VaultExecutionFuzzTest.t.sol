// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ICrystal } from "../../../contracts/interfaces/ICrystal.sol";
import { ICrystalVault } from "../../../contracts/interfaces/ICrystalVault.sol";
import { CrystalVaultFactory } from "../../../contracts/vaults/CrystalVaultFactory.sol";
import { BaseFuzzTest } from "../BaseFuzzTest.t.sol";

contract VaultExecutionFuzzTest is BaseFuzzTest {
    uint16 private constant VAULT_ORDER_CAP = 100;

    CrystalVaultFactory private vaultFactory;

    function setUp() public override {
        super.setUp();

        vaultFactory =
            new CrystalVaultFactory(address(crystal), CRYSTAL_GOVERNANCE, address(weth), 0, VAULT_ORDER_CAP, 0);
    }

    function testFuzzOwnerExecutePlacesBuyLimitOrderThroughVault(
        uint256 amountQuoteSeed,
        uint256 amountBaseSeed,
        uint256 cloidSeed,
        uint256 quotePerBaseSeed,
        uint256 sizeSeed
    ) public {
        uint256 amountQuote = _boundVaultQuote(amountQuoteSeed);
        uint256 amountBase = _boundVaultBase(amountBaseSeed);
        ICrystalVault vault = _deployVault(alice, amountQuote, amountBase);
        uint256 cloid = _boundVaultCloid(cloidSeed);
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 size = bound(sizeSeed, MARKET_MIN_SIZE, amountQuote);
        (,, uint256 availableQuoteBefore,) = vault.getBalances();

        vm.prank(alice);
        vault.execute(_singleAction(BatchAction.BuyLimit, cloid, price, size), 0);

        uint256 vaultUserId = crystal.addressToUserId(address(vault));
        ICrystal.Order memory order = crystal.getOrderByCloid(vaultUserId, cloid);
        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);
        ICrystal.MarketInfo memory info = crystal.getMarket(address(market));
        (,, uint256 availableQuoteAfter,) = vault.getBalances();

        assertEq(order.isBuy, true, "assert order.isBuy == true");
        assertEq(order.market, address(market), "assert order.market == address(market)");
        assertEq(order.price, price, "assert order.price == price");
        assertEq(order.size, size, "assert order.size == size");
        assertEq(order.userId, vaultUserId, "assert order.userId == vaultUserId");
        assertEq(level.size, size, "assert level.size == size");
        assertEq(info.highestBid, price, "assert info.highestBid == price");
        assertEq(
            availableQuoteAfter,
            availableQuoteBefore - size,
            "assert availableQuoteAfter == availableQuoteBefore - size"
        );
    }

    function testFuzzOwnerExecutePlacesSellLimitOrderThroughVault(
        uint256 amountQuoteSeed,
        uint256 amountBaseSeed,
        uint256 cloidSeed,
        uint256 quotePerBaseSeed,
        uint256 sizeSeed
    ) public {
        uint256 price = _boundPrice(quotePerBaseSeed);
        uint256 minSize = _minBaseForQuote(MARKET_MIN_SIZE, price);
        uint256 amountQuote = _boundVaultQuote(amountQuoteSeed);
        uint256 amountBase = _boundVaultBaseForSell(amountBaseSeed, minSize);
        ICrystalVault vault = _deployVault(alice, amountQuote, amountBase);
        uint256 cloid = _boundVaultCloid(cloidSeed);
        uint256 size = bound(sizeSeed, _minBaseForQuote(MARKET_MIN_SIZE, price), amountBase);
        (,,, uint256 availableBaseBefore) = vault.getBalances();

        vm.prank(alice);
        vault.execute(_singleAction(BatchAction.SellLimit, cloid, price, size), 0);

        uint256 vaultUserId = crystal.addressToUserId(address(vault));
        ICrystal.Order memory order = crystal.getOrderByCloid(vaultUserId, cloid);
        ICrystal.PriceLevel memory level = crystal.getPriceLevel(address(market), price);
        ICrystal.MarketInfo memory info = crystal.getMarket(address(market));
        (,,, uint256 availableBaseAfter) = vault.getBalances();

        assertEq(order.isBuy, false, "assert order.isBuy == false");
        assertEq(order.market, address(market), "assert order.market == address(market)");
        assertEq(order.price, price, "assert order.price == price");
        assertEq(order.size, size, "assert order.size == size");
        assertEq(order.userId, vaultUserId, "assert order.userId == vaultUserId");
        assertEq(level.size, size, "assert level.size == size");
        assertEq(info.lowestAsk, price, "assert info.lowestAsk == price");
        assertEq(
            availableBaseAfter, availableBaseBefore - size, "assert availableBaseAfter == availableBaseBefore - size"
        );
    }

    function _deployVault(address owner, uint256 amountQuote, uint256 amountBase)
        private
        returns (ICrystalVault vault)
    {
        vm.startPrank(owner);
        quote.approve(address(vaultFactory), type(uint256).max);
        weth.approve(address(vaultFactory), type(uint256).max);
        vault = ICrystalVault(
            vaultFactory.deploy(address(quote), address(weth), amountQuote, amountBase, 0, 0, false, _metadata())
        );
        vm.stopPrank();

        assertEq(vault.owner(), owner, "assert vault.owner() == owner");
        assertEq(vault.market(), address(market), "assert vault.market() == address(market)");
    }

    function _singleAction(BatchAction action, uint256 cloid, uint256 price, uint256 size)
        private
        pure
        returns (ICrystalVault.Action[] memory actions)
    {
        actions = new ICrystalVault.Action[](1);
        actions[0] = ICrystalVault.Action({
            requireSuccess: true, action: uint256(action), param1: price, param2: size, cloid: cloid
        });
    }

    function _boundVaultQuote(uint256 amount) private pure returns (uint256) {
        return bound(amount, MARKET_MIN_SIZE, 100_000 * QUOTE_UNIT);
    }

    function _boundVaultBase(uint256 amount) private pure returns (uint256) {
        return bound(amount, MIN_ETH_FUZZ_AMOUNT, 1_000 ether);
    }

    function _boundVaultBaseForSell(uint256 amount, uint256 minSize) private pure returns (uint256) {
        return bound(amount, minSize, 1_000 ether);
    }

    function _boundVaultCloid(uint256 cloid) private pure returns (uint256) {
        return bound(cloid, 1, VAULT_ORDER_CAP - 1);
    }

    function _metadata() private pure returns (ICrystalVault.VaultMetaData memory) {
        return ICrystalVault.VaultMetaData({
            name: "Vault Execution", description: "", social1: "", social2: "", social3: ""
        });
    }
}
