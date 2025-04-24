// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {BondNFT} from "./BondNFT.sol";

/**
 * @title BondNFTV2
 * @dev This contract is a test-only version of BondNFT, used to simulate and verify the UUPS proxy upgrade process.
 * It extends BondNFT with additional functionality for testing and is not intended for production.
 */
contract BondNFTV2 is BondNFT {
    function updateName(string memory newName) external onlyOwner {
        _getStorage().name = newName;
    }

    function version() external pure returns (string memory) {
        return "V2";
    }
}
