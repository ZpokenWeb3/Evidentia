// SPDX-License-Identifier: MIT
pragma solidity >=0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {StableCoinsStaking} from "../src/StableCoinsStaking.sol";
import {StableBondCoins} from "../src/StableBondCoins.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract EdgeRewardMock {
    uint256 private rewardAmount;
    bool private shouldRevert;

    constructor() {
        rewardAmount = 100;
        shouldRevert = false;
    }

    function setRewardAmount(uint256 _amount) external {
        rewardAmount = _amount;
    }

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function getRewardAmount() external view returns (uint256) {
        require(!shouldRevert, "Reverted as configured");
        return rewardAmount;
    }

    function getRewards() external view returns (uint256) {
        require(!shouldRevert, "Reverted as configured");
        return rewardAmount;
    }
}

// Better mock for NFTStakingAndBorrowing reward behavior
contract BetterRewardMock {
    uint256 private rewardAmount;
    uint256 private accumulatedRewards;

    constructor() {
        rewardAmount = 0;
        accumulatedRewards = 0;
    }

    function setRewardAmount(uint256 _amount) external {
        rewardAmount = _amount;
    }

    function addAccumulatedRewards(uint256 _amount) external {
        accumulatedRewards += _amount;
    }

    function resetAccumulatedRewards() external {
        accumulatedRewards = 0;
    }

    // This simulates reading the reward amount (view function)
    function getRewardAmount() external view returns (uint256) {
        return rewardAmount;
    }

    // This simulates claiming rewards (state changing function)
    function getRewards() external returns (uint256) {
        uint256 rewards = accumulatedRewards;
        accumulatedRewards = 0; // Reset after claiming
        return rewards;
    }
}

/**
 * Tests for StableCoinsStaking edge cases and complex scenarios
 */
contract StableCoinsStakingEdgeTest is Test {
    StableCoinsStaking public staking;
    StableBondCoins public stableBondCoins;
    EdgeRewardMock public rewardMock;
    address public owner;
    address public user1;
    address public user2;
    address public user3;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    function setUp() public {
        owner = address(1);
        user1 = address(2);
        user2 = address(3);
        user3 = address(4);

        vm.startPrank(owner);
        stableBondCoins = StableBondCoins(
            UnsafeUpgrades.deployUUPSProxy(
                address(new StableBondCoins()), abi.encodeCall(stableBondCoins.initialize, (owner, owner))
            )
        );

        // Use our improved mock
        rewardMock = new EdgeRewardMock();

        staking = StableCoinsStaking(
            UnsafeUpgrades.deployUUPSProxy(
                address(new StableCoinsStaking()),
                abi.encodeCall(staking.initialize, (address(stableBondCoins), address(rewardMock), address(owner)))
            )
        );

        stableBondCoins.grantRole(MINTER_ROLE, owner);

        // Mint different amounts to each user
        stableBondCoins.mint(user1, 10_000000); // Small amount
        stableBondCoins.mint(user2, 1000_000000); // Medium amount
        stableBondCoins.mint(user3, 1000000_000000); // Large but safe amount
        vm.stopPrank();

        // Approve staking contract for all users
        vm.prank(user1);
        stableBondCoins.approve(address(staking), type(uint256).max);

        vm.prank(user2);
        stableBondCoins.approve(address(staking), type(uint256).max);

        vm.prank(user3);
        stableBondCoins.approve(address(staking), type(uint256).max);
    }

    function testRewardDistributionRatio() public {
        // Test that rewards are properly distributed based on stake ratio
        vm.prank(user1);
        staking.stake(1_000000); // 1 token

        vm.prank(user2);
        staking.stake(999_000000); // 999 tokens

        // Total staked is 1000 tokens, with user1 having 0.1% and user2 having 99.9%

        // Set reward and move time forward
        rewardMock.setRewardAmount(1000_000000); // 1000 tokens as reward
        vm.warp(block.timestamp + 30 days);

        // Calculate expected rewards based on stake percentage
        uint256 user1Rewards = staking.pendingRewards(user1);
        uint256 user2Rewards = staking.pendingRewards(user2);

        // Check proportional distribution (with some allowance for rounding)
        assertApproxEqRel(user1Rewards, 1_000000, 0.01e18); // ~0.1% of rewards
        assertApproxEqRel(user2Rewards, 999_000000, 0.01e18); // ~99.9% of rewards

        // Verify total is correct
        assertApproxEqRel(user1Rewards + user2Rewards, 1000_000000, 0.01e18);
    }

    function testSequentialStakeAndWithdraw() public {
        // Test stake, withdraw, stake again behavior
        vm.startPrank(user2);

        // First stake
        staking.stake(500_000000);

        // Set initial reward
        rewardMock.setRewardAmount(100_000000);
        vm.warp(block.timestamp + 10 days);

        // Calculate rewards after first period
        uint256 firstPeriodRewards = staking.pendingRewards(user2);

        // Withdraw half
        staking.withdraw(250_000000);

        // Check staked amount
        uint256 stakedAmount = staking.stakers(user2).stakedAmount;
        assertEq(stakedAmount, 250_000000);

        // Set second reward
        rewardMock.setRewardAmount(50_000000);
        vm.warp(block.timestamp + 10 days);

        // Stake more
        staking.stake(100_000000);

        // Verify staked amount
        stakedAmount = staking.stakers(user2).stakedAmount;
        assertEq(stakedAmount, 350_000000);

        // Check that rewards are properly calculated across the transactions
        uint256 totalRewards = staking.pendingRewards(user2);

        // Total rewards should be greater than first period rewards
        assertGt(totalRewards, firstPeriodRewards);

        vm.stopPrank();
    }

    function testStakeTimestampUpdate() public {
        // Test that stakeTimestamp is properly updated on stake and withdraw

        // Initial stake
        vm.prank(user1);
        staking.stake(1_000000);

        // Check timestamp
        uint256 timestamp1 = staking.stakers(user1).stakeTimestamp;
        assertEq(timestamp1, block.timestamp);

        // Move time forward and stake again
        vm.warp(block.timestamp + 5 days);
        vm.prank(user1);
        staking.stake(500000);

        // Check timestamp is updated
        uint256 timestamp2 = staking.stakers(user1).stakeTimestamp;
        assertEq(timestamp2, block.timestamp);
        assertGt(timestamp2, timestamp1);

        // Move time and withdraw
        vm.warp(block.timestamp + 10 days);
        vm.prank(user1);
        staking.withdraw(300000);

        // Check timestamp is updated again
        uint256 timestamp3 = staking.stakers(user1).stakeTimestamp;
        assertEq(timestamp3, block.timestamp);
        assertGt(timestamp3, timestamp2);
    }

    function testLargeStakeAmount() public {
        // Test with large but safe stake amounts
        vm.prank(user3);
        staking.stake(1000000_000000);

        // Check total staked
        assertEq(staking.totalStaked(), 1000000_000000);

        // Set reward
        rewardMock.setRewardAmount(1000_000000);

        // Move time forward
        vm.warp(block.timestamp + 30 days);

        // Claim rewards
        vm.prank(user3);
        staking.claimRewards();

        // Check staked amount remains intact
        uint256 stakedAmount = staking.stakers(user3).stakedAmount;
        assertEq(stakedAmount, 1000000_000000);
    }

    function testMultipleUserStakeUnstake() public {
        vm.prank(user1);
        staking.stake(1_000000);

        vm.prank(user2);
        staking.stake(500_000000);

        rewardMock.setRewardAmount(0);
        vm.warp(block.timestamp + 30 days);

        vm.prank(user3);
        staking.stake(10_000000);

        rewardMock.setRewardAmount(1000_000000);
        vm.warp(block.timestamp + 30 days);

        vm.prank(user2);
        staking.stake(10_000000);

        // Call these functions to ensure coverage
        staking.pendingRewards(user1);
        staking.pendingRewards(user2);

        vm.prank(user1);
        uint256 withdrawAmount = 500000;
        staking.withdraw(withdrawAmount);

        uint256 user1Staked = staking.stakers(user1).stakedAmount;
        assertEq(user1Staked, 1_000000 - withdrawAmount);
    }
}
