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
        uint256 borrow_debt = maxBorrow * PROTOCOL_YIELD / DECIMALS_MULTIPLIER;
        if ((x256 - borrow_debt) >= maxBorrow) {
            diff = (x256 - borrow_debt) - maxBorrow;
        } else {
            diff = maxBorrow - (x256 - borrow_debt);
        }

        assertGt(maxBorrow / 5e16, diff);
    }

    function testFuzz_MaxBorrow_2years(uint128 x) public view {
        uint256 x256 = (uint256(x) + uint256(2)) * 1e18;
        uint256 maxBorrow = testlog.calculateMaxBorrow(x256, START_TIME, START_TIME + 2 * YEAR_IN_SECONDS);
        uint256 diff = 0;
        uint256 first_year_debt = maxBorrow * PROTOCOL_YIELD / DECIMALS_MULTIPLIER;
        uint256 second_year_debt = (first_year_debt + maxBorrow) * PROTOCOL_YIELD / DECIMALS_MULTIPLIER;

        if ((x256 - first_year_debt - second_year_debt) >= maxBorrow) {
            diff = (x256 - first_year_debt - second_year_debt) - maxBorrow;
        } else {
            diff = maxBorrow - (x256 - first_year_debt - second_year_debt);
        }

        assertGt(maxBorrow / 2e16, diff);
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

        assertGt(debt / 2e16, diff);
    }

    function testFuzz_Debt_2years(uint128 x) public view {
        uint256 x256 = (uint256(x) + uint256(2)) * 1e18;
        uint256 debt = testlog.calculateDebt(x256, START_TIME, START_TIME + 2 * YEAR_IN_SECONDS);
        uint256 diff = 0;
        uint256 first_year_debt = x256 + x256 * PROTOCOL_YIELD / DECIMALS_MULTIPLIER;
        uint256 second_year_debt = first_year_debt + first_year_debt * PROTOCOL_YIELD / DECIMALS_MULTIPLIER;
        if (second_year_debt >= debt) {
            diff = second_year_debt - debt;
        } else {
            diff = debt - second_year_debt;
        }

        assertGt(debt / 2e16, diff);
    }

    function testFuzz_MaxBorrow_1month(uint128 x) public view {
        uint256 x256 = (uint256(x) + uint256(2)) * 1e18;
        uint256 month_in_seconds = YEAR_IN_SECONDS / 12;
        uint256 month_yield = 948879293458 * DECIMALS_MULTIPLIER / (BIPS * 1e10); // (1.12)**(1/12)
        uint256 maxBorrow = testlog.calculateMaxBorrow(x256, START_TIME, START_TIME + month_in_seconds);
        uint256 diff = 0;
        uint256 month_debt = maxBorrow * month_yield / DECIMALS_MULTIPLIER;

        if ((x256 - month_debt) >= maxBorrow) {
            diff = (x256 - month_debt) - maxBorrow;
        } else {
            diff = maxBorrow - (x256 - month_debt);
        }

        assertGt(maxBorrow / 3e14, diff);
    }

    function testFuzz_MaxBorrow_2months(uint128 x) public view {
        uint256 x256 = (uint256(x) + uint256(2)) * 1e18;
        uint256 month_in_seconds = YEAR_IN_SECONDS / 12;
        uint256 month_yield = 948879293458 * DECIMALS_MULTIPLIER / (BIPS * 1e10); // (1.12)**(1/12)
        uint256 maxBorrow = testlog.calculateMaxBorrow(x256, START_TIME, START_TIME + 2 * month_in_seconds);
        uint256 diff = 0;
        uint256 first_month_debt = maxBorrow * month_yield / DECIMALS_MULTIPLIER;
        uint256 second_month_debt = (maxBorrow + first_month_debt) * month_yield / DECIMALS_MULTIPLIER;

        if ((x256 - first_month_debt - second_month_debt) >= maxBorrow) {
            diff = (x256 - first_month_debt - second_month_debt) - maxBorrow;
        } else {
            diff = maxBorrow - (x256 - first_month_debt - second_month_debt);
        }

        assertGt(maxBorrow / 1e14, diff);
    }

    function testFuzz_Debt_1month(uint128 x) public view {
        uint256 x256 = (uint256(x) + uint256(2)) * 1e18;
        uint256 month_in_seconds = YEAR_IN_SECONDS / 12;
        uint256 month_yield = 948879293458 * DECIMALS_MULTIPLIER / (BIPS * 1e10); // (1.12)**(1/12)
        uint256 debt = testlog.calculateDebt(x256, START_TIME, START_TIME + month_in_seconds);
        uint256 diff = 0;
        uint256 first_month_debt = x256 + x256 * month_yield / DECIMALS_MULTIPLIER;
        if (first_month_debt >= debt) {
            diff = first_month_debt - debt;
        } else {
            diff = debt - first_month_debt;
        }

        assertGt(debt / 1e14, diff);
    }

    function testFuzz_Debt_2month(uint128 x) public view {
        uint256 x256 = (uint256(x) + uint256(2)) * 1e18;
        uint256 month_in_seconds = YEAR_IN_SECONDS / 12;
        uint256 month_yield = 948879293458 * DECIMALS_MULTIPLIER / (BIPS * 1e10); // (1.12)**(1/12)
        uint256 debt = testlog.calculateDebt(x256, START_TIME, START_TIME + 2 * month_in_seconds);
        uint256 diff = 0;
        uint256 first_month_debt = x256 + x256 * month_yield / DECIMALS_MULTIPLIER;
        uint256 second_month_debt = first_month_debt + first_month_debt * month_yield / DECIMALS_MULTIPLIER;
        if (second_month_debt >= debt) {
            diff = second_month_debt - debt;
        } else {
            diff = debt - second_month_debt;
        }

        assertGt(debt / 1e14, diff);
    }
}
