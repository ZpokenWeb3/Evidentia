// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {NFTStakingAndBorrowing} from "../NFTStakingAndBorrowing.sol";

/**
 * @title NFTStakingAndBorrowingV2
 * @dev This contract is a test-only version of NFTStakingAndBorrowing, used to simulate and verify the UUPS proxy upgrade process.
 * It extends NFTStakingAndBorrowing with additional functionality for testing and is not intended for production.
 */
/// @custom:oz-upgrades-from NFTStakingAndBorrowing
contract NFTStakingAndBorrowingV2 is NFTStakingAndBorrowing {
    /// @custom:oz-upgrades-validate-as-initializer
    function initializeV2() external reinitializer(2) {
        __ERC1155Holder_init();
        __Ownable_init(owner());
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
    }

    function initialize() external initializer {
        __ERC1155Holder_init();
        __Ownable_init(owner());
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
    }

    function newFeature() external pure returns (string memory) {
        return "V2 Feature";
    }

    function getInitializedVersion() external view returns (uint64) {
        return _getInitializedVersion();
    }
}
