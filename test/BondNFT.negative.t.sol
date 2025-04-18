// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {BondNFT} from "../src/BondNFT.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract BondNFTNegativeTest is Test {
    BondNFT public bondNFT;
    address public owner;
    address public account1;
    address public account2;

    // Define event with same signature as in the contract
    event MintAllowanceSet(address user, uint256 id, uint256 allowedAmount);

    function setUp() public {
        owner = address(this);
        account1 = address(1);
        account2 = address(2);

        // Deploy the contract as a proxy with the initializer
        bondNFT = BondNFT(
            Upgrades.deployUUPSProxy(
                "BondNFT.sol",
                abi.encodeCall(BondNFT.initialize, (owner, "https://example.com/{id}.json"))
            )
        );

        bondNFT.setAllowedMints(account1, 1, 10);
    }

    // Test access control for owner-only functions
    function testSetURINotOwner() public {
        vm.prank(account1);
        vm.expectRevert();
        bondNFT.setURI("https://newexample.com/{id}.json");
    }

    function testSetMetaDataNotOwner() public {
        BondNFT.Metadata memory metadata = BondNFT.Metadata({
            value: 100,
            couponValue: 5,
            issueTimestamp: block.timestamp,
            expirationTimestamp: block.timestamp + 365 days,
            ISIN: "US1234567890"
        });

        vm.prank(account1);
        vm.expectRevert();
        bondNFT.setMetaData(1, metadata);
    }

    function testSetAllowedMintsNotOwner() public {
        vm.prank(account1);
        vm.expectRevert();
        bondNFT.setAllowedMints(account2, 1, 5);
    }

    // Test minting with no allowed mints
    function testMintNotAllowed() public {
        vm.prank(account2);
        vm.expectRevert(BondNFT.NftMintingNotAllowed.selector);
        bondNFT.mint(1, 10, "");
    }

    // Test minting with exceeded allowed mints
    function testMintLimitExceeded() public {
        vm.prank(account1);
        bondNFT.mint(1, 5, "");

        vm.prank(account1);
        vm.expectRevert(abi.encodeWithSelector(BondNFT.NftMintingLimitExceeded.selector, 5));
        bondNFT.mint(1, 6, "");
    }

    // Test mintBatch for not allowed tokens
    function testMintBatchNotAllowed() public {
        uint256[] memory ids = new uint256[](2);
        ids[0] = 1;
        ids[1] = 2; // No allowance for ID 2

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 1;

        vm.prank(account1);
        vm.expectRevert(BondNFT.NftMintingNotAllowed.selector);
        bondNFT.mintBatch(ids, amounts, "");
    }

    // Test mintBatch with exceeded allowed mints
    function testMintBatchLimitExceeded() public {
        bondNFT.setAllowedMints(account1, 2, 5);

        uint256[] memory ids = new uint256[](2);
        ids[0] = 1;
        ids[1] = 2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 5; // Within limit
        amounts[1] = 6; // Exceeds limit

        vm.prank(account1);
        vm.expectRevert(abi.encodeWithSelector(BondNFT.NftMintingLimitExceeded.selector, 5));
        bondNFT.mintBatch(ids, amounts, "");
    }

    // Test mintBatch with mixed exceed limits
    function testMintBatchPartialLimitExceeded() public {
        vm.prank(account1);
        bondNFT.mint(1, 6, ""); // Already minted 6 of 10 allowed

        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 5; // Would exceed limit of 10

        vm.prank(account1);
        vm.expectRevert(abi.encodeWithSelector(BondNFT.NftMintingLimitExceeded.selector, 4));
        bondNFT.mintBatch(ids, amounts, "");
    }

    // Test burn with insufficient balance
    function testBurnInsufficientBalance() public {
        vm.prank(account1);
        bondNFT.mint(1, 5, "");

        vm.prank(account1);
        vm.expectRevert(BondNFT.NftInsufficientBalanceToBurn.selector);
        bondNFT.burn(1, 6);
    }

    // Test burn with zero balance
    function testBurnZeroBalance() public {
        vm.prank(account1);
        vm.expectRevert(BondNFT.NftInsufficientBalanceToBurn.selector);
        bondNFT.burn(1, 1);
    }

    // Test remaining mints calculation
    function testRemainingMintsAfterUsage() public {
        // First check initial remaining mints
        assertEq(bondNFT.remainingMints(account1, 1), 10);

        // Mint some tokens
        vm.prank(account1);
        bondNFT.mint(1, 3, "");

        // Check remaining mints after partial usage
        assertEq(bondNFT.remainingMints(account1, 1), 7);

        // Mint remaining tokens
        vm.prank(account1);
        bondNFT.mint(1, 7, "");

        // Check remaining mints after full usage
        assertEq(bondNFT.remainingMints(account1, 1), 0);
    }
}
