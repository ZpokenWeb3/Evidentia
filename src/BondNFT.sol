// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.20;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC1155Supply} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract BondNFT is ERC1155, Ownable, ERC1155Supply, ReentrancyGuard {
    struct Metadata {
        uint256 value;
        uint256 couponValue;
        uint256 issueTimestamp;
        uint256 expirationTimestamp;
        string ISIN;
    }

    // Custom event
    event MintAllowanceSet(address user, uint256 id, uint256 allowedAmount);

    // Custom errors
    error NftMintingNotAllowed();
    error NftMintingLimitExceeded(uint256);
    error NftInsufficientBalanceToBurn();

    mapping(uint256 => Metadata) public metadata;

    // Mapping to store the allowed mints per user per token ID
    mapping(address => mapping(uint256 => uint256)) public allowedMints;

    // Mapping to track how many mints have been used per user per token ID
    mapping(address => mapping(uint256 => uint256)) public mintedPerUser;

    string public name = "BondNFT";
    string public symbol = "BNFT";

    constructor(address initialOwner, string memory _uri) ERC1155(_uri) Ownable(initialOwner) {}

    function setURI(string memory newuri) public onlyOwner {
        _setURI(newuri);
    }

    function setMetaData(uint256 id, Metadata memory _metadata) external onlyOwner {
        metadata[id] = _metadata;
    }

    function getMetaData(uint256 id) external view returns (Metadata memory) {
        return metadata[id];
    }

    // Function to set allowed mints for a user per token ID
    function setAllowedMints(address user, uint256 id, uint256 allowedAmount) external onlyOwner {
        allowedMints[user][id] = allowedAmount;
        emit MintAllowanceSet(user, id, allowedAmount);
    }

    // Function to mint tokens, ensuring the user has remaining allowed mints
    function mint(uint256 id, uint256 amount, bytes memory data) public nonReentrant {
        if (allowedMints[msg.sender][id] == 0) revert NftMintingNotAllowed();
        if (mintedPerUser[msg.sender][id] + amount > allowedMints[msg.sender][id]) {
            revert NftMintingLimitExceeded(allowedMints[msg.sender][id] - mintedPerUser[msg.sender][id]);
        }

        // Track the number of minted tokens per user for the given ID
        mintedPerUser[msg.sender][id] += amount;

        _mint(msg.sender, id, amount, data);
    }

    // Function to mint multiple tokens in batch, checking allowed mints for each token ID
    function mintBatch(uint256[] memory ids, uint256[] memory amounts, bytes memory data) public nonReentrant {
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

    // Function to burn tokens, ensuring only the token owner can burn
    function burn(uint256 id, uint256 amount) public nonReentrant {
        if (balanceOf(msg.sender, id) < amount) revert NftInsufficientBalanceToBurn();

        // Burn the tokens
        _burn(msg.sender, id, amount);
    }

    // The following functions are overrides required by Solidity.
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        override(ERC1155, ERC1155Supply)
    {
        super._update(from, to, ids, values);
    }

    // View function to get how many mints are remaining for a user per token ID
    function remainingMints(address user, uint256 id) external view returns (uint256) {
        return allowedMints[user][id] - mintedPerUser[user][id];
    }
}
