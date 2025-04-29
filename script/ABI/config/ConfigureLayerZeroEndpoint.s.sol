// scripts/ConfigureLZMinimal.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

contract ConfigureLZMinimal is Script {
    address public ENDPOINT = 0x6EDCE65403992e310A62460808c4b910D972f10f;
    address public OAPP = vm.envAddress("FUJI_CONTRACT_ADDRESS");
    uint32 public DEST_CHAIN_ID = 40161;
    address public SEND_LIB = 0x69BF5f48d2072DfeBc670A1D19dff91D0F4E8170;
    address public RECV_LIB = 0x819F0FAF2cb1Fba15b9cB24c9A2BDaDb0f895daf;
    uint16 public GRACE_PERIOD = 50;

    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        ILayerZeroEndpointV2 ep = ILayerZeroEndpointV2(ENDPOINT);

        // 1) register send library for cross-chain sends
        ep.setSendLibrary(
            /* aOFT */
            OAPP,
            /* dstEid */
            DEST_CHAIN_ID,
            /* newLib */
            SEND_LIB
        );

        // 2) register receive library for incoming messages
        ep.setReceiveLibrary(
            /* aOFT */
            OAPP,
            /* srcEid */
            DEST_CHAIN_ID,
            /* newLib */
            RECV_LIB,
            /* gracePeriod */
            GRACE_PERIOD
        );

        vm.stopBroadcast();
    }
}
