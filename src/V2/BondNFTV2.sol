// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {BondNFT} from "../BondNFT.sol";

/// @custom:oz-upgrades-from BondNFT
/**
 * @title BondNFTV2
 * @dev This contract is a test-only version of BondNFT, used to simulate and verify the UUPS proxy upgrade process.
 * It extends BondNFT with additional functionality for testing and is not intended for production.
 */
contract BondNFTV2 is BondNFT {
    function initializeV2() external reinitializer(2) {}

    function newFeature() external pure returns (string memory) {
        return "V2 Feature";
    }

    function getInitializedVersion() external view returns (uint64) {
        return _getInitializedVersion();
    }
}
