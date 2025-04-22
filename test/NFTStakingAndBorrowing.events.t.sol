// SPDX-License-Identifier: MIT
pragma solidity >=0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {NFTStakingAndBorrowing} from "../src/NFTStakingAndBorrowing.sol";
import {StableBondCoins} from "../src/StableBondCoins.sol";
import {BondNFT} from "../src/BondNFT.sol";
import {StableCoinsStaking} from "../src/StableCoinsStaking.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract NFTStakingAndBorrowingEventsTest is Test {
    NFTStakingAndBorrowing public nftStaking;
    BondNFT public bondNFT;
    StableBondCoins public stableBondCoins;
    address public owner;
    address public client1;
    address public client2;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    event NFTStaked(address indexed user, address indexed nftAddress, uint256 tokenId, uint256 amount);
    event NFTUnstaked(address indexed user, address indexed nftAddress, uint256 tokenId, uint256 amount);
    event Borrowed(address indexed user, uint256 amount);
    event Repaid(address indexed user, uint256 amount);
    event Liquidated(
        address indexed user, address liquidator, address indexed nftAddress, uint256 tokenId, uint256 amount
    );

    function setUp() public {
        owner = address(1);
        client1 = address(2);
        client2 = address(3);

        vm.startPrank(owner);

        // Deploy the contract as a proxy with the initializer
        bondNFT = BondNFT(
            UnsafeUpgrades.deployUUPSProxy(
                address(new BondNFT()),
                abi.encodeCall(BondNFT.initialize, (owner, "https://example.com/{id}.json"))
            )
        );

        stableBondCoins = StableBondCoins(
            UnsafeUpgrades.deployUUPSProxy(
                address(new StableBondCoins()), abi.encodeCall(stableBondCoins.initialize, (owner, owner))
            )
        );

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
        bondNFT.setAllowedMints(client1, 2, 10);
        bondNFT.setAllowedMints(client2, 3, 10);

        bondNFT.mint(1, 10, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        nftStaking.whitelistNFT(address(bondNFT), true);
        vm.stopPrank();

        vm.startPrank(client1);
        bondNFT.mint(2, 10, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        vm.stopPrank();

        vm.startPrank(client2);
        bondNFT.mint(3, 10, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        vm.stopPrank();
    }

    function testNFTStakedEvent() public {
        vm.expectEmit(true, true, true, true);
        emit NFTStaked(owner, address(bondNFT), 1, 5);

        vm.prank(owner);
        nftStaking.stakeNFT(address(bondNFT), 1, 5);
    }

    function testNFTUnstakedEvent() public {
        vm.prank(owner);
        nftStaking.stakeNFT(address(bondNFT), 1, 5);

        vm.expectEmit(true, true, true, true);
        emit NFTUnstaked(owner, address(bondNFT), 1, 3);

        vm.prank(owner);
        nftStaking.unstakeNFT(address(bondNFT), 1, 3);
    }

    function testBorrowedEvent() public {
        vm.prank(client1);
        nftStaking.stakeNFT(address(bondNFT), 2, 10);

        uint256 borrowAmount = 500_000000;

        vm.expectEmit(true, true, false, true);
        emit Borrowed(client1, borrowAmount);

        vm.prank(client1);
        nftStaking.borrow(borrowAmount);
    }

    function testRepaidEvent() public {
        vm.startPrank(client1);
        nftStaking.stakeNFT(address(bondNFT), 2, 10);
        uint256 borrowAmount = 500_000000;
        nftStaking.borrow(borrowAmount);

        stableBondCoins.approve(address(nftStaking), borrowAmount);

        vm.expectEmit(true, true, false, true);
        emit Repaid(client1, borrowAmount);

        nftStaking.repay(borrowAmount);
        vm.stopPrank();
    }

    function testLiquidatedEvent() public {
        vm.startPrank(client1);
        nftStaking.stakeNFT(address(bondNFT), 2, 10);

        uint256 borrowAmount = 500_000000;
        nftStaking.borrow(borrowAmount);
        vm.stopPrank();

        vm.warp(1 + 31536000 - nftStaking.liquidationTimeWindow() + 1 days);

        vm.prank(owner);
        stableBondCoins.mint(client2, 1000_000000);

        vm.startPrank(client2);
        stableBondCoins.approve(address(nftStaking), 1000_000000);

        vm.expectEmit(true, true, true, true);
        emit Liquidated(client1, client2, address(bondNFT), 2, 10);

        nftStaking.liquidate(address(bondNFT), 2, client1);
        vm.stopPrank();
    }

    function testMultipleEventsInOneTransaction() public {
        vm.startPrank(owner);
        nftStaking.stakeNFT(address(bondNFT), 1, 5);

        vm.expectEmit(true, true, false, true);
        emit Borrowed(owner, 100_000000);

        nftStaking.borrow(100_000000);

        vm.expectEmit(true, true, true, true);
        emit NFTUnstaked(owner, address(bondNFT), 1, 2);

        nftStaking.unstakeNFT(address(bondNFT), 1, 2);
        vm.stopPrank();
    }

    function testStakeNFTandStablesEvents() public {
        address stablesStaking = address(new StableCoinsStaking(address(stableBondCoins), address(nftStaking)));

        vm.startPrank(owner);
        nftStaking.setStablesStakingAddress(stablesStaking);
        stableBondCoins.grantRole(MINTER_ROLE, stablesStaking);
        vm.stopPrank();

        vm.expectEmit(true, true, true, true);
        emit NFTStaked(client1, address(bondNFT), 2, 5);

        vm.expectEmit(true, false, false, false);
        emit Borrowed(client1, 0);

        vm.prank(client1);
        nftStaking.stakeNFTandStables(address(bondNFT), 2, 5);

        assertEq(bondNFT.balanceOf(address(nftStaking), 2), 5);

        NFTStakingAndBorrowing.UserStats memory userStats = nftStaking.getUserStats(client1);
        assertTrue(userStats.borrowed > 0, "No tokens were borrowed");
    }

    function testLiquidateNoDebtEvent() public {
        vm.prank(client1);
        nftStaking.stakeNFT(address(bondNFT), 2, 10);

        vm.warp(1 + 31536000 - nftStaking.liquidationTimeWindow() + 1 days);

        vm.expectEmit(true, true, true, true);
        emit NFTUnstaked(client1, address(bondNFT), 2, 10);

        vm.prank(client2);
        nftStaking.liquidate(address(bondNFT), 2, client1);
    }

    function testPartialUnstakeEvents() public {
        vm.prank(owner);
        nftStaking.stakeNFT(address(bondNFT), 1, 10);

        vm.expectEmit(true, true, true, true);
        emit NFTUnstaked(owner, address(bondNFT), 1, 3);

        vm.prank(owner);
        nftStaking.unstakeNFT(address(bondNFT), 1, 3);

        vm.expectEmit(true, true, true, true);
        emit NFTUnstaked(owner, address(bondNFT), 1, 5);

        vm.prank(owner);
        nftStaking.unstakeNFT(address(bondNFT), 1, 5);

        assertEq(bondNFT.balanceOf(address(nftStaking), 1), 2);
        assertEq(bondNFT.balanceOf(owner, 1), 8);
    }

    function testZeroAmountRepayEvent() public {
        vm.startPrank(client1);
        nftStaking.stakeNFT(address(bondNFT), 2, 10);
        uint256 borrowAmount = 500_000000;
        nftStaking.borrow(borrowAmount);

        stableBondCoins.approve(address(nftStaking), type(uint256).max);

        vm.expectEmit(true, true, false, true);
        emit Repaid(client1, borrowAmount);

        nftStaking.repay(0);
        vm.stopPrank();

        NFTStakingAndBorrowing.UserStats memory userStats = nftStaking.getUserStats(client1);
        assertEq(userStats.debt, 0);
    }

    function testLiquidateCase3Event() public {
        owner = address(1);
        address localClient1 = address(2);
        address localClient2 = address(3);

        vm.startPrank(owner);
        bondNFT.setAllowedMints(localClient1, 1, 10);
        bondNFT.setAllowedMints(localClient2, 2, 20);
        vm.stopPrank();

        // Client1 mints and stakes NFTs
        vm.prank(localClient1);
        bondNFT.mint(1, 10, "");
        vm.prank(localClient1);
        bondNFT.setApprovalForAll(address(nftStaking), true);

        vm.startPrank(localClient1);
        nftStaking.stakeNFT(address(bondNFT), 1, 10);
        uint256 maxBorrowAmount = nftStaking.userAvailableToBorrow(localClient1);
        uint256 borrowAmount = maxBorrowAmount / 2; // Borrow only half of available amount
        nftStaking.borrow(borrowAmount);
        vm.stopPrank();

        // Client2 prepares for liquidation
        vm.prank(localClient2);
        bondNFT.mint(2, 20, "");
        vm.prank(localClient2);
        bondNFT.setApprovalForAll(address(nftStaking), true);

        vm.startPrank(localClient2);
        nftStaking.stakeNFT(address(bondNFT), 2, 20);
        nftStaking.borrow(nftStaking.userAvailableToBorrow(localClient2));
        stableBondCoins.approve(address(nftStaking), type(uint256).max);
        vm.stopPrank();

        // Fast forward time to approach expiration
        vm.warp(365 days - 40 days);
        vm.roll(2);

        // Expect the Liquidated event
        vm.expectEmit(true, true, false, true);
        emit Liquidated(localClient1, localClient2, address(bondNFT), 1, 10);

        // Client2 liquidates part of client1's position
        vm.prank(localClient2);
        nftStaking.liquidate(address(bondNFT), 1, localClient1);
    }
}
