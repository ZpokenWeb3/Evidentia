// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.22;

import {IBondNFT} from "./Interfaces/IBondNFT.sol";
import {ERC1155HolderUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UD60x18, ud} from "@prb/math/src/UD60x18.sol";
import {IStableCoinsStaking} from "./Interfaces/IStableCoinsStaking.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @dev Interface for a mintable and burnable ERC20 token.
 * Used for the stable token interaction within this contract.
 */
interface IMintableERC20 is IERC20 {
    /**
     * @notice Mints `amount` tokens and assigns them to `to`.
     * @param to The address to mint tokens to.
     * @param amount The amount of tokens to mint.
     */
    function mint(address to, uint256 amount) external;

    /**
     * @notice Burns `amount` tokens from `from`.
     * @param from The address to burn tokens from.
     * @param amount The amount of tokens to burn.
     */
    function burn(address from, uint256 amount) external;
}

/**
 * @title NFTStakingAndBorrowing
 * @notice This contract allows users to stake Bond NFTs (ERC1155) and borrow stable tokens (ERC20) against them.
 * It calculates borrowing limits based on NFT metadata (value, coupon, expiration) and applies interest over time.
 * Integrates with a separate StableCoinsStaking contract.
 * @dev This contract is designed to work with the BondNFT contract and a StableBondCoins contract where this contract has the MINTER_ROLE.
 * Uses OpenZeppelin contracts for ERC1155Holder, Ownable, ReentrancyGuard. Uses PRBMath for fixed-point arithmetic.
 */
contract NFTStakingAndBorrowing is
    ERC1155HolderUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    // Storage layout following ERC-7201 to prevent collisions
    struct Layout {
        /// @dev Global statistics for the protocol.
        TotalStats totalStats;
        /// @dev Mapping from NFT contract address to whitelist status. Only whitelisted NFTs can be staked.
        mapping(address => bool) whitelistedNFTs;
        /// @dev Mapping from user address to their statistics.
        mapping(address => UserStats) userStats;
        /// @dev Mapping tracks staked NFTs: user => nftContract => tokenId => amount.
        mapping(address => mapping(address => mapping(uint256 => uint256))) userNFTs;
        /// @dev Annual yield rate applied to borrowed amounts, expressed with UNIT precision (e.g., 12% is 1200 * UNIT / BPS).
        uint256 protocolYield;
        /// @dev Safety fee deducted from NFT value when calculating collateral, expressed with UNIT precision (e.g., 5% is 500 * UNIT / BPS).
        uint256 safetyFee;
        /// @dev Time window before NFT expiration during which liquidation is possible.
        uint256 liquidationTimeWindow;
        /// @dev Total rewards (accrued interest) transferred out to the stables staking contract.
        uint256 rewardsTransfered;
        /// @dev Address of the associated stablecoin staking contract.
        address stablesStakingAddress;
        /// @dev The stablecoin token contract used for borrowing and repayment. Must implement IMintableERC20.
        IMintableERC20 stableToken;
        /// @dev Protocol fee applied to rewards, expressed with UNIT precision (e.g., 1% is 100 * UNIT / BPS).
        uint256 protocolFee;
        /// @dev Address to receive protocol fees.
        address feeReceiver;
    }

    // keccak256(abi.encode(uint256(keccak256("nft.staking.and.borrowing.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_LOCATION = 0x9a8eb021283f43dd2cabdbb84bb028df4a714b0bdf8b9bbf43c63e73140ef000;

    /**
     * @dev Returns the storage layout for this contract.
     */
    function _getStorage() private pure returns (Layout storage $) {
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }

    /**
     * @dev Function that should revert when `msg.sender` is not authorized to upgrade the contract. Called by
     * {upgradeTo} and {upgradeToAndCall}.
     * @param newImplementation address of the new implementation.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Stores global statistics for the protocol.
     * @param staked Total nominal value of all staked NFTs (after safety fee).
     * @param borrowed Total amount of stablecoins initially borrowed by all users.
     * @param debt Total current debt (borrowed + accrued interest) across all users.
     * @param debtUpdateTimestamp Timestamp when the total debt was last updated.
     */
    struct TotalStats {
        uint256 staked;
        uint256 borrowed;
        uint256 debt;
        uint256 debtUpdateTimestamp;
    }

    /**
     * @notice Stores statistics for a specific user.
     * @param staked Total nominal value of the user's staked NFTs (after safety fee).
     * @param nominalAvailable The maximum amount the user *could* borrow based on their staked collateral's future value, before accounting for existing debt.
     * @param borrowed Total amount of stablecoins initially borrowed by the user.
     * @param debt User's current debt (borrowed + accrued interest).
     * @param debtUpdateTimestamp Timestamp when the user's debt and nominalAvailable were last updated.
     */
    struct UserStats {
        uint256 staked;
        uint256 nominalAvailable;
        uint256 borrowed;
        uint256 debt;
        uint256 debtUpdateTimestamp;
    }

    /// @dev Number of seconds in a year, used for interest calculations.
    uint256 internal constant YEAR_IN_SECONDS = 31536000;
    /// @dev Basis unit for fixed-point math (1e18).
    uint256 internal constant UNIT = 1e18;
    /// @dev Basis points denominator (10000), used for fees and yields.
    uint256 internal constant BPS = 1e4;

    /// @notice Emitted when a user stakes NFTs.
    event NFTStaked(address indexed user, address indexed nftAddress, uint256 tokenId, uint256 amount);
    /// @notice Emitted when a user unstakes NFTs.
    event NFTUnstaked(address indexed user, address indexed nftAddress, uint256 tokenId, uint256 amount);
    /// @notice Emitted when a user borrows stablecoins.
    event Borrowed(address indexed user, uint256 amount);
    /// @notice Emitted when a user repays debt.
    event Repaid(address indexed user, uint256 amount);
    /// @notice Emitted when a user's position is liquidated.
    event Liquidated(
        address indexed user, address liquidator, address indexed nftAddress, uint256 tokenId, uint256 amount
    );
    /// @notice Emitted when the stablecoin staking contract address is updated.
    event StablesStakingAddressUpdated(address indexed oldAddress, address indexed newAddress);

    /// @dev Error when attempting to stake an NFT that is not whitelisted.
    error NFTNotWhitelisted();
    /// @dev Error when attempting an action (stake, unstake, liquidate) with insufficient NFT balance (either in wallet or staked).
    error InsufficientNFTBalance();
    /// @dev Error when attempting to borrow more than the calculated maximum allowed amount. Includes the maximum amount allowed.
    error BorrowAmountExceedsLimit(uint256 maxBorrow);
    /// @dev Error when attempting to repay without sufficient stablecoin balance in the wallet.
    error InsufficientBalanceToRepay();
    /// @dev Error when attempting to unstake NFTs would leave insufficient collateral for the existing debt. Includes the remaining borrowing capacity.
    error NotEnoughCollateral(uint256 remainingCapacity);
    /// @dev Error when attempting to liquidate a position before the liquidation time window opens.
    error TooEarlyToLiquidate();
    /// @dev Error when a function restricted to the stable staking contract is called by another address.
    error OnlyStableStakingContract();
    /// @dev Error when attempting to set an address parameter (e.g., stablesStakingAddress) to the zero address.
    error ZeroAddress();
    /// @dev Error when an arithmetic operation results in an overflow during debt/borrow calculations.
    error AmountOverflow();
    /// @dev Error when attempting to stake NFT that has expired over liquidation time.
    error NftExpired();

    /**
     * @dev Initializes the contract (replaces constructor).
     * @param _stableToken The address of the stablecoin (IMintableERC20) contract.
     */
    function initialize(address _stableToken) external initializer {
        if (_stableToken == address(0)) revert ZeroAddress();

        // Initialize parent contracts
        __ERC1155Holder_init();
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        // Initialize storage
        Layout storage $ = _getStorage();
        $.stableToken = IMintableERC20(_stableToken);
        $.protocolYield = 1200 * UNIT / BPS;
        $.safetyFee = 500 * UNIT / BPS;
        $.liquidationTimeWindow = 45 days;
        $.protocolFee = 1000 * UNIT / BPS;
        $.feeReceiver = msg.sender;
    }

    /**
     * @dev Modifier to restrict function access to the `stablesStakingAddress`.
     */
    modifier onlyStablesStaking() {
        Layout storage $ = _getStorage();
        if (msg.sender != $.stablesStakingAddress) revert OnlyStableStakingContract();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Whitelists or de-whitelists an NFT contract address.
     * @dev Only callable by the contract owner.
     * @param nftAddress The address of the NFT contract.
     * @param status The desired whitelist status (true = whitelisted, false = not whitelisted).
     */
    function whitelistNFT(address nftAddress, bool status) external onlyOwner {
        Layout storage $ = _getStorage();
        $.whitelistedNFTs[nftAddress] = status;
    }

    /**
     * @notice Sets the annual protocol yield rate.
     * @dev Only callable by the contract owner. Input is in Basis Points (BPS).
     * @param _protocolYieldInBPS The new yield rate in BPS (e.g., 1200 for 12%).
     */
    function setProtocolYield(uint256 _protocolYieldInBPS) external onlyOwner {
        Layout storage $ = _getStorage();
        $.protocolYield = _protocolYieldInBPS * UNIT / BPS;
    }

    /**
     * @notice Sets the safety fee applied to NFT collateral value.
     * @dev Only callable by the contract owner. Input is in Basis Points (BPS).
     * @param _safetyFeeInBPS The new safety fee in BPS (e.g., 500 for 5%).
     */
    function setSafetyFee(uint256 _safetyFeeInBPS) external onlyOwner {
        Layout storage $ = _getStorage();
        $.safetyFee = _safetyFeeInBPS * UNIT / BPS;
    }

    /**
     * @notice Sets the time window before NFT expiration during which liquidation is allowed.
     * @dev Only callable by the contract owner.
     * @param _timeWindowInSeconds The new liquidation window duration in seconds.
     */
    function setLiquidationTimeWindow(uint256 _timeWindowInSeconds) external onlyOwner {
        Layout storage $ = _getStorage();
        $.liquidationTimeWindow = _timeWindowInSeconds;
    }

    /**
     * @notice Sets the address of the associated stablecoin staking contract.
     * @dev Only callable by the contract owner. Cannot be set to the zero address.
     * @param _address The new address of the stablecoin staking contract.
     */
    function setStablesStakingAddress(address _address) external onlyOwner {
        if (_address == address(0)) revert ZeroAddress();
        Layout storage $ = _getStorage();
        address oldAddress = $.stablesStakingAddress;
        $.stablesStakingAddress = _address;
        emit StablesStakingAddressUpdated(oldAddress, $.stablesStakingAddress);
    }

    /**
     * @notice Sets the protocol fee.
     * @dev Only callable by the contract owner. Input is in Basis Points (BPS).
     * @param _protocolFeeInBPS The new protocol fee in BPS (e.g., 1000 for 10%).
     */
    function setProtocolFee(uint256 _protocolFeeInBPS) external onlyOwner {
        Layout storage $ = _getStorage();
        $.protocolFee = _protocolFeeInBPS * UNIT / BPS;
    }

    /**
     * @notice Sets the fee receiver address.
     * @dev Only callable by the contract owner. Cannot be set to the zero address.
     * @param _address The new fee receiver address.
     */
    function setFeeReceiver(address _address) external onlyOwner {
        if (_address == address(0)) revert ZeroAddress();
        Layout storage $ = _getStorage();
        $.feeReceiver = _address;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculates and returns the current statistics for a given user.
     * @dev Updates debt and nominalAvailable based on time elapsed since the last update.
     * @param userAddress The address of the user.
     * @return updatedUserStats The UserStats struct with debt and nominalAvailable updated to the current block timestamp.
     */
    function getUserStats(address userAddress) public view returns (UserStats memory updatedUserStats) {
        Layout storage $ = _getStorage();
        UserStats memory currentUserStats = $.userStats[userAddress];
        if (currentUserStats.debtUpdateTimestamp == block.timestamp) {
            return currentUserStats;
        }
        uint256 updatedDebt = 0;
        if (currentUserStats.debt != 0) {
            updatedDebt = calculateDebt(currentUserStats.debt, currentUserStats.debtUpdateTimestamp, block.timestamp);
        }
        uint256 updatedNominalAvailable = 0;
        if (currentUserStats.nominalAvailable != 0) {
            updatedNominalAvailable =
                calculateDebt(currentUserStats.nominalAvailable, currentUserStats.debtUpdateTimestamp, block.timestamp);
        }

        updatedUserStats = UserStats(
            currentUserStats.staked, updatedNominalAvailable, currentUserStats.borrowed, updatedDebt, block.timestamp
        );
        return updatedUserStats;
    }

    /**
     * @notice Calculates and returns the current global statistics for the protocol.
     * @dev Updates total debt based on time elapsed since the last update.
     * @return updatedTotalStats The TotalStats struct with debt updated to the current block timestamp.
     */
    function getTotalStats() public view returns (TotalStats memory updatedTotalStats) {
        Layout storage $ = _getStorage();
        if ($.totalStats.debtUpdateTimestamp == block.timestamp) {
            return $.totalStats;
        }
        uint256 updatedDebt = 0;
        if ($.totalStats.debt != 0) {
            updatedDebt = calculateDebt($.totalStats.debt, $.totalStats.debtUpdateTimestamp, block.timestamp);
        }

        updatedTotalStats = TotalStats($.totalStats.staked, $.totalStats.borrowed, updatedDebt, block.timestamp);
        return updatedTotalStats;
    }

    /**
     * @notice Calculates the maximum amount that can be borrowed against a given collateral value (`totalAmount`) considering the time until NFT expiration.
     * @dev This represents the present value of the future collateral value, discounted by the protocol yield.
     * Uses logarithmic and exponential functions for calculation via PRBMath UD60x18.
     * @param totalAmount The value of the collateral (e.g., nominal value after safety fee).
     * @param fromTime The timestamp from which to calculate the present value (e.g., `block.timestamp`).
     * @param toTime The timestamp representing the future point in time (e.g., NFT expiration).
     * @return The maximum borrowable amount (present value) with UNIT precision, divided by UNIT. Returns 0 if fromTime >= toTime.
     * @dev Reverts with AmountOverflow if totalAmount is larger than PRBMath limit.
     */
    function calculateMaxBorrow(uint256 totalAmount, uint256 fromTime, uint256 toTime) public view returns (uint256) {
        Layout storage $ = _getStorage();
        if (fromTime >= toTime) {
            return 0;
        }
        // Prevent overflow when scaling by UNIT
        if (totalAmount > type(uint256).max / UNIT) {
            revert AmountOverflow();
        }
        // Scale amount to UNIT precision for PRBMath
        totalAmount = totalAmount * UNIT;
        UD60x18 timeDelta = ud(toTime - fromTime);
        UD60x18 maxBorrowLog2 =
            ud(totalAmount).log2() - (timeDelta / ud(YEAR_IN_SECONDS)) * (ud(UNIT + $.protocolYield)).log2();

        return maxBorrowLog2.exp2().intoUint256() / UNIT;
    }

    /**
     * @notice Calculates the future value of a borrowed amount after accruing interest over a period.
     * @dev Uses logarithmic and exponential functions for calculation via PRBMath UD60x18.
     * @param borrowedAmount The initial amount borrowed.
     * @param fromTime The timestamp when the amount was borrowed or last updated.
     * @param toTime The timestamp until which interest should be calculated (e.g., `block.timestamp`).
     * @return The debt amount (borrowed amount + accrued interest) with UNIT precision, divided by UNIT.
     * @dev Returns the original borrowedAmount (scaled by UNIT) if fromTime >= toTime.
     */
    function calculateDebt(uint256 borrowedAmount, uint256 fromTime, uint256 toTime) public view returns (uint256) {
        // Scale amount to UNIT precision for PRBMath
        Layout storage $ = _getStorage();
        borrowedAmount = borrowedAmount * UNIT;
        if (fromTime >= toTime) {
            return borrowedAmount / UNIT; // Return original amount if no time passed
        }
        UD60x18 timeDelta = ud(toTime - fromTime);
        UD60x18 debtLog2 =
            (timeDelta / ud(YEAR_IN_SECONDS)) * (ud(UNIT + $.protocolYield)).log2() + ud(borrowedAmount).log2();

        return debtLog2.exp2().intoUint256() / UNIT;
    }

    /**
     * @notice Calculates the amount of stablecoins a user can currently borrow.
     * @dev Updates the user's nominal available borrowing power and current debt to the present block timestamp,
     * then returns the difference. Returns 0 if the user has no nominal available power or if debt exceeds it.
     * @param userAddress The address of the user.
     * @return The amount of stablecoins the user can borrow at the current time.
     */
    function userAvailableToBorrow(address userAddress) public view returns (uint256) {
        if (getUserStats(userAddress).nominalAvailable == 0) return 0; // No collateral staked

        // Calculate current nominal available borrowing power
        uint256 nominalAvailable = calculateDebt(
            getUserStats(userAddress).nominalAvailable, getUserStats(userAddress).debtUpdateTimestamp, block.timestamp
        );

        // Calculate current debt
        if (getUserStats(userAddress).debt == 0) {
            return nominalAvailable; // No debt, can borrow full nominal amount
        } else {
            uint256 debt = calculateDebt(
                getUserStats(userAddress).debt, getUserStats(userAddress).debtUpdateTimestamp, block.timestamp
            );
            // Return difference if positive, otherwise 0
            return nominalAvailable > debt ? nominalAvailable - debt : 0;
        }
    }

    /**
     * @notice Calculates the maximum amount of a specific NFT that a user can currently unstake.
     * @dev Considers the user's current debt and the collateral value required to back that debt after unstaking.
     * Calculates the value of the NFT to be unstaked and the user's current debt/available stats.
     * Determines how much collateral value can be removed without making the remaining collateral insufficient for the debt.
     * Converts this value back into an amount of the specific NFT.
     * @param userAddress The address of the user.
     * @param nftAddress The address of the NFT contract.
     * @param tokenId The ID of the NFT token.
     * @return The maximum amount of the specified NFT that can be unstaked. Returns 0 if the user holds none, or if their debt already exceeds their borrowing capacity.
     */
    function userAvailableToUnstake(address userAddress, address nftAddress, uint256 tokenId)
        public
        view
        returns (uint256)
    {
        uint256 amount = _getStorage().userNFTs[userAddress][nftAddress][tokenId];
        if (amount == 0) {
            return 0; // User doesn't hold this NFT
        }

        // Get NFT metadata to calculate its value
        IBondNFT.Metadata memory metadata = IBondNFT(nftAddress).getMetaData(tokenId);
        // Calculate the value of a single NFT unit for collateral purposes (after safety fee)
        uint256 singleUnstakeValue = (metadata.value + metadata.couponValue) * (UNIT - _getStorage().safetyFee) / UNIT;
        if (singleUnstakeValue == 0) {
            return amount; // If NFT has no value, it doesn't affect collateral, can unstake all
        }

        // Get user stats updated to current time
        UserStats memory updatedUserStats = getUserStats(userAddress);

        // If user is already underwater (debt >= nominal available), they can't unstake collateral
        if (updatedUserStats.nominalAvailable <= updatedUserStats.debt) {
            return 0;
        }

        // If user has no debt, they can unstake all their NFTs
        if (updatedUserStats.debt == 0) {
            return amount;
        }

        // Calculate the maximum borrow power provided by one unit of this NFT
        uint256 maxBorrowPerNFT = calculateMaxBorrow(singleUnstakeValue, block.timestamp, metadata.expirationTimestamp);
        if (maxBorrowPerNFT == 0) {
            return amount; // If NFT max borrow is zero (e.g., expired), it doesn't affect collateral, can unstake all
        }

        // Calculate how much 'excess' borrowing power the user has
        uint256 excessBorrowingPower = updatedUserStats.nominalAvailable - updatedUserStats.debt;

        // Calculate how many NFTs can be removed based on the excess borrowing power
        // availableToUnstake = excessBorrowingPower / maxBorrowPerNFT
        uint256 availableToUnstake = excessBorrowingPower / maxBorrowPerNFT;

        // Return the calculated available amount, capped by the actual amount the user holds
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
     * @notice Allows a user to stake a whitelisted NFT in the contract.
     * @dev This function transfers the specified amount of the NFT from the user to the contract,
     * updates the user's and total staked values, calculates the added borrowing power (`nominalAvailable`),
     * mints corresponding stablecoins to the contract (pre-funding potential future borrows), and emits `NFTStaked`.
     * It uses the internal `_stakeNFT` function and applies a reentrancy guard.
     * NFTs are held by the contract but not explicitly locked.
     * @param nftAddress The address of the whitelisted NFT contract.
     * @param tokenId The ID of the NFT to stake.
     * @param amount The amount of the specific NFT tokenId to stake.
     */
    function stakeNFT(address nftAddress, uint256 tokenId, uint256 amount) public nonReentrant {
        _stakeNFT(nftAddress, tokenId, amount);
    }

    /**
     * @notice Internal function to handle the logic of staking an NFT.
     * @dev Checks whitelisting and user balance. Fetches NFT metadata to calculate its value (minus safety fee).
     * Updates user and total stats (`staked`, `nominalAvailable`, `debtUpdateTimestamp`).
     * Transfers NFT from user to contract. Mints stablecoins to the contract equal to the NFT's calculated value.
     * Emits `NFTStaked`. This function does *not* have a reentrancy guard itself; the public `stakeNFT` does.
     * @param nftAddress The address of the NFT contract.
     * @param tokenId The ID of the NFT to stake.
     * @param amount The amount of the NFT to stake.
     */
    function _stakeNFT(address nftAddress, uint256 tokenId, uint256 amount) internal {
        Layout storage $ = _getStorage();
        // Checks
        if (!$.whitelistedNFTs[nftAddress]) revert NFTNotWhitelisted();
        if (IBondNFT(nftAddress).balanceOf(msg.sender, tokenId) < amount) revert InsufficientNFTBalance();

        // Get Metadata and Calculate Value
        IBondNFT.Metadata memory metadata = IBondNFT(nftAddress).getMetaData(tokenId);
        if (metadata.expirationTimestamp - $.liquidationTimeWindow <= block.timestamp) revert NftExpired();
        // Value used for collateral calculation (includes coupon, reduced by safety fee)
        uint256 totalValue = (metadata.value + metadata.couponValue) * amount * (UNIT - $.safetyFee) / UNIT;
        // Maximum borrowable amount against this specific staked batch
        uint256 maxBorrowForThisStake = calculateMaxBorrow(totalValue, block.timestamp, metadata.expirationTimestamp);

        // Update State (User and Total)
        updateUserDebtAndAvailable(msg.sender);
        updateTotalDebt();

        $.userNFTs[msg.sender][nftAddress][tokenId] += amount;
        $.totalStats.staked += totalValue;
        $.userStats[msg.sender].staked += totalValue;
        $.userStats[msg.sender].nominalAvailable += maxBorrowForThisStake;
        // Note: debtUpdateTimestamp is updated within updateUserDebtAndAvailable
        // Interactions
        IBondNFT(nftAddress).safeTransferFrom(msg.sender, address(this), tokenId, amount, "");
        // Mint stablecoins to this contract, pre-funding potential borrows against the new collateral
        $.stableToken.mint(address(this), totalValue); // Minting full value, not just max borrow

        emit NFTStaked(msg.sender, nftAddress, tokenId, amount);
    }

    /**
     * @notice Allows a user to stake an NFT and simultaneously borrow the maximum possible amount against it,
     * staking those borrowed stables in the designated staking contract.
     * @dev A convenience function combining staking and borrowing/staking stables.
     * It first calls `_stakeNFT` to stake the NFT. Then, it updates the user's debt/available stats.
     * It calculates the newly available amount to borrow (total nominal available minus current debt),
     * borrows this amount using `_borrow` (which updates debt stats but doesn't transfer),
     * approves the stable staking contract, and calls `stakeOnBehalfOf` on the stable staking contract to deposit
     * the borrowed tokens. Uses reentrancy guard.
     * @param nftAddress The address of the whitelisted NFT contract.
     * @param tokenId The ID of the NFT to stake.
     * @param amountNft The amount of the specific NFT tokenId to stake.
     */
    function stakeNFTandStables(address nftAddress, uint256 tokenId, uint256 amountNft) external nonReentrant {
        // 1. Stake NFT
        _stakeNFT(nftAddress, tokenId, amountNft); // Updates state, transfers NFT, mints stables to this contract

        // 2. Calculate amount to borrow & stake (should be max available after NFT stake)
        // Note: _stakeNFT already updated user stats internally via updateUserDebtAndAvailable
        uint256 amountToStake = getUserStats(msg.sender).nominalAvailable - getUserStats(msg.sender).debt;

        // 3. Borrow internally (updates debt state variables)
        _borrow(amountToStake, msg.sender);

        // 4. Stake borrowed stables
        Layout storage $ = _getStorage();
        $.stableToken.approve($.stablesStakingAddress, amountToStake);
        // Assumes stablesStakingAddress is set and implements IStableCoinsStaking
        IStableCoinsStaking($.stablesStakingAddress).stakeOnBehalfOf(amountToStake, msg.sender);
    }

    /**
     * @notice Allows a user to borrow stablecoins against their existing staked collateral
     * and stake those borrowed stables in the designated staking contract.
     * @dev Updates user and total debt/available stats. Calculates the maximum borrowable amount.
     * If `amountToStake` is 0, it defaults to the maximum borrowable amount.
     * Reverts if the requested amount exceeds the maximum. Borrows the amount using `_borrow`,
     * approves the stable staking contract, and calls `stakeOnBehalfOf` on the stable staking contract.
     * Uses reentrancy guard.
     * @param amountToStake The amount of stables to borrow and stake. If 0, borrows and stakes the maximum available amount.
     */
    function stakeStables(uint256 amountToStake) external nonReentrant {
        // 1. Update state
        updateUserDebtAndAvailable(msg.sender);
        updateTotalDebt();

        // 2. Determine borrow amount
        uint256 maxBorrow = getUserStats(msg.sender).nominalAvailable - getUserStats(msg.sender).debt;
        if (amountToStake == 0) {
            amountToStake = maxBorrow;
        }
        if (amountToStake > maxBorrow) {
            revert BorrowAmountExceedsLimit(maxBorrow);
        }

        // 3. Borrow internally
        _borrow(amountToStake, msg.sender);

        // 4. Stake borrowed stables
        Layout storage $ = _getStorage();
        $.stableToken.approve($.stablesStakingAddress, amountToStake);
        IStableCoinsStaking($.stablesStakingAddress).stakeOnBehalfOf(amountToStake, msg.sender);
    }

    /**
     * @notice Allows a user to unstake a previously staked NFT.
     * @dev Checks whitelisting and user's staked balance of the specific NFT.
     * Fetches metadata to calculate the value being unstaked.
     * Updates user and total debt/available stats.
     * **Crucially, it checks if the user's remaining collateral (`nominalAvailable - debt`)
     * is sufficient to cover the borrowing power (`maxBorrow`) being removed by this unstake action.**
     * If collateral is insufficient, it reverts. Updates user and total stats (`staked`, `nominalAvailable`),
     * transfers the NFT back to the user, burns the corresponding stablecoins
     * from the contract's balance (reversing the initial mint), and emits `NFTUnstaked`. Uses reentrancy guard.
     * @param nftAddress The address of the NFT contract.
     * @param tokenId The ID of the NFT to unstake.
     * @param amount The amount of the specific NFT tokenId to unstake.
     */
    function unstakeNFT(address nftAddress, uint256 tokenId, uint256 amount) external nonReentrant {
        Layout storage $ = _getStorage();
        // Checks
        if (!$.whitelistedNFTs[nftAddress]) revert NFTNotWhitelisted();
        // Check if user actually has this NFT staked
        if ($.userNFTs[msg.sender][nftAddress][tokenId] < amount) revert InsufficientNFTBalance();

        // Calculations
        IBondNFT.Metadata memory metadata = IBondNFT(nftAddress).getMetaData(tokenId);
        uint256 totalUnstakeValue = (metadata.value + metadata.couponValue) * amount * (UNIT - $.safetyFee) / UNIT;
        uint256 maxBorrowForUnstake =
            calculateMaxBorrow(totalUnstakeValue, block.timestamp, metadata.expirationTimestamp);

        // Update State (before collateral check)
        updateUserDebtAndAvailable(msg.sender);
        updateTotalDebt();

        // Check if user has enough collateral remaining *after* this unstake
        // The remaining collateral value (in terms of borrow power) must cover the debt.
        if (
            getUserStats(msg.sender).debt > 0
                && maxBorrowForUnstake > (getUserStats(msg.sender).nominalAvailable - getUserStats(msg.sender).debt)
        ) {
            revert NotEnoughCollateral(getUserStats(msg.sender).nominalAvailable - getUserStats(msg.sender).debt);
        }

        // Update State (apply changes)
        $.userNFTs[msg.sender][nftAddress][tokenId] -= amount;
        $.userStats[msg.sender].staked -= totalUnstakeValue;

        // Decrease nominal available carefully, avoid underflow
        if ($.userStats[msg.sender].nominalAvailable >= maxBorrowForUnstake) {
            $.userStats[msg.sender].nominalAvailable -= maxBorrowForUnstake;
        } else {
            // This case should ideally not be reached due to the NotEnoughCollateral check,
            // but included for safety. It implies the user's collateral was exactly enough
            // to cover the debt *before* unstaking this piece.
            $.userStats[msg.sender].nominalAvailable = 0;
        }
        // Note: user debtUpdateTimestamp was updated in updateUserDebtAndAvailable

        $.totalStats.staked -= totalUnstakeValue;
        // Note: total debtUpdateTimestamp was updated in updateTotalDebt

        // Interactions
        IBondNFT(nftAddress).safeTransferFrom(address(this), msg.sender, tokenId, amount, "");
        // Burn the stablecoins that were minted when this NFT was staked
        $.stableToken.burn(address(this), totalUnstakeValue);

        emit NFTUnstaked(msg.sender, nftAddress, tokenId, amount);
    }

    /**
     * @notice Allows a user to borrow stablecoins against their total staked collateral.
     * @dev Updates user and total debt/available stats. Calculates the maximum currently borrowable amount.
     * If `amount` is 0, defaults to the maximum. Reverts if the requested `amount` exceeds the maximum.
     * Calls `_borrow` to update internal debt states, then transfers the borrowed stablecoins from the contract to the user.
     * Uses reentrancy guard.
     * @param amount The amount of stablecoins to borrow. If 0, borrows the maximum available amount.
     */
    function borrow(uint256 amount) public nonReentrant {
        // 1. Update State
        updateUserDebtAndAvailable(msg.sender);
        updateTotalDebt();

        // 2. Determine Borrow Amount
        uint256 maxBorrow = getUserStats(msg.sender).nominalAvailable - getUserStats(msg.sender).debt;
        if (amount == 0) {
            amount = maxBorrow;
        }

        // 3. Check Limit
        if (amount > maxBorrow) {
            revert BorrowAmountExceedsLimit(maxBorrow);
        }

        // 4. Update Debt Internally
        _borrow(amount, msg.sender); // This emits Borrowed event

        // 5. Transfer Tokens
        _getStorage().stableToken.transfer(msg.sender, amount);
    }

    /**
     * @notice Internal function to update debt states when borrowing.
     * @dev Increases the user's `debt` and `borrowed` amounts.
     * Increases the total `debt` and `borrowed` amounts. Emits the `Borrowed` event.
     * This function *only* updates state variables and does *not* perform token transfers.
     * @param amount The amount of stablecoins being borrowed.
     * @param userAddress The address of the user borrowing.
     */
    function _borrow(uint256 amount, address userAddress) internal {
        Layout storage $ = _getStorage();
        // Note: Assumes user/total debt/available stats are already updated for the current block
        $.userStats[userAddress].debt += amount;
        $.userStats[userAddress].borrowed += amount; // Track lifetime borrowed amount for user
        $.totalStats.borrowed += amount; // Track lifetime borrowed amount globally
        $.totalStats.debt += amount;

        emit Borrowed(userAddress, amount);
    }

    /**
     * @notice Updates a user's debt and nominal available borrowing power to the current block timestamp.
     * @dev Checks if an update is needed for the current block.
     * If yes, calculates the accrued interest on the existing debt
     * and the growth of nominal available using `calculateDebt`,
     * updates the user's stats, and sets the `debtUpdateTimestamp` to `block.timestamp`.
     * @param userAddress The address of the user whose stats need updating.
     */
    function updateUserDebtAndAvailable(address userAddress) internal {
        Layout storage $ = _getStorage();
        if ($.userStats[userAddress].debtUpdateTimestamp == block.timestamp) return; // Already updated this block

        // Calculate accrued interest on debt
        if ($.userStats[userAddress].debt != 0) {
            $.userStats[userAddress].debt = calculateDebt(
                $.userStats[userAddress].debt, $.userStats[userAddress].debtUpdateTimestamp, block.timestamp
            );
        }
        // Calculate growth of nominal available (acts like negative debt compounding)
        if ($.userStats[userAddress].nominalAvailable != 0) {
            $.userStats[userAddress].nominalAvailable = calculateDebt(
                $.userStats[userAddress].nominalAvailable, $.userStats[userAddress].debtUpdateTimestamp, block.timestamp
            );
        }
        // Update timestamp
        $.userStats[userAddress].debtUpdateTimestamp = block.timestamp;
    }

    /**
     * @notice Updates the total contract debt to the current block timestamp.
     * @dev Checks if an update is needed for the current block.
     * If yes, calculates the accrued interest on the total existing debt using `calculateDebt`,
     * updates the `totalStats.debt`, and sets the `totalStats.debtUpdateTimestamp` to `block.timestamp`.
     */
    function updateTotalDebt() internal {
        Layout storage $ = _getStorage();
        if ($.totalStats.debtUpdateTimestamp == block.timestamp) return; // Already updated this block

        // Calculate accrued interest on total debt
        if ($.totalStats.debt != 0) {
            $.totalStats.debt = calculateDebt($.totalStats.debt, $.totalStats.debtUpdateTimestamp, block.timestamp);
        }
        // Update timestamp
        $.totalStats.debtUpdateTimestamp = block.timestamp;
    }

    /**
     * @notice Allows a user to repay their outstanding debt.
     * @dev Updates user and total debt stats.
     * If `amount` is 0, defaults to repaying the user's full current debt.
     * Checks if the user has sufficient stablecoin balance. Decreases user and total `debt`.
     * Decreases user and total `borrowed` (lifetime borrowed tracker, capped at 0).
     * Transfers the stablecoins from the user to the contract. Emits `Repaid`. Uses reentrancy guard.
     * @param amount The amount of stablecoins to repay. If 0, repays the full debt.
     */
    function repay(uint256 amount) external nonReentrant {
        // 1. Update State
        updateUserDebtAndAvailable(msg.sender);
        updateTotalDebt();

        // 2. Determine Repayment Amount
        if (amount == 0) amount = getUserStats(msg.sender).debt;
        if (amount == 0) return; // Nothing to repay

        // Ensure user repays at most their current debt
        if (amount > getUserStats(msg.sender).debt) {
            amount = getUserStats(msg.sender).debt;
        }

        // 3. Check User Balance
        if (_getStorage().stableToken.balanceOf(msg.sender) < amount) revert InsufficientBalanceToRepay();

        // 4. Update Debt State (before transfer)
        _getStorage().userStats[msg.sender].debt -= amount;
        // Decrease lifetime borrowed amount, avoid underflow
        if (_getStorage().userStats[msg.sender].borrowed >= amount) {
            _getStorage().userStats[msg.sender].borrowed -= amount;
        } else {
            _getStorage().userStats[msg.sender].borrowed = 0;
        }
        // Note: user debtUpdateTimestamp updated earlier

        _getStorage().totalStats.debt -= amount;
        // Decrease lifetime borrowed amount globally, avoid underflow
        if (_getStorage().totalStats.borrowed >= amount) {
            _getStorage().totalStats.borrowed -= amount;
        } else {
            _getStorage().totalStats.borrowed = 0;
        }
        // Note: total debtUpdateTimestamp updated earlier

        // 5. Transfer Tokens
        _getStorage().stableToken.transferFrom(msg.sender, address(this), amount);

        emit Repaid(msg.sender, amount);
    }

    /**
     * @notice Allows anyone to liquidate an expired or soon-to-expire NFT position of another user.
     * @dev Checks if NFT is whitelisted and if the position owner has staked this NFT.
     * Checks if the current time is within the `liquidationTimeWindow` before the NFT's expiration.
     * Fetches NFT metadata. Updates position owner's and total debt/available stats.
     * Handles three liquidation scenarios:
     * 1. No Debt: NFT is returned to the original `positionOwner`. Liquidator pays only gas.
     *    - Updates state variables (userNFTs, staked)
     *    - Burns tokens to reflect the removal of collateral value
     *    - Returns NFT to the position owner and emits `NFTUnstaked` event
     *
     * 2. Debt >= Max Borrow at Liquidation:
     *    - Liquidator pays `maxPositionBorrow` amount of stablecoins
     *    - Updates state variables (userNFTs, staked, debt)
     *    - Burns tokens to reflect the removal of collateral value
     *    - Transfers all NFTs to the liquidator and emits `Liquidated` event
     *    - User's debt is reduced by the paid amount
     *
     * 3. Debt < Max Borrow at Liquidation:
     *    - Calculates the NFT amount (`amountToLiquidate`) needed to cover the `positionOwner`'s entire debt
     *    - Liquidator pays stablecoins equal to the borrowing power (`liquidationPayment`) of `amountToLiquidate`
     *    - Updates state variables (userNFTs, staked, debt) - the `positionOwner`'s debt is cleared
     *    - Burns tokens to reflect the removal of collateral value
     *    - Any excess payment (`liquidationPayment - currentDebt`) is transferred to the `positionOwner`
     *    - The liquidator receives `amountToLiquidate` NFTs and emits `Liquidated` event
     *    - Any remaining NFT amount is returned to the `positionOwner` and emits `NFTUnstaked` event
     *    - All NFTs are removed from staking regardless of where they go
     *
     * Uses reentrancy guard for security.
     * @param nftAddress The address of the NFT contract.
     * @param tokenId The ID of the NFT within the position to liquidate.
     * @param positionOwner The address of the user whose position is being liquidated.
     */
    function liquidate(address nftAddress, uint256 tokenId, address positionOwner) external nonReentrant {
        Layout storage $ = _getStorage();
        if (!$.whitelistedNFTs[nftAddress]) revert NFTNotWhitelisted();
        if ($.userNFTs[positionOwner][nftAddress][tokenId] == 0) revert InsufficientNFTBalance();
        IBondNFT.Metadata memory metadata = IBondNFT(nftAddress).getMetaData(tokenId);
        if (block.timestamp < metadata.expirationTimestamp - $.liquidationTimeWindow) revert TooEarlyToLiquidate();

        uint256 amount = $.userNFTs[positionOwner][nftAddress][tokenId];

        uint256 positionValue = (metadata.value + metadata.couponValue) * amount * (UNIT - $.safetyFee) / UNIT;
        uint256 maxPositionBorrow = calculateMaxBorrow(positionValue, block.timestamp, metadata.expirationTimestamp);

        updateUserDebtAndAvailable(positionOwner);
        updateTotalDebt();

        // Case 1: Position has no debt - all NFTs return to the position owner
        //         Liquidator does not pay any debt only for transaction fee
        if ($.userStats[positionOwner].debt == 0) {
            // Update NFT balance and staked values
            $.userNFTs[positionOwner][nftAddress][tokenId] = 0;
            $.userStats[positionOwner].staked -= positionValue;
            $.totalStats.staked -= positionValue;

            // Burn tokens (before any external transfers)
            $.stableToken.burn(address(this), positionValue);

            // Transfer NFTs back to the owner and emit event
            IBondNFT(nftAddress).safeTransferFrom(address(this), positionOwner, tokenId, amount, "");
            emit NFTUnstaked(positionOwner, nftAddress, tokenId, amount);
            return;
        }

        // Case 2: Position has debt greater than max borrow at this point - all NFTs go to the liquidator
        //         Liquidator pays part of the debt equivalent to max borrow at this point
        if ($.userStats[positionOwner].debt >= maxPositionBorrow) {
            // Intentional deviation from checks-effects-interactions pattern:
            // Transfer called before state changes for atomicity reasons
            $.stableToken.transferFrom(msg.sender, address(this), maxPositionBorrow);

            // Update state variables
            $.userNFTs[positionOwner][nftAddress][tokenId] = 0;
            $.userStats[positionOwner].staked -= positionValue;
            $.totalStats.staked -= positionValue;
            $.userStats[positionOwner].debt -= maxPositionBorrow;
            $.totalStats.debt -= maxPositionBorrow;

            // Burn tokens (before any external transfers)
            $.stableToken.burn(address(this), positionValue);

            // Transfer NFTs to liquidator and emit event
            IBondNFT(nftAddress).safeTransferFrom(address(this), msg.sender, tokenId, amount, "");
            emit Liquidated(positionOwner, msg.sender, nftAddress, tokenId, amount);
            return;
        } else {
            // Case 3: Position has debt less than max borrow at this point
            //         - Liquidator receives a portion of NFTs proportional to the debt/maxBorrow ratio
            //         - Remaining NFTs (if any) are returned to the position owner
            //         - Liquidator pays the full debt to the contract
            //         - Position owner receives (liquidationPayment - debt) as compensation
            //         - All NFTs are removed from staking regardless of where they go
            uint256 amountToLiquidate = amount * $.userStats[positionOwner].debt / maxPositionBorrow
                + (amount * $.userStats[positionOwner].debt % maxPositionBorrow == 0 ? 0 : 1);
            uint256 liquidationPayment = calculateMaxBorrow(
                (metadata.value + metadata.couponValue) * amountToLiquidate * (UNIT - $.safetyFee) / UNIT,
                block.timestamp,
                metadata.expirationTimestamp
            );
            // Intentional deviation from checks-effects-interactions pattern:
            // Transfer called before state changes for atomicity reasons
            $.stableToken.transferFrom(msg.sender, address(this), liquidationPayment);

            uint256 currentDebt = $.userStats[positionOwner].debt;

            // Update state variables
            // Set to 0 instead of (amount - amountToLiquidate) because all NFTs are removed from staking
            // The NFTs returned to the owner are no longer staked and should not be tracked in userNFTs
            $.userNFTs[positionOwner][nftAddress][tokenId] = 0;
            // Update staked values to reflect removal of all NFTs from staking
            $.userStats[positionOwner].staked -= positionValue;
            $.totalStats.staked -= positionValue;
            $.userStats[positionOwner].debt = 0;
            $.totalStats.debt -= currentDebt;

            // Burn tokens (before any external transfers)
            $.stableToken.burn(address(this), positionValue);

            // Transfer excess payment to position owner
            $.stableToken.transfer(positionOwner, liquidationPayment - currentDebt);

            // Transfer NFTs to liquidator and emit event
            IBondNFT(nftAddress).safeTransferFrom(address(this), msg.sender, tokenId, amountToLiquidate, "");
            emit Liquidated(positionOwner, msg.sender, nftAddress, tokenId, amountToLiquidate);

            // Only transfer NFTs back to the owner if there are any remaining
            uint256 remainingAmount = amount - amountToLiquidate;
            if (remainingAmount > 0) {
                IBondNFT(nftAddress).safeTransferFrom(address(this), positionOwner, tokenId, remainingAmount, "");
                // Emit unstake event for NFTs returned to the owner
                emit NFTUnstaked(positionOwner, nftAddress, tokenId, remainingAmount);
            }
            return;
        }
    }

    /**
     * @notice Calculates the amount of rewards (accrued interest minus already transferred rewards) available to be claimed.
     * @dev Calculates the current total debt based on the last update timestamp.
     * The reward amount is the difference between the current total debt, the total amount ever borrowed (principal), and the rewards already transferred out.
     * @return rewardAmount The amount of claimable rewards.
     */
    function getRewardAmount() external view returns (uint256) {
        Layout storage $ = _getStorage();
        // Calculate total debt up to current block timestamp
        uint256 currentDebt = calculateDebt($.totalStats.debt, $.totalStats.debtUpdateTimestamp, block.timestamp);
        // Rewards = Total Current Debt - Total Principal Borrowed - Rewards Already Claimed
        uint256 rewardAmount = currentDebt - $.totalStats.borrowed - $.rewardsTransfered;
        // Deduct protocol fee
        // Rewards are rounded down, protocol fee is rounded up
        rewardAmount = rewardAmount * (UNIT - $.protocolFee) / UNIT;
        return rewardAmount;
    }

    /**
     * @notice Allows the designated stablecoin staking contract to claim accumulated rewards (interest).
     * @dev Calculates the current total debt. Determines the reward amount (current total debt - total principal borrowed - already transferred rewards).
     * Updates `rewardsTransfered`. Transfers the calculated `rewardAmount` of stablecoins to the caller (`msg.sender`,
     * which must be `stablesStakingAddress` due to the modifier). Only callable by `stablesStakingAddress`.
     * @return rewardAmount The amount of rewards transferred in this call.
     */
    function getRewards() external onlyStablesStaking returns (uint256) {
        Layout storage $ = _getStorage();
        uint256 currentDebt;
        uint256 protocolFee;

        // Get current total debt (avoid redundant calculation if already updated this block)
        if ($.totalStats.debtUpdateTimestamp == block.timestamp) {
            currentDebt = $.totalStats.debt;
        } else {
            // Needs calculation (note: this doesn't update the stored totalStats.debt, only calculates for reward purpose)
            // It might be better to call updateTotalDebt() here first, but sticking to original logic.
            currentDebt = calculateDebt($.totalStats.debt, $.totalStats.debtUpdateTimestamp, block.timestamp);
        }

        // Calculate claimable rewards
        uint256 rewardAmount = currentDebt - $.totalStats.borrowed - $.rewardsTransfered;

        // Update rewards transferred *before* transfer (Effects before Interactions)
        $.rewardsTransfered += rewardAmount;

        // Calculate protocol fee
        if (rewardAmount > 0 && $.protocolFee > 0) {
            // Calculate the product first to avoid potential intermediate truncation
            uint256 product = rewardAmount * $.protocolFee;
            // Perform ceiling division to round up
            protocolFee = (product + UNIT - 1) / UNIT;
        }

        // Deduct protocol fee
        rewardAmount = rewardAmount - protocolFee;

        // Transfer rewards if any
        if (rewardAmount > 0) {
            $.stableToken.transfer(msg.sender, rewardAmount);
        }
        if (protocolFee > 0) {
            $.stableToken.transfer($.feeReceiver, protocolFee);
        }

        return rewardAmount;
    }

    /**
     * @notice Get the amount of a specific NFT a user has staked.
     * @dev Returns the value from the `userNFTs` mapping.
     * @param user The address of the user.
     * @param nftAddress The address of the NFT contract.
     * @param tokenId The ID of the NFT.
     * @return The amount of the specified NFT the user has staked.
     */
    function getUserNFTBalance(address user, address nftAddress, uint256 tokenId) external view returns (uint256) {
        Layout storage $ = _getStorage();
        return $.userNFTs[user][nftAddress][tokenId];
    }

    /**
     * @notice Returns whether an NFT contract is whitelisted.
     * @param nftAddress The address of the NFT contract.
     * @return bool True if the NFT is whitelisted, false otherwise.
     */
    function isWhitelistedNFT(address nftAddress) external view returns (bool) {
        Layout storage $ = _getStorage();
        return $.whitelistedNFTs[nftAddress];
    }

    /**
     * @notice Returns the current protocol yield rate.
     * @return uint256 The annual yield rate expressed with UNIT precision.
     */
    function getProtocolYield() external view returns (uint256) {
        Layout storage $ = _getStorage();
        return $.protocolYield;
    }

    /**
     * @notice Returns the current safety fee.
     * @return uint256 The safety fee expressed with UNIT precision.
     */
    function getSafetyFee() external view returns (uint256) {
        Layout storage $ = _getStorage();
        return $.safetyFee;
    }

    /**
     * @notice Returns the current liquidation time window.
     * @return uint256 The time window in seconds before NFT expiration during which liquidation is possible.
     */
    function getLiquidationTimeWindow() external view returns (uint256) {
        Layout storage $ = _getStorage();
        return $.liquidationTimeWindow;
    }

    /**
     * @notice Returns the total rewards transferred to the stables staking contract.
     * @return uint256 The total amount of rewards transferred.
     */
    function getRewardsTransfered() external view returns (uint256) {
        Layout storage $ = _getStorage();
        return $.rewardsTransfered;
    }

    /**
     * @notice Returns the address of the stablecoin staking contract.
     * @return address The address of the stables staking contract.
     */
    function getStablesStakingAddress() external view returns (address) {
        Layout storage $ = _getStorage();
        return $.stablesStakingAddress;
    }

    /**
     * @notice Returns the address of the stablecoin token contract.
     * @return address The address of the stablecoin token contract.
     */
    function getStableToken() external view returns (address) {
        Layout storage $ = _getStorage();
        return address($.stableToken);
    }

    /**
     * @notice Returns the current protocol fee.
     * @return uint256 The protocol fee expressed with UNIT precision.
     */
    function getProtocolFee() external view returns (uint256) {
        Layout storage $ = _getStorage();
        return $.protocolFee;
    }

    /**
     * @notice Returns the current fee receiver address.
     * @return address The fee receiver address.
     */
    function getFeeReceiver() external view returns (address) {
        Layout storage $ = _getStorage();
        return $.feeReceiver;
    }
}
