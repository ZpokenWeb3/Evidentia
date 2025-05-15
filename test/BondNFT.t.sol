// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {BondNFT} from "../src/BondNFT.sol";
import {BondNFTV2} from "../src/V2/BondNFTV2.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract BondNFTTest is Test {
    BondNFT public bondNFT;
    address public owner;
    address public account1;
    address public account2;

    function setUp() public {
        owner = address(this);
        account1 = address(1);
        account2 = address(2);
        // Deploy the contract as a proxy with the initializer
        bondNFT = BondNFT(
            Upgrades.deployUUPSProxy(
                "BondNFT.sol", abi.encodeCall(BondNFT.initialize, (owner, "https://example.com/{id}.json"))
            )
        );
        bondNFT.setAllowedMints(account1, 1, 10);
    }

    function testNameSpace() public pure {
        assertEq(
            keccak256(abi.encode(uint256(keccak256("BondNFT.storage")) - 1)) & ~bytes32(uint256(0xff)),
            0xffef8b0e9aa2c483e819ac9d28d3b5f004d7e8fbb6ec97cdc9221e749673c000
        );
    }

    function testInitialOwner() public view {
        assertEq(bondNFT.owner(), owner);
    }

    function testSetURI() public {
        string memory newURI = "https://newexample.com/{id}.json";
        bondNFT.setURI(newURI);
        assertEq(bondNFT.uri(1), newURI);
    }

    function testSetMetaDataAndGetMetaData() public {
        BondNFT.Metadata memory metadata = BondNFT.Metadata({
            value: 100,
            couponValue: 5,
            issueTimestamp: block.timestamp,
            expirationTimestamp: block.timestamp + 365 days,
            ISIN: "US1234567890"
        });
        bondNFT.setMetaData(1, metadata);
        BondNFT.Metadata memory retrievedMetadata = bondNFT.getMetaData(1);
        assertEq(retrievedMetadata.value, metadata.value);
        assertEq(retrievedMetadata.couponValue, metadata.couponValue);
        assertEq(retrievedMetadata.issueTimestamp, metadata.issueTimestamp);
        assertEq(retrievedMetadata.expirationTimestamp, metadata.expirationTimestamp);
        assertEq(retrievedMetadata.ISIN, metadata.ISIN);
    }

    function testMint() public {
        uint256 id = 1;
        uint256 amount = 10;
        vm.prank(account1);
        bondNFT.mint(id, amount, "");
        assertEq(bondNFT.balanceOf(account1, id), amount);
    }

    function testBurn() public {
        uint256 id = 1;
        uint256 amount = 10;
        vm.prank(account1);
        bondNFT.mint(id, amount, "");
        vm.prank(account1);
        bondNFT.burn(id, amount);
        assertEq(bondNFT.balanceOf(account1, id), 0);
    }

    function testRemainingMints() public {
        // Initial remaining mints should be the allowed amount
        assertEq(bondNFT.remainingMints(account1, 1), 10);

        // After minting, remainingMints should decrease
        vm.prank(account1);
        bondNFT.mint(1, 3, "");
        assertEq(bondNFT.remainingMints(account1, 1), 7);

        // Mint more tokens
        vm.prank(account1);
        bondNFT.mint(1, 2, "");
        assertEq(bondNFT.remainingMints(account1, 1), 5);

        // Account with no allowance should have 0 remainingMints
        assertEq(bondNFT.remainingMints(account2, 1), 0);
    }

    function testNameAndSymbol() public view {
        assertEq(bondNFT.name(), "BondNFT");
        assertEq(bondNFT.symbol(), "BNFT");
    }

    function testMintBatch() public {
        uint256[] memory ids = new uint256[](2);
        ids[0] = 1;
        ids[1] = 2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 5;
        amounts[1] = 5;

        // Set allowed mints for both IDs
        bondNFT.setAllowedMints(account1, 2, 10);

        // Account should be able to mint
        vm.prank(account1);
        bondNFT.mintBatch(ids, amounts, "");

        // Check balances
        assertEq(bondNFT.balanceOf(account1, 1), 5);
        assertEq(bondNFT.balanceOf(account1, 2), 5);

        // Check mintedPerUser values are updated
        assertEq(bondNFT.remainingMints(account1, 1), 5);
        assertEq(bondNFT.remainingMints(account1, 2), 5);
    }

    function testUUPSUpgrade() public {
        address proxy = Upgrades.deployUUPSProxy(
            "BondNFT.sol", abi.encodeCall(BondNFT.initialize, (owner, "https://example.com/{id}.json"))
        );
        BondNFT instance = BondNFT(proxy);

        BondNFT.Metadata memory metadata = BondNFT.Metadata({
            value: 100,
            couponValue: 5,
            issueTimestamp: block.timestamp,
            expirationTimestamp: block.timestamp + 365 days,
            ISIN: "US1234567890"
        });
        instance.setMetaData(1, metadata);
        instance.setAllowedMints(account1, 1, 10);

        vm.prank(account1);
        instance.mint(1, 5, "");

        assertEq(instance.name(), "BondNFT");
        assertEq(instance.balanceOf(account1, 1), 5);
        assertEq(instance.getMetaData(1).value, 100);
        address implAddressV1 = Upgrades.getImplementationAddress(proxy);

        //         vm.prank(account2);
        //         vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, account2));
        //         Upgrades.upgradeProxy(
        //             proxy,
        //             "BondNFTV2.sol",
        //             abi.encodeCall(BondNFTV2.initializeV2, ()),
        //             account2
        //         );

        Upgrades.upgradeProxy(proxy, "BondNFTV2.sol", abi.encodeCall(BondNFTV2.initializeV2, ()), owner);

        BondNFTV2 instance2 = BondNFTV2(proxy);
        address implAddressV2 = Upgrades.getImplementationAddress(proxy);
        assertFalse(implAddressV2 == implAddressV1, "Implementation address should change");
        assertEq(instance2.name(), "BondNFT", "Name should not change");
        assertEq(instance2.balanceOf(account1, 1), 5, "Balance should be preserved");
        assertEq(instance2.getMetaData(1).value, 100, "Metadata should be preserved");
        assertEq(instance2.getInitializedVersion(), 2, "Version should be updated to 2");
        assertEq(instance2.newFeature(), "V2 Feature", "Should use V2 implementation");
    }
}
