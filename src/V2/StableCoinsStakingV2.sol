// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {StableCoinsStaking} from "../StableCoinsStaking.sol";

/**
 * @title StableCoinsStakingV2
 * @dev This contract is a test-only version of StableCoinsStaking, used to simulate and verify the UUPS proxy upgrade process.
 * It extends StableCoinsStaking with additional functionality for testing and is not intended for production.
 */
/// @custom:oz-upgrades-from StableCoinsStaking
contract StableCoinsStakingV2 is StableCoinsStaking {
    /// @custom:oz-upgrades-validate-as-initializer
    function initializeV2() external reinitializer(2) {
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        __AccessControl_init();
    }

    function initialize() external initializer {
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        __AccessControl_init();
    }

    function newFeature() external pure returns (string memory) {
        return "V2 Feature";
    }

    function getInitializedVersion() external view returns (uint64) {
        return _getInitializedVersion();
    }
}
