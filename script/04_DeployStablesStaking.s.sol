// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {StableCoinsStaking} from "../src/StableCoinsStaking.sol";
import {console} from "forge-std/console.sol";

contract DeployStablesStaking is Script {
    function run() external returns (StableCoinsStaking) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address stableCoinsAddress = vm.envAddress("STABLES_ADDRESS");
        address nftStakingAddress = vm.envAddress("NFT_STAKING_ADDRESS");
        vm.startBroadcast(deployerPrivateKey);
        StableCoinsStaking stablesStaking = new StableCoinsStaking(stableCoinsAddress, nftStakingAddress);
        vm.stopBroadcast();
        return stablesStaking;
    }
}
