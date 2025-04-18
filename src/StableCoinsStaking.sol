// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.22;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title Interface for interacting with ERC20 tokens.
 */
interface IERC20 {
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function transfer(address to, uint256 value) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title Interface for interacting with an external contract providing rewards.
 */
interface IExternalRewardContract {
    /**
     * @notice Gets the current reward amount available from the external contract (view function).
     * @return The amount of rewards currently available.
     */
    function getRewardAmount() external view returns (uint256);

    /**
     * @notice Gets and potentially transfers rewards from the external contract.
     * @return The amount of rewards obtained.
     */
    function getRewards() external returns (uint256);
}

/**
 * @title A contract for staking stablecoins and earning rewards from an external source.
 * @dev Implements staking, withdrawal, and reward claiming functionalities. Utilizes ReentrancyGuard for security.
 */
contract StableCoinsStaking is ReentrancyGuard {
    /// @notice The ERC20 token used for staking.
    IERC20 public stakingToken;
    /// @notice The contract from which rewards are fetched.
    IExternalRewardContract public externalRewardContract;

    /// @dev Constant representing the number of seconds in a year (365 days).
    uint256 internal constant YEAR_IN_SECONDS = 31536000;
    /// @notice Total amount of tokens currently staked in the contract.
    uint256 public totalStaked;
    /// @notice Cumulative rewards distributed per staked token since the contract's inception. Used for reward calculation.
    uint256 public rewardPerTokenStored;
    /// @notice Timestamp of the last time the reward variables were updated.
    uint256 public lastUpdateTime;

    /**
     * @dev Structure to store information about each staker.
     */
    struct StakerInfo {
        /// @notice The amount of tokens staked by the user.
        uint256 stakedAmount;
        /// @notice Total rewards claimed by the user so far.
        uint256 rewardPaid;
        /// @notice The value of `rewardPerTokenStored` the last time the user's rewards were calculated.
        uint256 userRewardPerTokenPaid;
        /// @notice Rewards earned by the user but not yet claimed.
        uint256 rewardsEarned;
        /// @notice Timestamp of the last stake or withdrawal action by the user.
        uint256 stakeTimestamp;
    }

    /// @notice Mapping from staker address to their StakerInfo struct.
    mapping(address => StakerInfo) public stakers;

    /**
     * @notice Emitted when a user stakes tokens.
     * @param user The address of the staker.
     * @param amount The amount of tokens staked.
     */
    event Staked(address indexed user, uint256 amount);

    /**
     * @notice Emitted when a user withdraws staked tokens.
     * @param user The address of the user withdrawing tokens.
     * @param amount The amount of tokens withdrawn.
     */
    event Withdrawn(address indexed user, uint256 amount);

    /**
     * @notice Emitted when a user claims their earned rewards.
     * @param user The address of the user claiming rewards.
     * @param reward The amount of reward claimed.
     */
    event RewardClaimed(address indexed user, uint256 reward);

    /**
     * @notice Error reverted when attempting an operation with zero amount where it's not allowed (e.g., staking 0 tokens).
     */
    error ZeroAmountNotAllowed();
    /**
     * @notice Error reverted when attempting to withdraw more tokens than currently staked.
     * @param staked The amount currently staked by the user.
     */
    error NotEnoughStaked(uint256 staked);
    /**
     * @notice Error reverted when attempting to claim rewards but none are available.
     */
    error NoRewardsAvailable();
    /**
     * @notice Error reverted when the user does not have enough balance of the staking token to perform the stake operation.
     */
    error NotEnoughBalance();

    /**
     * @notice Initializes the contract with the addresses of the staking token and the external reward contract.
     * @param _stakingToken The address of the ERC20 token to be used for staking.
     * @param _externalRewardContract The address of the contract providing external rewards.
     */
    constructor(address _stakingToken, address _externalRewardContract) {
        stakingToken = IERC20(_stakingToken);
        externalRewardContract = IExternalRewardContract(_externalRewardContract);
    }

    /**
     * @dev Modifier to update reward calculations before certain actions.
     * @param _staker The address of the staker whose rewards need to be updated. If address(0), only global state is updated.
     */
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

    /**
     * @notice Allows a user to stake a specified amount of staking tokens.
     * @dev Requires the user to have approved the contract to spend their tokens. Updates rewards before staking.
     * @param _amount The amount of tokens to stake. Must be greater than zero.
     */
    function stake(uint256 _amount) external nonReentrant updateReward(msg.sender) {
        if (_amount == 0) revert ZeroAmountNotAllowed();
        if (stakingToken.balanceOf(msg.sender) < _amount) revert NotEnoughBalance();

        StakerInfo storage user = stakers[msg.sender];
        user.stakedAmount += _amount;
        totalStaked += _amount;
        user.stakeTimestamp = block.timestamp;
        stakingToken.transferFrom(msg.sender, address(this), _amount);

        emit Staked(msg.sender, _amount);
    }

    /**
     * @notice Allows a user (sender) to stake tokens on behalf of another address.
     * @dev Requires the sender to have approved the contract to spend their tokens. Updates rewards for the beneficiary before staking.
     * @param _amount The amount of tokens to stake. Must be greater than zero.
     * @param onBehalfOf The address for whom the tokens are being staked.
     */
    function stakeOnBehalfOf(uint256 _amount, address onBehalfOf) external nonReentrant updateReward(onBehalfOf) {
        if (_amount == 0) revert ZeroAmountNotAllowed();
        if (stakingToken.balanceOf(msg.sender) < _amount) revert NotEnoughBalance();

        StakerInfo storage user = stakers[onBehalfOf];
        user.stakedAmount += _amount;
        totalStaked += _amount;
        user.stakeTimestamp = block.timestamp;
        stakingToken.transferFrom(msg.sender, address(this), _amount);

        emit Staked(onBehalfOf, _amount);
    }

    /**
     * @notice Allows a user to withdraw a specified amount of their staked tokens.
     * @dev Updates rewards before withdrawal. The amount must be greater than zero and not exceed the user's staked amount.
     * @param _amount The amount of tokens to withdraw.
     */
    function withdraw(uint256 _amount) external nonReentrant updateReward(msg.sender) {
        if (_amount == 0) revert ZeroAmountNotAllowed();
        StakerInfo storage user = stakers[msg.sender];

        if (_amount > user.stakedAmount) revert NotEnoughStaked(user.stakedAmount);

        user.stakedAmount -= _amount;
        totalStaked -= _amount;

        user.stakeTimestamp = block.timestamp;
        stakingToken.transfer(msg.sender, _amount);

        emit Withdrawn(msg.sender, _amount);
    }

    /**
     * @notice Allows a user to claim their accumulated rewards.
     * @dev Updates rewards before claiming. Reverts if no rewards are available.
     */
    function claimRewards() external nonReentrant updateReward(msg.sender) {
        StakerInfo storage user = stakers[msg.sender];
        uint256 reward = user.rewardsEarned;

        if (reward == 0) revert NoRewardsAvailable();

        user.rewardsEarned = 0;
        user.rewardPaid += reward;

        stakingToken.transfer(msg.sender, reward);
        emit RewardClaimed(msg.sender, reward);
    }

    /**
     * @notice Calculates the current reward rate per staked token.
     * @dev Fetches new rewards from the external contract and distributes them proportionally to the total staked amount.
     * @return The updated reward per token value (scaled by 1e18).
     */
    function _rewardPerToken() internal returns (uint256) {
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }

        uint256 currentRewardPerTokenStored = rewardPerTokenStored;
        // Get rewards from the external source (this action might transfer tokens)
        uint256 rewardFromExternal = externalRewardContract.getRewards();
        // Calculate the increase in reward per token based on the new rewards
        return currentRewardPerTokenStored + ((rewardFromExternal * 1e18) / totalStaked);
    }

    /**
     * @notice Calculates the amount of rewards earned by a specific staker since their last update.
     * @dev This calculation is based on the staker's current staked amount and the change in reward per token since their last interaction.
     * @param _staker The address of the staker.
     * @return The total rewards earned by the staker (previously earned but unclaimed + newly earned).
     */
    function _earned(address _staker) internal view returns (uint256) {
        StakerInfo storage user = stakers[_staker];
        // Calculate the difference in reward per token since the user's last update
        uint256 rewardPerTokenDelta = rewardPerTokenStored - user.userRewardPerTokenPaid;
        // Calculate the rewards earned based on staked amount and reward delta, add any previously earned but unclaimed rewards
        return ((user.stakedAmount * rewardPerTokenDelta) / 1e18) + user.rewardsEarned;
    }

    /**
     * @notice Provides a view of the pending rewards for a specific staker without triggering any state changes or reward updates.
     * @dev This function simulates the reward calculation based on the current viewable reward amount from the external contract.
     * @param _staker The address of the staker whose pending rewards are being queried.
     * @return The amount of rewards currently pending for the staker.
     */
    function pendingRewards(address _staker) public view returns (uint256) {
        if (totalStaked == 0) {
            return 0;
        }
        // Get the current potential reward amount from the external contract (view only)
        uint256 rewardFromExternal = externalRewardContract.getRewardAmount();
        // Calculate what the reward per token would be if these rewards were added now
        uint256 _rewardPerTokenStored = rewardPerTokenStored + ((rewardFromExternal * 1e18) / totalStaked);

        StakerInfo storage user = stakers[_staker];
        // Calculate the difference using the simulated reward per token
        uint256 rewardPerTokenDelta = _rewardPerTokenStored - user.userRewardPerTokenPaid;

        // Calculate pending rewards based on the simulated state
        return ((user.stakedAmount * rewardPerTokenDelta) / 1e18) + user.rewardsEarned;
    }
}
