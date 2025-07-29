// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BondNFT} from "../BondNFT.sol";

/**
 * @title BondNFTV2
 * @dev This contract is a test-only version of BondNFT, used to simulate and verify the UUPS proxy upgrade process.
 * It extends BondNFT with additional functionality for testing and is not intended for production.
 */
/// @custom:oz-upgrades-from BondNFT
contract BondNFTV2 is BondNFT {
    /// @custom:oz-upgrades-validate-as-initializer
    function initializeV2() external reinitializer(2) {
        __ERC1155_init(uri(0));
        __Ownable_init(owner());
        __ERC1155Supply_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
    }

    function initialize() external initializer {
        __ERC1155_init(uri(0));
        __Ownable_init(owner());
        __ERC1155Supply_init();
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
