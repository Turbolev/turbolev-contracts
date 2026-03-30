// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../math/MathLib.sol";

/**
 * @title VaultConfigLib
 * @notice Library containing all vault configuration constants and structs
 * @dev Centralizes configuration management for AssetVaultUpgradeable
 *      - Constants: Immutable system limits and defaults
 *      - Structs: Configurable parameters that can be updated by admin
 *      - Default helpers: Functions to get default configurations
 *      - BASIS_POINTS consolidated to MathLib.BASIS_POINTS (I-V3-06)
 */
library VaultConfigLib {
    // ========================================================================
    // SYSTEM CONSTANTS
    // ========================================================================

    uint256 constant INITIAL_SHARE_MULTIPLIER = 1e18;

    // ========================================================================
    // TIME CONSTANTS
    // ========================================================================

    uint256 constant MIN_LOCK_PERIOD = 30 days;
    uint256 constant REWARD_MIN_STAKE_PERIOD = 1 days;

    // ========================================================================
    // PROCESSING LIMITS
    // ========================================================================

    uint256 constant MAX_CATCHUP_HOURS = 2;
    uint256 constant MAX_PAYOUTS_PER_TX = 50;
    uint8 constant MAX_PAYOUT_RETRIES = 3;
    uint256 constant MAX_DAYS_PER_CALCULATION = 365;
    uint256 constant MAX_LPS_PER_FINALIZE = 200;

    // ========================================================================
    // FEE BOUNDS
    // ========================================================================

    uint16 constant MAX_STAKING_FEE_BPS = 200; // 2%
    uint16 constant MAX_EARLY_WITHDRAWAL_FEE_BPS = 2000; // 20%
    uint16 constant MIN_POSITION_FEE_BPS = 1; // 0.01%
    uint16 constant MAX_POSITION_FEE_BPS = 100; // 1%

    // ========================================================================
    // DEFAULT VALUES - FEE CONFIG
    // ========================================================================

    uint16 constant DEFAULT_STAKING_FEE_BPS = 0;
    uint16 constant DEFAULT_EARLY_WITHDRAWAL_FEE_BPS = 1000; // 10%
    uint16 constant DEFAULT_OPEN_POSITION_FEE_BPS = 5; // 0.05%
    uint16 constant DEFAULT_CLOSE_POSITION_FEE_BPS = 5; // 0.05%

    // ========================================================================
    // DEFAULT VALUES - LEVERAGE TIER CONFIG
    // ========================================================================

    uint256 constant DEFAULT_LEVERAGE_TIER1_THRESHOLD = 100_000 * 1e18;
    uint256 constant DEFAULT_LEVERAGE_TIER2_THRESHOLD = 500_000 * 1e18;
    uint16 constant DEFAULT_TIER1_MAX_LEVERAGE = 10;
    uint16 constant DEFAULT_TIER2_MAX_LEVERAGE = 10;
    uint16 constant DEFAULT_TIER3_MAX_LEVERAGE = 10;

    // ========================================================================
    // DEFAULT VALUES - OI TIER CONFIG
    // ========================================================================

    uint16 constant DEFAULT_TOTAL_OI_RISK_MULTIPLIER_BPS = 15_000; // 1.5x
    uint16 constant DEFAULT_OI_TIER1_MULTIPLIER_BPS = 15_000; // 1.5x
    uint16 constant DEFAULT_OI_TIER2_MULTIPLIER_BPS = 15_000; // 1.5x
    uint16 constant DEFAULT_OI_TIER3_MULTIPLIER_BPS = 15_000; // 1.5x
    uint16 constant DEFAULT_OI_TIER4_MULTIPLIER_BPS = 15_000; // 1.5x

    // ========================================================================
    // DEFAULT VALUES - RISK CONFIG
    // ========================================================================

    uint16 constant DEFAULT_MAX_DIRECTIONAL_EXPOSURE_BPS = 2500; // 25%

    // ========================================================================
    // DEFAULT VALUES - MAX PROFIT CAP CONFIG
    // ========================================================================

    uint8 constant DEFAULT_MAX_PROFIT_CAP_MULTIPLIER = 2; // 2x collateral
    uint8 constant MIN_MAX_PROFIT_CAP_MULTIPLIER = 1; // 1x minimum
    uint8 constant MAX_MAX_PROFIT_CAP_MULTIPLIER = 10; // 10x maximum

    // ========================================================================
    // RISK CONTROL BOUNDS
    // ========================================================================

    uint16 constant MAX_LEVERAGE_ALLOWED = 1000; // Safety cap for max leverage
    uint16 constant MIN_DIRECTIONAL_EXPOSURE_BPS = 1000; // 10% minimum
    uint16 constant MAX_DIRECTIONAL_EXPOSURE_BPS = 10_000; // 100% maximum

    // ========================================================================
    // DEFAULT VALUES - UTILIZATION CONFIG (for leverage adjustment)
    // ========================================================================

    /// @dev Utilization thresholds in basis points
    uint16 constant DEFAULT_UTILIZATION_TIER1_BPS = 3000; // 30%
    uint16 constant DEFAULT_UTILIZATION_TIER2_BPS = 6000; // 60%
    uint16 constant DEFAULT_UTILIZATION_TIER3_BPS = 8000; // 80%

    /// @dev Leverage factors in basis points (percentage of base leverage)
    uint16 constant DEFAULT_LEVERAGE_FACTOR_TIER1_BPS = 10_000; // 100% - Full leverage
    uint16 constant DEFAULT_LEVERAGE_FACTOR_TIER2_BPS = 5000; // 50% - Half leverage
    uint16 constant DEFAULT_LEVERAGE_FACTOR_TIER3_BPS = 2000; // 20% - 1/5 leverage
    uint16 constant DEFAULT_LEVERAGE_FACTOR_EMERGENCY_BPS = 400; // 4% - Emergency mode

    // ========================================================================
    // CONFIG STRUCTS
    // ========================================================================

    /**
     * @notice Fee configuration for deposits, withdrawals, and positions
     * @param stakingFeeBps Fee charged on deposits (basis points)
     * @param earlyWithdrawalFeeBps Penalty for early withdrawal (basis points)
     * @param openPositionFeeBps Fee charged when opening position (basis points)
     * @param closePositionFeeBps Fee charged when closing position (basis points)
     */
    struct FeeConfig {
        uint16 stakingFeeBps;
        uint16 earlyWithdrawalFeeBps;
        uint16 openPositionFeeBps;
        uint16 closePositionFeeBps;
    }

    /**
     * @notice Leverage tier configuration based on vault TVL
     * @dev Max leverage increases as vault grows (more mature = higher leverage allowed)
     * @param tier1Threshold TVL threshold for tier 1 (Launch Phase)
     * @param tier2Threshold TVL threshold for tier 2 (Growth Phase)
     * @param tier1MaxLeverage Max leverage for TVL < tier1Threshold
     * @param tier2MaxLeverage Max leverage for tier1Threshold <= TVL < tier2Threshold
     * @param tier3MaxLeverage Max leverage for TVL >= tier2Threshold (Mature Phase)
     */
    struct LeverageTierConfig {
        uint256 tier1Threshold;
        uint256 tier2Threshold;
        uint16 tier1MaxLeverage;
        uint16 tier2MaxLeverage;
        uint16 tier3MaxLeverage;
    }

    /**
     * @notice Total OI tier configuration for risk multiplier based on TVL
     * @dev Risk multiplier determines max total OI as percentage of TVL
     * @param fixedMultiplierBps Fixed multiplier when tiers disabled (0 thresholds)
     * @param tier1Threshold Small vault threshold
     * @param tier2Threshold Medium vault threshold
     * @param tier3Threshold Large vault threshold
     * @param tier1MultiplierBps Multiplier for TVL < tier1 (e.g., 15000 = 1.5x)
     * @param tier2MultiplierBps Multiplier for tier1 <= TVL < tier2
     * @param tier3MultiplierBps Multiplier for tier2 <= TVL < tier3
     * @param tier4MultiplierBps Multiplier for TVL >= tier3
     */
    struct OITierConfig {
        uint16 fixedMultiplierBps;
        uint256 tier1Threshold;
        uint256 tier2Threshold;
        uint256 tier3Threshold;
        uint16 tier1MultiplierBps;
        uint16 tier2MultiplierBps;
        uint16 tier3MultiplierBps;
        uint16 tier4MultiplierBps;
    }

    /**
     * @notice Risk control configuration
     * @param maxDirectionalExposureBps Max net directional exposure as % of TVL
     */
    struct RiskConfig {
        uint16 maxDirectionalExposureBps;
    }

    /**
     * @notice Utilization-based leverage adjustment configuration
     * @dev Reduces max leverage as vault utilization increases
     *
     * Utilization Tiers (thresholds in basis points):
     * - Below tier1Bps: Full leverage (factorTier1Bps)
     * - tier1Bps to tier2Bps: Reduced leverage (factorTier2Bps)
     * - tier2Bps to tier3Bps: Further reduced (factorTier3Bps)
     * - Above tier3Bps: Emergency mode (factorEmergencyBps)
     *
     * @param tier1Bps Threshold for full leverage (default 30%)
     * @param tier2Bps Threshold for reduced leverage (default 60%)
     * @param tier3Bps Threshold for emergency mode (default 80%)
     * @param factorTier1Bps Leverage factor below tier1 (default 100%)
     * @param factorTier2Bps Leverage factor tier1-tier2 (default 50%)
     * @param factorTier3Bps Leverage factor tier2-tier3 (default 20%)
     * @param factorEmergencyBps Leverage factor above tier3 (default 4%)
     */
    struct UtilizationConfig {
        uint16 tier1Bps;
        uint16 tier2Bps;
        uint16 tier3Bps;
        uint16 factorTier1Bps;
        uint16 factorTier2Bps;
        uint16 factorTier3Bps;
        uint16 factorEmergencyBps;
    }

    // ========================================================================
    // DEFAULT CONFIG HELPERS
    // ========================================================================

    /**
     * @notice Returns default fee configuration
     * @return config Default FeeConfig struct
     */
    function getDefaultFeeConfig() internal pure returns (FeeConfig memory config) {
        return FeeConfig({
            stakingFeeBps: DEFAULT_STAKING_FEE_BPS,
            earlyWithdrawalFeeBps: DEFAULT_EARLY_WITHDRAWAL_FEE_BPS,
            openPositionFeeBps: DEFAULT_OPEN_POSITION_FEE_BPS,
            closePositionFeeBps: DEFAULT_CLOSE_POSITION_FEE_BPS
        });
    }

    /**
     * @notice Returns default leverage tier configuration
     * @return config Default LeverageTierConfig struct
     */
    function getDefaultLeverageTierConfig()
        internal
        pure
        returns (LeverageTierConfig memory config)
    {
        return LeverageTierConfig({
            tier1Threshold: DEFAULT_LEVERAGE_TIER1_THRESHOLD,
            tier2Threshold: DEFAULT_LEVERAGE_TIER2_THRESHOLD,
            tier1MaxLeverage: DEFAULT_TIER1_MAX_LEVERAGE,
            tier2MaxLeverage: DEFAULT_TIER2_MAX_LEVERAGE,
            tier3MaxLeverage: DEFAULT_TIER3_MAX_LEVERAGE
        });
    }

    /**
     * @notice Returns default OI tier configuration
     * @return config Default OITierConfig struct
     */
    function getDefaultOITierConfig() internal pure returns (OITierConfig memory config) {
        return OITierConfig({
            fixedMultiplierBps: DEFAULT_TOTAL_OI_RISK_MULTIPLIER_BPS,
            tier1Threshold: 0,
            tier2Threshold: 0,
            tier3Threshold: 0,
            tier1MultiplierBps: DEFAULT_OI_TIER1_MULTIPLIER_BPS,
            tier2MultiplierBps: DEFAULT_OI_TIER2_MULTIPLIER_BPS,
            tier3MultiplierBps: DEFAULT_OI_TIER3_MULTIPLIER_BPS,
            tier4MultiplierBps: DEFAULT_OI_TIER4_MULTIPLIER_BPS
        });
    }

    /**
     * @notice Returns default risk configuration
     * @return config Default RiskConfig struct
     */
    function getDefaultRiskConfig() internal pure returns (RiskConfig memory config) {
        return RiskConfig({ maxDirectionalExposureBps: DEFAULT_MAX_DIRECTIONAL_EXPOSURE_BPS });
    }

    /**
     * @notice Returns default utilization configuration
     * @return config Default UtilizationConfig struct
     */
    function getDefaultUtilizationConfig() internal pure returns (UtilizationConfig memory config) {
        return UtilizationConfig({
            tier1Bps: DEFAULT_UTILIZATION_TIER1_BPS,
            tier2Bps: DEFAULT_UTILIZATION_TIER2_BPS,
            tier3Bps: DEFAULT_UTILIZATION_TIER3_BPS,
            factorTier1Bps: DEFAULT_LEVERAGE_FACTOR_TIER1_BPS,
            factorTier2Bps: DEFAULT_LEVERAGE_FACTOR_TIER2_BPS,
            factorTier3Bps: DEFAULT_LEVERAGE_FACTOR_TIER3_BPS,
            factorEmergencyBps: DEFAULT_LEVERAGE_FACTOR_EMERGENCY_BPS
        });
    }

    // ========================================================================
    // VALIDATION HELPERS
    // ========================================================================

    /**
     * @notice Validate fee configuration
     * @param config FeeConfig to validate
     * @return valid True if configuration is valid
     */
    function validateFeeConfig(FeeConfig memory config) internal pure returns (bool valid) {
        if (config.stakingFeeBps > MAX_STAKING_FEE_BPS) return false;
        if (config.earlyWithdrawalFeeBps > MAX_EARLY_WITHDRAWAL_FEE_BPS) return false;
        if (config.openPositionFeeBps < MIN_POSITION_FEE_BPS) return false;
        if (config.openPositionFeeBps > MAX_POSITION_FEE_BPS) return false;
        if (config.closePositionFeeBps < MIN_POSITION_FEE_BPS) return false;
        if (config.closePositionFeeBps > MAX_POSITION_FEE_BPS) return false;
        return true;
    }

    /**
     * @notice Validate leverage tier configuration
     * @param config LeverageTierConfig to validate
     * @return valid True if configuration is valid
     */
    function validateLeverageTierConfig(LeverageTierConfig memory config)
        internal
        pure
        returns (bool valid)
    {
        // tier2 must be >= tier1
        if (config.tier2Threshold < config.tier1Threshold) return false;
        // Leverage must be positive
        if (config.tier1MaxLeverage == 0) return false;
        if (config.tier2MaxLeverage == 0) return false;
        if (config.tier3MaxLeverage == 0) return false;
        // Leverage must not exceed safety cap
        if (config.tier1MaxLeverage > MAX_LEVERAGE_ALLOWED) return false;
        if (config.tier2MaxLeverage > MAX_LEVERAGE_ALLOWED) return false;
        if (config.tier3MaxLeverage > MAX_LEVERAGE_ALLOWED) return false;
        return true;
    }

    /**
     * @notice Validate max profit cap multiplier
     * @param multiplier Max profit cap multiplier to validate
     * @return valid True if multiplier is valid
     */
    function validateMaxProfitCapMultiplier(uint8 multiplier) internal pure returns (bool valid) {
        return
            multiplier >= MIN_MAX_PROFIT_CAP_MULTIPLIER
                && multiplier <= MAX_MAX_PROFIT_CAP_MULTIPLIER;
    }

    /**
     * @notice Validate directional exposure bps
     * @param exposureBps Directional exposure in basis points
     * @return valid True if exposure is valid
     */
    function validateDirectionalExposure(uint16 exposureBps) internal pure returns (bool valid) {
        return
            exposureBps >= MIN_DIRECTIONAL_EXPOSURE_BPS
                && exposureBps <= MAX_DIRECTIONAL_EXPOSURE_BPS;
    }

    /**
     * @notice Validate OI tier configuration
     * @param config OITierConfig to validate
     * @return valid True if configuration is valid
     */
    function validateOITierConfig(OITierConfig memory config) internal pure returns (bool valid) {
        // Fixed multiplier must be positive
        if (config.fixedMultiplierBps == 0) return false;
        // If using tiers, they must be in order
        if (config.tier1Threshold > 0 || config.tier2Threshold > 0 || config.tier3Threshold > 0) {
            if (config.tier2Threshold < config.tier1Threshold) return false;
            if (config.tier3Threshold < config.tier2Threshold) return false;
        }
        // All multipliers must be positive
        if (config.tier1MultiplierBps == 0) return false;
        if (config.tier2MultiplierBps == 0) return false;
        if (config.tier3MultiplierBps == 0) return false;
        if (config.tier4MultiplierBps == 0) return false;
        return true;
    }

    /**
     * @notice Validate utilization configuration
     * @param config UtilizationConfig to validate
     * @return valid True if configuration is valid
     */
    function validateUtilizationConfig(UtilizationConfig memory config)
        internal
        pure
        returns (bool valid)
    {
        // Tiers must be in ascending order
        if (config.tier2Bps < config.tier1Bps) return false;
        if (config.tier3Bps < config.tier2Bps) return false;
        // Factors must be positive (except emergency which can be very low)
        if (config.factorTier1Bps == 0) return false;
        // Factors should decrease as utilization increases
        if (config.factorTier2Bps > config.factorTier1Bps) return false;
        if (config.factorTier3Bps > config.factorTier2Bps) return false;
        if (config.factorEmergencyBps > config.factorTier3Bps) return false;
        return true;
    }
}
