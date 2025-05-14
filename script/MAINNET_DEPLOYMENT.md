# Mainnet Deployment Instructions

This document provides instructions for deploying the contracts to the Ethereum mainnet.

## Prerequisites

1. Make sure you have the `.env_mainnet` file properly configured with:
   - `MAINNET_RPC_URL`: A valid Ethereum mainnet RPC URL
   - `PRIVATE_KEY`: The private key of the deployer account (with sufficient ETH for gas)
   - `ETHERSCAN_API_KEY`: A valid Etherscan API key for contract verification
   - Other required configuration parameters

2. Ensure the deployer account has sufficient ETH for gas fees on mainnet.

## Deployment Options

### Option 1: Full Deployment

To deploy all contracts to mainnet in sequence:

```bash
./script/deploy_all.sh mainnet
```

This will:
1. Update all ABIs
2. Deploy StableBondCoins
3. Deploy BondNFT
4. Deploy NFTStakingAndBorrowing
5. Deploy StableCoinsStaking
6. Configure contract interactions (set minter, whitelist NFT, etc.)

### Option 2: Individual Contract Deployment

To deploy individual contracts to mainnet:

```bash
# Deploy StableBondCoins
./script/01_run_DeployStables.sh mainnet

# Deploy BondNFT
./script/02_run_DeployNft.sh mainnet

# Deploy NFTStakingAndBorrowing
./script/03_run_DeployNftStaking.sh mainnet

# Deploy StableCoinsStaking
./script/04_run_DeployStablesStaking.sh mainnet
```

### Option 3: Post-Deployment Configuration

To run individual configuration steps after deployment:

```bash
# Set NFTStakingAndBorrowing as minter for StableBondCoins
NODE_ENV=mainnet node script/05_set_Minter.js

# Whitelist BondNFT in NFTStakingAndBorrowing
NODE_ENV=mainnet node script/05a_whitelist_nft_contract.js

# Set StableCoinsStaking address in NFTStakingAndBorrowing
NODE_ENV=mainnet node script/05b_set_stables_staking.js

# Set metadata for a specific token ID in BondNFT
NODE_ENV=mainnet node script/05c_set_metadata.js -i DD.MM.YYYY -e DD.MM.YYYY -v VALUE -c COUPON -n ISIN
```

## Logs

All deployment logs will be saved in the `./log` directory with timestamps and network information.

## Verification

After deployment, you can verify the contracts on Etherscan using:

```bash
# Uncomment the verification step in deploy_all.sh or run manually:
# ./script/verify_contracts.sh mainnet
```

## Troubleshooting

1. If a deployment fails, check the logs for error messages.
2. Ensure your `.env_mainnet` file has the correct configuration.
3. Make sure your deployer account has sufficient ETH for gas fees.
4. For contract interaction issues, verify that the contract addresses in `.env_mainnet` are correct.