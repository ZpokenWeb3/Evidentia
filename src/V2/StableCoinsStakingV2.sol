// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {StableCoinsStaking} from "../StableCoinsStaking.sol";

/// @custom:oz-upgrades-from StableCoinsStaking
/**
 * @title StableCoinsStakingV2
 * @dev This contract is a test-only version of StableCoinsStaking, used to simulate and verify the UUPS proxy upgrade process.
 * It extends StableCoinsStaking with additional functionality for testing and is not intended for production.
 */
contract StableCoinsStakingV2 is StableCoinsStaking {
    function initializeV2() external reinitializer(2) {}

    function newFeature() external pure returns (string memory) {
        return "V2 Feature";
    }

    function getInitializedVersion() external view returns (uint64) {
        return _getInitializedVersion();
    }
}
