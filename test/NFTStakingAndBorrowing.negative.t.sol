// SPDX-License-Identifier: MIT
pragma solidity >=0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {NFTStakingAndBorrowing} from "../src/NFTStakingAndBorrowing.sol";
import {StableBondCoins} from "../src/StableBondCoins.sol";
import {BondNFT} from "../src/BondNFT.sol";
import {StableCoinsStaking} from "../src/StableCoinsStaking.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract NFTStakingAndBorrowingNegativeTest is Test {
    NFTStakingAndBorrowing public nftStaking;
    BondNFT public bondNFT;
    StableBondCoins public stableBondCoins;
    StableCoinsStaking public stableStaking;
    address public owner;
    address public client1;
    address public client2;
    address public notWhitelistedNFT;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    uint256 public constant MAX_UINT = type(uint256).max;

    function setUp() public {
        owner = address(1);
        client1 = address(2);
        client2 = address(3);
        notWhitelistedNFT = address(4);

        vm.startPrank(owner);

        // Deploy the contract as a proxy with the initializer
        bondNFT = BondNFT(
            UnsafeUpgrades.deployUUPSProxy(
                address(new BondNFT()), abi.encodeCall(BondNFT.initialize, (owner, "https://example.com/{id}.json"))
            )
        );

        stableBondCoins = StableBondCoins(
            UnsafeUpgrades.deployUUPSProxy(
                address(new StableBondCoins()), abi.encodeCall(stableBondCoins.initialize, (owner, owner))
            )
        );

        nftStaking = new NFTStakingAndBorrowing(address(stableBondCoins));

        stableStaking = StableCoinsStaking(
            UnsafeUpgrades.deployUUPSProxy(
                address(new StableCoinsStaking()),
                abi.encodeCall(
                    stableStaking.initialize, (address(stableBondCoins), address(nftStaking), address(owner))
                )
            )
        );

        nftStaking.setStablesStakingAddress(address(stableStaking));
        stableBondCoins.grantRole(MINTER_ROLE, address(nftStaking));
        stableBondCoins.grantRole(MINTER_ROLE, address(stableStaking));

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

        vm.prank(client1);
        bondNFT.mint(2, 10, "");
        vm.prank(client1);
        bondNFT.setApprovalForAll(address(nftStaking), true);

        vm.prank(client2);
        bondNFT.mint(3, 10, "");
        vm.prank(client2);
        bondNFT.setApprovalForAll(address(nftStaking), true);
    }

    function testStakeNFTNotWhitelistedNFTReverts() public {
        vm.prank(client1);
        vm.expectRevert(NFTStakingAndBorrowing.NFTNotWhitelisted.selector);
        nftStaking.stakeNFT(notWhitelistedNFT, 1, 1);
    }

    function testStakeNFTInsufficientNFTBalanceReverts() public {
        vm.prank(client1);
        vm.expectRevert(NFTStakingAndBorrowing.InsufficientNFTBalance.selector);
        nftStaking.stakeNFT(address(bondNFT), 1, 1); // client1 doesn't have token 1
    }

    function testUnstakeNFTNotWhitelistedNFTReverts() public {
        vm.prank(client1);
        vm.expectRevert(NFTStakingAndBorrowing.NFTNotWhitelisted.selector);
        nftStaking.unstakeNFT(notWhitelistedNFT, 1, 1);
    }

    function testUnstakeNFTInsufficientNFTBalanceReverts() public {
        vm.prank(client1);
        vm.expectRevert(NFTStakingAndBorrowing.InsufficientNFTBalance.selector);
        nftStaking.unstakeNFT(address(bondNFT), 2, 11); // Client1 has only 10 tokens
    }

    function testUnstakeNFTNotEnoughCollateralReverts() public {
        vm.prank(client1);
        nftStaking.stakeNFT(address(bondNFT), 2, 10);

        vm.startPrank(client1);
        stableBondCoins.approve(address(nftStaking), MAX_UINT);

        // Borrow most of the available funds, leaving some free collateral
        uint256 maxBorrow = nftStaking.userAvailableToBorrow(client1);
        uint256 borrowAmount = maxBorrow - 1_000000;
        nftStaking.borrow(borrowAmount);

        uint256 availableToUnstake = nftStaking.userAvailableToUnstake(client1, address(bondNFT), 2);
        console.log("Available to unstake:", availableToUnstake);

        // Try to unstake more than available, don't check exact error selector
        vm.expectRevert();
        nftStaking.unstakeNFT(address(bondNFT), 2, 10);
        vm.stopPrank();
    }

    function testBorrowExceedReverts() public {
        vm.prank(client1);
        nftStaking.stakeNFT(address(bondNFT), 2, 5);

        vm.startPrank(client1);
        stableBondCoins.approve(address(nftStaking), MAX_UINT);

        // Use a large value, more than the number of tokens in the system
        uint256 largeAmount = 1000_000_000000;
        vm.expectRevert();
        nftStaking.borrow(largeAmount);
        vm.stopPrank();
    }

    function testRepayInsufficientBalanceToRepayReverts() public {
        vm.prank(client1);
        nftStaking.stakeNFT(address(bondNFT), 2, 10);

        vm.startPrank(client1);
        stableBondCoins.approve(address(nftStaking), MAX_UINT);
        uint256 borrowAmount = 1000_000000;
        nftStaking.borrow(borrowAmount);

        // Transfer tokens away so client1 has insufficient balance
        stableBondCoins.transfer(client2, borrowAmount);

        vm.expectRevert(NFTStakingAndBorrowing.InsufficientBalanceToRepay.selector);
        nftStaking.repay(borrowAmount);
        vm.stopPrank();
    }

    function testLiquidateNotWhitelistedNFTReverts() public {
        vm.prank(client1);
        vm.expectRevert(NFTStakingAndBorrowing.NFTNotWhitelisted.selector);
        nftStaking.liquidate(notWhitelistedNFT, 1, client2);
    }

    function testLiquidateInsufficientNFTBalanceReverts() public {
        vm.prank(client1);
        vm.expectRevert(NFTStakingAndBorrowing.InsufficientNFTBalance.selector);
        nftStaking.liquidate(address(bondNFT), 1, client2); // client2 doesn't have token 1 staked
    }

    function testLiquidateTooEarlyToLiquidateReverts() public {
        vm.prank(client1);
        nftStaking.stakeNFT(address(bondNFT), 2, 10);

        vm.startPrank(client1);
        stableBondCoins.approve(address(nftStaking), MAX_UINT);
        uint256 borrowAmount = 1000_000000;
        nftStaking.borrow(borrowAmount);
        vm.stopPrank();

        // Should fail because it's too early for liquidation
        vm.startPrank(client2);
        stableBondCoins.approve(address(nftStaking), MAX_UINT);
        vm.expectRevert(NFTStakingAndBorrowing.TooEarlyToLiquidate.selector);
        nftStaking.liquidate(address(bondNFT), 2, client1);
        vm.stopPrank();
    }

    function testOnlyOwnerFunctionsReverts() public {
        vm.prank(client1);
        vm.expectRevert();
        nftStaking.whitelistNFT(address(bondNFT), true);

        vm.prank(client1);
        vm.expectRevert();
        nftStaking.setProtocolYield(1200);

        vm.prank(client1);
        vm.expectRevert();
        nftStaking.setSafetyFee(500);

        vm.prank(client1);
        vm.expectRevert();
        nftStaking.setLiquidationTimeWindow(45 days);

        vm.prank(client1);
        vm.expectRevert();
        nftStaking.setStablesStakingAddress(address(1));
    }

    function testOnlyStablesStakingGetRewardsReverts() public {
        vm.prank(client1);
        vm.expectRevert(NFTStakingAndBorrowing.OnlyStableStakingContract.selector);
        nftStaking.getRewards();
    }

    function testZeroAddressStableStakingReverts() public {
        vm.expectRevert(NFTStakingAndBorrowing.ZeroAddress.selector);
        vm.prank(owner);
        nftStaking.setStablesStakingAddress(address(0));
    }

    function testCalculateMaxBorrowOverflowReverts() public {
        vm.expectRevert(NFTStakingAndBorrowing.AmountOverflow.selector);
        nftStaking.calculateMaxBorrow(type(uint256).max / 10 ^ 18 + 1, 90, 1_000_000);
    }
}
