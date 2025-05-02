export $(grep -v '^#' .env | xargs)
forge script --chain sepolia script/03_DeployNftStaking.s.sol --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify -vvvv
