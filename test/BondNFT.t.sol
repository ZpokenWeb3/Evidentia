// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {BondNFT} from "../src/BondNFT.sol";

contract BondNFTTest is Test {
    BondNFT public bondNFT;
    address public owner;
    address public account1;

    function setUp() public {
        owner = address(this);
        account1 = address(1);
        bondNFT = new BondNFT(owner, "https://example.com/{id}.json");
    }

    function testInitialOwner() public {
        assertEq(bondNFT.owner(), owner);
    }

    function testSetURI() public {
        string memory newURI = "https://newexample.com/{id}.json";
        bondNFT.setURI(newURI);
        assertEq(bondNFT.uri(1), newURI);
    }

    function testSetMetaData() public {
        BondNFT.Metadata memory metadata = BondNFT.Metadata({
            value: 100,
            couponValue: 5,
            issueTimestamp: block.timestamp,
            expirationTimestamp: block.timestamp + 365 days,
            ISIN: "US1234567890"
        });
        bondNFT.setMetaData(1, metadata);
        (uint256 value, uint256 couponValue, uint256 issueTimestamp, uint256 expirationTimestamp, string memory ISIN) =
            bondNFT.metadata(1);
        assertEq(value, metadata.value);
        assertEq(couponValue, metadata.couponValue);
        assertEq(issueTimestamp, metadata.issueTimestamp);
        assertEq(expirationTimestamp, metadata.expirationTimestamp);
        assertEq(ISIN, metadata.ISIN);
    }

    function testMint() public {
        uint256 id = 1;
        uint256 amount = 10;
        bondNFT.mint(account1, id, amount, "");
        assertEq(bondNFT.balanceOf(account1, id), amount);
    }

    function testBurn() public {
        uint256 id = 1;
        uint256 amount = 10;
        bondNFT.mint(account1, id, amount, "");
        bondNFT.burn(account1, id, amount);
        assertEq(bondNFT.balanceOf(account1, id), 0);
    }

    function testFailMintNotOwner() public {
        uint256 id = 1;
        uint256 amount = 10;
        vm.prank(account1);
        bondNFT.mint(account1, id, amount, "");
        assertEq(bondNFT.balanceOf(account1, id), 0);
    }

    function testFailBurnNotOwner() public {
        uint256 id = 1;
        uint256 amount = 10;
        bondNFT.mint(account1, id, amount, "");
        vm.prank(account1);
        bondNFT.burn(account1, id, amount);
        assertEq(bondNFT.balanceOf(account1, id), amount);
    }
}
