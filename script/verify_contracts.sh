#!/bin/bash

# Log function with timestamp
log() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    echo "$message"
}

# Load environment variables
if [ ! -f .env ]; then
    log "ERROR: .env file not found"
    exit 1
fi
export $(grep -v '^#' .env | xargs)

# Function to check if contract is already verified
check_verification_status() {
    local address=$1
    local contract_name=$2
    local output
    output=$(forge verify-check --chain-id 11155111 --etherscan-api-key "$ETHERSCAN_API_KEY" "$address" 2>&1)
    if echo "$output" | grep -q "Contract is already verified"; then
        log "Contract at $address ($contract_name) is already verified. Skipping verification."
        return 0
    fi
    return 1
}

# Function to verify implementation contract
verify_implementation() {
    local address=$1
    local contract=$2

    log "Starting verification of implementation contract \`$address\` for \`$contract\` on Sepolia"

    # Skip if already verified
    if check_verification_status "$address" "$contract"; then
        return 0
    fi

    forge verify-contract \
        --chain-id 11155111 \
        --watch \
        --etherscan-api-key "$ETHERSCAN_API_KEY" \
        --compiler-version v0.8.30+commit.4fc1097e \
        "$address" \
        "$contract" || {
        log "WARNING: Failed to verify implementation contract \`$address\` for \`$contract\`"
        return 1
    }
    log "Successfully verified implementation contract \`$address\` for \`$contract\`"
}

# Function to verify proxy contract
verify_proxy() {
    local proxy_address=$1
    local impl_address=$2

    log "Starting verification of proxy contract \`$proxy_address\` pointing to implementation \`$impl_address\` on Sepolia"

    # Skip if already verified
    if check_verification_status "$proxy_address" "ERC1967Proxy"; then
        return 0
    fi

    # Use the correct path to OpenZeppelin ERC1967Proxy contract
    forge verify-contract \
        --chain-id 11155111 \
        --watch \
        --constructor-args $(cast abi-encode "constructor(address,bytes)" "$impl_address" "0x") \
        --etherscan-api-key "$ETHERSCAN_API_KEY" \
        --compiler-version v0.8.30+commit.4fc1097e \
        "$proxy_address" \
        "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy" || {
        log "WARNING: Failed to verify proxy contract \`$proxy_address\`"
        return 1
    }
    log "Successfully verified proxy contract \`$proxy_address\`"
}

log "Starting contracts verification process (continue on errors)..."

# Verify StableBondCoins implementation and proxy
verify_implementation "$STABLES_IMPL_ADDRESS" "src/StableBondCoins.sol:StableBondCoins"
verify_proxy "$STABLES_PROXY_ADDRESS" "$STABLES_IMPL_ADDRESS"

# Verify BondNFT implementation and proxy
verify_implementation "$BOND_NFT_IMPL_ADDRESS" "src/BondNFT.sol:BondNFT"
verify_proxy "$BOND_NFT_PROXY_ADDRESS" "$BOND_NFT_IMPL_ADDRESS"

# Verify NFTStakingAndBorrowing implementation and proxy
verify_implementation "$NFT_STAKING_IMPL_ADDRESS" "src/NFTStakingAndBorrowing.sol:NFTStakingAndBorrowing"
verify_proxy "$NFT_STAKING_PROXY_ADDRESS" "$NFT_STAKING_IMPL_ADDRESS"

# Verify StableCoinsStaking implementation and proxy
verify_implementation "$STABLES_STAKING_IMPL_ADDRESS" "src/StableCoinsStaking.sol:StableCoinsStaking"
verify_proxy "$STABLES_STAKING_PROXY_ADDRESS" "$STABLES_STAKING_IMPL_ADDRESS"

log "Contracts verification process completed"
