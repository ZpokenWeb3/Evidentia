#!/bin/bash

./script/deploy_contract.sh \
    script/02_DeployNft.s.sol \
    BondNFT \
    NFT_PROXY_ADDRESS \
    NFT_IMPL_ADDRESS
