#!/bin/bash

# Load environment variables
export $(grep -v '^#' .env | xargs)

# Function to verify implementation contract
verify_implementation() {
    local address=$1
    local contract=$2
    local constructor_args=$3

    echo "Start verifying contract \`$address\` deployed on sepolia"
    
    if [ -z "$constructor_args" ]; then
        forge verify-contract \
            --chain-id 11155111 \
            --watch \
            --constructor-args "$constructor_args" \
            --etherscan-api-key "$ETHERSCAN_API_KEY" \
            --compiler-version v0.8.22+commit.4fc1097e \
            "$address" \
            "$contract"
    else
        forge verify-contract \
            --chain-id 11155111 \
            --watch \
            --constructor-args "$constructor_args" \
            --etherscan-api-key "$ETHERSCAN_API_KEY" \
            --compiler-version v0.8.22+commit.4fc1097e \
            "$address" \
            "$contract"
    fi
}

# Function to verify proxy contract
verify_proxy() {
    local address=$1
    local implementation=$2
    local constructor_args=$3

    echo "Start verifying contract \`$address\` deployed on sepolia"
    
    forge verify-contract \
        --chain-id 11155111 \
        --watch \
        --constructor-args "$constructor_args" \
        --etherscan-api-key "$ETHERSCAN_API_KEY" \
        --compiler-version v0.8.22+commit.4fc1097e \
        "$address" \
        "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy"
}

# Verify StableBondCoins implementation
verify_implementation "0xde8580Ecf96200457aabD5D6eF530Aef9490C39b" "src/StableBondCoins.sol:StableBondCoins"

# Verify StableBondCoins proxy
verify_proxy "0xE2a8D33e3a60486Bd737760B58811B9089Baa69D" "0xde8580Ecf96200457aabD5D6eF530Aef9490C39b" "0x000000000000000000000000de8580ecf96200457aabd5d6ef530aef9490c39b00000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000"

# Verify BondNFT implementation
verify_implementation "0xd7F2B31EA671eE20a20d85c4350B662F4A547a4E" "src/BondNFT.sol:BondNFT"

# Verify BondNFT proxy
verify_proxy "0x384bdd458c0D390Da495a8E230277dE3a1EE3451" "0xd7F2B31EA671eE20a20d85c4350B662F4A547a4E" "0x000000000000000000000000d7f2b31ea671ee20a20d85c4350b662f4a547a4e00000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000"

# Verify NFTStakingAndBorrowing implementation
verify_implementation "0x9e29Ab5e79B1b5c93CFd7C4Fd0Cfd15BC0e8dC80" "src/NFTStakingAndBorrowing.sol:NFTStakingAndBorrowing"

# Verify NFTStakingAndBorrowing proxy
verify_proxy "0xc590d6e6acdb02957e51B1f549D8B3A8847991D7" "0x9e29Ab5e79B1b5c93CFd7C4Fd0Cfd15BC0e8dC80" "0x0000000000000000000000009e29ab5e79b1b5c93cfd7c4fd0cfd15bc0e8dc8000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000"

# Verify StableCoinsStaking implementation
verify_implementation "0x77f691222B6083a231cC44bcC793847103527F7E" "src/StableCoinsStaking.sol:StableCoinsStaking"

# Verify StableCoinsStaking proxy
verify_proxy "0x86D121802b9c82447E166baAe3893B17D4Ba5A3A" "0x77f691222B6083a231cC44bcC793847103527F7E" "0x00000000000000000000000077f691222b6083a231cc44bcc793847103527f7e00000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000" 
