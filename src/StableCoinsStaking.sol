// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.30;

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

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
    function getRewardAmount() external view returns (uint256);
    function getRewards() external returns (uint256);
}

/**
 * @title StableCoinsStaking
 * @dev An upgradeable contract for staking stablecoins and earning rewards from an external source.
 * Implements staking, withdrawal, and reward claiming functionalities. Uses ERC7201 storage namespace and UUPS proxy pattern for upgradeability.
 */
contract StableCoinsStaking is ReentrancyGuardUpgradeable, UUPSUpgradeable, AccessControlUpgradeable {
    // keccak256(abi.encode(uint256(keccak256("StableCoinsStaking.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_LOCATION = 0x5ad9b57132bffc89e46deaf23730f9173da95952e39a655cdb65df9a44414600;

    /// @notice Role identifier for the admin who can upgrade the contract.
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /**
     * @dev Storage struct for ERC7201 namespace.
     */
    struct StableCoinsStakingStorage {
        IERC20 stakingToken;
        IExternalRewardContract externalRewardContract;
        uint256 totalStaked;
        uint256 rewardPerTokenStored;
        uint256 lastUpdateTime;
        mapping(address => StakerInfo) stakers;
    }

    /**
     * @dev Structure to store information about each staker.
     */
    struct StakerInfo {
        uint256 stakedAmount;
        uint256 rewardPaid;
        uint256 userRewardPerTokenPaid;
        uint256 rewardsEarned;
        uint256 stakeTimestamp;
    }

    /// @dev Constant representing the number of seconds in a year (365 days).
    uint256 internal constant YEAR_IN_SECONDS = 31536000;

    /**
     * @notice Emitted when a user stakes tokens.
     */
    event Staked(address indexed user, uint256 amount);

    /**
     * @notice Emitted when a user withdraws staked tokens.
     */
    event Withdrawn(address indexed user, uint256 amount);

    /**
     * @notice Emitted when a user claims their earned rewards.
     */
    event RewardClaimed(address indexed user, uint256 reward);

    /**
     * @notice Errors
     */
    error ZeroAmountNotAllowed();
    error NotEnoughStaked(uint256 staked);
    error NoRewardsAvailable();
    error NotEnoughBalance();

    /**
     * @dev Retrieve the storage slot for the contract.
     */
    function _getStableCoinsStakingStorage() private pure returns (StableCoinsStakingStorage storage $) {
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }

    /**
     * @dev Initializes the contract (replaces constructor).
     * @param _stakingToken The address of the ERC20 token to be used for staking.
     * @param _externalRewardContract The address of the contract providing external rewards.
     * @param admin The address that will be granted the admin role for upgrades.
     */
    function initialize(address _stakingToken, address _externalRewardContract, address admin) external initializer {
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        __AccessControl_init();

        _grantRole(ADMIN_ROLE, admin);

        StableCoinsStakingStorage storage $ = _getStableCoinsStakingStorage();
        $.stakingToken = IERC20(_stakingToken);
        $.externalRewardContract = IExternalRewardContract(_externalRewardContract);
        $.lastUpdateTime = block.timestamp;
    }

    /**
     * @dev Authorize upgrades (required for UUPS).
     * Only callable by the admin (holder of ADMIN_ROLE).
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}

    /**
     * @dev Modifier to update reward calculations before certain actions.
     * @param _staker The address of the staker whose rewards need to be updated. If address(0), only global state is updated.
     */
    modifier updateReward(address _staker) {
        StableCoinsStakingStorage storage $ = _getStableCoinsStakingStorage();
        $.rewardPerTokenStored = _rewardPerToken();
        $.lastUpdateTime = block.timestamp;

        if (_staker != address(0)) {
            StakerInfo storage user = $.stakers[_staker];
            user.rewardsEarned = _earned(_staker);
            user.userRewardPerTokenPaid = $.rewardPerTokenStored;
        }
        _;
    }

    /**
     * @notice Allows a user to stake a specified amount of staking tokens.
     */
    function stake(uint256 _amount) external nonReentrant updateReward(msg.sender) {
        StableCoinsStakingStorage storage $ = _getStableCoinsStakingStorage();
        if (_amount == 0) revert ZeroAmountNotAllowed();
        if ($.stakingToken.balanceOf(msg.sender) < _amount) revert NotEnoughBalance();

        StakerInfo storage user = $.stakers[msg.sender];
        user.stakedAmount += _amount;
        $.totalStaked += _amount;
        user.stakeTimestamp = block.timestamp;
        $.stakingToken.transferFrom(msg.sender, address(this), _amount);

        emit Staked(msg.sender, _amount);
    }

    /**
     * @notice Allows a user (sender) to stake tokens on behalf of another address.
     */
    function stakeOnBehalfOf(uint256 _amount, address onBehalfOf) external nonReentrant updateReward(onBehalfOf) {
        StableCoinsStakingStorage storage $ = _getStableCoinsStakingStorage();
        if (_amount == 0) revert ZeroAmountNotAllowed();
        if ($.stakingToken.balanceOf(msg.sender) < _amount) revert NotEnoughBalance();

        StakerInfo storage user = $.stakers[onBehalfOf];
        user.stakedAmount += _amount;
        $.totalStaked += _amount;
        user.stakeTimestamp = block.timestamp;
        $.stakingToken.transferFrom(msg.sender, address(this), _amount);

        emit Staked(onBehalfOf, _amount);
    }

    /**
     * @notice Allows a user to withdraw a specified amount of their staked tokens.
     */
    function withdraw(uint256 _amount) external nonReentrant updateReward(msg.sender) {
        StableCoinsStakingStorage storage $ = _getStableCoinsStakingStorage();
        if (_amount == 0) revert ZeroAmountNotAllowed();
        StakerInfo storage user = $.stakers[msg.sender];

        if (_amount > user.stakedAmount) revert NotEnoughStaked(user.stakedAmount);

        user.stakedAmount -= _amount;
        $.totalStaked -= _amount;

        user.stakeTimestamp = block.timestamp;
        $.stakingToken.transfer(msg.sender, _amount);

        emit Withdrawn(msg.sender, _amount);
    }

    /**
     * @notice Allows a user to claim their accumulated rewards.
     */
    function claimRewards() external nonReentrant updateReward(msg.sender) {
        StableCoinsStakingStorage storage $ = _getStableCoinsStakingStorage();
        StakerInfo storage user = $.stakers[msg.sender];
        uint256 reward = user.rewardsEarned;

        if (reward == 0) revert NoRewardsAvailable();

        user.rewardsEarned = 0;
        user.rewardPaid += reward;

        $.stakingToken.transfer(msg.sender, reward);
        emit RewardClaimed(msg.sender, reward);
    }

    /**
     * @notice Calculates the current reward rate per staked token.
     */
    function _rewardPerToken() internal returns (uint256) {
        StableCoinsStakingStorage storage $ = _getStableCoinsStakingStorage();
        if ($.totalStaked == 0) {
            return $.rewardPerTokenStored;
        }

        uint256 currentRewardPerTokenStored = $.rewardPerTokenStored;
        uint256 rewardFromExternal = $.externalRewardContract.getRewards();
        return currentRewardPerTokenStored + ((rewardFromExternal * 1e18) / $.totalStaked);
    }

    /**
     * @notice Calculates the amount of rewards earned by a specific staker since their last update.
     */
    function _earned(address _staker) internal view returns (uint256) {
        StableCoinsStakingStorage storage $ = _getStableCoinsStakingStorage();
        StakerInfo storage user = $.stakers[_staker];
        uint256 rewardPerTokenDelta = $.rewardPerTokenStored - user.userRewardPerTokenPaid;
        return ((user.stakedAmount * rewardPerTokenDelta) / 1e18) + user.rewardsEarned;
    }

    /**
     * @notice Provides a view of the pending rewards for a specific staker without triggering any state changes.
     */
    function pendingRewards(address _staker) public view returns (uint256) {
        StableCoinsStakingStorage storage $ = _getStableCoinsStakingStorage();
        if ($.totalStaked == 0) {
            return 0;
        }

        uint256 rewardFromExternal = $.externalRewardContract.getRewardAmount();
        uint256 _rewardPerTokenStored = $.rewardPerTokenStored + ((rewardFromExternal * 1e18) / $.totalStaked);

        StakerInfo storage user = $.stakers[_staker];
        uint256 rewardPerTokenDelta = _rewardPerTokenStored - user.userRewardPerTokenPaid;
        return ((user.stakedAmount * rewardPerTokenDelta) / 1e18) + user.rewardsEarned;
    }

    /**
     * @notice Get the staking token address.
     */
    function stakingToken() external view returns (address) {
        StableCoinsStakingStorage storage $ = _getStableCoinsStakingStorage();
        return address($.stakingToken);
    }

    /**
     * @notice Get the external reward contract address.
     */
    function externalRewardContract() external view returns (address) {
        StableCoinsStakingStorage storage $ = _getStableCoinsStakingStorage();
        return address($.externalRewardContract);
    }

    /**
     * @notice Get the total amount of tokens currently staked.
     */
    function totalStaked() external view returns (uint256) {
        StableCoinsStakingStorage storage $ = _getStableCoinsStakingStorage();
        return $.totalStaked;
    }

    /**
     * @notice Get the reward per token stored.
     */
    function rewardPerTokenStored() external view returns (uint256) {
        StableCoinsStakingStorage storage $ = _getStableCoinsStakingStorage();
        return $.rewardPerTokenStored;
    }

    /**
     * @notice Get the last update timestamp.
     */
    function lastUpdateTime() external view returns (uint256) {
        StableCoinsStakingStorage storage $ = _getStableCoinsStakingStorage();
        return $.lastUpdateTime;
    }

    /**
     * @notice Get the staker's information.
     */
    function stakers(address staker) external view returns (StakerInfo memory) {
        StableCoinsStakingStorage storage $ = _getStableCoinsStakingStorage();
        return $.stakers[staker];
    }
}
