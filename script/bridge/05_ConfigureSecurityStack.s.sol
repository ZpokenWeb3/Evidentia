// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {ILayerZeroEndpointV2} from "LayerZero-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {LayerZeroConstants} from "./LayerZeroConstants.s.sol";
import {console} from "forge-std/console.sol";
import {SetConfigParam} from "LayerZero-v2/contracts/interfaces/IMessageLibManager.sol";

/**
 * @title ConfigureSecurityStack
 * @dev Sets up the security stack (DVNs and Executor) for an OFT contract on a given chain.
 *
 * USAGE:
 *   forge script script/bridge/05_ConfigureSecurityStack.s.sol:ConfigureSecurityStack \
 *     --sig "run(string)" \
 *     --rpc-url mainnet \
 *     --broadcast \
 *     --private-key $PRIVATE_KEY \
 *     "mainnet"
 */
contract ConfigureSecurityStack is Script {
    // Config types for ULN (Ultra Light Node)
    uint32 constant CONFIG_TYPE_ULN = 1;
    // Config types for Executor
    uint32 constant CONFIG_TYPE_EXECUTOR = 2;

    /// @param network human‐readable key: "mainnet", "tron-mainnet", etc.
    function run(string memory network) external {
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

        // Configure Executor settings
        bytes memory executorConfig = _getExecutorConfig();
        SetConfigParam[] memory executorParams = new SetConfigParam[](1);
        executorParams[0] = SetConfigParam({
            eid: destinationEid,
            configType: CONFIG_TYPE_EXECUTOR,
            config: executorConfig
        });

        // Set ULN config
        console.log("Setting ULN config for OApp:", oapp);
        ILayerZeroEndpointV2(cfg.endpoint).setConfig(oapp, cfg.ulnSendLib, ulnParams);

        // Set Executor config
        console.log("Setting Executor config for OApp:", oapp);
        ILayerZeroEndpointV2(cfg.endpoint).setConfig(oapp, cfg.ulnSendLib, executorParams);

        vm.stopBroadcast();
    }

    // Returns the ULN (DVN) configuration
    function _getUlnConfig() internal pure returns (bytes memory) {
        // https://docs.layerzero.network/v2/deployments/dvn-addresses
        address[] memory dvns = new address[](1);
        dvns[0] = 0x8bC1D368036EE5E726D230beB685294BE191A24e; // LayerZero Labs

        uint16[] memory dvnConfirmations = new uint16[](1);
        dvnConfirmations[0] = 2;

        // Encode the ULN config
        return abi.encode(dvns, dvnConfirmations);
    }

    // Returns the Executor configuration
    function _getExecutorConfig() internal pure returns (bytes memory) {
        // https://docs.layerzero.network/v2/deployments/deployed-contracts
        address executor = 0x173272739Bd7Aa6e4e214714048a9fE699453059; // LayerZero Default Executor

        // Max gas limit for execution
        uint256 maxGasLimit = 2000000;

        // Encode the Executor config
        return abi.encode(executor, maxGasLimit);
    }
}
