// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {StableBondCoins} from "../StableBondCoins.sol";

/**
 * @title StableBondCoinsV2
 * @dev This contract is a test-only version of StableBondCoins, used to simulate and verify the UUPS proxy upgrade process.
 * It extends StableBondCoins with additional functionality for testing and is not intended for production.
 */
/// @custom:oz-upgrades-from StableBondCoins
contract StableBondCoinsV2 is StableBondCoins {
    /// @custom:oz-upgrades-validate-as-initializer
    function initializeV2() external reinitializer(2) {
        __ERC20_init(name(), symbol());
        __ERC20Permit_init(name());
        __AccessControl_init();
        __UUPSUpgradeable_init();
    }

    function newFeature() external pure returns (string memory) {
        return "V2 Feature";
    }

    function getInitializedVersion() external view returns (uint64) {
        return _getInitializedVersion();
    }
}
