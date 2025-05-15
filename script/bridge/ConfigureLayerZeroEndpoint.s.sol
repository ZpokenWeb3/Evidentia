// scripts/ConfigureLZMinimal.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {LayerZeroConstants} from "./LayerZeroConstants.s.sol";

/**
 * @title ConfigureLayerZeroEndpoint
 * @dev Sets the send-library for an OFT contract on a given chain by name.
 *
 * USAGE:
 *   forge script script/bridge/ConfigureLayerZeroEndpoint.s.sol:ConfigureLayerZeroEndpoint \
 *     --sig "run(string)" \
 *     --rpc-url fuji \
 *     --broadcast \
 *     --private-key $PRIVATE_KEY \
 *     "fuji"
 */
contract ConfigureLayerZeroEndpoint is Script {
    /// @param network human‐readable key: "fuji", "sepolia", "tron-testnet", etc.
    function run(string calldata network) external {
        // 1) look up the whole config
        LayerZeroConstants.ChainConfig memory cfg = LayerZeroConstants.getChainConfigByName(network);

        //  dispatch on network name to the correct env-var
        address oapp;
        bytes32 k = keccak256(bytes(network));
        if (k == keccak256("fuji")) {
            oapp = vm.envAddress("FUJI_STABLE_CONTRACT_ADDRESS");
        } else if (k == keccak256("sepolia")) {
            oapp = vm.envAddress("SEPOLIA_STABLE_CONTRACT_ADDRESS");
        } else if (k == keccak256("tron-testnet")) {
            oapp = vm.envAddress("TRON_TESTNET_STABLE_CONTRACT_ADDRESS");
        } else {
            revert("Unknown network");
        }
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        ILayerZeroEndpointV2(cfg.endpoint).setSendLibrary(oapp, cfg.eid, cfg.ulnSendLib);

        vm.stopBroadcast();
    }
}
