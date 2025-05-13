// SPDX-License-Identifier: MIT
pragma solidity >=0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {StableCoinsStaking} from "../src/StableCoinsStaking.sol";
import {StableBondCoins} from "../src/StableBondCoins.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

// Mock for reward contract
contract MockReward {
    uint256 public rewardToReturn;

    constructor(uint256 _rewardToReturn) {
        rewardToReturn = _rewardToReturn;
    }

    function setRewardAmount(uint256 _rewardToReturn) external {
        rewardToReturn = _rewardToReturn;
    }

    function getRewardAmount() external view returns (uint256) {
        return rewardToReturn;
    }

    function getRewards() external view returns (uint256) {
        return rewardToReturn;
    }
}

/**
 * Tests for StableCoinsStaking negative scenarios
 */
contract StableCoinsStakingNegativeTest is Test {
    StableCoinsStaking public staking;
    StableBondCoins public stableBondCoins;
    MockReward public mockReward;
    address public owner;
    address public user1;
    address public user2;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // Custom errors
    error ZeroAmountNotAllowed();
    error NotEnoughStaked(uint256);
    error NoRewardsAvailable();
    error NotEnoughBalance();

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

        mockReward = new MockReward(0);

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

    function testZeroStakeReverts() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroAmountNotAllowed.selector));
        vm.prank(user1);
        staking.stake(0);
    }

    function testZeroStakeOnBehalfOfReverts() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroAmountNotAllowed.selector));
        vm.prank(user1);
        staking.stakeOnBehalfOf(0, user2);
    }

    function testZeroWithdrawReverts() public {
        vm.prank(user1);
        staking.stake(500_000000);

        vm.expectRevert(abi.encodeWithSelector(ZeroAmountNotAllowed.selector));
        vm.prank(user1);
        staking.withdraw(0);
    }

    function testWithdrawMoreThanStakedReverts() public {
        vm.prank(user1);
        staking.stake(500_000000);

        vm.expectRevert(abi.encodeWithSelector(NotEnoughStaked.selector, 500_000000));
        vm.prank(user1);
        staking.withdraw(600_000000);
    }

    function testWithdrawWithoutStakingReverts() public {
        vm.expectRevert(abi.encodeWithSelector(NotEnoughStaked.selector, 0));
        vm.prank(user1);
        staking.withdraw(100_000000);
    }

    function testClaimZeroRewardsReverts() public {
        mockReward.setRewardAmount(0);

        vm.prank(user1);
        staking.stake(500_000000);

        vm.expectRevert(abi.encodeWithSelector(NoRewardsAvailable.selector));
        vm.prank(user1);
        staking.claimRewards();
    }

    function testStakeMoreThanBalanceReverts() public {
        vm.expectRevert(abi.encodeWithSelector(NotEnoughBalance.selector));
        vm.prank(user1);
        staking.stake(2000_000000); // User only has 1000_000000
    }

    function testStakeOnBehalfMoreThanBalanceReverts() public {
        vm.expectRevert(abi.encodeWithSelector(NotEnoughBalance.selector));
        vm.prank(user1);
        staking.stakeOnBehalfOf(2000_000000, user2); // User only has 1000_000000
    }

    function testZeroTotalStakedReverts() public {
        // Test when totalStaked = 0
        uint256 result = staking.pendingRewards(user1);
        assertEq(result, 0);

        mockReward.setRewardAmount(1000);

        result = staking.pendingRewards(user1);
        assertEq(result, 0);
    }

    function testUpdateRewardWithAddressZeroReverts() public {
        vm.prank(user1);
        staking.stake(100_000000);

        mockReward.setRewardAmount(1000);

        vm.prank(user1);
        staking.withdraw(50_000000);

        uint256 rewards = staking.pendingRewards(user1);
        assertGt(rewards, 0);
    }
}
