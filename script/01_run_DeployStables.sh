#!/bin/bash

./script/deploy_contract.sh \
    script/01_DeployStables.s.sol \
    StableBondCoins \
    STABLES_PROXY_ADDRESS \
    STABLES_IMPL_ADDRESS
