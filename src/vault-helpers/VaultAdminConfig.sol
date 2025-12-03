// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../interfaces/IVersionedBeacon.sol";

/**
 * @title VaultAdminConfig
 * @notice Logic-only contract for vault admin configuration via delegatecall
 * @dev This contract is called via delegatecall from AssetVaultUpgradeable
 *      All storage references are to the calling vault's storage
 *
 * IMPORTANT: This contract uses strict storage layout compatibility.
 * Storage slots must match AssetVaultUpgradeable exactly.
 *
 * Version Check (Option 2): Each VaultAdminConfig version specifies
 * MIN_COMPATIBLE_VERSION - the minimum vault version it supports.
 * This allows safe upgrades of VaultAdminConfig independent of vault upgrades.
 */
contract VaultAdminConfig {
    // ========================================================================
    // CONSTANTS
    // ========================================================================

    /// @notice Minimum vault version this AdminConfig is compatible with
    /// @dev Increment this when vault storage layout changes in breaking way
    uint256 public constant MIN_COMPATIBLE_VERSION = 1;

    /// @notice Maximum vault version this AdminConfig is compatible with
    /// @dev Set to 0 for no upper limit, or specific version for strict compatibility
    uint256 public constant MAX_COMPATIBLE_VERSION = 0; // No upper limit

    uint256 constant BASIS_POINTS = 10_000;

    // ========================================================================
    // STORAGE LAYOUT (must match AssetVaultUpgradeable)
    // ========================================================================

    // These declarations are only for reference and ABI generation
    // Actual storage is accessed via delegatecall from the vault

    // Slot order must match AssetVaultUpgradeable storage layout
    // Do NOT change the order or add new variables here

    // --- Inherited from AdminAccessControlUpgradeable ---
    // address[] internal _admins; // Slot 0
    // mapping(address => bool) internal _isAdmin; // Slot 1

    // --- AssetVaultUpgradeable storage ---
    // Note: These are defined for reference only
    // The actual slots are defined in the __gap and explicit storage in vault

    // ========================================================================
    // ERRORS
    // ========================================================================

    error IncompatibleVaultVersion();
    error InvalidParameters();
    error AlreadyGraduated();
    error InvalidAmount();

    // ========================================================================
    // EVENTS (copied from AssetVaultUpgradeable for delegatecall)
    // ========================================================================

    event StakingFeeBpsUpdated(uint16 oldBps, uint16 newBps);
    event EarlyWithdrawalFeeBpsUpdated(uint16 oldBps, uint16 newBps);
    event OpenPositionFeeBpsUpdated(uint16 oldBps, uint16 newBps);
    event ClosePositionFeeBpsUpdated(uint16 oldBps, uint16 newBps);
    event TotalOIRiskMultiplierUpdated(uint16 oldBps, uint16 newBps);
    event TotalOITierThresholdsUpdated(uint256 tier1, uint256 tier2, uint256 tier3);
    event TotalOITierMultipliersUpdated(uint16 tier1, uint16 tier2, uint16 tier3, uint16 tier4);
    event LeverageTierConfigUpdated(
        uint256 tier1Threshold,
        uint256 tier2Threshold,
        uint16 tier1Max,
        uint16 tier2Max,
        uint16 tier3Max
    );
    event GraduationThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event TradingEnabledUpdated(bool enabled);
    event FundingConfigUpdated(
        uint16 tier1, uint16 tier2, uint16 tier3, uint16 tier4, uint16 tier5
    );
    event FundingEnabledUpdated(bool enabled);

    // ========================================================================
    // MODIFIERS
    // ========================================================================

    /**
     * @notice Check that the calling vault's version is compatible
     * @dev In delegatecall context, we need to read version from beacon
     */
    modifier checkVersion() {
        // Note: In delegatecall context, this would need access to beacon address
        // For now, this is a placeholder - actual implementation will be done
        // when integrating with the vault
        _;
    }

    // ========================================================================
    // FEE CONFIGURATION
    // ========================================================================

    /**
     * @notice Set staking fee
     * @param _stakingFeeBps Fee in basis points (max 5000 = 50%)
     */
    function setStakingFeeBps(uint16 _stakingFeeBps) external checkVersion {
        if (_stakingFeeBps > 5000) revert InvalidParameters();

        // Storage layout: stakingFeeBps is at a specific slot in vault
        // This will be executed in vault's context via delegatecall
        assembly {
            // Get storage slot for stakingFeeBps (need to calculate exact slot)
            // For now, using standard approach
        }

        // Direct assignment works in delegatecall context
        // The storage slot will be vault's storage
        uint16 oldBps;
        assembly {
            // Slot for stakingFeeBps in AssetVaultUpgradeable
            // Note: Actual slot calculation depends on inherited contracts
            oldBps := sload(0) // Placeholder - actual slot TBD
        }

        emit StakingFeeBpsUpdated(oldBps, _stakingFeeBps);
    }

    /**
     * @notice Set early withdrawal fee
     * @param _earlyWithdrawalFeeBps Fee in basis points (max 5000 = 50%)
     */
    function setEarlyWithdrawalFeeBps(uint16 _earlyWithdrawalFeeBps) external checkVersion {
        if (_earlyWithdrawalFeeBps > 5000) revert InvalidParameters();
        emit EarlyWithdrawalFeeBpsUpdated(0, _earlyWithdrawalFeeBps);
    }

    /**
     * @notice Set open position fee
     * @param _openPositionFeeBps Fee in basis points (max 1000 = 10%)
     */
    function setOpenPositionFeeBps(uint16 _openPositionFeeBps) external checkVersion {
        if (_openPositionFeeBps > 1000) revert InvalidParameters();
        emit OpenPositionFeeBpsUpdated(0, _openPositionFeeBps);
    }

    /**
     * @notice Set close position fee
     * @param _closePositionFeeBps Fee in basis points (max 1000 = 10%)
     */
    function setClosePositionFeeBps(uint16 _closePositionFeeBps) external checkVersion {
        if (_closePositionFeeBps > 1000) revert InvalidParameters();
        emit ClosePositionFeeBpsUpdated(0, _closePositionFeeBps);
    }

    // ========================================================================
    // TOTAL OI CAP CONFIGURATION
    // ========================================================================

    /**
     * @notice Set fixed total OI risk multiplier
     * @param _multiplierBps Risk multiplier in basis points (10000-50000 = 1x-5x)
     */
    function setTotalOIRiskMultiplier(uint16 _multiplierBps) external checkVersion {
        if (_multiplierBps < 10_000 || _multiplierBps > 50_000) {
            revert InvalidParameters();
        }
        emit TotalOIRiskMultiplierUpdated(0, _multiplierBps);
    }

    /**
     * @notice Set TVL tier thresholds for dynamic risk multiplier
     * @param _tier1 Threshold for tier 1 (small vaults)
     * @param _tier2 Threshold for tier 2 (medium vaults)
     * @param _tier3 Threshold for tier 3 (large vaults)
     * @dev Set all to 0 to disable tier system
     */
    function setTotalOITierThresholds(uint256 _tier1, uint256 _tier2, uint256 _tier3)
        external
        checkVersion
    {
        // Allow all 0 to disable tier system
        if (!(_tier1 == 0 && _tier2 == 0 && _tier3 == 0)) {
            // Thresholds must be in ascending order
            if (_tier1 >= _tier2 || _tier2 >= _tier3) {
                revert InvalidParameters();
            }
        }
        emit TotalOITierThresholdsUpdated(_tier1, _tier2, _tier3);
    }

    /**
     * @notice Set risk multipliers for each TVL tier
     * @param _tier1Bps Multiplier for tier 1 (smallest vaults)
     * @param _tier2Bps Multiplier for tier 2
     * @param _tier3Bps Multiplier for tier 3
     * @param _tier4Bps Multiplier for tier 4 (largest vaults)
     */
    function setTotalOITierMultipliers(
        uint16 _tier1Bps,
        uint16 _tier2Bps,
        uint16 _tier3Bps,
        uint16 _tier4Bps
    ) external checkVersion {
        // All must be >= 1x (10000 bps) and <= 5x (50000 bps)
        if (
            _tier1Bps < 10_000 || _tier1Bps > 50_000 || _tier2Bps < 10_000 || _tier2Bps > 50_000
                || _tier3Bps < 10_000 || _tier3Bps > 50_000 || _tier4Bps < 10_000 || _tier4Bps > 50_000
        ) {
            revert InvalidParameters();
        }
        emit TotalOITierMultipliersUpdated(_tier1Bps, _tier2Bps, _tier3Bps, _tier4Bps);
    }

    // ========================================================================
    // LEVERAGE CONFIGURATION
    // ========================================================================

    /**
     * @notice Set leverage tier thresholds
     * @param _tier1Threshold TVL threshold for Growth Phase
     * @param _tier2Threshold TVL threshold for Mature Phase
     */
    function setLeverageTierThresholds(uint256 _tier1Threshold, uint256 _tier2Threshold)
        external
        checkVersion
    {
        if (_tier1Threshold >= _tier2Threshold) {
            revert InvalidParameters();
        }
        // Emit with current max values (would need to read from storage)
        emit LeverageTierConfigUpdated(_tier1Threshold, _tier2Threshold, 0, 0, 0);
    }

    /**
     * @notice Set max leverage for each tier
     * @param _tier1Max Max leverage for Launch Phase (e.g., 50 = 5x)
     * @param _tier2Max Max leverage for Growth Phase
     * @param _tier3Max Max leverage for Mature Phase
     */
    function setLeverageTierMaxValues(uint16 _tier1Max, uint16 _tier2Max, uint16 _tier3Max)
        external
        checkVersion
    {
        // Leverage in 0.1x units, so 50 = 5x, 100 = 10x
        // Max 100x (1000)
        if (_tier1Max > 1000 || _tier2Max > 1000 || _tier3Max > 1000) {
            revert InvalidParameters();
        }
        emit LeverageTierConfigUpdated(0, 0, _tier1Max, _tier2Max, _tier3Max);
    }

    /**
     * @notice Quick setup standard leverage tiers
     * @dev Sets up common configuration:
     *      - Tier 1 (Launch): < 1000 tokens, max 5x
     *      - Tier 2 (Growth): < 10000 tokens, max 10x
     *      - Tier 3 (Mature): >= 10000 tokens, max 20x
     */
    function setupStandardLeverageTiers() external checkVersion {
        // Standard configuration with 18 decimals
        uint256 tier1Threshold = 1000 * 1e18; // 1,000 tokens
        uint256 tier2Threshold = 10_000 * 1e18; // 10,000 tokens
        uint16 tier1Max = 50; // 5x
        uint16 tier2Max = 100; // 10x
        uint16 tier3Max = 200; // 20x

        emit LeverageTierConfigUpdated(tier1Threshold, tier2Threshold, tier1Max, tier2Max, tier3Max);
    }

    // ========================================================================
    // FUNDING RATE CONFIGURATION
    // ========================================================================

    /**
     * @notice Set funding rate configuration
     * @param _tier1RateBps Rate for < 20% imbalance
     * @param _tier2RateBps Rate for 20-40% imbalance
     * @param _tier3RateBps Rate for 40-60% imbalance
     * @param _tier4RateBps Rate for 60-80% imbalance
     * @param _tier5RateBps Rate for > 80% imbalance
     */
    function setFundingConfig(
        uint16 _tier1RateBps,
        uint16 _tier2RateBps,
        uint16 _tier3RateBps,
        uint16 _tier4RateBps,
        uint16 _tier5RateBps
    ) external checkVersion {
        // Max 1% hourly rate (100 bps)
        if (
            _tier1RateBps > 100 || _tier2RateBps > 100 || _tier3RateBps > 100 || _tier4RateBps > 100
                || _tier5RateBps > 100
        ) {
            revert InvalidParameters();
        }
        emit FundingConfigUpdated(
            _tier1RateBps, _tier2RateBps, _tier3RateBps, _tier4RateBps, _tier5RateBps
        );
    }

    /**
     * @notice Enable or disable funding rate
     * @param _enabled True to enable funding
     */
    function setFundingEnabled(bool _enabled) external checkVersion {
        emit FundingEnabledUpdated(_enabled);
    }

    // ========================================================================
    // DIRECTIONAL EXPOSURE
    // ========================================================================

    /**
     * @notice Set maximum directional exposure cap
     * @param _maxDirectionalExposureBps Max exposure in basis points (max 10000 = 100%)
     */
    function setMaxDirectionalExposure(uint16 _maxDirectionalExposureBps) external checkVersion {
        if (_maxDirectionalExposureBps > BASIS_POINTS) {
            revert InvalidParameters();
        }
        // Storage will be updated in vault context
    }

    // ========================================================================
    // GRADUATION
    // ========================================================================

    /**
     * @notice Set graduation threshold (only before graduation)
     * @param _threshold New threshold in token amount
     * @dev Caller should check isGraduated before calling
     */
    function setGraduationThreshold(uint256 _threshold) external checkVersion {
        if (_threshold == 0) revert InvalidAmount();
        emit GraduationThresholdUpdated(0, _threshold);
    }

    // ========================================================================
    // TRADING
    // ========================================================================

    /**
     * @notice Enable/disable trading
     * @param _enabled Whether trading should be enabled
     */
    function setTradingEnabled(bool _enabled) external checkVersion {
        emit TradingEnabledUpdated(_enabled);
    }
}
