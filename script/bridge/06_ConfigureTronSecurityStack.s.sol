// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {LayerZeroConstants} from "./LayerZeroConstants.s.sol";
import {console} from "forge-std/console.sol";
import {SetConfigParam} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";

/**
 * @title ConfigureTronSecurityStack
 * @dev Sets up the security stack (DVNs and Executor) for an OFT contract on Tron.
 *
 * USAGE:
 *   forge script script/bridge/06_ConfigureTronSecurityStack.s.sol:ConfigureTronSecurityStack \
 *     --sig "run()" \
 *     --rpc-url tron-mainnet \
 *     --broadcast \
 *     --private-key $PRIVATE_KEY
 */
contract ConfigureTronSecurityStack is Script {
    // Config types for ULN (Ultra Light Node)
    uint32 constant CONFIG_TYPE_ULN = 1;
    // Config types for Executor
    uint32 constant CONFIG_TYPE_EXECUTOR = 2;

    function run() external {
        // Get Tron mainnet config
        LayerZeroConstants.ChainConfig memory cfg = LayerZeroConstants.getChainConfigByName("tron-mainnet");

        // Get the OApp address on Tron
        address oapp = vm.envAddress("TRON_OFT_TOKEN_ADDRESS");
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        uint32 destinationEid = 30101; // Default to Ethereum Mainnet

        console.log("Configuring security stack from EID:", cfg.eid, "to destination EID:", destinationEid);

        // Configure ULN (DVN) settings
        bytes memory ulnConfig = _getUlnConfig();
        SetConfigParam[] memory ulnParams = new SetConfigParam[](1);
        ulnParams[0] = SetConfigParam({
            eid: destinationEid,
            configType: CONFIG_TYPE_ULN,
            config: ulnConfig
        });

        // Configure Executor settings
        bytes memory executorConfig = _getExecutorConfig();
        SetConfigParam[] memory executorParams = new SetConfigParam[](1);
        executorParams[0] = SetConfigParam({
            eid: destinationEid,
            configType: CONFIG_TYPE_EXECUTOR,
            config: executorConfig
        });

        // Set ULN config
        console.log("Setting ULN config for Tron OApp:", oapp);
        ILayerZeroEndpointV2(cfg.endpoint).setConfig(oapp, cfg.ulnSendLib, ulnParams);

        // Set Executor config
        console.log("Setting Executor config for Tron OApp:", oapp);
        ILayerZeroEndpointV2(cfg.endpoint).setConfig(oapp, cfg.ulnSendLib, executorParams);

        vm.stopBroadcast();
    }

    // Returns the ULN (DVN) configuration
    function _getUlnConfig() internal pure returns (bytes memory) {
        // https://docs.layerzero.network/v2/deployments/dvn-addresses
        address[] memory dvns = new address[](2);
        dvns[0] = 0x589dEDbD617e0CBcB916A9223F4d1300c294236b; // LayerZero Labs
        dvns[1] = 0xD56e4eAb23cb81f43168F9F45211Eb027b9aC7cc; // Google Cloud

        uint16[] memory dvnConfirmations = new uint16[](2);
        dvnConfirmations[0] = 2;
        dvnConfirmations[1] = 2;

        // Encode the ULN config
        return abi.encode(dvns, dvnConfirmations);
    }

    // Returns the Executor configuration
    function _getExecutorConfig() internal pure returns (bytes memory) {
        // https://docs.layerzero.network/v2/deployments/deployed-contracts
        address executor = 0x67DE40af19C0C0a6D0278d96911889fAF4EBc1Bc; // LayerZero Default Executor

        // Max gas limit for execution
        uint256 maxGasLimit = 2000000;

        // Encode the Executor config
        return abi.encode(executor, maxGasLimit);
    }
}
