// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {StableBondCoins} from "../src/StableBondCoins.sol";
import {console} from "forge-std/console.sol";

/**
 * @title OFT Testnet Setup Script
 * @dev Sets up peer connections between StableBondCoins contracts on different testnets
 */
contract SetupOFTTestnet is Script {
    // LayerZero chain IDs
    // Source: https://docs.layerzero.network/v2/developers/chain-ids
    uint32 public constant SEPOLIA_CHAIN_ID = 40161; // Ethereum Sepolia
    uint32 public constant FUJI_CHAIN_ID = 40106; // Polygon Fuji

    function run() external {
        // Get private key from .env
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Get deployed contract addresses
        address sepoliaContractAddress = vm.envAddress("SEPOLIA_CONTRACT_ADDRESS");
        address fujiContractAddress = vm.envAddress("FUJI_CONTRACT_ADDRESS");

        // Get contract instance
        StableBondCoins sepoliaContract = StableBondCoins(sepoliaContractAddress);

        vm.startBroadcast(deployerPrivateKey);

        // Set peer on Sepolia
        // Convert address to bytes32 for the peer parameter
        bytes32 peerAddress = bytes32(uint256(uint160(fujiContractAddress)));
        sepoliaContract.setPeer(FUJI_CHAIN_ID, peerAddress);

        console.log("Set peer for Sepolia -> Fuji");

        vm.stopBroadcast();
    }

    // Additional script for Fuji network setup
    function runFuji() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address sepoliaContractAddress = vm.envAddress("SEPOLIA_CONTRACT_ADDRESS");
        address fujiContractAddress = vm.envAddress("FUJI_CONTRACT_ADDRESS");

        StableBondCoins fujiContract = StableBondCoins(fujiContractAddress);

        vm.startBroadcast(deployerPrivateKey);

        // Set peer on Fuji
        // Convert address to bytes32 for the peer parameter
        bytes32 peerAddress = bytes32(uint256(uint160(sepoliaContractAddress)));
        fujiContract.setPeer(SEPOLIA_CHAIN_ID, peerAddress);

        console.log("Set peer for Fuji -> Sepolia");

        vm.stopBroadcast();
    }
}
