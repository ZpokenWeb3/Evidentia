#!/bin/bash

# Check if source and destination network parameters are provided
if [ $# -ne 2 ]; then
    echo "Usage: $0 <source_network> <destination_network>"
    echo "Example: $0 sepolia fuji"
    exit 1
fi

SOURCE_NETWORK="$1"
DESTINATION_NETWORK="$2"

# Create logs directory if it doesn't exist
mkdir -p ./log

# Generate timestamp and log file name
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE="./log/setup_peers_${SOURCE_NETWORK}_to_${DESTINATION_NETWORK}_${TIMESTAMP}.log"

# Log function with timestamp
log() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    echo "$message" | tee -a "$LOG_FILE"
}

# Determine which env file to use based on network
if [[ "$SOURCE_NETWORK" == "mainnet" || "$SOURCE_NETWORK" == "fuji" || "$SOURCE_NETWORK" == "tron-testnet" ]]; then
    ENV_FILE=".env_mainnet"
    log "Using mainnet configuration from $ENV_FILE"
else
    ENV_FILE=".env"
    log "Using testnet configuration from $ENV_FILE"
fi

# Check if env file exists
if [ ! -f "$ENV_FILE" ]; then
    log "ERROR: $ENV_FILE file not found"
    exit 1
fi

# Load environment variables
export $(grep -v '^#' "$ENV_FILE" | xargs)

# Check if OFT_ADAPTER_PROXY_ADDRESS is set
if [ -z "$OFT_ADAPTER_PROXY_ADDRESS" ]; then
    log "ERROR: OFT_ADAPTER_PROXY_ADDRESS is not set in $ENV_FILE"
    exit 1
fi

log "Starting setup of peer connection from $SOURCE_NETWORK to $DESTINATION_NETWORK..."

# Set RPC URL based on source network
if [ "$SOURCE_NETWORK" = "mainnet" ]; then
    RPC_URL="$MAINNET_RPC_URL"
    CHAIN="mainnet"
elif [ "$SOURCE_NETWORK" = "fuji" ]; then
    RPC_URL="$FUJI_RPC_URL"
    CHAIN="fuji"
elif [ "$SOURCE_NETWORK" = "tron-testnet" ]; then
    RPC_URL="$TRON_TESTNET_RPC_URL"
    CHAIN="tron-testnet"
else
    RPC_URL="$SEPOLIA_RPC_URL"
    CHAIN="sepolia"
fi

# Run setup peers script
log "Setting up peer connection from $SOURCE_NETWORK to $DESTINATION_NETWORK..."
RESULT=$(forge script script/bridge/03_SetupPeers.s.sol:SetupPeers \
    --sig "run(string,string)" \
    --rpc-url "$RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --broadcast \
    "$SOURCE_NETWORK" "$DESTINATION_NETWORK" \
    -vvvv \
    2>&1 | tee -a "$LOG_FILE")

# Check if the command was successful
if [ $? -eq 0 ]; then
    log "Peer connection setup completed successfully from $SOURCE_NETWORK to $DESTINATION_NETWORK"
else
    log "ERROR: Failed to setup peer connection from $SOURCE_NETWORK to $DESTINATION_NETWORK"
    exit 1
fi

log "Peer setup complete."
log "Full setup log saved to: $LOG_FILE"