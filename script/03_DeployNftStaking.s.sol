// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {NFTStakingAndBorrowing} from "../src/NFTStakingAndBorrowing.sol";
import {console} from "forge-std/console.sol";

contract DeployNftStaking is Script {
    function run() external returns (NFTStakingAndBorrowing) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address stableCoinsAddress = 0x1a6026a6b3b1a535cA5259e5feC0cDC2E7b3261D;
        vm.startBroadcast(deployerPrivateKey);
        NFTStakingAndBorrowing nftStaking = new NFTStakingAndBorrowing(stableCoinsAddress);
        vm.stopBroadcast();
        return nftStaking;
    }
}
