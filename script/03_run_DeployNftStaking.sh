#!/bin/bash

# Check if network parameter is provided
NETWORK="${1:-sepolia}"  # Default to sepolia if not specified

./script/deploy_contract.sh \
    script/03_DeployNftStaking.s.sol \
    NFTStakingAndBorrowing \
    NFT_STAKING_PROXY_ADDRESS \
    NFT_STAKING_IMPL_ADDRESS \
    $NETWORK
