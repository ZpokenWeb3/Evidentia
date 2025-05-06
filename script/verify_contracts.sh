#!/bin/bash

# Load environment variables
export $(grep -v '^#' .env | xargs)

# Function to verify implementation contract
verify_implementation() {
    local address=$1
    local contract=$2

    echo "Start verifying implementation contract \`$address\` for \`$contract\` on sepolia"
    
    forge verify-contract \
        --chain-id 11155111 \
        --watch \
        --etherscan-api-key "$ETHERSCAN_API_KEY" \
        --compiler-version v0.8.22+commit.4fc1097e \
        "$address" \
        "$contract"
}

# Function to verify proxy contract
verify_proxy() {
    local proxy_address=$1
    local impl_address=$2

    echo "Start verifying proxy contract \`$proxy_address\` pointing to implementation \`$impl_address\` on sepolia"
    
    forge verify-contract \
        --chain-id 11155111 \
        --watch \
        --constructor-args $(cast abi-encode "constructor(address,bytes)" "$impl_address" "0x") \
        --etherscan-api-key "$ETHERSCAN_API_KEY" \
        --compiler-version v0.8.22+commit.4fc1097e \
        "$proxy_address" \
        "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy"
}

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
