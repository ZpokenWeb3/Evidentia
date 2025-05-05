// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {StableBondCoins} from "../StableBondCoins.sol";

/**
 * @title StableBondCoinsV2
 * @dev This contract is a test-only version of StableBondCoins, used to simulate and verify the UUPS proxy upgrade process.
 * It extends StableBondCoins with additional functionality for testing and is not intended for production.
 */
/// @custom:oz-upgrades-from StableBondCoins
contract StableBondCoinsV2 is StableBondCoins {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _lzEndpoint) StableBondCoins(_lzEndpoint) {}

    /// @custom:oz-upgrades-validate-as-initializer
    function initializeV2() external reinitializer(2) {
        __OFT_init("Stable Bond Coins", "SBC", owner());
        __ERC20Permit_init("Stable Bond Coins");
        __AccessControl_init();
        __Ownable_init(owner());
        __UUPSUpgradeable_init();
    }

    function newFeature() external pure returns (string memory) {
        return "V2 Feature";
    }

    function getInitializedVersion() external view returns (uint64) {
        return _getInitializedVersion();
    }
}
