// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {StableOFTAdapter} from "../../src/StableOFTAdapter.sol";
import {LayerZeroConstants} from "./LayerZeroConstants.s.sol";

contract DeployOFTAdapter is Script {
    function run() external returns (StableOFTAdapter) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.envAddress("STABLE_OFT_AD_OWNER_ADDRESS");

        string memory network = vm.envOr("NETWORK", string("sepolia"));

        LayerZeroConstants.ChainConfig memory cfg = LayerZeroConstants.getChainConfigByName(network);

        // Get the token address to adapt
        address tokenAddress = vm.envAddress("STABLE_BOND_COINS_PROXY_ADDRESS");

        // StableOFTAdapter requires constructor arguments for immutable variables
        // The constructor takes (address _token, address _lzEndpoint)
        console.log("Deploying StableOFTAdapter with:");
        console.log("  - Token address:", tokenAddress);
        console.log("  - LZ Endpoint:", cfg.endpoint);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the contract using constructor params and initializer
        Options memory opts;
        opts.constructorData = abi.encode(tokenAddress, cfg.endpoint);

        address proxy =
            Upgrades.deployUUPSProxy("StableOFTAdapter.sol", abi.encodeCall(StableOFTAdapter.initialize, (owner)), opts);

        StableOFTAdapter stablesContract = StableOFTAdapter(proxy);
        vm.stopBroadcast();

        console.log("StableOFTAdapter deployed at:", address(stablesContract));
        return stablesContract;
    }
}
