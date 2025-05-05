// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.22;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC20PermitUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OFTUpgradeable} from "@layerzerolabs/oft-evm-upgradeable/contracts/oft/OFTUpgradeable.sol";

/**
 * @title StableBondCoins
 * @dev An upgradeable OFT (Omnichain Fungible Token) with minting and burning capabilities controlled by AccessControl.
 * It includes ERC20Permit functionality and uses ERC7201 storage namespace and UUPS proxy pattern for upgradeability.
 */
contract StableBondCoins is OFTUpgradeable, AccessControlUpgradeable, ERC20PermitUpgradeable, UUPSUpgradeable {
    // keccak256(abi.encode(uint256(keccak256("StableBondCoins.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_LOCATION = 0xd617c1a7b49d27159d9fe0ce7de01c7130c8a8bb809755fe8b0df36a2bc07e00;

    /**
     * @dev Role identifier for minters. Only addresses with this role can mint or burn tokens.
     */
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /**
     * @dev Constructor that disables initializers
     * @param _lzEndpoint The LayerZero endpoint address
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _lzEndpoint) OFTUpgradeable(_lzEndpoint) {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract (replaces constructor).
     * @param defaultAdmin The address that will be granted the default admin role.
     * @param minter The address that will be granted the minter role.
     * @param delegate The address that will receive the ownership of the OFT
     */
    function initialize(address defaultAdmin, address minter, address delegate) external initializer {
        __OFT_init("Stable Bond Coins", "SBC", delegate);
        __ERC20Permit_init("Stable Bond Coins");
        __AccessControl_init();
        __Ownable_init(delegate);
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(MINTER_ROLE, minter);
    }

    /**
     * @dev Authorize upgrades (required for UUPS).
     * Only callable by the admin (holder of DEFAULT_ADMIN_ROLE).
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /**
     * @dev Creates `amount` tokens and assigns them to `to`, increasing the total supply.
     * Requirements:
     * - The caller must have the `MINTER_ROLE`.
     */
    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `from`, reducing the total supply.
     * Requirements:
     * - The caller must have the `MINTER_ROLE`.
     * - `from` cannot be the zero address.
     * - `from` must have at least `amount` tokens.
     */
    function burn(address from, uint256 amount) public onlyRole(MINTER_ROLE) {
        _burn(from, amount);
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     */
    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
