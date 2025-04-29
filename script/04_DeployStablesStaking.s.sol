// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Script} from "forge-std/Script.sol";
import {StableCoinsStaking} from "../src/StableCoinsStaking.sol";
import {console} from "forge-std/console.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract DeployStablesStaking is Script {
    function run() external returns (StableCoinsStaking) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address stableCoinsAddress = vm.envAddress("STABLES_ADDRESS");
        address nftStakingAddress = vm.envAddress("NFT_STAKING_ADDRESS");
        address owner = vm.envAddress("OWNER_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        address proxy = Upgrades.deployUUPSProxy(
            "StableCoinsStaking.sol",
            abi.encodeCall(StableCoinsStaking.initialize, (stableCoinsAddress, nftStakingAddress, owner))
        );

        StableCoinsStaking stableStaking = StableCoinsStaking(proxy);

        vm.stopBroadcast();

        console.log("StableCoinsStaking deployed at:", address(stableStaking));
        return stableStaking;
    }
}
