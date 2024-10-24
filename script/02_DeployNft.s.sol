// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {BondNFT} from "../src/BondNFT.sol";
import {console} from "forge-std/console.sol";

contract DeployNft is Script {
    function run() external returns (BondNFT) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.envAddress("OWNER");
        vm.startBroadcast(deployerPrivateKey);
        BondNFT basicNft = new BondNFT(owner, "https://example.com/{id}.json");
        vm.stopBroadcast();
        return basicNft;
    }
}
