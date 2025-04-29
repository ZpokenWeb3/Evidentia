// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {StableBondCoins} from "../../src/StableBondCoins.sol";
import {console} from "forge-std/console.sol";
import {MessagingFee} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

using OptionsBuilder for bytes;

/**
 * @title OFT Cross-Chain Transfer Test Script
 * @dev Tests token transfers between chains via OFT protocol
 */
contract TestOFTCrossChainTransfer is Script {
    // LayerZero chain IDs
    uint32 public constant SEPOLIA_CHAIN_ID = 40161; // Ethereum Sepolia
    uint32 public constant FUJI_CHAIN_ID = 40106; // Polygon Fuji

    // Test token transfer from Sepolia to Fuji
    function run() external {
        // Get private key from .env
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        // Get deployed contract addresses
        address sepoliaContractAddress = vm.envAddress("SEPOLIA_CONTRACT_ADDRESS");
        address recipientAddress = vm.envAddress("RECIPIENT_ADDRESS");

        // Token amount to send (with 6 decimals)
        uint256 amountToSend = 10 * 10 ** 6; // 10 tokens

        // Create contract instance
        StableBondCoins sepoliaContract = StableBondCoins(sepoliaContractAddress);

        vm.startBroadcast(deployerPrivateKey);

        sepoliaContract.mint(deployerAddress, amountToSend);

        // Check balance before transfer
        uint256 initialBalance = sepoliaContract.balanceOf(deployerAddress);
        console.log("Initial sender balance:", initialBalance / 10 ** 6, "SBC");

        // Create proper options for ULN
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0) // gas for execution on target chain
            .addExecutorLzComposeOption(0, 200000, 0); // compose option

        // Create SendParam struct for the token transfer using bytes32 for recipient address
        bytes32 recipientAddressBytes32 = bytes32(uint256(uint160(recipientAddress)));

        // Create the SendParam struct
        SendParam memory sendParam = SendParam({
            dstEid: FUJI_CHAIN_ID,
            to: recipientAddressBytes32,
            amountLD: amountToSend,
            minAmountLD: amountToSend * 95 / 100, // 5% slippage allowance
            extraOptions: options, // Use the options we created above
            composeMsg: bytes(""),
            oftCmd: bytes("")
        });

        // Get fee quote
        MessagingFee memory fee = sepoliaContract.quoteSend(sendParam, false);

        console.log("Transfer fee (wei):", fee.nativeFee);

        // Send tokens via OFT
        sepoliaContract.send{value: fee.nativeFee}(
            sendParam,
            fee,
            deployerAddress // refund address
        );

        console.log("Successfully sent", amountToSend / 10 ** 6, "SBC to Fuji");
        console.log("Recipient:", recipientAddress);

        // Check updated balance
        uint256 newBalance = sepoliaContract.balanceOf(deployerAddress);
        console.log("New sender balance:", newBalance / 10 ** 6, "SBC");

        vm.stopBroadcast();
    }

    // Additional script to check balance on Fuji
    function checkFujiBalance() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        address fujiContractAddress = vm.envAddress("FUJI_CONTRACT_ADDRESS");
        address recipientAddress = vm.envAddress("RECIPIENT_ADDRESS");

        StableBondCoins fujiContract = StableBondCoins(fujiContractAddress);

        vm.startBroadcast(deployerPrivateKey);

        // Check recipient balance on Fuji
        uint256 recipientBalance = fujiContract.balanceOf(recipientAddress);
        console.log("Recipient balance on Fuji:", recipientBalance / 10 ** 6, "SBC");

        vm.stopBroadcast();
    }
}
