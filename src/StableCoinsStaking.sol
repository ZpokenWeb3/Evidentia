// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

interface IERC20 {
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function transfer(address to, uint256 value) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IExternalRewardContract {
    function getRewardAmount() external view returns (uint256);
}

contract StableCoinsStaking {
    IERC20 public stakingToken;
    IExternalRewardContract public externalRewardContract;

    struct StakerInfo {
        uint256 stakedAmount; // Amount of tokens staked by the user
        uint256 rewardDebt; // Rewards already paid to the user
        uint256 depositTime; // The time when the user last deposited or updated staking
    }

    uint256 public totalStaked;
    uint256 public totalTimeWeightedStake; // The total of time-weighted staking (amount * duration)
    uint256 public timeUpdated; // The time when the totalStaked and totalTimeWeightedStake were last updated

    mapping(address => StakerInfo) public stakers;
    uint256 internal constant YEAR_IN_SECONDS = 31536000; // 365 days

    // Event declarations for staking, withdrawing, and claiming rewards
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 reward);

    constructor(address _stakingToken, address _externalRewardContract) {
        stakingToken = IERC20(_stakingToken);
        externalRewardContract = IExternalRewardContract(_externalRewardContract);
    }

    // Function to stake tokens
    function stake(uint256 _amount) external {
        require(_amount > 0, "Cannot stake 0 tokens");

        // Update user's rewards before staking
        _updateRewards(msg.sender);

        stakingToken.transferFrom(msg.sender, address(this), _amount);

        StakerInfo storage user = stakers[msg.sender];

        // Add the new amount to the user's staked amount
        user.stakedAmount += _amount;
        user.depositTime = block.timestamp;

        totalStaked += _amount;

        emit Staked(msg.sender, _amount);
    }

    // Function to withdraw staked tokens
    function withdraw(uint256 _amount) external {
        StakerInfo storage user = stakers[msg.sender];
        require(user.stakedAmount >= _amount, "Withdraw amount exceeds staked balance");

        // Update user's rewards before withdrawing
        _updateRewards(msg.sender);

        user.stakedAmount -= _amount;
        totalStaked -= _amount;

        stakingToken.transfer(msg.sender, _amount);

        emit Withdrawn(msg.sender, _amount);
    }

    // Function to claim rewards
    function claimRewards() external {
        // Update rewards before claiming
        _updateRewards(msg.sender);

        StakerInfo storage user = stakers[msg.sender];
        uint256 pendingReward = _calculatePendingRewards(msg.sender);

        require(pendingReward > 0, "No rewards available");

        user.rewardDebt += pendingReward;

        stakingToken.transfer(msg.sender, pendingReward);

        emit RewardClaimed(msg.sender, pendingReward);
    }

    // Internal function to update rewards and update time-weighted stakes
    function _updateRewards(address _staker) internal {
        StakerInfo storage user = stakers[_staker];

        if (user.stakedAmount > 0) {
            uint256 pendingReward = _calculatePendingRewards(_staker);
            user.rewardDebt += pendingReward;
        }

        // Update totalTimeWeightedStake for the contract
        totalTimeWeightedStake += totalStaked * (block.timestamp - timeUpdated);
        timeUpdated = block.timestamp;

        // Reset the user's deposit time to now after updating rewards
        user.depositTime = block.timestamp;
    }

    // Internal function to calculate pending rewards for a user
    function _calculatePendingRewards(address _staker) internal view returns (uint256) {
        StakerInfo storage user = stakers[_staker];

        if (user.stakedAmount == 0) {
            return 0;
        }

        uint256 _totalTimeWeightedStake = totalTimeWeightedStake + totalStaked * (block.timestamp - timeUpdated);

        // Get the total reward pool from the external contract
        uint256 totalRewardsAvailable = externalRewardContract.getRewardAmount();
        if (totalRewardsAvailable == 0 || totalStaked == 0 || _totalTimeWeightedStake == 0) {
            return 0;
        }

        // Time-weighted stake for the user
        uint256 stakerDuration = block.timestamp - user.depositTime;
        uint256 userTimeWeightedStake = user.stakedAmount * stakerDuration;

        // Calculate the user's share of the total rewards
        uint256 userRewardShare = (userTimeWeightedStake * totalRewardsAvailable) / _totalTimeWeightedStake;

        // Deduct any previously paid rewards
        if (userRewardShare <= user.rewardDebt) {
            return 0;
        }

        return userRewardShare - user.rewardDebt;
    }

    // Function to view pending rewards for a specific user (helper for frontend)
    function pendingRewards(address _staker) external view returns (uint256) {
        return _calculatePendingRewards(_staker);
    }

    function userAPY(address _staker) external view returns (uint256) {
        StakerInfo storage user = stakers[_staker];
        uint256 stakerDuration = block.timestamp - user.depositTime;
        return YEAR_IN_SECONDS * (_calculatePendingRewards(_staker) + user.rewardDebt) * 10000
            / (user.stakedAmount * stakerDuration);
    }
}
