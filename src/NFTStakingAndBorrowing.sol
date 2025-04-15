// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {IBondNFT} from "./Interfaces/IBondNFT.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {UD60x18, ud} from "@prb/math/src/UD60x18.sol";
import {IStableCoinsStaking} from "./Interfaces/IStableCoinsStaking.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IMintableERC20 is IERC20 {
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
}

/**
 * @title NFTStakingAndBorrowing
 * @notice This contract allows users to stake NFTs and borrow stable tokens against them.
 * @dev This contract is designed to work with the BondNFT contract and the StableBondCoins contract with minter role.
 */
contract NFTStakingAndBorrowing is ERC1155Holder, Ownable, ReentrancyGuard {
    struct TotalStats {
        uint256 staked;
        uint256 borrowed;
        uint256 debt;
        uint256 debtUpdateTimestamp;
    }

    struct UserStats {
        uint256 staked;
        uint256 nominalAvailable;
        uint256 borrowed;
        uint256 debt;
        uint256 debtUpdateTimestamp;
    }

    TotalStats internal totalStats;

    mapping(address => bool) public whitelistedNFTs;
    mapping(address => UserStats) internal userStats;
    mapping(address => mapping(address => mapping(uint256 => uint256))) public userNFTs;

    uint256 internal constant YEAR_IN_SECONDS = 31536000;
    uint256 internal constant UNIT = 1e18;
    uint256 internal constant BPS = 1e4;
    uint256 public protocolYield = 1200 * UNIT / BPS;
    uint256 public safetyFee = 500 * UNIT / BPS;
    uint256 public liquidationTimeWindow = 45 days;
    uint256 public RewardsTransfered;
    address public stablesStakingAddress;

    IMintableERC20 public stableToken;

    event NFTStaked(address indexed user, address indexed nftAddress, uint256 tokenId, uint256 amount);
    event NFTUnstaked(address indexed user, address indexed nftAddress, uint256 tokenId, uint256 amount);
    event Borrowed(address indexed user, uint256 amount);
    event Repaid(address indexed user, uint256 amount);
    event Liquidated(
        address indexed user, address liquidator, address indexed nftAddress, uint256 tokenId, uint256 amount
    );
    event StablesStakingAddressUpdated(address indexed oldAddress, address indexed newAddress);

    // Custom errors
    error NFTNotWhitelisted();
    error InsufficientNFTBalance();
    error BorrowAmountExceedsLimit(uint256);
    error InsufficientBalanceToRepay();
    error NotEnoughCollateral(uint256);
    error TooEarlyToLiquidate();
    error OnlyStableStakingContract();
    error ZeroAddress();

    constructor(address _stableToken) ERC1155Holder() Ownable(msg.sender) {
        stableToken = IMintableERC20(_stableToken);
    }

    modifier onlyStablesStaking() {
        if (msg.sender != stablesStakingAddress) revert OnlyStableStakingContract();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function whitelistNFT(address nftAddress, bool status) external onlyOwner {
        whitelistedNFTs[nftAddress] = status;
    }

    function setProtocolYield(uint256 _protocolYieldInBPS) external onlyOwner {
        protocolYield = _protocolYieldInBPS * UNIT / BPS;
    }

    function setSafetyFee(uint256 _safetyFeeInBPS) external onlyOwner {
        safetyFee = _safetyFeeInBPS * UNIT / BPS;
    }

    function setLiquidationTimeWindow(uint256 _timeWindowInSeconds) external onlyOwner {
        liquidationTimeWindow = _timeWindowInSeconds;
    }

    function setStablesStakingAddress(address _address) external onlyOwner {
        if (_address == address(0)) revert ZeroAddress();
        address oldAddress = stablesStakingAddress;
        stablesStakingAddress = _address;
        emit StablesStakingAddressUpdated(oldAddress, stablesStakingAddress);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getUserStats(address userAddress) public view returns (UserStats memory) {
        if (userStats[userAddress].debtUpdateTimestamp == block.timestamp) {
            return userStats[userAddress];
        }
        uint256 updatedDebt = 0;
        if (userStats[userAddress].debt != 0) {
            updatedDebt =
                calculateDebt(userStats[userAddress].debt, userStats[userAddress].debtUpdateTimestamp, block.timestamp);
        }
        uint256 updatedNominalAvailable = calculateDebt(
            userStats[userAddress].nominalAvailable, userStats[userAddress].debtUpdateTimestamp, block.timestamp
        );
        UserStats memory updatedUserStats = UserStats(
            userStats[userAddress].staked,
            updatedNominalAvailable,
            userStats[userAddress].borrowed,
            updatedDebt,
            block.timestamp
        );
        return updatedUserStats;
    }

    function getTotalStats() public view returns (TotalStats memory) {
        if (totalStats.debtUpdateTimestamp == block.timestamp) {
            return totalStats;
        }
        uint256 updatedDebt = 0;
        if (totalStats.debt != 0) {
            updatedDebt = calculateDebt(totalStats.debt, totalStats.debtUpdateTimestamp, block.timestamp);
        }

        TotalStats memory updatedTotalStats =
            TotalStats(totalStats.staked, totalStats.borrowed, updatedDebt, block.timestamp);
        return updatedTotalStats;
    }

    function calculateMaxBorrow(uint256 totalAmount, uint256 fromTime, uint256 toTime) public view returns (uint256) {
        totalAmount = totalAmount * UNIT;
        UD60x18 timeDelta = ud(toTime - fromTime);
        UD60x18 maxBorrowLog2 =
            ud(totalAmount).log2() - (timeDelta / ud(YEAR_IN_SECONDS)) * (ud(UNIT + protocolYield)).log2();

        return maxBorrowLog2.exp2().intoUint256() / UNIT;
    }

    function calculateDebt(uint256 borrowedAmount, uint256 fromTime, uint256 toTime) public view returns (uint256) {
        borrowedAmount = borrowedAmount * UNIT;
        UD60x18 timeDelta = ud(toTime - fromTime);
        UD60x18 debtLog2 =
            (timeDelta / ud(YEAR_IN_SECONDS)) * (ud(UNIT + protocolYield)).log2() + ud(borrowedAmount).log2();
        return debtLog2.exp2().intoUint256() / UNIT;
    }

    function userAvailableToBorrow(address userAddress) public view returns (uint256) {
        if (userStats[userAddress].nominalAvailable == 0) return 0;

        uint256 nominalAvailable = calculateDebt(
            userStats[userAddress].nominalAvailable, userStats[userAddress].debtUpdateTimestamp, block.timestamp
        );
        if (userStats[userAddress].debt == 0) {
            return nominalAvailable;
        } else {
            uint256 debt =
                calculateDebt(userStats[userAddress].debt, userStats[userAddress].debtUpdateTimestamp, block.timestamp);
            return nominalAvailable - debt;
        }
    }

    function userAvailableToUnstake(address userAddress, address nftAddress, uint256 tokenId)
        public
        view
        returns (uint256)
    {
        uint256 amount = userNFTs[userAddress][nftAddress][tokenId];

        if (amount == 0) {
            return 0;
        }

        IBondNFT.Metadata memory metadata = IBondNFT(nftAddress).getMetaData(tokenId);
        uint256 unstakeValue = (metadata.value + metadata.couponValue) * (UNIT - safetyFee) / UNIT;

        UserStats memory updatedUserStats = getUserStats(userAddress);

        if (updatedUserStats.nominalAvailable <= updatedUserStats.debt) {
            return 0;
        }

        if (updatedUserStats.debt == 0) {
            return amount;
        }

        uint256 availableToUnstake = (updatedUserStats.nominalAvailable - updatedUserStats.debt)
            / calculateMaxBorrow(unstakeValue, block.timestamp, metadata.expirationTimestamp);

        if (amount > availableToUnstake) {
            return availableToUnstake;
        } else {
            return amount;
        }
    }

    /*//////////////////////////////////////////////////////////////
                            MAIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allows a user to stake an NFT in the contract.
     * @dev This function transfers the NFT to the contract and updates the user's balance.
     * @dev NFT are not locked in the contract.
     * @dev Stable coins are preminted in the contract when the NFT is staked.
     * @param nftAddress The address of the NFT contract.
     * @param tokenId The ID of the NFT to stake.
     * @param amount The amount of NFTs to stake.
     */
    function stakeNFT(address nftAddress, uint256 tokenId, uint256 amount) public nonReentrant {
        _stakeNFT(nftAddress, tokenId, amount);
    }

    /**
     * @notice Internal function to process stake NFT
     */
    function _stakeNFT(address nftAddress, uint256 tokenId, uint256 amount) internal {
        if (!whitelistedNFTs[nftAddress]) revert NFTNotWhitelisted();
        if (IBondNFT(nftAddress).balanceOf(msg.sender, tokenId) < amount) revert InsufficientNFTBalance();

        IBondNFT.Metadata memory metadata = IBondNFT(nftAddress).getMetaData(tokenId);

        uint256 totalValue = (metadata.value + metadata.couponValue) * amount * (UNIT - safetyFee) / UNIT;

        userNFTs[msg.sender][nftAddress][tokenId] += amount;
        totalStats.staked += totalValue;
        userStats[msg.sender].staked += totalValue;
        userStats[msg.sender].nominalAvailable +=
            calculateMaxBorrow(totalValue, block.timestamp, metadata.expirationTimestamp);
        userStats[msg.sender].debtUpdateTimestamp = block.timestamp;

        IBondNFT(nftAddress).safeTransferFrom(msg.sender, address(this), tokenId, amount, "");
        stableToken.mint(address(this), totalValue);

        emit NFTStaked(msg.sender, nftAddress, tokenId, amount);
    }

    /**
     * @notice Allows a user to stake an NFT and stake stable coins simultaneously.
     * @dev This function transfers the NFT to the contract, borrows the stable coins, and stakes the stable coins.
     * @dev NFT are not locked in the contract.
     * @dev Stable coins are borrowed at the same time and staked in the Stables Staking contract.
     * @param nftAddress The address of the NFT contract.
     * @param tokenId The ID of the NFT to stake.
     * @param amountNft The amount of NFTs to stake.
     */
    function stakeNFTandStables(address nftAddress, uint256 tokenId, uint256 amountNft) external nonReentrant {
        _stakeNFT(nftAddress, tokenId, amountNft);
        updateUserDebtAndAvailable(msg.sender);
        updateTotalDebt();
        uint256 amount_to_stake = userStats[msg.sender].nominalAvailable - userStats[msg.sender].debt;

        _borrow(amount_to_stake, msg.sender);

        stableToken.approve(stablesStakingAddress, amount_to_stake);
        IStableCoinsStaking(stablesStakingAddress).stakeOnBehalfOf(amount_to_stake, msg.sender);
    }

    /**
     * @notice Allows a user to borrow and stake stable coins simultaneously.
     * @dev This function borrows the stable coins, and stakes the stable coins.
     * @dev 0 is all available stable coins to borrow.
     * @param amount_to_stake The amount of stables to stake.
     */
    function stakeStables(uint256 amount_to_stake) external nonReentrant {
        updateUserDebtAndAvailable(msg.sender);
        updateTotalDebt();
        uint256 max_borrow = userStats[msg.sender].nominalAvailable - userStats[msg.sender].debt;
        if (amount_to_stake == 0) {
            amount_to_stake = max_borrow;
        }
        if (amount_to_stake > max_borrow) {
            revert BorrowAmountExceedsLimit(max_borrow);
        }

        _borrow(amount_to_stake, msg.sender);

        stableToken.approve(stablesStakingAddress, amount_to_stake);
        IStableCoinsStaking(stablesStakingAddress).stakeOnBehalfOf(amount_to_stake, msg.sender);
    }

    /**
     * @notice Allows a user to unstake an NFT from the contract.
     * @dev This function transfers the NFT back to the user and updates the user's balance.
     * @dev User should have enough NFT balance left as a collateral.
     * @param nftAddress The address of the NFT contract.
     * @param tokenId The ID of the NFT to unstake.
     * @param amount The amount of NFTs to unstake.
     */
    function unstakeNFT(address nftAddress, uint256 tokenId, uint256 amount) external nonReentrant {
        if (!whitelistedNFTs[nftAddress]) revert NFTNotWhitelisted();
        // Only NFT owner can unstake anytime
        if (userNFTs[msg.sender][nftAddress][tokenId] < amount) revert InsufficientNFTBalance();

        IBondNFT.Metadata memory metadata = IBondNFT(nftAddress).getMetaData(tokenId);
        uint256 totalUnstakeValue = (metadata.value + metadata.couponValue) * amount * (UNIT - safetyFee) / UNIT;

        updateUserDebtAndAvailable(msg.sender);
        updateTotalDebt();

        // Check if user has enough collateral
        if (
            userStats[msg.sender].debt > 0
                && calculateMaxBorrow(totalUnstakeValue, block.timestamp, metadata.expirationTimestamp)
                    > userStats[msg.sender].nominalAvailable - userStats[msg.sender].debt
        ) {
            revert NotEnoughCollateral(userStats[msg.sender].nominalAvailable - userStats[msg.sender].debt);
        }

        userNFTs[msg.sender][nftAddress][tokenId] -= amount;

        userStats[msg.sender].staked -= totalUnstakeValue;
        if (
            userStats[msg.sender].nominalAvailable
                > calculateMaxBorrow(totalUnstakeValue, block.timestamp, metadata.expirationTimestamp)
        ) {
            userStats[msg.sender].nominalAvailable -=
                calculateMaxBorrow(totalUnstakeValue, block.timestamp, metadata.expirationTimestamp);
        } else {
            userStats[msg.sender].nominalAvailable = 0;
        }

        totalStats.staked -= totalUnstakeValue;

        IBondNFT(nftAddress).safeTransferFrom(address(this), msg.sender, tokenId, amount, "");

        stableToken.burn(address(this), totalUnstakeValue);

        emit NFTUnstaked(msg.sender, nftAddress, tokenId, amount);
    }

    /**
     * @notice Allows a user to borrow stable tokens against their staked NFTs.
     * @dev This function checks if the user has sufficient NFT balance,
     * @dev if the NFT is whitelisted, and if the user's debt is within the allowed limit.
     * @param amount The amount of stable tokens to borrow. 0 means full available amount.
     */
    function borrow(uint256 amount) public nonReentrant {
        updateUserDebtAndAvailable(msg.sender);
        updateTotalDebt();
        uint256 max_borrow = userStats[msg.sender].nominalAvailable - userStats[msg.sender].debt;
        if (amount == 0) {
            amount = max_borrow;
        }

        if (amount > max_borrow) {
            revert BorrowAmountExceedsLimit(max_borrow);
        }

        _borrow(amount, msg.sender);

        stableToken.transfer(msg.sender, amount);
    }

    /**
     * @notice Internal function to process borrow
     * @dev Has no transfer
     * @param amount The amount of stable tokens to borrow.
     * @param user_address The address of the user
     */
    function _borrow(uint256 amount, address user_address) internal {
        userStats[user_address].debt += amount;
        userStats[user_address].borrowed += amount;
        totalStats.borrowed += amount;
        totalStats.debt += amount;

        emit Borrowed(user_address, amount);
    }

    function updateUserDebtAndAvailable(address userAddress) internal {
        if (userStats[userAddress].debtUpdateTimestamp == block.timestamp) return;

        if (userStats[userAddress].debt != 0) {
            userStats[userAddress].debt =
                calculateDebt(userStats[userAddress].debt, userStats[userAddress].debtUpdateTimestamp, block.timestamp);
        }
        if (userStats[userAddress].nominalAvailable != 0) {
            userStats[userAddress].nominalAvailable = calculateDebt(
                userStats[userAddress].nominalAvailable, userStats[userAddress].debtUpdateTimestamp, block.timestamp
            );
        }
        userStats[userAddress].debtUpdateTimestamp = block.timestamp;
    }

    function updateTotalDebt() internal {
        if (totalStats.debtUpdateTimestamp == block.timestamp) return;

        if (totalStats.debt != 0) {
            totalStats.debt = calculateDebt(totalStats.debt, totalStats.debtUpdateTimestamp, block.timestamp);
        }
        totalStats.debtUpdateTimestamp = block.timestamp;
    }

    /**
     * @notice Allows a user to repay their debt.
     * @dev This function transfers the repayment amount from the user's wallet to the contract.
     * @param amount The amount to repay. 0 for full debt.
     */
    function repay(uint256 amount) external nonReentrant {
        updateUserDebtAndAvailable(msg.sender);
        updateTotalDebt();

        if (amount == 0) amount = userStats[msg.sender].debt;

        if (stableToken.balanceOf(msg.sender) < amount) revert InsufficientBalanceToRepay();

        userStats[msg.sender].debt -= amount;
        if (userStats[msg.sender].borrowed > amount) {
            userStats[msg.sender].borrowed -= amount;
        } else {
            userStats[msg.sender].borrowed = 0;
        }

        totalStats.debt -= amount;
        if (totalStats.borrowed > amount) {
            totalStats.borrowed -= amount;
        } else {
            totalStats.borrowed = 0;
        }

        stableToken.transferFrom(msg.sender, address(this), amount);

        emit Repaid(msg.sender, amount);
    }

    /**
     * @notice Allows a liquidator to liquidate a user's NFT position.
     * @dev This function checks if the NFT is whitelisted, if the user has sufficient NFT balance, and if current timestamp is within the liquidation time window.
     * @param nftAddress The address of the NFT contract.
     * @param tokenId The ID of the NFT to liquidate in the position.
     * @param positionOwner The address of the user who owns the NFT position.
     */
    function liquidate(address nftAddress, uint256 tokenId, address positionOwner) external nonReentrant {
        if (!whitelistedNFTs[nftAddress]) revert NFTNotWhitelisted();
        if (userNFTs[positionOwner][nftAddress][tokenId] == 0) revert InsufficientNFTBalance();
        IBondNFT.Metadata memory metadata = IBondNFT(nftAddress).getMetaData(tokenId);
        if (block.timestamp < metadata.expirationTimestamp - liquidationTimeWindow) revert TooEarlyToLiquidate();

        uint256 amount = userNFTs[positionOwner][nftAddress][tokenId];

        uint256 positionValue = (metadata.value + metadata.couponValue) * amount * (UNIT - safetyFee) / UNIT;
        uint256 maxPositionBorrow = calculateMaxBorrow(positionValue, block.timestamp, metadata.expirationTimestamp);

        updateUserDebtAndAvailable(positionOwner);
        updateTotalDebt();

        // Case 1: Position has no debt - all NFTs return to the position owner
        //         Liquidator does not pay any debt only for transaction fee
        if (userStats[positionOwner].debt == 0) {
            // Update NFT balance and staked values
            userNFTs[positionOwner][nftAddress][tokenId] = 0;
            userStats[positionOwner].staked -= positionValue;
            totalStats.staked -= positionValue;

            IBondNFT(nftAddress).safeTransferFrom(address(this), positionOwner, tokenId, amount, "");
            stableToken.burn(address(this), positionValue);

            emit NFTUnstaked(positionOwner, nftAddress, tokenId, amount);
            return;
        }

        // Case 2: Position has debt greater than max borrow at this point - all NFTs go to the liquidator
        //         Liquidator pays part of the debt equivalent to max borrow at this point
        if (userStats[positionOwner].debt >= maxPositionBorrow) {
            // Intentional deviation from checks-effects-interactions pattern:
            // Transfer called before state changes for atomicity reasons
            stableToken.transferFrom(msg.sender, address(this), maxPositionBorrow);

            userNFTs[positionOwner][nftAddress][tokenId] = 0;
            userStats[positionOwner].staked -= positionValue;
            totalStats.staked -= positionValue;
            userStats[positionOwner].debt -= maxPositionBorrow;
            totalStats.debt -= maxPositionBorrow;

            IBondNFT(nftAddress).safeTransferFrom(address(this), msg.sender, tokenId, amount, "");
            stableToken.burn(address(this), positionValue);

            emit Liquidated(positionOwner, msg.sender, nftAddress, tokenId, amount);
        } else {
            // Case 3: Position has debt less than max borrow at this point - part or all of NFTs goes to the liquidator
            //         Liquidator pays (maxBorrow - debt) to the position owner
            //         Liquidator pays full the debt
            uint256 amountToLiquidate = amount * userStats[positionOwner].debt / maxPositionBorrow
                + (amount * userStats[positionOwner].debt % maxPositionBorrow == 0 ? 0 : 1);
            uint256 liquidationPayment = calculateMaxBorrow(
                (metadata.value + metadata.couponValue) * amountToLiquidate * (UNIT - safetyFee) / UNIT,
                block.timestamp,
                metadata.expirationTimestamp
            );
            // Intentional deviation from checks-effects-interactions pattern:
            // Transfer called before state changes for atomicity reasons
            stableToken.transferFrom(msg.sender, address(this), liquidationPayment);

            uint256 currentDebt = userStats[positionOwner].debt;
            userNFTs[positionOwner][nftAddress][tokenId] = amount - amountToLiquidate;
            uint256 liquidatedValue =
                (metadata.value + metadata.couponValue) * amountToLiquidate * (UNIT - safetyFee) / UNIT;
            userStats[positionOwner].staked -= liquidatedValue;
            totalStats.staked -= liquidatedValue;
            userStats[positionOwner].debt = 0;
            totalStats.debt -= currentDebt;

            stableToken.transfer(positionOwner, liquidationPayment - currentDebt);
            IBondNFT(nftAddress).safeTransferFrom(address(this), msg.sender, tokenId, amountToLiquidate, "");
            IBondNFT(nftAddress).safeTransferFrom(address(this), positionOwner, tokenId, amount - amountToLiquidate, "");
            stableToken.burn(address(this), positionValue);
        }

        emit Liquidated(positionOwner, msg.sender, nftAddress, tokenId, amount);
        return;
    }

    function getRewardAmount() external view returns (uint256) {
        uint256 currentDebt = calculateDebt(totalStats.debt, totalStats.debtUpdateTimestamp, block.timestamp);
        uint256 rewardAmount = currentDebt - totalStats.borrowed - RewardsTransfered;
        return rewardAmount;
    }

    function getRewards() external onlyStablesStaking returns (uint256) {
        uint256 currentDebt;
        if (totalStats.debtUpdateTimestamp == block.timestamp) {
            currentDebt = totalStats.debt;
        } else {
            currentDebt = calculateDebt(totalStats.debt, totalStats.debtUpdateTimestamp, block.timestamp);
        }

        uint256 rewardAmount = currentDebt - totalStats.borrowed - RewardsTransfered;
        RewardsTransfered += rewardAmount;

        if (rewardAmount > 0) {
            stableToken.transfer(msg.sender, rewardAmount);
        }

        return rewardAmount;
    }

    /**
     * @notice Get the amount of NFTs a user has staked for a specific NFT contract and token ID
     * @dev This is a view function for testing purposes
     * @param user The address of the user
     * @param nftAddress The address of the NFT contract
     * @param tokenId The ID of the NFT
     * @return The amount of NFTs the user has staked
     */
    function getUserNFTBalance(address user, address nftAddress, uint256 tokenId) external view returns (uint256) {
        return userNFTs[user][nftAddress][tokenId];
    }
}
