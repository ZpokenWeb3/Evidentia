// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Script} from "forge-std/Script.sol";
import {StableBondCoins} from "../src/StableBondCoins.sol";
import {console} from "forge-std/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployStables is Script {
    function run() external returns (StableBondCoins) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.envAddress("OWNER");
        address lzEndpoint = vm.envAddress("LZ_ENDPOINT");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation
        StableBondCoins implementation = new StableBondCoins(lzEndpoint);

        // Deploy proxy and initialize
        ERC1967Proxy proxy =
            new ERC1967Proxy(address(implementation), abi.encodeCall(implementation.initialize, (owner, owner, owner)));

        StableBondCoins stableBondCoins = StableBondCoins(address(proxy));

        console.log("StableBondCoins deployed at:", address(stableBondCoins));

        vm.stopBroadcast();
        return stableBondCoins;
    }
}
