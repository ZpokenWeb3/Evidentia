// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {NFTStakingAndBorrowing} from "../src/NFTStakingAndBorrowing.sol";
import {StableBondCoins} from "../src/StableBondCoins.sol";
import {StableCoinsStaking} from "../src/StableCoinsStaking.sol";
import {BondNFT} from "../src/BondNFT.sol";

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

        stakingStables = new StableCoinsStaking(address(stableBondCoins), address(nftStaking));
        vm.stopPrank();
    }

    function test_stake_stables() public {
        owner = address(1);
        address client1 = address(2);
        address client2 = address(3);
        address client3 = address(4);

        vm.startPrank(owner);
        bondNFT.setAllowedMints(client1, 2, 10);
        bondNFT.setAllowedMints(client2, 3, 10);
        bondNFT.setAllowedMints(client3, 3, 20);
        vm.stopPrank();

        vm.startPrank(client1);
        bondNFT.mint(2, 10, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        nftStaking.stakeNFT(address(bondNFT), 2, 10);
        nftStaking.borrow(0);
        vm.stopPrank();

        vm.startPrank(client2);
        bondNFT.mint(3, 10, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        nftStaking.stakeNFT(address(bondNFT), 3, 10);
        nftStaking.borrow(0);
        stableBondCoins.approve(address(stakingStables), UINT256_MAX);
        uint256 amount = stableBondCoins.balanceOf(client2);
        // Client 2 stakes stables
        stakingStables.stake(amount);
        vm.stopPrank();

        vm.warp(90 days);
        vm.roll(2);

        (uint256 staked,,) = stakingStables.stakers(client2);
        console.log("Client2 staked : ", staked);
        console.log("Pending rewards: ", nftStaking.getRewardAmount());
        console.log("Client2 rewards: ", stakingStables.pendingRewards(client2));
        console.log("Client2 APY    : ", stakingStables.userAPY(client2));

        vm.startPrank(client3);
        bondNFT.mint(3, 20, "");
        bondNFT.setApprovalForAll(address(nftStaking), true);
        nftStaking.stakeNFT(address(bondNFT), 3, 20);
        nftStaking.borrow(0);
        stableBondCoins.approve(address(stakingStables), UINT256_MAX);
        amount = stableBondCoins.balanceOf(client3);
        // Client 2 stakes stables
        stakingStables.stake(amount);
        vm.stopPrank();

        vm.warp(180 days);
        vm.roll(3);

        console.log("After 90 days...");
        console.log("Pending rewards: ", nftStaking.getRewardAmount());
        console.log("Client2 rewards: ", stakingStables.pendingRewards(client2));
        console.log("Client3 rewards: ", stakingStables.pendingRewards(client3));
        console.log("Client2 APY    : ", stakingStables.userAPY(client2));
        console.log("Client3 APY    : ", stakingStables.userAPY(client3));
    }
}
