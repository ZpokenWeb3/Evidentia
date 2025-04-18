// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.22;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title StableBondCoins
 * @dev An ERC20 token contract with minting and burning capabilities controlled by AccessControl.
 * It also includes ERC20Permit functionality.
 */
contract StableBondCoins is ERC20, AccessControl, ERC20Permit {
    /**
     * @dev Role identifier for minters. Only addresses with this role can mint or burn tokens.
     */
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /**
     * @dev Sets up the contract, assigning initial roles.
     * @param defaultAdmin The address that will be granted the default admin role.
     * @param minter The address that will be granted the minter role.
     */
    constructor(address defaultAdmin, address minter)
        ERC20("Stable Bond Coins", "SBC")
        ERC20Permit("Stable Bond Coins")
    {
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(MINTER_ROLE, minter);
    }

    /**
     * @dev Creates `amount` tokens and assigns them to `to`, increasing the total supply.
     * Emits a {Transfer} event with `from` set to the zero address.
     * Requirements:
     * - The caller must have the `MINTER_ROLE`.
     * @param to The address that will receive the minted tokens.
     * @param amount The amount of tokens to mint.
     */
    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `from`, reducing the total supply.
     * Emits a {Transfer} event with `to` set to the zero address.
     * Requirements:
     * - The caller must have the `MINTER_ROLE`.
     * - `from` cannot be the zero address.
     * - `from` must have at least `amount` tokens.
     * @param from The address whose tokens will be burned.
     * @param amount The amount of tokens to burn.
     */
    function burn(address from, uint256 amount) public onlyRole(MINTER_ROLE) {
        _burn(from, amount);
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * @return The number of decimals (set to 6).
     */
    function decimals() public view virtual override returns (uint8) {
        return 6;
    }
}
