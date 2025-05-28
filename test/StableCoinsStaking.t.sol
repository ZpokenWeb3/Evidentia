// SPDX-License-Identifier: MIT
pragma solidity >=0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {NFTStakingAndBorrowing} from "../src/NFTStakingAndBorrowing.sol";
import {StableBondCoins} from "../src/StableBondCoins.sol";
import {StableCoinsStaking} from "../src/StableCoinsStaking.sol";
import {StableCoinsStakingV2} from "../src/V2/StableCoinsStakingV2.sol";
import {BondNFT} from "../src/BondNFT.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract StakingStablesTest is Test {
    NFTStakingAndBorrowing public nftStaking;
    BondNFT public bondNFT;
    StableBondCoins public stableBondCoins;
    StableCoinsStaking public stakingStables;
    address public owner;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

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
            issueTimestamp: 0,
            expirationTimestamp: 31536000,
            ISIN: "US1234567890"
        });

        bondNFT.setMetaData(1, metadata);
        bondNFT.setMetaData(2, metadata);
        bondNFT.setMetaData(3, metadata);
        nftStaking.whitelistNFT(address(bondNFT), true);

        stakingStables = StableCoinsStaking(
            Upgrades.deployUUPSProxy(
                "StableCoinsStaking.sol:StableCoinsStaking",
                abi.encodeCall(
                    stakingStables.initialize, (address(stableBondCoins), address(nftStaking), address(owner))
                )
            )
        );
        nftStaking.setStablesStakingAddress(address(stakingStables));
        nftStaking.setProtocolFee(0);
        vm.stopPrank();
    }

    function testNameSpace() public pure {
        assertEq(
            keccak256(abi.encode(uint256(keccak256("StableCoinsStaking.storage")) - 1)) & ~bytes32(uint256(0xff)),
            0x5ad9b57132bffc89e46deaf23730f9173da95952e39a655cdb65df9a44414600
        );
    }

    function testStakeStables() public {
        owner = address(1);
        address client1 = address(2);
        address client2 = address(3);
        address client3 = address(4);

        vm.startPrank(owner);
        bondNFT.setAllowedMints(client1, 1, 30);
        bondNFT.setAllowedMints(client2, 2, 10);
        bondNFT.setAllowedMints(client3, 3, 20);
        vm.stopPrank();

        vm.startPrank(client1);
        bondNFT.mint(1, 30, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        nftStaking.stakeNFT(address(bondNFT), 1, 30);
        nftStaking.borrow(0); // client1 borrows all available stables
        vm.stopPrank();

        vm.startPrank(client2);
        bondNFT.mint(2, 10, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        nftStaking.stakeNFT(address(bondNFT), 2, 10);
        nftStaking.borrow(0);
        stableBondCoins.approve(address(stakingStables), UINT256_MAX);
        uint256 amount = stableBondCoins.balanceOf(client2);
        // Client 2 stakes stables
        stakingStables.stake(amount);
        vm.stopPrank();

        vm.warp(30 days);
        vm.roll(2);

        uint256 staked = stakingStables.stakers(client2).stakedAmount;
        console.log("After 30 days...");
        console.log("Client2 staked : ", staked);
        console.log("Client2 rewards: ", stakingStables.pendingRewards(client2));

        vm.startPrank(client3);
        bondNFT.mint(3, 20, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        nftStaking.stakeNFT(address(bondNFT), 3, 20);
        nftStaking.borrow(0);
        stableBondCoins.approve(address(stakingStables), UINT256_MAX);
        amount = stableBondCoins.balanceOf(client3);
        // Client 3 stakes stables
        stakingStables.stake(amount);
        vm.stopPrank();

        vm.warp(90 days);
        vm.roll(3);

        console.log("After 90 days...");
        console.log("Client2 rewards: ", stakingStables.pendingRewards(client2));
        console.log("Client3 rewards: ", stakingStables.pendingRewards(client3));

        vm.warp(180 days);
        vm.roll(4);

        console.log("After 180 days...");
        console.log("Client2 rewards: ", stakingStables.pendingRewards(client2));
        console.log("Client3 rewards: ", stakingStables.pendingRewards(client3));

        vm.warp(270 days);
        vm.roll(5);

        console.log("After 270 days...");
        console.log("Client2 rewards: ", stakingStables.pendingRewards(client2));
        console.log("Client3 rewards: ", stakingStables.pendingRewards(client3));

        assertEq(stakingStables.pendingRewards(client2), 1715707503);
        assertEq(stakingStables.pendingRewards(client3), 2790515371);
    }

    function testRewards() public {
        owner = address(1);
        address client1 = address(2);
        address client2 = address(3);
        address client3 = address(4);

        vm.startPrank(owner);
        bondNFT.setAllowedMints(client1, 1, 30);
        bondNFT.setAllowedMints(client2, 2, 10);
        bondNFT.setAllowedMints(client3, 3, 20);
        vm.stopPrank();

        vm.startPrank(client1);
        bondNFT.mint(1, 30, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        nftStaking.stakeNFT(address(bondNFT), 1, 30);
        nftStaking.borrow(0); // client1 borrows all available stables
        vm.stopPrank();

        vm.startPrank(client2);
        bondNFT.mint(2, 10, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        nftStaking.stakeNFT(address(bondNFT), 2, 10);
        nftStaking.borrow(0);
        stableBondCoins.approve(address(stakingStables), UINT256_MAX);
        uint256 amount = stableBondCoins.balanceOf(client2);
        // Client 2 stakes stables
        stakingStables.stake(amount);
        vm.stopPrank();

        vm.warp(30 days);
        vm.roll(2);

        uint256 staked = stakingStables.stakers(client2).stakedAmount;
        console.log("After 30 days...");
        console.log("Client2 staked : ", staked);
        uint256 client2Rewards = stakingStables.pendingRewards(client2);
        console.log("Client2 rewards: ", client2Rewards);

        vm.prank(client2);
        stakingStables.claimRewards();

        assertEq(stableBondCoins.balanceOf(client2), client2Rewards);

        vm.startPrank(client3);
        bondNFT.mint(3, 20, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        nftStaking.stakeNFT(address(bondNFT), 3, 20);
        nftStaking.borrow(0);
        stableBondCoins.approve(address(stakingStables), UINT256_MAX);
        amount = stableBondCoins.balanceOf(client3);
        // Client 3 stakes stables
        stakingStables.stake(amount);
        vm.stopPrank();

        vm.warp(90 days);
        vm.roll(3);

        console.log("After 90 days...");
        console.log("Client3 staked : ", amount);
        uint256 client2Rewards2 = stakingStables.pendingRewards(client2);
        console.log("Client2 rewards: ", client2Rewards2);
        uint256 client3Rewards = stakingStables.pendingRewards(client3);
        console.log("Client3 rewards: ", client3Rewards);

        vm.prank(client2);
        stakingStables.claimRewards();
        vm.prank(client3);
        stakingStables.claimRewards();

        assertEq(stableBondCoins.balanceOf(client2), client2Rewards + client2Rewards2);
        assertEq(stableBondCoins.balanceOf(client3), client3Rewards);
    }

    function testWithdraw() public {
        owner = address(1);
        address client1 = address(2);
        address client2 = address(3);
        address client3 = address(4);

        vm.startPrank(owner);
        bondNFT.setAllowedMints(client1, 1, 30);
        bondNFT.setAllowedMints(client2, 2, 10);
        bondNFT.setAllowedMints(client3, 3, 20);
        vm.stopPrank();

        vm.startPrank(client1);
        bondNFT.mint(1, 30, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        nftStaking.stakeNFT(address(bondNFT), 1, 30);
        nftStaking.borrow(0); // client1 borrows all available stables
        vm.stopPrank();

        vm.startPrank(client2);
        bondNFT.mint(2, 10, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        nftStaking.stakeNFT(address(bondNFT), 2, 10);
        nftStaking.borrow(0);
        stableBondCoins.approve(address(stakingStables), UINT256_MAX);
        uint256 amount = stableBondCoins.balanceOf(client2);
        // Client 2 stakes stables
        stakingStables.stake(amount);
        vm.stopPrank();

        vm.warp(30 days);
        vm.roll(2);

        uint256 staked = stakingStables.stakers(client2).stakedAmount;
        console.log("After 30 days...");
        console.log("Client2 staked : ", staked);
        console.log("Client2 rewards: ", stakingStables.pendingRewards(client2));

        vm.startPrank(client3);
        bondNFT.mint(3, 20, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        nftStaking.stakeNFT(address(bondNFT), 3, 20);
        nftStaking.borrow(0);
        stableBondCoins.approve(address(stakingStables), UINT256_MAX);
        amount = stableBondCoins.balanceOf(client3);
        // Client 3 stakes stables
        stakingStables.stake(amount);
        vm.stopPrank();

        vm.warp(90 days);
        vm.roll(3);

        console.log("After 90 days...");
        console.log("Client2 rewards: ", stakingStables.pendingRewards(client2));
        console.log("Client3 rewards: ", stakingStables.pendingRewards(client3));

        vm.prank(client2);
        stakingStables.withdraw(staked / 2);

        vm.warp(180 days);
        vm.roll(4);

        console.log("After 180 days...");
        console.log("Client2 rewards: ", stakingStables.pendingRewards(client2));
        console.log("Client3 rewards: ", stakingStables.pendingRewards(client3));

        vm.prank(client2);
        stakingStables.withdraw(staked / 2);

        vm.warp(270 days);
        vm.roll(5);

        console.log("After 270 days...");
        console.log("Client2 rewards: ", stakingStables.pendingRewards(client2));
        console.log("Client3 rewards: ", stakingStables.pendingRewards(client3));

        staked = stakingStables.stakers(client2).stakedAmount;
        assertEq(staked, 0);
    }

    function testRestakeRewards() public {
        owner = address(1);
        address client1 = address(2);
        address client2 = address(3);
        address client3 = address(4);

        vm.startPrank(owner);
        bondNFT.setAllowedMints(client1, 1, 30);
        bondNFT.setAllowedMints(client2, 2, 10);
        bondNFT.setAllowedMints(client3, 3, 20);
        vm.stopPrank();

        vm.startPrank(client1);
        bondNFT.mint(1, 30, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        nftStaking.stakeNFT(address(bondNFT), 1, 30);
        nftStaking.borrow(0); // client1 borrows all available stables
        vm.stopPrank();

        vm.startPrank(client2);
        bondNFT.mint(2, 10, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        nftStaking.stakeNFT(address(bondNFT), 2, 10);
        nftStaking.borrow(0);
        stableBondCoins.approve(address(stakingStables), UINT256_MAX);
        uint256 amount = stableBondCoins.balanceOf(client2);
        // Client 2 stakes stables
        stakingStables.stake(amount);
        vm.stopPrank();

        vm.warp(30 days);
        vm.roll(2);

        uint256 staked = stakingStables.stakers(client2).stakedAmount;
        console.log("After 30 days...");
        console.log("Client2 staked : ", staked);
        console.log("Client2 rewards: ", stakingStables.pendingRewards(client2));

        vm.startPrank(client3);
        bondNFT.mint(3, 20, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        nftStaking.stakeNFT(address(bondNFT), 3, 20);
        nftStaking.borrow(0);
        stableBondCoins.approve(address(stakingStables), UINT256_MAX);
        amount = stableBondCoins.balanceOf(client3);
        // Client 3 stakes stables
        stakingStables.stake(amount);
        vm.stopPrank();

        vm.startPrank(client2);
        stakingStables.claimRewards();
        stakingStables.stake(stableBondCoins.balanceOf(client2));
        vm.stopPrank();

        vm.warp(90 days);
        vm.roll(3);

        staked = stakingStables.stakers(client2).stakedAmount;
        console.log("After 90 days...");
        console.log("Client2 staked : ", staked);
        console.log("Client2 rewards: ", stakingStables.pendingRewards(client2));
        console.log("Client3 rewards: ", stakingStables.pendingRewards(client3));

        vm.startPrank(client2);
        stakingStables.claimRewards();
        stakingStables.stake(stableBondCoins.balanceOf(client2));
        vm.stopPrank();

        vm.warp(180 days);
        vm.roll(4);

        staked = stakingStables.stakers(client2).stakedAmount;
        console.log("After 180 days...");
        console.log("Client2 staked : ", staked);
        console.log("Client2 rewards: ", stakingStables.pendingRewards(client2));
        console.log("Client3 rewards: ", stakingStables.pendingRewards(client3));

        vm.startPrank(client2);
        stakingStables.claimRewards();
        stakingStables.stake(stableBondCoins.balanceOf(client2));
        vm.stopPrank();

        vm.warp(270 days);
        vm.roll(5);

        staked = stakingStables.stakers(client2).stakedAmount;
        console.log("After 270 days...");
        console.log("Client2 staked : ", staked);
        console.log("Client2 rewards: ", stakingStables.pendingRewards(client2));
        console.log("Client3 rewards: ", stakingStables.pendingRewards(client3));

        assertEq(staked, 10125390760);
    }

    function testStakeNFTAndStables() public {
        owner = address(1);
        address client1 = address(2);
        address client2 = address(3);
        address client3 = address(4);

        vm.startPrank(owner);
        bondNFT.setAllowedMints(client1, 1, 30);
        bondNFT.setAllowedMints(client2, 2, 10);
        bondNFT.setAllowedMints(client3, 3, 20);
        vm.stopPrank();

        vm.startPrank(client1);
        bondNFT.mint(1, 30, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        nftStaking.stakeNFT(address(bondNFT), 1, 30);
        nftStaking.borrow(0); // client1 borrows all available stables
        vm.stopPrank();

        vm.startPrank(client2);
        bondNFT.mint(2, 10, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        nftStaking.stakeNFTandStables(address(bondNFT), 2, 10);
        vm.stopPrank();

        vm.warp(30 days);
        vm.roll(2);

        uint256 staked = stakingStables.stakers(client2).stakedAmount;
        console.log("After 30 days...");
        console.log("Client2 staked : ", staked);
        console.log("Client2 rewards: ", stakingStables.pendingRewards(client2));

        vm.startPrank(client3);
        bondNFT.mint(3, 20, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        nftStaking.stakeNFTandStables(address(bondNFT), 3, 20);
        vm.stopPrank();

        vm.warp(90 days);
        vm.roll(3);

        console.log("After 90 days...");
        console.log("Client2 rewards: ", stakingStables.pendingRewards(client2));
        console.log("Client3 rewards: ", stakingStables.pendingRewards(client3));

        vm.warp(180 days);
        vm.roll(4);

        console.log("After 180 days...");
        console.log("Client2 rewards: ", stakingStables.pendingRewards(client2));
        console.log("Client3 rewards: ", stakingStables.pendingRewards(client3));

        vm.warp(270 days);
        vm.roll(5);

        console.log("After 270 days...");
        console.log("Client2 rewards: ", stakingStables.pendingRewards(client2));
        console.log("Client3 rewards: ", stakingStables.pendingRewards(client3));

        assertEq(stakingStables.pendingRewards(client2), 1715707503);
        assertEq(stakingStables.pendingRewards(client3), 2790515371);
    }

    function testStakeStablesFromNFTStaking() public {
        owner = address(1);
        address client1 = address(2);
        address client2 = address(3);
        address client3 = address(4);

        vm.startPrank(owner);
        bondNFT.setAllowedMints(client1, 1, 30);
        bondNFT.setAllowedMints(client2, 2, 10);
        bondNFT.setAllowedMints(client3, 3, 20);
        vm.stopPrank();

        vm.startPrank(client1);
        bondNFT.mint(1, 30, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        nftStaking.stakeNFT(address(bondNFT), 1, 30);
        nftStaking.borrow(0); // client1 borrows all available stables
        vm.stopPrank();

        vm.startPrank(client2);
        bondNFT.mint(2, 10, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        nftStaking.stakeNFT(address(bondNFT), 2, 10);
        nftStaking.stakeStables(1000_000000);
        nftStaking.stakeStables(0);
        vm.stopPrank();

        vm.warp(30 days);
        vm.roll(2);

        uint256 staked = stakingStables.stakers(client2).stakedAmount;
        console.log("After 30 days...");
        console.log("Client2 staked : ", staked);
        console.log("Client2 rewards: ", stakingStables.pendingRewards(client2));

        vm.startPrank(client3);
        bondNFT.mint(3, 20, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        nftStaking.stakeNFT(address(bondNFT), 3, 20);
        nftStaking.stakeStables(0);
        vm.stopPrank();

        vm.warp(90 days);
        vm.roll(3);

        console.log("After 90 days...");
        console.log("Client2 rewards: ", stakingStables.pendingRewards(client2));
        console.log("Client3 rewards: ", stakingStables.pendingRewards(client3));

        vm.warp(180 days);
        vm.roll(4);

        console.log("After 180 days...");
        console.log("Client2 rewards: ", stakingStables.pendingRewards(client2));
        console.log("Client3 rewards: ", stakingStables.pendingRewards(client3));

        vm.warp(270 days);
        vm.roll(5);

        console.log("After 270 days...");
        console.log("Client2 rewards: ", stakingStables.pendingRewards(client2));
        console.log("Client3 rewards: ", stakingStables.pendingRewards(client3));

        assertEq(stakingStables.pendingRewards(client2), 1715707503);
        assertEq(stakingStables.pendingRewards(client3), 2790515371);
    }

    function testUUPSUpgrade() public {
        address defaultAdmin = owner;

        vm.prank(defaultAdmin);
        address proxy = Upgrades.deployUUPSProxy(
            "StableCoinsStaking.sol:StableCoinsStaking",
            abi.encodeCall(StableCoinsStaking.initialize, (address(stableBondCoins), address(nftStaking), defaultAdmin))
        );
        StableCoinsStaking instance = StableCoinsStaking(proxy);

        address client2 = address(2);
        vm.startPrank(defaultAdmin);
        bondNFT.setAllowedMints(client2, 2, 10);
        vm.stopPrank();

        vm.startPrank(client2);
        bondNFT.mint(2, 10, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        nftStaking.stakeNFT(address(bondNFT), 2, 10);
        nftStaking.borrow(0);
        stableBondCoins.approve(address(instance), UINT256_MAX);
        uint256 amount = stableBondCoins.balanceOf(client2);
        instance.stake(amount);
        vm.stopPrank();

        uint256 stakedAmount = instance.stakers(client2).stakedAmount;
        assertEq(stakedAmount, amount, "Staked amount should match");
        address implAddressV1 = Upgrades.getImplementationAddress(proxy);

        //         address unauthorizedUser = address(3);
        //         vm.prank(unauthorizedUser);
        //         vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, unauthorizedUser, 0));
        //         Upgrades.upgradeProxy(
        //             proxy,
        //             "StableCoinsStakingV2.sol:StableCoinsStakingV2",
        //             abi.encodeCall(StableCoinsStakingV2.initializeV2, ()),
        //             unauthorizedUser
        //         );

        Upgrades.upgradeProxy(
            proxy,
            "StableCoinsStakingV2.sol:StableCoinsStakingV2",
            abi.encodeCall(StableCoinsStakingV2.initializeV2, ()),
            defaultAdmin
        );

        StableCoinsStakingV2 instance2 = StableCoinsStakingV2(proxy);
        address implAddressV2 = Upgrades.getImplementationAddress(proxy);
        assertFalse(implAddressV2 == implAddressV1, "Implementation address should change");
        assertEq(instance2.stakers(client2).stakedAmount, stakedAmount, "Staked amount should be preserved");
        assertEq(instance2.getInitializedVersion(), 2, "Version should be updated to 2");
        assertEq(instance2.newFeature(), "V2 Feature", "Should use V2 implementation");
    }

    function testRewardsWithFee() public {
        owner = address(1);
        address client1 = address(2);
        address client2 = address(3);
        address client3 = address(4);
        address feeReceiver = address(555);

        vm.startPrank(owner);
        bondNFT.setAllowedMints(client1, 1, 30);
        bondNFT.setAllowedMints(client2, 2, 10);
        bondNFT.setAllowedMints(client3, 3, 20);
        nftStaking.setProtocolFee(1000); // 10% of rewards
        nftStaking.setFeeReceiver(feeReceiver);
        vm.stopPrank();

        vm.startPrank(client1);
        bondNFT.mint(1, 30, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        nftStaking.stakeNFT(address(bondNFT), 1, 30);
        nftStaking.borrow(0); // client1 borrows all available stables
        vm.stopPrank();

        vm.startPrank(client2);
        bondNFT.mint(2, 10, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        nftStaking.stakeNFT(address(bondNFT), 2, 10);
        nftStaking.borrow(0);
        stableBondCoins.approve(address(stakingStables), UINT256_MAX);
        uint256 amount = stableBondCoins.balanceOf(client2);
        // Client 2 stakes stables
        stakingStables.stake(amount);
        vm.stopPrank();

        vm.warp(30 days);
        vm.roll(2);

        uint256 staked = stakingStables.stakers(client2).stakedAmount;
        console.log("After 30 days...");
        console.log("Client2 staked : ", staked);
        uint256 client2Rewards = stakingStables.pendingRewards(client2);
        console.log("Client2 rewards: ", client2Rewards);
        assertEq(stableBondCoins.balanceOf(feeReceiver), 0);
        vm.prank(client2);
        stakingStables.claimRewards();

        assertEq(stableBondCoins.balanceOf(client2), client2Rewards);
        // Calculate fee if it takes 10% out of total rewards
        assertEq(stableBondCoins.balanceOf(feeReceiver), (client2Rewards * 100000000 + 5) / 899999994);

        vm.startPrank(client3);
        bondNFT.mint(3, 20, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        nftStaking.stakeNFT(address(bondNFT), 3, 20);
        nftStaking.borrow(0);
        stableBondCoins.approve(address(stakingStables), UINT256_MAX);
        amount = stableBondCoins.balanceOf(client3);
        // Client 3 stakes stables
        stakingStables.stake(amount);
        vm.stopPrank();

        vm.warp(90 days);
        vm.roll(3);

        console.log("After 90 days...");
        console.log("Client3 staked : ", amount);
        uint256 client2Rewards2 = stakingStables.pendingRewards(client2);
        console.log("Client2 rewards: ", client2Rewards2);
        uint256 client3Rewards = stakingStables.pendingRewards(client3);
        console.log("Client3 rewards: ", client3Rewards);

        vm.prank(client2);
        stakingStables.claimRewards();
        vm.prank(client3);
        stakingStables.claimRewards();

        assertEq(stableBondCoins.balanceOf(client2), client2Rewards + client2Rewards2);
        assertEq(stableBondCoins.balanceOf(client3), client3Rewards);

        assertEq(
            stableBondCoins.balanceOf(feeReceiver),
            ((client2Rewards + client2Rewards2 + client3Rewards) * 100000000 + 5) / 899999994
        );
    }
}
