// SPDX-License-Identifier: MIT
pragma solidity >=0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {BondNFT} from "../src/BondNFT.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract BondNFTEventsTest is Test {
    BondNFT public bondNFT;
    address public owner;
    address public user1;
    address public user2;

    event MintAllowanceSet(address user, uint256 id, uint256 allowedAmount);

    function setUp() public {
        owner = address(1);
        user1 = address(2);
        user2 = address(3);

        vm.startPrank(owner);
        // Deploy the contract as a proxy with the initializer
        bondNFT = BondNFT(
            UnsafeUpgrades.deployUUPSProxy(
                address(new BondNFT()),
                abi.encodeCall(BondNFT.initialize, (owner, "https://example.com/{id}.json"))
            )
        );

        BondNFT.Metadata memory metadata = BondNFT.Metadata({
            value: 1000_000000,
            couponValue: 50_000000,
            issueTimestamp: 1,
            expirationTimestamp: 1 + 31536000,
            ISIN: "US1234567890"
        });

        bondNFT.setMetaData(1, metadata);
        bondNFT.setMetaData(2, metadata);
        vm.stopPrank();
    }

    function testMintAllowanceSetEvent() public {
        uint256 tokenId = 1;
        uint256 allowedAmount = 10;

        vm.expectEmit(true, true, true, true);
        emit MintAllowanceSet(user1, tokenId, allowedAmount);

        vm.prank(owner);
        bondNFT.setAllowedMints(user1, tokenId, allowedAmount);

        assertEq(bondNFT.allowedMints(user1, tokenId), allowedAmount);
    }

    function testMultipleAllowanceEvents() public {
        vm.startPrank(owner);

        vm.expectEmit(true, true, true, true);
        emit MintAllowanceSet(user1, 1, 5);
        bondNFT.setAllowedMints(user1, 1, 5);

        vm.expectEmit(true, true, true, true);
        emit MintAllowanceSet(user1, 2, 10);
        bondNFT.setAllowedMints(user1, 2, 10);

        vm.expectEmit(true, true, true, true);
        emit MintAllowanceSet(user2, 1, 15);
        bondNFT.setAllowedMints(user2, 1, 15);

        vm.stopPrank();

        assertEq(bondNFT.allowedMints(user1, 1), 5);
        assertEq(bondNFT.allowedMints(user1, 2), 10);
        assertEq(bondNFT.allowedMints(user2, 1), 15);
    }

    function testUpdateAllowanceEvent() public {
        vm.prank(owner);
        bondNFT.setAllowedMints(user1, 1, 5);

        vm.expectEmit(true, true, true, true);
        emit MintAllowanceSet(user1, 1, 10);

        vm.prank(owner);
        bondNFT.setAllowedMints(user1, 1, 10);

        assertEq(bondNFT.allowedMints(user1, 1), 10);
    }

    function testZeroAllowanceEvent() public {
        vm.prank(owner);
        bondNFT.setAllowedMints(user1, 1, 5);

        vm.expectEmit(true, true, true, true);
        emit MintAllowanceSet(user1, 1, 0);

        vm.prank(owner);
        bondNFT.setAllowedMints(user1, 1, 0);

        assertEq(bondNFT.allowedMints(user1, 1), 0);
    }
}
