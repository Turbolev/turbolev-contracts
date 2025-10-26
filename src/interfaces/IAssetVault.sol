// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IAssetVault
 * @notice Interface for AssetVault contract
 */
interface IAssetVault {
    struct VaultInfo {
        address tokenAddress;
        uint256 totalLiquidity;
        uint256 activeLiquidity;
        uint256 reservedLiquidity;
        uint256 totalShares;
        uint256 lifetimePnL;
        bool isNegativePnL;
        uint256 totalVolume;
        uint256 totalPositionsSettled;
        uint256 totalLeverageExposure;
        uint256 maxLeverageExposure;
        bool isPaused;
        bool isInitialized;
        uint256 createdAt;
        // Fee tracking (new in Phase 1)
        uint256 totalFeesCollected;
        uint256 totalStakingFees;
        uint256 totalWithdrawalFees;
        // Graduation (Phase 2)
        bool isGraduated;
        uint256 graduationThreshold; // Token amount threshold (not USD)
        uint256 graduatedAt;
        bool tradingEnabled;
        // Trading Caps (Phase 3)
        uint256 totalExcessProfit;
    }

    struct VaultParams {
        uint16 maxPayoutBps;
        uint16 perBetUtilBps;
        uint16 maxUtilizationBps;
        uint256 minBetAmount;
        uint256 maxBetAmount;
        uint16 maxLeverageExposureBps;
        uint16 maxPositionSizePercentBps; // Phase 5: Max position size as % of TVL
        uint256 minLiquidityAmount; // REFACTOR: Min liquidity deposit
    }

    // Phase 5: Open Interest tracking per asset
    struct AssetOIInfo {
        uint256 totalOI; // Total Open Interest for this asset
        uint256 longOI; // OI from LONG positions
        uint256 shortOI; // OI from SHORT positions
        uint256 maxOI; // Max OI allowed for this asset
        uint256 positionCount; // Number of open positions
    }

    struct LPPosition {
        address user;
        uint256 shares;
        uint256 stakedAmount;
        uint256 stakedAt;
        uint256 lastRewardClaim;
        uint256 totalRewardsClaimed;
        uint256 lastProcessedDay; // Phase 4
        uint256 pendingRewards; // Phase 4
    }

    // Phase 4: Daily Snapshot for Staker Rewards
    struct DailySnapshot {
        uint256 day;
        uint256 totalLiquidity;
        uint256 totalShares;
        int256 netPnL;
        uint256 totalPositionsSettled;
        bool isProcessed;
        uint256 timestamp;
        uint64[] positionIds; // All position IDs settled this day
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
     * @param amount Collateral amount
     * @param positionSize Position size
     * @param priceFeedId Pyth price feed ID of asset being bet on
     * @param direction Position direction (1=LONG, 2=SHORT)
     */
    function depositFromBet(
        uint256 amount,
        uint256 positionSize,
        bytes32 priceFeedId,
        uint8 direction
    ) external payable;

    /**
     * @notice Execute payout to user
     * @param user User address
     * @param amount Payout amount
     */
    function executePayout(address user, uint256 amount) external;

    /**
     * @notice Update vault P&L
     * @param positionId Position ID (for tracking)
     * @param collateral Collateral amount
     * @param vaultPnL Vault P&L
     * @param fee Fee collected
     * @param positionSize Position size
     * @param excessProfit Excess profit from capped trades
     * @param priceFeedId Pyth price feed ID of the asset
     * @param direction Position direction (1=LONG, 2=SHORT)
     */
    function updateVaultPnL(
        uint64 positionId,
        uint256 collateral,
        int256 vaultPnL,
        uint256 fee,
        uint256 positionSize,
        uint256 excessProfit,
        bytes32 priceFeedId,
        uint8 direction
    ) external;

    /**
     * @notice Check position risk
     * @param positionSize Position size
     * @param leverage Leverage multiplier
     * @param priceFeedId Pyth price feed ID of asset being bet on
     * @return canOpen Whether position can be opened
     * @return reason Reason if cannot open
     */
    function checkPositionRisk(
        uint256 positionSize,
        uint8 leverage,
        bytes32 priceFeedId
    ) external view returns (bool canOpen, string memory reason);

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
    function getLPPosition(
        address user
    ) external view returns (LPPosition memory);

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
    // FEE-RELATED FUNCTIONS (Phase 1)
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
    function calculateWithdrawalAmount(
        address user,
        uint256 shares
    )
        external
        view
        returns (
            uint256 grossAmount,
            uint256 fee,
            uint256 netAmount,
            bool isEarlyWithdrawal
        );

    /**
     * @notice Get fee configuration
     * @return stakingFeeBps Staking fee in basis points
     * @return earlyWithdrawalFeeBps Early withdrawal fee in basis points
     * @return minLockPeriod Minimum lock period in seconds
     */
    function getFeeConfig()
        external
        view
        returns (
            uint16 stakingFeeBps,
            uint16 earlyWithdrawalFeeBps,
            uint256 minLockPeriod
        );

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
    // GRADUATION FUNCTIONS (Phase 2)
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
     * @notice Set Pyth Oracle address
     * @param pythOracle Pyth Oracle contract address
     */
    function setPythOracle(address pythOracle) external;

    // ========================================================================
    // PHASE 4: STAKER REWARD FUNCTIONS
    // ========================================================================

    /**
     * @notice Finalize daily rewards and take snapshot
     * @dev Called by backend bot at end of each day
     */
    function finalizeDailyReward() external;

    /**
     * @notice Calculate pending rewards for a staker
     * @param user Address of staker
     * @return pendingRewards Total pending rewards
     * @return processableDays Number of days that can be processed
     */
    function calculatePendingRewards(
        address user
    ) external view returns (uint256 pendingRewards, uint256 processableDays);

    /**
     * @notice Claim pending rewards
     */
    function claimRewards() external;

    /**
     * @notice Compound pending rewards back into vault
     */
    function compoundRewards() external;

    /**
     * @notice Add a backend bot address
     * @param backend Backend bot address to add
     */
    function addBackend(address backend) external;

    /**
     * @notice Remove a backend bot address
     * @param backend Backend bot address to remove
     */
    function removeBackend(address backend) external;

    /**
     * @notice Check if an address is a backend
     * @param account Address to check
     * @return bool True if address is a backend
     */
    function isBackend(address account) external view returns (bool);

    /**
     * @notice Get all backend addresses
     * @return address[] Array of backend addresses
     */
    function getBackends() external view returns (address[] memory);

    /**
     * @notice Get number of backends
     * @return uint256 Number of backend addresses
     */
    function getBackendCount() external view returns (uint256);

    /**
     * @notice Get daily snapshot details
     * @param day Day number
     * @return snapshot Daily snapshot data
     */
    function getDailySnapshot(
        uint256 day
    ) external view returns (DailySnapshot memory snapshot);

    /**
     * @notice Get position IDs settled in a specific day
     * @param day Day number
     * @return positionIds Array of position IDs
     */
    function getDailyPositionIds(
        uint256 day
    ) external view returns (uint64[] memory positionIds);

    /**
     * @notice Get current day's position IDs (before snapshot)
     * @return positionIds Array of position IDs settled today
     */
    function getCurrentDailyPositionIds()
        external
        view
        returns (uint64[] memory positionIds);

    // ========================================================================
    // PHASE 5: OPEN INTEREST FUNCTIONS
    // ========================================================================

    /**
     * @notice Get Open Interest info for a specific asset
     * @param priceFeedId Pyth price feed ID
     * @return assetOI Asset OI information
     */
    function getAssetOI(
        bytes32 priceFeedId
    ) external view returns (AssetOIInfo memory assetOI);

    /**
     * @notice Get all tracked assets with open positions
     * @return assets Array of price feed IDs
     */
    function getTrackedAssets() external view returns (bytes32[] memory assets);

    /**
     * @notice Get OI utilization rate for a specific asset
     * @param priceFeedId Pyth price feed ID
     * @return utilizationBps OI utilization in basis points (0-10000)
     */
    function getAssetOIUtilization(
        bytes32 priceFeedId
    ) external view returns (uint256 utilizationBps);

    /**
     * @notice Get LONG/SHORT imbalance for a specific asset
     * @param priceFeedId Pyth price feed ID
     * @return imbalance Difference between LONG and SHORT OI
     * @return imbalancePercent Imbalance as percentage of total OI (in bps)
     */
    function getAssetOIImbalance(
        bytes32 priceFeedId
    ) external view returns (int256 imbalance, int256 imbalancePercent);

    /**
     * @notice Get total OI across all assets
     * @return totalOI Sum of all asset OIs
     */
    function getTotalOIAllAssets() external view returns (uint256 totalOI);

    /**
     * @notice Set max Open Interest for a specific asset
     * @param priceFeedId Pyth price feed ID
     * @param maxOI Maximum Open Interest allowed
     */
    function setAssetMaxOI(bytes32 priceFeedId, uint256 maxOI) external;

    /**
     * @notice Set max OI for multiple assets at once
     * @param priceFeedIds Array of price feed IDs
     * @param maxOIs Array of max OI values
     */
    function setAssetMaxOIBatch(
        bytes32[] calldata priceFeedIds,
        uint256[] calldata maxOIs
    ) external;
}
