// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {NFTStakingAndBorrowing} from "../src/NFTStakingAndBorrowing.sol";
import {console} from "forge-std/console.sol";

contract DeployNftStaking is Script {
    function run() external returns (NFTStakingAndBorrowing) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address stableCoinsAddress = vm.envAddress("STABLES_ADDRESS");
        vm.startBroadcast(deployerPrivateKey);
        NFTStakingAndBorrowing nftStaking = new NFTStakingAndBorrowing(stableCoinsAddress);
        vm.stopBroadcast();
        return nftStaking;
    }
}
