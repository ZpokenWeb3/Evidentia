// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {NFTStakingAndBorrowing} from "../src/NFTStakingAndBorrowing.sol";
import {StableBondCoins} from "../src/StableBondCoins.sol";
import {BondNFT} from "../src/BondNFT.sol";
import {StableCoinsStaking} from "../src/StableCoinsStaking.sol";

contract NFTStakingAndBorrowingTest is Test {
    NFTStakingAndBorrowing public nftStaking;
    BondNFT public bondNFT;
    StableBondCoins public stableBondCoins;
    address public owner;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    uint256 internal constant YEAR_IN_SECONDS = 31536000; // 365 days
    uint256 internal constant START_TIME = 1706745600;
    uint256 internal constant UNIT = 1e18;
    uint256 internal constant BIPS = 1e4;
    uint256 internal constant PROTOCOL_YIELD = 1200 * UNIT / BIPS;

    function setUp() public {
        owner = address(1);
        vm.startPrank(owner);
        bondNFT = new BondNFT(owner, "https://example.com/{id}.json");
        stableBondCoins = new StableBondCoins(owner, owner);

        nftStaking = new NFTStakingAndBorrowing(address(stableBondCoins));

        stableBondCoins.grantRole(MINTER_ROLE, address(nftStaking));
        BondNFT.Metadata memory metadata = BondNFT.Metadata({
            value: 1000_000000,
            couponValue: 50_000000,
            issueTimestamp: 1,
            expirationTimestamp: 1 + 31536000,
            ISIN: "US1234567890"
        });

        bondNFT.setMetaData(1, metadata);
        bondNFT.setMetaData(2, metadata);
        bondNFT.setMetaData(3, metadata);
        bondNFT.setAllowedMints(owner, 1, 10);
        bondNFT.setAllowedMints(owner, 2, 10);
        bondNFT.setAllowedMints(owner, 3, 10);
        bondNFT.mint(1, 10, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        nftStaking.whitelistNFT(address(bondNFT), true);
        vm.stopPrank();
    }

    function test_stakeNFT() public {
        owner = address(1);
        vm.prank(owner);
        nftStaking.stakeNFT(address(bondNFT), 1, 10);
        console.log(address(this));
        assertEq(stableBondCoins.balanceOf(address(nftStaking)), 9975_000000);

        NFTStakingAndBorrowing.TotalStats memory totalStats = nftStaking.getTotalStats();

        assertEq(totalStats.staked, 9975_000000);

        NFTStakingAndBorrowing.UserStats memory userStats = nftStaking.getUserStats(owner);

        assertEq(userStats.staked, 9975_000000);
        assertApproxEqRel(nftStaking.userAvailableToBorrow(owner), 8906_250000, 0.001e18);
    }

    function test_borrow() public {
        owner = address(1);

        vm.startPrank(owner);
        nftStaking.stakeNFT(address(bondNFT), 1, 10);
        NFTStakingAndBorrowing.UserStats memory userStats = nftStaking.getUserStats(owner);

        assertEq(userStats.staked, 9975_000000);
        assertApproxEqRel(nftStaking.userAvailableToBorrow(owner), 8906_250000, 0.001e18);

        nftStaking.borrow(500_000000);
        vm.stopPrank();

        userStats = nftStaking.getUserStats(owner);

        assertEq(userStats.borrowed, 500_000000);
        assertEq(nftStaking.userAvailableToBorrow(owner), 8406_250000);

        NFTStakingAndBorrowing.TotalStats memory totalStats = nftStaking.getTotalStats();
        assertEq(totalStats.borrowed, 500_000000);

        vm.roll(12345);
        vm.warp(1 + 30 days);

        userStats = nftStaking.getUserStats(owner);
        totalStats = nftStaking.getTotalStats();
        assertEq(nftStaking.userAvailableToBorrow(owner), 8484_917395);
        assertEq(userStats.debtUpdateTimestamp, 2592001);
        assertEq(totalStats.debt, 504_679101);
        assertEq(userStats.debt, 504_679101);
    }

    function test_repay() public {
        owner = address(1);
        address client1 = address(2);
        address client2 = address(3);

        vm.startPrank(owner);
        bondNFT.setAllowedMints(client1, 2, 10);
        bondNFT.setAllowedMints(client2, 3, 10);
        vm.stopPrank();

        vm.prank(client1);
        bondNFT.mint(2, 10, "");
        vm.prank(client2);
        bondNFT.mint(3, 10, "");

        vm.prank(client1);
        bondNFT.setApprovalForAll(address(nftStaking), true);
        vm.prank(client2);
        bondNFT.setApprovalForAll(address(nftStaking), true);

        vm.prank(client1);
        nftStaking.stakeNFT(address(bondNFT), 2, 10);
        vm.prank(client2);
        nftStaking.stakeNFT(address(bondNFT), 3, 10);

        vm.prank(client1);
        nftStaking.borrow(0);
        vm.prank(client2);
        nftStaking.borrow(0);

        vm.warp(30 days);
        vm.roll(3);

        vm.prank(client2);
        stableBondCoins.transfer(client1, 500_000000);

        vm.prank(client1);
        stableBondCoins.approve(address(nftStaking), UINT256_MAX);

        vm.prank(client1);
        nftStaking.repay(0);

        NFTStakingAndBorrowing.UserStats memory userStats = nftStaking.getUserStats(client1);
        NFTStakingAndBorrowing.TotalStats memory totalStats = nftStaking.getTotalStats();

        userStats = nftStaking.getUserStats(client1);
        assertEq(userStats.nominalAvailable, 8989_596464);
        assertEq(userStats.borrowed, 0);
        assertEq(userStats.debt, 0);
        assertEq(8989_596464 + 3 - nftStaking.userAvailableToBorrow(client1) < 5, true);
    }

    function test_small_amounts() public {
        owner = address(1);

        vm.startPrank(owner);
        nftStaking.stakeNFT(address(bondNFT), 1, 10);
        NFTStakingAndBorrowing.UserStats memory userStats = nftStaking.getUserStats(owner);

        assertEq(userStats.staked, 9975_000000);
        assertApproxEqRel(nftStaking.userAvailableToBorrow(owner), 8906_250000, 0.001e18);

        nftStaking.borrow(10);
        vm.stopPrank();

        userStats = nftStaking.getUserStats(owner);

        assertEq(userStats.borrowed, 10);
        assertEq(nftStaking.userAvailableToBorrow(owner), 8906_250000 - 10);

        NFTStakingAndBorrowing.TotalStats memory totalStats = nftStaking.getTotalStats();
        assertEq(totalStats.borrowed, 10);

        vm.roll(2);
        vm.warp(1 + 30 days);

        userStats = nftStaking.getUserStats(owner);
        totalStats = nftStaking.getTotalStats();
        assertEq(nftStaking.userAvailableToBorrow(owner), 8989_596486);
        assertEq(userStats.debtUpdateTimestamp, 2592001);
        assertEq(totalStats.debt, 10);
        assertEq(userStats.debt, 10);
    }

    function test_staking_over_time() public {
        owner = address(1);
        address client1 = address(2);
        address client2 = address(3);

        vm.startPrank(owner);
        bondNFT.setAllowedMints(client1, 2, 10);
        bondNFT.setAllowedMints(client2, 3, 10);
        vm.stopPrank();

        vm.prank(client1);
        bondNFT.mint(2, 10, "");
        vm.prank(client2);
        bondNFT.mint(3, 10, "");

        vm.prank(client1);
        bondNFT.setApprovalForAll(address(nftStaking), true);
        vm.prank(client2);
        bondNFT.setApprovalForAll(address(nftStaking), true);

        vm.warp(30 days);
        vm.roll(3);
        // Client1 makes some staking
        vm.prank(client1);
        nftStaking.stakeNFT(address(bondNFT), 2, 1);

        NFTStakingAndBorrowing.UserStats memory userStats = nftStaking.getUserStats(client1);
        NFTStakingAndBorrowing.TotalStats memory totalStats = nftStaking.getTotalStats();

        assertEq(userStats.staked, 997_500000);
        assertEq(totalStats.staked, 997_500000);
        assertEq(totalStats.debt, 0);
        assertEq(userStats.debtUpdateTimestamp, 30 days);
        assertEq(userStats.nominalAvailable, 898_959646);
        userStats = nftStaking.getUserStats(client1);

        // Client1 borrows everything available
        vm.prank(client1);
        nftStaking.borrow(0);

        userStats = nftStaking.getUserStats(client1);
        assertEq(userStats.nominalAvailable, 898_959646);
        assertEq(userStats.borrowed, 898_959646);
        assertEq(userStats.debt, 898_959646);
        assertEq(nftStaking.userAvailableToBorrow(client1), 0);

        vm.warp(90 days);
        vm.roll(4);

        // Client2 makes some staking
        vm.prank(client2);
        nftStaking.stakeNFT(address(bondNFT), 3, 1);

        userStats = nftStaking.getUserStats(client1);
        assertEq(userStats.debt, 915_863667);
        assertEq(userStats.debtUpdateTimestamp, 90 days);

        userStats = nftStaking.getUserStats(client2);
        totalStats = nftStaking.getTotalStats();

        assertEq(userStats.staked, 997_500000);
        assertEq(totalStats.staked, 2 * 997_500000);
        assertEq(totalStats.debt, 915_863667);
        assertEq(userStats.debtUpdateTimestamp, 90 days);
        assertEq(totalStats.debtUpdateTimestamp, 90 days);
        assertEq(userStats.nominalAvailable, 915_863667);
        assertEq(nftStaking.userAvailableToBorrow(client2), 915_863666);
        assertEq(nftStaking.userAvailableToBorrow(client1), 0);

        // Client2 borrows everything available
        vm.prank(client2);
        nftStaking.borrow(0);

        vm.warp(120 days);
        vm.roll(5);

        NFTStakingAndBorrowing.UserStats memory userStats1 = nftStaking.getUserStats(client1);
        NFTStakingAndBorrowing.UserStats memory userStats2 = nftStaking.getUserStats(client2);
        totalStats = nftStaking.getTotalStats();

        assertEq(userStats1.debt, 924_434505);
        assertEq(userStats2.debt, 924_434505);
        assertEq(totalStats.debt, 2 * 924_434505);
        assertEq(totalStats.borrowed, 915_863667 + 898_959646);
        assertEq(userStats1.debtUpdateTimestamp, 120 days);
        assertEq(userStats2.debtUpdateTimestamp, 120 days);
    }

    function test_unstake() public {
        owner = address(1);
        address client1 = address(2);
        address client2 = address(3);

        vm.startPrank(owner);
        bondNFT.setAllowedMints(client1, 2, 10);
        bondNFT.setAllowedMints(client2, 3, 10);
        vm.stopPrank();

        vm.prank(client1);
        bondNFT.mint(2, 10, "");
        vm.prank(client2);
        bondNFT.mint(3, 10, "");

        vm.prank(client1);
        bondNFT.setApprovalForAll(address(nftStaking), true);
        vm.prank(client2);
        bondNFT.setApprovalForAll(address(nftStaking), true);

        vm.warp(30 days);
        vm.roll(3);
        // Client1 makes some staking
        vm.startPrank(client1);
        nftStaking.stakeNFT(address(bondNFT), 2, 5);
        assertEq(nftStaking.userAvailableToUnstake(client1, address(bondNFT), 2), 5);
        nftStaking.unstakeNFT(address(bondNFT), 2, 5);
        assertEq(nftStaking.userAvailableToUnstake(client1, address(bondNFT), 2), 0);
        nftStaking.stakeNFT(address(bondNFT), 2, 5);
        assertEq(nftStaking.userAvailableToUnstake(client1, address(bondNFT), 2), 5);

        vm.warp(30 days + 111);
        vm.roll(4);
        nftStaking.unstakeNFT(address(bondNFT), 2, 5);
        nftStaking.stakeNFT(address(bondNFT), 2, 5);

        vm.warp(30 days + 178);
        vm.roll(5);
        assertEq(nftStaking.userAvailableToUnstake(client1, address(bondNFT), 2), 5);
        nftStaking.unstakeNFT(address(bondNFT), 2, 5);
        nftStaking.stakeNFT(address(bondNFT), 2, 5);

        vm.warp(35 days);
        vm.roll(6);

        assertEq(nftStaking.userAvailableToUnstake(client1, address(bondNFT), 2), 5);
        nftStaking.unstakeNFT(address(bondNFT), 2, 5);
        nftStaking.stakeNFT(address(bondNFT), 2, 5);
        nftStaking.stakeNFT(address(bondNFT), 2, 5);
        vm.stopPrank();

        NFTStakingAndBorrowing.UserStats memory userStats = nftStaking.getUserStats(client1);
        assertEq(userStats.staked, 9975_000000);

        // Client borrows less than a half of available
        uint256 borrow_amount = nftStaking.userAvailableToBorrow(client1) / 2;
        vm.prank(client1);
        nftStaking.borrow(borrow_amount);

        // User unstakes
        console.log("Available to borrow: ", nftStaking.userAvailableToBorrow(client1));
        assertEq(nftStaking.userAvailableToUnstake(client1, address(bondNFT), 2), 5);
        vm.prank(client1);
        nftStaking.unstakeNFT(address(bondNFT), 2, 4);

        userStats = nftStaking.getUserStats(client1);
        assertEq(userStats.staked, 6 * 9975_000000 / 10);
        assertLe(nftStaking.userAvailableToBorrow(client1), borrow_amount);
    }

    function test_unstake_case_02() public {
        owner = address(1);
        address client1 = address(2);

        vm.startPrank(owner);
        bondNFT.setAllowedMints(client1, 2, 10);
        bondNFT.setAllowedMints(client1, 3, 10);
        vm.stopPrank();

        vm.startPrank(client1);
        bondNFT.mint(2, 10, "");
        bondNFT.mint(3, 10, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        bondNFT.setApprovalForAll(address(nftStaking), true);

        vm.warp(30 days);
        vm.roll(3);
        nftStaking.stakeNFT(address(bondNFT), 2, 10);
        assertEq(nftStaking.userAvailableToUnstake(client1, address(bondNFT), 2), 10);

        vm.warp(30 days + 111);
        vm.roll(4);

        uint256 borrow_amount = nftStaking.userAvailableToBorrow(client1);
        nftStaking.borrow(borrow_amount - 10);
        assertEq(nftStaking.userAvailableToUnstake(client1, address(bondNFT), 2), 0);

        nftStaking.stakeNFT(address(bondNFT), 3, 10);
        assertEq(nftStaking.userAvailableToUnstake(client1, address(bondNFT), 2), 10);
        assertEq(nftStaking.userAvailableToUnstake(client1, address(bondNFT), 3), 10);

        nftStaking.unstakeNFT(address(bondNFT), 2, 10);
        assertEq(nftStaking.userAvailableToUnstake(client1, address(bondNFT), 3), 0);
    }

    function test_liquidate_case_01() public {
        owner = address(1);
        address client1 = address(2);
        address client2 = address(3);

        vm.startPrank(owner);
        bondNFT.setAllowedMints(client1, 2, 10);
        bondNFT.setAllowedMints(client2, 3, 10);
        vm.stopPrank();

        vm.prank(client1);
        bondNFT.mint(2, 10, "");
        vm.prank(client2);
        bondNFT.mint(3, 10, "");

        vm.prank(client1);
        bondNFT.setApprovalForAll(address(nftStaking), true);
        vm.prank(client2);
        bondNFT.setApprovalForAll(address(nftStaking), true);

        // Client1 borrows less than a half of available
        vm.startPrank(client1);
        nftStaking.stakeNFT(address(bondNFT), 2, 10);
        console.log("Minted Stables:  ", stableBondCoins.balanceOf(address(nftStaking)));
        assertEq(nftStaking.userAvailableToUnstake(client1, address(bondNFT), 2), 10);
        uint256 borrow_amount = nftStaking.userAvailableToBorrow(client1) / 2;
        nftStaking.borrow(borrow_amount);
        assertEq(nftStaking.userAvailableToUnstake(client1, address(bondNFT), 2), 5);
        vm.stopPrank();

        assertEq(stableBondCoins.balanceOf(client1), borrow_amount);
        console.log("Client1 borrowed:", borrow_amount);
        console.log("Stables left:    ", stableBondCoins.balanceOf(address(nftStaking)));
        assertEq(stableBondCoins.balanceOf(address(nftStaking)), 9975_000000 - borrow_amount);
        assert(nftStaking.userAvailableToBorrow(client1) - borrow_amount < 10);

        // we go to the future, 40 days to expiration
        vm.warp(365 days - 40 days);
        vm.roll(2);
        NFTStakingAndBorrowing.UserStats memory userStats = nftStaking.getUserStats(client1);
        assertEq(userStats.borrowed, borrow_amount);
        assertEq(userStats.debt, 4925_940379);

        console.log("Client1 debt:    ", userStats.debt);
        console.log("Client1 Stables: ", stableBondCoins.balanceOf(client1));

        assertEq(bondNFT.balanceOf(client1, 2), 0);
        assertEq(bondNFT.balanceOf(address(nftStaking), 2), 10);
        assertEq(stableBondCoins.balanceOf(client2), 0);

        // Client2 borrows to get stable coins and liquidate
        vm.startPrank(client2);
        nftStaking.stakeNFT(address(bondNFT), 3, 10);
        nftStaking.borrow(0);
        stableBondCoins.approve(address(nftStaking), UINT256_MAX);
        console.log("Client2 Stables: ", stableBondCoins.balanceOf(client2));
        nftStaking.liquidate(address(bondNFT), 2, client1);
        vm.stopPrank();

        console.log("Client1 Stables: ", stableBondCoins.balanceOf(client1));
        console.log("Client2 Stables: ", stableBondCoins.balanceOf(client2));

        assertEq(bondNFT.balanceOf(client1, 2), 5);
        assertEq(bondNFT.balanceOf(client2, 2), 5);
        assertEq(bondNFT.balanceOf(address(nftStaking), 2), 0);

        assertEq(stableBondCoins.balanceOf(client1), 4453_125000);
        assertEq(stableBondCoins.balanceOf(client2), 4925_940381);
    }

    function test_liquidate_case_02() public {
        owner = address(1);
        address client1 = address(2);
        address client2 = address(3);

        vm.startPrank(owner);
        bondNFT.setAllowedMints(client1, 1, 5);
        bondNFT.setAllowedMints(client1, 2, 10);
        bondNFT.setAllowedMints(client2, 3, 20);
        vm.stopPrank();

        vm.prank(client1);
        bondNFT.mint(1, 5, "");
        vm.prank(client1);
        bondNFT.mint(2, 10, "");
        vm.prank(client2);
        bondNFT.mint(3, 20, "");

        vm.prank(client1);
        bondNFT.setApprovalForAll(address(nftStaking), true);
        vm.prank(client2);
        bondNFT.setApprovalForAll(address(nftStaking), true);

        // Client1 borrows less than a half of available
        vm.startPrank(client1);
        nftStaking.stakeNFT(address(bondNFT), 1, 5);
        nftStaking.stakeNFT(address(bondNFT), 2, 10);
        console.log("Minted Stables:  ", stableBondCoins.balanceOf(address(nftStaking)));
        uint256 borrow_amount = nftStaking.userAvailableToBorrow(client1);
        nftStaking.borrow(borrow_amount);
        vm.stopPrank();

        assertEq(stableBondCoins.balanceOf(client1), borrow_amount);
        console.log("Client1 borrowed:", borrow_amount);
        console.log("Stables left:    ", stableBondCoins.balanceOf(address(nftStaking)));
        assertEq(stableBondCoins.balanceOf(address(nftStaking)), 14962_500000 - borrow_amount);
        assert(nftStaking.userAvailableToBorrow(client1) < 10);

        // we go to the future, 40 days to expiration
        vm.warp(365 days - 40 days);
        vm.roll(2);
        NFTStakingAndBorrowing.UserStats memory userStats = nftStaking.getUserStats(client1);
        assertEq(userStats.borrowed, borrow_amount);
        assertEq(userStats.debt, 14777_821141);

        console.log("Client1 debt:    ", userStats.debt);
        console.log("Client1 Stables: ", stableBondCoins.balanceOf(client1));

        assertEq(bondNFT.balanceOf(client1, 2), 0);
        assertEq(bondNFT.balanceOf(address(nftStaking), 2), 10);
        assertEq(stableBondCoins.balanceOf(client2), 0);

        // Client2 borrows to get stable coins and liquidate
        vm.startPrank(client2);
        nftStaking.stakeNFT(address(bondNFT), 3, 20);
        nftStaking.borrow(0);
        stableBondCoins.approve(address(nftStaking), UINT256_MAX);
        console.log("Client2 Stables: ", stableBondCoins.balanceOf(client2));
        nftStaking.liquidate(address(bondNFT), 2, client1);
        vm.stopPrank();

        console.log("Client1 Stables: ", stableBondCoins.balanceOf(client1));
        console.log("Client2 Stables: ", stableBondCoins.balanceOf(client2));

        assertEq(bondNFT.balanceOf(client1, 2), 0);
        assertEq(bondNFT.balanceOf(client2, 2), 10);
        assertEq(bondNFT.balanceOf(address(nftStaking), 2), 0);

        assertEq(stableBondCoins.balanceOf(client1), 13359_374999);
        assertEq(stableBondCoins.balanceOf(client2), 9851_880762);
    }

    function test_getRewardAmount() public {
        vm.startPrank(owner);
        StableCoinsStaking stableStaking = new StableCoinsStaking(address(stableBondCoins), address(nftStaking));
        nftStaking.setStablesStakingAddress(address(stableStaking));
        vm.stopPrank();

        vm.prank(owner);
        nftStaking.stakeNFT(address(bondNFT), 1, 10);

        vm.startPrank(owner);
        stableBondCoins.approve(address(nftStaking), type(uint256).max);
        uint256 borrowAmount = 1000_000000;
        nftStaking.borrow(borrowAmount);
        vm.stopPrank();

        // Fast forward time to accumulate interest
        vm.warp(30 days);

        uint256 rewardAmount = nftStaking.getRewardAmount();
        assertGt(rewardAmount, 0, "Reward amount should be greater than 0");

        // Claim rewards through stableStaking contract
        vm.prank(address(stableStaking));
        uint256 claimedRewards = nftStaking.getRewards();

        assertEq(claimedRewards, rewardAmount);
        assertEq(nftStaking.getRewardAmount(), 0);
    }

    function test_edge_cases() public {
        // Test for small amounts
        vm.startPrank(owner);
        nftStaking.stakeNFT(address(bondNFT), 1, 1);

        // Borrow a very small amount (1)
        uint256 initialBorrow = 1;
        nftStaking.borrow(initialBorrow);

        assertEq(stableBondCoins.balanceOf(owner), initialBorrow);

        vm.warp(30 days);

        stableBondCoins.approve(address(nftStaking), 1000_000000);
        nftStaking.repay(0); // full debt

        NFTStakingAndBorrowing.UserStats memory userStats = nftStaking.getUserStats(owner);
        assertEq(userStats.debt, 0);

        vm.stopPrank();
    }

    function test_stakeNFTandStables() public {
        vm.startPrank(owner);
        StableCoinsStaking stableStaking = new StableCoinsStaking(address(stableBondCoins), address(nftStaking));
        nftStaking.setStablesStakingAddress(address(stableStaking));
        vm.stopPrank();

        vm.startPrank(owner);
        nftStaking.stakeNFT(address(bondNFT), 1, 5);

        stableBondCoins.approve(address(nftStaking), type(uint256).max);
        nftStaking.stakeNFTandStables(address(bondNFT), 1, 5);

        (uint256 stakedAmount,,,,) = stableStaking.stakers(owner);
        assertGt(stakedAmount, 0, "Staked amount should be > 0");

        vm.stopPrank();
    }

    function test_stakeStables_with_amount() public {
        vm.startPrank(owner);
        StableCoinsStaking stableStaking = new StableCoinsStaking(address(stableBondCoins), address(nftStaking));
        nftStaking.setStablesStakingAddress(address(stableStaking));
        vm.stopPrank();

        vm.startPrank(owner);
        nftStaking.stakeNFT(address(bondNFT), 1, 10);

        stableBondCoins.approve(address(nftStaking), type(uint256).max);

        uint256 stakeAmount = 1000_000000;
        nftStaking.stakeStables(stakeAmount);

        (uint256 stakedAmount,,,,) = stableStaking.stakers(owner);
        assertEq(stakedAmount, stakeAmount);

        vm.stopPrank();
    }

    function testFuzz_MaxBorrow(uint128 x) public view {
        uint256 x256 = (uint256(x) + uint256(2)) * 1e18;
        uint256 maxBorrow = nftStaking.calculateMaxBorrow(x256, START_TIME, START_TIME + YEAR_IN_SECONDS);
        uint256 diff = 0;
        uint256 borrow_debt = maxBorrow * PROTOCOL_YIELD / UNIT;
        if ((x256 - borrow_debt) >= maxBorrow) {
            diff = (x256 - borrow_debt) - maxBorrow;
        } else {
            diff = maxBorrow - (x256 - borrow_debt);
        }

        assertGt(maxBorrow / 5e16, diff);
    }

    function testFuzz_MaxBorrow_2years(uint128 x) public view {
        uint256 x256 = (uint256(x) + uint256(2)) * 1e18;
        uint256 maxBorrow = nftStaking.calculateMaxBorrow(x256, START_TIME, START_TIME + 2 * YEAR_IN_SECONDS);
        uint256 diff = 0;
        uint256 first_year_debt = maxBorrow * PROTOCOL_YIELD / UNIT;
        uint256 second_year_debt = (first_year_debt + maxBorrow) * PROTOCOL_YIELD / UNIT;

        if ((x256 - first_year_debt - second_year_debt) >= maxBorrow) {
            diff = (x256 - first_year_debt - second_year_debt) - maxBorrow;
        } else {
            diff = maxBorrow - (x256 - first_year_debt - second_year_debt);
        }

        assertGt(maxBorrow / 5e16, diff);
    }

    function testFuzz_Debt(uint128 x) public view {
        uint256 x256 = (uint256(x) + uint256(2)) * 1e18;
        uint256 debt = nftStaking.calculateDebt(x256, START_TIME, START_TIME + YEAR_IN_SECONDS);
        uint256 diff = 0;
        if ((x256 + x256 * PROTOCOL_YIELD / UNIT) >= debt) {
            diff = (x256 + x256 * PROTOCOL_YIELD / UNIT) - debt;
        } else {
            diff = debt - (x256 + x256 * PROTOCOL_YIELD / UNIT);
        }

        assertGt(debt / 3e16, diff);
    }

    function testFuzz_Debt_2years(uint128 x) public view {
        uint256 x256 = (uint256(x) + uint256(2)) * 1e18;
        uint256 debt = nftStaking.calculateDebt(x256, START_TIME, START_TIME + 2 * YEAR_IN_SECONDS);
        uint256 diff = 0;
        uint256 first_year_debt = x256 + x256 * PROTOCOL_YIELD / UNIT;
        uint256 second_year_debt = first_year_debt + first_year_debt * PROTOCOL_YIELD / UNIT;
        if (second_year_debt >= debt) {
            diff = second_year_debt - debt;
        } else {
            diff = debt - second_year_debt;
        }

        assertGt(debt / 3e16, diff);
    }

    function testFuzz_MaxBorrow_1month(uint128 x) public view {
        uint256 x256 = (uint256(x) + uint256(2)) * 1e18;
        uint256 month_in_seconds = YEAR_IN_SECONDS / 12;
        uint256 month_yield = 9488792934583 * UNIT / (BIPS * 1e11); // (1.12)**(1/12)
        uint256 maxBorrow = nftStaking.calculateMaxBorrow(x256, START_TIME, START_TIME + month_in_seconds);
        uint256 diff = 0;
        uint256 month_debt = maxBorrow * month_yield / UNIT;

        if ((x256 - month_debt) >= maxBorrow) {
            diff = (x256 - month_debt) - maxBorrow;
        } else {
            diff = maxBorrow - (x256 - month_debt);
        }

        assertGt(maxBorrow / 1e16, diff);
    }

    function testFuzz_MaxBorrow_2months(uint128 x) public view {
        uint256 x256 = (uint256(x) + uint256(2)) * 1e18;
        uint256 month_in_seconds = YEAR_IN_SECONDS / 12;
        uint256 month_yield = 9488792934583 * UNIT / (BIPS * 1e11); // (1.12)**(1/12)
        uint256 maxBorrow = nftStaking.calculateMaxBorrow(x256, START_TIME, START_TIME + 2 * month_in_seconds);
        uint256 diff = 0;
        uint256 first_month_debt = maxBorrow * month_yield / UNIT;
        uint256 second_month_debt = (maxBorrow + first_month_debt) * month_yield / UNIT;

        if ((x256 - first_month_debt - second_month_debt) >= maxBorrow) {
            diff = (x256 - first_month_debt - second_month_debt) - maxBorrow;
        } else {
            diff = maxBorrow - (x256 - first_month_debt - second_month_debt);
        }

        assertGt(maxBorrow / 1e16, diff);
    }

    function testFuzz_Debt_1month(uint128 x) public view {
        uint256 x256 = (uint256(x) + uint256(2)) * 1e18;
        uint256 month_in_seconds = YEAR_IN_SECONDS / 12;
        uint256 month_yield = 9488792934583 * UNIT / (BIPS * 1e11); // (1.12)**(1/12)
        uint256 debt = nftStaking.calculateDebt(x256, START_TIME, START_TIME + month_in_seconds);
        uint256 diff = 0;
        uint256 first_month_debt = x256 + x256 * month_yield / UNIT;
        if (first_month_debt >= debt) {
            diff = first_month_debt - debt;
        } else {
            diff = debt - first_month_debt;
        }

        assertGt(debt / 1e16, diff);
    }

    function testFuzz_Debt_2month(uint128 x) public view {
        uint256 x256 = (uint256(x) + uint256(2)) * 1e18;
        uint256 month_in_seconds = YEAR_IN_SECONDS / 12;
        uint256 month_yield = 9488792934583 * UNIT / (BIPS * 1e11); // (1.12)**(1/12)
        uint256 debt = nftStaking.calculateDebt(x256, START_TIME, START_TIME + 2 * month_in_seconds);
        uint256 diff = 0;
        uint256 first_month_debt = x256 + x256 * month_yield / UNIT;
        uint256 second_month_debt = first_month_debt + first_month_debt * month_yield / UNIT;
        if (second_month_debt >= debt) {
            diff = second_month_debt - debt;
        } else {
            diff = debt - second_month_debt;
        }

        assertGt(debt / 1e16, diff);
    }
}