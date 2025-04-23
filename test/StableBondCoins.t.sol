// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {StableBondCoins} from "../src/StableBondCoins.sol";
import {Test, console} from "forge-std/Test.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {EndpointV2Mock} from "@layerzerolabs/test-devtools-evm-foundry/contracts/Mocks/EndpointV2Mock.sol";

contract StableBondCoinsTest is Test {
    StableBondCoins public stableBondCoins;
    address public defaultAdmin;
    address public minter;
    address public delegate;
    address public lzEndpoint;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    function setUp() public {
        defaultAdmin = address(1);
        minter = address(2);
        delegate = address(3);

        // 1. Deploy a mock endpoint
        EndpointV2Mock mock = new EndpointV2Mock(1, address(this));

        StableBondCoins impl = new StableBondCoins(address(mock));
        bytes memory initData = abi.encodeCall(StableBondCoins.initialize, (defaultAdmin, minter, delegate));
        address proxyAddr = UnsafeUpgrades.deployUUPSProxy(address(impl), initData);
        stableBondCoins = StableBondCoins(proxyAddr);
    }

    function testConstructor() public view {
        assertEq(stableBondCoins.name(), "Stable Bond Coins");
        assertEq(stableBondCoins.symbol(), "SBC");
        assertEq(stableBondCoins.decimals(), 6);

        assertEq(stableBondCoins.hasRole(DEFAULT_ADMIN_ROLE, defaultAdmin), true);
        assertEq(stableBondCoins.hasRole(MINTER_ROLE, minter), true);
        assertEq(stableBondCoins.owner(), delegate);
    }

    function testNameSpace() public pure {
        assertEq(
            keccak256(abi.encode(uint256(keccak256("StableBondCoins.storage")) - 1)) & ~bytes32(uint256(0xff)),
            0xd617c1a7b49d27159d9fe0ce7de01c7130c8a8bb809755fe8b0df36a2bc07e00
        );
    }

    function testMint() public {
        address recipient = address(5);
        uint256 amount = 100;

        vm.prank(minter);
        stableBondCoins.mint(recipient, amount);

        assertEq(stableBondCoins.balanceOf(recipient), amount);
    }

    function testBurn() public {
        address owner = address(5);
        uint256 amount = 100;

        vm.prank(minter);
        stableBondCoins.mint(owner, amount);

        vm.prank(minter);
        stableBondCoins.burn(owner, amount);

        assertEq(stableBondCoins.balanceOf(owner), 0);
    }

    function testOnlyMinterCanMint() public {
        address recipient = address(5);
        uint256 amount = 100;

        vm.expectRevert();
        stableBondCoins.mint(recipient, amount);
    }

    function testOnlyMinterCanBurn() public {
        address owner = address(5);
        uint256 amount = 100;

        vm.prank(minter);
        stableBondCoins.mint(owner, amount);

        vm.expectRevert();
        stableBondCoins.burn(owner, amount);
    }
}
