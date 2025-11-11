// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../DeployHelper.s.sol";
import "../../src/VaultManagerHelper.sol";
import "../../src/AssetVault.sol";
import "../../src/interfaces/IAssetVault.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title InteractVaultManagerHelper
 * @notice Script to interact with VaultManagerHelper contract
 * @dev Includes view functions and admin proxy functions
 */
contract InteractVaultManagerHelper is DeployHelper {
    VaultManagerHelper public vaultMgrHelper;

    function setUp() public override {
        super.setUp();

        // Load vault manager helper address from env or deployment file
        address vaultManagerHelperAddr =
            vm.envOr("VAULT_MANAGER_HELPER_ADDRESS", vaultManagerHelper);
        require(vaultManagerHelperAddr != address(0), "Vault Manager Helper address not set");
        vaultMgrHelper = VaultManagerHelper(payable(vaultManagerHelperAddr));

        console.log("Vault Manager Helper Address:", address(vaultMgrHelper));
        console.log("Vault Manager Address:", vaultMgrHelper.vaultManager());
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /**
     * @notice Get vault address for a project token
     * @param projectToken Project token address
     */
    function getVault(address projectToken) public view {
        console.log("\n=== Get Vault ===");
        console.log("Project Token:", projectToken);

        try vaultMgrHelper.getVault(projectToken) returns (address vaultAddr) {
            console.log("Vault Address:", vaultAddr);
        } catch Error(string memory reason) {
            console.log("Error:", reason);
        }
    }

    /**
     * @notice Get all vault addresses
     */
    function getAllVaults() public view {
        console.log("\n=== Get All Vaults ===");

        address[] memory vaults = vaultMgrHelper.getAllVaults();
        console.log("Total Vaults:", vaults.length);

        for (uint256 i = 0; i < vaults.length; i++) {
            console.log("\nVault", i, ":", vaults[i]);

            // Get basic info for each vault
            try AssetVault(payable(vaults[i])).getVaultInfo() returns (
                AssetVault.VaultInfo memory info
            ) {
                console.log("  Total Liquidity:", info.totalLiquidity);
                console.log("  Total Shares:", info.totalShares);
                console.log("  Is Graduated:", info.isGraduated);
                console.log("  Trading Enabled:", info.tradingEnabled);
            } catch {
                console.log("  Failed to get vault info");
            }
        }
    }

    /**
     * @notice Get vault info for a token
     * @param tokenAddress Token address
     */
    function getVaultInfo(address tokenAddress) public view {
        console.log("\n=== Get Vault Info ===");
        console.log("Token Address:", tokenAddress);

        try vaultMgrHelper.getVaultInfo(tokenAddress) returns (IAssetVault.VaultInfo memory info) {
            console.log("\n--- Liquidity ---");
            console.log("Total Liquidity:", info.totalLiquidity);
            console.log("Total Shares:", info.totalShares);
            console.log("Pending Positions:", info.pendingPositions);

            console.log("\n--- P&L ---");
            console.log("Lifetime P&L:", info.lifetimePnL);
            console.log("Is Negative P&L:", info.isNegativePnL);

            console.log("\n--- Trading Stats ---");
            console.log("Total Volume:", info.totalVolume);
            console.log("Total Positions Settled:", info.totalPositionsSettled);
            console.log("Total Leverage Exposure:", info.totalLeverageExposure);

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
        } catch Error(string memory reason) {
            console.log("Error:", reason);
        }
    }

    /**
     * @notice Get vault parameters for a token
     * @param tokenAddress Token address
     */
    function getVaultParams(address tokenAddress) public view {
        console.log("\n=== Get Vault Parameters ===");
        console.log("Token Address:", tokenAddress);

        try vaultMgrHelper.getVaultParams(tokenAddress) returns (
            IAssetVault.VaultParams memory params
        ) {
            console.log("Min Bet Amount:", params.minBetAmount);
            console.log("Max Bet Amount:", params.maxBetAmount);
            console.log("Max Position Size Percent BPS:", params.maxPositionSizePercentBps);
            console.log("Min Liquidity Amount:", params.minLiquidityAmount);
        } catch Error(string memory reason) {
            console.log("Error:", reason);
        }
    }

    /**
     * @notice Check if vault is supported for a project token
     * @param projectToken Project token address
     */
    function isVaultSupported(address projectToken) public view {
        console.log("\n=== Is Vault Supported ===");
        console.log("Project Token:", projectToken);

        bool supported = vaultMgrHelper.isVaultSupported(projectToken);
        console.log("Supported:", supported);
    }

    /**
     * @notice Get LP position for a user in a specific vault
     * @param tokenAddress Token address
     * @param user User address
     */
    function getLPPosition(address tokenAddress, address user) public view {
        console.log("\n=== Get LP Position ===");
        console.log("Token Address:", tokenAddress);
        console.log("User:", user);

        try vaultMgrHelper.getLPPosition(tokenAddress, user) returns (
            IAssetVault.LPPosition memory pos
        ) {
            console.log("Shares:", pos.shares);
            console.log("Staked Amount:", pos.stakedAmount);
            console.log("Staked At:", pos.stakedAt);
            console.log("Total Rewards Claimed:", pos.totalRewardsClaimed);
            console.log("Last Processed Day:", pos.lastProcessedDay);
        } catch Error(string memory reason) {
            console.log("Error:", reason);
        }
    }

    /**
     * @notice Get total liquidity across all vaults
     */
    function getTotalLiquidity() public view {
        console.log("\n=== Get Total Liquidity ===");

        try vaultMgrHelper.getTotalLiquidity() returns (uint256 total) {
            console.log("Total Liquidity (native token):", total);
        } catch Error(string memory reason) {
            console.log("Error:", reason);
        }
    }

    /**
     * @notice Get total USD value across all vaults
     */
    function getTotalValueUSD() public view {
        console.log("\n=== Get Total Value USD ===");

        try vaultMgrHelper.getTotalValueUSD() returns (uint256 totalUSD) {
            console.log("Total Value (USD, 18 decimals):", totalUSD);
            // Display in human-readable format (assuming 18 decimals)
            console.log("Total Value (USD, formatted):", totalUSD / 1e18);
        } catch Error(string memory reason) {
            console.log("Error:", reason);
        }
    }

    /**
     * @notice Get native balance in VaultManagerHelper
     */
    function getNativeBalance() public view {
        console.log("\n=== Get Native Balance ===");

        uint256 balance = vaultMgrHelper.getNativeBalance();
        console.log("Native Balance:", balance);
    }

    /**
     * @notice Get ERC20 token balance in VaultManagerHelper
     * @param token Token address
     */
    function getTokenBalance(address token) public view {
        console.log("\n=== Get Token Balance ===");
        console.log("Token Address:", token);

        try vaultMgrHelper.getTokenBalance(token) returns (uint256 balance) {
            console.log("Token Balance:", balance);
        } catch Error(string memory reason) {
            console.log("Error:", reason);
        }
    }

    /**
     * @notice Get comprehensive summary of all vaults
     */
    function getVaultsSummary() public view {
        console.log("\n=== Vaults Summary ===");

        address[] memory vaults = vaultMgrHelper.getAllVaults();
        console.log("Total Vaults:", vaults.length);

        uint256 totalLiquidity = vaultMgrHelper.getTotalLiquidity();
        console.log("Total Liquidity:", totalLiquidity);

        try vaultMgrHelper.getTotalValueUSD() returns (uint256 totalUSD) {
            console.log("Total Value (USD):", totalUSD / 1e18);
        } catch {
            console.log("Total Value (USD): Unable to fetch");
        }

        console.log("\n--- Individual Vaults ---");
        for (uint256 i = 0; i < vaults.length; i++) {
            console.log("\nVault", i, ":", vaults[i]);
            AssetVault vault = AssetVault(payable(vaults[i]));

            AssetVault.VaultInfo memory info = vault.getVaultInfo();
            console.log("  Liquidity:", info.totalLiquidity);
            console.log("  Volume:", info.totalVolume);
            console.log("  Positions:", info.totalPositionsSettled);
            console.log("  Graduated:", info.isGraduated);
        }
    }

    // ========================================================================
    // VAULT ADMIN PROXY FUNCTIONS
    // ========================================================================

    /**
     * @notice Pause a specific vault
     * @param tokenAddress Token address
     */
    function pauseVault(address tokenAddress) public {
        console.log("\n=== Pause Vault ===");
        console.log("Token Address:", tokenAddress);

        vm.startBroadcast(deployer);
        vaultMgrHelper.pauseVault(tokenAddress);
        console.log("Vault paused successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Unpause a specific vault
     * @param tokenAddress Token address
     */
    function unpauseVault(address tokenAddress) public {
        console.log("\n=== Unpause Vault ===");
        console.log("Token Address:", tokenAddress);

        vm.startBroadcast(deployer);
        vaultMgrHelper.unpauseVault(tokenAddress);
        console.log("Vault unpaused successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Add an admin to a vault
     * @param tokenAddress Token address
     * @param admin Admin address to add
     */
    function addVaultAdmin(address tokenAddress, address admin) public {
        console.log("\n=== Add Vault Admin ===");
        console.log("Token Address:", tokenAddress);
        console.log("Admin:", admin);

        vm.startBroadcast(deployer);
        vaultMgrHelper.addVaultAdmin(tokenAddress, admin);
        console.log("Admin added successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Remove an admin from a vault
     * @param tokenAddress Token address
     * @param admin Admin address to remove
     */
    function removeVaultAdmin(address tokenAddress, address admin) public {
        console.log("\n=== Remove Vault Admin ===");
        console.log("Token Address:", tokenAddress);
        console.log("Admin:", admin);

        vm.startBroadcast(deployer);
        vaultMgrHelper.removeVaultAdmin(tokenAddress, admin);
        console.log("Admin removed successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Update vault parameters
     * @param tokenAddress Token address
     * @param minBetAmount Min bet amount
     * @param maxBetAmount Max bet amount
     * @param maxPositionSizePercentBps Max position size percent in basis points
     */
    function updateVaultParams(
        address tokenAddress,
        uint256 minBetAmount,
        uint256 maxBetAmount,
        uint16 maxPositionSizePercentBps
    ) public {
        console.log("\n=== Update Vault Parameters ===");
        console.log("Token Address:", tokenAddress);
        console.log("Min Bet Amount:", minBetAmount);
        console.log("Max Bet Amount:", maxBetAmount);
        console.log("Max Position Size Percent BPS:", maxPositionSizePercentBps);

        vm.startBroadcast(deployer);
        vaultMgrHelper.updateVaultParams(
            tokenAddress, minBetAmount, maxBetAmount, maxPositionSizePercentBps
        );
        console.log("Vault parameters updated successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Set staking fee BPS for a vault
     * @param tokenAddress Token address
     * @param stakingFeeBps Staking fee BPS
     */
    function setVaultStakingFeeBps(address tokenAddress, uint16 stakingFeeBps) public {
        console.log("\n=== Set Vault Staking Fee BPS ===");
        console.log("Token Address:", tokenAddress);
        console.log("Staking Fee BPS:", stakingFeeBps);

        vm.startBroadcast(deployer);
        vaultMgrHelper.setVaultStakingFeeBps(tokenAddress, stakingFeeBps);
        console.log("Staking fee BPS updated successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Set early withdrawal fee BPS for a vault
     * @param tokenAddress Token address
     * @param earlyWithdrawalFeeBps Early withdrawal fee BPS
     */
    function setVaultEarlyWithdrawalFeeBps(address tokenAddress, uint16 earlyWithdrawalFeeBps)
        public
    {
        console.log("\n=== Set Vault Early Withdrawal Fee BPS ===");
        console.log("Token Address:", tokenAddress);
        console.log("Early Withdrawal Fee BPS:", earlyWithdrawalFeeBps);

        vm.startBroadcast(deployer);
        vaultMgrHelper.setVaultEarlyWithdrawalFeeBps(tokenAddress, earlyWithdrawalFeeBps);
        console.log("Early withdrawal fee BPS updated successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Set graduation threshold for a vault
     * @param tokenAddress Token address
     * @param graduationThreshold Graduation threshold
     */
    function setVaultGraduationThreshold(address tokenAddress, uint256 graduationThreshold)
        public
    {
        console.log("\n=== Set Vault Graduation Threshold ===");
        console.log("Token Address:", tokenAddress);
        console.log("Graduation Threshold:", graduationThreshold);

        vm.startBroadcast(deployer);
        vaultMgrHelper.setVaultGraduationThreshold(tokenAddress, graduationThreshold);
        console.log("Graduation threshold updated successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Set trading enabled for a vault
     * @param tokenAddress Token address
     * @param tradingEnabled Trading enabled
     */
    function setVaultTradingEnabled(address tokenAddress, bool tradingEnabled) public {
        console.log("\n=== Set Vault Trading Enabled ===");
        console.log("Token Address:", tokenAddress);
        console.log("Trading Enabled:", tradingEnabled);

        vm.startBroadcast(deployer);
        vaultMgrHelper.setVaultTradingEnabled(tokenAddress, tradingEnabled);
        console.log("Trading status updated successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Set PriceFeedManager address
     * @param priceFeedManager PriceFeedManager contract address
     */
    function setPriceFeedManager(address priceFeedManager) public {
        console.log("\n=== Set PriceFeedManager ===");
        console.log("PriceFeedManager:", priceFeedManager);

        vm.startBroadcast(deployer);
        vaultMgrHelper.setPriceFeedManager(priceFeedManager);
        console.log("PriceFeedManager updated successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Set treasury address for a specific vault
     * @param tokenAddress Token address
     * @param treasury Treasury address (address(0) to use owner as default)
     */
    function setVaultTreasury(address tokenAddress, address treasury) public {
        console.log("\n=== Set Vault Treasury ===");
        console.log("Token Address:", tokenAddress);
        console.log("Treasury Address:", treasury);

        if (treasury == address(0)) {
            console.log("Note: Setting to address(0) - fees will go to owner");
        }

        vm.startBroadcast(deployer);
        vaultMgrHelper.setVaultTreasury(tokenAddress, treasury);
        console.log("Treasury address updated successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Set treasury address for all vaults
     * @param treasury Treasury address (address(0) to use owner as default)
     */
    function setTreasuryForAllVaults(address treasury) public {
        console.log("\n=== Set Treasury For All Vaults ===");
        console.log("Treasury Address:", treasury);

        if (treasury == address(0)) {
            console.log("Note: Setting to address(0) - fees will go to owner");
        }

        // Show how many vaults will be affected
        address[] memory vaults = vaultMgrHelper.getAllVaults();
        console.log("Number of vaults to update:", vaults.length);

        vm.startBroadcast(deployer);
        vaultMgrHelper.setTreasuryForAllVaults(treasury);
        console.log("Treasury address updated for all vaults successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice View withdrawable fees for a specific vault
     * @param tokenAddress Token address
     */
    function viewVaultWithdrawableFees(address tokenAddress) public view {
        console.log("\n=== View Vault Withdrawable Fees ===");
        console.log("Token Address:", tokenAddress);

        try vaultMgrHelper.getVault(tokenAddress) returns (address vaultAddr) {
            if (vaultAddr == address(0)) {
                console.log("Error: Vault not found");
                return;
            }

            AssetVault vault = AssetVault(payable(vaultAddr));

            uint256 withdrawableFees = vault.getWithdrawableFees();
            console.log("Withdrawable Fees:", withdrawableFees);

            (uint256 total, uint256 staking, uint256 withdrawal) = vault.getFeesCollected();
            console.log("Total Fees Collected:", total);
            console.log("  - Staking Fees:", staking);
            console.log("  - Withdrawal Fees:", withdrawal);

            address treasuryAddr = vault.getTreasury();
            console.log("Treasury Address:", treasuryAddr);
            if (treasuryAddr == address(0)) {
                console.log("Note: Treasury not set, fees will go to owner");
            }
        } catch Error(string memory reason) {
            console.log("Error:", reason);
        }
    }

    /**
     * @notice View withdrawable fees for all vaults
     */
    function viewAllVaultsWithdrawableFees() public view {
        console.log("\n=== View All Vaults Withdrawable Fees ===");

        address[] memory vaults = vaultMgrHelper.getAllVaults();
        console.log("Total Vaults:", vaults.length);

        uint256 totalWithdrawable = 0;

        for (uint256 i = 0; i < vaults.length; i++) {
            console.log("\nVault", i, ":", vaults[i]);

            AssetVault vault = AssetVault(payable(vaults[i]));

            uint256 withdrawableFees = vault.getWithdrawableFees();
            console.log("  Withdrawable Fees:", withdrawableFees);
            totalWithdrawable += withdrawableFees;

            address treasuryAddr = vault.getTreasury();
            console.log("  Treasury:", treasuryAddr);
        }

        console.log("\n=== Summary ===");
        console.log("Total Withdrawable Fees Across All Vaults:", totalWithdrawable);
    }

    // ========================================================================
    // BATCH OPERATIONS
    // ========================================================================

    /**
     * @notice Pause multiple vaults at once
     * @param tokenAddresses Array of token addresses
     */
    function pauseVaultsBatch(address[] memory tokenAddresses) public {
        console.log("\n=== Pause Vaults Batch ===");
        console.log("Number of vaults:", tokenAddresses.length);

        vm.startBroadcast(deployer);
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            console.log("Pausing vault", i, ":", tokenAddresses[i]);
            vaultMgrHelper.pauseVault(tokenAddresses[i]);
        }
        console.log("All vaults paused successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Unpause multiple vaults at once
     * @param tokenAddresses Array of token addresses
     */
    function unpauseVaultsBatch(address[] memory tokenAddresses) public {
        console.log("\n=== Unpause Vaults Batch ===");
        console.log("Number of vaults:", tokenAddresses.length);

        vm.startBroadcast(deployer);
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            console.log("Unpausing vault", i, ":", tokenAddresses[i]);
            vaultMgrHelper.unpauseVault(tokenAddresses[i]);
        }
        console.log("All vaults unpaused successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Set staking fee for multiple vaults at once
     * @param tokenAddresses Array of token addresses
     * @param stakingFeeBps Staking fee BPS to set for all vaults
     */
    function setStakingFeeBatch(address[] memory tokenAddresses, uint16 stakingFeeBps) public {
        console.log("\n=== Set Staking Fee Batch ===");
        console.log("Number of vaults:", tokenAddresses.length);
        console.log("Staking Fee BPS:", stakingFeeBps);

        vm.startBroadcast(deployer);
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            console.log("Setting fee for vault", i, ":", tokenAddresses[i]);
            vaultMgrHelper.setVaultStakingFeeBps(tokenAddresses[i], stakingFeeBps);
        }
        console.log("Staking fees updated for all vaults");
        vm.stopBroadcast();
    }
}
