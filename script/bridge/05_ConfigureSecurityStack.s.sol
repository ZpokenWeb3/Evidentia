// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {ILayerZeroEndpointV2} from "LayerZero-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {LayerZeroConstants} from "./LayerZeroConstants.s.sol";
import {console} from "forge-std/console.sol";
import {SetConfigParam} from "LayerZero-v2/contracts/interfaces/IMessageLibManager.sol";
import { UlnConfig } from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";

/**
 * @title ConfigureSecurityStack
 * @dev Sets up the security stack (DVNs) for an OFT contract
 *
 * USAGE:
 *   forge script script/bridge/05_ConfigureSecurityStack.s.sol:ConfigureSecurityStack \
 *     --sig "run(string,string)" \
 *     --rpc-url mainnet \
 *     --broadcast \
 *     --private-key $PRIVATE_KEY \
 *     "mainnet" "send"
 */
contract ConfigureSecurityStack is Script {
    // Config types for ULN (Ultra Light Node)
    uint32 constant CONFIG_TYPE_ULN = 2;

    /// @param network human‐readable key: "mainnet", "tron-mainnet", etc.
    /// @param libType "send" to use cfg.ulnSendLib, "recv" to use cfg.ulnRecvLib
    function run(string memory network, string memory libType) external {
        // 1) look up the whole config
        LayerZeroConstants.ChainConfig memory cfg = LayerZeroConstants.getChainConfigByName(network);

        // Get the OApp address
        address oapp = vm.envAddress("OFT_ADAPTER_PROXY_ADDRESS");
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        uint32 destinationEid = 30420; // Default to Tron Mainnet

        console.log("Configuring security stack from EID:", cfg.eid, "to destination EID:", destinationEid);

        // Configure ULN (DVN) settings
        bytes memory ulnConfig = _getUlnConfig();

        SetConfigParam[] memory ulnParams = new SetConfigParam[](1);
        ulnParams[0] = SetConfigParam({
            eid: destinationEid,
            configType: CONFIG_TYPE_ULN,
            config: ulnConfig
        });

        // Set ULN config
        console.log("Setting ULN config for OApp:", oapp);
        address lib;
        if (keccak256(abi.encodePacked(libType)) == keccak256(abi.encodePacked("send"))) {
            lib = cfg.ulnSendLib;
        } else if (keccak256(abi.encodePacked(libType)) == keccak256(abi.encodePacked("recv"))) {
            lib = cfg.ulnRecvLib;
        } else {
            revert(string(abi.encodePacked("Invalid libType: ", libType, ". Must be 'send' or 'recv'")));
        }
        console.log("Using lib:", lib, "- libType:", libType);
        ILayerZeroEndpointV2(cfg.endpoint).setConfig(oapp, lib, ulnParams);

        vm.stopBroadcast();
    }

    // Returns the ULN (DVN) configuration
    function _getUlnConfig() internal pure returns (bytes memory) {
        // https://docs.layerzero.network/v2/deployments/dvn-addresses

        // struct UlnConfig {
        //     uint64 confirmations;
        //     uint8 requiredDVNCount; // 0 indicate DEFAULT, NIL_DVN_COUNT indicate NONE (to override the value of default)
        //     uint8 optionalDVNCount; // 0 indicate DEFAULT, NIL_DVN_COUNT indicate NONE (to override the value of default)
        //     uint8 optionalDVNThreshold; // (0, optionalDVNCount]
        //     address[] requiredDVNs; // no duplicates. sorted an an ascending order. allowed overlap with optionalDVNs
        //     address[] optionalDVNs; // no duplicates. sorted an an ascending order. allowed overlap with requiredDVNs
        // }

        UlnConfig memory ulnConfig;
        ulnConfig = UlnConfig(15, 2, 0, 0, new address[](2), new address[](0));
        // Addresses must be sorted in ascending order
        ulnConfig.requiredDVNs[0] = address(0x3b0531eB02Ab4aD72e7a531180beeF9493a00dD2); // USDT0
        ulnConfig.requiredDVNs[1] = address(0x589dEDbD617e0CBcB916A9223F4d1300c294236b); // LayerZero Labs

        // Encode the ULN config
        return abi.encode(ulnConfig);
    }
}
