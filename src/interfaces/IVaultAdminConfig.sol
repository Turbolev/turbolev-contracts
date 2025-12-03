// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IVaultAdminConfig
 * @notice Interface for VaultAdminConfig contract
 * @dev Logic-only contract used via delegatecall from vaults
 */
interface IVaultAdminConfig {
    /**
     * @notice Get minimum compatible vault version
     */
    function MIN_COMPATIBLE_VERSION() external view returns (uint256);

    /**
     * @notice Set fixed total OI risk multiplier
     * @param multiplierBps Risk multiplier in basis points (15000 = 1.5x)
     */
    function setTotalOIRiskMultiplier(uint16 multiplierBps) external;

    /**
     * @notice Set TVL tier thresholds for dynamic risk multiplier
     * @param tier1 Threshold for tier 1 (small vaults)
     * @param tier2 Threshold for tier 2 (medium vaults)
     * @param tier3 Threshold for tier 3 (large vaults)
     */
    function setTotalOITierThresholds(uint256 tier1, uint256 tier2, uint256 tier3) external;

    /**
     * @notice Set risk multipliers for each TVL tier
     * @param tier1Bps Multiplier for tier 1
     * @param tier2Bps Multiplier for tier 2
     * @param tier3Bps Multiplier for tier 3
     * @param tier4Bps Multiplier for tier 4
     */
    function setTotalOITierMultipliers(
        uint16 tier1Bps,
        uint16 tier2Bps,
        uint16 tier3Bps,
        uint16 tier4Bps
    ) external;

    /**
     * @notice Set leverage tier thresholds
     * @param tier1Threshold TVL threshold for Growth Phase
     * @param tier2Threshold TVL threshold for Mature Phase
     */
    function setLeverageTierThresholds(uint256 tier1Threshold, uint256 tier2Threshold) external;

    /**
     * @notice Set max leverage for each tier
     * @param tier1Max Max leverage for Launch Phase
     * @param tier2Max Max leverage for Growth Phase
     * @param tier3Max Max leverage for Mature Phase
     */
    function setLeverageTierMaxValues(uint16 tier1Max, uint16 tier2Max, uint16 tier3Max) external;

    /**
     * @notice Quick setup standard leverage tiers
     */
    function setupStandardLeverageTiers() external;

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
     * @notice Set maximum directional exposure cap
     * @param maxDirectionalExposureBps Max exposure in basis points
     */
    function setMaxDirectionalExposure(uint16 maxDirectionalExposureBps) external;

    /**
     * @notice Set staking fee
     * @param stakingFeeBps Fee in basis points
     */
    function setStakingFeeBps(uint16 stakingFeeBps) external;

    /**
     * @notice Set early withdrawal fee
     * @param earlyWithdrawalFeeBps Fee in basis points
     */
    function setEarlyWithdrawalFeeBps(uint16 earlyWithdrawalFeeBps) external;

    /**
     * @notice Set open position fee
     * @param openPositionFeeBps Fee in basis points
     */
    function setOpenPositionFeeBps(uint16 openPositionFeeBps) external;

    /**
     * @notice Set close position fee
     * @param closePositionFeeBps Fee in basis points
     */
    function setClosePositionFeeBps(uint16 closePositionFeeBps) external;

    /**
     * @notice Set graduation threshold
     * @param threshold Threshold in token amount
     */
    function setGraduationThreshold(uint256 threshold) external;

    /**
     * @notice Enable/disable trading
     * @param enabled Whether trading should be enabled
     */
    function setTradingEnabled(bool enabled) external;
}
