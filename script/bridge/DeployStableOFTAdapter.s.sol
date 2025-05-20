// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {StableOFTAdapter} from "../../src/StableOFTAdapter.sol";
import {LayerZeroConstants} from "./LayerZeroConstants.s.sol";

contract DeployStableOFTAdapter is Script {
    function run() external returns (StableOFTAdapter) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.envAddress("STABLE_OFT_AD_OWNER_ADDRESS");

        string memory network = vm.envOr("NETWORK", string("sepolia"));

        console.log("network:", network);

        LayerZeroConstants.ChainConfig memory cfg = LayerZeroConstants.getChainConfigByName(network);

        // Get the token address to adapt
        address tokenAddress = vm.envAddress("STABLES_PROXY_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        Options memory opts;
        opts.constructorData = abi.encode(tokenAddress, cfg.endpoint);
        opts.unsafeAllow = "constructor,missing-initializer-call,state-variable-immutable";

        address srcProxyAddr = Upgrades.deployTransparentProxy(
            "StableOFTAdapter.sol", owner, abi.encodeCall(StableOFTAdapter.initialize, (owner)), opts
        );
        StableOFTAdapter OFTAdapter = StableOFTAdapter(srcProxyAddr);

        vm.stopBroadcast();

        console.log("StableOFTAdapter deployed at:", address(OFTAdapter));
        return OFTAdapter;
    }
}
