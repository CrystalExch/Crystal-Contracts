// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BaseFuzzTest } from "../BaseFuzzTest.t.sol";

contract RegisterUserFuzzTest is BaseFuzzTest {
    event UserRegistered(address indexed user, uint256 indexed userId);

    function testFuzzRegisterUserAssignsNextUserIdToCaller(uint256 userSeed) public {
        address user = _boundFreshUser(userSeed);
        vm.assume(crystal.addressToUserId(user) == 0);
        uint256 previousLatestUserId = crystal.latestUserId();

        vm.prank(user);
        uint256 userId = crystal.registerUser(user);

        assertEq(userId, previousLatestUserId + 1, "assert userId == previousLatestUserId + 1");
        assertEq(crystal.latestUserId(), userId, "assert crystal.latestUserId() == userId");
        assertEq(crystal.addressToUserId(user), userId, "assert crystal.addressToUserId(user) == userId");
        assertEq(crystal.userIdToAddress(userId), user, "assert crystal.userIdToAddress(userId) == user");
    }

    function testFuzzRegisterUserEmitsRegistrationEvent(uint256 userSeed) public {
        address user = _boundFreshUser(userSeed);
        vm.assume(crystal.addressToUserId(user) == 0);
        uint256 expectedUserId = crystal.latestUserId() + 1;

        vm.expectEmit(true, true, true, true, address(crystal));
        emit UserRegistered(user, expectedUserId);

        vm.prank(user);
        crystal.registerUser(user);
    }
}
