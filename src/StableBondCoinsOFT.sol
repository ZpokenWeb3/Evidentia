// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.23;

import {OFTUpgradeable} from "@layerzerolabs/oft-evm-upgradeable/contracts/oft/OFTUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC20PermitUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title StableBondCoinsOFT
 * @dev An upgradeable OFT (Omnichain Fungible Token) contract with minting and burning capabilities controlled by AccessControl.
 * It includes ERC20Permit functionality and uses the UUPS proxy pattern for upgradeability.
 */
contract StableBondCoinsOFT is OFTUpgradeable, AccessControlUpgradeable, ERC20PermitUpgradeable, UUPSUpgradeable {
    /**
     * @dev Role identifier for minters. Only addresses with this role can mint or burn tokens.
     */
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /**
     * @dev Constructor that disables initializers
     * @param _lzEndpoint The LayerZero endpoint address
     */
    constructor(address _lzEndpoint) OFTUpgradeable(_lzEndpoint) {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract (replaces constructor).
     * @param defaultAdmin The address that will be granted the default admin role.
     * @param minter The address that will be granted the minter role.
     * @param name The name of the token.
     * @param symbol The symbol of the token.
     */
    function initialize(address defaultAdmin, address minter, string memory name, string memory symbol)
        external
        initializer
    {
        __OFT_init(name, symbol, defaultAdmin);
        __Ownable_init(defaultAdmin);
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ERC20Permit_init(name);
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(MINTER_ROLE, minter);
    }

    /**
     * @dev Authorizes upgrades (required for UUPS).
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
    function decimals() public view virtual override returns (uint8) {
        return 6;
    }
}
