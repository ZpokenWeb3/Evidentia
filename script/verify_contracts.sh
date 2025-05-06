#!/bin/bash

export $(grep -v '^#' .env | xargs)

# StableBondCoins
forge verify-contract \
    0xde8580Ecf96200457aabD5D6eF530Aef9490C39b \
    src/StableBondCoins.sol:StableBondCoins \
    --chain-id 11155111 \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --watch

forge verify-contract \
    0xE2a8D33e3a60486Bd737760B58811B9089Baa69D \
    lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy \
    --constructor-args $(cast abi-encode "constructor(address,bytes)" "0xde8580Ecf96200457aabD5D6eF530Aef9490C39b" "0x") \
    --chain-id 11155111 \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --watch

# BondNFT
forge verify-contract \
    0xd7F2B31EA671eE20a20d85c4350B662F4A547a4E \
    src/BondNFT.sol:BondNFT \
    --chain-id 11155111 \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --watch

forge verify-contract \
    0x384bdd458c0D390Da495a8E230277dE3a1EE3451 \
    lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy \
    --constructor-args $(cast abi-encode "constructor(address,bytes)" "0xd7F2B31EA671eE20a20d85c4350B662F4A547a4E" "0x") \
    --chain-id 11155111 \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --watch

# NFTStakingAndBorrowing
forge verify-contract \
    0x9e29Ab5e79B1b5c93CFd7C4Fd0Cfd15BC0e8dC80 \
    src/NFTStakingAndBorrowing.sol:NFTStakingAndBorrowing \
    --chain-id 11155111 \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --watch

forge verify-contract \
    0xc590d6e6acdb02957e51B1f549D8B3A8847991D7 \
    lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy \
    --constructor-args $(cast abi-encode "constructor(address,bytes)" "0x9e29Ab5e79B1b5c93CFd7C4Fd0Cfd15BC0e8dC80" "0x") \
    --chain-id 11155111 \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --watch

# StableCoinsStaking
forge verify-contract \
    0x77f691222B6083a231cC44bcC793847103527F7E \
    src/StableCoinsStaking.sol:StableCoinsStaking \
    --chain-id 11155111 \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --watch

forge verify-contract \
    0x86D121802b9c82447E166baAe3893B17D4Ba5A3A \
    lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy \
    --constructor-args $(cast abi-encode "constructor(address,bytes)" "0x77f691222B6083a231cC44bcC793847103527F7E" "0x") \
    --chain-id 11155111 \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --watch 