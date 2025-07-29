// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {NFTStakingAndBorrowing} from "../src/NFTStakingAndBorrowing.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {console} from "forge-std/console.sol";

contract DeployNftStaking is Script {
    function run() external returns (NFTStakingAndBorrowing) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address stableCoinsAddress = vm.envAddress("STABLES_PROXY_ADDRESS");
        address owner = vm.addr(deployerPrivateKey);
        address feeReceiver = owner;

        // Deploy the contract as a UUPS proxy with the initializer
        vm.startBroadcast(deployerPrivateKey);
        address proxy = Upgrades.deployUUPSProxy(
            "NFTStakingAndBorrowing.sol:NFTStakingAndBorrowing",
            abi.encodeCall(
                NFTStakingAndBorrowing.initialize,
                (stableCoinsAddress, owner, feeReceiver, 1200, 500, 45 days, 1000, 9850)
            )
        );
        NFTStakingAndBorrowing nftStaking = NFTStakingAndBorrowing(proxy);
        vm.stopBroadcast();

        console.log("NFTStakingAndBorrowing deployed at:", address(nftStaking));
        return nftStaking;
    }
}
