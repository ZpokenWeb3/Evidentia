# Deployment order:

## 1. Update all ABIs

```bash
./script/update_all_abis.sh
```

## 2. Deploy StableBondCoins

```bash
./script/01_run_DeployStables.sh
```

## 3. Deploy BondNFT

```bash
./script/02_run_DeployNft.sh
```

## 4. Deploy NFTStakingAndBorrowing

```bash
./script/03_run_DeployNftStaking.sh
```

## 5. Deploy StableCoinsStaking

```bash
./script/04_run_DeployStablesStaking.sh
```

## 6. Verify contracts

```bash
./script/verify_contracts.sh
```

## 7. Set NFTStakingAndBorrowing as minter for StableBondCoins

```bash
node script/05_set_Minter.js
```

## 8. Whitelist BondNFT in NFTStakingAndBorrowing

```bash
node script/05a_whitelist_nft_contract.js
```

## 9. Set StableCoinsStaking address in NFTStakingAndBorrowing

```bash
node script/05b_set_stables_staking.js
```

## 10. Set Metadata for a specific token ID in BondNFT

```bash
node script/05c_set_metadata.js [options]
node script/05c_set_metadata.js -i DD.MM.YYYY -e DD.MM.YYYY -v VALUE -c COUPON -n ISIN
```

Example:

```bash
node script/05c_set_metadata.js -i 29.04.2025 -e 19.08.2026 -v 1000_000000 -c 81_650000 -n UA4000235378
NODE_ENV=mainnet node script/05c_set_metadata.js -i 29.04.2025 -e 19.08.2026 -v 1000_000000 -c 81_650000 -n UA4000235378
```

# Automated Deployment

```bash
./script/deploy_all.sh
```

## 1. Deploy StableOFTAdapter

```bash
./script/bridge/01_run_DeployStableOFTAdapter.sh [network]
```

Example:

```bash
./script/bridge/01_run_DeployStableOFTAdapter.sh sepolia
./script/bridge/01_run_DeployStableOFTAdapter.sh fuji
```

This script uses the `01_DeployStableOFTAdapter.s.sol` Solidity script to deploy the StableOFTAdapter contract.

## 2. Configure LayerZero Endpoint for StableOFTAdapter

After deploying the StableOFTAdapter, you need to configure the LayerZero endpoint to enable cross-chain functionality.

```bash
./script/bridge/02_run_ConfigureLayerZeroEndpoint.sh [network]
```

Example:

```bash
./script/bridge/02_run_ConfigureLayerZeroEndpoint.sh sepolia
./script/bridge/02_run_ConfigureLayerZeroEndpoint.sh fuji
```

This script uses the `02_ConfigureLayerZeroEndpoint.s.sol` Solidity script to configure the send library for the OFT adapter in the LayerZero endpoint, which is necessary for cross-chain token transfers.

## 3. Setup Peer Connection Between Networks

After configuring the LayerZero endpoints, you need to set up peer connections between OFT adapters in different networks to enable cross-chain token transfers.

```bash
./script/bridge/03_run_SetupPeers.sh <source_network> <destination_network>
```

Example:

```bash
./script/bridge/03_run_SetupPeers.sh sepolia fuji
```

This script uses the `03_SetupPeers.s.sol` Solidity script to establish a connection between the OFT adapter in the source network and the OFT adapter in the destination network. You need to run this script for each direction of token transfer you want to enable.

## 4. Test Cross-Chain Token Transfer

After setting up peer connections, you can test cross-chain token transfers between networks.

```bash
./script/bridge/04_run_TestOFTCrossChainTransfer.sh <source_network> <destination_network> <amount>
```

Example:

```bash
./script/bridge/04_run_TestOFTCrossChainTransfer.sh sepolia fuji 1000000
```

This script uses the `04_TestOFTCrossChainTransfer.s.sol` Solidity script to mint tokens in the source network and send them to the destination network. The amount is specified in base units (e.g., 1000000 for 1 token with 6 decimals).

## Automated Bridge Deployment

You can also use the automated script to deploy and configure the bridge between two networks in one go:

```bash
./script/bridge/deploy_bridge_all.sh <source_network> <destination_network> [amount]
```

Example:

```bash
./script/bridge/deploy_bridge_all.sh sepolia fuji 1000000
```

This script will:
1. Deploy StableOFTAdapter on both networks (using `01_DeployStableOFTAdapter.s.sol`)
2. Configure LayerZero Endpoint for both networks (using `02_ConfigureLayerZeroEndpoint.s.sol`)
3. Setup peer connections between networks in both directions (using `03_SetupPeers.s.sol`)
4. Test cross-chain token transfer with the specified amount (using `04_TestOFTCrossChainTransfer.s.sol`)

# Testing in Testnet

This section describes the scripts used for testing the smart contracts in the Sepolia testnet.
Each script interacts with the deployed contracts and accepts parameters via the command line.
Environment variables (e.g., contract addresses, private key, RPC URL) are loaded from the `.env` file.

## Set Mint Allowance for NFT Tokens

```bash
node script/06_mint_allowance.js <allowToAddress> <tokenId> <mintAmount>
```

Example:

```bash
node script/06_mint_allowance.js 0xC85906530Df2D4227f713CFCDD08085309A4f821 75955146522550863186049403197281544413786813629915328080343312216854220103147 1000
NODE_ENV=mainnet node script/06_mint_allowance.js 0x2e990d5cea3e2748257287acb0d70a50e6f31f33 75955146522550863186049403197281544413786813629915328080343312216854220103147 1000
```

## Mint NFT Tokens

```bash
node script/07_mint_nft.js <tokenId> <mintAmount>
```

Example:

```bash
node script/07_mint_nft.js 75955146522550863186049403197281544413786813629915328080343312216854220103147 10
```

## Approve NFT Tokens

```bash
node script/08_approve_nft.js
```

## Stake NFT Tokens

```bash
node script/09_stake_nft.js <tokenId> <amount>
```

Example:

```bash
node script/09_stake_nft.js 75955146522550863186049403197281544413786813629915328080343312216854220103147 10
```

## Unstake NFT Tokens

```bash
node script/10_unstake_nft.js <tokenId> <amount>
```

Example:

```bash
node script/10_unstake_nft.js 75955146522550863186049403197281544413786813629915328080343312216854220103147 10
```

## Borrow Stables

```bash
node script/11_borrow.js <amount>
```

Example:

```bash
node script/11_borrow.js 1000000000
```

## Repay Stables

```bash
node script/12_repay.js <amount>
```

Example:

```bash
node script/12_repay.js 1000000000
```

## Stake NFT and Stables

```bash
node script/13_stake_nft_and_stables.js <tokenId> <amount>
```

Example:

```bash
node script/13_stake_nft_and_stables.js 75955146522550863186049403197281544413786813629915328080343312216854220103147 10
```

## Approve Stables

```bash
node script/14_approve_stables.js
```

## Stake Stables

```bash
node script/15_stake_stables.js <amount>
```

Example:

```bash
node script/15_stake_stables.js 1000000000
```
