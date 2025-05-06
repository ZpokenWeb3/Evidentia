// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {StableBondCoins} from "../src/StableBondCoins.sol";
import {console} from "forge-std/console.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options, DefenderOptions, TxOverrides} from "openzeppelin-foundry-upgrades/Options.sol";

contract UpdateStables is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.envAddress("STABLE_BOND_COINS_OWNER_ADDRESS");
        address minter = vm.envAddress("NFT_STAKING_ADDRESS");

        // Address of the existing proxy
        address proxyAddress = 0xE2a8D33e3a60486Bd737760B58811B9089Baa69D;

        // Address of the current implementation
        address currentImplementation = 0xde8580Ecf96200457aabD5D6eF530Aef9490C39b;

        console.log("Current implementation address:", currentImplementation);
        console.log("Proxy address:", proxyAddress);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy new implementation and update proxy
        address newImplementation = Upgrades.deployImplementation(
            "StableBondCoins.sol",
            Options({
                referenceContract: "",
                referenceBuildInfoDir: "",
                constructorData: "",
                exclude: new string[](0),
                unsafeAllow: "constructor",
                unsafeAllowRenames: true,
                unsafeSkipProxyAdminCheck: false,
                unsafeSkipStorageCheck: true,
                unsafeSkipAllChecks: false,
                defender: DefenderOptions({
                    useDefenderDeploy: false,
                    skipVerifySourceCode: false,
                    relayerId: "",
                    salt: bytes32(0),
                    upgradeApprovalProcessId: "",
                    licenseType: "",
                    skipLicenseType: false,
                    txOverrides: TxOverrides({
                        gasLimit: 0,
                        gasPrice: 0,
                        maxFeePerGas: 0,
                        maxPriorityFeePerGas: 0
                    }),
                    metadata: ""
                })
            })
        );
        console.log("New implementation deployed at:", newImplementation);

        // Update the proxy to point to the new implementation
        Upgrades.upgradeProxy(
            proxyAddress,
            "StableBondCoins.sol",
            abi.encodeCall(
                StableBondCoins.initialize,
                (owner, minter, "eUAH", "eUAH", 6)
            )
        );

        vm.stopBroadcast();

        console.log("Contract updated successfully!");
        console.log("New implementation address:", newImplementation);
    }
} 
