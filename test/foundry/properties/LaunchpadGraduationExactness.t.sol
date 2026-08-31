// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Vm } from "forge-std/Vm.sol";
import { CrystalToken } from "../../../contracts/core/CrystalToken.sol";
import { BaseTest } from "../BaseTest.t.sol";

contract LaunchpadGraduationExactness is BaseTest {
    uint256 internal constant SOLD_TARGET = 800000000000000000000000000;
    bytes32 internal constant LAUNCHPAD_TRADE_SIG =
        keccak256("LaunchpadTrade(address,address,bool,uint256,uint256,uint256,uint256)");

    function _create() internal returns (address token) {
        vm.prank(alice);
        token = crystal.createToken("Exact", "EXCT", "", "", "", "", "", "");
    }

    uint256 internal constant INITIAL_CURVE = 1066666666666666666666666667;
    uint256 internal constant GRADUATED_CURVE = 266666666666666666666666667;

    function _netCurveSold(address token) internal returns (uint256 net) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 lastTokenReserve = INITIAL_CURVE;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length < 3 || logs[i].topics[0] != LAUNCHPAD_TRADE_SIG) continue;
            if (address(uint160(uint256(logs[i].topics[1]))) != token) continue;
            (,,,, uint256 tokenReserve) = abi.decode(logs[i].data, (bool, uint256, uint256, uint256, uint256));
            lastTokenReserve = tokenReserve;
        }
        return INITIAL_CURVE - lastTokenReserve;
    }

    function testFuzz_graduationSellsExactlyTarget(uint256[6] memory seeds, uint256 sellSeed) public {
        address token = _create();
        vm.deal(bob, 200_000 ether);
        vm.recordLogs();

        for (uint256 i = 0; i < seeds.length; i++) {
            uint256 amt = 0.01 ether + (seeds[i] % 900 ether);
            vm.prank(bob);
            try crystal.buy{ value: amt }(true, token, amt, 0) {} catch {}
            (, uint112 tR,,,) = crystal.launchpadTokenToMarket(token);
            if (tR == 0) break;
            if (i == 3) {
                uint256 held = CrystalToken(token).balanceOf(bob);
                if (held > 1) {
                    uint256 sellAmt = 1 + (sellSeed % (held / 2 + 1));
                    vm.startPrank(bob);
                    CrystalToken(token).approve(address(crystal), sellAmt);
                    try crystal.sell(true, token, sellAmt, 0) {} catch {}
                    vm.stopPrank();
                }
            }
        }

        (, uint112 tRw,,,) = crystal.launchpadTokenToMarket(token);
        if (tRw != 0) {
            vm.prank(bob);
            crystal.buy{ value: 60_000 ether }(true, token, 60_000 ether, 0);
        }

        (, uint112 tRend,,,) = crystal.launchpadTokenToMarket(token);
        assertEq(tRend, 0, "must graduate");
        assertEq(_netCurveSold(token), SOLD_TARGET, "curve must sell exactly 800m");

        address market = crystal.getMarketByTokens(address(weth), token);
        (, uint112 reserveBase) = crystal.getReserves(market);
        assertEq(
            CrystalToken(token).balanceOf(address(crystal)),
            uint256(reserveBase),
            "custody must exactly back the amm reserve"
        );
    }

    function testFuzz_exactOutputFinisherIsExact(uint256 preSeed, uint256 requestSeed) public {
        address token = _create();
        vm.deal(bob, 200_000 ether);
        vm.recordLogs();

        uint256 pre = 0.5 ether + (preSeed % 1_500 ether);
        vm.prank(bob);
        crystal.buy{ value: pre }(true, token, pre, 0);

        (, uint112 tR,,,) = crystal.launchpadTokenToMarket(token);
        if (tR == 0) return;

        uint256 room = uint256(tR) - 266666666666666666666666667;
        uint256 request = 1 + (requestSeed % (room + 60_000_000 ether));
        vm.prank(bob);
        try crystal.buy{ value: 60_000 ether }(false, token, 60_000 ether, request) {} catch {}

        (, uint112 tRmid,,,) = crystal.launchpadTokenToMarket(token);
        if (tRmid != 0) {
            vm.prank(bob);
            crystal.buy{ value: 60_000 ether }(true, token, 60_000 ether, 0);
        }

        assertEq(_netCurveSold(token), SOLD_TARGET, "curve must sell exactly 800m");
    }
}
