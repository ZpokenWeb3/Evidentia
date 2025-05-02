// SPDX-License-Identifier: MIT
pragma solidity >=0.8.22;

import {Test, console, Vm} from "forge-std/Test.sol";
import {StableCoinsStaking} from "../src/StableCoinsStaking.sol";
import {StableBondCoins} from "../src/StableBondCoins.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {EndpointV2Mock} from "@layerzerolabs/test-devtools-evm-foundry/contracts/Mocks/EndpointV2Mock.sol";

// Simple mock contract for tests
contract MockReward {
    function getRewardAmount() external pure returns (uint256) {
        return 0;
    }

    function getRewards() external pure returns (uint256) {
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
    address public lzEndpoint;
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
        lzEndpoint = address(4);

        vm.startPrank(owner);

        // 1. Deploy a mock endpoint
        EndpointV2Mock mock = new EndpointV2Mock(1, owner);

        StableBondCoins impl = new StableBondCoins(address(mock));
        bytes memory initData = abi.encodeCall(StableBondCoins.initialize, (owner, owner, owner));
        address proxyAddr = UnsafeUpgrades.deployUUPSProxy(address(impl), initData);
        stableBondCoins = StableBondCoins(proxyAddr);

        MockReward mockReward = new MockReward();

        staking = StableCoinsStaking(
            UnsafeUpgrades.deployUUPSProxy(
                address(new StableCoinsStaking()),
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
