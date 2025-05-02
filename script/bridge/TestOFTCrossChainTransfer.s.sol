// scripts/TestOFTCrossChainByName.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {StableBondCoins} from "../../src/StableBondCoins.sol";
import {MessagingFee} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {LayerZeroConstants} from "./LayerZeroConstants.s.sol";

using OptionsBuilder for bytes;

/**
 * @title OFT Cross-Chain Transfer by Chain Name
 *
 * Usage:
 *   forge script \
 *     script/bridge/TestOFTCrossChainTransfer.s.sol:TestOFTCrossChainTransfer \
 *     --sig "run(string,string,uint256)" \
 *     --rpc-url fuji \
 *     --broadcast \
 *     --private-key $PRIVATE_KEY \
 *     "fuji" "sepolia" 100
 */
contract TestOFTCrossChainTransfer is Script {
    /// @param src    e.g. "fuji", "sepolia", etc.
    /// @param dst    e.g. "sepolia", "fuji", etc.
    /// @param amount number of tokens to send (in base units, e.g. 100e6 for 100 tokens)
    function run(string calldata src, string calldata dst, uint256 amount) external {
        // load deployer key & sender address
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address sender = vm.addr(pk);

        // lookup LayerZero chain configs
        LayerZeroConstants.ChainConfig memory cDst = LayerZeroConstants.getChainConfigByName(dst);

        // read proxies from env based on network name
        address srcProxy = _getProxy(src);

        StableBondCoins token = StableBondCoins(srcProxy);

        vm.startBroadcast(pk);
        // mint to sender
        token.mint(sender, amount);

        // quote and send cross-chain
        bytes memory opts = OptionsBuilder.newOptions().addExecutorLzReceiveOption(cDst.gracePeriod, 0)
            .addExecutorLzComposeOption(0, cDst.gracePeriod, 0);

        SendParam memory param = SendParam({
            dstEid: cDst.eid,
            to: bytes32(uint256(uint160(sender))),
            amountLD: amount,
            minAmountLD: (amount * 95) / 100,
            extraOptions: opts,
            composeMsg: "",
            oftCmd: ""
        });

        MessagingFee memory fee = token.quoteSend(param, false);

        token.send{value: fee.nativeFee}(param, fee, sender);
        vm.stopBroadcast();
    }

    function _getProxy(string memory network) internal view returns (address) {
        bytes32 k = keccak256(bytes(network));
        if (k == keccak256("fuji")) return vm.envAddress("FUJI_STABLE_CONTRACT_ADDRESS");
        if (k == keccak256("sepolia")) return vm.envAddress("SEPOLIA_STABLE_CONTRACT_ADDRESS");
        if (k == keccak256("tron-testnet")) return vm.envAddress("TRON_TESTNET_STABLE_CONTRACT_ADDRESS");
        revert("Unknown network");
    }
}
