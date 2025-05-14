#!/bin/bash

# Check if network parameter is provided
NETWORK="${1:-sepolia}"  # Default to sepolia if not specified

./script/deploy_contract.sh \
    script/01_DeployStables.s.sol \
    StableBondCoins \
    STABLES_PROXY_ADDRESS \
    STABLES_IMPL_ADDRESS \
    $NETWORK
