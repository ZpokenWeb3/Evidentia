// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

interface IERC20 {
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function transfer(address to, uint256 value) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IExternalRewardContract {
    function getRewardAmount() external view returns (uint256);
    function getRewards() external returns (uint256);
}

contract StableCoinsStaking {
    IERC20 public stakingToken;
    IExternalRewardContract public externalRewardContract;

    uint256 public totalStaked; // Total amount of tokens staked
    uint256 public rewardPerTokenStored; // Cumulative rewards per staked token
    uint256 public lastUpdateTime; // The last time the rewards were updated

    struct StakerInfo {
        uint256 stakedAmount; // Amount of tokens staked by the user
        uint256 rewardPaid; // Rewards already paid to the user
        uint256 userRewardPerTokenPaid; // The last reward per token the user has "seen"
        uint256 rewardsEarned; // Rewards earned by the user, unclaimed
    }

    mapping(address => StakerInfo) public stakers;

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 reward);

    constructor(address _stakingToken, address _externalRewardContract) {
        stakingToken = IERC20(_stakingToken);
        externalRewardContract = IExternalRewardContract(_externalRewardContract);
    }

    modifier updateReward(address _staker) {
        // Update global `rewardPerTokenStored` before any actions
        rewardPerTokenStored = _rewardPerToken();
        lastUpdateTime = block.timestamp;

        if (_staker != address(0)) {
            // Update the user's earned rewards before any action
            StakerInfo storage user = stakers[_staker];
            user.rewardsEarned = _earned(_staker);
            user.userRewardPerTokenPaid = rewardPerTokenStored;
        }
        _;
    }

    // Function to stake tokens
    function stake(uint256 _amount) external updateReward(msg.sender) {
        require(_amount > 0, "Cannot stake 0 tokens");

        stakingToken.transferFrom(msg.sender, address(this), _amount);

        StakerInfo storage user = stakers[msg.sender];
        user.stakedAmount += _amount;
        totalStaked += _amount;

        emit Staked(msg.sender, _amount);
    }

    // Function to withdraw staked tokens
    function withdraw(uint256 _amount) external updateReward(msg.sender) {
        StakerInfo storage user = stakers[msg.sender];
        require(user.stakedAmount >= _amount, "Withdraw amount exceeds staked balance");

        user.stakedAmount -= _amount;
        totalStaked -= _amount;

        stakingToken.transfer(msg.sender, _amount);

        emit Withdrawn(msg.sender, _amount);
    }

    // Function to claim rewards
    function claimRewards() external updateReward(msg.sender) {
        StakerInfo storage user = stakers[msg.sender];
        uint256 reward = user.rewardsEarned;
        require(reward > 0, "No rewards available");

        user.rewardsEarned = 0;
        user.rewardPaid += reward;

        stakingToken.transfer(msg.sender, reward);

        emit RewardClaimed(msg.sender, reward);
    }

    // Internal function to calculate current reward per token
    function _rewardPerToken() internal returns (uint256) {
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }

        uint256 rewardFromExternal = externalRewardContract.getRewards();
        return rewardPerTokenStored + ((rewardFromExternal * 1e18) / totalStaked);
    }

    // Internal function to calculate the user's earned rewards
    function _earned(address _staker) internal view returns (uint256) {
        StakerInfo storage user = stakers[_staker];
        uint256 rewardPerTokenDelta = rewardPerTokenStored - user.userRewardPerTokenPaid;
        return ((user.stakedAmount * rewardPerTokenDelta) / 1e18) + user.rewardsEarned;
    }

    // Helper function to view pending rewards for a user
    function pendingRewards(address _staker) external view returns (uint256) {
        if (totalStaked == 0) {
            return 0;
        }
        uint256 rewardFromExternal = externalRewardContract.getRewardAmount();
        uint256 _rewardPerTokenStored = rewardPerTokenStored + ((rewardFromExternal * 1e18) / totalStaked);

        StakerInfo storage user = stakers[_staker];
        uint256 rewardPerTokenDelta = _rewardPerTokenStored - user.userRewardPerTokenPaid;

        return ((user.stakedAmount * rewardPerTokenDelta) / 1e18) + user.rewardsEarned;
    }
}
