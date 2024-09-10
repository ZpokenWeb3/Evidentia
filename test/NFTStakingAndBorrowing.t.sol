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
            issueTimestamp: block.timestamp,
            expirationTimestamp: block.timestamp + 365 days,
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

        assertEq(totalStats.staked, 10500_000000);

        NFTStakingAndBorrowing.UserStats memory userStats = nftStaking.getUserStats(owner);

        assertEq(userStats.staked, 10500_000000);
        assertEq(userStats.available, 937_4999999);

    }

    function test_borrow() public {
        owner = address(1);

        vm.startPrank(owner);
        nftStaking.stakeNFT(address(bondNFT), 1, 10);
        NFTStakingAndBorrowing.UserStats memory userStats = nftStaking.getUserStats(owner);

        assertEq(userStats.staked, 10500_000000);
        assertEq(userStats.available, 9374_999999);

        nftStaking.borrow(500_000000);
        vm.stopPrank();

        userStats = nftStaking.getUserStats(owner);

        assertEq(userStats.debt, 500_000000);
        assertEq(userStats.available, 8875_000032);

        NFTStakingAndBorrowing.TotalStats memory totalStats = nftStaking.getTotalStats();
        assertEq(totalStats.borrowed, 500_000000);
        
    }

}