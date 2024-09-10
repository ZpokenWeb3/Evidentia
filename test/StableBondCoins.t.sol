// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {StableBondCoins} from "../src/StableBondCoins.sol";
import {Test, console} from "forge-std/Test.sol";

contract StableBondCoinsTest is Test {
    StableBondCoins public stableBondCoins;
    address public defaultAdmin;
    address public minter;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    function setUp() public {
        defaultAdmin = address(1);
        minter = address(2);

        stableBondCoins = new StableBondCoins(defaultAdmin, minter);
    }

    function testConstructor() public view {
        assertEq(stableBondCoins.name(), "Stable Bond Coins");
        assertEq(stableBondCoins.symbol(), "SBC");
        assertEq(stableBondCoins.decimals(), 6);

        assertEq(stableBondCoins.hasRole(DEFAULT_ADMIN_ROLE, defaultAdmin), true);
        assertEq(stableBondCoins.hasRole(MINTER_ROLE, minter), true);
    }

    function testMint() public {
        address recipient = address(3);
        uint256 amount = 100;

        vm.prank(minter);
        stableBondCoins.mint(recipient, amount);

        assertEq(stableBondCoins.balanceOf(recipient), amount);
    }

    function testBurn() public {
        address owner = address(3);
        uint256 amount = 100;

        vm.prank(minter);
        stableBondCoins.mint(owner, amount);

        vm.prank(minter);
        stableBondCoins.burn(owner, amount);

        assertEq(stableBondCoins.balanceOf(owner), 0);
    }

    function testOnlyMinterCanMint() public {
        address recipient = address(3);
        uint256 amount = 100;

        vm.expectRevert();
        stableBondCoins.mint(recipient, amount);
    }

    function testOnlyMinterCanBurn() public {
        address owner = address(3);
        uint256 amount = 100;

        vm.prank(minter);
        stableBondCoins.mint(owner, amount);

        vm.expectRevert();
        stableBondCoins.burn(owner, amount);
    }
}
