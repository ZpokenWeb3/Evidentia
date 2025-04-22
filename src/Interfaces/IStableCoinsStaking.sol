// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface IStableCoinsStaking {
    function stake(uint256 amount) external;
    function stakeOnBehalfOf(uint256 _amount, address onBehalfOf) external;
    function withdraw(uint256 amount) external;
    function claimRewards() external;
    function pendingRewards(address user) external view returns (uint256);
    function expectedAPY(address user) external view returns (uint256);
    function totalStaked() external view returns (uint256);
    function rewardPerTokenStored() external view returns (uint256);
    function lastUpdateTime() external view returns (uint256);
    function stakers(address user) external view returns (StakerInfo memory);
}

struct StakerInfo {
    uint256 stakedAmount;
    uint256 rewardPaid;
    uint256 userRewardPerTokenPaid;
    uint256 rewardsEarned;
    uint256 stakeTimestamp;
}
