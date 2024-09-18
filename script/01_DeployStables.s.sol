// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {StableBondCoins} from "../src/StableBondCoins.sol";
import {console} from "forge-std/console.sol";

contract DeployStables is Script {
    function run() external returns (StableBondCoins) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = 0x7Df601525A53AbaD47C69E78ae151b6F96c59097;
        vm.startBroadcast(deployerPrivateKey);
        StableBondCoins stablesContract = new StableBondCoins(owner, owner);
        vm.stopBroadcast();
        return stablesContract;
    }
}
