// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.20;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC1155Supply} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title BondNFT
 * @dev An ERC1155 contract representing tokenized bonds with metadata and minting controls.
 * Inherits from OpenZeppelin's ERC1155, Ownable, ERC1155Supply, and ReentrancyGuard contracts.
 */
contract BondNFT is ERC1155, Ownable, ERC1155Supply, ReentrancyGuard {
    /**
     * @dev Struct to hold metadata for each bond type (token ID).
     * @param value The face value or principal amount of the bond.
     * @param couponValue The value of the coupon payment.
     * @param issueTimestamp The timestamp when the bond was issued.
     * @param expirationTimestamp The timestamp when the bond expires or matures.
     * @param ISIN International Securities Identification Number for the bond.
     */
    struct Metadata {
        uint256 value;
        uint256 couponValue;
        uint256 issueTimestamp;
        uint256 expirationTimestamp;
        string ISIN;
    }

    /**
     * @dev Emitted when the mint allowance for a specific user and token ID is set or updated.
     * @param user The address of the user whose allowance is being set.
     * @param id The token ID for which the allowance is being set.
     * @param allowedAmount The new allowed mint amount.
     */
    event MintAllowanceSet(address user, uint256 id, uint256 allowedAmount);

    /**
     * @dev Reverts when a user attempts to mint a token ID they are not allowed to mint (allowance is 0).
     */
    error NftMintingNotAllowed();
    /**
     * @dev Reverts when a user attempts to mint more tokens than their remaining allowance for a specific token ID.
     * @param remaining The number of tokens the user is still allowed to mint.
     */
    error NftMintingLimitExceeded(uint256 remaining);
    /**
     * @dev Reverts when a user attempts to burn more tokens than they own for a specific token ID.
     */
    error NftInsufficientBalanceToBurn();

    /**
     * @dev Mapping from token ID to its Metadata struct.
     */
    mapping(uint256 => Metadata) public metadata;

    /**
     * @dev Mapping to store the allowed mints per user per token ID.
     * `allowedMints[user][id]` returns the total amount of tokens of `id` that `user` is allowed to mint.
     */
    mapping(address => mapping(uint256 => uint256)) public allowedMints;

    /**
     * @dev Mapping to track how many mints have been used per user per token ID.
     * `mintedPerUser[user][id]` returns the amount of tokens of `id` that `user` has already minted.
     */
    mapping(address => mapping(uint256 => uint256)) public mintedPerUser;

    /**
     * @dev The name of the token collection.
     */
    string public name = "BondNFT";
    /**
     * @dev The symbol of the token collection.
     */
    string public symbol = "BNFT";

    /**
     * @dev Contract constructor.
     * @param initialOwner The address that will initially own the contract.
     * @param _uri The base URI for token metadata.
     */
    constructor(address initialOwner, string memory _uri) ERC1155(_uri) Ownable(initialOwner) {}

    /**
     * @dev Sets the base URI for token metadata.
     * Only callable by the owner.
     * @param newuri The new base URI string.
     */
    function setURI(string memory newuri) public onlyOwner {
        _setURI(newuri);
    }

    /**
     * @dev Sets the metadata for a specific token ID.
     * Only callable by the owner.
     * @param id The token ID to set metadata for.
     * @param _metadata The Metadata struct containing the details.
     */
    function setMetaData(uint256 id, Metadata memory _metadata) external onlyOwner {
        metadata[id] = _metadata;
    }

    /**
     * @dev Retrieves the metadata for a specific token ID.
     * @param id The token ID to query metadata for.
     * @return Metadata struct containing the bond details.
     */
    function getMetaData(uint256 id) external view returns (Metadata memory) {
        return metadata[id];
    }

    /**
     * @dev Sets the maximum number of tokens of a specific ID that a user is allowed to mint.
     * Only callable by the owner. Emits a {MintAllowanceSet} event.
     * @param user The address of the user whose allowance is being set.
     * @param id The token ID for which the allowance is being set.
     * @param allowedAmount The total number of tokens the user is allowed to mint for this ID.
     */
    function setAllowedMints(address user, uint256 id, uint256 allowedAmount) external onlyOwner {
        allowedMints[user][id] = allowedAmount;
        emit MintAllowanceSet(user, id, allowedAmount);
    }

    /**
     * @dev Mints a specified `amount` of tokens with `id` to the caller (`msg.sender`).
     * Requires the user to have sufficient minting allowance remaining.
     * Uses `nonReentrant` modifier to prevent reentrancy attacks.
     * Reverts with {NftMintingNotAllowed} if the user's allowance is 0.
     * Reverts with {NftMintingLimitExceeded} if the requested amount exceeds the remaining allowance.
     * Updates the `mintedPerUser` count.
     * @param id The token ID to mint.
     * @param amount The number of tokens to mint.
     * @param data Additional data to pass to the mint function (optional).
     */
    function mint(uint256 id, uint256 amount, bytes memory data) public nonReentrant {
        if (allowedMints[msg.sender][id] == 0) revert NftMintingNotAllowed();
        if (mintedPerUser[msg.sender][id] + amount > allowedMints[msg.sender][id]) {
            revert NftMintingLimitExceeded(allowedMints[msg.sender][id] - mintedPerUser[msg.sender][id]);
        }

        // Track the number of minted tokens per user for the given ID
        mintedPerUser[msg.sender][id] += amount;
        _mint(msg.sender, id, amount, data);
    }

    /**
     * @dev Mints multiple token IDs in a single transaction (batch mint).
     * Requires the user to have sufficient minting allowance for each token ID being minted.
     * Uses `nonReentrant` modifier to prevent reentrancy attacks.
     * Reverts with {NftMintingNotAllowed} if the user's allowance is 0 for any ID.
     * Reverts with {NftMintingLimitExceeded} if the requested amount exceeds the remaining allowance for any ID.
     * Updates the `mintedPerUser` count for each ID.
     * @param ids An array of token IDs to mint.
     * @param amounts An array of corresponding amounts to mint for each ID.
     * @param data Additional data to pass to the batch mint function (optional).
     */
    function mintBatch(uint256[] memory ids, uint256[] memory amounts, bytes memory data) public nonReentrant {
        // Check allowances for all requested mints first
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 id = ids[i];
            uint256 amount = amounts[i];

            // Ensure the user is allowed to mint the specified amount for each token ID
            if (allowedMints[msg.sender][id] == 0) revert NftMintingNotAllowed();
            if (mintedPerUser[msg.sender][id] + amount > allowedMints[msg.sender][id]) {
                revert NftMintingLimitExceeded(allowedMints[msg.sender][id] - mintedPerUser[msg.sender][id]);
            }

            // Update minted count for the user per token ID
            mintedPerUser[msg.sender][id] += amount;
        }

        // Proceed with the batch mint after all checks
        _mintBatch(msg.sender, ids, amounts, data);
    }

    /**
     * @dev Burns a specified `amount` of tokens with `id` owned by the caller (`msg.sender`).
     * Uses `nonReentrant` modifier to prevent reentrancy attacks.
     * Reverts with {NftInsufficientBalanceToBurn} if the caller does not own enough tokens.
     * @param id The token ID to burn.
     * @param amount The number of tokens to burn.
     */
    function burn(uint256 id, uint256 amount) public nonReentrant {
        if (balanceOf(msg.sender, id) < amount) revert NftInsufficientBalanceToBurn();
        // Burn the tokens
        _burn(msg.sender, id, amount);
    }

    /**
     * @dev Hook that is called before any token transfer, including minting and burning.
     * Overrides the function from {ERC1155} and {ERC1155Supply}.
     * @inheritdoc ERC1155Supply
     */
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        override(ERC1155, ERC1155Supply)
    {
        super._update(from, to, ids, values);
    }

    /**
     * @dev View function to get the number of remaining mints allowed for a user per token ID.
     * @param user The address of the user to query.
     * @param id The token ID to query.
     * @return The number of tokens the user can still mint for the specified ID.
     */
    function remainingMints(address user, uint256 id) external view returns (uint256) {
        return allowedMints[user][id] - mintedPerUser[user][id];
    }
}
