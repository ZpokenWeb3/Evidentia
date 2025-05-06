// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Script} from "forge-std/Script.sol";
import {NFTStakingAndBorrowing} from "../src/NFTStakingAndBorrowing.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {console} from "forge-std/console.sol";

contract DeployNftStaking is Script {
    function run() external returns (NFTStakingAndBorrowing) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address stableCoinsAddress = vm.envAddress("STABLES_ADDRESS");

        // Deploy the contract as a UUPS proxy with the initializer
        vm.startBroadcast(deployerPrivateKey);
        address proxy = Upgrades.deployUUPSProxy(
            "NFTStakingAndBorrowing.sol:NFTStakingAndBorrowing",
            abi.encodeCall(NFTStakingAndBorrowing.initialize, (stableCoinsAddress))
        )
        NFTStakingAndBorrowing nftStaking = NFTStakingAndBorrowing(proxy);
        vm.stopBroadcast();

        console.log("NFTStakingAndBorrowing deployed at:", address(nftStaking));
        return nftStaking;
    }
}
