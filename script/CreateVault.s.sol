// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "./DeployHelper.s.sol";
import "../src/VaultManager.sol";
import "../src/AssetVaultUpgradeable.sol";

/**
 * @title CreateVault Script
 * @notice Script to create new asset vaults through VaultManager
 * @dev Usage: forge script script/CreateVault.s.sol:CreateVault --rpc-url $RPC_URL --broadcast
 */
contract CreateVault is DeployHelper {
    function run() public {
        require(vaultManager != address(0), "VaultManager not deployed");

        // Read vault configuration from environment
        address projectToken = vm.envAddress("PROJECT_TOKEN");
        require(projectToken != address(0), "PROJECT_TOKEN not set");

        uint256 minBetAmount = vm.envOr("MIN_BET_AMOUNT", MIN_BET_AMOUNT);
        uint256 maxBetAmount = vm.envOr("MAX_BET_AMOUNT", MAX_BET_AMOUNT);
        uint256 graduationThreshold =
            vm.envOr("GRADUATION_THRESHOLD_OVERRIDE", GRADUATION_THRESHOLD);

        console.log("\n=== Creating New Vault ===");
        console.log("Project Token:", projectToken);
        console.log("Min Bet Amount:", minBetAmount);
        console.log("Max Bet Amount:", maxBetAmount);
        console.log("Graduation Threshold:", graduationThreshold);

        VaultManager vm_ = VaultManager(payable(vaultManager));

        vm.startBroadcast(deployer);

        address newVault =
            vm_.createVaultWithBeacon(projectToken, minBetAmount, maxBetAmount, graduationThreshold);

        vm.stopBroadcast();

        console.log("\n=== Vault Created Successfully ===");
        console.log("New Vault Address:", newVault);

        // Verify vault info
        AssetVaultUpgradeable vault = AssetVaultUpgradeable(payable(newVault));
        AssetVaultUpgradeable.VaultInfo memory info = vault.getVaultInfo();
        console.log("\n=== Vault Info ===");
        console.log("Total Liquidity:", info.totalLiquidity);
        console.log("Trading Enabled:", info.tradingEnabled);
        console.log("Is Graduated:", info.isGraduated);
    }
}

/**
 * @title ViewVault Script
 * @notice Script to view vault information
 */
contract ViewVault is DeployHelper {
    function run() public view {
        address vaultAddr = vm.envAddress("VAULT_ADDRESS");
        require(vaultAddr != address(0), "VAULT_ADDRESS not set");

        AssetVaultUpgradeable vault = AssetVaultUpgradeable(payable(vaultAddr));

        console.log("\n=== Vault Information ===");
        console.log("Vault Address:", vaultAddr);

        AssetVaultUpgradeable.VaultInfo memory info = vault.getVaultInfo();
        console.log("Total Liquidity:", info.totalLiquidity);
        console.log("Total Shares:", info.totalShares);
        console.log("Lifetime PnL:", info.lifetimePnL);
        console.log("Is Negative PnL:", info.isNegativePnL);
        console.log("Total Volume:", info.totalVolume);
        console.log("Is Graduated:", info.isGraduated);
        console.log("Trading Enabled:", info.tradingEnabled);
        console.log("Total Fees Collected:", info.totalFeesCollected);

        console.log("\n=== Risk Controls ===");
        console.log("Max Directional Exposure BPS:", vault.maxDirectionalExposureBps());
        console.log("Total Long Exposure:", vault.totalLongExposure());
        console.log("Total Short Exposure:", vault.totalShortExposure());
        console.log("Tier1 Max Leverage:", vault.tier1MaxLeverage());
        console.log("Tier2 Max Leverage:", vault.tier2MaxLeverage());
        console.log("Tier3 Max Leverage:", vault.tier3MaxLeverage());

        console.log("\n=== Funding Status ===");
        console.log("Funding Enabled:", vault.fundingEnabled());
        console.log("Cumulative Long Rate:", vault.cumulativeFundingRateLong());
        console.log("Cumulative Short Rate:", vault.cumulativeFundingRateShort());
    }
}

/**
 * @title ListAllVaults Script
 * @notice Script to list all vaults from VaultManager
 */
contract ListAllVaults is DeployHelper {
    function run() public view {
        require(vaultManager != address(0), "VaultManager not deployed");

        VaultManager vm_ = VaultManager(payable(vaultManager));
        address[] memory vaults = vm_.getAllVaults();

        console.log("\n=== All Vaults ===");
        console.log("Total vaults:", vaults.length);

        for (uint256 i = 0; i < vaults.length; i++) {
            address vaultAddr = vaults[i];
            AssetVaultUpgradeable vault = AssetVaultUpgradeable(payable(vaultAddr));
            AssetVaultUpgradeable.VaultInfo memory info = vault.getVaultInfo();

            console.log("\n--- Vault", i, "---");
            console.log("Address:", vaultAddr);
            console.log("Project Token:", vault.projectToken());
            console.log("Total Liquidity:", info.totalLiquidity);
            console.log("Is Graduated:", info.isGraduated);
            console.log("Trading Enabled:", info.tradingEnabled);
        }
    }
}
