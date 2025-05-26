# LayerZero Bridge Scripts

This directory contains JavaScript scripts for interacting with LayerZero's OFT (Omnichain Fungible Token) protocol for cross-chain token transfers.

## Available Scripts

1. **testOFTCrossChainTransfer.js** - Perform cross-chain token transfers
2. **checkTronBalance.js** - Check token balance on Tron network

## Prerequisites

1. Node.js installed
2. Required npm packages:
   - ethers
   - dotenv
   - @layerzerolabs/lz-v2-utilities
   - yargs
   - tronweb (for Tron-related scripts)

## Installation

Install the required dependencies:

```bash
npm install ethers dotenv @layerzerolabs/lz-v2-utilities yargs tronweb
```

## Configuration

Create a `.env` file in the project root with the following variables:

```
# RPC URL for Sepolia network
SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/YOUR_API_KEY

# Private key for transaction signing
PRIVATE_KEY=your_private_key_here
TRON_PRIVATE_KEY=your_tron_private_key_here

# Contract addresses
STABLES_PROXY_ADDRESS=0x...
OFT_ADAPTER_PROXY_ADDRESS=0x...
TRON_OFT_TOKEN_ADDRESS=0x...
```

## Usage

### Cross-Chain Transfer

Run the cross-chain transfer script with the following command:

```bash
# With minting (if you need to mint tokens before transfer)
node script/bridge/js/testOFTCrossChainTransfer.js --src "sepolia" --dst "tron-testnet" --amount 100000000 --mint

# Without minting (using existing token balance)
node script/bridge/js/testOFTCrossChainTransfer.js --src "sepolia" --dst "tron-testnet" --amount 100000000
```

#### Parameters

- `--src`: Source network (e.g., "sepolia", "fuji", "tron-testnet")
- `--dst`: Destination network (e.g., "sepolia", "fuji", "tron-testnet")
- `--amount`: Amount to transfer in base units (e.g., 100000000 for 100 tokens with 6 decimals)
- `--mint`: (Optional) Mint tokens before transfer. If not provided, the script will use existing token balance.

### Check Tron Balance

To check your token balance on the Tron network:

```bash
node script/bridge/js/checkTronBalance.js
```

## Supported Networks

- Sepolia (Ethereum Testnet)
- Fuji (Avalanche Testnet)
- Tron Testnet

## How It Works

### Cross-Chain Transfer Process

1. Connects to the source network
2. Checks token balance
3. Mints tokens to the sender address (if `--mint` flag is provided)
4. Approves the OFT adapter to spend tokens
5. Sets up LayerZero options for cross-chain transfer
6. Quotes the fee for the transfer
7. Sends tokens cross-chain with the required fee

### Verifying Transfers

After initiating a cross-chain transfer, you can:

1. Use the `checkTronBalance.js` script to verify the tokens arrived at the destination
2. Check the transaction status on LayerZero Explorer: https://testnet.layerzeroscan.com/
3. View the transaction on the destination chain's explorer (e.g., https://shasta.tronscan.org/ for Tron Testnet)
