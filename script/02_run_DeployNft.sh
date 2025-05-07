#!/bin/bash

./script/deploy_contract.sh \
    script/02_DeployNft.s.sol \
    BondNFT \
    BOND_NFT_PROXY_ADDRESS \
    BOND_NFT_IMPL_ADDRESS
