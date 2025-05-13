// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.30;

import {ERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC1155SupplyUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title BondNFT
 * @dev An upgradeable ERC1155 contract representing tokenized bonds with metadata and minting controls.
 * Inherits from OpenZeppelin's upgradeable ERC1155, Ownable, ERC1155Supply, and ReentrancyGuard contracts.
 */
contract BondNFT is
    Initializable,
    ERC1155Upgradeable,
    OwnableUpgradeable,
    ERC1155SupplyUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    // keccak256(abi.encode(uint256(keccak256("BondNFT.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_LOCATION = 0xffef8b0e9aa2c483e819ac9d28d3b5f004d7e8fbb6ec97cdc9221e749673c000;

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
     * @dev Storage struct for ERC7201 namespace.
     */
    /// @custom:storage-location erc7201:BondNFT.storage
    struct BondNFTStorage {
        /**
         * @dev Mapping from token ID to its Metadata struct.
         */
        mapping(uint256 => Metadata) metadata;
        /**
         * @dev Mapping to store the allowed mints per user per token ID.
         * `allowedMints[user][id]` returns the total amount of tokens of `id` that `user` is allowed to mint.
         */
        mapping(address => mapping(uint256 => uint256)) allowedMints;
        /**
         * @dev Mapping to track how many mints have been used per user per token ID.
         * `mintedPerUser[user][id]` returns the amount of tokens of `id` that `user` has already minted.
         */
        mapping(address => mapping(uint256 => uint256)) mintedPerUser;
        /**
         * @dev The name of the token collection.
         */
        string name;
        /**
         * @dev The symbol of the token collection.
         */
        string symbol;
    }

    /**
     * @dev Retrieves the storage slot for the contract.
     */
    function _getBondNFTStorage() internal pure returns (BondNFTStorage storage $) {
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }

    /**
     * @dev Emitted when the mint allowance for a specific user and token ID is set or updated.
     * @param user The address of the user whose allowance is being set.
     * @param id The token ID for which the allowance is being set.
     * @param allowedAmount The new allowed mint amount.
     */
    event MintAllowanceSet(address user, uint256 id, uint256 allowedAmount);

    /**
     * @dev Emitted when the metadata for a specific token ID is updated.
     * @param id The token ID for which the metadata is being updated.
     * @param value The face value or principal amount of the bond.
     * @param couponValue The value of the coupon payment.
     * @param issueTimestamp The timestamp when the bond was issued.
     * @param expirationTimestamp The timestamp when the bond expires or matures.
     * @param ISIN International Securities Identification Number for the bond.
     */
    event MetadataUpdated(
        uint256 id, uint256 value, uint256 couponValue, uint256 issueTimestamp, uint256 expirationTimestamp, string ISIN
    );

    /**
     * @dev Reverts when a user attempts to mint a token ID they are not allowed to mint (allowance is 0).
     */
    error NftMintingNotAllowed();
    /**
     * @dev Reverts when a user attempts to mint more tokens than their remaining allowance.
     * @param remaining The number of tokens the user is still allowed to mint.
     */
    error NftMintingLimitExceeded(uint256 remaining);
    /**
     * @dev Reverts when a user attempts to burn more tokens than they own.
     */
    error NftInsufficientBalanceToBurn();

    /**
     * @dev Initializes the contract. Replaces constructor for upgradeable contracts.
     * @param initialOwner The address that will initially own the contract.
     * @param _uri The base URI for token metadata.
     */
    function initialize(address initialOwner, string memory _uri) external initializer {
        __ERC1155_init(_uri);
        __Ownable_init(initialOwner);
        __ERC1155Supply_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        BondNFTStorage storage $ = _getBondNFTStorage();
        $.name = "BondNFT";
        $.symbol = "BNFT";
    }

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
        BondNFTStorage storage $ = _getBondNFTStorage();
        $.metadata[id] = _metadata;
        emit MetadataUpdated(
            id,
            _metadata.value,
            _metadata.couponValue,
            _metadata.issueTimestamp,
            _metadata.expirationTimestamp,
            _metadata.ISIN
        );
    }

    /**
     * @dev Retrieves the metadata for a specific token ID.
     * @param id The token ID to query metadata for.
     * @return Metadata struct containing the bond details.
     */
    function getMetaData(uint256 id) external view returns (Metadata memory) {
        BondNFTStorage storage $ = _getBondNFTStorage();
        return $.metadata[id];
    }

    /**
     * @dev Sets the maximum number of tokens of a specific ID that a user is allowed to mint.
     * Only callable by the owner. Emits a {MintAllowanceSet} event.
     * @param user The address of the user whose allowance is being set.
     * @param id The token ID for which the allowance is being set.
     * @param allowedAmount The total number of tokens the user is allowed to mint for this ID.
     */
    function setAllowedMints(address user, uint256 id, uint256 allowedAmount) external onlyOwner {
        BondNFTStorage storage $ = _getBondNFTStorage();
        $.allowedMints[user][id] = allowedAmount;
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
        BondNFTStorage storage $ = _getBondNFTStorage();
        if ($.allowedMints[msg.sender][id] == 0) revert NftMintingNotAllowed();
        if ($.mintedPerUser[msg.sender][id] + amount > $.allowedMints[msg.sender][id]) {
            revert NftMintingLimitExceeded($.allowedMints[msg.sender][id] - $.mintedPerUser[msg.sender][id]);
        }

        // Track the number of minted tokens per user for the given ID
        $.mintedPerUser[msg.sender][id] += amount;
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
        BondNFTStorage storage $ = _getBondNFTStorage();
        // Check allowances for all requested mints first
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 id = ids[i];
            uint256 amount = amounts[i];

            // Ensure the user is allowed to mint the specified amount for each token ID
            if ($.allowedMints[msg.sender][id] == 0) revert NftMintingNotAllowed();
            if ($.mintedPerUser[msg.sender][id] + amount > $.allowedMints[msg.sender][id]) {
                revert NftMintingLimitExceeded($.allowedMints[msg.sender][id] - $.mintedPerUser[msg.sender][id]);
            }

            // Update minted count for the user per token ID
            $.mintedPerUser[msg.sender][id] += amount;
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
     * @dev Authorizes an upgrade to a new implementation contract address. Only callable by the contract owner.
     * @param newImplementation The address of the new implementation contract.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev Hook called before any token transfer, including minting and burning.
     * Overrides the function from {ERC1155Upgradeable} and {ERC1155SupplyUpgradeable}.
     * @inheritdoc ERC1155SupplyUpgradeable
     */
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        override(ERC1155Upgradeable, ERC1155SupplyUpgradeable)
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
        BondNFTStorage storage $ = _getBondNFTStorage();
        return $.allowedMints[user][id] - $.mintedPerUser[user][id];
    }

    /**
     * @dev Retrieves the total number of tokens of a specific ID that a user is allowed to mint.
     * @param user The address of the user to query.
     * @param id The token ID to query.
     * @return The total number of tokens the user is allowed to mint for the specified ID.
     */
    function allowedMints(address user, uint256 id) external view returns (uint256) {
        BondNFTStorage storage $ = _getBondNFTStorage();
        return $.allowedMints[user][id];
    }

    /**
     * @dev Returns the name of the token collection.
     */
    function name() external view returns (string memory) {
        BondNFTStorage storage $ = _getBondNFTStorage();
        return $.name;
    }

    /**
     * @dev Returns the symbol of the token collection.
     */
    function symbol() external view returns (string memory) {
        BondNFTStorage storage $ = _getBondNFTStorage();
        return $.symbol;
    }
}
