// SPDX-License-Identifier: MIT
pragma solidity >=0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {NFTStakingAndBorrowing} from "../src/NFTStakingAndBorrowing.sol";
import {StableBondCoins} from "../src/StableBondCoins.sol";
import {BondNFT} from "../src/BondNFT.sol";
import {StableCoinsStaking} from "../src/StableCoinsStaking.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

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

    /**
     * @notice Test for Case 2 (full liquidation) event emission
     * This test verifies that the Liquidated event is emitted with the correct amount of NFTs
     * when a position is fully liquidated (debt >= maxBorrow)
     */
    function testLiquidateCase2Event() public {
        vm.startPrank(client1);
        nftStaking.stakeNFT(address(bondNFT), 2, 10);

        // Borrow maximum amount to ensure full liquidation when time passes
        uint256 borrowAmount = nftStaking.userAvailableToBorrow(client1);
        nftStaking.borrow(borrowAmount);
        vm.stopPrank();

        // Fast forward time to approach expiration, reducing maxBorrow significantly
        vm.warp(1 + 31536000 - nftStaking.getLiquidationTimeWindow() + 10 days);
        vm.roll(2);

        vm.prank(owner);
        stableBondCoins.mint(client2, 10000_000000);

        vm.startPrank(client2);
        stableBondCoins.approve(address(nftStaking), 10000_000000);

        // Verify this is Case 2 (full liquidation)
        NFTStakingAndBorrowing.UserStats memory userStats = nftStaking.getUserStats(client1);
        uint256 currentDebt = userStats.debt;
        BondNFT.Metadata memory metadata = bondNFT.getMetaData(2);
        uint256 maxBorrow =
            nftStaking.calculateMaxBorrow(userStats.staked, block.timestamp, metadata.expirationTimestamp);

        assertGe(currentDebt, maxBorrow, "This should be a full liquidation (Case 2)");

        // Expect the Liquidated event with all NFTs
        vm.expectEmit(true, true, true, true);
        emit Liquidated(client1, client2, address(bondNFT), 2, 10);

        nftStaking.liquidate(address(bondNFT), 2, client1);
        vm.stopPrank();

        // Verify the result of liquidation
        assertEq(bondNFT.balanceOf(client2, 2), 10, "Liquidator should receive all NFTs");
        assertEq(bondNFT.balanceOf(client1, 2), 0, "Original owner should have no NFTs left");
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
        StableCoinsStaking stablesStaking = new StableCoinsStaking();
        stablesStaking.initialize(address(stableBondCoins), address(nftStaking), address(owner));

        vm.startPrank(owner);
        nftStaking.setStablesStakingAddress(address(stablesStaking));
        stableBondCoins.grantRole(MINTER_ROLE, address(stablesStaking));
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

        vm.warp(1 + 31536000 - nftStaking.getLiquidationTimeWindow() + 1 days);

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

    /**
     * @notice Test for Case 3 (partial liquidation) event emission when some NFTs are returned to owner
     * This test verifies that both Liquidated and NFTUnstaked events are emitted correctly
     * when a position is partially liquidated and some NFTs are returned to the owner
     */
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

        // Calculate how many NFTs will be liquidated
        NFTStakingAndBorrowing.UserStats memory userStats = nftStaking.getUserStats(localClient1);
        uint256 currentDebt = userStats.debt;
        BondNFT.Metadata memory metadata = bondNFT.getMetaData(1);
        uint256 maxBorrow =
            nftStaking.calculateMaxBorrow(userStats.staked, block.timestamp, metadata.expirationTimestamp);

        // Verify this is Case 3 (partial liquidation)
        assertLt(currentDebt, maxBorrow, "This should be a partial liquidation (Case 3)");

        // Calculate how many NFTs will be liquidated
        uint256 expectedNFTToLiquidator = (currentDebt * 10 / maxBorrow) + (currentDebt * 10 % maxBorrow == 0 ? 0 : 1);

        // Calculate remaining NFTs
        uint256 remainingNFTs = 10 - expectedNFTToLiquidator;

        // Ensure this test case has remaining NFTs to return to owner
        assertGt(remainingNFTs, 0, "This test requires remaining NFTs to test both events");

        // Expect the Liquidated event first (now that we've changed the order in the contract)
        vm.expectEmit(true, true, true, true);
        emit Liquidated(localClient1, localClient2, address(bondNFT), 1, expectedNFTToLiquidator);

        // Then expect the NFTUnstaked event for NFTs returned to the owner
        vm.expectEmit(true, true, true, true);
        emit NFTUnstaked(localClient1, address(bondNFT), 1, remainingNFTs);

        vm.prank(localClient2);
        nftStaking.liquidate(address(bondNFT), 1, localClient1);

        // Verify the result of liquidation
        assertEq(
            bondNFT.balanceOf(localClient2, 1), expectedNFTToLiquidator, "Liquidator should receive correct NFT amount"
        );
        assertEq(
            bondNFT.balanceOf(localClient1, 1),
            10 - expectedNFTToLiquidator,
            "Original owner should receive remaining NFTs"
        );
    }

    /**
     * @notice Test for Case 3 (partial liquidation) event emission when all NFTs go to liquidator
     * This test verifies that only the Liquidated event is emitted (no NFTUnstaked event)
     * when a position is partially liquidated but all NFTs go to the liquidator
     */
    function testLiquidateCase3EventAllNFTsToLiquidator() public {
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

        // Borrow an amount that will result in debt close to maxBorrow
        // This will cause all NFTs to go to liquidator when liquidated
        uint256 maxBorrowAmount = nftStaking.userAvailableToBorrow(localClient1);
        uint256 borrowAmount = maxBorrowAmount * 9 / 10; // Borrow 90% of available amount
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

        // Calculate how many NFTs will be liquidated
        NFTStakingAndBorrowing.UserStats memory userStats = nftStaking.getUserStats(localClient1);
        uint256 currentDebt = userStats.debt;
        BondNFT.Metadata memory metadata = bondNFT.getMetaData(1);
        uint256 maxBorrow =
            nftStaking.calculateMaxBorrow(userStats.staked, block.timestamp, metadata.expirationTimestamp);

        // Verify this is Case 3 (partial liquidation)
        assertLt(currentDebt, maxBorrow, "This should be a partial liquidation (Case 3)");

        // Calculate how many NFTs will be liquidated
        uint256 expectedNFTToLiquidator = (currentDebt * 10 / maxBorrow) + (currentDebt * 10 % maxBorrow == 0 ? 0 : 1);

        // Calculate remaining NFTs
        uint256 remainingNFTs = 10 - expectedNFTToLiquidator;

        // Ensure this test case has NO remaining NFTs to return to owner
        assertEq(remainingNFTs, 0, "This test requires all NFTs to go to liquidator");

        // Expect only the Liquidated event (no NFTUnstaked event)
        vm.expectEmit(true, true, true, true);
        emit Liquidated(localClient1, localClient2, address(bondNFT), 1, 10);

        vm.prank(localClient2);
        nftStaking.liquidate(address(bondNFT), 1, localClient1);

        // Verify the result of liquidation
        assertEq(bondNFT.balanceOf(localClient2, 1), 10, "Liquidator should receive all NFTs");
        assertEq(bondNFT.balanceOf(localClient1, 1), 0, "Original owner should receive no NFTs");
    }
}
