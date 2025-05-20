#!/bin/bash

# Check if network parameter is provided
NETWORK="${1:-sepolia}"  # Default to sepolia if not specified

./script/deploy_contract.sh \
    script/bridge/01_DeployStableOFTAdapter.s.sol \
    StableOFTAdapter \
    OFT_ADAPTER_PROXY_ADDRESS \
    OFT_ADAPTER_IMPL_ADDRESS \
    $NETWORK
