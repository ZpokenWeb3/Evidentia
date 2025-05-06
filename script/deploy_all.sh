#!/bin/bash

# Log function with timestamp
log() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    echo "$message"
}

# Function to execute a command and check its status
execute_step() {
    local step_name="$1"
    local command="$2"
    log "Executing: $step_name"
    log "Command: $command"
    eval "$command"
    if [ $? -ne 0 ]; then
        log "ERROR: $step_name failed"
        exit 1
    fi
    log "$step_name completed successfully"
}

# Create logs directory if it doesn't exist
mkdir -p ./log

# Main log file for the entire deployment process
LOG_FILE="./log/deploy_all_$(date +'%Y-%m-%d_%H-%M-%S').log"

# Redirect all output to log file and console
exec > >(tee -a "$LOG_FILE") 2>&1

log "Starting full deployment process..."

# Step 1: Update all ABIs
execute_step "Update all ABIs" "./script/update_all_abis.sh"

# Pause for 5 seconds
log "Waiting 5 seconds before next step..."
sleep 5

# Step 2: Deploy StableBondCoins
execute_step "Deploy StableBondCoins" "./script/01_run_DeployStables.sh"

# Pause for 60 seconds
log "Waiting 60 seconds before next step..."
sleep 60

# Step 3: Deploy BondNFT
execute_step "Deploy BondNFT" "./script/02_run_DeployNft.sh"

# Pause for 60 seconds
log "Waiting 60 seconds before next step..."
sleep 60

# Step 4: Deploy NFTStakingAndBorrowing
execute_step "Deploy NFTStakingAndBorrowing" "./script/03_run_DeployNftStaking.sh"

# Pause for 60 seconds
log "Waiting 60 seconds before next step..."
sleep 60

# Step 5: Deploy StableCoinsStaking
execute_step "Deploy StableCoinsStaking" "./script/04_run_DeployStablesStaking.sh"

# Pause for 60 seconds
log "Waiting 60 seconds before next step..."
sleep 60

# # Step 6: Verify contracts
# execute_step "Verify contracts" "./script/verify_contracts.sh"
# 
# # Pause for 5 seconds
# log "Waiting 5 seconds before next step..."
# sleep 5

# Step 7: Set NFTStakingAndBorrowing as minter for StableBondCoins
execute_step "Set NFTStakingAndBorrowing as minter" "node script/05_set_Minter.js"

# Pause for 20 seconds
log "Waiting 20 seconds before next step..."
sleep 20

# Step 8: Whitelist BondNFT in NFTStakingAndBorrowing
execute_step "Whitelist BondNFT" "node script/05a_whitelist_nft_contract.js"

# Pause for 20 seconds
log "Waiting 20 seconds before next step..."
sleep 20

# Step 9: Set StableCoinsStaking address in NFTStakingAndBorrowing
execute_step "Set StableCoinsStaking address" "node script/05b_set_stables_staking.js"

# # Pause for 20 seconds
# log "Waiting 20 seconds before next step..."
# sleep 20
# 
# # Step 10: Set Metadata for a specific token ID in BondNFT
# execute_step "Set Metadata for BondNFT" "node script/05c_set_metadata.js -i 29.04.2025 -e 19.08.2026 -v 1000_000000 -c 81_650000 -n UA4000235378"

log "Full deployment process completed successfully!"
log "All logs saved to: $LOG_FILE"
