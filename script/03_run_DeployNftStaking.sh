#!/bin/bash

./script/deploy_contract.sh \
    script/03_DeployNftStaking.s.sol \
    NFTStakingAndBorrowing \
    NFT_STAKING_PROXY_ADDRESS \
    NFT_STAKING_IMPL_ADDRESS
