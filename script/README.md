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
```

# Automated Deployment

```bash
./script/deploy_all.sh
```

# Testing in Testnet

This section describes the scripts used for testing the smart contracts in the Sepolia testnet.
Each script interacts with the deployed contracts and accepts parameters via the command line.
Environment variables (e.g., contract addresses, private key, RPC URL) are loaded from the `.env` file.

## Set Mint Allowance for NFT Tokens

```bash
node script/06_mint_allowance.js <allowToAddress> <tokenId> <mintAmount>
```

## Mint NFT Tokens

```bash
node script/07_mint_nft.js <tokenId> <mintAmount>
```

## Approve NFT Tokens

```bash
node script/08_approve_nft.js
```

## Stake NFT Tokens

```bash
node script/09_stake_nft.js <tokenId> <amount>
```

## Unstake NFT Tokens

```bash
node script/10_unstake_nft.js <tokenId> <amount>
```

## Borrow Stables

```bash
node script/11_borrow.js <amount>
```

## Repay Stables

```bash
node script/12_repay.js <amount>
```

## Stake NFT and Stables

```bash
node script/13_stake_nft_and_stables.js <tokenId> <amount>
```

## Approve Stables

```bash
node script/14_approve_stables.js
```

## Stake Stables

```bash
node script/15_stake_stables.js <amount>
```
