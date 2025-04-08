// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {TestLog} from "../src/TestLog.sol";

contract TestLogTest is Test {
    TestLog public testlog;
    uint256 internal constant YEAR_IN_SECONDS = 31536000; // 365 days
    uint256 internal constant START_TIME = 1706745600;

    uint256 internal constant DECIMALS_MULTIPLIER = 1e18;
    uint256 internal constant BIPS = 1e4;
    uint256 public constant PROTOCOL_YIELD = 1200 * DECIMALS_MULTIPLIER / BIPS;

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

    function testFuzz_MaxBorrow(uint128 x) public view {
        uint256 x256 = (uint256(x) + uint256(2)) * 1e18;
        uint256 maxBorrow = testlog.calculateMaxBorrow(x256, START_TIME, START_TIME + YEAR_IN_SECONDS);
        uint256 diff = 0;
        if ((x256 - maxBorrow * PROTOCOL_YIELD / DECIMALS_MULTIPLIER) >= maxBorrow) {
            diff = (x256 - maxBorrow * PROTOCOL_YIELD / DECIMALS_MULTIPLIER) - maxBorrow;
        } else {
            diff = maxBorrow - (x256 - maxBorrow * PROTOCOL_YIELD / DECIMALS_MULTIPLIER);
        }
        
        assertGt(maxBorrow/1e17, diff);
        
    }

    function testFuzz_Debt(uint128 x) public view {
        uint256 x256 = (uint256(x) + uint256(2)) * 1e18;
        uint256 debt = testlog.calculateDebt(x256, START_TIME, START_TIME + YEAR_IN_SECONDS);
        uint256 diff = 0;
        if ((x256 + x256 * PROTOCOL_YIELD / DECIMALS_MULTIPLIER) >= debt) {
            diff = (x256 + x256 * PROTOCOL_YIELD / DECIMALS_MULTIPLIER) - debt;
        } else {
            diff = debt - (x256 + x256 * PROTOCOL_YIELD / DECIMALS_MULTIPLIER);
        }
        
        assertGt(debt/2e16, diff);
    }

}
