// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {NFTStakingAndBorrowing} from "../src/NFTStakingAndBorrowing.sol";
import {StableBondCoins} from "../src/StableBondCoins.sol";
import {BondNFT} from "../src/BondNFT.sol";

contract NFTStakingAndBorrowingTest is Test {
    NFTStakingAndBorrowing public nftStaking;
    BondNFT public bondNFT;
    StableBondCoins public stableBondCoins;
    address public owner;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

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
        bondNFT.mint(owner, 1, 10, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        nftStaking.whitelistNFT(address(bondNFT), true);
        vm.stopPrank();
    }

    function test_stakeNFT() public {
        owner = address(1);
        vm.prank(owner);
        nftStaking.stakeNFT(address(bondNFT), 1, 10);

        NFTStakingAndBorrowing.TotalStats memory totalStats = nftStaking.getTotalStats();

        assertEq(totalStats.staked, 9975_000000);

        NFTStakingAndBorrowing.UserStats memory userStats = nftStaking.getUserStats(owner);

        assertEq(userStats.staked, 9975_000000);
        assertEq(nftStaking.userAvailableToBorrow(owner), 8906_249999);
    }

    function test_borrow() public {
        owner = address(1);

        vm.startPrank(owner);
        nftStaking.stakeNFT(address(bondNFT), 1, 10);
        NFTStakingAndBorrowing.UserStats memory userStats = nftStaking.getUserStats(owner);

        assertEq(userStats.staked, 9975_000000);
        assertEq(nftStaking.userAvailableToBorrow(owner), 8906_249999);

        nftStaking.borrow(500_000000);
        vm.stopPrank();

        userStats = nftStaking.getUserStats(owner);

        assertEq(userStats.borrowed, 500_000000);
        assertEq(nftStaking.userAvailableToBorrow(owner), 8406_249999);

        NFTStakingAndBorrowing.TotalStats memory totalStats = nftStaking.getTotalStats();
        assertEq(totalStats.borrowed, 500_000000);

        vm.roll(12345);
        vm.warp(1 + 30 days);

        userStats = nftStaking.getUserStats(owner);
        totalStats = nftStaking.getTotalStats();
        assertEq(nftStaking.userAvailableToBorrow(owner), 8484_917394);
        assertEq(userStats.debtUpdateTimestamp, 2592001);
        assertEq(totalStats.debt, 504_679101);
        assertEq(userStats.debt, 504_679101);
    }

    function test_staking_over_time() public {
        owner = address(1);
        address client1 = address(2);
        address client2 = address(3);

        vm.startPrank(owner);
        BondNFT.Metadata memory metadata = BondNFT.Metadata({
            value: 1000_000000,
            couponValue: 50_000000,
            issueTimestamp: 1,
            expirationTimestamp: 1 + 31536000,
            ISIN: "US1234567890"
        });
        bondNFT.setMetaData(2, metadata);
        bondNFT.mint(client1, 2, 10, "");
        bondNFT.setMetaData(3, metadata);
        bondNFT.mint(client2, 3, 10, "");
        vm.stopPrank();

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
        assertEq(userStats.nominalAvailable, 898_959645);
        assertEq(userStats.borrowed, 898_959645);
        assertEq(userStats.debt, 898_959645);
        assertEq(nftStaking.userAvailableToBorrow(client1), 0);

        vm.warp(90 days);
        vm.roll(4);

        // Client2 makes some staking
        vm.prank(client2);
        nftStaking.stakeNFT(address(bondNFT), 3, 1);

        userStats = nftStaking.getUserStats(client1);
        assertEq(userStats.debt, 915_863666);
        assertEq(userStats.debtUpdateTimestamp, 90 days);

        userStats = nftStaking.getUserStats(client2);
        totalStats = nftStaking.getTotalStats();

        assertEq(userStats.staked, 997_500000);
        assertEq(totalStats.staked, 2 * 997_500000);
        assertEq(totalStats.debt, 915_863666);
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

        assertEq(userStats1.debt, 924_434504);
        assertEq(userStats2.debt, 924_434504);
        assertEq(totalStats.debt, 2 * 924_434504);
        assertEq(totalStats.borrowed, 915_863666 + 898_959645);
        assertEq(userStats1.debtUpdateTimestamp, 120 days);
        assertEq(userStats2.debtUpdateTimestamp, 120 days);

    }
}
