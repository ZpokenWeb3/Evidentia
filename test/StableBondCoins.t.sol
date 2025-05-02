// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {StableBondCoins} from "../src/StableBondCoins.sol";
import {StableBondCoinsV2} from "../src/V2/StableBondCoinsV2.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {EndpointV2Mock} from "@layerzerolabs/test-devtools-evm-foundry/contracts/Mocks/EndpointV2Mock.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

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

    function testUUPSUpgrade() public {
        vm.prank(defaultAdmin);
        address proxy = UnsafeUpgrades.deployUUPSProxy(
            address(new StableBondCoins()), abi.encodeCall(StableBondCoins.initialize, (defaultAdmin, minter))
        );
        StableBondCoins instance = StableBondCoins(proxy);

        vm.prank(minter);
        instance.mint(address(3), 100);

        assertEq(instance.name(), "Stable Bond Coins");
        assertEq(instance.balanceOf(address(3)), 100);
        assertEq(instance.decimals(), 6);
        address implAddressV1 = UnsafeUpgrades.getImplementationAddress(proxy);

        vm.prank(defaultAdmin);
        address newImplementation = address(new StableBondCoinsV2());

        //         vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(3), DEFAULT_ADMIN_ROLE));
        //         UnsafeUpgrades.upgradeProxy(
        //             proxy,
        //             newImplementation,
        //             abi.encodeCall(StableBondCoinsV2.initializeV2, ()),
        //             address(3)
        //         );

        UnsafeUpgrades.upgradeProxy(
            proxy, newImplementation, abi.encodeCall(StableBondCoinsV2.initializeV2, ()), defaultAdmin
        );

        StableBondCoinsV2 instance2 = StableBondCoinsV2(proxy);
        address implAddressV2 = UnsafeUpgrades.getImplementationAddress(proxy);
        assertFalse(implAddressV2 == implAddressV1, "Implementation address should change");
        assertEq(instance2.name(), "Stable Bond Coins", "Name should not change");
        assertEq(instance2.balanceOf(address(3)), 100, "Balance should be preserved");
        assertEq(instance2.decimals(), 6, "Decimals should be preserved");
        assertEq(instance2.getInitializedVersion(), 2, "Version should be updated to 2");
        assertEq(instance2.newFeature(), "V2 Feature", "Should use V2 implementation");
    }
}
