#!/bin/bash

# Load environment variables
export $(grep -v '^#' .env | xargs)

# Run the script
forge script script/02_DeployNft.s.sol \
    --chain sepolia \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify \
    -vvvv 
