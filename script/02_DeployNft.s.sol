// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {BondNFT} from "../src/BondNFT.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {console} from "forge-std/console.sol";

contract DeployNft is Script {
    function run() external returns (BondNFT) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.envAddress("BOND_NFT_OWNER_ADDRESS");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the contract as a UUPS proxy with the initializer
        address proxy = Upgrades.deployUUPSProxy(
            "BondNFT.sol", abi.encodeCall(BondNFT.initialize, (owner, "https://example.com/{id}.json"))
        );
        BondNFT basicNft = BondNFT(proxy);

        vm.stopBroadcast();
        console.log("BondNFT deployed at:", address(basicNft));
        return basicNft;
    }
}
