// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {StableBondCoins} from "../src/StableBondCoins.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title StableBondCoins Testnet Deployment Script
 * @dev Deploys StableBondCoins as UUPS proxy in a test network
 */
contract DeployStableBondCoinsToTestnet is Script {
    // LayerZero v2 Endpoint addresses
    // Source: https://docs.layerzero.network/v2/technical-reference/mainnet-endpoints
    address public constant LZ_ENDPOINT_SEPOLIA = 0x6EDCE65403992e310A62460808c4b910D972f10f;
    address public constant LZ_ENDPOINT_FUJI = 0x6EDCE65403992e310A62460808c4b910D972f10f;

    function run() external {
        // Get private key from .env
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address defaultAdmin = vm.envAddress("DEFAULT_ADMIN_ADDRESS");

        // Start broadcast
        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation
        StableBondCoins implementation = new StableBondCoins(LZ_ENDPOINT_FUJI);

        // Prepare initialization data
        bytes memory initData = abi.encodeCall(StableBondCoins.initialize, (defaultAdmin, defaultAdmin, defaultAdmin));

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);

        // Get StableBondCoins instance
        StableBondCoins stableBondCoins = StableBondCoins(address(proxy));

        // Log addresses
        console.log("StableBondCoins Implementation deployed at:", address(implementation));
        console.log("StableBondCoins Proxy deployed at:", address(proxy));

        // End broadcast
        vm.stopBroadcast();
    }
}
