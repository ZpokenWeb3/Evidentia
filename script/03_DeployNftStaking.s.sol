// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {NFTStakingAndBorrowing} from "../src/NFTStakingAndBorrowing.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {console} from "forge-std/console.sol";

contract DeployNftStaking is Script {
    function run() external returns (NFTStakingAndBorrowing) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address stableCoinsAddress = vm.envAddress("STABLES_ADDRESS");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the contract as a proxy with the initializer
        NFTStakingAndBorrowing nftStaking = NFTStakingAndBorrowing(
            UnsafeUpgrades.deployUUPSProxy(
                address(new NFTStakingAndBorrowing()),
                abi.encodeCall(NFTStakingAndBorrowing.initialize, (stableCoinsAddress))
            )
        );

        vm.stopBroadcast();
        return nftStaking;
    }
}
