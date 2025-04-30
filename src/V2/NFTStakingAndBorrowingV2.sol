// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {NFTStakingAndBorrowing} from "../NFTStakingAndBorrowing.sol";

/**
 * @title NFTStakingAndBorrowingV2
 * @dev This contract is a test-only version of NFTStakingAndBorrowing, used to simulate and verify the UUPS proxy upgrade process.
 * It extends NFTStakingAndBorrowing with additional functionality for testing and is not intended for production.
 */
contract NFTStakingAndBorrowingV2 is NFTStakingAndBorrowing {
    function initializeV2() external reinitializer(2) {}

    function newFeature() external pure returns (string memory) {
        return "V2 Feature";
    }

    function getInitializedVersion() external view returns (uint64) {
        return _getInitializedVersion();
    }
}
