// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseTest } from "../BaseTest.t.sol";

contract RegisterUserTest is BaseTest {
    event UserRegistered(bool indexed isMargin, address indexed user, uint256 indexed userId);

    function testRegisterUserAssignsNextUserIdToCaller() public {
        uint256 previousLatestUserId = crystal.latestUserId();

        vm.prank(carol);
        uint256 userId = crystal.registerUser(carol);

        assertEq(userId, previousLatestUserId + 1, "assert userId == previousLatestUserId + 1");
        assertEq(crystal.latestUserId(), userId, "assert crystal.latestUserId() == userId");
        assertEq(crystal.addressToUserId(carol), userId, "assert crystal.addressToUserId(carol) == userId");
        assertEq(crystal.userIdToAddress(userId), carol, "assert crystal.userIdToAddress(userId) == carol");
    }

    function testRegisterUserEmitsRegistrationEvent() public {
        uint256 expectedUserId = crystal.latestUserId() + 1;

        vm.expectEmit(true, true, true, true, address(crystal));
        emit UserRegistered(false, carol, expectedUserId);

        vm.prank(carol);
        crystal.registerUser(carol);
    }
}
