// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../DeployHelper.s.sol";
import "../../src/AssetVault.sol";

/**
 * @title InteractAssetVault
 * @notice Script to interact with AssetVault contract
 * @dev Includes user functions, view functions and admin functions
 */
contract InteractAssetVault is DeployHelper {
    AssetVault public vault;

    function setUp() public override {
        super.setUp();

        // Load vault address from env
        address vaultAddr = vm.envAddress("VAULT_ADDRESS");
        require(vaultAddr != address(0), "Vault address not set");
        vault = AssetVault(payable(vaultAddr));

        console.log("Asset Vault Address:", address(vault));
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /**
     * @notice View vault information
     */
    function viewVaultInfo() public view {
        console.log("\n=== Vault Information ===");

        AssetVault.VaultInfo memory info = vault.getVaultInfo();

        console.log("Total Liquidity:", info.totalLiquidity);
        console.log("Total Shares:", info.totalShares);
        console.log("Lifetime PnL:", info.lifetimePnL);
        console.log("Is Negative PnL:", info.isNegativePnL);
        console.log("Total Volume:", info.totalVolume);
        console.log("Total Positions Settled:", info.totalPositionsSettled);
        console.log("Total Leverage Exposure:", info.totalLeverageExposure);
        console.log("Max Leverage Exposure:", info.maxLeverageExposure);
        console.log("Created At:", info.createdAt);
        console.log("Total Fees Collected:", info.totalFeesCollected);
        console.log("Total Staking Fees:", info.totalStakingFees);
        console.log("Total Withdrawal Fees:", info.totalWithdrawalFees);
        console.log("Is Graduated:", info.isGraduated);
        console.log("Graduation Threshold:", info.graduationThreshold);
        console.log("Graduated At:", info.graduatedAt);
        console.log("Trading Enabled:", info.tradingEnabled);
        console.log("Total Excess Profit:", info.totalExcessProfit);
        console.log("Pending Positions:", info.pendingPositions);
    }

    /**
     * @notice View vault parameters
     */
    function viewVaultParams() public view {
        console.log("\n=== Vault Parameters ===");

        AssetVault.VaultParams memory params = vault.getVaultParams();

        console.log("Max Payout BPS:", params.maxPayoutBps);
        console.log("Per Bet Util BPS:", params.perBetUtilBps);
        console.log("Max Utilization BPS:", params.maxUtilizationBps);
        console.log("Min Bet Amount:", params.minBetAmount);
        console.log("Max Bet Amount:", params.maxBetAmount);
        console.log("Max Leverage Exposure BPS:", params.maxLeverageExposureBps);
        console.log("Max Position Size Percent BPS:", params.maxPositionSizePercentBps);
        console.log("Min Liquidity Amount:", params.minLiquidityAmount);
    }

    /**
     * @notice View user LP position
     */
    function viewLPPosition(address user) public view {
        console.log("\n=== LP Position ===");
        console.log("User:", user);

        AssetVault.LPPosition memory lpPos = vault.getLPPosition(user);

        console.log("Shares:", lpPos.shares);
        console.log("Staked Amount:", lpPos.stakedAmount);
        console.log("Staked At:", lpPos.stakedAt);
        console.log("Last Reward Claim:", lpPos.lastRewardClaim);
        console.log("Total Rewards Claimed:", lpPos.totalRewardsClaimed);
        console.log("Last Processed Day:", lpPos.lastProcessedDay);
        console.log("Pending Rewards:", lpPos.pendingRewards);
    }

    /**
     * @notice Calculate share value
     */
    function calculateShareValue(uint256 shares) public view {
        console.log("\n=== Calculate Share Value ===");
        console.log("Shares:", shares);

        uint256 value = vault.calculateShareValue(shares);
        console.log("Value:", value);
    }

    /**
     * @notice Calculate pending rewards for user
     */
    function calculatePendingRewards(address user) public view {
        console.log("\n=== Calculate Pending Rewards ===");
        console.log("User:", user);

        (uint256 pendingRewards, uint256 processableDays) = vault.calculatePendingRewards(user);
        console.log("Pending Rewards:", pendingRewards);
        console.log("Processable Days:", processableDays);
    }

    /**
     * @notice Get remaining lock time
     */
    function getRemainingLockTime(address user) public view {
        console.log("\n=== Remaining Lock Time ===");
        console.log("User:", user);

        uint256 remaining = vault.getRemainingLockTime(user);
        console.log("Remaining Time (seconds):", remaining);
        console.log("Remaining Time (days):", remaining / 86_400);
    }

    /**
     * @notice Calculate withdrawal amount
     */
    function calculateWithdrawalAmount(address user, uint256 shares) public view {
        console.log("\n=== Calculate Withdrawal Amount ===");
        console.log("User:", user);
        console.log("Shares:", shares);

        (uint256 grossAmount, uint256 fee, uint256 netAmount, bool isEarlyWithdrawal) =
            vault.calculateWithdrawalAmount(user, shares);

        console.log("Gross Amount:", grossAmount);
        console.log("Fee:", fee);
        console.log("Net Amount:", netAmount);
        console.log("Is Early Withdrawal:", isEarlyWithdrawal);
    }

    /**
     * @notice Get vault value in USD
     */
    function getVaultValueUSD() public view {
        console.log("\n=== Vault Value USD ===");

        uint256 valueUSD = vault.getVaultValueUSD();
        console.log("Value USD:", valueUSD);
    }

    /**
     * @notice View fee configuration
     */
    function viewFeeConfig() public view {
        console.log("\n=== Fee Configuration ===");

        (uint16 stakingFeeBps, uint16 earlyWithdrawalFeeBps, uint256 minLockPeriod) =
            vault.getFeeConfig();

        console.log("Staking Fee BPS:", stakingFeeBps);
        console.log("Early Withdrawal Fee BPS:", earlyWithdrawalFeeBps);
        console.log("Min Lock Period (seconds):", minLockPeriod);
        console.log("Min Lock Period (days):", minLockPeriod / 86_400);
    }

    // ========================================================================
    // USER FUNCTIONS
    // ========================================================================

    /**
     * @notice Add liquidity to vault
     * @dev Requires token approval first if ERC20
     */
    function addLiquidity(uint256 amount) public {
        console.log("\n=== Add Liquidity ===");
        console.log("Amount:", amount);

        vm.startBroadcast(deployer);
        vault.addLiquidity(amount);
        console.log("Liquidity added successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Remove liquidity from vault
     */
    function removeLiquidity(uint256 shares) public {
        console.log("\n=== Remove Liquidity ===");
        console.log("Shares:", shares);

        vm.startBroadcast(deployer);
        vault.removeLiquidity(shares);
        console.log("Liquidity removed successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Claim rewards
     */
    function claimRewards() public {
        console.log("\n=== Claim Rewards ===");

        vm.startBroadcast(deployer);
        vault.claimRewards();
        console.log("Rewards claimed successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Process pending payouts manually
     */
    function processPendingPayouts() public {
        console.log("\n=== Process Pending Payouts ===");

        vm.startBroadcast(deployer);
        vault.processPendingPayouts();
        console.log("Pending payouts processed");
        vm.stopBroadcast();
    }

    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================

    /**
     * @notice Update vault parameters
     */
    function updateVaultParams(
        uint16 maxPayoutBps,
        uint16 perBetUtilBps,
        uint16 maxUtilizationBps,
        uint256 minBetAmount,
        uint256 maxBetAmount,
        uint16 maxLeverageExposureBps,
        uint16 maxPositionSizePercentBps
    ) public {
        console.log("\n=== Update Vault Parameters ===");

        vm.startBroadcast(deployer);
        vault.updateVaultParams(
            maxPayoutBps,
            perBetUtilBps,
            maxUtilizationBps,
            minBetAmount,
            maxBetAmount,
            maxLeverageExposureBps,
            maxPositionSizePercentBps
        );
        console.log("Vault parameters updated successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Set staking fee BPS
     */
    function setStakingFeeBps(uint16 newStakingFeeBps) public {
        console.log("\n=== Set Staking Fee BPS ===");
        console.log("New Staking Fee BPS:", newStakingFeeBps);

        vm.startBroadcast(deployer);
        vault.setStakingFeeBps(newStakingFeeBps);
        console.log("Staking fee BPS updated successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Set early withdrawal fee BPS
     */
    function setEarlyWithdrawalFeeBps(uint16 newEarlyWithdrawalFeeBps) public {
        console.log("\n=== Set Early Withdrawal Fee BPS ===");
        console.log("New Early Withdrawal Fee BPS:", newEarlyWithdrawalFeeBps);

        vm.startBroadcast(deployer);
        vault.setEarlyWithdrawalFeeBps(newEarlyWithdrawalFeeBps);
        console.log("Early withdrawal fee BPS updated successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Set graduation threshold
     */
    function setGraduationThreshold(uint256 newThreshold) public {
        console.log("\n=== Set Graduation Threshold ===");
        console.log("New Threshold:", newThreshold);

        vm.startBroadcast(deployer);
        vault.setGraduationThreshold(newThreshold);
        console.log("Graduation threshold updated successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Set trading enabled
     */
    function setTradingEnabled(bool enabled) public {
        console.log("\n=== Set Trading Enabled ===");
        console.log("Enabled:", enabled);

        vm.startBroadcast(deployer);
        vault.setTradingEnabled(enabled);
        console.log("Trading enabled status updated successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Set Blocksense Oracle address
     */
    function setBlocksenseOracle(address newOracle) public {
        console.log("\n=== Set Blocksense Oracle ===");
        console.log("New Oracle:", newOracle);

        vm.startBroadcast(deployer);
        vault.setBlocksenseOracle(newOracle);
        console.log("Blocksense Oracle updated successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Add backend address
     */
    function addBackend(address newBackend) public {
        console.log("\n=== Add Backend ===");
        console.log("New Backend:", newBackend);

        vm.startBroadcast(deployer);
        vault.addBackend(newBackend);
        console.log("Backend added successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Remove backend address
     */
    function removeBackend(address backendToRemove) public {
        console.log("\n=== Remove Backend ===");
        console.log("Backend to Remove:", backendToRemove);

        vm.startBroadcast(deployer);
        vault.removeBackend(backendToRemove);
        console.log("Backend removed successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Finalize daily reward
     */
    function finalizeDailyReward() public {
        console.log("\n=== Finalize Daily Reward ===");

        vm.startBroadcast(deployer);
        vault.finalizeDailyReward();
        console.log("Daily reward finalized successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Pause vault
     */
    function pauseVault() public {
        console.log("\n=== Pause Vault ===");

        vm.startBroadcast(deployer);
        vault.pause();
        console.log("Vault paused successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Unpause vault
     */
    function unpauseVault() public {
        console.log("\n=== Unpause Vault ===");

        vm.startBroadcast(deployer);
        vault.unpause();
        console.log("Vault unpaused successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Check and update graduation status
     */
    function checkGraduation() public {
        console.log("\n=== Check Graduation ===");

        vm.startBroadcast(deployer);
        vault.checkGraduation();
        console.log("Graduation check completed");
        vm.stopBroadcast();
    }
}
