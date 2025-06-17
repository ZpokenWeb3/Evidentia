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
                gracePeriod: 0
            });
        }
        // Ethereum Sepolia
        if (key == keccak256("sepolia")) {
            return ChainConfig({
                eid: 40161,
                endpoint: 0x6EDCE65403992e310A62460808c4b910D972f10f,
                ulnSendLib: 0xcc1ae8Cf5D3904Cef3360A9532B477529b177cCE,
                ulnRecvLib: 0xdAf00F5eE2158dD58E0d3857851c432E34A3A851,
                gracePeriod: 0
            });
        }
        // Ethereum Mainnet
        if (key == keccak256("mainnet")) {
            return ChainConfig({
                eid: 30101,
                endpoint: 0x1a44076050125825900e736c501f859c50fE728c,
                ulnSendLib: 0xbB2Ea70C9E858123480642Cf96acbcCE1372dCe1,
                ulnRecvLib: 0xc02Ab410f0734EFa3F14628780e6e695156024C2,
                gracePeriod: 0
            });
        }
        // Tron Testnet
        if (key == keccak256("tron-testnet")) {
            return ChainConfig({
                eid: 40420,
                endpoint: 0x1b356f3030CE0c1eF9D3e1E250Bf0BB11D81b2d1,
                ulnSendLib: 0xaef63752785Ad2104cea1aa42b69b46f2530312F,
                ulnRecvLib: 0x843810EB9f002E940870a95B366cc59E623bF5f1,
                gracePeriod: 0
            });
        }
        // Tron Mainnet
        if (key == keccak256("tron-mainnet")) {
            return ChainConfig({
                eid: 30420,
                endpoint: 0x0Af59750D5dB5460E5d89E268C474d5F7407c061,
                ulnSendLib: 0xE369D146219380B24Bb5D9B9E08a5b9936F9E719,
                ulnRecvLib: 0x612215D4dB0475a76dCAa36C7f9afD748c42ed2D,
                gracePeriod: 0
            });
        }

        revert("LayerZeroConstants: unsupported chain name");
    }
}
