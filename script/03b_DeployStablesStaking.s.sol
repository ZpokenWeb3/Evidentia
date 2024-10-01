// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {StableCoinsStaking} from "../src/StableCoinsStaking.sol";
import {console} from "forge-std/console.sol";

contract DeployStablesStaking is Script {
    function run() external returns (StableCoinsStaking) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address stableCoinsAddress = 0xbDBc6f32699c39DF208595BfC7Dfb96C6F837aBE;
        address nftStakingAddress = 0x5fc677Bec2ccF1E4fDb3b621AC5ae7CD7AaA7EA5;
        vm.startBroadcast(deployerPrivateKey);
        StableCoinsStaking stablesStaking = new StableCoinsStaking(stableCoinsAddress, nftStakingAddress);
        vm.stopBroadcast();
        return stablesStaking;
    }
}
