// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {TestLog} from "../src/TestLog.sol";

contract TestLogTest is Test {
    TestLog public testlog;

    function setUp() public {
        testlog = new TestLog();
    }

    function test_calculateDebt() public view {
        uint256 newDebt = testlog.calculateDebt(89896e16, 1706745600, 1735689600);
        assertEq(newDebt, 997500388704920390522);
    }

    function test_calculateMaxBorrow() public view {
        uint256 maxBorrow = testlog.calculateMaxBorrow(9975e17, 1706745600, 1735689600);
        assertEq(maxBorrow, 898959649694196407801);
    }

    function testFuzz_MaxBorrow(uint64 x) public view {
        uint256 x256 = (uint256(x) + uint256(2)) * 1e18;
        uint256 maxBorrow = testlog.calculateMaxBorrow(x256, 1706745600, 1735689600);
        assertLe(maxBorrow, x256);
    }
}
