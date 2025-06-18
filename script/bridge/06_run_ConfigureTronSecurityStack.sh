#!/bin/bash

# Script to configure the LayerZero security stack for Tron Mainnet
# This script sets up DVNs and Executors for the OApp on Tron

# Exit on error
set -e

# Directory for logs
LOG_DIR="./log"
mkdir -p "$LOG_DIR"

# Timestamp for log file
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE="$LOG_DIR/configure_tron_security_stack_$TIMESTAMP.log"

# Function to log messages
log() {
    local message="[$(date +"%Y-%m-%d %H:%M:%S")] $1"
    echo "$message"
    echo "$message" >> "$LOG_FILE"
}

# Check if .env_mainnet file exists
if [ ! -f ".env_mainnet" ]; then
    log "ERROR: .env_mainnet file not found. Please create it with the required environment variables."
    exit 1
fi

# Load environment variables
log "Using mainnet configuration from .env_mainnet"
source .env_mainnet

# Check required environment variables
if [ -z "$TRON_OFT_TOKEN_ADDRESS" ]; then
    log "ERROR: TRON_OFT_TOKEN_ADDRESS environment variable is not set"
    exit 1
fi

if [ -z "$PRIVATE_KEY" ]; then
    log "ERROR: PRIVATE_KEY environment variable is not set"
    exit 1
fi

if [ -z "$TRON_MAINNET_RPC_URL" ]; then
    log "ERROR: TRON_MAINNET_RPC_URL environment variable is not set"
    exit 1
fi

# Start the configuration process
log "Starting Tron security stack configuration..."

# Run configure Tron security stack script
log "Configuring security stack for Tron Mainnet..."
set -o pipefail
forge script script/bridge/06_ConfigureTronSecurityStack.s.sol:ConfigureTronSecurityStack \
    --sig "run()" \
    --rpc-url "$TRON_MAINNET_RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --broadcast \
    -vvvv \
    2>&1 | tee -a "$LOG_FILE"

RESULT=$?
# Check if the command was successful
if [ $RESULT -eq 0 ]; then
    log "Tron security stack configuration completed successfully"
else
    log "ERROR: Failed to configure Tron security stack"
    exit 1
fi

log "Tron security stack configuration complete."
log "Full configuration log saved to: $LOG_FILE"
