#!/bin/bash

# Check if required arguments are provided
if [ $# -ne 4 ]; then
    echo "Usage: $0 <sol_script> <contract_name> <proxy_env_var> <impl_env_var>"
    echo "Example: $0 script/01_DeployStables.s.sol StableBondCoins STABLES_PROXY_ADDRESS STABLES_IMPL_ADDRESS"
    exit 1
fi

SOL_SCRIPT="$1"
CONTRACT_NAME="$2"
PROXY_ENV_VAR="$3"
IMPL_ENV_VAR="$4"

# Create logs directory if it doesn't exist
mkdir -p ./log

# Generate timestamp and log file name
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE="./log/deploy_${CONTRACT_NAME}_${TIMESTAMP}.log"

# Log function with timestamp
log() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    echo "$message" | tee -a "$LOG_FILE"
}

# Check if .env file exists
if [ ! -f .env ]; then
    log "ERROR: .env file not found"
    exit 1
fi

# Load environment variables
export $(grep -v '^#' .env | xargs)

log "Starting deployment of $CONTRACT_NAME contract..."

# Run deployment with tee to both console and log file
log "Deployment command executing..."
DEPLOY_OUTPUT=$(forge script "$SOL_SCRIPT" \
    --chain sepolia \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --slow \
    --verify \
    -vvvv \
    2>&1 | tee -a "$LOG_FILE")

# Parse addresses from deployment output
PROXY_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep -oP 'new ERC1967Proxy@0x[a-fA-F0-9]{40}' | head -1 | grep -oP '0x[a-fA-F0-9]{40}')
IMPL_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep -oP "new ${CONTRACT_NAME}@0x[a-fA-F0-9]{40}" | head -1 | grep -oP '0x[a-fA-F0-9]{40}')

# Validate addresses
validate_address() {
    [[ $1 =~ ^0x[a-fA-F0-9]{40}$ ]] || {
        log "ERROR: Invalid address: $1"
        exit 1
    }
}

# Check if addresses were found
if [ -z "$PROXY_ADDRESS" ]; then
    log "ERROR: Failed to parse Proxy contract address"
    exit 1
fi
if [ -z "$IMPL_ADDRESS" ]; then
    log "ERROR: Failed to parse $CONTRACT_NAME contract address"
    exit 1
fi

validate_address "$PROXY_ADDRESS"
validate_address "$IMPL_ADDRESS"

log "Proxy: $PROXY_ADDRESS"
log "Implementation ($CONTRACT_NAME): $IMPL_ADDRESS"

# Update .env file
log "Updating .env file..."
sed -i -E "s|^(${PROXY_ENV_VAR}=).*|\1$PROXY_ADDRESS|" .env
sed -i -E "s|^(${IMPL_ENV_VAR}=).*|\1$IMPL_ADDRESS|" .env

log "Update complete. Deployment finished."
log "Full deployment log saved to: $LOG_FILE"
