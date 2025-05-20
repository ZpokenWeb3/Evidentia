#!/bin/bash

# Script to deploy and configure the bridge between two networks
# Usage: ./deploy_bridge_all.sh <source_network> <destination_network> [amount]
# Example: ./deploy_bridge_all.sh sepolia fuji 1000000

# Check if the required arguments are provided
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <source_network> <destination_network> [amount]"
    echo "Example: $0 sepolia fuji 1000000"
    exit 1
fi

SOURCE_NETWORK=$1
DESTINATION_NETWORK=$2
AMOUNT=${3:-1000000}  # Default amount is 1000000 if not provided

echo "Starting bridge deployment and configuration..."
echo "Source network: $SOURCE_NETWORK"
echo "Destination network: $DESTINATION_NETWORK"
echo "Test transfer amount: $AMOUNT"

# Step 1: Deploy StableOFTAdapter on both networks
echo "Step 1: Deploying StableOFTAdapter on $SOURCE_NETWORK..."
./script/bridge/01_run_DeployStableOFTAdapter.sh $SOURCE_NETWORK
if [ $? -ne 0 ]; then
    echo "Failed to deploy StableOFTAdapter on $SOURCE_NETWORK"
    exit 1
fi

echo "Step 1: Deploying StableOFTAdapter on $DESTINATION_NETWORK..."
./script/bridge/01_run_DeployStableOFTAdapter.sh $DESTINATION_NETWORK
if [ $? -ne 0 ]; then
    echo "Failed to deploy StableOFTAdapter on $DESTINATION_NETWORK"
    exit 1
fi

# Step 2: Configure LayerZero Endpoint for both networks
echo "Step 2: Configuring LayerZero Endpoint on $SOURCE_NETWORK..."
./script/bridge/02_run_ConfigureLayerZeroEndpoint.sh $SOURCE_NETWORK
if [ $? -ne 0 ]; then
    echo "Failed to configure LayerZero Endpoint on $SOURCE_NETWORK"
    exit 1
fi

echo "Step 2: Configuring LayerZero Endpoint on $DESTINATION_NETWORK..."
./script/bridge/02_run_ConfigureLayerZeroEndpoint.sh $DESTINATION_NETWORK
if [ $? -ne 0 ]; then
    echo "Failed to configure LayerZero Endpoint on $DESTINATION_NETWORK"
    exit 1
fi

# Step 3: Setup peer connections between networks (both directions)
echo "Step 3: Setting up peer connection from $SOURCE_NETWORK to $DESTINATION_NETWORK..."
./script/bridge/03_run_SetupPeers.sh $SOURCE_NETWORK $DESTINATION_NETWORK
if [ $? -ne 0 ]; then
    echo "Failed to setup peer connection from $SOURCE_NETWORK to $DESTINATION_NETWORK"
    exit 1
fi

echo "Step 3: Setting up peer connection from $DESTINATION_NETWORK to $SOURCE_NETWORK..."
./script/bridge/03_run_SetupPeers.sh $DESTINATION_NETWORK $SOURCE_NETWORK
if [ $? -ne 0 ]; then
    echo "Failed to setup peer connection from $DESTINATION_NETWORK to $SOURCE_NETWORK"
    exit 1
fi

# Step 4: Test cross-chain token transfer
echo "Step 4: Testing cross-chain token transfer from $SOURCE_NETWORK to $DESTINATION_NETWORK with amount $AMOUNT..."
./script/bridge/04_run_TestOFTCrossChainTransfer.sh $SOURCE_NETWORK $DESTINATION_NETWORK $AMOUNT
if [ $? -ne 0 ]; then
    echo "Failed to test cross-chain token transfer from $SOURCE_NETWORK to $DESTINATION_NETWORK"
    exit 1
fi

echo "Bridge deployment and configuration completed successfully!"
echo "You can now transfer tokens between $SOURCE_NETWORK and $DESTINATION_NETWORK."