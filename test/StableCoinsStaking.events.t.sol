// SPDX-License-Identifier: MIT
pragma solidity >=0.8.30;

import {Test, console, Vm} from "forge-std/Test.sol";
import {StableCoinsStaking} from "../src/StableCoinsStaking.sol";
import {StableBondCoins} from "../src/StableBondCoins.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

// Simple mock contract for tests
contract MockReward {
    uint256 private rewardAmount;

    function getRewardAmount() external pure returns (uint256) {
        return 0;
    }

    function transferRewards() external returns (uint256) {
        rewardAmount = 0;
        return 0;
    }
}

/**
 * Tests for StableCoinsStaking events using a mock reward contract
 */
contract StableCoinsStakingEventsTest is Test {
    StableCoinsStaking public staking;
    StableBondCoins public stableBondCoins;
    address public owner;
    address public user1;
    address public user2;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // Events to test
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 reward);

    // Custom errors
    error NoRewardsAvailable();

    function setUp() public {
        owner = address(1);
        user1 = address(2);
        user2 = address(3);

        vm.startPrank(owner);
        stableBondCoins = StableBondCoins(
            Upgrades.deployUUPSProxy(
                "StableBondCoins.sol:StableBondCoins",
                abi.encodeCall(stableBondCoins.initialize, (owner, owner, "Stable Bond Coins", "SBC", 6))
            )
        );

        MockReward mockReward = new MockReward();

        staking = StableCoinsStaking(
            Upgrades.deployUUPSProxy(
                "StableCoinsStaking.sol:StableCoinsStaking",
                abi.encodeCall(staking.initialize, (address(stableBondCoins), address(mockReward), address(owner)))
            )
        );

        stableBondCoins.grantRole(MINTER_ROLE, owner);

        stableBondCoins.mint(user1, 1000_000000);
        stableBondCoins.mint(user2, 1000_000000);
        vm.stopPrank();

        vm.prank(user1);
        stableBondCoins.approve(address(staking), type(uint256).max);

        vm.prank(user2);
        stableBondCoins.approve(address(staking), type(uint256).max);
    }

    function testStakedEvent() public {
        uint256 stakeAmount = 100_000000;

        vm.expectEmit(true, false, false, true);
        emit Staked(user1, stakeAmount);

        vm.prank(user1);
        staking.stake(stakeAmount);

        uint256 stakedAmount = staking.stakers(user1).stakedAmount;
        assertEq(stakedAmount, stakeAmount);
        assertEq(staking.totalStaked(), stakeAmount);
    }

    function testStakedOnBehalfOfEvent() public {
        uint256 stakeAmount = 100_000000;

        vm.expectEmit(true, false, false, true);
        emit Staked(user2, stakeAmount);

        vm.prank(user1);
        staking.stakeOnBehalfOf(stakeAmount, user2);

        uint256 stakedAmount = staking.stakers(user2).stakedAmount;
        assertEq(stakedAmount, stakeAmount);
        assertEq(staking.totalStaked(), stakeAmount);
    }

    function testMultipleStakes() public {
        vm.prank(user1);
        staking.stake(50_000000);

        vm.prank(user1);
        staking.stake(30_000000);

        uint256 stakedAmount = staking.stakers(user1).stakedAmount;
        assertEq(stakedAmount, 80_000000);
    }

    function testWithdrawnEvent() public {
        uint256 stakeAmount = 100_000000;
        uint256 withdrawAmount = 50_000000;

        vm.prank(user1);
        staking.stake(stakeAmount);

        vm.expectEmit(true, false, false, true);
        emit Withdrawn(user1, withdrawAmount);

        vm.prank(user1);
        staking.withdraw(withdrawAmount);

        uint256 stakedAmount = staking.stakers(user1).stakedAmount;
        assertEq(stakedAmount, stakeAmount - withdrawAmount);
        assertEq(staking.totalStaked(), stakeAmount - withdrawAmount);
    }

    function testFullWithdrawalEvent() public {
        uint256 stakeAmount = 100_000000;

        vm.prank(user1);
        staking.stake(stakeAmount);

        vm.expectEmit(true, false, false, true);
        emit Withdrawn(user1, stakeAmount);

        vm.prank(user1);
        staking.withdraw(stakeAmount);

        uint256 stakedAmount = staking.stakers(user1).stakedAmount;
        assertEq(stakedAmount, 0);
        assertEq(staking.totalStaked(), 0);
    }

    function testRewardClaimedNoRewardsError() public {
        uint256 stakeAmount = 100_000000;

        vm.prank(user1);
        staking.stake(stakeAmount);

        vm.expectRevert(abi.encodeWithSelector(NoRewardsAvailable.selector));
        vm.prank(user1);
        staking.claimRewards();
    }
}
