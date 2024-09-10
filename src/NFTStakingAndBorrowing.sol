// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {IBondNFT} from "./Interfaces/IBondNFT.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import { UD60x18, ud } from "@prb/math/src/UD60x18.sol";

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
    uint256 public constant PROTOCOL_YIELD = 1200 * UNIT / BIPS;

    IMintableERC20 public stableToken;

    event NFTStaked(address indexed user, address indexed nftAddress, uint256 tokenId, uint256 amount);
    event NFTUnstaked(address indexed user, address indexed nftAddress, uint256 tokenId, uint256 amount);
    event Borrowed(address indexed user, uint256 amount);
    event Repaid(address indexed user, uint256 amount);

    // Custom errors
    error NFTNotWhitelisted();
    error InsufficientNFTBalance();
    error BorrowAmountExceedsLimit();
    error InsufficientBalanceToRepay();
    error NotEnoughCollateral();

    constructor(address _stableToken) ERC1155Holder() Ownable(msg.sender) {
        stableToken = IMintableERC20(_stableToken);
    }

    function whitelistNFT(address nftAddress, bool status) external onlyOwner {
        whitelistedNFTs[nftAddress] = status;
    }

    function getUserStats(address user) public view returns (UserStats memory) {
        return userStats[user];
    }

    function getTotalStats() public view returns (TotalStats memory) {
        return totalStats;
    }

    function stakeNFT(address nftAddress, uint256 tokenId, uint256 amount) external {
        if (!whitelistedNFTs[nftAddress]) revert NFTNotWhitelisted();
        if (IBondNFT(nftAddress).balanceOf(msg.sender, tokenId) < amount) revert InsufficientNFTBalance();

        IBondNFT(nftAddress).safeTransferFrom(msg.sender, address(this), tokenId, amount, "");
        userNFTs[msg.sender][nftAddress][tokenId] = amount;

        IBondNFT.Metadata memory metadata = IBondNFT(nftAddress).getMetaData(tokenId);

        uint256 totalValue = (metadata.value + metadata.couponValue) * amount;

        totalStats.staked += totalValue;

        userStats[msg.sender].staked += totalValue;
        userStats[msg.sender].nominalAvailable += calculateMaxBorrow(totalValue, block.timestamp, metadata.expirationTimestamp);

        stableToken.mint(address(this), totalValue);

        emit NFTStaked(msg.sender, nftAddress, tokenId, amount);
    }

    function calculateMaxBorrow(uint256 totalAmount, uint256 fromTime, uint256 toTime) internal pure returns (uint256) {
        totalAmount = totalAmount * 1e12;
        UD60x18 timeDelta = ud(toTime) - ud(fromTime);
        UD60x18 maxBorrow = ud(totalAmount).log2() 
            - (timeDelta/ud(YEAR_IN_SECONDS)) * (ud(UNIT) + ud(PROTOCOL_YIELD)).log2();

        return maxBorrow.exp2().intoUint256()/1e12;
    }

    function calculateDebt(uint256 borrowedAmount, uint256 fromTime, uint256 toTime) internal pure returns (uint256) {
        borrowedAmount = borrowedAmount * 1e12;
        UD60x18 timeDelta = ud(toTime) - ud(fromTime);
        UD60x18 debtLog2 = (timeDelta/ud(YEAR_IN_SECONDS)) * (ud(UNIT) + ud(PROTOCOL_YIELD)).log2()
            + ud(borrowedAmount).log2();
        return debtLog2.exp2().intoUint256()/1e12;
    }

    function unstakeNFT(address nftAddress, uint256 tokenId, uint256 amount) external {
        if (!whitelistedNFTs[nftAddress]) revert NFTNotWhitelisted();
        if (userNFTs[msg.sender][nftAddress][tokenId] < amount) revert InsufficientNFTBalance();

        IBondNFT.Metadata memory metadata = IBondNFT(nftAddress).getMetaData(tokenId);
        uint256 totalValue = (metadata.value + metadata.couponValue) * amount;

        updateUserDebtAndAvailable(msg.sender);

        // TODO check if user has enough collateral
        if (calculateMaxBorrow(totalValue, block.timestamp, metadata.expirationTimestamp) > userStats[msg.sender].nominalAvailable - userStats[msg.sender].debt) 
            revert NotEnoughCollateral();

        userNFTs[msg.sender][nftAddress][tokenId] -= amount;

        userStats[msg.sender].staked -= totalValue;
        userStats[msg.sender].nominalAvailable -= calculateMaxBorrow(totalValue, block.timestamp, metadata.expirationTimestamp);

        IBondNFT(nftAddress).safeTransferFrom(address(this), msg.sender, tokenId, amount, "");

        stableToken.burn(address(this), totalValue);

        emit NFTUnstaked(msg.sender, nftAddress, tokenId, amount);

    }

    function userAvailableToBorrow(address userAddress) public view returns (uint256) {
        uint256 nominalAvailable = calculateDebt(userStats[userAddress].nominalAvailable, userStats[userAddress].debtUpdateTimestamp, block.timestamp);
        if (userStats[userAddress].debt == 0) 
            return nominalAvailable;
        else {
            uint256 debt = calculateDebt(userStats[userAddress].debt, userStats[userAddress].debtUpdateTimestamp, block.timestamp);
            return nominalAvailable - debt;
        }          
    }

    function borrow(uint256 amount) external {
        
        updateUserDebtAndAvailable(msg.sender);

        if (amount > userStats[msg.sender].nominalAvailable - userStats[msg.sender].debt) revert BorrowAmountExceedsLimit();

        if (totalStats.debt != 0) {
            totalStats.debt = calculateDebt(totalStats.debt, totalStats.debtUpdateTimestamp, block.timestamp);
            totalStats.debtUpdateTimestamp = block.timestamp;
        }

        userStats[msg.sender].debt += amount;
        userStats[msg.sender].borrowed += amount;
        totalStats.borrowed += amount;

        stableToken.transfer(msg.sender, amount);

        emit Borrowed(msg.sender, amount);
    }

    function updateUserDebtAndAvailable(address userAddress) internal {
        if (userStats[userAddress].debt != 0) {
            userStats[userAddress].debt = calculateDebt(userStats[userAddress].debt, userStats[userAddress].debtUpdateTimestamp, block.timestamp);
        }
        userStats[userAddress].nominalAvailable = calculateDebt(userStats[userAddress].nominalAvailable, userStats[userAddress].debtUpdateTimestamp, block.timestamp);
        userStats[userAddress].debtUpdateTimestamp = block.timestamp;
    }

    function repay() external {
        // Loan storage loan = loans[msg.sender];
        // if (loan.amount == 0) revert NoOutstandingLoan();

        // uint256 interest = calculateInterest(loan.amount, loan.timestamp);
        // uint256 totalDue = loan.amount + interest;

        // if (stableToken.balanceOf(msg.sender) < totalDue) revert InsufficientBalanceToRepay();

        // stableToken.burn(msg.sender, totalDue);
        // totalBorrowed -= loan.amount;

        // emit Repaid(msg.sender, totalDue);

        // delete loans[msg.sender];
    }

}