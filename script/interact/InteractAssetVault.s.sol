// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../DeployHelper.s.sol";
import "../../src/AssetVaultUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract InteractAssetVault is DeployHelper {
    AssetVaultUpgradeable public vault;

    function setUp() public override {
        super.setUp();
        address vaultAddr = vm.envAddress("VAULT_ADDRESS");
        require(vaultAddr != address(0), "Vault address not set");
        vault = AssetVaultUpgradeable(payable(vaultAddr));
        console.log("Asset Vault Address:", address(vault));
    }

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
    // NOTE: Admin functions have been moved to InteractVaultAdminConfig.s.sol
    // ========================================================================
    // The following admin functions are now available in InteractVaultAdminConfig:
    // - setMaxDirectionalExposure()
    // - setLeverageTierMaxValues()
    // - setFundingEnabled()
    // - updateHourlyFunding()
    // - pauseVault() / unpauseVault()
    // - All other admin configuration functions
    // ========================================================================
}
