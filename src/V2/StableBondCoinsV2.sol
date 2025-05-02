// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {StableBondCoins} from "../StableBondCoins.sol";

/// @custom:oz-upgrades-from StableBondCoins
/**
 * @title StableBondCoinsV2
 * @dev This contract is a test-only version of StableBondCoins, used to simulate and verify the UUPS proxy upgrade process.
 * It extends StableBondCoins with additional functionality for testing and is not intended for production.
 */
contract StableBondCoinsV2 is StableBondCoins {
    constructor(address _lzEndpoint) StableBondCoins(_lzEndpoint) {}

    function initializeV2() external reinitializer(2) {}

    function newFeature() external pure returns (string memory) {
        return "V2 Feature";
    }

    function getInitializedVersion() external view returns (uint64) {
        return _getInitializedVersion();
    }
}
