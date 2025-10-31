// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IAssetVault
 * @notice Interface for AssetVault contract
 */
interface IAssetVault {
    enum LiquidityOperationType {
        USER_DEPOSIT, // User deposits liquidity
        USER_WITHDRAW, // User withdraws liquidity
        CLOSE_POSITION, // Liquidity change from position closure
        BET_DEPOSIT, // Liquidity from bet collateral deposit
        PAYOUT_EXECUTION // Liquidity change from payout execution

    }

    struct VaultInfo {
        uint256 totalLiquidity; // Total LP liquidity only
        uint256 totalShares;
        uint256 lifetimePnL;
        bool isNegativePnL;
        uint256 totalVolume;
        uint256 totalPositionsSettled;
        uint256 totalLeverageExposure;
        uint256 createdAt;
        uint256 totalFeesCollected;
        uint256 totalStakingFees;
        uint256 totalWithdrawalFees;
        bool isGraduated;
        uint256 graduationThreshold;
        uint256 graduatedAt;
        bool tradingEnabled;
        uint256 pendingPositions;
    }

    struct VaultParams {
        uint256 minBetAmount;
        uint256 maxBetAmount;
        uint16 maxPositionSizePercentBps;
        uint256 minLiquidityAmount;
    }

    struct LPPosition {
        address user;
        uint256 shares;
        uint256 stakedAmount;
        uint256 stakedAt;
        uint256 lastRewardClaim;
        uint256 totalRewardsClaimed;
        uint256 lastProcessedDay;
        uint256 pendingRewards;
    }

    struct DailySnapshot {
        uint256 day;
        uint256 totalLiquidity;
        uint256 totalShares;
        int256 netPnL;
        uint256 totalPositionsSettled;
        bool isProcessed;
        uint256 timestamp;
        uint64[] positionIds;
    }

    /**
     * @notice Add liquidity to vault
     * @param amount Amount of tokens
     */
    function addLiquidity(uint256 amount) external payable;

    /**
     * @notice Remove liquidity from vault
     * @param shares Amount of shares to burn
     */
    function removeLiquidity(uint256 shares) external;

    /**
     * @notice Deposit collateral from bet
     * @param positionId Position ID
     * @param amount Collateral amount in project tokens
     * @param positionSize Position size
     * @param isMarginAdd True if adding margin to existing position, false if opening new position
     */
    function depositFromBet(
        uint64 positionId,
        uint256 amount,
        uint256 positionSize,
        bool isMarginAdd
    ) external payable;

    /**
     * @notice Execute payout to user
     * @param user User address
     * @param amount Payout amount in project tokens
     * @param positionId Position ID for tracking partial payouts
     */
    function executePayout(address user, uint256 amount, uint64 positionId) external;

    /**
     * @notice Update vault P&L
     * @param positionId Position ID (for tracking)
     * @param collateral Collateral amount
     * @param vaultPnL Vault P&L
     * @param fee Fee collected
     * @param positionSize Position size
     */
    function updateVaultPnL(
        uint64 positionId,
        uint256 collateral,
        int256 vaultPnL,
        uint256 fee,
        uint256 positionSize
    ) external;

    function updateVaultParams(
        uint256 _minBetAmount,
        uint256 _maxBetAmount,
        uint16 _maxPositionSizePercentBps
    ) external;

    /**
     * @notice Check position risk
     * @param positionSize Position size
     * @param leverage Leverage multiplier
     * @return canOpen Whether position can be opened
     * @return reason Reason if cannot open
     */
    function checkPositionRisk(uint256 positionSize, uint8 leverage)
        external
        view
        returns (bool canOpen, string memory reason);

    /**
     * @notice Get vault info
     */
    function getVaultInfo() external view returns (VaultInfo memory);

    /**
     * @notice Get vault parameters
     */
    function getVaultParams() external view returns (VaultParams memory);

    /**
     * @notice Get LP position
     * @param user User address
     */
    function getLPPosition(address user) external view returns (LPPosition memory);

    /**
     * @notice Set PositionManager contract address
     * @param _positionManager PositionManager address
     */
    function setPositionManager(address _positionManager) external;

    /**
     * @notice Pause vault
     */
    function pause() external;

    /**
     * @notice Unpause vault
     */
    function unpause() external;

    // ========================================================================
    // FEE-RELATED FUNCTIONS
    // ========================================================================

    /**
     * @notice Get remaining lock time for a user
     * @param user User address
     * @return remainingTime Remaining lock time in seconds
     */
    function getRemainingLockTime(address user) external view returns (uint256);

    /**
     * @notice Calculate withdrawal amount with potential early withdrawal fee
     * @param user User address
     * @param shares Amount of shares to withdraw
     * @return grossAmount Gross withdrawal amount (before fee)
     * @return fee Early withdrawal fee (0 if after lock period or vault not graduated)
     * @return netAmount Net amount user will receive
     * @return isEarlyWithdrawal Whether this would be an early withdrawal
     */
    function calculateWithdrawalAmount(address user, uint256 shares)
        external
        view
        returns (uint256 grossAmount, uint256 fee, uint256 netAmount, bool isEarlyWithdrawal);

    /**
     * @notice Get fee configuration
     * @return stakingFeeBps Staking fee in basis points
     * @return earlyWithdrawalFeeBps Early withdrawal fee in basis points
     * @return minLockPeriod Minimum lock period in seconds
     */
    function getFeeConfig()
        external
        view
        returns (uint16 stakingFeeBps, uint16 earlyWithdrawalFeeBps, uint256 minLockPeriod);

    /**
     * @notice Get total fees collected
     * @return total Total fees collected (all types)
     * @return staking Total staking fees
     * @return withdrawal Total early withdrawal fees
     */
    function getFeesCollected()
        external
        view
        returns (uint256 total, uint256 staking, uint256 withdrawal);

    /**
     * @notice Update staking fee
     * @param stakingFeeBps New staking fee in basis points
     */
    function setStakingFeeBps(uint16 stakingFeeBps) external;

    /**
     * @notice Update early withdrawal fee
     * @param earlyWithdrawalFeeBps New early withdrawal fee in basis points
     */
    function setEarlyWithdrawalFeeBps(uint16 earlyWithdrawalFeeBps) external;

    // ========================================================================
    // GRADUATION FUNCTIONS
    // ========================================================================

    /**
     * @notice Get vault value in USD (for future use)
     * @return valueUSD Vault value in USD (18 decimals)
     */
    function getVaultValueUSD() external view returns (uint256 valueUSD);

    /**
     * @notice Check and update graduation status
     * @dev Uses token amount (not USD value) for graduation check
     */
    function checkGraduation() external;

    /**
     * @notice Set graduation threshold (only before graduation)
     * @param threshold New threshold in token amount (same decimals as token)
     */
    function setGraduationThreshold(uint256 threshold) external;

    /**
     * @notice Emergency: Enable/disable trading (admin override)
     * @param enabled Whether trading should be enabled
     */
    function setTradingEnabled(bool enabled) external;

    /**
     * @notice Set Blocksense Oracle address
     * @param blocksenseOracle Blocksense Oracle contract address
     */
    function setBlocksenseOracle(address blocksenseOracle) external;

    /**
     * @notice Set Oracle Adapter address
     * @param oracleAdapter CLAggregatorAdapter contract address
     */
    function setOracleAdapter(address oracleAdapter) external;

    /**
     * @notice Get oracle adapter address for price feed
     * @return adapter CLAggregatorAdapter address
     */
    function oracleAdapter() external view returns (address);

    /**
     * @notice Get blocksense oracle address
     * @return oracle BlocksenseOracle address
     */
    function blocksenseOracle() external view returns (address);

    // ========================================================================
    // STAKER REWARD FUNCTIONS
    // ========================================================================

    /**
     * @notice Finalize daily rewards and take snapshot
     * @dev Called by admin bot at end of each day
     */
    function finalizeDailyReward() external;

    /**
     * @notice Calculate pending rewards for a staker
     * @param user Address of staker
     * @return pendingRewards Total pending rewards
     * @return processableDays Number of days that can be processed
     */
    function calculatePendingRewards(address user)
        external
        view
        returns (uint256 pendingRewards, uint256 processableDays);

    /**
     * @notice Claim pending rewards
     */
    function claimRewards() external;

    /**
     * @notice Add an admin bot address
     * @param admin Admin bot address to add
     */
    function addAdmin(address admin) external;

    /**
     * @notice Remove an admin bot address
     * @param admin Admin bot address to remove
     */
    function removeAdmin(address admin) external;

    /**
     * @notice Check if an address is an admin
     * @param account Address to check
     * @return bool True if address is an admin
     */
    function isAdmin(address account) external view returns (bool);

    /**
     * @notice Get all admin addresses
     * @return address[] Array of admin addresses
     */
    function getAdmins() external view returns (address[] memory);

    /**
     * @notice Get number of admins
     * @return uint256 Number of admin addresses
     */
    function getAdminCount() external view returns (uint256);

    /**
     * @notice Get daily snapshot details
     * @param day Day number
     * @return snapshot Daily snapshot data
     */
    function getDailySnapshot(uint256 day) external view returns (DailySnapshot memory snapshot);

    /**
     * @notice Get position IDs settled in a specific day
     * @param day Day number
     * @return positionIds Array of position IDs
     */
    function getDailyPositionIds(uint256 day) external view returns (uint64[] memory positionIds);

    /**
     * @notice Get current day's position IDs (before snapshot)
     * @return positionIds Array of position IDs settled today
     */
    function getCurrentDailyPositionIds() external view returns (uint64[] memory positionIds);

    // ========================================================================
    // PENDING PAYOUT SYSTEM FUNCTIONS
    // ========================================================================

    /**
     * @notice Manually trigger processing of pending payouts
     * @dev Can be called by admin when liquidity is added
     */
    function processPendingPayouts() external;

    /**
     * @notice Get pending payout amount for a position
     * @param positionId Position ID
     * @return amount Pending payout amount
     */
    function positionPayouts(uint64 positionId) external view returns (uint256 amount);

    /**
     * @notice Get user address for a pending payout
     * @param positionId Position ID
     * @return user User address
     */
    function pendingPayoutUsers(uint64 positionId) external view returns (address user);

    /**
     * @notice Get the pending payout queue
     * @return queue Array of position IDs in FIFO order
     */
    function getPendingPayoutQueue() external view returns (uint64[] memory queue);
}
