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
        console.log("Created At:", info.createdAt);
        console.log("Total Fees Collected:", info.totalFeesCollected);
        console.log("Total Staking Fees:", info.totalStakingFees);
        console.log("Total Withdrawal Fees:", info.totalWithdrawalFees);
        console.log("Is Graduated:", info.isGraduated);
        console.log("Graduation Threshold:", info.graduationThreshold);
        console.log("Graduated At:", info.graduatedAt);
        console.log("Trading Enabled:", info.tradingEnabled);
        console.log("Pending Positions:", info.pendingPositions);
    }

    /**
     * @notice View vault parameters
     */
    function viewVaultParams() public view {
        console.log("\n=== Vault Parameters ===");

        AssetVault.VaultParams memory params = vault.getVaultParams();

        console.log("Min Bet Amount:", params.minBetAmount);
        console.log("Max Bet Amount:", params.maxBetAmount);
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

    /**
     * @notice View treasury address
     */
    function viewTreasury() public view {
        console.log("\n=== Treasury Address ===");

        address treasuryAddr = vault.getTreasury();
        console.log("Treasury Address:", treasuryAddr);

        if (treasuryAddr == address(0)) {
            console.log("Note: Treasury not set, fees will go to owner");
        }
    }

    /**
     * @notice View withdrawable fees
     */
    function viewWithdrawableFees() public view {
        console.log("\n=== Withdrawable Fees ===");

        uint256 withdrawableFees = vault.getWithdrawableFees();
        console.log("Withdrawable Fees:", withdrawableFees);

        (uint256 total, uint256 staking, uint256 withdrawal) = vault.getFeesCollected();
        console.log("Total Fees Collected:", total);
        console.log("  - Staking Fees:", staking);
        console.log("  - Withdrawal Fees:", withdrawal);
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
        address projectToken = vault.projectToken();
        if (projectToken != address(0)) {
            IERC20(projectToken).approve(address(vault), amount);
            vault.addLiquidity(amount);
        }
        console.log("Liquidity added successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Remove liquidity from vault
     * @dev Removes all shares from the user
     */
    function removeLiquidity() public {
        console.log("\n=== Remove Liquidity ===");

        // Show shares before removal
        uint256 shares = vault.getLPPosition(deployer).shares;
        console.log("Shares to remove:", shares);

        vm.startBroadcast(deployer);
        vault.removeLiquidity();
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
        uint256 minBetAmount,
        uint256 maxBetAmount,
        uint16 maxPositionSizePercentBps
    ) public {
        console.log("\n=== Update Vault Parameters ===");

        vm.startBroadcast(deployer);
        vault.updateVaultParams(minBetAmount, maxBetAmount, maxPositionSizePercentBps);
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
     * @notice Add admin address
     */
    function addAdmin(address newAdmin) public {
        console.log("\n=== Add Admin ===");
        console.log("New Admin:", newAdmin);

        vm.startBroadcast(deployer);
        vault.addAdmin(newAdmin);
        console.log("Admin added successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Remove admin address
     */
    function removeAdmin(address adminToRemove) public {
        console.log("\n=== Remove Admin ===");
        console.log("Admin to Remove:", adminToRemove);

        vm.startBroadcast(deployer);
        vault.removeAdmin(adminToRemove);
        console.log("Admin removed successfully");
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

    /**
     * @notice Set treasury address for fee collection
     * @param treasuryAddress Treasury address (address(0) to use owner as default)
     */
    function setTreasury(address treasuryAddress) public {
        console.log("\n=== Set Treasury ===");
        console.log("Treasury Address:", treasuryAddress);

        if (treasuryAddress == address(0)) {
            console.log("Note: Setting to address(0) - fees will go to owner");
        }

        vm.startBroadcast(deployer);
        vault.setTreasury(treasuryAddress);
        console.log("Treasury address updated successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Withdraw collected fees
     * @param amount Amount to withdraw (0 = withdraw all)
     */
    function withdrawFees(uint256 amount) public {
        console.log("\n=== Withdraw Fees ===");

        // Show current withdrawable fees
        uint256 withdrawableFees = vault.getWithdrawableFees();
        console.log("Current Withdrawable Fees:", withdrawableFees);

        // Show treasury info
        address treasuryAddr = vault.getTreasury();
        address recipient = treasuryAddr != address(0) ? treasuryAddr : vault.owner();
        console.log("Fees will be sent to:", recipient);

        if (amount == 0) {
            console.log("Amount: ALL (", withdrawableFees, ")");
        } else {
            console.log("Amount:", amount);
        }

        vm.startBroadcast(deployer);
        vault.withdrawFees(amount);
        console.log("Fees withdrawn successfully");
        vm.stopBroadcast();

        // Show remaining fees
        uint256 remainingFees = vault.getWithdrawableFees();
        console.log("Remaining Withdrawable Fees:", remainingFees);
    }
}
