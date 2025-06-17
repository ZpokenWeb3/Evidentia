// scripts/SetupPeersByName.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {StableBondCoins} from "../../src/StableBondCoins.sol";
import {LayerZeroConstants} from "./LayerZeroConstants.s.sol";
import {console} from "forge-std/console.sol";
import {StableOFTAdapter} from "../../src/StableOFTAdapter.sol";

/**
 * @title SetupPeers
 * @dev Sets up peer connections between StableBondCoins contracts on different chains.
 *
 * USAGE:
 *   forge script script/bridge/SetupPeers.s.sol:SetupPeers \
 *     --sig "run(string,string)" \
 *     --rpc-url fuji \
 *     --broadcast \
 *     --private-key $PRIVATE_KEY \
 *     "fuji" "sepolia"
 */
contract SetupPeers is Script {
    /// @param src  human-readable key for the source chain, e.g. "fuji", "sepolia", "tron-testnet"
    /// @param dst  human-readable key for the destination chain
    function run(string calldata src, string calldata dst) external {
        LayerZeroConstants.ChainConfig memory cDst = LayerZeroConstants.getChainConfigByName(dst);

        // pick up the two proxy addresses from env
        address proxySrc = _envProxy(src);
        address proxyDst = _envProxy(dst);

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        // setPeer(dstEid, bytes32 address) on the source contract
        StableOFTAdapter(proxySrc).setPeer(cDst.eid, bytes32(uint256(uint160(proxyDst))));
        vm.stopBroadcast();

        console.log("Peer set:", src, "->", dst);
    }

    /// internal helper: branch on the chain name to pick the right env var
    function _envProxy(string memory network) internal view returns (address) {
        bytes32 k = keccak256(bytes(network));

        if (k == keccak256("sepolia")) {
            return vm.envAddress("OFT_ADAPTER_PROXY_ADDRESS");
        }
        if (k == keccak256("tron-testnet")) {
            return vm.envAddress("TRON_OFT_TOKEN_ADDRESS");
        }
        if (k == keccak256("mainnet")) {
            return vm.envAddress("OFT_ADAPTER_PROXY_ADDRESS");
        }
        if (k == keccak256("tron-mainnet")) {
            return vm.envAddress("TRON_OFT_TOKEN_ADDRESS");
        }
        revert("SetupPeersByName: unknown network");
    }
}
