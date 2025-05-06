#!/bin/bash

./script/deploy_contract.sh \
    script/04_DeployStablesStaking.s.sol \
    StableCoinsStaking \
    STABLES_STAKING_PROXY_ADDRESS \
    STABLES_STAKING_IMPL_ADDRESS
