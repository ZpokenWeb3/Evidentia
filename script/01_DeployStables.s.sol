// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {StableBondCoins} from "../src/StableBondCoins.sol";
import {console} from "forge-std/console.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract DeployStables is Script {
    function run() external returns (StableBondCoins) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.envAddress("STABLE_BOND_COINS_OWNER_ADDRESS");
        address minter = vm.envAddress("MINTER_ADDRESS");

        // Deploy the contract as a UUPS proxy with the initializer
        vm.startBroadcast(deployerPrivateKey);
        address proxy =
            Upgrades.deployUUPSProxy("StableBondCoins.sol", abi.encodeCall(StableBondCoins.initialize, (owner, minter, "eUAH", "eUAH", 6)));
        StableBondCoins stablesContract = StableBondCoins(proxy);
        vm.stopBroadcast();

        console.log("StableBondCoins deployed at:", address(stablesContract));
        return stablesContract;
    }
}
