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
     * @dev Automatically removes all shares from the user
     */
    function removeLiquidity() external;

    /**
     * @notice Deposit collateral from bet
     * @param positionId Position ID
     * @param amount Collateral amount in project tokens
     * @param positionSize Position size
     * @param isMarginAdd True if adding margin to existing position, false if opening new position
     * @param direction Position direction (1 = LONG, 2 = SHORT)
     */
    function depositFromBet(
        uint64 positionId,
        uint256 amount,
        uint256 positionSize,
        bool isMarginAdd,
        uint8 direction
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
     * @param positionSize Position size
     * @param direction Position direction (1 = LONG, 2 = SHORT)
     * @param user User address for event tracking
     */
    function updateVaultPnL(
        uint64 positionId,
        uint256 collateral,
        int256 vaultPnL,
        uint256 positionSize,
        uint8 direction,
        address user
    ) external returns (uint256 closeFee);

    function updateVaultParams(uint256 _minBetAmount, uint256 _maxBetAmount) external;

    /**
     * @notice Check position risk
     * @dev Reverts with specific custom error if position cannot be opened
     * @param positionSize Position size
     * @param leverage Leverage multiplier
     * @param direction Position direction (1 = LONG, 2 = SHORT)
     */
    function checkPositionRisk(uint256 positionSize, uint8 leverage, uint8 direction) external view;

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
     * @notice Set treasury address for fee collection
     * @param _treasury Treasury address (can be address(0) to use owner as default)
     */
    function setTreasury(address _treasury) external;

    /**
     * @notice Get treasury address
     * @return Treasury address (address(0) if not set, fees go to owner)
     */
    function getTreasury() external view returns (address);

    /**
     * @notice Pause vault
     */
    function pause() external;

    /**
     * @notice Unpause vault
     */
    function unpause() external;

    /**
     * @notice Check if vault is paused
     * @return True if vault is paused
     */
    function paused() external view returns (bool);

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
     * @notice Get withdrawable fees available for admin
     * @return amount Amount of fees that can be withdrawn by admin
     */
    function getWithdrawableFees() external view returns (uint256 amount);

    /**
     * @notice Withdraw collected fees (staking fees + early withdrawal fees)
     * @param amount Amount to withdraw (0 = withdraw all)
     * @dev Only owner can withdraw fees. Fees will be sent to treasury if set, otherwise to owner.
     */
    function withdrawFees(uint256 amount) external;

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
     * @notice Get project token address
     * @return token Project token address
     */
    function projectToken() external view returns (address);

    // ========================================================================
    // STAKER REWARD FUNCTIONS
    // ========================================================================

    /**
     * @notice Finalize daily rewards and take snapshot
     * @dev Called by admin bot at end of each day
     *      Pre-calculates and stores rewards for all LPs
     */
    function finalizeDailyReward() external;

    /**
     * @notice Finalize daily rewards for remaining LPs (if there are more than MAX_LPS_PER_FINALIZE)
     * @dev Can be called multiple times to process remaining LPs
     *      Automatically continues from last processed index
     * @return isComplete True if all LPs have been processed
     */
    function finalizeDailyRewardRemaining() external returns (bool isComplete);

    /**
     * @notice Calculate pending rewards for a staker
     * @param user Address of staker
     * @return pendingRewards Total pending rewards
     * @return lastProcessedDay Last day that was processed in this calculation
     */
    function calculatePendingRewards(address user)
        external
        view
        returns (uint256 pendingRewards, uint256 lastProcessedDay);

    /**
     * @notice Claim pending rewards (processes up to MAX_DAYS_PER_CALCULATION days per call)
     * @dev Processes rewards in batches to prevent out of gas errors
     *      No slippage protection - use claimRewardsProtected for front-running protection
     */
    function claimRewards() external;

    /**
     * @notice Claim pending rewards with slippage protection
     * @param minExpectedRewards Minimum rewards expected (reverts if actual < min)
     * @dev Added slippage protection to prevent front-running attacks
     */
    function claimRewardsProtected(uint256 minExpectedRewards) external;

    /**
     * @notice Claim pending rewards with custom batch size
     * @param maxDays Maximum number of days to process (0 = use MAX_DAYS_PER_CALCULATION)
     * @dev Processes rewards in batches to prevent out of gas errors
     */
    function claimRewardsBatch(uint256 maxDays) external;

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

    // ========================================================================
    // DIRECTIONAL EXPOSURE FUNCTIONS
    // ========================================================================

    /**
     * @notice Set maximum directional exposure cap
     * @param maxDirectionalExposureBps New max directional exposure in basis points (e.g., 5000 = 50%)
     */
    function setMaxDirectionalExposure(uint16 maxDirectionalExposureBps) external;

    /**
     * @notice Get current directional exposure stats
     * @return longExposure Total LONG exposure
     * @return shortExposure Total SHORT exposure
     * @return netExposure Net exposure (|Long OI - Short OI|)
     * @return maxExposure Maximum allowed directional exposure (based on TVL)
     * @return netUtilization Net exposure utilization in basis points (netExposure / maxExposure * 10000)
     * @return isLongBias True if long bias (longExposure > shortExposure), false if short bias
     */
    function getDirectionalExposure()
        external
        view
        returns (
            uint256 longExposure,
            uint256 shortExposure,
            uint256 netExposure,
            uint256 maxExposure,
            uint256 netUtilization,
            bool isLongBias
        );

    /**
     * @notice Get total LONG exposure
     * @return Total LONG position exposure
     */
    function totalLongExposure() external view returns (uint256);

    /**
     * @notice Get total SHORT exposure
     * @return Total SHORT position exposure
     */
    function totalShortExposure() external view returns (uint256);

    /**
     * @notice Get max directional exposure in basis points
     * @return Max directional exposure cap (e.g., 5000 = 50%)
     */
    function maxDirectionalExposureBps() external view returns (uint16);

    // ========================================================================
    // RISK CONFIG SETTERS
    // ========================================================================

    /**
     * @notice Set leverage tier configuration
     * @param tier1Threshold TVL threshold for tier 1 (Launch Phase)
     * @param tier2Threshold TVL threshold for tier 2 (Growth Phase)
     * @param tier1MaxLeverage Max leverage for TVL < tier1Threshold
     * @param tier2MaxLeverage Max leverage for tier1Threshold <= TVL < tier2Threshold
     * @param tier3MaxLeverage Max leverage for TVL >= tier2Threshold (Mature Phase)
     */
    function setLeverageTierConfig(
        uint256 tier1Threshold,
        uint256 tier2Threshold,
        uint16 tier1MaxLeverage,
        uint16 tier2MaxLeverage,
        uint16 tier3MaxLeverage
    ) external;

    /**
     * @notice Set total OI tier configuration
     * @param totalOIRiskMultiplierBps Fixed multiplier when tiers disabled
     * @param tier1Threshold Small vault threshold
     * @param tier2Threshold Medium vault threshold
     * @param tier3Threshold Large vault threshold
     * @param tier1MultiplierBps Multiplier for tier 1
     * @param tier2MultiplierBps Multiplier for tier 2
     * @param tier3MultiplierBps Multiplier for tier 3
     * @param tier4MultiplierBps Multiplier for tier 4
     */
    function setTotalOITierConfig(
        uint16 totalOIRiskMultiplierBps,
        uint256 tier1Threshold,
        uint256 tier2Threshold,
        uint256 tier3Threshold,
        uint16 tier1MultiplierBps,
        uint16 tier2MultiplierBps,
        uint16 tier3MultiplierBps,
        uint16 tier4MultiplierBps
    ) external;

    /**
     * @notice Set utilization-based leverage configuration
     * @param tier1Bps Threshold for full leverage
     * @param tier2Bps Threshold for reduced leverage
     * @param tier3Bps Threshold for emergency mode
     * @param factorTier1Bps Leverage factor below tier1
     * @param factorTier2Bps Leverage factor tier1-tier2
     * @param factorTier3Bps Leverage factor tier2-tier3
     * @param factorEmergencyBps Leverage factor above tier3
     */
    function setUtilizationConfig(
        uint16 tier1Bps,
        uint16 tier2Bps,
        uint16 tier3Bps,
        uint16 factorTier1Bps,
        uint16 factorTier2Bps,
        uint16 factorTier3Bps,
        uint16 factorEmergencyBps
    ) external;

    /**
     * @notice Set max profit cap multiplier (per-vault)
     * @param multiplier New multiplier (e.g., 3 = 3x collateral)
     */
    function setMaxProfitCapMultiplier(uint8 multiplier) external;

    /**
     * @notice Get max profit cap multiplier
     * @return multiplier Current max profit cap multiplier
     */
    function getMaxProfitCapMultiplier() external view returns (uint8);

    // ========================================================================
    // FUNDING RATE FUNCTIONS
    // ========================================================================

    /**
     * @notice Update hourly funding rates (called by keeper every hour)
     * @return newLongRate New cumulative long rate
     * @return newShortRate New cumulative short rate
     * @return imbalanceBps Current imbalance in basis points
     * @return hasCounterparty True if both Long and Short have OI
     */
    function updateHourlyFunding()
        external
        returns (
            int256 newLongRate,
            int256 newShortRate,
            uint256 imbalanceBps,
            bool hasCounterparty
        );

    /**
     * @notice Get cumulative funding rates
     * @return cumulativeLongRate Cumulative funding rate for Longs
     * @return cumulativeShortRate Cumulative funding rate for Shorts
     */
    function getCumulativeFundingRates()
        external
        view
        returns (int256 cumulativeLongRate, int256 cumulativeShortRate);

    /**
     * @notice Calculate funding owed by a position
     * @param entryRateLong Position's entry cumulative long rate
     * @param entryRateShort Position's entry cumulative short rate
     * @param positionSize Position size
     * @param direction Position direction (1 = LONG, 2 = SHORT)
     * @return fundingOwed Funding amount (positive = owes, negative = receives)
     */
    function calculatePositionFunding(
        int256 entryRateLong,
        int256 entryRateShort,
        uint256 positionSize,
        uint8 direction
    ) external view returns (int256 fundingOwed);

    /**
     * @notice Get current hourly funding rate based on imbalance
     * @return rateBps Funding rate in basis points per hour
     * @return longsPayShorts True if longs pay shorts
     * @return imbalanceBps Current imbalance in basis points
     * @return hasCounterparty True if both sides have OI
     */
    function getCurrentHourlyFundingRate()
        external
        view
        returns (uint256 rateBps, bool longsPayShorts, uint256 imbalanceBps, bool hasCounterparty);

    /**
     * @notice Get funding rate statistics
     * @return cumulativeLongRate Cumulative long rate
     * @return cumulativeShortRate Cumulative short rate
     * @return lastUpdateTime Last funding update timestamp
     * @return currentHourlyRateBps Current hourly rate in bps
     * @return longsPayShorts True if longs pay shorts
     * @return imbalanceBps Current imbalance
     */
    function getFundingStats()
        external
        view
        returns (
            int256 cumulativeLongRate,
            int256 cumulativeShortRate,
            uint256 lastUpdateTime,
            uint256 currentHourlyRateBps,
            bool longsPayShorts,
            uint256 imbalanceBps
        );

    /**
     * @notice Check if position is liquidatable due to funding
     * @param collateral Position collateral
     * @param entryRateLong Entry funding rate for long
     * @param entryRateShort Entry funding rate for short
     * @param positionSize Position size
     * @param direction Position direction
     * @param maintenanceMarginRatio Maintenance margin ratio in bps
     * @return isLiquidatable True if position should be liquidated
     * @return fundingOwed Amount of funding owed
     * @return effectiveCollateral Collateral after funding deduction
     */
    function checkFundingLiquidation(
        uint256 collateral,
        int256 entryRateLong,
        int256 entryRateShort,
        uint256 positionSize,
        uint8 direction,
        uint256 maintenanceMarginRatio
    ) external view returns (bool isLiquidatable, int256 fundingOwed, uint256 effectiveCollateral);

    /**
     * @notice Set funding rate configuration
     * @param tier1RateBps Rate for < 20% imbalance
     * @param tier2RateBps Rate for 20-40% imbalance
     * @param tier3RateBps Rate for 40-60% imbalance
     * @param tier4RateBps Rate for 60-80% imbalance
     * @param tier5RateBps Rate for > 80% imbalance
     */
    function setFundingConfig(
        uint16 tier1RateBps,
        uint16 tier2RateBps,
        uint16 tier3RateBps,
        uint16 tier4RateBps,
        uint16 tier5RateBps
    ) external;

    /**
     * @notice Enable or disable funding rate
     * @param enabled True to enable funding
     */
    function setFundingEnabled(bool enabled) external;

    /**
     * @notice Check if funding is enabled
     * @return True if funding is enabled
     */
    function isFundingEnabled() external view returns (bool);

    // ========================================================================
    // CONFIG VIEW FUNCTIONS (V2 - for VaultViewer)
    // ========================================================================

    /**
     * @notice Get Total OI tier configuration
     */
    function getTotalOITierConfig()
        external
        view
        returns (
            uint16 totalOIRiskMultiplierBps,
            uint256 tier1Threshold,
            uint256 tier2Threshold,
            uint256 tier3Threshold,
            uint16 tier1MultiplierBps,
            uint16 tier2MultiplierBps,
            uint16 tier3MultiplierBps,
            uint16 tier4MultiplierBps
        );

    /**
     * @notice Get leverage tier configuration
     */
    function getLeverageTierConfig()
        external
        view
        returns (
            uint256 tier1Threshold,
            uint256 tier2Threshold,
            uint16 tier1MaxLeverage,
            uint16 tier2MaxLeverage,
            uint16 tier3MaxLeverage
        );

    /**
     * @notice Get utilization-based leverage configuration
     * @dev Controls how max leverage is reduced as vault utilization increases
     */
    function getUtilizationConfig()
        external
        view
        returns (
            uint16 tier1Bps,
            uint16 tier2Bps,
            uint16 tier3Bps,
            uint16 factorTier1Bps,
            uint16 factorTier2Bps,
            uint16 factorTier3Bps,
            uint16 factorEmergencyBps
        );

    // Note: getFeeConfig() is defined above in FEE-RELATED FUNCTIONS section

    /**
     * @notice Get funding rate configuration
     */
    function getFundingConfig()
        external
        view
        returns (
            uint16 tier1RateBps,
            uint16 tier2RateBps,
            uint16 tier3RateBps,
            uint16 tier4RateBps,
            uint16 tier5RateBps
        );

    /**
     * @notice Get last funding update timestamp
     */
    function lastFundingUpdateTime() external view returns (uint256);

    /**
     * @notice Check if funding rate is enabled
     */
    function fundingEnabled() external view returns (bool);

    /**
     * @notice Get cumulative funding rate for longs
     */
    function cumulativeFundingRateLong() external view returns (int256);

    /**
     * @notice Get cumulative funding rate for shorts
     */
    function cumulativeFundingRateShort() external view returns (int256);

    /**
     * @notice Get claimable rewards for a user
     */
    function claimableRewards(address user) external view returns (uint256);

    // ========================================================================
    // LP ARRAY STATE GETTERS (for VaultViewer)
    // ========================================================================

    /**
     * @notice Get LP address at index (auto-generated from public array)
     */
    function vaultLPs(uint256 index) external view returns (address);

    /**
     * @notice Get LP index (1-based) for address (auto-generated from public mapping)
     */
    function lpIndex(address lp) external view returns (uint256);

    /**
     * @notice Get pending payout queue item at index
     */
    function pendingPayoutQueue(uint256 index) external view returns (uint64);

    /**
     * @notice Get queue start index
     */
    function queueStartIndex() external view returns (uint256);

    // ========================================================================
    // EXPLICIT ARRAY LENGTH GETTERS
    // ========================================================================

    /**
     * @notice Get total number of active LPs in the vault
     * @return length Number of LPs in the vaultLPs array
     */
    function getVaultLPsLength() external view returns (uint256 length);

    /**
     * @notice Get total length of pending payout queue
     * @return length Total length of pendingPayoutQueue array
     */
    function getPendingPayoutQueueLength() external view returns (uint256 length);
}
