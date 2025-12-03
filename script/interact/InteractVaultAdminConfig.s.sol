// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../DeployHelper.s.sol";
import "../../src/AssetVaultUpgradeable.sol";

/**
 * @title InteractVaultAdminConfig
 * @notice Script to interact with vault admin configuration functions
 * @dev All admin functions are called directly on AssetVaultUpgradeable
 *      Functions are organized by category matching VaultAdminConfig interface
 */
contract InteractVaultAdminConfig is DeployHelper {
    AssetVaultUpgradeable public vault;

    function setUp() public override {
        super.setUp();
        address vaultAddr = vm.envAddress("VAULT_ADDRESS");
        require(vaultAddr != address(0), "VAULT_ADDRESS not set");
        vault = AssetVaultUpgradeable(payable(vaultAddr));
        console.log("Vault Address:", address(vault));
    }

    // ========================================================================
    // FEE CONFIGURATION
    // ========================================================================

    /**
     * @notice Set staking fee
     * @param stakingFeeBps Fee in basis points (max 1000 = 10%)
     */
    function setStakingFeeBps(uint16 stakingFeeBps) public {
        vm.startBroadcast(deployer);
        vault.setStakingFeeBps(stakingFeeBps);
        console.log("Staking fee updated to:", stakingFeeBps, "bps");
        vm.stopBroadcast();
    }

    /**
     * @notice Set early withdrawal fee
     * @param earlyWithdrawalFeeBps Fee in basis points (max 5000 = 50%)
     */
    function setEarlyWithdrawalFeeBps(uint16 earlyWithdrawalFeeBps) public {
        vm.startBroadcast(deployer);
        vault.setEarlyWithdrawalFeeBps(earlyWithdrawalFeeBps);
        console.log("Early withdrawal fee updated to:", earlyWithdrawalFeeBps, "bps");
        vm.stopBroadcast();
    }

    /**
     * @notice Set open position fee
     * @param openPositionFeeBps Fee in basis points (max 1000 = 10%)
     */
    function setOpenPositionFeeBps(uint16 openPositionFeeBps) public {
        vm.startBroadcast(deployer);
        vault.setOpenPositionFeeBps(openPositionFeeBps);
        console.log("Open position fee updated to:", openPositionFeeBps, "bps");
        vm.stopBroadcast();
    }

    /**
     * @notice Set close position fee
     * @param closePositionFeeBps Fee in basis points (max 1000 = 10%)
     */
    function setClosePositionFeeBps(uint16 closePositionFeeBps) public {
        vm.startBroadcast(deployer);
        vault.setClosePositionFeeBps(closePositionFeeBps);
        console.log("Close position fee updated to:", closePositionFeeBps, "bps");
        vm.stopBroadcast();
    }

    /**
     * @notice View current fee configuration
     */
    function viewFeeConfig() public view {
        console.log("\n=== Fee Configuration ===");
        console.log("Staking Fee BPS:", vault.stakingFeeBps());
        console.log("Early Withdrawal Fee BPS:", vault.earlyWithdrawalFeeBps());
        console.log("Open Position Fee BPS:", vault.openPositionFeeBps());
        console.log("Close Position Fee BPS:", vault.closePositionFeeBps());
    }

    // ========================================================================
    // TOTAL OI CAP CONFIGURATION
    // ========================================================================

    /**
     * @notice Set fixed total OI risk multiplier
     * @param multiplierBps Risk multiplier in basis points (10000-50000 = 1x-5x)
     */
    function setTotalOIRiskMultiplier(uint16 multiplierBps) public {
        vm.startBroadcast(deployer);
        vault.setTotalOIRiskMultiplier(multiplierBps);
        console.log("Total OI risk multiplier updated to:", multiplierBps, "bps");
        vm.stopBroadcast();
    }

    /**
     * @notice Set TVL tier thresholds for dynamic risk multiplier
     * @param tier1 Threshold for tier 1 (small vaults)
     * @param tier2 Threshold for tier 2 (medium vaults)
     * @param tier3 Threshold for tier 3 (large vaults)
     */
    function setTotalOITierThresholds(uint256 tier1, uint256 tier2, uint256 tier3) public {
        vm.startBroadcast(deployer);
        vault.setTotalOITierThresholds(tier1, tier2, tier3);
        console.log("Total OI tier thresholds updated");
        console.log("Tier 1:", tier1);
        console.log("Tier 2:", tier2);
        console.log("Tier 3:", tier3);
        vm.stopBroadcast();
    }

    /**
     * @notice Set risk multipliers for each TVL tier
     * @param tier1Bps Multiplier for tier 1 (smallest vaults)
     * @param tier2Bps Multiplier for tier 2
     * @param tier3Bps Multiplier for tier 3
     * @param tier4Bps Multiplier for tier 4 (largest vaults)
     */
    function setTotalOITierMultipliers(
        uint16 tier1Bps,
        uint16 tier2Bps,
        uint16 tier3Bps,
        uint16 tier4Bps
    ) public {
        vm.startBroadcast(deployer);
        vault.setTotalOITierMultipliers(tier1Bps, tier2Bps, tier3Bps, tier4Bps);
        console.log("Total OI tier multipliers updated");
        console.log("Tier 1:", tier1Bps, "bps");
        console.log("Tier 2:", tier2Bps, "bps");
        console.log("Tier 3:", tier3Bps, "bps");
        console.log("Tier 4:", tier4Bps, "bps");
        vm.stopBroadcast();
    }

    /**
     * @notice View current total OI configuration
     */
    function viewTotalOIConfig() public view {
        console.log("\n=== Total OI Configuration ===");
        (
            uint16 fixedMultiplier,
            uint256 t1,
            uint256 t2,
            uint256 t3,
            uint16 m1,
            uint16 m2,
            uint16 m3,
            uint16 m4
        ) = vault.getTotalOITierConfig();
        console.log("Fixed Multiplier BPS:", fixedMultiplier);
        console.log("Tier 1 Threshold:", t1);
        console.log("Tier 2 Threshold:", t2);
        console.log("Tier 3 Threshold:", t3);
        console.log("Tier 1 Multiplier BPS:", m1);
        console.log("Tier 2 Multiplier BPS:", m2);
        console.log("Tier 3 Multiplier BPS:", m3);
        console.log("Tier 4 Multiplier BPS:", m4);
    }

    // ========================================================================
    // LEVERAGE CONFIGURATION
    // ========================================================================

    /**
     * @notice Set leverage tier thresholds
     * @param tier1Threshold TVL threshold for Growth Phase
     * @param tier2Threshold TVL threshold for Mature Phase
     */
    function setLeverageTierThresholds(uint256 tier1Threshold, uint256 tier2Threshold) public {
        vm.startBroadcast(deployer);
        vault.setLeverageTierThresholds(tier1Threshold, tier2Threshold);
        console.log("Leverage tier thresholds updated");
        console.log("Tier 1 Threshold:", tier1Threshold);
        console.log("Tier 2 Threshold:", tier2Threshold);
        vm.stopBroadcast();
    }

    /**
     * @notice Set max leverage for each tier
     * @param tier1Max Max leverage for Launch Phase
     * @param tier2Max Max leverage for Growth Phase
     * @param tier3Max Max leverage for Mature Phase
     */
    function setLeverageTierMaxValues(uint16 tier1Max, uint16 tier2Max, uint16 tier3Max) public {
        vm.startBroadcast(deployer);
        vault.setLeverageTierMaxValues(tier1Max, tier2Max, tier3Max);
        console.log("Leverage tier max values updated");
        console.log("Tier 1 Max:", tier1Max);
        console.log("Tier 2 Max:", tier2Max);
        console.log("Tier 3 Max:", tier3Max);
        vm.stopBroadcast();
    }

    /**
     * @notice Quick setup standard leverage tiers
     */
    function setupStandardLeverageTiers() public {
        vm.startBroadcast(deployer);
        vault.setupStandardLeverageTiers();
        console.log("Standard leverage tiers setup completed");
        vm.stopBroadcast();
    }

    /**
     * @notice View current leverage configuration
     */
    function viewLeverageConfig() public view {
        console.log("\n=== Leverage Configuration ===");
        (uint256 t1Threshold, uint256 t2Threshold, uint16 t1Max, uint16 t2Max, uint16 t3Max) =
            vault.getLeverageTierConfig();
        console.log("Tier 1 Threshold:", t1Threshold);
        console.log("Tier 2 Threshold:", t2Threshold);
        console.log("Tier 1 Max Leverage:", t1Max);
        console.log("Tier 2 Max Leverage:", t2Max);
        console.log("Tier 3 Max Leverage:", t3Max);
    }

    // ========================================================================
    // FUNDING RATE CONFIGURATION
    // ========================================================================

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
    ) public {
        vm.startBroadcast(deployer);
        vault.setFundingConfig(tier1RateBps, tier2RateBps, tier3RateBps, tier4RateBps, tier5RateBps);
        console.log("Funding config updated");
        console.log("Tier 1 Rate BPS:", tier1RateBps);
        console.log("Tier 2 Rate BPS:", tier2RateBps);
        console.log("Tier 3 Rate BPS:", tier3RateBps);
        console.log("Tier 4 Rate BPS:", tier4RateBps);
        console.log("Tier 5 Rate BPS:", tier5RateBps);
        vm.stopBroadcast();
    }

    /**
     * @notice Enable or disable funding rate
     * @param enabled True to enable funding
     */
    function setFundingEnabled(bool enabled) public {
        vm.startBroadcast(deployer);
        vault.setFundingEnabled(enabled);
        console.log("Funding enabled:", enabled);
        vm.stopBroadcast();
    }

    /**
     * @notice View current funding configuration
     */
    function viewFundingConfig() public view {
        console.log("\n=== Funding Configuration ===");
        console.log("Funding Enabled:", vault.fundingEnabled());
        (uint16 t1, uint16 t2, uint16 t3, uint16 t4, uint16 t5) = vault.getFundingConfig();
        console.log("Tier 1 Rate BPS:", t1);
        console.log("Tier 2 Rate BPS:", t2);
        console.log("Tier 3 Rate BPS:", t3);
        console.log("Tier 4 Rate BPS:", t4);
        console.log("Tier 5 Rate BPS:", t5);
    }

    // ========================================================================
    // DIRECTIONAL EXPOSURE
    // ========================================================================

    /**
     * @notice Set maximum directional exposure cap
     * @param maxDirectionalExposureBps Max exposure in basis points (max 10000 = 100%)
     */
    function setMaxDirectionalExposure(uint16 maxDirectionalExposureBps) public {
        vm.startBroadcast(deployer);
        vault.setMaxDirectionalExposure(maxDirectionalExposureBps);
        console.log("Max directional exposure updated to:", maxDirectionalExposureBps, "bps");
        vm.stopBroadcast();
    }

    /**
     * @notice View current directional exposure settings
     */
    function viewDirectionalExposureConfig() public view {
        console.log("\n=== Directional Exposure Configuration ===");
        console.log("Max Directional Exposure BPS:", vault.maxDirectionalExposureBps());
        console.log("Total Long Exposure:", vault.totalLongExposure());
        console.log("Total Short Exposure:", vault.totalShortExposure());
    }

    // ========================================================================
    // GRADUATION
    // ========================================================================

    /**
     * @notice Set graduation threshold (only before graduation)
     * @param threshold New threshold in token amount
     */
    function setGraduationThreshold(uint256 threshold) public {
        vm.startBroadcast(deployer);
        vault.setGraduationThreshold(threshold);
        console.log("Graduation threshold updated to:", threshold);
        vm.stopBroadcast();
    }

    /**
     * @notice View graduation status
     */
    function viewGraduationStatus() public view {
        console.log("\n=== Graduation Status ===");
        AssetVaultUpgradeable.VaultInfo memory info = vault.getVaultInfo();
        console.log("Is Graduated:", info.isGraduated);
        console.log("Graduation Threshold:", info.graduationThreshold);
        console.log("Total Liquidity:", info.totalLiquidity);
    }

    // ========================================================================
    // TRADING
    // ========================================================================

    /**
     * @notice Enable/disable trading
     * @param enabled Whether trading should be enabled
     */
    function setTradingEnabled(bool enabled) public {
        vm.startBroadcast(deployer);
        vault.setTradingEnabled(enabled);
        console.log("Trading enabled:", enabled);
        vm.stopBroadcast();
    }

    /**
     * @notice View trading status
     */
    function viewTradingStatus() public view {
        console.log("\n=== Trading Status ===");
        AssetVaultUpgradeable.VaultInfo memory info = vault.getVaultInfo();
        console.log("Trading Enabled:", info.tradingEnabled);
    }

    // ========================================================================
    // PAUSE/UNPAUSE FUNCTIONS
    // ========================================================================

    /**
     * @notice Pause the vault (emergency function)
     */
    function pauseVault() public {
        vm.startBroadcast(deployer);
        vault.pause();
        console.log("Vault paused");
        vm.stopBroadcast();
    }

    /**
     * @notice Unpause the vault
     */
    function unpauseVault() public {
        vm.startBroadcast(deployer);
        vault.unpause();
        console.log("Vault unpaused");
        vm.stopBroadcast();
    }

    /**
     * @notice View pause status
     */
    function viewPauseStatus() public view {
        console.log("\n=== Pause Status ===");
        console.log("Is Paused:", vault.paused());
    }

    // ========================================================================
    // FUNDING UPDATE FUNCTIONS
    // ========================================================================

    /**
     * @notice Update hourly funding rate (admin only)
     * @dev Can only be called once per hour
     */
    function updateHourlyFunding() public {
        vm.startBroadcast(deployer);
        (int256 newLongRate, int256 newShortRate, uint256 imbalanceBps, bool hasCounterparty) =
            vault.updateHourlyFunding();
        console.log("Hourly funding updated");
        console.log("New Long Rate:", uint256(newLongRate));
        console.log("New Short Rate:", uint256(newShortRate));
        console.log("Imbalance BPS:", imbalanceBps);
        console.log("Has Counterparty:", hasCounterparty);
        vm.stopBroadcast();
    }

    // ========================================================================
    // ADMIN MANAGEMENT
    // ========================================================================

    /**
     * @notice Add an admin to the vault
     * @param admin Admin address to add
     */
    function addAdmin(address admin) public {
        vm.startBroadcast(deployer);
        vault.addAdmin(admin);
        console.log("Admin added:", admin);
        vm.stopBroadcast();
    }

    /**
     * @notice Remove an admin from the vault
     * @param admin Admin address to remove
     */
    function removeAdmin(address admin) public {
        vm.startBroadcast(deployer);
        vault.removeAdmin(admin);
        console.log("Admin removed:", admin);
        vm.stopBroadcast();
    }

    // ========================================================================
    // COMPREHENSIVE VIEW FUNCTIONS
    // ========================================================================

    /**
     * @notice View all admin configurations
     */
    function viewAllConfigs() public view {
        console.log("\n========================================");
        console.log("ALL ADMIN CONFIGURATIONS");
        console.log("========================================");

        viewFeeConfig();
        viewTotalOIConfig();
        viewLeverageConfig();
        viewFundingConfig();
        viewDirectionalExposureConfig();
        viewGraduationStatus();
        viewTradingStatus();

        console.log("\n========================================");
    }

    /**
     * @notice View risk control configurations
     */
    function viewRiskControls() public view {
        console.log("\n========================================");
        console.log("RISK CONTROL CONFIGURATIONS");
        console.log("========================================");

        viewTotalOIConfig();
        viewLeverageConfig();
        viewDirectionalExposureConfig();

        console.log("\n========================================");
    }
}
