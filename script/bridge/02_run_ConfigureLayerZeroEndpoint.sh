#!/bin/bash

# Check if network parameter is provided
if [ $# -gt 1 ]; then
    echo "Usage: $0 [network]"
    echo "Example: $0 sepolia"
    echo "Example: $0 fuji"
    echo "Default network is sepolia if not specified"
    exit 1
fi

NETWORK="${1:-sepolia}"  # Default to sepolia if not specified

# Create logs directory if it doesn't exist
mkdir -p ./log

# Generate timestamp and log file name
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE="./log/configure_lz_endpoint_${NETWORK}_${TIMESTAMP}.log"

# Log function with timestamp
log() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    echo "$message" | tee -a "$LOG_FILE"
}

# Determine which env file to use based on network
if [[ "$NETWORK" == "mainnet" || "$NETWORK" == "fuji" || "$NETWORK" == "tron-testnet" ]]; then
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

log "Starting configuration of LayerZero endpoint for OFT Adapter on $NETWORK..."

# Set RPC URL based on network
if [ "$NETWORK" = "mainnet" ]; then
    RPC_URL="$MAINNET_RPC_URL"
    CHAIN="mainnet"
elif [ "$NETWORK" = "fuji" ]; then
    RPC_URL="$FUJI_RPC_URL"
    CHAIN="fuji"
elif [ "$NETWORK" = "tron-testnet" ]; then
    RPC_URL="$TRON_TESTNET_RPC_URL"
    CHAIN="tron-testnet"
else
    RPC_URL="$SEPOLIA_RPC_URL"
    CHAIN="sepolia"
fi

# Run configuration script
log "Configuration command executing on $NETWORK..."
RESULT=$(forge script script/bridge/02_ConfigureLayerZeroEndpoint.s.sol:ConfigureLayerZeroEndpoint \
    --sig "run(string)" \
    --rpc-url "$RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --broadcast \
    "$NETWORK" \
    -vvvv \
    2>&1 | tee -a "$LOG_FILE")

# Check if the command was successful
if [ $? -eq 0 ]; then
    log "LayerZero endpoint configuration completed successfully for OFT Adapter on $NETWORK"
else
    log "ERROR: Failed to configure LayerZero endpoint for OFT Adapter on $NETWORK"
    exit 1
fi

log "Configuration complete."
log "Full configuration log saved to: $LOG_FILE"