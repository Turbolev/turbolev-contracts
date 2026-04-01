// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IVaultRouter
 * @notice Interface for VaultRouter contract (modular vault system)
 * @dev Used by VaultViewerModular to query vault data
 */
interface IVaultRouter {
    // ========================================================================
    // STRUCTS
    // ========================================================================

    struct VaultInfo {
        uint256 totalLiquidity;
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

    // ========================================================================
    // VAULT INFO GETTERS
    // ========================================================================

    function getVaultInfo() external view returns (VaultInfo memory);
    function getVaultParams() external view returns (VaultParams memory);
    function getLPPosition(address user) external view returns (LPPosition memory);
    function projectToken() external view returns (address);
    function paused() external view returns (bool);
    function vaultManager() external view returns (address);
    function positionManager() external view returns (address);
    function tradingEnabled() external view returns (bool);
    function isGraduated() external view returns (bool);
    function withdrawableFees() external view returns (uint256);
    function feePool() external view returns (uint256);

    // ========================================================================
    // EXPOSURE GETTERS
    // ========================================================================

    function totalLongExposure() external view returns (uint256);
    function totalShortExposure() external view returns (uint256);
    function maxDirectionalExposureBps() external view returns (uint16);

    // ========================================================================
    // PRICE IMPACT GETTERS
    // ========================================================================

    function getExecutionPrice(uint256 markPrice, uint8 direction, uint256 positionSize)
        external
        view
        returns (uint256 executionPrice, uint256 impactFee, uint256 impactBps, bool isCrowdedSide);
    function getCurrentImpactRate()
        external
        view
        returns (uint256 impactBps, bool isLongDominant, uint256 imbalanceBps);
    function getImpactStats()
        external
        view
        returns (
            uint256 longExposure,
            uint256 shortExposure,
            uint256 currentImpactBps,
            bool isLongDominant,
            uint256 imbalanceBps,
            uint256 totalFeesCollected
        );
    function isImpactEnabled() external view returns (bool);
    function getImpactConfig() external view returns (uint16, uint16, uint16, uint16, uint16);
    function totalImpactFeesCollected() external view returns (uint256);

    // ========================================================================
    // RISK CONFIG GETTERS
    // ========================================================================

    function getTotalOITierConfig()
        external
        view
        returns (
            uint16 fixedMultiplier,
            uint256 tier1Threshold,
            uint256 tier2Threshold,
            uint256 tier3Threshold,
            uint16 tier1Multiplier,
            uint16 tier2Multiplier,
            uint16 tier3Multiplier,
            uint16 tier4Multiplier
        );

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

    function getFeeConfig()
        external
        view
        returns (uint16 stakingFeeBps, uint16 earlyWithdrawalFeeBps, uint256 minLockPeriod);

    // ========================================================================
    // LP ARRAY GETTERS
    // ========================================================================

    function getVaultLPsLength() external view returns (uint256);
    function vaultLPs(uint256 index) external view returns (address);
    function lpIndex(address account) external view returns (uint256);

    // ========================================================================
    // PAYOUT QUEUE GETTERS
    // ========================================================================

    function getPendingPayoutQueueLength() external view returns (uint256);
    function queueStartIndex() external view returns (uint256);

    // ========================================================================
    // REWARDS GETTERS
    // ========================================================================

    function claimableRewards(address user) external view returns (uint256);
    function calculatePendingRewards(address user) external view returns (uint256);
    function currentDay() external view returns (uint256);
    function lastSnapshotDay() external view returns (uint256);

    // ========================================================================
    // WRITE FUNCTIONS (used by VaultManager)
    // ========================================================================

    function depositFromBet(
        uint64 positionId,
        uint256 amount,
        uint256 positionSize,
        bool isMarginAdd,
        uint8 direction
    ) external payable;

    function executePayout(address user, uint256 amount, uint64 positionId) external;

    function updateVaultPnL(
        uint64 positionId,
        uint256 collateral,
        int256 vaultPnL,
        uint256 positionSize,
        uint8 direction,
        address user
    ) external returns (uint256 closeFee);

    function checkPositionRisk(uint256 positionSize, uint16 leverage, uint8 direction) external view;

    function setTradingEnabled(bool enabled) external;
    function setPositionManager(address positionManager) external;
    function pause() external;
    function unpause() external;

    // ========================================================================
    // ADMIN FUNCTIONS (used by VaultAdminProxy)
    // ========================================================================

    function setFee(uint8 feeType, uint16 feeBps) external;
    function setTreasury(address treasury) external;
    function setGraduationThreshold(uint256 threshold) external;
    function withdrawFees(uint256 amount) external;
    function updateVaultParams(uint256 minBetAmount, uint256 maxBetAmount) external;
    function recordImpactFee(
        uint64 positionId,
        address user,
        uint8 direction,
        uint256 markPrice,
        uint256 executionPrice,
        uint256 impactBps,
        uint256 impactFee,
        bool isCrowdedSide
    ) external;
    function setImpactConfig(
        uint16 tier1ImpactBps,
        uint16 tier2ImpactBps,
        uint16 tier3ImpactBps,
        uint16 tier4ImpactBps,
        uint16 tier5ImpactBps
    ) external;
    function setImpactEnabled(bool enabled) external;

    // ========================================================================
    // RISK CONFIG SETTERS (used by VaultAdminProxy)
    // ========================================================================

    function setLeverageTierConfig(
        uint256 tier1Threshold,
        uint256 tier2Threshold,
        uint16 tier1MaxLeverage,
        uint16 tier2MaxLeverage,
        uint16 tier3MaxLeverage
    ) external;

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

    function setMaxDirectionalExposure(uint16 maxDirectionalExposureBps) external;

    function setUtilizationConfig(
        uint16 tier1Bps,
        uint16 tier2Bps,
        uint16 tier3Bps,
        uint16 factorTier1Bps,
        uint16 factorTier2Bps,
        uint16 factorTier3Bps,
        uint16 factorEmergencyBps
    ) external;

    function setMaxProfitCapMultiplier(uint8 multiplier) external;

    function getMaxProfitCapMultiplier() external view returns (uint8);

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
}
