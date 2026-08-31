// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { CrystalToken } from "../../../contracts/core/CrystalToken.sol";
import { BaseTest } from "../BaseTest.t.sol";

contract LaunchpadTest is BaseTest {
    function testCreateTokenInitializesLaunchpadMarket() public {
        vm.prank(alice);
        address token = crystal.createToken(
            "Launch Token",
            "LAUNCH",
            "ipfs://launch",
            "Focused launchpad token",
            "https://x.example/launch",
            "https://t.me/launch",
            "",
            ""
        );

        (
            uint112 virtualNativeReserve,
            uint112 virtualTokenReserve,
            uint256 k,
            address creator,
            address marketAddress
        ) = crystal.launchpadTokenToMarket(token);

        assertEq(crystal.allTokens(0), token, "assert crystal.allTokens(0) == token");
        assertEq(CrystalToken(token).name(), "Launch Token", "assert CrystalToken(token).name() == \"Launch Token\"");
        assertEq(CrystalToken(token).symbol(), "LAUNCH", "assert CrystalToken(token).symbol() == \"LAUNCH\"");
        assertEq(
            CrystalToken(token).balanceOf(address(crystal)),
            CrystalToken(token).totalSupply(),
            "assert CrystalToken(token).balanceOf(address(crystal)) == CrystalToken(token).totalSupply()"
        );
        assertEq(creator, alice, "assert creator == alice");
        assertTrue(marketAddress != address(0), "assert marketAddress != address(0)");
        assertEq(
            virtualNativeReserve,
            LAUNCHPAD_INITIAL_NATIVE_SUPPLY,
            "assert virtualNativeReserve == LAUNCHPAD_INITIAL_NATIVE_SUPPLY"
        );
        assertEq(
            k,
            uint256(virtualNativeReserve) * uint256(virtualTokenReserve),
            "assert k == uint256(virtualNativeReserve) * uint256(virtualTokenReserve)"
        );
    }

    function testBuyLaunchpadTokenUpdatesBuyerBalanceAndReserves() public {
        address token = _createLaunchpadToken();
        uint256 buyAmount = 1 ether;

        (uint256 quotedBuyIn, uint256 quotedBuyOut, bool quotedGraduated) = crystal.quoteBuy(true, token, buyAmount, 0);
        (uint256 nativeReserveBeforeBuy, uint256 tokenReserveBeforeBuy) = crystal.getVirtualReserves(token);

        vm.prank(bob);
        (uint256 buyInput, uint256 buyOutput, bool graduated) =
            crystal.buy{ value: buyAmount }(true, token, buyAmount, 0);

        (uint256 nativeReserveAfterBuy, uint256 tokenReserveAfterBuy) = crystal.getVirtualReserves(token);

        assertEq(buyInput, quotedBuyIn, "assert buyInput == quotedBuyIn");
        assertEq(buyOutput, quotedBuyOut, "assert buyOutput == quotedBuyOut");
        assertEq(graduated, quotedGraduated, "assert graduated == quotedGraduated");
        assertEq(
            CrystalToken(token).balanceOf(bob), buyOutput, "assert CrystalToken(token).balanceOf(bob) == buyOutput"
        );
        assertGt(nativeReserveAfterBuy, nativeReserveBeforeBuy, "assert nativeReserveAfterBuy > nativeReserveBeforeBuy");
        assertLt(tokenReserveAfterBuy, tokenReserveBeforeBuy, "assert tokenReserveAfterBuy < tokenReserveBeforeBuy");
    }

    function testSellLaunchpadTokenAfterBuyReturnsNativeAndUpdatesReserves() public {
        address token = _createLaunchpadToken();
        uint256 buyOutput = _buyTokenAsBob(token, 1 ether);

        uint256 sellAmount = buyOutput / 2;
        (uint256 quotedSellIn, uint256 quotedSellOut) = crystal.quoteSell(true, token, sellAmount, 0);
        uint256 bobEthBeforeSell = bob.balance;
        (uint256 nativeReserveBeforeSell, uint256 tokenReserveBeforeSell) = crystal.getVirtualReserves(token);

        vm.prank(bob);
        (uint256 sellInput, uint256 sellOutput) = crystal.sell(true, token, sellAmount, 0);

        (uint256 nativeReserveAfterSell, uint256 tokenReserveAfterSell) = crystal.getVirtualReserves(token);

        assertEq(sellInput, quotedSellIn, "assert sellInput == quotedSellIn");
        assertEq(sellOutput, quotedSellOut, "assert sellOutput == quotedSellOut");
        assertEq(
            CrystalToken(token).balanceOf(bob),
            buyOutput - sellAmount,
            "assert CrystalToken(token).balanceOf(bob) == buyOutput - sellAmount"
        );
        assertEq(bob.balance, bobEthBeforeSell + sellOutput, "assert bob.balance == bobEthBeforeSell + sellOutput");
        assertLt(
            nativeReserveAfterSell, nativeReserveBeforeSell, "assert nativeReserveAfterSell < nativeReserveBeforeSell"
        );
        assertGt(tokenReserveAfterSell, tokenReserveBeforeSell, "assert tokenReserveAfterSell > tokenReserveBeforeSell");
    }

    function _createLaunchpadToken() private returns (address token) {
        token = crystal.createToken(
            "Launch Token",
            "LAUNCH",
            "ipfs://launch",
            "Focused launchpad token",
            "https://x.example/launch",
            "https://t.me/launch",
            "",
            ""
        );
    }

    function _buyTokenAsBob(address token, uint256 buyAmount) private returns (uint256 buyOutput) {
        vm.prank(bob);
        (, buyOutput,) = crystal.buy{ value: buyAmount }(true, token, buyAmount, 0);
    }
}
