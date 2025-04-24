# Evidentia Bond-Backed Stablecoin Platform

## Overview

This protocol creates a decentralized finance (DeFi) ecosystem centered around tokenized bonds. It enables users to leverage their bond holdings (represented as NFTs) to access liquidity in the form of stablecoins, while also providing a yield-generating opportunity for stablecoin holders.

## Core Workflow
1. **Tokenize Bonds**  
   Bonds are represented as ERC-1155 NFTs via the `BondNFT` contract, embedding key metadata (value, coupon rate, timestamps, ISIN).
2. **Stake Bonds as Collateral**  
   Users deposit `BondNFT`s into the `NFTStakingAndBorrowing` contract.
3. **Borrow Stablecoins**  
   Against the staked NFTs, users borrow `StableBondCoins` (SBC), a native ERC-20 token. Loans accrue interest over time.
4. **Earn Yield via Staking**  
   SBC holders can stake their tokens in the `StableCoinsStaking` contract to earn rewards from interest revenue.

## Key Features

* **Tokenized Bonds (ERC1155):** Utilizes the `BondNFT` contract (ERC1155 standard) to represent bonds with specific metadata (value, coupon, timestamps, ISIN).
* **Collateralized Debt Position (CDP):** The `NFTStakingAndBorrowing` contract allows users to borrow stablecoins against their staked `BondNFT` collateral.
* **Native Stablecoin (ERC20):** Introduces `StableBondCoins` (SBC), a mintable/burnable ERC20 token with `ERC20Permit`, serving as the primary medium for borrowing.
* **NFT Staking & Borrowing:** Users lock `BondNFT`s to borrow SBC, subject to collateralization ratios and interest rates.
* **Stablecoin Staking & Yield:** The `StableCoinsStaking` contract allows users to stake stablecoins (`SBC` or others) to earn rewards sourced externally.
* **Interest Accrual & Reward Distribution:** Manages loan interest and distributes rewards to participants (borrowers/stakers).
* **Modular Architecture:** Separates functionality into distinct contracts (`BondNFT`, `StableBondCoins`, `NFTStakingAndBorrowing`, `StableCoinsStaking`).
* **Access Control & Security:** Employs `Ownable`, `AccessControl`, and `ReentrancyGuard` for security and administrative control.

## Contracts & Functionality

### `BondNFT` (ERC1155)

* `mint(address to, uint256 id, uint256 amount, bytes data)` / `mintBatch(...)`: Creates new bond NFTs (Owner restricted).
* `burn(uint256 id, uint256 amount)` / `burnBatch(...)`: Destroys owned bond NFTs.
* `setMetadata(uint256 id, uint256 value, uint256 couponValue, uint256 issueTimestamp, uint256 expirationTimestamp, string memory ISIN)`: Updates metadata for a bond ID (Owner restricted).
* `getMetadata(uint256 id)`: Retrieves stored metadata for a bond ID.
* `balanceOf(address account, uint256 id)` / `balanceOfBatch(...)`: Checks token balances.
* `safeTransferFrom(...)` / `safeBatchTransferFrom(...)`: Transfers NFTs.
* `totalSupply(uint256 id)`: Checks the total supply of a specific bond NFT ID.

### `BondNFTV2` (ERC1155, Testing Only)

* **Purpose**: This contract is a test-only version of `BondNFT`, used to simulate and verify the upgrade process for the UUPS proxy. It extends `BondNFT` with additional functionality for testing purposes, such as updating the token name and verifying the implementation version.
* **Key Functions**:
  * `updateName(string memory newName)`: Allows the owner to update the token collection name (for testing state changes after upgrades). 
  * `version()`: Returns `"V2"` to confirm the upgraded implementation is active.
* **Note**: `BondNFTV2` is not intended for production deployment.

### `StableBondCoins` (ERC20)

* `mint(address to, uint256 amount)`: Creates new SBC tokens (Requires `MINTER_ROLE`).
* `burn(address from, uint256 amount)`: Destroys SBC tokens (Requires `MINTER_ROLE`).
* `transfer(address to, uint256 value)` / `transferFrom(...)`: Standard ERC20 token transfers.
* `approve(address spender, uint256 value)`: Standard ERC20 allowance.
* `permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)`: Gasless approvals (EIP-2612).

### `NFTStakingAndBorrowing`

* `stakeNFT(address nftAddress, uint256 tokenId, uint256 amount)`: Deposits `BondNFT`s as collateral.
* `unstakeNFT(address nftAddress, uint256 tokenId, uint256 amount)`: Withdraws staked `BondNFT`s.
* `borrow(uint256 borrowAmount)`: Borrows `StableBondCoins` against collateral.
* `repay(uint256 repayAmount)`: Repays borrowed `StableBondCoins` plus interest.
* `claimRewards()`: Claims rewards generated from borrowing interest.
* `getUserNFTBalance(address user, address nftAddress, uint256 tokenId)`: Checks a user's staked NFT balance.

### `StableCoinsStaking`

* `stake(uint256 _amount)`: Deposits `stakingToken` into the contract.
* `withdraw(uint256 _amount)`: Withdraws staked `stakingToken`.
* `claimRewards()`: Claims accrued rewards earned from staking.
* `earned(address _staker)`: Calculates current unclaimed rewards for a staker.
* `pendingRewards(address _staker)`: Views pending rewards without triggering state changes.

## Development & Testing (Foundry)

This project uses [Foundry](https://book.getfoundry.sh/) for smart contract development and testing.

### Prerequisites

Ensure you have Foundry installed. If not, run:
```bash
curl -L [https://foundry.paradigm.xyz](https://foundry.paradigm.xyz) | bash
foundryup
```

### Foundry Documentation

https://book.getfoundry.sh/

### Add libs

```bash
forge install foundry-rs/forge-std --no-commit
forge install OpenZeppelin/openzeppelin-contracts --no-commit
forge install OpenZeppelin/openzeppelin-foundry-upgrades --no-commit
forge install OpenZeppelin/openzeppelin-contracts-upgradeable --no-commit
```

### Running Tests

To run tests with increased verbosity (showing logs and traces):
```bash
forge test --ffi -vvv
```

### Format

```bash
forge fmt
```

### Gas Snapshots

```bash
forge snapshot
```

### Anvil

```bash
anvil
```
