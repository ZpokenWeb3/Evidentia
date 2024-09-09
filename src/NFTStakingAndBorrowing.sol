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
    struct Stake {
        address nftContract;
        uint256 tokenId;
        uint256 amount;
        uint256 timestamp;
        uint256 value;
    }

    struct TotalStats {
        uint256 staked;
        uint256 borrowed;
        uint256 debt;
        uint256 debtUpdateTimestamp;
    }

    struct UserStats {
        uint256 staked;
        uint256 available;
        uint256 borrowed;
        uint256 debt;
        uint256 debtUpdateTimestamp;
    }

    TotalStats public totalStats;

    mapping(address => bool) public whitelistedNFTs;
    mapping(address => Stake[]) public userStakes;
    mapping(address => UserStats) public userStats;

    uint256 internal constant YEAR_IN_SECONDS = 31536000; // 365 days
    uint256 internal constant DECIMALS_MULTIPLIER = 1e18;
    uint256 internal constant BIPS = 1e4;
    uint256 public constant PROTOCOL_YIELD = 1200 * DECIMALS_MULTIPLIER / BIPS;

    IMintableERC20 public stableToken;

    event NFTStaked(address indexed user, address indexed nftContract, uint256 tokenId, uint256 amount);
    event NFTUnstaked(address indexed user, address indexed nftContract, uint256 tokenId, uint256 amount);
    event Borrowed(address indexed user, uint256 amount);
    event Repaid(address indexed user, uint256 amount);

    // Custom errors
    error NFTNotWhitelisted();
    error InsufficientNFTBalance();
    error InvalidStakeIndex();
    error OutstandingLoanExists();
    error BorrowAmountExceedsLimit();
    error NoOutstandingLoan();
    error InsufficientBalanceToRepay();

    constructor(address _stableToken) ERC1155Holder() Ownable(msg.sender) {
        stableToken = IMintableERC20(_stableToken);
    }

    function whitelistNFT(address nftContract, bool status) external onlyOwner {
        whitelistedNFTs[nftContract] = status;
    }

    function getUserStakes(address user) public view returns (Stake[] memory) {
        return userStakes[user];
    }

    function getUserStats(address user) public view returns (UserStats memory) {
        return userStats[user];
    }

    function getTotalStats() public view returns (TotalStats memory) {
        return totalStats;
    }

    function stakeNFT(address nftContract, uint256 tokenId, uint256 amount) external {
        if (!whitelistedNFTs[nftContract]) revert NFTNotWhitelisted();
        if (IBondNFT(nftContract).balanceOf(msg.sender, tokenId) < amount) revert InsufficientNFTBalance();

        IBondNFT(nftContract).safeTransferFrom(msg.sender, address(this), tokenId, amount, "");

        IBondNFT.Metadata memory metadata = IBondNFT(nftContract).getMetaData(tokenId);

        uint256 totalValue = (metadata.value + metadata.couponValue) * amount;

        userStakes[msg.sender].push(Stake(nftContract, tokenId, amount, block.timestamp, totalValue));
        totalStats.staked += totalValue;

        userStats[msg.sender].staked += totalValue;
        // if (userStats[msg.sender].debt != 0) {
        //     userStats[msg.sender].debt = calculateDebt(userStats[msg.sender].debt, userStats[msg.sender].debtUpdateTimestamp, block.timestamp);
        //     userStats[msg.sender].debtUpdateTimestamp = block.timestamp;
        // }
        userStats[msg.sender].available += calculateMaxBorrow(totalValue, block.timestamp, metadata.expirationTimestamp);

        stableToken.mint(address(this), totalValue);

        emit NFTStaked(msg.sender, nftContract, tokenId, amount);
    }

    function calculateMaxBorrow(uint256 totalAmount, uint256 fromTime, uint256 toTime) internal pure returns (uint256) {
        totalAmount = totalAmount * 1e12;
        UD60x18 timeDelta = ud(toTime) - ud(fromTime);
        UD60x18 maxBorrow = ud(totalAmount).log2() 
            - (timeDelta/ud(YEAR_IN_SECONDS)) * (ud(DECIMALS_MULTIPLIER) + ud(PROTOCOL_YIELD)).log2();

        return maxBorrow.exp2().intoUint256()/1e12;
    }

    function calculateDebt(uint256 borrowedAmount, uint256 fromTime, uint256 toTime) internal pure returns (uint256) {
        borrowedAmount = borrowedAmount * 1e12;
        UD60x18 timeDelta = ud(toTime) - ud(fromTime);
        UD60x18 debtLog2 = (timeDelta/ud(YEAR_IN_SECONDS)) * (ud(DECIMALS_MULTIPLIER) + ud(PROTOCOL_YIELD)).log2()
            + ud(borrowedAmount).log2();
        return debtLog2.exp2().intoUint256()/1e12;
    }

    function unstakeNFT(uint256 stakeIndex) external {
        if (stakeIndex >= userStakes[msg.sender].length) revert InvalidStakeIndex();
        // if (loans[msg.sender].amount != 0) revert OutstandingLoanExists();

        // Stake storage stake = userStakes[msg.sender][stakeIndex];

        // uint256 reward = calculateReward(msg.sender, stakeIndex);
        // stableToken.mint(msg.sender, reward);

        // IBondNFT(stake.nftContract).safeTransferFrom(address(this), msg.sender, stake.tokenId, stake.amount, "");

        // stableToken.burn(msg.sender, stake.value + reward);

        // emit NFTUnstaked(msg.sender, stake.nftContract, stake.tokenId, stake.amount);

        // // Remove the stake by swapping with the last element and then popping
        // userStakes[msg.sender][stakeIndex] = userStakes[msg.sender][userStakes[msg.sender].length - 1];
        // userStakes[msg.sender].pop();
    }

    function borrow(uint256 amount) external {
        // uint256 maxBorrow = getMaxBorrow(msg.sender);
        // if (amount > maxBorrow) revert BorrowAmountExceedsLimit();
        // if (loans[msg.sender].amount != 0) revert OutstandingLoanExists();

        // loans[msg.sender] = Loan(amount, block.timestamp);
        // stableToken.mint(msg.sender, amount);
        // totalBorrowed += amount;

        // emit Borrowed(msg.sender, amount);
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