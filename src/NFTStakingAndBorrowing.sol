// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {IBondNFT} from "./Interfaces/IBondNFT.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {UD60x18, ud} from "@prb/math/src/UD60x18.sol";

interface IMintableERC20 is IERC20 {
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
}

contract NFTStakingAndBorrowing is ERC1155Holder, Ownable {
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

    TotalStats public totalStats;

    mapping(address => bool) public whitelistedNFTs;
    mapping(address => UserStats) public userStats;
    mapping(address => mapping(address => mapping(uint256 => uint256))) public userNFTs;

    uint256 internal constant YEAR_IN_SECONDS = 31536000; // 365 days
    uint256 internal constant UNIT = 1e18;
    uint256 internal constant BIPS = 1e4;
    uint256 public PROTOCOL_YIELD = 1200 * UNIT / BIPS;
    uint256 public SAFETY_FEE = 500 * UNIT / BIPS;
    uint256 public LIQUIDATION_TIME_WINDOW = 45 * 24 * 60 * 60; // 45 days

    IMintableERC20 public stableToken;

    event NFTStaked(address indexed user, address indexed nftAddress, uint256 tokenId, uint256 amount);
    event NFTUnstaked(address indexed user, address indexed nftAddress, uint256 tokenId, uint256 amount);
    event Borrowed(address indexed user, uint256 amount);
    event Repaid(address indexed user, uint256 amount);
    event Liquidated(
        address indexed user, address liquidator, address indexed nftAddress, uint256 tokenId, uint256 amount
    );

    // Custom errors
    error NFTNotWhitelisted();
    error InsufficientNFTBalance();
    error BorrowAmountExceedsLimit(uint256);
    error InsufficientBalanceToRepay();
    error NotEnoughCollateral(uint256);
    error TooEarlyToLiquidate();

    constructor(address _stableToken) ERC1155Holder() Ownable(msg.sender) {
        stableToken = IMintableERC20(_stableToken);
    }

    function whitelistNFT(address nftAddress, bool status) external onlyOwner {
        whitelistedNFTs[nftAddress] = status;
    }

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

    // function getUserStats(address userAddress) public view returns (UserStats memory) {
    //     return userStats[userAddress];
    // }

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

    function stakeNFT(address nftAddress, uint256 tokenId, uint256 amount) external {
        if (!whitelistedNFTs[nftAddress]) revert NFTNotWhitelisted();
        if (IBondNFT(nftAddress).balanceOf(msg.sender, tokenId) < amount) revert InsufficientNFTBalance();

        IBondNFT(nftAddress).safeTransferFrom(msg.sender, address(this), tokenId, amount, "");
        userNFTs[msg.sender][nftAddress][tokenId] = amount;

        IBondNFT.Metadata memory metadata = IBondNFT(nftAddress).getMetaData(tokenId);

        uint256 totalValue = (metadata.value + metadata.couponValue) * amount * (UNIT - SAFETY_FEE) / UNIT;

        totalStats.staked += totalValue;

        userStats[msg.sender].staked += totalValue;
        userStats[msg.sender].nominalAvailable +=
            calculateMaxBorrow(totalValue, block.timestamp, metadata.expirationTimestamp);
        userStats[msg.sender].debtUpdateTimestamp = block.timestamp;

        stableToken.mint(address(this), totalValue);

        emit NFTStaked(msg.sender, nftAddress, tokenId, amount);
    }

    function calculateMaxBorrow(uint256 totalAmount, uint256 fromTime, uint256 toTime) public view returns (uint256) {
        totalAmount = totalAmount * 1e12;
        UD60x18 timeDelta = ud(toTime - fromTime);
        UD60x18 maxBorrowLog2 =
            ud(totalAmount).log2() - (timeDelta / ud(YEAR_IN_SECONDS)) * (ud(UNIT + PROTOCOL_YIELD)).log2();

        return maxBorrowLog2.exp2().intoUint256() / 1e12;
    }

    function calculateDebt(uint256 borrowedAmount, uint256 fromTime, uint256 toTime) internal view returns (uint256) {
        borrowedAmount = borrowedAmount * 1e12;
        UD60x18 timeDelta = ud(toTime - fromTime);
        UD60x18 debtLog2 =
            (timeDelta / ud(YEAR_IN_SECONDS)) * (ud(UNIT + PROTOCOL_YIELD)).log2() + ud(borrowedAmount).log2();
        return debtLog2.exp2().intoUint256() / 1e12;
    }

    function unstakeNFT(address nftAddress, uint256 tokenId, uint256 amount) external {
        if (!whitelistedNFTs[nftAddress]) revert NFTNotWhitelisted();
        // Only NFT owner can unstake anytime
        if (userNFTs[msg.sender][nftAddress][tokenId] < amount) revert InsufficientNFTBalance();

        IBondNFT.Metadata memory metadata = IBondNFT(nftAddress).getMetaData(tokenId);
        uint256 totalUnstakeValue = (metadata.value + metadata.couponValue) * amount * (UNIT - SAFETY_FEE) / UNIT;

        updateUserDebtAndAvailable(msg.sender);
        updateTotalDebt();

        // check if user has enough collateral
        if (
            calculateMaxBorrow(totalUnstakeValue, block.timestamp, metadata.expirationTimestamp)
                > userStats[msg.sender].nominalAvailable - userStats[msg.sender].debt
        ) {
            revert NotEnoughCollateral(userStats[msg.sender].nominalAvailable - userStats[msg.sender].debt);
        }

        userNFTs[msg.sender][nftAddress][tokenId] -= amount;

        userStats[msg.sender].staked -= totalUnstakeValue;
        userStats[msg.sender].nominalAvailable -=
            calculateMaxBorrow(totalUnstakeValue, block.timestamp, metadata.expirationTimestamp);
        totalStats.staked -= totalUnstakeValue;

        IBondNFT(nftAddress).safeTransferFrom(address(this), msg.sender, tokenId, amount, "");

        stableToken.burn(address(this), totalUnstakeValue);

        emit NFTUnstaked(msg.sender, nftAddress, tokenId, amount);
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

    function borrow(uint256 amount) external {
        updateUserDebtAndAvailable(msg.sender);
        updateTotalDebt();

        if (amount == 0) {
            amount = userStats[msg.sender].nominalAvailable - userStats[msg.sender].debt;
        }

        if (amount > userStats[msg.sender].nominalAvailable - userStats[msg.sender].debt) {
            revert BorrowAmountExceedsLimit(userStats[msg.sender].nominalAvailable - userStats[msg.sender].debt);
        }

        userStats[msg.sender].debt += amount;
        userStats[msg.sender].borrowed += amount;
        totalStats.borrowed += amount;
        totalStats.debt += amount;

        stableToken.transfer(msg.sender, amount);

        emit Borrowed(msg.sender, amount);
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

    function repay(uint256 amount) external {
        updateUserDebtAndAvailable(msg.sender);
        updateTotalDebt();

        if (amount == 0) amount = userStats[msg.sender].debt;

        if (stableToken.balanceOf(msg.sender) < amount) revert InsufficientBalanceToRepay();

        stableToken.transferFrom(msg.sender, address(this), amount);
        userStats[msg.sender].debt -= amount;
        userStats[msg.sender].borrowed -= amount;

        totalStats.borrowed -= amount;
        totalStats.debt -= amount;

        emit Repaid(msg.sender, amount);
    }

    function liquidate(address nftAddress, uint256 tokenId, address positionOwner) external {
        if (!whitelistedNFTs[nftAddress]) revert NFTNotWhitelisted();
        if (userNFTs[positionOwner][nftAddress][tokenId] == 0) revert InsufficientNFTBalance();
        IBondNFT.Metadata memory metadata = IBondNFT(nftAddress).getMetaData(tokenId);
        if (block.timestamp < metadata.expirationTimestamp - LIQUIDATION_TIME_WINDOW) revert TooEarlyToLiquidate();

        uint256 amount = userNFTs[positionOwner][nftAddress][tokenId];

        uint256 positionValue = (metadata.value + metadata.couponValue) * amount * (UNIT - SAFETY_FEE) / UNIT;

        updateUserDebtAndAvailable(positionOwner);
        updateTotalDebt();

        // Case 1: Position has no debt - all NFTs return to the position owner
        //         Liquidator does not pay any debt only for transaction fee
        if (userStats[positionOwner].debt == 0) {
            IBondNFT(nftAddress).safeTransferFrom(address(this), positionOwner, tokenId, amount, "");
            stableToken.burn(address(this), positionValue);
            emit NFTUnstaked(positionOwner, nftAddress, tokenId, amount);
            return;
        }

        // Case 2: Position has debt position value - all NFTs go to the liquidator
        //         Liquidator pays part of the debt equivalently to NFTs total value
        if (userStats[positionOwner].debt >= positionValue) {
            stableToken.transferFrom(msg.sender, address(this), positionValue);
            IBondNFT(nftAddress).safeTransferFrom(address(this), msg.sender, tokenId, amount, "");
            userStats[positionOwner].debt -= positionValue;
            totalStats.debt -= positionValue;
            stableToken.burn(address(this), positionValue);
            emit Liquidated(positionOwner, msg.sender, nftAddress, tokenId, amount);
            return;
        }

        // Case 3: Position has debt less than position value - part of NFTs goes to the liquidator
        //         Liquidator pays full the debt
        if (userStats[positionOwner].debt < positionValue) {
            uint256 amountToLiquidate = amount * userStats[positionOwner].debt / positionValue
                + (amount * userStats[positionOwner].debt % positionValue == 0 ? 0 : 1);
            uint256 liquidationPayment =
                (metadata.value + metadata.couponValue) * amountToLiquidate * (UNIT - SAFETY_FEE) / UNIT;
            stableToken.transferFrom(msg.sender, address(this), liquidationPayment);
            stableToken.transfer(positionOwner, liquidationPayment - userStats[positionOwner].debt);

            IBondNFT(nftAddress).safeTransferFrom(address(this), msg.sender, tokenId, amountToLiquidate, "");
            IBondNFT(nftAddress).safeTransferFrom(address(this), positionOwner, tokenId, amount - amountToLiquidate, "");

            userStats[positionOwner].debt = 0;
            totalStats.debt -= userStats[positionOwner].debt;

            stableToken.burn(address(this), positionValue);
            emit Liquidated(positionOwner, msg.sender, nftAddress, tokenId, amount);
            return;
        }
    }
}
