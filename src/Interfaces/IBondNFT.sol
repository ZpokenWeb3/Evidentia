// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

interface IBondNFT is IERC1155 {
    struct Metadata {
        uint256 value;
        uint256 couponValue;
        uint256 issueTimestamp;
        uint256 expirationTimestamp;
        string ISIN;
    }

    function getMetaData(uint256 id) external view returns (Metadata memory);

    function setURI(string memory newuri) external;

    function setMetaData(uint256 id, Metadata memory _metadata) external;

    function mint(address account, uint256 id, uint256 amount, bytes memory data) external;

    function burn(address account, uint256 id, uint256 amount) external;

    function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data) external;

    function totalSupply(uint256 id) external view returns (uint256);
    function exists(uint256 id) external view returns (bool);
}
