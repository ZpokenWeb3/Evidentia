// SPDX-License-Identifier: MIT
pragma solidity >=0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {NFTStakingAndBorrowing} from "../src/NFTStakingAndBorrowing.sol";
import {NFTStakingAndBorrowingV2} from "../src/V2/NFTStakingAndBorrowingV2.sol";
import {StableBondCoins} from "../src/StableBondCoins.sol";
import {BondNFT} from "../src/BondNFT.sol";
import {StableCoinsStaking} from "../src/StableCoinsStaking.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

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
    uint256 internal constant PROTOCOL_RATE = 1200 * UNIT / BIPS;

    function setUp() public {
        owner = address(1);
        vm.startPrank(owner);

        // Deploy the contract as a proxy with the initializer
        bondNFT = BondNFT(
            Upgrades.deployUUPSProxy(
                "BondNFT.sol:BondNFT", abi.encodeCall(BondNFT.initialize, (owner, "https://example.com/{id}.json"))
            )
        );

        stableBondCoins = StableBondCoins(
            Upgrades.deployUUPSProxy(
                "StableBondCoins.sol:StableBondCoins",
                abi.encodeCall(stableBondCoins.initialize, (owner, owner, "Stable Bond Coins", "SBC", 6))
            )
        );

        nftStaking = NFTStakingAndBorrowing(
            Upgrades.deployUUPSProxy(
                "NFTStakingAndBorrowing.sol:NFTStakingAndBorrowing",
                abi.encodeCall(NFTStakingAndBorrowing.initialize, (address(stableBondCoins)))
            )
        );

        stableBondCoins.grantRole(MINTER_ROLE, address(nftStaking));
        BondNFT.Metadata memory metadata = BondNFT.Metadata({
            value: 1000_000000,
            couponValue: 50_000000,
            issueTimestamp: 1,
            expirationTimestamp: 1 + YEAR_IN_SECONDS,
            ISIN: "US1234567890"
        });

        bondNFT.setMetaData(1, metadata);
        bondNFT.setMetaData(2, metadata);
        metadata.issueTimestamp = 1 + 45 days;
        metadata.expirationTimestamp = 1 + YEAR_IN_SECONDS + 45 days;
        bondNFT.setMetaData(3, metadata);
        bondNFT.setAllowedMints(owner, 1, 10);
        bondNFT.setAllowedMints(owner, 2, 10);
        bondNFT.setAllowedMints(owner, 3, 10);
        bondNFT.mint(1, 10, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        nftStaking.whitelistNFT(address(bondNFT), true);
        nftStaking.setProtocolFee(0);
        vm.stopPrank();
    }

    function testStakeNFT() public {
        owner = address(1);
        vm.prank(owner);
        nftStaking.stakeNFT(address(bondNFT), 1, 10);
        console.log("address(this):", address(this));
        assertEq(stableBondCoins.balanceOf(address(nftStaking)), 9975_000000);

        NFTStakingAndBorrowing.TotalStats memory totalStats = nftStaking.getTotalStats();

        assertEq(totalStats.staked, 9975_000000);

        NFTStakingAndBorrowing.UserStats memory userStats = nftStaking.getUserStats(owner);

        assertEq(userStats.staked, 9975_000000);
        assertApproxEqRel(nftStaking.userAvailableToBorrow(owner), 8906_250000, 0.001e18);
    }

    function testBorrow() public {
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
        assertEq(totalStats.debt, 504_679102);
        assertEq(userStats.debt, 504_679102);
    }

    function testRepay() public {
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
        assertEq(userStats.nominalAvailable, 8989_596465);
        assertEq(userStats.borrowed, 0);
        assertEq(userStats.debt, 0);
        assertEq(8989_596464 + 3 - nftStaking.userAvailableToBorrow(client1) < 5, true);
    }

    function testSmallAmounts() public {
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
        assertEq(totalStats.debt, 11);
        assertEq(userStats.debt, 11);
    }

    function testStakingOverTime() public {
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
        assertEq(userStats.debt, 915863668);
        assertEq(userStats.debtUpdateTimestamp, 90 days);

        userStats = nftStaking.getUserStats(client2);
        totalStats = nftStaking.getTotalStats();

        assertEq(userStats.staked, 997_500000);
        assertEq(totalStats.staked, 2 * 997_500000);
        assertEq(totalStats.debt, 915863668);
        assertEq(userStats.debtUpdateTimestamp, 90 days);
        assertEq(totalStats.debtUpdateTimestamp, 90 days);
        assertEq(userStats.nominalAvailable, 903_156174);
        assertEq(nftStaking.userAvailableToBorrow(client2), 903_156174);
        assertEq(nftStaking.userAvailableToBorrow(client1), 0);

        // Client2 borrows everything available
        vm.prank(client2);
        nftStaking.borrow(0);

        vm.warp(120 days);
        vm.roll(5);

        NFTStakingAndBorrowing.UserStats memory userStats1 = nftStaking.getUserStats(client1);
        NFTStakingAndBorrowing.UserStats memory userStats2 = nftStaking.getUserStats(client2);
        totalStats = nftStaking.getTotalStats();

        assertEq(userStats1.debt, 924434506);
        assertEq(userStats2.debt, 911608093);
        assertEq(totalStats.debt, 1836042600);
        assertEq(totalStats.borrowed, 903_156174 + 898_959646);
        assertEq(userStats1.debtUpdateTimestamp, 120 days);
        assertEq(userStats2.debtUpdateTimestamp, 120 days);
    }

    function testUnstake() public {
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
        uint256 borrowAmount = nftStaking.userAvailableToBorrow(client1) / 2;
        vm.prank(client1);
        nftStaking.borrow(borrowAmount);

        // User unstakes
        console.log("Available to borrow: ", nftStaking.userAvailableToBorrow(client1));
        assertEq(nftStaking.userAvailableToUnstake(client1, address(bondNFT), 2), 5);
        vm.prank(client1);
        nftStaking.unstakeNFT(address(bondNFT), 2, 4);

        userStats = nftStaking.getUserStats(client1);
        assertEq(userStats.staked, 6 * 9975_000000 / 10);
        assertLe(nftStaking.userAvailableToBorrow(client1), borrowAmount);
    }

    function testUnstakeCase02() public {
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

        uint256 borrowAmount = nftStaking.userAvailableToBorrow(client1);
        nftStaking.borrow(borrowAmount - 10);
        assertEq(nftStaking.userAvailableToUnstake(client1, address(bondNFT), 2), 0);

        nftStaking.stakeNFT(address(bondNFT), 3, 10);
        assertEq(nftStaking.userAvailableToUnstake(client1, address(bondNFT), 2), 9);
        assertEq(nftStaking.userAvailableToUnstake(client1, address(bondNFT), 3), 10);

        nftStaking.unstakeNFT(address(bondNFT), 2, 9);
        assertEq(nftStaking.userAvailableToUnstake(client1, address(bondNFT), 3), 0);
    }

    function testLiquidateCase01() public {
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
        uint256 borrowAmount = nftStaking.userAvailableToBorrow(client1) / 2;
        nftStaking.borrow(borrowAmount);
        assertEq(nftStaking.userAvailableToUnstake(client1, address(bondNFT), 2), 5);
        vm.stopPrank();

        assertEq(stableBondCoins.balanceOf(client1), borrowAmount);
        console.log("Client1 borrowed:", borrowAmount);
        console.log("Stables left:    ", stableBondCoins.balanceOf(address(nftStaking)));
        assertEq(stableBondCoins.balanceOf(address(nftStaking)), 9975_000000 - borrowAmount);
        assert(nftStaking.userAvailableToBorrow(client1) - borrowAmount < 10);

        // we go to the future, 40 days to expiration
        vm.warp(365 days - 40 days);
        vm.roll(2);
        NFTStakingAndBorrowing.UserStats memory userStats = nftStaking.getUserStats(client1);
        assertEq(userStats.borrowed, borrowAmount);
        assertEq(userStats.debt, 4925_940381);

        console.log("Client1 debt:    ", userStats.debt);
        console.log("Client1 Stables: ", stableBondCoins.balanceOf(client1));
        uint256 client1BalanceBefore = stableBondCoins.balanceOf(client1);

        assertEq(bondNFT.balanceOf(client1, 2), 0);
        assertEq(bondNFT.balanceOf(address(nftStaking), 2), 10);
        assertEq(stableBondCoins.balanceOf(client2), 0);

        // Client2 borrows to get stable coins and liquidate
        vm.startPrank(client2);
        nftStaking.stakeNFT(address(bondNFT), 3, 10);
        nftStaking.borrow(0);
        stableBondCoins.approve(address(nftStaking), UINT256_MAX);
        uint256 client2BalanceBefore = stableBondCoins.balanceOf(client2);
        console.log("Client2 Stables: ", stableBondCoins.balanceOf(client2));
        nftStaking.liquidate(address(bondNFT), 2, client1);
        vm.stopPrank();

        console.log("Client1 Stables: ", stableBondCoins.balanceOf(client1));
        console.log("Client2 Stables: ", stableBondCoins.balanceOf(client2));
        console.log("Client1 Gets:    ", stableBondCoins.balanceOf(client1) - client1BalanceBefore);
        console.log("Client2 Pays:    ", client2BalanceBefore - stableBondCoins.balanceOf(client2));

        assertEq(bondNFT.balanceOf(client1, 2), 4);
        assertEq(bondNFT.balanceOf(client2, 2), 6);
        assertEq(bondNFT.balanceOf(address(nftStaking), 2), 0);

        // Check internal mapping state - userNFTs should be 0 as all NFTs are removed from staking
        assertEq(
            nftStaking.getUserNFTBalance(client1, address(bondNFT), 2),
            0,
            "userNFTs balance should be 0 after liquidation as all NFTs are removed from staking"
        );

        assertEq(stableBondCoins.balanceOf(client1), 5438_313075);
        assertEq(stableBondCoins.balanceOf(client2), 3804_058702);
    }

    function testLiquidateCase02() public {
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
        uint256 borrowAmount = nftStaking.userAvailableToBorrow(client1);
        nftStaking.borrow(borrowAmount);
        vm.stopPrank();

        assertEq(stableBondCoins.balanceOf(client1), borrowAmount);
        console.log("Client1 borrowed:", borrowAmount);
        console.log("Stables left:    ", stableBondCoins.balanceOf(address(nftStaking)));
        assertEq(stableBondCoins.balanceOf(address(nftStaking)), 14962_500000 - borrowAmount);
        assert(nftStaking.userAvailableToBorrow(client1) < 10);

        // we go to the future, 40 days to expiration
        vm.warp(365 days - 40 days);
        vm.roll(2);
        NFTStakingAndBorrowing.UserStats memory userStats = nftStaking.getUserStats(client1);
        assertEq(userStats.borrowed, borrowAmount);
        assertEq(userStats.debt, 14777_821143);

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

        // Verify internal mapping state matches expected NFT balance
        assertEq(
            nftStaking.getUserNFTBalance(client1, address(bondNFT), 2),
            0,
            "userNFTs balance incorrect after liquidation"
        );

        assertEq(stableBondCoins.balanceOf(client1), 13359_375000);
        assertEq(stableBondCoins.balanceOf(client2), 9578_493554);
    }

    function testLiquidateCase03() public {
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

        // Client1 stakes NFT and borrows a small amount
        vm.startPrank(client1);
        nftStaking.stakeNFT(address(bondNFT), 2, 10);

        // Borrowing only 1/4 of the available amount so debt will be less than max borrow
        uint256 borrowAmount = nftStaking.userAvailableToBorrow(client1) / 4;
        nftStaking.borrow(borrowAmount);
        vm.stopPrank();

        assertEq(stableBondCoins.balanceOf(client1), borrowAmount);

        // we go to the future, 40 days to expiration
        vm.warp(365 days - 40 days);
        vm.roll(2);

        NFTStakingAndBorrowing.UserStats memory userStats = nftStaking.getUserStats(client1);
        assertEq(userStats.borrowed, borrowAmount);

        // Check that debt has accumulated but is still less than max borrow
        uint256 currentDebt = userStats.debt;
        BondNFT.Metadata memory metadata = bondNFT.getMetaData(2);
        uint256 maxBorrow =
            nftStaking.calculateMaxBorrow(userStats.staked, block.timestamp, metadata.expirationTimestamp);

        assertLt(currentDebt, maxBorrow, "Debt should be less than max borrow for Case 3");

        // Check initial balances
        assertEq(bondNFT.balanceOf(client1, 2), 0);
        assertEq(bondNFT.balanceOf(address(nftStaking), 2), 10);
        assertEq(stableBondCoins.balanceOf(client2), 0);

        // Calculate how many NFTs liquidator should receive
        uint256 expectedNFTToLiquidator = (currentDebt * 10 / maxBorrow) + (currentDebt * 10 % maxBorrow == 0 ? 0 : 1);
        uint256 expectedNFTToOwner = 10 - expectedNFTToLiquidator;

        // Client2 prepares and liquidates
        vm.startPrank(client2);
        nftStaking.stakeNFT(address(bondNFT), 3, 10);
        nftStaking.borrow(0);
        stableBondCoins.approve(address(nftStaking), type(uint256).max);

        uint256 client2BalanceBefore = stableBondCoins.balanceOf(client2);
        uint256 client1BalanceBefore = stableBondCoins.balanceOf(client1);

        nftStaking.liquidate(address(bondNFT), 2, client1);
        vm.stopPrank();

        // Verify balances after liquidation
        assertEq(bondNFT.balanceOf(client1, 2), expectedNFTToOwner, "Original owner should receive remaining NFTs");
        assertEq(bondNFT.balanceOf(client2, 2), expectedNFTToLiquidator, "Liquidator should receive proportional NFTs");
        assertEq(bondNFT.balanceOf(address(nftStaking), 2), 0, "Contract should have no NFTs left");

        // Check internal mapping state - userNFTs should be 0 as all NFTs are removed from staking
        assertEq(
            nftStaking.getUserNFTBalance(client1, address(bondNFT), 2),
            0,
            "userNFTs balance should be 0 after liquidation as all NFTs are removed from staking"
        );

        // Verify that client1 received excess payment (liquidationPayment - debt)
        assertGt(
            stableBondCoins.balanceOf(client1), client1BalanceBefore, "Position owner should receive excess payment"
        );

        // Verify client2 paid for the liquidation
        assertLt(stableBondCoins.balanceOf(client2), client2BalanceBefore, "Liquidator should pay for liquidation");

        // Verify client1's debt is cleared
        userStats = nftStaking.getUserStats(client1);
        assertEq(userStats.debt, 0, "Debt should be cleared after liquidation");
    }

    /**
     * @notice Test to specifically verify the token burning behavior during partial liquidation (Case 3).
     * This test ensures that the entire position value is burned, not just the value of the liquidated NFTs.
     * This is because all NFTs are removed from staking (some go to liquidator, some to owner).
     */
    function testLiquidateCase03TokenBurning() public {
        owner = address(1);
        address client1 = address(2);
        address client2 = address(3);

        // Setup test environment
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

        // Client1 stakes NFT and borrows a small amount
        vm.startPrank(client1);
        nftStaking.stakeNFT(address(bondNFT), 2, 10);
        uint256 borrowAmount = nftStaking.userAvailableToBorrow(client1) / 4;
        nftStaking.borrow(borrowAmount);
        vm.stopPrank();

        // Go to the future, 40 days to expiration
        vm.warp(365 days - 40 days);
        vm.roll(2);

        // Get current state
        NFTStakingAndBorrowing.UserStats memory userStats = nftStaking.getUserStats(client1);
        uint256 currentDebt = userStats.debt;
        BondNFT.Metadata memory metadata = bondNFT.getMetaData(2);
        uint256 maxBorrow =
            nftStaking.calculateMaxBorrow(userStats.staked, block.timestamp, metadata.expirationTimestamp);

        // Calculate how many NFTs liquidator should receive
        uint256 expectedNFTToLiquidator = (currentDebt * 10 / maxBorrow) + (currentDebt * 10 % maxBorrow == 0 ? 0 : 1);

        // Calculate the value of the NFTs to be liquidated (this is what should be burned)
        uint256 liquidatedValue =
            (metadata.value + metadata.couponValue) * expectedNFTToLiquidator * (UNIT - 500 * UNIT / BIPS) / UNIT;

        // Calculate the total position value (this is what would be burned with the bug)
        uint256 totalPositionValue = (metadata.value + metadata.couponValue) * 10 * (UNIT - 500 * UNIT / BIPS) / UNIT;

        // Verify that we're doing a partial liquidation (Case 3)
        assertLt(liquidatedValue, totalPositionValue, "This should be a partial liquidation");

        // Client2 prepares for liquidation
        vm.startPrank(client2);
        nftStaking.stakeNFT(address(bondNFT), 3, 10);
        nftStaking.borrow(0);
        stableBondCoins.approve(address(nftStaking), type(uint256).max);

        // Record total supply before liquidation
        uint256 totalSupplyBefore = stableBondCoins.totalSupply();

        // Execute liquidation
        nftStaking.liquidate(address(bondNFT), 2, client1);
        vm.stopPrank();

        // Record total supply after liquidation and calculate burned tokens
        uint256 totalSupplyAfter = stableBondCoins.totalSupply();
        uint256 tokensBurned = totalSupplyBefore - totalSupplyAfter;

        // Verify token burning behavior - we burn the total position value
        assertEq(tokensBurned, totalPositionValue, "The total position value should be burned");
        assertGt(tokensBurned, liquidatedValue, "Burned amount should be greater than just liquidated value");
    }

    function testGetRewardAmount() public {
        vm.startPrank(owner);
        StableCoinsStaking stableStaking = new StableCoinsStaking();
        stableStaking.initialize(address(stableBondCoins), address(nftStaking), address(owner));
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
        uint256 claimedRewards = nftStaking.transferRewards();

        assertEq(claimedRewards, rewardAmount);
        assertEq(nftStaking.getRewardAmount(), 0);
    }

    function testEdgeCases() public {
        // Test for small amounts
        vm.startPrank(owner);
        nftStaking.stakeNFT(address(bondNFT), 1, 1);

        // Borrow a very small amount (1)
        uint256 initialBorrow = 1;
        nftStaking.borrow(initialBorrow);

        assertEq(stableBondCoins.balanceOf(owner), initialBorrow);

        vm.warp(30 days);

        // Repay all debt
        stableBondCoins.mint(owner, 1_000000);
        stableBondCoins.approve(address(nftStaking), 1_000000);
        nftStaking.repay(0); // full debt

        NFTStakingAndBorrowing.UserStats memory userStats = nftStaking.getUserStats(owner);
        assertEq(userStats.debt, 0);

        vm.stopPrank();
    }

    function testStakeNFTAndStables() public {
        vm.startPrank(owner);
        StableCoinsStaking stableStaking = new StableCoinsStaking();
        stableStaking.initialize(address(stableBondCoins), address(nftStaking), address(owner));
        nftStaking.setStablesStakingAddress(address(stableStaking));
        vm.stopPrank();

        vm.startPrank(owner);
        nftStaking.stakeNFT(address(bondNFT), 1, 5);

        stableBondCoins.approve(address(nftStaking), type(uint256).max);
        nftStaking.stakeNFTandStables(address(bondNFT), 1, 5);

        uint256 stakedAmount = stableStaking.stakers(owner).stakedAmount;
        assertGt(stakedAmount, 0, "Staked amount should be > 0");

        vm.stopPrank();
    }

    function testStakeStablesWithAmount() public {
        vm.startPrank(owner);
        StableCoinsStaking stableStaking = new StableCoinsStaking();
        stableStaking.initialize(address(stableBondCoins), address(nftStaking), address(owner));
        nftStaking.setStablesStakingAddress(address(stableStaking));
        vm.stopPrank();

        vm.startPrank(owner);
        nftStaking.stakeNFT(address(bondNFT), 1, 10);

        stableBondCoins.approve(address(nftStaking), type(uint256).max);

        uint256 stakeAmount = 1000_000000;
        nftStaking.stakeStables(stakeAmount);

        uint256 stakedAmount = stableStaking.stakers(owner).stakedAmount;
        assertEq(stakedAmount, stakeAmount);

        vm.stopPrank();
    }

    function testFuzzMaxBorrow(uint128 x) public view {
        uint256 x256 = (uint256(x) + uint256(2)) * 1e18;
        uint256 maxBorrow = nftStaking.calculateMaxBorrow(x256, START_TIME, START_TIME + YEAR_IN_SECONDS);
        uint256 diff = 0;
        uint256 borrowDebt = maxBorrow * PROTOCOL_RATE / UNIT;
        if ((x256 - borrowDebt) >= maxBorrow) {
            diff = (x256 - borrowDebt) - maxBorrow;
        } else {
            diff = maxBorrow - (x256 - borrowDebt);
        }

        assertGt(maxBorrow / 5e16, diff);
    }

    function testFuzzMaxBorrow2Years(uint128 x) public view {
        uint256 x256 = (uint256(x) + uint256(2)) * 1e18;
        uint256 maxBorrow = nftStaking.calculateMaxBorrow(x256, START_TIME, START_TIME + 2 * YEAR_IN_SECONDS);
        uint256 diff = 0;
        uint256 firstYearDebt = maxBorrow * PROTOCOL_RATE / UNIT;
        uint256 secondYearDebt = (firstYearDebt + maxBorrow) * PROTOCOL_RATE / UNIT;

        if ((x256 - firstYearDebt - secondYearDebt) >= maxBorrow) {
            diff = (x256 - firstYearDebt - secondYearDebt) - maxBorrow;
        } else {
            diff = maxBorrow - (x256 - firstYearDebt - secondYearDebt);
        }

        assertGt(maxBorrow / 5e16, diff);
    }

    function testFuzzDebt(uint128 x) public view {
        uint256 x256 = (uint256(x) + uint256(2)) * 1e18;
        uint256 debt = nftStaking.calculateDebt(x256, START_TIME, START_TIME + YEAR_IN_SECONDS);
        uint256 diff = 0;
        if ((x256 + x256 * PROTOCOL_RATE / UNIT) >= debt) {
            diff = (x256 + x256 * PROTOCOL_RATE / UNIT) - debt;
        } else {
            diff = debt - (x256 + x256 * PROTOCOL_RATE / UNIT);
        }

        assertGt(debt / 3e16, diff);
    }

    function testFuzzDebt2Years(uint128 x) public view {
        uint256 x256 = (uint256(x) + uint256(2)) * 1e18;
        uint256 debt = nftStaking.calculateDebt(x256, START_TIME, START_TIME + 2 * YEAR_IN_SECONDS);
        uint256 diff = 0;
        uint256 firstYearDebt = x256 + x256 * PROTOCOL_RATE / UNIT;
        uint256 secondYearDebt = firstYearDebt + firstYearDebt * PROTOCOL_RATE / UNIT;
        if (secondYearDebt >= debt) {
            diff = secondYearDebt - debt;
        } else {
            diff = debt - secondYearDebt;
        }

        assertGt(debt / 3e16, diff);
    }

    function testFuzzDebtVariableInterval(uint128 x, uint32 intervalInSeconds) public view {
        uint256 x256 = (uint256(x) + uint256(2)) * 1e18;

        // Bound interval to reasonable values (0 to 10 years to avoid overflow)
        uint256 maxInterval = 10 * YEAR_IN_SECONDS;
        uint256 boundedInterval = bound(intervalInSeconds, 0, maxInterval);
        uint256 diff = 0;
        uint256 debt;

        // If fromTime >= toTime, debt should equal input amount
        if (boundedInterval == 0) {
            debt = nftStaking.calculateDebt(x256, START_TIME, START_TIME);

            if (x256 >= debt) {
                diff = x256 - debt;
            } else {
                diff = debt - x256;
            }

            assertGt(debt / 7e16, diff, "Debt should equal input amount for zero interval");
            return;
        }

        debt = nftStaking.calculateDebt(x256, START_TIME, START_TIME + boundedInterval);

        // Linear approximation for comparison
        // Linear debt = principal + (principal * protocolRate * time / YEAR_IN_SECONDS)
        uint256 linearDebt = x256 + (x256 / UNIT) * PROTOCOL_RATE * boundedInterval / YEAR_IN_SECONDS;

        assertGe(debt, linearDebt / 1e18, "Debt should be at least as large as linear approximation");
        assertGt(debt, x256 / 1e18, "Debt should increase over time");
    }

    function testFuzzMaxBorrowVariableInterval(uint128 x, uint32 intervalInSeconds) public view {
        uint256 x256 = (uint256(x) + uint256(2)) * 1e18;

        // Bound interval to reasonable values (0 to 10 years to avoid overflow)
        uint256 maxInterval = 10 * YEAR_IN_SECONDS;
        uint256 boundedInterval = bound(intervalInSeconds, 0, maxInterval);
        uint256 maxBorrow;

        // If fromTime >= toTime, maxBorrow should be 0
        if (boundedInterval == 0) {
            maxBorrow = nftStaking.calculateMaxBorrow(x256, START_TIME, START_TIME);
            assertEq(maxBorrow, 0, "Max borrow should be zero for zero interval");
            return;
        }

        maxBorrow = nftStaking.calculateMaxBorrow(x256, START_TIME, START_TIME + boundedInterval);
        uint256 debt = nftStaking.calculateDebt(maxBorrow, START_TIME, START_TIME + boundedInterval);

        assertGe(maxBorrow + debt, x256, "Max borrow plus debt should be less than input amount");
        assertLe(maxBorrow, x256, "Max borrow should not exceed input amount");
        assertGt(maxBorrow, 0, "Max borrow should be positive for non-zero interval");
    }

    function testFuzzMaxBorrow1Month(uint128 x) public view {
        uint256 x256 = (uint256(x) + uint256(2)) * 1e18;
        uint256 monthInSeconds = YEAR_IN_SECONDS / 12;
        uint256 monthRate = 9488792934583 * UNIT / (BIPS * 1e11); // (1.12)**(1/12)
        uint256 maxBorrow = nftStaking.calculateMaxBorrow(x256, START_TIME, START_TIME + monthInSeconds);
        uint256 diff = 0;
        uint256 monthDebt = maxBorrow * monthRate / UNIT;

        if ((x256 - monthDebt) >= maxBorrow) {
            diff = (x256 - monthDebt) - maxBorrow;
        } else {
            diff = maxBorrow - (x256 - monthDebt);
        }

        assertGt(maxBorrow / 1e16, diff);
    }

    function testFuzzMaxBorrow2Months(uint128 x) public view {
        uint256 x256 = (uint256(x) + uint256(2)) * 1e18;
        uint256 monthInSeconds = YEAR_IN_SECONDS / 12;
        uint256 monthRate = 9488792934583 * UNIT / (BIPS * 1e11); // (1.12)**(1/12)
        uint256 maxBorrow = nftStaking.calculateMaxBorrow(x256, START_TIME, START_TIME + 2 * monthInSeconds);
        uint256 diff = 0;
        uint256 firstMonthDebt = maxBorrow * monthRate / UNIT;
        uint256 secondMonthDebt = (maxBorrow + firstMonthDebt) * monthRate / UNIT;

        if ((x256 - firstMonthDebt - secondMonthDebt) >= maxBorrow) {
            diff = (x256 - firstMonthDebt - secondMonthDebt) - maxBorrow;
        } else {
            diff = maxBorrow - (x256 - firstMonthDebt - secondMonthDebt);
        }

        assertGt(maxBorrow / 1e16, diff);
    }

    function testFuzzDebt1Month(uint128 x) public view {
        uint256 x256 = (uint256(x) + uint256(2)) * 1e18;
        uint256 monthInSeconds = YEAR_IN_SECONDS / 12;
        uint256 monthRate = 9488792934583 * UNIT / (BIPS * 1e11); // (1.12)**(1/12)
        uint256 debt = nftStaking.calculateDebt(x256, START_TIME, START_TIME + monthInSeconds);
        uint256 diff = 0;
        uint256 firstMonthDebt = x256 + x256 * monthRate / UNIT;
        if (firstMonthDebt >= debt) {
            diff = firstMonthDebt - debt;
        } else {
            diff = debt - firstMonthDebt;
        }

        assertGt(debt / 1e16, diff);
    }

    function testFuzzDebt2Month(uint128 x) public view {
        uint256 x256 = (uint256(x) + uint256(2)) * 1e18;
        uint256 monthInSeconds = YEAR_IN_SECONDS / 12;
        uint256 monthRate = 9488792934583 * UNIT / (BIPS * 1e11); // (1.12)**(1/12)
        uint256 debt = nftStaking.calculateDebt(x256, START_TIME, START_TIME + 2 * monthInSeconds);
        uint256 diff = 0;
        uint256 firstMonthDebt = x256 + x256 * monthRate / UNIT;
        uint256 secondMonthDebt = firstMonthDebt + firstMonthDebt * monthRate / UNIT;
        if (secondMonthDebt >= debt) {
            diff = secondMonthDebt - debt;
        } else {
            diff = debt - secondMonthDebt;
        }

        assertGt(debt / 1e16, diff);
    }

    function testTotalBorrowForManyUsers() public {
        owner = address(1);
        uint256 numberOfUsers = 100;

        vm.roll(1);
        vm.warp(1);

        for (uint256 i = 0; i < numberOfUsers; i++) {
            address client = address(uint160(i + 1000));
            vm.prank(owner);
            bondNFT.setAllowedMints(client, 1, 10);

            vm.startPrank(client);
            bondNFT.mint(1, 10, "");
            bondNFT.setApprovalForAll(address(nftStaking), true);
            nftStaking.stakeNFT(address(bondNFT), 1, 10);
            nftStaking.borrow(0);
            vm.stopPrank();
        }

        NFTStakingAndBorrowing.TotalStats memory totalStats = nftStaking.getTotalStats();
        assertEq(totalStats.staked, numberOfUsers * 9_975_000000);
        assertEq(totalStats.borrowed, numberOfUsers * 8_906_250000);
        assertEq(totalStats.debt, numberOfUsers * 8_906_250000);

        vm.roll(12345);
        vm.warp(1 + YEAR_IN_SECONDS);

        totalStats = nftStaking.getTotalStats();
        assertEq(totalStats.staked, numberOfUsers * 9_975_000000);
        assertEq(totalStats.borrowed, numberOfUsers * 8_906_250000);
        assertEq(totalStats.debt, numberOfUsers * 9_975_000000);

        // Sum of the Debt per each user
        NFTStakingAndBorrowing.UserStats memory userStats;
        uint256 totalUserDebt;
        for (uint256 i = 0; i < numberOfUsers; i++) {
            address client = address(uint160(i + 1000));
            userStats = nftStaking.getUserStats(client);
            totalUserDebt += userStats.debt;
        }
        assertEq(totalStats.debt, totalUserDebt, "Debt should be equal to the sum of the Debt per each user");
    }

    function testCalculateMaxBorrowShouldReturnZero() public view {
        // fromTime > toTime
        assertEq(nftStaking.calculateMaxBorrow(1000, 1000, 900), 0);
    }

    function testGetUserNFTBalance() public {
        // Arrange: Setup NFT staking for testing
        vm.startPrank(owner);
        bondNFT.setAllowedMints(owner, 1, 20);
        vm.stopPrank();

        vm.startPrank(owner);
        bondNFT.mint(1, 10, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);

        // Initial balance should be 0
        assertEq(nftStaking.getUserNFTBalance(owner, address(bondNFT), 1), 0);

        // Stake 5 NFTs
        nftStaking.stakeNFT(address(bondNFT), 1, 5);

        // Balance should be 5
        assertEq(nftStaking.getUserNFTBalance(owner, address(bondNFT), 1), 5);

        // Stake 3 more NFTs
        nftStaking.stakeNFT(address(bondNFT), 1, 3);

        // Balance should be 8
        assertEq(nftStaking.getUserNFTBalance(owner, address(bondNFT), 1), 8);

        // Unstake 2 NFTs
        nftStaking.unstakeNFT(address(bondNFT), 1, 2);

        // Balance should be 6
        assertEq(nftStaking.getUserNFTBalance(owner, address(bondNFT), 1), 6);
        vm.stopPrank();

        // Different user should have 0 balance
        assertEq(nftStaking.getUserNFTBalance(address(42), address(bondNFT), 1), 0);
    }

    function testTransferRewardsWithZeroReward() public {
        vm.startPrank(owner);
        StableCoinsStaking stableStaking = new StableCoinsStaking();
        stableStaking.initialize(address(stableBondCoins), address(nftStaking), address(owner));
        nftStaking.setStablesStakingAddress(address(stableStaking));

        nftStaking.stakeNFT(address(bondNFT), 1, 1);
        nftStaking.borrow(1);

        stableBondCoins.approve(address(nftStaking), 1);
        nftStaking.repay(1);
        vm.stopPrank();

        vm.prank(address(stableStaking));
        uint256 rewardAmount = nftStaking.transferRewards();

        // Should be 0 since debt is 0
        assertEq(rewardAmount, 0);
    }

    function testTransferRewardsAfterMultipleCalls() public {
        vm.startPrank(owner);
        StableCoinsStaking stableStaking = new StableCoinsStaking();
        stableStaking.initialize(address(stableBondCoins), address(nftStaking), address(owner));
        nftStaking.setStablesStakingAddress(address(stableStaking));

        // Stake and borrow to accumulate debt
        nftStaking.stakeNFT(address(bondNFT), 1, 5);
        nftStaking.borrow(1000_000000);
        vm.stopPrank();

        // Fast forward time to accumulate interest
        vm.warp(30 days);

        // First call to transferRewards
        vm.prank(address(stableStaking));
        uint256 firstReward = nftStaking.transferRewards();
        assertGt(firstReward, 0);

        // RewardsTransfered should be updated, so getRewardAmount should return 0
        assertEq(nftStaking.getRewardAmount(), 0);

        // Fast forward time to accumulate more interest
        vm.warp(block.timestamp + 30 days);

        // Second call to transferRewards should return new rewards only
        vm.prank(address(stableStaking));
        uint256 secondReward = nftStaking.transferRewards();
        assertGt(secondReward, 0);

        // Ensure first and second rewards are different
        assertNotEq(firstReward, secondReward);
    }

    function testTransferRewardsWithRecentUpdate() public {
        StableCoinsStaking stableStaking;

        vm.startPrank(owner);
        stableStaking = new StableCoinsStaking();
        stableStaking.initialize(address(stableBondCoins), address(nftStaking), address(owner));
        nftStaking.setStablesStakingAddress(address(stableStaking));

        nftStaking.stakeNFT(address(bondNFT), 1, 5);
        nftStaking.borrow(1000_000000);

        // Call that updates totalStats.debtUpdateTimestamp to current block timestamp
        nftStaking.borrow(0);
        vm.stopPrank();

        // Test transferRewards when debtUpdateTimestamp equals block.timestamp
        vm.prank(address(stableStaking));
        uint256 rewardAmount = nftStaking.transferRewards();

        // Should be 0 since debt was just updated
        assertEq(rewardAmount, 0);
    }

    function testUserAvailableToBorrowWithZeroNominalAvailable() public view {
        address testUser = address(42);

        uint256 available = nftStaking.userAvailableToBorrow(testUser);
        assertEq(available, 0);
    }

    function testUserAvailableToBorrowWithZeroDebt() public {
        vm.startPrank(owner);
        nftStaking.stakeNFT(address(bondNFT), 1, 1);

        uint256 available = nftStaking.userAvailableToBorrow(owner);
        assertGt(available, 0);
        vm.stopPrank();
    }

    function testUserAvailableToUnstakeWithVariousConditions() public {
        vm.startPrank(owner);

        // Case 1: No staked NFTs
        assertEq(nftStaking.userAvailableToUnstake(owner, address(bondNFT), 1), 0);

        // Case 2: Has staked, no debt
        nftStaking.stakeNFT(address(bondNFT), 1, 5);
        assertEq(nftStaking.userAvailableToUnstake(owner, address(bondNFT), 1), 5);

        // Case 3: Has staked, has debt, enough collateral
        nftStaking.borrow(1000_000000);
        assertGt(nftStaking.userAvailableToUnstake(owner, address(bondNFT), 1), 0);

        // Case 4: Has staked, has debt, nominalAvailable <= debt
        nftStaking.borrow(0); // Borrow max available
        assertEq(nftStaking.userAvailableToUnstake(owner, address(bondNFT), 1), 0);

        vm.stopPrank();
    }

    function testAdminFunctions() public {
        vm.startPrank(owner);

        // Initial values
        uint256 initialProtocolRate = 1200; // 12% in BPS
        uint256 initialSafetyFee = 500; // 5% in BPS
        uint256 initialLiquidationTimeWindow = 45 days;

        // Check initial values
        assertEq(nftStaking.getProtocolRate(), initialProtocolRate * 1e18 / 1e4);
        assertEq(nftStaking.getSafetyFee(), initialSafetyFee * 1e18 / 1e4);
        assertEq(nftStaking.getLiquidationTimeWindow(), initialLiquidationTimeWindow);

        // Change values
        uint256 newProtocolRate = 1000; // 10% in BPS
        uint256 newSafetyFee = 300; // 3% in BPS
        uint256 newLiquidationTimeWindow = 30 days;

        nftStaking.setProtocolRate(newProtocolRate);
        nftStaking.setSafetyFee(newSafetyFee);
        nftStaking.setLiquidationTimeWindow(newLiquidationTimeWindow);

        // Check updated values
        assertEq(nftStaking.getProtocolRate(), newProtocolRate * 1e18 / 1e4);
        assertEq(nftStaking.getSafetyFee(), newSafetyFee * 1e18 / 1e4);
        assertEq(nftStaking.getLiquidationTimeWindow(), newLiquidationTimeWindow);

        vm.stopPrank();
    }

    function testRepayPartialBorrowedAmount() public {
        owner = address(1);
        address client1 = address(2);

        vm.startPrank(owner);
        bondNFT.setAllowedMints(client1, 2, 10);
        vm.stopPrank();

        vm.prank(client1);
        bondNFT.mint(2, 10, "");

        vm.prank(client1);
        bondNFT.setApprovalForAll(address(nftStaking), true);

        vm.startPrank(client1);
        nftStaking.stakeNFT(address(bondNFT), 2, 10);

        uint256 borrowAmount = 5000_000000;
        nftStaking.borrow(borrowAmount);

        NFTStakingAndBorrowing.UserStats memory statsBefore = nftStaking.getUserStats(client1);
        assertEq(statsBefore.borrowed, borrowAmount);

        // Repay part of the debt (less than borrowed)
        uint256 repayAmount = borrowAmount / 2;
        stableBondCoins.approve(address(nftStaking), repayAmount);
        nftStaking.repay(repayAmount);

        NFTStakingAndBorrowing.UserStats memory statsAfter = nftStaking.getUserStats(client1);
        assertEq(statsAfter.borrowed, borrowAmount - repayAmount);
        assertEq(statsAfter.debt, statsBefore.debt - repayAmount);

        vm.stopPrank();
    }

    function testStakeStablesExceedLimit() public {
        vm.startPrank(owner);
        StableCoinsStaking stableStaking = new StableCoinsStaking();
        stableStaking.initialize(address(stableBondCoins), address(nftStaking), address(owner));
        nftStaking.setStablesStakingAddress(address(stableStaking));

        nftStaking.stakeNFT(address(bondNFT), 1, 1);

        uint256 availableToBorrow = nftStaking.userAvailableToBorrow(owner);

        // Try to stake more than available limit
        uint256 excessiveAmount = availableToBorrow + 1000;

        vm.expectRevert();
        nftStaking.stakeStables(excessiveAmount);

        vm.stopPrank();
    }

    function testNameSpace() public pure {
        assertEq(
            keccak256(abi.encode(uint256(keccak256("NFTStakingAndBorrowing.storage")) - 1)) & ~bytes32(uint256(0xff)),
            0x6a441442997d548c1da10218ea0e91c439ff7c57f962abbe6c4b985a11b4e500
        );
    }

    function testUUPSUpgrade() public {
        // Deploy initial proxy
        address proxy = Upgrades.deployUUPSProxy(
            "NFTStakingAndBorrowing.sol:NFTStakingAndBorrowing",
            abi.encodeCall(NFTStakingAndBorrowing.initialize, (address(stableBondCoins)))
        );
        NFTStakingAndBorrowing instance = NFTStakingAndBorrowing(proxy);

        instance.transferOwnership(owner);

        // Setup initial state using setUp data
        vm.startPrank(owner);
        stableBondCoins.grantRole(MINTER_ROLE, address(instance));
        instance.whitelistNFT(address(bondNFT), true);

        // Approve the new proxy contract to manage owner's NFTs
        bondNFT.setApprovalForAll(address(instance), true);

        // Perform staking and borrowing with existing NFTs from setUp
        instance.stakeNFT(address(bondNFT), 1, 10);
        instance.borrow(500_000000);
        vm.stopPrank();

        // Verify initial state
        assertEq(instance.getTotalStats().staked, 9975_000000, "Initial staked amount incorrect");
        assertEq(instance.getUserStats(owner).borrowed, 500_000000, "Initial borrowed amount incorrect");
        assertEq(bondNFT.balanceOf(address(instance), 1), 10, "Initial NFT balance incorrect");
        address implAddressV1 = Upgrades.getImplementationAddress(proxy);

        // Upgrade to V2
        Upgrades.upgradeProxy(
            proxy,
            "NFTStakingAndBorrowingV2.sol:NFTStakingAndBorrowingV2",
            abi.encodeCall(NFTStakingAndBorrowingV2.initializeV2, ()),
            owner
        );

        // Verify state after upgrade
        NFTStakingAndBorrowingV2 instance2 = NFTStakingAndBorrowingV2(proxy);
        address implAddressV2 = Upgrades.getImplementationAddress(proxy);
        assertFalse(implAddressV2 == implAddressV1, "Implementation address should change");
        assertEq(instance2.getTotalStats().staked, 9975_000000, "Staked amount should be preserved");
        assertEq(instance2.getUserStats(owner).borrowed, 500_000000, "Borrowed amount should be preserved");
        assertEq(bondNFT.balanceOf(address(instance2), 1), 10, "NFT balance should be preserved");
        assertEq(instance2.getInitializedVersion(), 2, "Version should be updated to 2");
        assertEq(instance2.newFeature(), "V2 Feature", "Should use V2 implementation");
    }

    function testProtocolRateCheckpointsDoNotChangeResults() public {
        owner = address(1);

        assertEq(nftStaking.getProtocolRate(), 1200 * 1e18 / 1e4);
        assertEq(nftStaking.getCheckpointsCount(), 1);

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

        vm.roll(2);
        vm.warp(1 + 30 days);

        vm.prank(owner);
        nftStaking.setProtocolRate(1200);

        assertEq(nftStaking.getProtocolRate(), 1200 * 1e18 / 1e4);
        assertEq(nftStaking.getCheckpointsCount(), 2);

        userStats = nftStaking.getUserStats(owner);
        totalStats = nftStaking.getTotalStats();
        assertEq(nftStaking.userAvailableToBorrow(owner), 8484_917395);
        assertEq(userStats.debtUpdateTimestamp, 2592001);
        assertEq(totalStats.debt, 504_679102);
        assertEq(userStats.debt, 504_679102);
    }

    function testProtocolRateCheckpointsYearlyMath() public {
        owner = address(1);
        uint256[] memory spans;
        uint256[] memory protocolRates;

        vm.startPrank(owner);

        // 10%
        nftStaking.setProtocolRate(1000);
        (uint48 timestamp, uint208 protocolRate) = nftStaking.getCheckpoint(0);
        console.log("Checkpoint 0:", timestamp, protocolRate);

        nftStaking.stakeNFT(address(bondNFT), 1, 10);
        NFTStakingAndBorrowing.UserStats memory userStats = nftStaking.getUserStats(owner);

        nftStaking.borrow(1000_000000);

        // After 1 year
        vm.warp(1 + YEAR_IN_SECONDS);

        userStats = nftStaking.getUserStats(owner);
        console.log("1 year : ", nftStaking.calculateDebt(1000_000000, 1, 1 + YEAR_IN_SECONDS));
        assertEq(userStats.debt, 1100_000000, "1 year diff wrong");

        // 20%
        nftStaking.setProtocolRate(2000);
        assertEq(nftStaking.getProtocolRate(), 2000 * 1e18 / 1e4);
        assertEq(nftStaking.getCheckpointsCount(), 2);
        (timestamp, protocolRate) = nftStaking.getCheckpoint(1);
        console.log("Checkpoint 1:", timestamp, protocolRate);

        // After 2 years
        vm.warp(1 + 2 * YEAR_IN_SECONDS);

        userStats = nftStaking.getUserStats(owner);
        console.log("2 years: ", nftStaking.calculateDebt(1000_000000, 1, 1 + 2 * YEAR_IN_SECONDS));
        console.log("Spans and rates:");
        (spans, protocolRates) = nftStaking.getProtocolRateTimeSpans(10, uint48(10 + 2 * YEAR_IN_SECONDS));
        for (uint256 i = 0; i < spans.length; i++) {
            console.log(spans[i], protocolRates[i]);
        }
        assertEq(userStats.debt, 1320_000000, "2 years diff wrong");

        // 30%
        nftStaking.setProtocolRate(3000);
        assertEq(nftStaking.getProtocolRate(), 3000 * 1e18 / 1e4);
        assertEq(nftStaking.getCheckpointsCount(), 3);
        (timestamp, protocolRate) = nftStaking.getCheckpoint(2);
        console.log("Checkpoint 2:", timestamp, protocolRate);

        // After 3 years
        vm.warp(1 + 3 * YEAR_IN_SECONDS);

        userStats = nftStaking.getUserStats(owner);
        console.log("3 years: ", nftStaking.calculateDebt(1000_000000, 1, 1 + 3 * YEAR_IN_SECONDS));
        assertEq(userStats.debt, 1716_000000, "3 years diff wrong");

        console.log("Spans and rates:");
        (spans, protocolRates) = nftStaking.getProtocolRateTimeSpans(1, uint48(1 + 3 * YEAR_IN_SECONDS));
        for (uint256 i = 0; i < spans.length; i++) {
            console.log(spans[i], protocolRates[i]);
        }

        vm.stopPrank();
    }

    function testProtocolRateCheckpointsBeforeFirstChekpoint() public {
        vm.warp(1000);

        vm.startPrank(owner);
        nftStaking = NFTStakingAndBorrowing(
            Upgrades.deployUUPSProxy(
                "NFTStakingAndBorrowing.sol:NFTStakingAndBorrowing",
                abi.encodeCall(NFTStakingAndBorrowing.initialize, (address(stableBondCoins)))
            )
        );
        nftStaking.setProtocolRate(1000);

        bondNFT.setApprovalForAll(address(nftStaking), true);
        nftStaking.whitelistNFT(address(bondNFT), true);
        nftStaking.setProtocolFee(0);

        (uint48 timestamp, uint208 protocolRate) = nftStaking.getCheckpoint(0);
        console.log("Checkpoint 0:", timestamp, protocolRate);

        // After 1 year
        vm.warp(1 + YEAR_IN_SECONDS);
        nftStaking.setProtocolRate(2000);
        (timestamp, protocolRate) = nftStaking.getCheckpoint(1);
        console.log("Checkpoint 1:", timestamp, protocolRate);

        uint256[] memory spans;
        uint256[] memory protocolRates;
        console.log("Spans and rates:");
        (spans, protocolRates) = nftStaking.getProtocolRateTimeSpans(1, uint48(1 + 2 * YEAR_IN_SECONDS));
        for (uint256 i = 0; i < spans.length; i++) {
            console.log(spans[i], protocolRates[i]);
        }

        uint256 debt = nftStaking.calculateDebt(1000_000000, 1, 1 + 2 * YEAR_IN_SECONDS);
        console.log("2 years: ", debt);
        assertEq(debt, 1320_000000, "2 years debt wrong");

        debt = nftStaking.calculateDebt(1000_000000, YEAR_IN_SECONDS + 200, 2 * YEAR_IN_SECONDS + 200);
        console.log("Only 2nd year: ", debt);
        assertEq(debt, 1200_000000, "Second year debt wrong");

        // Testing only 2nd year
        console.log("Spans and rates:");
        (spans, protocolRates) =
            nftStaking.getProtocolRateTimeSpans(uint48(YEAR_IN_SECONDS + 200), uint48(2 * YEAR_IN_SECONDS + 200));
        for (uint256 i = 0; i < spans.length; i++) {
            console.log(spans[i], protocolRates[i]);
        }

        vm.stopPrank();
    }

    function testLiquidateByDebt() public {
        owner = address(1);
        address client1 = address(2);
        address client2 = address(3);

        // 10%
        vm.prank(owner);
        nftStaking.setProtocolRate(1000);

        vm.startPrank(owner);
        bondNFT.setAllowedMints(client1, 2, 10);
        bondNFT.setAllowedMints(client2, 2, 20);
        vm.stopPrank();

        vm.prank(client1);
        bondNFT.mint(2, 10, "");
        vm.prank(client2);
        bondNFT.mint(2, 20, "");

        vm.prank(client1);
        bondNFT.setApprovalForAll(address(nftStaking), true);

        vm.prank(client2);
        bondNFT.setApprovalForAll(address(nftStaking), true);

        // Client1 borrows MAX
        vm.startPrank(client1);
        nftStaking.stakeNFT(address(bondNFT), 2, 10);
        nftStaking.borrow(0);
        vm.stopPrank();

        // 20% - rate change
        vm.warp(30 days);
        vm.prank(owner);
        nftStaking.setProtocolRate(2000);

        // Client2 borrows MAX
        vm.startPrank(client2);
        nftStaking.stakeNFT(address(bondNFT), 2, 20);
        nftStaking.borrow(0);
        vm.stopPrank();

        // we go to the future when debt of client1 is more than 90% of nominal available
        uint256 daysToFuture = 190 days;
        vm.warp(daysToFuture);
        NFTStakingAndBorrowing.UserStats memory userStats = nftStaking.getUserStats(client1);

        uint256 protocolRate = nftStaking.getProtocolRate();

        console.log("Client1 debt:     ", userStats.debt);
        console.log("Client1 borrowed: ", userStats.borrowed);
        console.log("Client1 staked:   ", userStats.staked);
        console.log("Client1 threshold:", userStats.staked * 9850 / 10000);
        console.log("Client1 Stables:  ", stableBondCoins.balanceOf(client1));
        assertEq(block.timestamp, daysToFuture, "Time should be daysToFuture days");

        uint256 client2BalanceBefore = stableBondCoins.balanceOf(client2);

        // vm.warp(355 days);
        // Client2 liquidates client1
        vm.startPrank(client2);
        stableBondCoins.approve(address(nftStaking), UINT256_MAX);
        nftStaking.liquidate(address(bondNFT), 2, client1);
        vm.stopPrank();

        // Verify balances after liquidation
        assertEq(bondNFT.balanceOf(client1, 2), 0, "Original owner should receive remaining NFTs");
        assertEq(bondNFT.balanceOf(client2, 2), 10, "Liquidator should receive proportional NFTs");
        assertEq(bondNFT.balanceOf(address(nftStaking), 2), 20, "Contract should have only client2 NFTs left");

        // Check internal mapping state - userNFTs should be 0 as all NFTs are removed from staking
        assertEq(
            nftStaking.getUserNFTBalance(client1, address(bondNFT), 2),
            0,
            "userNFTs balance should be 0 after liquidation as all NFTs are removed from staking"
        );

        // Verify client2 paid for the liquidation
        assertLt(stableBondCoins.balanceOf(client2), client2BalanceBefore, "Liquidator should pay for liquidation");
        console.log("Client2 Pays:     ", client2BalanceBefore - stableBondCoins.balanceOf(client2));

        // Verify client1's debt is cleared
        userStats = nftStaking.getUserStats(client1);
        assertEq(userStats.debt, 0, "Debt should be cleared after liquidation");
    }

    function testLiquidateByDebtPartial() public {
        owner = address(1);
        address client1 = address(2);
        address client2 = address(3);

        // 10%
        vm.prank(owner);
        nftStaking.setProtocolRate(1000);

        vm.startPrank(owner);
        bondNFT.setAllowedMints(client1, 1, 10);
        bondNFT.setAllowedMints(client1, 2, 10);
        bondNFT.setAllowedMints(client2, 2, 20);
        vm.stopPrank();

        vm.startPrank(client1);
        bondNFT.mint(1, 10, "");
        bondNFT.mint(2, 10, "");
        vm.stopPrank();
        vm.prank(client2);
        bondNFT.mint(2, 20, "");

        vm.prank(client1);
        bondNFT.setApprovalForAll(address(nftStaking), true);

        vm.prank(client2);
        bondNFT.setApprovalForAll(address(nftStaking), true);

        // Client1 borrows MAX
        vm.startPrank(client1);
        nftStaking.stakeNFT(address(bondNFT), 1, 10);
        nftStaking.stakeNFT(address(bondNFT), 2, 10);
        nftStaking.borrow(0);
        vm.stopPrank();

        // 20% - rate change
        vm.warp(30 days);
        vm.prank(owner);
        nftStaking.setProtocolRate(2000);

        // Client2 borrows MAX
        vm.startPrank(client2);
        nftStaking.stakeNFT(address(bondNFT), 2, 20);
        nftStaking.borrow(0);
        vm.stopPrank();

        // we go to the future when debt of client1 is more than 90% of nominal available
        uint256 daysToFuture = 190 days;
        vm.warp(daysToFuture);
        NFTStakingAndBorrowing.UserStats memory userStats = nftStaking.getUserStats(client1);

        uint256 protocolRate = nftStaking.getProtocolRate();

        console.log("Client1 debt:     ", userStats.debt);
        console.log("Client1 borrowed: ", userStats.borrowed);
        console.log("Client1 staked:   ", userStats.staked);
        console.log("Client1 threshold:", userStats.staked * 9850 / 10000);
        console.log("Client1 Stables:  ", stableBondCoins.balanceOf(client1));
        assertEq(block.timestamp, daysToFuture, "Time should be daysToFuture days");

        uint256 client1DebtBeforeLiquidation = userStats.debt;
        uint256 client2BalanceBefore = stableBondCoins.balanceOf(client2);

        // vm.warp(355 days);
        // Client2 liquidates client1
        vm.startPrank(client2);
        stableBondCoins.approve(address(nftStaking), UINT256_MAX);
        nftStaking.liquidate(address(bondNFT), 2, client1);
        vm.stopPrank();

        // Verify balances after liquidation
        assertEq(bondNFT.balanceOf(client1, 2), 0, "Original owner should receive remaining NFTs");
        assertEq(bondNFT.balanceOf(client2, 2), 10, "Liquidator should receive proportional NFTs");
        assertEq(bondNFT.balanceOf(address(nftStaking), 2), 20, "Contract should have only client2 NFTs left");

        // Check internal mapping state - userNFTs should be 0 as all NFTs are removed from staking
        assertEq(
            nftStaking.getUserNFTBalance(client1, address(bondNFT), 2),
            0,
            "userNFTs balance should be 0 after liquidation as all NFTs are removed from staking"
        );

        // Verify client2 paid for the liquidation
        assertLt(stableBondCoins.balanceOf(client2), client2BalanceBefore, "Liquidator should pay for liquidation");
        console.log("Client2 Pays:     ", client2BalanceBefore - stableBondCoins.balanceOf(client2));

        // Verify client1's debt is cleared
        userStats = nftStaking.getUserStats(client1);
        assertEq(
            userStats.debt,
            client1DebtBeforeLiquidation - client2BalanceBefore + stableBondCoins.balanceOf(client2),
            "Debt should be cleared after liquidation"
        );
    }

    function testLiquidateByDebtWhenBorrowedLater() public {
        owner = address(1);
        address client1 = address(2);
        address client2 = address(3);

        // 10%
        vm.prank(owner);
        nftStaking.setProtocolRate(1000);

        vm.warp(30 days);
        // user mints 30 days after bond is issued

        vm.startPrank(owner);
        bondNFT.setAllowedMints(client1, 2, 10);
        bondNFT.setAllowedMints(client2, 2, 20);
        vm.stopPrank();

        vm.prank(client1);
        bondNFT.mint(2, 10, "");
        vm.prank(client2);
        bondNFT.mint(2, 20, "");

        vm.prank(client1);
        bondNFT.setApprovalForAll(address(nftStaking), true);

        vm.prank(client2);
        bondNFT.setApprovalForAll(address(nftStaking), true);

        // Client1 borrows MAX
        vm.startPrank(client1);
        nftStaking.stakeNFT(address(bondNFT), 2, 10);
        nftStaking.borrow(0);
        vm.stopPrank();

        // 20% - rate change
        vm.warp(60 days);
        vm.prank(owner);
        nftStaking.setProtocolRate(2000);

        // Client2 borrows MAX
        vm.startPrank(client2);
        nftStaking.stakeNFT(address(bondNFT), 2, 20);
        nftStaking.borrow(0);
        vm.stopPrank();

        // we go to the future when debt of client1 is more than 90% of nominal available
        uint256 daysToFuture = 190 days;
        vm.warp(daysToFuture);
        NFTStakingAndBorrowing.UserStats memory userStats = nftStaking.getUserStats(client1);

        uint256 protocolRate = nftStaking.getProtocolRate();

        console.log("Client1 debt:     ", userStats.debt);
        console.log("Client1 borrowed: ", userStats.borrowed);
        console.log("Client1 staked:   ", userStats.staked);
        console.log("Client1 threshold:", userStats.staked * 9850 / 10000);
        console.log("Client1 Stables:  ", stableBondCoins.balanceOf(client1));
        assertEq(block.timestamp, daysToFuture, "Time should be daysToFuture days");

        uint256 client2BalanceBefore = stableBondCoins.balanceOf(client2);

        // vm.warp(355 days);
        // Client2 liquidates client1
        vm.startPrank(client2);
        stableBondCoins.approve(address(nftStaking), UINT256_MAX);
        nftStaking.liquidate(address(bondNFT), 2, client1);
        vm.stopPrank();

        // Verify balances after liquidation
        assertEq(bondNFT.balanceOf(client1, 2), 0, "Original owner should receive remaining NFTs");
        assertEq(bondNFT.balanceOf(client2, 2), 10, "Liquidator should receive proportional NFTs");
        assertEq(bondNFT.balanceOf(address(nftStaking), 2), 20, "Contract should have only client2 NFTs left");

        // Check internal mapping state - userNFTs should be 0 as all NFTs are removed from staking
        assertEq(
            nftStaking.getUserNFTBalance(client1, address(bondNFT), 2),
            0,
            "userNFTs balance should be 0 after liquidation as all NFTs are removed from staking"
        );

        // Verify client2 paid for the liquidation
        assertLt(stableBondCoins.balanceOf(client2), client2BalanceBefore, "Liquidator should pay for liquidation");
        console.log("Client2 Pays:     ", client2BalanceBefore - stableBondCoins.balanceOf(client2));
        console.log("Client2 should pay:", userStats.staked * (UNIT - (protocolRate / 20)) / UNIT);

        // Verify client1's debt is cleared
        userStats = nftStaking.getUserStats(client1);
        assertEq(userStats.debt, 0, "Debt should be cleared after liquidation");
    }

    function testLiquidateWithRateChange() public {
        owner = address(1);
        address client1 = address(2);
        address client2 = address(3);

        // 10%
        vm.prank(owner);
        nftStaking.setProtocolRate(1000);

        vm.startPrank(owner);
        bondNFT.setAllowedMints(client1, 2, 10);
        bondNFT.setAllowedMints(client2, 2, 20);
        vm.stopPrank();

        vm.prank(client1);
        bondNFT.mint(2, 10, "");
        vm.prank(client2);
        bondNFT.mint(2, 20, "");

        vm.prank(client1);
        bondNFT.setApprovalForAll(address(nftStaking), true);

        vm.prank(client2);
        bondNFT.setApprovalForAll(address(nftStaking), true);

        // Client1 borrows 500
        vm.startPrank(client1);
        nftStaking.stakeNFT(address(bondNFT), 2, 10);
        nftStaking.borrow(500_000000);
        vm.stopPrank();

        // 11% - rate change
        vm.warp(150 days);
        vm.prank(owner);
        nftStaking.setProtocolRate(1100);

        // Client2 borrows MAX
        vm.startPrank(client2);
        nftStaking.stakeNFT(address(bondNFT), 2, 20);
        nftStaking.borrow(0);
        vm.stopPrank();

        // normal liquidation window
        uint256 daysToFuture = 321 days;
        vm.warp(daysToFuture);
        NFTStakingAndBorrowing.UserStats memory userStats = nftStaking.getUserStats(client1);

        uint256 protocolRate = nftStaking.getProtocolRate();

        console.log("Client1 debt:     ", userStats.debt);
        console.log("Client1 borrowed: ", userStats.borrowed);
        console.log("Client1 staked:   ", userStats.staked);
        console.log("Client1 threshold:", userStats.staked * 9850 / 10000);
        console.log("Client1 Stables:  ", stableBondCoins.balanceOf(client1));
        assertEq(block.timestamp, daysToFuture, "Time should be daysToFuture days");

        uint256 client1BalanceBefore = stableBondCoins.balanceOf(client1);
        uint256 client2BalanceBefore = stableBondCoins.balanceOf(client2);

        // Client2 liquidates client1
        vm.startPrank(client2);
        stableBondCoins.approve(address(nftStaking), UINT256_MAX);
        nftStaking.liquidate(address(bondNFT), 2, client1);
        vm.stopPrank();

        // Verify balances after liquidation
        assertEq(bondNFT.balanceOf(client1, 2), 9, "Original owner should receive remaining NFTs");
        assertEq(bondNFT.balanceOf(client2, 2), 1, "Liquidator should receive proportional NFTs");

        // Check internal mapping state - userNFTs should be 0 as all NFTs are removed from staking
        assertEq(
            nftStaking.getUserNFTBalance(client1, address(bondNFT), 2),
            0,
            "userNFTs balance should be 0 after liquidation as all NFTs are removed from staking"
        );

        // Verify client2 paid for the liquidation
        assertLt(stableBondCoins.balanceOf(client2), client2BalanceBefore, "Liquidator should pay for liquidation");
        console.log("Client2 Pays:     ", client2BalanceBefore - stableBondCoins.balanceOf(client2));
        // Client1 should get the diff between liguidated NFTs and his debt
        console.log("Client1 Stables:  ", stableBondCoins.balanceOf(client1));
        console.log("Client1 Gets:     ", stableBondCoins.balanceOf(client1) - client1BalanceBefore);

        // Verify client1's debt is cleared
        userStats = nftStaking.getUserStats(client1);
        assertEq(userStats.debt, 0, "Debt should be cleared after liquidation");
    }

    function testLiquidateWithRateChangeBeforeBorrowBase() public {
        owner = address(1);
        address client1 = address(2);
        address client2 = address(3);

        // 10%
        vm.prank(owner);
        nftStaking.setProtocolRate(1000);

        vm.startPrank(owner);
        bondNFT.setAllowedMints(client1, 2, 10);
        bondNFT.setAllowedMints(client2, 2, 20);
        vm.stopPrank();

        vm.prank(client1);
        bondNFT.mint(2, 10, "");
        vm.prank(client2);
        bondNFT.mint(2, 20, "");

        vm.prank(client1);
        bondNFT.setApprovalForAll(address(nftStaking), true);

        vm.prank(client2);
        bondNFT.setApprovalForAll(address(nftStaking), true);

        // Rate change
        // Base - no rate change
        vm.warp(50 days);

        vm.prank(owner);
        nftStaking.setProtocolRate(1000);

        vm.warp(100 days);

        // Client1 borrows 500
        vm.startPrank(client1);
        nftStaking.stakeNFT(address(bondNFT), 2, 10);
        nftStaking.borrow(500_000000);
        vm.stopPrank();

        // Client2 borrows MAX
        vm.startPrank(client2);
        nftStaking.stakeNFT(address(bondNFT), 2, 20);
        nftStaking.borrow(0);
        vm.stopPrank();

        // normal liquidation window
        uint256 daysToFuture = 321 days;
        vm.warp(daysToFuture);
        NFTStakingAndBorrowing.UserStats memory userStats = nftStaking.getUserStats(client1);

        uint256 protocolRate = nftStaking.getProtocolRate();

        console.log("Client1 debt:     ", userStats.debt);
        console.log("Client1 borrowed: ", userStats.borrowed);
        console.log("Client1 staked:   ", userStats.staked);
        console.log("Client1 threshold:", userStats.staked * 9850 / 10000);
        console.log("Client1 Stables:  ", stableBondCoins.balanceOf(client1));
        assertEq(block.timestamp, daysToFuture, "Time should be daysToFuture days");

        uint256 client1BalanceBefore = stableBondCoins.balanceOf(client1);
        uint256 client2BalanceBefore = stableBondCoins.balanceOf(client2);

        // Client2 liquidates client1
        vm.startPrank(client2);
        stableBondCoins.approve(address(nftStaking), UINT256_MAX);
        nftStaking.liquidate(address(bondNFT), 2, client1);
        vm.stopPrank();

        // Verify balances after liquidation
        assertEq(bondNFT.balanceOf(client1, 2), 9, "Original owner should receive remaining NFTs");
        assertEq(bondNFT.balanceOf(client2, 2), 1, "Liquidator should receive proportional NFTs");

        // Check internal mapping state - userNFTs should be 0 as all NFTs are removed from staking
        assertEq(
            nftStaking.getUserNFTBalance(client1, address(bondNFT), 2),
            0,
            "userNFTs balance should be 0 after liquidation as all NFTs are removed from staking"
        );

        // Verify client2 paid for the liquidation
        assertLt(stableBondCoins.balanceOf(client2), client2BalanceBefore, "Liquidator should pay for liquidation");
        console.log("Client2 Pays:     ", client2BalanceBefore - stableBondCoins.balanceOf(client2));
        // Client1 should get the diff between liguidated NFTs and his debt
        console.log("Client1 Stables:  ", stableBondCoins.balanceOf(client1));
        console.log("Client1 Gets:     ", stableBondCoins.balanceOf(client1) - client1BalanceBefore);

        // Verify client1's debt is cleared
        userStats = nftStaking.getUserStats(client1);
        assertEq(userStats.debt, 0, "Debt should be cleared after liquidation");
    }

    function testLiquidateWithRateChangeBeforeBorrowUp() public {
        owner = address(1);
        address client1 = address(2);
        address client2 = address(3);

        // 15%
        vm.prank(owner);
        nftStaking.setProtocolRate(1500);

        vm.startPrank(owner);
        bondNFT.setAllowedMints(client1, 2, 10);
        bondNFT.setAllowedMints(client2, 2, 20);
        vm.stopPrank();

        vm.prank(client1);
        bondNFT.mint(2, 10, "");
        vm.prank(client2);
        bondNFT.mint(2, 20, "");

        vm.prank(client1);
        bondNFT.setApprovalForAll(address(nftStaking), true);

        vm.prank(client2);
        bondNFT.setApprovalForAll(address(nftStaking), true);

        // Rate change
        // Base - no rate change
        vm.warp(50 days);

        vm.prank(owner);
        nftStaking.setProtocolRate(1000);

        vm.warp(100 days);

        // Client1 borrows 500
        vm.startPrank(client1);
        nftStaking.stakeNFT(address(bondNFT), 2, 10);
        nftStaking.borrow(500_000000);
        vm.stopPrank();

        // Client2 borrows MAX
        vm.startPrank(client2);
        nftStaking.stakeNFT(address(bondNFT), 2, 20);
        nftStaking.borrow(0);
        vm.stopPrank();

        // normal liquidation window
        uint256 daysToFuture = 321 days;
        vm.warp(daysToFuture);
        NFTStakingAndBorrowing.UserStats memory userStats = nftStaking.getUserStats(client1);

        uint256 protocolRate = nftStaking.getProtocolRate();

        console.log("Client1 debt:     ", userStats.debt);
        console.log("Client1 borrowed: ", userStats.borrowed);
        console.log("Client1 staked:   ", userStats.staked);
        console.log("Client1 threshold:", userStats.staked * 9850 / 10000);
        console.log("Client1 Stables:  ", stableBondCoins.balanceOf(client1));
        assertEq(block.timestamp, daysToFuture, "Time should be daysToFuture days");

        uint256 client1BalanceBefore = stableBondCoins.balanceOf(client1);
        uint256 client2BalanceBefore = stableBondCoins.balanceOf(client2);

        // Client2 liquidates client1
        vm.startPrank(client2);
        stableBondCoins.approve(address(nftStaking), UINT256_MAX);
        nftStaking.liquidate(address(bondNFT), 2, client1);
        vm.stopPrank();

        // Verify balances after liquidation
        assertEq(bondNFT.balanceOf(client1, 2), 9, "Original owner should receive remaining NFTs");
        assertEq(bondNFT.balanceOf(client2, 2), 1, "Liquidator should receive proportional NFTs");

        // Check internal mapping state - userNFTs should be 0 as all NFTs are removed from staking
        assertEq(
            nftStaking.getUserNFTBalance(client1, address(bondNFT), 2),
            0,
            "userNFTs balance should be 0 after liquidation as all NFTs are removed from staking"
        );

        // Verify client2 paid for the liquidation
        assertLt(stableBondCoins.balanceOf(client2), client2BalanceBefore, "Liquidator should pay for liquidation");
        console.log("Client2 Pays:     ", client2BalanceBefore - stableBondCoins.balanceOf(client2));
        // Client1 should get the diff between liguidated NFTs and his debt
        console.log("Client1 Stables:  ", stableBondCoins.balanceOf(client1));
        console.log("Client1 Gets:     ", stableBondCoins.balanceOf(client1) - client1BalanceBefore);

        // Verify client1's debt is cleared
        userStats = nftStaking.getUserStats(client1);
        assertEq(userStats.debt, 0, "Debt should be cleared after liquidation");
    }

    function testLiquidateWithRateChangeBeforeBorrowDown() public {
        owner = address(1);
        address client1 = address(2);
        address client2 = address(3);

        // 5%
        vm.prank(owner);
        nftStaking.setProtocolRate(500);

        vm.startPrank(owner);
        bondNFT.setAllowedMints(client1, 2, 10);
        bondNFT.setAllowedMints(client2, 2, 20);
        vm.stopPrank();

        vm.prank(client1);
        bondNFT.mint(2, 10, "");
        vm.prank(client2);
        bondNFT.mint(2, 20, "");

        vm.prank(client1);
        bondNFT.setApprovalForAll(address(nftStaking), true);

        vm.prank(client2);
        bondNFT.setApprovalForAll(address(nftStaking), true);

        // Rate change
        // Base - no rate change
        vm.warp(50 days);

        vm.prank(owner);
        nftStaking.setProtocolRate(1000);

        vm.warp(100 days);

        // Client1 borrows 500
        vm.startPrank(client1);
        nftStaking.stakeNFT(address(bondNFT), 2, 10);
        nftStaking.borrow(500_000000);
        vm.stopPrank();

        // Client2 borrows MAX
        vm.startPrank(client2);
        nftStaking.stakeNFT(address(bondNFT), 2, 20);
        nftStaking.borrow(0);
        vm.stopPrank();

        // normal liquidation window
        uint256 daysToFuture = 321 days;
        vm.warp(daysToFuture);
        NFTStakingAndBorrowing.UserStats memory userStats = nftStaking.getUserStats(client1);

        uint256 protocolRate = nftStaking.getProtocolRate();

        console.log("Client1 debt:     ", userStats.debt);
        console.log("Client1 borrowed: ", userStats.borrowed);
        console.log("Client1 staked:   ", userStats.staked);
        console.log("Client1 threshold:", userStats.staked * 9850 / 10000);
        console.log("Client1 Stables:  ", stableBondCoins.balanceOf(client1));
        assertEq(block.timestamp, daysToFuture, "Time should be daysToFuture days");

        uint256 client1BalanceBefore = stableBondCoins.balanceOf(client1);
        uint256 client2BalanceBefore = stableBondCoins.balanceOf(client2);

        // Client2 liquidates client1
        vm.startPrank(client2);
        stableBondCoins.approve(address(nftStaking), UINT256_MAX);
        nftStaking.liquidate(address(bondNFT), 2, client1);
        vm.stopPrank();

        // Verify balances after liquidation
        assertEq(bondNFT.balanceOf(client1, 2), 9, "Original owner should receive remaining NFTs");
        assertEq(bondNFT.balanceOf(client2, 2), 1, "Liquidator should receive proportional NFTs");

        // Check internal mapping state - userNFTs should be 0 as all NFTs are removed from staking
        assertEq(
            nftStaking.getUserNFTBalance(client1, address(bondNFT), 2),
            0,
            "userNFTs balance should be 0 after liquidation as all NFTs are removed from staking"
        );

        // Verify client2 paid for the liquidation
        assertLt(stableBondCoins.balanceOf(client2), client2BalanceBefore, "Liquidator should pay for liquidation");
        console.log("Client2 Pays:     ", client2BalanceBefore - stableBondCoins.balanceOf(client2));
        // Client1 should get the diff between liguidated NFTs and his debt
        console.log("Client1 Stables:  ", stableBondCoins.balanceOf(client1));
        console.log("Client1 Gets:     ", stableBondCoins.balanceOf(client1) - client1BalanceBefore);

        // Verify client1's debt is cleared
        userStats = nftStaking.getUserStats(client1);
        assertEq(userStats.debt, 0, "Debt should be cleared after liquidation");
    }

    function testLiquidateWithPartialBadDebt() public {
        owner = address(1);
        address client1 = address(2);
        address client2 = address(3);

        // 10%
        vm.prank(owner);
        nftStaking.setProtocolRate(1000);

        vm.startPrank(owner);
        bondNFT.setAllowedMints(client1, 1, 10);
        bondNFT.setAllowedMints(client1, 2, 10);
        bondNFT.setAllowedMints(client2, 2, 20);
        vm.stopPrank();

        vm.startPrank(client1);
        bondNFT.mint(1, 10, "");
        bondNFT.mint(2, 10, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        nftStaking.stakeNFT(address(bondNFT), 1, 10);
        nftStaking.borrow(0);
        vm.stopPrank();

        vm.startPrank(client2);
        bondNFT.mint(2, 20, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        vm.stopPrank();

        // Rate change
        vm.warp(50 days);

        vm.prank(owner);
        nftStaking.setProtocolRate(1500);

        vm.warp(100 days);

        // Client1 new stake
        vm.startPrank(client1);
        nftStaking.stakeNFT(address(bondNFT), 2, 10);
        vm.stopPrank();

        // Client2 borrows MAX
        vm.startPrank(client2);
        nftStaking.stakeNFT(address(bondNFT), 2, 20);
        nftStaking.borrow(0);
        vm.stopPrank();

        // normal liquidation window
        uint256 daysToFuture = 321 days;
        vm.warp(daysToFuture);
        NFTStakingAndBorrowing.UserStats memory userStats = nftStaking.getUserStats(client1);

        uint256 protocolRate = nftStaking.getProtocolRate();

        console.log("Client1 debt:     ", userStats.debt);
        console.log("Client1 borrowed: ", userStats.borrowed);
        console.log("Client1 staked:   ", userStats.staked);
        console.log("Client1 threshold:", userStats.staked * 9850 / 10000);
        console.log("Client1 Stables:  ", stableBondCoins.balanceOf(client1));
        assertEq(block.timestamp, daysToFuture, "Time should be daysToFuture days");

        uint256 client1BalanceBefore = stableBondCoins.balanceOf(client1);
        uint256 client2BalanceBefore = stableBondCoins.balanceOf(client2);

        // Client2 liquidates client1
        vm.startPrank(client2);
        stableBondCoins.approve(address(nftStaking), UINT256_MAX);
        nftStaking.liquidate(address(bondNFT), 2, client1);
        vm.stopPrank();

        // Verify balances after liquidation
        assertEq(bondNFT.balanceOf(client1, 2), 0, "Position fully liquidated");
        assertEq(bondNFT.balanceOf(client2, 2), 10, "Liquidator should receive NFTs");

        // Check internal mapping state - userNFTs should be 0 as all NFTs are removed from staking
        assertEq(
            nftStaking.getUserNFTBalance(client1, address(bondNFT), 2),
            0,
            "userNFTs balance should be 0 after liquidation as all NFTs are removed from staking"
        );

        // Verify client2 paid for the liquidation
        assertLt(stableBondCoins.balanceOf(client2), client2BalanceBefore, "Liquidator should pay for liquidation");
        console.log("Client2 Pays:     ", client2BalanceBefore - stableBondCoins.balanceOf(client2));
        // Client1 should get the diff between liguidated NFTs and his debt
        console.log("Client1 Stables:  ", stableBondCoins.balanceOf(client1));
        console.log("Client1 Gets:     ", stableBondCoins.balanceOf(client1) - client1BalanceBefore);

        // Verify client1's debt
        userStats = nftStaking.getUserStats(client1);
        console.log("Client1 debt left: ", userStats.debt);

        client2BalanceBefore = stableBondCoins.balanceOf(client2);
        // Client2 liquidates second position of the client1
        vm.startPrank(client2);
        nftStaking.liquidate(address(bondNFT), 1, client1);
        vm.stopPrank();

        console.log("Client2 Pays 2:    ", client2BalanceBefore - stableBondCoins.balanceOf(client2));
        userStats = nftStaking.getUserStats(client1);
        console.log("Client1 debt left: ", userStats.debt);
    }
}
