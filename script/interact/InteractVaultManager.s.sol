// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../DeployHelper.s.sol";
import "../../src/VaultManager.sol";
import "../../src/AssetVault.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title InteractVaultManager
 * @notice Script to interact with VaultManager contract and individual vaults
 * @dev Includes view functions, LP functions, and admin functions
 */
contract InteractVaultManager is DeployHelper {
    VaultManager public vaultMgr;

    function setUp() public override {
        super.setUp();

        // Load vault manager address from env or deployment file
        address vaultMgrAddr = vm.envOr("VAULT_MANAGER_ADDRESS", vaultManager);
        require(vaultMgrAddr != address(0), "Vault Manager address not set");
        vaultMgr = VaultManager(vaultMgrAddr);

        console.log("Vault Manager Address:", address(vaultMgr));
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /**
     * @notice View vault manager configuration
     */
    function viewConfig() public view {
        console.log("\n=== Vault Manager Configuration ===");
        console.log("Owner:", vaultMgr.owner());
        console.log("Position Manager:", vaultMgr.positionManager());
        console.log("Settlement Engine:", vaultMgr.settlementEngine());
        console.log("Paused:", vaultMgr.paused());
        console.log("Total Vaults:", vaultMgr.getVaultCount());
    }

    /**
     * @notice Get vault address for a project token
     */
    function getVault(address projectToken) public view {
        console.log("\n=== Get Vault ===");
        console.log("Project Token:", projectToken);

        try vaultMgr.getVault(projectToken) returns (address vaultAddr) {
            console.log("Vault Address:", vaultAddr);
        } catch Error(string memory reason) {
            console.log("Error:", reason);
        }
    }

    /**
     * @notice Check if vault exists for project token
     */
    function isVaultSupported(address projectToken) public view {
        console.log("\n=== Is Vault Supported ===");
        console.log("Project Token:", projectToken);

        bool supported = vaultMgr.isVaultSupported(projectToken);
        console.log("Is Supported:", supported);
    }

    /**
     * @notice Get all vault addresses
     */
    function getAllVaults() public view {
        console.log("\n=== All Vaults ===");

        address[] memory vaults = vaultMgr.getAllVaults();
        console.log("Total Vaults:", vaults.length);

        for (uint256 i = 0; i < vaults.length; i++) {
            console.log("Vault", i, ":", vaults[i]);
            address projectToken = vaultMgr.getVaultProjectToken(vaults[i]);
            console.log("  Project Token:", projectToken);
        }
    }

    /**
     * @notice Check if vault is graduated
     */
    function isVaultGraduated(address vaultAddress) public view {
        console.log("\n=== Is Vault Graduated ===");
        console.log("Vault Address:", vaultAddress);

        bool graduated = vaultMgr.isVaultGraduated(vaultAddress);
        console.log("Is Graduated:", graduated);
    }

    /**
     * @notice Get vault project token
     */
    function getVaultProjectToken(address vaultAddress) public view {
        console.log("\n=== Get Vault Project Token ===");
        console.log("Vault Address:", vaultAddress);

        address projectToken = vaultMgr.getVaultProjectToken(vaultAddress);
        console.log("Project Token:", projectToken);
    }

    /**
     * @notice Check position risk
     */
    function checkPositionRisk(address projectToken, uint256 positionSize, uint8 leverage)
        public
        view
    {
        console.log("\n=== Check Position Risk ===");
        console.log("Project Token:", projectToken);
        console.log("Position Size:", positionSize);
        console.log("Leverage:", leverage);

        (bool canOpen, string memory reason) =
            vaultMgr.checkPositionRisk(projectToken, positionSize, leverage);

        console.log("Can Open:", canOpen);
        if (!canOpen) {
            console.log("Reason:", reason);
        }
    }

    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================

    /**
     * @notice Create a new vault
     */
    function createVault(
        address projectToken,
        address projectTokenBase,
        address projectTokenQuote,
        uint16 maxPayoutBps,
        uint16 perBetUtilBps,
        uint16 maxUtilizationBps,
        uint256 minBetAmount,
        uint256 maxBetAmount,
        uint256 graduationThreshold
    ) public {
        console.log("\n=== Create Vault ===");
        console.log("Project Token:", projectToken);
        console.log("Project Token Base:", projectTokenBase);
        console.log("Project Token Quote:", projectTokenQuote);
        console.log("Max Payout BPS:", maxPayoutBps);
        console.log("Per Bet Util BPS:", perBetUtilBps);
        console.log("Max Utilization BPS:", maxUtilizationBps);
        console.log("Min Bet Amount:", minBetAmount);
        console.log("Max Bet Amount:", maxBetAmount);
        console.log("Graduation Threshold:", graduationThreshold);

        vm.startBroadcast(deployer);
        address vaultAddr = vaultMgr.createVault(
            projectToken,
            projectTokenBase,
            projectTokenQuote,
            maxPayoutBps,
            perBetUtilBps,
            maxUtilizationBps,
            minBetAmount,
            maxBetAmount,
            graduationThreshold
        );
        console.log("Vault created at:", vaultAddr);
        vm.stopBroadcast();
    }

    /**
     * @notice Set position manager address
     */
    function setPositionManager(address newPositionManager) public {
        console.log("\n=== Set Position Manager ===");
        console.log("New Position Manager:", newPositionManager);

        vm.startBroadcast(deployer);
        vaultMgr.setPositionManager(newPositionManager);
        console.log("Position Manager updated successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Set settlement engine address
     */
    function setSettlementEngine(address newSettlementEngine) public {
        console.log("\n=== Set Settlement Engine ===");
        console.log("New Settlement Engine:", newSettlementEngine);

        vm.startBroadcast(deployer);
        vaultMgr.setSettlementEngine(newSettlementEngine);
        console.log("Settlement Engine updated successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Pause vault manager
     */
    function pauseVaultManager() public {
        console.log("\n=== Pause Vault Manager ===");

        vm.startBroadcast(deployer);
        vaultMgr.pause();
        console.log("Vault Manager paused successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Unpause vault manager
     */
    function unpauseVaultManager() public {
        console.log("\n=== Unpause Vault Manager ===");

        vm.startBroadcast(deployer);
        vaultMgr.unpause();
        console.log("Vault Manager unpaused successfully");
        vm.stopBroadcast();
    }

    // ========================================================================
    // VAULT INTERACTION FUNCTIONS (LP Functions)
    // ========================================================================

    /**
     * @notice Helper to get vault from project token
     */
    function _getVaultAddress(address projectToken) internal view returns (address) {
        address vaultAddr = vaultMgr.getVaultByProjectToken(projectToken);
        require(vaultAddr != address(0), "Vault not found for project token");
        return vaultAddr;
    }

    /**
     * @notice Add liquidity to a vault (stake tokens)
     * @param projectToken Project token address
     * @param amount Amount of project tokens to stake
     * @dev User needs to approve tokens first
     */
    function addLiquidity(address projectToken, uint256 amount) public {
        console.log("\n=== Add Liquidity to Vault ===");
        console.log("Project Token:", projectToken);
        console.log("Amount:", amount);

        address vaultAddr = _getVaultAddress(projectToken);
        console.log("Vault Address:", vaultAddr);

        AssetVault vault = AssetVault(payable(vaultAddr));

        vm.startBroadcast(deployer);

        // Approve tokens if ERC20
        if (projectToken != address(0)) {
            IERC20(projectToken).approve(vaultAddr, amount);
            console.log("Tokens approved");
        }

        // Add liquidity
        if (projectToken == address(0)) {
            vault.addLiquidity{ value: amount }(amount);
        } else {
            vault.addLiquidity(amount);
        }

        console.log("Liquidity added successfully");
        vm.stopBroadcast();

        // Show updated position
        getLPPosition(projectToken, deployer);
    }

    /**
     * @notice Remove liquidity from a vault (unstake tokens)
     * @param projectToken Project token address
     * @param shares Amount of shares to burn
     */
    function removeLiquidity(address projectToken, uint256 shares) public {
        console.log("\n=== Remove Liquidity from Vault ===");
        console.log("Project Token:", projectToken);
        console.log("Shares:", shares);

        address vaultAddr = _getVaultAddress(projectToken);
        console.log("Vault Address:", vaultAddr);

        AssetVault vault = AssetVault(payable(vaultAddr));

        vm.startBroadcast(deployer);
        vault.removeLiquidity(shares);
        console.log("Liquidity removed successfully");
        vm.stopBroadcast();

        // Show updated position
        getLPPosition(projectToken, deployer);
    }

    /**
     * @notice Claim pending rewards from a vault
     * @param projectToken Project token address
     */
    function claimRewards(address projectToken) public {
        console.log("\n=== Claim Rewards ===");
        console.log("Project Token:", projectToken);

        address vaultAddr = _getVaultAddress(projectToken);
        console.log("Vault Address:", vaultAddr);

        AssetVault vault = AssetVault(payable(vaultAddr));

        // Check pending rewards first
        (uint256 pendingRewards, uint256 daysProcessed) = vault.calculatePendingRewards(deployer);
        console.log("Pending Rewards:", pendingRewards);
        console.log("Days Processed:", daysProcessed);

        if (pendingRewards == 0) {
            console.log("No rewards to claim");
            return;
        }

        vm.startBroadcast(deployer);
        vault.claimRewards();
        console.log("Rewards claimed successfully");
        vm.stopBroadcast();
    }

    // ========================================================================
    // VAULT VIEW FUNCTIONS
    // ========================================================================

    /**
     * @notice Get LP position for a user
     * @param projectToken Project token address
     * @param user User address
     */
    function getLPPosition(address projectToken, address user) public view {
        console.log("\n=== LP Position ===");
        console.log("Project Token:", projectToken);
        console.log("User:", user);

        address vaultAddr = _getVaultAddress(projectToken);
        AssetVault vault = AssetVault(payable(vaultAddr));

        AssetVault.LPPosition memory pos = vault.getLPPosition(user);

        console.log("Shares:", pos.shares);
        console.log("Staked Amount:", pos.stakedAmount);
        console.log("Staked At:", pos.stakedAt);
        console.log("Total Rewards Claimed:", pos.totalRewardsClaimed);
        console.log("Last Processed Day:", pos.lastProcessedDay);

        // Calculate share value
        uint256 shareValue = vault.calculateShareValue(pos.shares);
        console.log("Current Share Value:", shareValue);

        // Check pending rewards
        (uint256 pendingRewards, uint256 daysProcessed) = vault.calculatePendingRewards(user);
        console.log("Pending Rewards:", pendingRewards);
        console.log("Processable Days:", daysProcessed);
    }

    /**
     * @notice Get vault info
     * @param projectToken Project token address
     */
    function getVaultInfo(address projectToken) public view {
        console.log("\n=== Vault Info ===");
        console.log("Project Token:", projectToken);

        address vaultAddr = _getVaultAddress(projectToken);
        console.log("Vault Address:", vaultAddr);

        AssetVault vault = AssetVault(payable(vaultAddr));
        AssetVault.VaultInfo memory info = vault.getVaultInfo();

        console.log("\n--- Liquidity ---");
        console.log("Total Liquidity:", info.totalLiquidity);
        console.log("Total Shares:", info.totalShares);
        console.log("Pending Positions:", info.pendingPositions);

        console.log("\n--- P&L ---");
        console.log("Lifetime P&L:", info.lifetimePnL);
        console.log("Is Negative P&L:", info.isNegativePnL);
        console.log("Total Excess Profit:", info.totalExcessProfit);

        console.log("\n--- Trading Stats ---");
        console.log("Total Volume:", info.totalVolume);
        console.log("Total Positions Settled:", info.totalPositionsSettled);
        console.log("Total Leverage Exposure:", info.totalLeverageExposure);
        console.log("Max Leverage Exposure:", info.maxLeverageExposure);

        console.log("\n--- Fees ---");
        console.log("Total Fees Collected:", info.totalFeesCollected);
        console.log("Total Staking Fees:", info.totalStakingFees);
        console.log("Total Withdrawal Fees:", info.totalWithdrawalFees);

        console.log("\n--- Graduation ---");
        console.log("Is Graduated:", info.isGraduated);
        console.log("Graduation Threshold:", info.graduationThreshold);
        console.log("Trading Enabled:", info.tradingEnabled);
        console.log("Created At:", info.createdAt);
        console.log("Graduated At:", info.graduatedAt);

        // Get vault value in USD
        uint256 valueUSD = vault.getVaultValueUSD();
        console.log("\nVault Value (USD):", valueUSD);
    }

    /**
     * @notice Get vault parameters
     * @param projectToken Project token address
     */
    function getVaultParams(address projectToken) public view {
        console.log("\n=== Vault Parameters ===");
        console.log("Project Token:", projectToken);

        address vaultAddr = _getVaultAddress(projectToken);
        AssetVault vault = AssetVault(payable(vaultAddr));

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
     * @notice Get fee configuration
     * @param projectToken Project token address
     */
    function getFeeConfig(address projectToken) public view {
        console.log("\n=== Fee Configuration ===");
        console.log("Project Token:", projectToken);

        address vaultAddr = _getVaultAddress(projectToken);
        AssetVault vault = AssetVault(payable(vaultAddr));

        (uint16 stakingFeeBps, uint16 earlyWithdrawalFeeBps, uint256 minLockPeriod) =
            vault.getFeeConfig();

        console.log("Staking Fee BPS:", stakingFeeBps);
        console.log("Early Withdrawal Fee BPS:", earlyWithdrawalFeeBps);
        console.log("Min Lock Period (seconds):", minLockPeriod);
        console.log("Min Lock Period (days):", minLockPeriod / 1 days);
    }

    /**
     * @notice Calculate withdrawal amount for a user
     * @param projectToken Project token address
     * @param user User address
     * @param shares Shares to withdraw
     */
    function calculateWithdrawalAmount(address projectToken, address user, uint256 shares)
        public
        view
    {
        console.log("\n=== Calculate Withdrawal Amount ===");
        console.log("Project Token:", projectToken);
        console.log("User:", user);
        console.log("Shares:", shares);

        address vaultAddr = _getVaultAddress(projectToken);
        AssetVault vault = AssetVault(payable(vaultAddr));

        (uint256 grossAmount, uint256 fee, uint256 netAmount, bool isEarlyWithdrawal) =
            vault.calculateWithdrawalAmount(user, shares);

        console.log("Gross Amount:", grossAmount);
        console.log("Fee:", fee);
        console.log("Net Amount:", netAmount);
        console.log("Is Early Withdrawal:", isEarlyWithdrawal);

        if (isEarlyWithdrawal) {
            uint256 remainingLockTime = vault.getRemainingLockTime(user);
            console.log("Remaining Lock Time (seconds):", remainingLockTime);
            console.log("Remaining Lock Time (days):", remainingLockTime / 1 days);
        }
    }

    /**
     * @notice Get remaining lock time for a user
     * @param projectToken Project token address
     * @param user User address
     */
    function getRemainingLockTime(address projectToken, address user) public view {
        console.log("\n=== Remaining Lock Time ===");
        console.log("Project Token:", projectToken);
        console.log("User:", user);

        address vaultAddr = _getVaultAddress(projectToken);
        AssetVault vault = AssetVault(payable(vaultAddr));

        uint256 remainingTime = vault.getRemainingLockTime(user);
        console.log("Remaining Time (seconds):", remainingTime);
        console.log("Remaining Time (days):", remainingTime / 1 days);
        console.log("Remaining Time (hours):", remainingTime / 1 hours);
    }

    /**
     * @notice Get all LPs in a vault
     * @param projectToken Project token address
     */
    function getAllLPs(address projectToken) public view {
        console.log("\n=== All LPs ===");
        console.log("Project Token:", projectToken);

        address vaultAddr = _getVaultAddress(projectToken);
        AssetVault vault = AssetVault(payable(vaultAddr));

        address[] memory lps = vault.getAllLPs();
        console.log("Total LPs:", lps.length);

        for (uint256 i = 0; i < lps.length; i++) {
            console.log("\nLP", i, ":", lps[i]);
            AssetVault.LPPosition memory pos = vault.getLPPosition(lps[i]);
            console.log("  Shares:", pos.shares);
            console.log("  Staked Amount:", pos.stakedAmount);
        }
    }

    /**
     * @notice Get pending payout queue
     * @param projectToken Project token address
     */
    function getPendingPayoutQueue(address projectToken) public view {
        console.log("\n=== Pending Payout Queue ===");
        console.log("Project Token:", projectToken);

        address vaultAddr = _getVaultAddress(projectToken);
        AssetVault vault = AssetVault(payable(vaultAddr));

        uint64[] memory queue = vault.getPendingPayoutQueue();
        console.log("Queue Length:", queue.length);

        for (uint256 i = 0; i < queue.length && i < 10; i++) {
            console.log("Position ID", i, ":", queue[i]);
        }

        if (queue.length > 10) {
            console.log("... and", queue.length - 10, "more");
        }
    }

    /**
     * @notice Process pending payouts manually
     * @param projectToken Project token address
     */
    function processPendingPayouts(address projectToken) public {
        console.log("\n=== Process Pending Payouts ===");
        console.log("Project Token:", projectToken);

        address vaultAddr = _getVaultAddress(projectToken);
        AssetVault vault = AssetVault(payable(vaultAddr));

        vm.startBroadcast(deployer);
        vault.processPendingPayouts();
        console.log("Pending payouts processed");
        vm.stopBroadcast();
    }

    /**
     * @notice Get daily snapshot
     * @param projectToken Project token address
     * @param day Day number
     */
    function getDailySnapshot(address projectToken, uint256 day) public view {
        console.log("\n=== Daily Snapshot ===");
        console.log("Project Token:", projectToken);
        console.log("Day:", day);

        address vaultAddr = _getVaultAddress(projectToken);
        AssetVault vault = AssetVault(payable(vaultAddr));

        AssetVault.DailySnapshot memory snapshot = vault.getDailySnapshot(day);

        console.log("Is Processed:", snapshot.isProcessed);
        if (snapshot.isProcessed) {
            console.log("Total Liquidity:", snapshot.totalLiquidity);
            console.log("Total Shares:", snapshot.totalShares);
            console.log("Net P&L:", snapshot.netPnL);
            console.log("Total Positions Settled:", snapshot.totalPositionsSettled);
            console.log("Timestamp:", snapshot.timestamp);
        }
    }

    // ========================================================================
    // VAULT ADMIN FUNCTIONS
    // ========================================================================

    /**
     * @notice Pause a vault
     * @param projectToken Project token address
     */
    function pauseVault(address projectToken) public {
        console.log("\n=== Pause Vault ===");
        console.log("Project Token:", projectToken);

        address vaultAddr = _getVaultAddress(projectToken);
        AssetVault vault = AssetVault(payable(vaultAddr));

        vm.startBroadcast(deployer);
        vault.pause();
        console.log("Vault paused successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Unpause a vault
     * @param projectToken Project token address
     */
    function unpauseVault(address projectToken) public {
        console.log("\n=== Unpause Vault ===");
        console.log("Project Token:", projectToken);

        address vaultAddr = _getVaultAddress(projectToken);
        AssetVault vault = AssetVault(payable(vaultAddr));

        vm.startBroadcast(deployer);
        vault.unpause();
        console.log("Vault unpaused successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Set trading enabled for a vault
     * @param projectToken Project token address
     * @param enabled Whether trading should be enabled
     */
    function setTradingEnabled(address projectToken, bool enabled) public {
        console.log("\n=== Set Trading Enabled ===");
        console.log("Project Token:", projectToken);
        console.log("Enabled:", enabled);

        address vaultAddr = _getVaultAddress(projectToken);
        AssetVault vault = AssetVault(payable(vaultAddr));

        vm.startBroadcast(deployer);
        vault.setTradingEnabled(enabled);
        console.log("Trading status updated successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Update vault parameters
     * @param projectToken Project token address
     */
    function updateVaultParams(
        address projectToken,
        uint16 maxPayoutBps,
        uint16 perBetUtilBps,
        uint16 maxUtilizationBps,
        uint256 minBetAmount,
        uint256 maxBetAmount,
        uint16 maxLeverageExposureBps,
        uint16 maxPositionSizePercentBps
    ) public {
        console.log("\n=== Update Vault Parameters ===");
        console.log("Project Token:", projectToken);

        address vaultAddr = _getVaultAddress(projectToken);
        AssetVault vault = AssetVault(payable(vaultAddr));

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
     * @notice Set graduation threshold
     * @param projectToken Project token address
     * @param threshold New threshold
     */
    function setGraduationThreshold(address projectToken, uint256 threshold) public {
        console.log("\n=== Set Graduation Threshold ===");
        console.log("Project Token:", projectToken);
        console.log("Threshold:", threshold);

        address vaultAddr = _getVaultAddress(projectToken);
        AssetVault vault = AssetVault(payable(vaultAddr));

        vm.startBroadcast(deployer);
        vault.setGraduationThreshold(threshold);
        console.log("Graduation threshold updated successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Check graduation status manually
     * @param projectToken Project token address
     */
    function checkGraduation(address projectToken) public {
        console.log("\n=== Check Graduation ===");
        console.log("Project Token:", projectToken);

        address vaultAddr = _getVaultAddress(projectToken);
        AssetVault vault = AssetVault(payable(vaultAddr));

        vm.startBroadcast(deployer);
        vault.checkGraduation();
        console.log("Graduation check completed");
        vm.stopBroadcast();

        // Show updated info
        AssetVault.VaultInfo memory info = vault.getVaultInfo();
        console.log("Is Graduated:", info.isGraduated);
        console.log("Trading Enabled:", info.tradingEnabled);
    }

    /**
     * @notice Add backend bot address
     * @param projectToken Project token address
     * @param backend Backend address to add
     */
    function addBackend(address projectToken, address backend) public {
        console.log("\n=== Add Backend ===");
        console.log("Project Token:", projectToken);
        console.log("Backend:", backend);

        address vaultAddr = _getVaultAddress(projectToken);
        AssetVault vault = AssetVault(payable(vaultAddr));

        vm.startBroadcast(deployer);
        vault.addBackend(backend);
        console.log("Backend added successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Remove backend bot address
     * @param projectToken Project token address
     * @param backend Backend address to remove
     */
    function removeBackend(address projectToken, address backend) public {
        console.log("\n=== Remove Backend ===");
        console.log("Project Token:", projectToken);
        console.log("Backend:", backend);

        address vaultAddr = _getVaultAddress(projectToken);
        AssetVault vault = AssetVault(payable(vaultAddr));

        vm.startBroadcast(deployer);
        vault.removeBackend(backend);
        console.log("Backend removed successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Set Blocksense Oracle for a vault
     * @param projectToken Project token address
     * @param blocksenseOracle Oracle address
     */
    function setBlocksenseOracle(address projectToken, address blocksenseOracle) public {
        console.log("\n=== Set Blocksense Oracle ===");
        console.log("Project Token:", projectToken);
        console.log("Oracle:", blocksenseOracle);

        address vaultAddr = _getVaultAddress(projectToken);
        AssetVault vault = AssetVault(payable(vaultAddr));

        vm.startBroadcast(deployer);
        vault.setBlocksenseOracle(blocksenseOracle);
        console.log("Blocksense Oracle updated successfully");
        vm.stopBroadcast();
    }
}
