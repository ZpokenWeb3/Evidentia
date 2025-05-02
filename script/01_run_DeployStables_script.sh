export $(grep -v '^#' .env | xargs)
forge script --chain sepolia script/01_DeployStables.s.sol --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify -vvvv
