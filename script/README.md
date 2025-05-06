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
