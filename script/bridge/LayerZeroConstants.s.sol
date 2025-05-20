// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/// @title LayerZero per‐chain configs by name
library LayerZeroConstants {
    struct ChainConfig {
        uint32 eid;
        address endpoint;
        address ulnSendLib;
        address ulnRecvLib;
        uint16 gracePeriod;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Hard‐coded chain configs
    // ─────────────────────────────────────────────────────────────────────────────
    function getChainConfigByName(string memory name) internal pure returns (ChainConfig memory) {
        bytes32 key = keccak256(bytes(name));

        // Fuji (Avalanche Testnet)
        if (key == keccak256("fuji")) {
            return ChainConfig({
                eid: 40106,
                endpoint: 0x6EDCE65403992e310A62460808c4b910D972f10f,
                ulnSendLib: 0x69BF5f48d2072DfeBc670A1D19dff91D0F4E8170,
                ulnRecvLib: 0x819F0FAF2cb1Fba15b9cB24c9A2BDaDb0f895daf,
                gracePeriod: 50
            });
        }
        // Ethereum Sepolia
        if (key == keccak256("sepolia")) {
            return ChainConfig({
                eid: 40161,
                endpoint: 0x6EDCE65403992e310A62460808c4b910D972f10f,
                ulnSendLib: 0xcc1ae8Cf5D3904Cef3360A9532B477529b177cCE,
                ulnRecvLib: 0xdAf00F5eE2158dD58E0d3857851c432E34A3A851,
                gracePeriod: 50
            });
        }
        // Tron Testnet
        if (key == keccak256("tron-testnet")) {
            return ChainConfig({
                eid: 40420,
                endpoint: 0x1b356f3030CE0c1eF9D3e1E250Bf0BB11D81b2d1,
                ulnSendLib: 0xaef63752785Ad2104cea1aa42b69b46f2530312F,
                ulnRecvLib: 0x843810EB9f002E940870a95B366cc59E623bF5f1,
                gracePeriod: 50
            });
        }

        revert("LayerZeroConstants: unsupported chain name");
    }
}
