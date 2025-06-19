#!/bin/bash

# Check if network and libType parameters are provided
if [ $# -ne 2 ]; then
    echo "Usage: $0 <network> <libType>"
    echo "Example: $0 mainnet send"
    echo "libType must be 'send' or 'recv'"
    exit 1
fi

NETWORK="$1"
LIB_TYPE="$2"

# Validate libType
if [ "$LIB_TYPE" != "send" ] && [ "$LIB_TYPE" != "recv" ]; then
    echo "ERROR: libType must be 'send' or 'recv'"
    exit 1
fi

# Create logs directory if it doesn't exist
mkdir -p ./log

# Generate timestamp and log file name
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE="./log/configure_security_stack_${NETWORK}_${LIB_TYPE}_${TIMESTAMP}.log"

# Log function with timestamp
log() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    echo "$message" | tee -a "$LOG_FILE"
}

# Determine which env file to use based on network
if [[ "$NETWORK" == "mainnet" || "$NETWORK" == "fuji" || "$NETWORK" == "tron-mainnet" ]]; then
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

log "Starting security stack configuration for $NETWORK with libType $LIB_TYPE..."

# Set RPC URL based on network
if [ "$NETWORK" = "mainnet" ]; then
    RPC_URL="$MAINNET_RPC_URL"
    CHAIN="mainnet"
elif [ "$NETWORK" = "fuji" ]; then
    RPC_URL="$FUJI_RPC_URL"
    CHAIN="fuji"
elif [ "$NETWORK" = "tron-mainnet" ]; then
    RPC_URL="$TRON_MAINNET_RPC_URL"
    CHAIN="tron-mainnet"
else
    RPC_URL="$SEPOLIA_RPC_URL"
    CHAIN="sepolia"
fi

# Run configure security stack script
log "Configuring security stack for $NETWORK with libType $LIB_TYPE..."
set -o pipefail
forge script script/bridge/05_ConfigureSecurityStack.s.sol:ConfigureSecurityStack \
    --sig "run(string,string)" \
    --rpc-url "$RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --broadcast \
    "$NETWORK" "$LIB_TYPE" \
    -vvvv \
    2>&1 | tee -a "$LOG_FILE"

RESULT=$?
# Check if the command was successful
if [ $RESULT -eq 0 ]; then
    log "Security stack configuration completed successfully for $NETWORK with libType $LIB_TYPE"
else
    log "ERROR: Failed to configure security stack for $NETWORK with libType $LIB_TYPE"
    exit 1
fi

log "Security stack configuration complete."
log "Full configuration log saved to: $LOG_FILE"
