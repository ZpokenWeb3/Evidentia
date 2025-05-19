// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.30;

import {OFTAdapterUpgradeable} from "@layerzerolabs/oft-evm-upgradeable/contracts/oft/OFTAdapterUpgradeable.sol";

/**
 * @title StableOFTAdapter
 * @dev An upgradeable OFT (Omnichain Fungible Token) adapter contract that enables cross-chain
 * functionality for an existing ERC20 token.
 *
 * This adapter allows the token to be transferred across different blockchains using LayerZero's
 * cross-chain messaging protocol.
 */
contract StableOFTAdapter is OFTAdapterUpgradeable {
    /**
     * @dev Constructor that disables initializers
     * @param _token The address of the ERC20 token to adapt
     * @param _lzEndpoint The LayerZero endpoint address
     */
    constructor(address _token, address _lzEndpoint) OFTAdapterUpgradeable(_token, _lzEndpoint) {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract.
     * @param defaultAdmin The address that will be granted the admin role.
     */
    function initialize(address defaultAdmin) public initializer {
        __Ownable_init(defaultAdmin);
        __OAppCore_init(defaultAdmin);
        __OFTCore_init_unchained();
        __OFTAdapter_init_unchained();
    }
}
