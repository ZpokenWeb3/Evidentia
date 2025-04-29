// scripts/DeployStablesByName.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {StableBondCoins} from "../src/StableBondCoins.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {LayerZeroConstants} from "./bridge/LayerZeroConstants.s.sol";

/**
 * @title DeployStablesByName
 * @dev Deploys a UUPS proxy of StableBondCoins on any supported chain by name.
 *
 * USAGE:
 *   forge script \
 *     script/01_DeployStables.s.sol:DeployStables \
 *     --sig "run(string)" \
 *     --rpc-url sepolia \
 *     --broadcast \
 *     --private-key $PRIVATE_KEY \
 *     "sepolia"
 */
contract DeployStables is Script {
    /// @param network one of: "fuji", "avaxMainnet", "arbSepolia", "mumbai", "tron-testnet", etc.
    function run(string calldata network) external returns (StableBondCoins) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address owner = vm.envAddress("OWNER");
        // look up the LayerZero endpoint for this chain
        LayerZeroConstants.ChainConfig memory cfg = LayerZeroConstants.getChainConfigByName(network);

        vm.startBroadcast(pk);
        // deploy implementation
        StableBondCoins impl = new StableBondCoins(cfg.endpoint);

        // deploy UUPS proxy, calling initialize(owner, owner, owner)
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), abi.encodeCall(impl.initialize, (owner, owner, owner)));

        StableBondCoins token = StableBondCoins(address(proxy));
        console.log("StableBondCoins proxy deployed at:", address(token));
        vm.stopBroadcast();

        return token;
    }
}
