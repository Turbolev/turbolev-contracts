// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../DeployHelper.s.sol";
import "../../src/legacy/AssetVaultUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title InteractAssetVault
 * @notice Script to interact with AssetVaultUpgradeable contract
 * @dev Contains both user functions (addLiquidity, removeLiquidity, claimRewards)
 *      and admin functions (fee config, leverage, funding, etc.)
 */
contract InteractAssetVault is DeployHelper {
    AssetVaultUpgradeable public vault;

    function setUp() public override {
        super.setUp();
        address vaultAddr = vm.envAddress("VAULT_ADDRESS");
        require(vaultAddr != address(0), "VAULT_ADDRESS not set");
        vault = AssetVaultUpgradeable(payable(vaultAddr));
        console.log("Asset Vault Address:", address(vault));
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    function viewVaultInfo() public view {
        console.log("\n=== Vault Information ===");
        AssetVaultUpgradeable.VaultInfo memory info = vault.getVaultInfo();
        console.log("Total Liquidity:", info.totalLiquidity);
        console.log("Total Shares:", info.totalShares);
        console.log("Lifetime PnL:", info.lifetimePnL);
        console.log("Is Negative PnL:", info.isNegativePnL);
        console.log("Total Volume:", info.totalVolume);
        console.log("Is Graduated:", info.isGraduated);
        console.log("Trading Enabled:", info.tradingEnabled);
        console.log("Total Fees Collected:", info.totalFeesCollected);
    }

    function viewRiskControls() public view {
        console.log("\n=== Risk Controls ===");
        console.log("Max Directional Exposure BPS:", vault.maxDirectionalExposureBps());
        console.log("Total Long Exposure:", vault.totalLongExposure());
        console.log("Total Short Exposure:", vault.totalShortExposure());
        console.log("Tier1 Max Leverage:", vault.tier1MaxLeverage());
        console.log("Tier2 Max Leverage:", vault.tier2MaxLeverage());
        console.log("Tier3 Max Leverage:", vault.tier3MaxLeverage());
    }

    function viewFundingStatus() public view {
        console.log("\n=== Funding Rate Status ===");
        console.log("Funding Enabled:", vault.fundingEnabled());
        console.log("Cumulative Long Rate:", vault.cumulativeFundingRateLong());
        console.log("Cumulative Short Rate:", vault.cumulativeFundingRateShort());
        console.log("Last Funding Update Time:", vault.lastFundingUpdateTime());
    }

    function viewLPPosition(address user) public view {
        console.log("\n=== LP Position ===");
        AssetVaultUpgradeable.LPPosition memory lpPos = vault.getLPPosition(user);
        console.log("Shares:", lpPos.shares);
        console.log("Staked Amount:", lpPos.stakedAmount);
        console.log("Staked At:", lpPos.stakedAt);
        if (lpPos.shares > 0) {
            AssetVaultUpgradeable.VaultInfo memory info = vault.getVaultInfo();
            uint256 currentValue =
                info.totalShares > 0 ? (lpPos.shares * info.totalLiquidity) / info.totalShares : 0;
            console.log("Current Value:", currentValue);
        }
    }

    function viewFeeConfig() public view {
        console.log("\n=== Fee Configuration ===");
        console.log("Staking Fee BPS:", vault.stakingFeeBps());
        console.log("Early Withdrawal Fee BPS:", vault.earlyWithdrawalFeeBps());
        console.log("Open Position Fee BPS:", vault.openPositionFeeBps());
        console.log("Close Position Fee BPS:", vault.closePositionFeeBps());
    }

    function viewTotalOIConfig() public view {
        console.log("\n=== Total OI Configuration ===");
        console.log("Total OI Risk Multiplier BPS:", vault.totalOIRiskMultiplierBps());
        console.log("Tier 1 Threshold:", vault.tier1Threshold());
        console.log("Tier 2 Threshold:", vault.tier2Threshold());
        console.log("Tier 3 Threshold:", vault.tier3Threshold());
    }

    function viewLeverageConfig() public view {
        console.log("\n=== Leverage Configuration ===");
        console.log("Tier 1 Threshold:", vault.leverageTier1Threshold());
        console.log("Tier 2 Threshold:", vault.leverageTier2Threshold());
        console.log("Tier 1 Max:", vault.tier1MaxLeverage());
        console.log("Tier 2 Max:", vault.tier2MaxLeverage());
        console.log("Tier 3 Max:", vault.tier3MaxLeverage());
    }

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

    function viewDirectionalExposureConfig() public view {
        console.log("\n=== Directional Exposure Configuration ===");
        console.log("Max Directional Exposure BPS:", vault.maxDirectionalExposureBps());
        console.log("Total Long Exposure:", vault.totalLongExposure());
        console.log("Total Short Exposure:", vault.totalShortExposure());
    }

    function viewGraduationStatus() public view {
        console.log("\n=== Graduation Status ===");
        AssetVaultUpgradeable.VaultInfo memory info = vault.getVaultInfo();
        console.log("Is Graduated:", info.isGraduated);
        console.log("Graduation Threshold:", info.graduationThreshold);
        console.log("Total Liquidity:", info.totalLiquidity);
    }

    function viewTradingStatus() public view {
        console.log("\n=== Trading Status ===");
        AssetVaultUpgradeable.VaultInfo memory info = vault.getVaultInfo();
        console.log("Trading Enabled:", info.tradingEnabled);
    }

    function viewPauseStatus() public view {
        console.log("\n=== Pause Status ===");
        console.log("Is Paused:", vault.paused());
    }

    function viewAllConfigs() public view {
        console.log("\n========================================");
        console.log("ALL VAULT CONFIGURATIONS");
        console.log("========================================");

        viewVaultInfo();
        viewFeeConfig();
        viewTotalOIConfig();
        viewLeverageConfig();
        viewFundingConfig();
        viewDirectionalExposureConfig();
        viewGraduationStatus();
        viewTradingStatus();
        viewPauseStatus();

        console.log("\n========================================");
    }

    // ========================================================================
    // USER FUNCTIONS (LP Functions)
    // ========================================================================

    function addLiquidity(uint256 amount) public {
        vm.startBroadcast(deployer);
        address projectToken = vault.projectToken();
        if (projectToken != address(0)) {
            IERC20(projectToken).approve(address(vault), amount);
            vault.addLiquidity(amount);
        } else {
            vault.addLiquidity{ value: amount }(amount);
        }
        console.log("Liquidity added:", amount);
        vm.stopBroadcast();
    }

    function removeLiquidity() public {
        vm.startBroadcast(deployer);
        vault.removeLiquidity();
        console.log("Liquidity removed");
        vm.stopBroadcast();
    }

    function claimRewards() public {
        vm.startBroadcast(deployer);
        vault.claimRewards();
        console.log("Rewards claimed");
        vm.stopBroadcast();
    }

    // ========================================================================
    // ADMIN FUNCTIONS - Fee Configuration
    // ========================================================================

    /**
     * @notice Set fee by type: 0=staking, 1=earlyWithdrawal, 2=openPosition, 3=closePosition
     */
    function setFee(uint8 feeType, uint16 feeBps) public {
        vm.startBroadcast(deployer);
        vault.setFee(feeType, feeBps);
        string[4] memory feeNames =
            ["Staking", "Early Withdrawal", "Open Position", "Close Position"];
        console.log(feeNames[feeType], "fee updated to:", feeBps, "bps");
        vm.stopBroadcast();
    }

    /// @notice Convenience: Set staking fee (type 0)
    function setStakingFeeBps(uint16 feeBps) public {
        setFee(0, feeBps);
    }
    /// @notice Convenience: Set early withdrawal fee (type 1)

    function setEarlyWithdrawalFeeBps(uint16 feeBps) public {
        setFee(1, feeBps);
    }
    /// @notice Convenience: Set open position fee (type 2)

    function setOpenPositionFeeBps(uint16 feeBps) public {
        setFee(2, feeBps);
    }
    /// @notice Convenience: Set close position fee (type 3)

    function setClosePositionFeeBps(uint16 feeBps) public {
        setFee(3, feeBps);
    }

    // ========================================================================
    // ADMIN FUNCTIONS - Total OI Cap Configuration
    // ========================================================================

    /**
     * @notice Set OI tier config in one call
     * @param fixedMultiplier Fixed multiplier when tier disabled (0 to skip update)
     * @param thresholds [tier1, tier2, tier3] thresholds (all 0 to use fixed multiplier)
     * @param multipliers [tier1, tier2, tier3, tier4] multipliers in bps
     */
    function setOITierConfig(
        uint16 fixedMultiplier,
        uint256[3] calldata thresholds,
        uint16[4] calldata multipliers
    ) public {
        vm.startBroadcast(deployer);
        vault.setOITierConfig(fixedMultiplier, thresholds, multipliers);
        console.log("OI tier config updated");
        console.log("Fixed Multiplier:", fixedMultiplier);
        vm.stopBroadcast();
    }

    // ========================================================================
    // ADMIN FUNCTIONS - Leverage Configuration
    // ========================================================================

    /**
     * @notice Set leverage tier config in one call
     * @param t1Threshold TVL threshold for Growth Phase
     * @param t2Threshold TVL threshold for Mature Phase
     * @param t1Max Max leverage for Launch Phase
     * @param t2Max Max leverage for Growth Phase
     * @param t3Max Max leverage for Mature Phase
     */
    function setLeverageTierConfig(
        uint256 t1Threshold,
        uint256 t2Threshold,
        uint16 t1Max,
        uint16 t2Max,
        uint16 t3Max
    ) public {
        vm.startBroadcast(deployer);
        vault.setLeverageTierConfig(t1Threshold, t2Threshold, t1Max, t2Max, t3Max);
        console.log("Leverage tier config updated");
        vm.stopBroadcast();
    }

    /**
     * @notice Quick setup standard leverage tiers
     */
    function setupStandardLeverageTiers() public {
        setLeverageTierConfig(100_000 * 1e18, 500_000 * 1e18, 100, 200, 500);
        console.log("Standard: 100K/500K thresholds, 100x/200x/500x max leverage");
    }

    // ========================================================================
    // ADMIN FUNCTIONS - Funding Rate Configuration
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
     * @notice Update hourly funding rate (permissionless)
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
    // ADMIN FUNCTIONS - Directional Exposure
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

    // ========================================================================
    // ADMIN FUNCTIONS - Graduation
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

    // ========================================================================
    // ADMIN FUNCTIONS - Trading
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

    // ========================================================================
    // ADMIN FUNCTIONS - Pause/Unpause
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

    // ========================================================================
    // ADMIN FUNCTIONS - Admin Management
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
    // ADMIN FUNCTIONS - Treasury & Fees
    // ========================================================================

    /**
     * @notice Set treasury address for fee collection
     * @param treasury Treasury address
     */
    function setTreasury(address treasury) public {
        vm.startBroadcast(deployer);
        vault.setTreasury(treasury);
        console.log("Treasury set to:", treasury);
        vm.stopBroadcast();
    }

    /**
     * @notice Withdraw collected fees
     * @param amount Amount to withdraw (0 = withdraw all)
     */
    function withdrawFees(uint256 amount) public {
        vm.startBroadcast(deployer);
        vault.withdrawFees(amount);
        console.log("Fees withdrawn:", amount);
        vm.stopBroadcast();
    }
}
