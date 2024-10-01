// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {NFTStakingAndBorrowing} from "../src/NFTStakingAndBorrowing.sol";
import {console} from "forge-std/console.sol";

contract DeployNftStaking is Script {
    function run() external returns (NFTStakingAndBorrowing) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address stableCoinsAddress = 0xbDBc6f32699c39DF208595BfC7Dfb96C6F837aBE;
        vm.startBroadcast(deployerPrivateKey);
        NFTStakingAndBorrowing nftStaking = new NFTStakingAndBorrowing(stableCoinsAddress);
        vm.stopBroadcast();
        return nftStaking;
    }
}
