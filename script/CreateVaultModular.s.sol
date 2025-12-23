// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "./DeployHelper.s.sol";
import "../src/vault-modular/VaultManager.sol";
import "../src/vault-modular/VaultRouter.sol";

/**
 * @title CreateVaultModular
 * @notice Script to create a new vault using the modular VaultManager
 * @dev Usage: Set PROJECT_TOKEN_ADDRESS, MIN_BET, MAX_BET, GRADUATION_THRESHOLD in .env
 *
 * Example:
 *   forge script script/CreateVaultModular.s.sol:CreateVaultModular \
 *     --sig "createVault(address)" 0xTokenAddress \
 *     --rpc-url $RPC_URL --broadcast
 */
contract CreateVaultModular is DeployHelper {
    VaultManager public vmgr;

    function setUp() public override {
        super.setUp();
        vmgr = VaultManager(payable(vaultManager));
        console.log("VaultManager Address:", address(vmgr));
    }

    /**
     * @notice Create a new vault with default parameters
     * @param projectToken Project token address
     */
    function createVault(address projectToken) public {
        vm.startBroadcast(deployer);

        console.log("\n===========================================");
        console.log("Creating New Vault (Modular)");
        console.log("Project Token:", projectToken);
        console.log("===========================================\n");

        // Get parameters from env or use defaults
        uint256 minBet = vm.envOr("MIN_BET", MIN_BET_AMOUNT);
        uint256 maxBet = vm.envOr("MAX_BET", MAX_BET_AMOUNT);
        uint256 graduationThreshold = vm.envOr("GRADUATION_THRESHOLD", GRADUATION_THRESHOLD);

        console.log("Min Bet Amount:", minBet);
        console.log("Max Bet Amount:", maxBet);
        console.log("Graduation Threshold:", graduationThreshold);

        // Create vault
        address vaultAddress = vmgr.createVault(projectToken, minBet, maxBet, graduationThreshold);

        console.log("\n[SUCCESS] Vault Created!");
        console.log("Vault Address:", vaultAddress);

        // Get vault info
        _printVaultInfo(vaultAddress);

        vm.stopBroadcast();
    }

    /**
     * @notice Create a vault with custom parameters
     * @param projectToken Project token address
     * @param minBet Minimum bet amount
     * @param maxBet Maximum bet amount
     * @param graduationThreshold Graduation threshold
     */
    function createVaultWithParams(
        address projectToken,
        uint256 minBet,
        uint256 maxBet,
        uint256 graduationThreshold
    ) public {
        vm.startBroadcast(deployer);

        console.log("\n===========================================");
        console.log("Creating New Vault (Modular) with Custom Params");
        console.log("Project Token:", projectToken);
        console.log("Min Bet:", minBet);
        console.log("Max Bet:", maxBet);
        console.log("Graduation Threshold:", graduationThreshold);
        console.log("===========================================\n");

        address vaultAddress = vmgr.createVault(projectToken, minBet, maxBet, graduationThreshold);

        console.log("\n[SUCCESS] Vault Created!");
        console.log("Vault Address:", vaultAddress);

        _printVaultInfo(vaultAddress);

        vm.stopBroadcast();
    }

    /**
     * @notice View all vaults
     */
    function viewAllVaults() public view {
        console.log("\n=== All Vaults ===");
        address[] memory vaults = vmgr.getAllVaults();
        console.log("Total vaults:", vaults.length);
        for (uint256 i = 0; i < vaults.length; i++) {
            console.log("Vault", i, ":", vaults[i]);
            _printVaultSummary(vaults[i]);
        }
    }

    /**
     * @notice View vault by project token
     * @param projectToken Project token address
     */
    function viewVault(address projectToken) public view {
        address vaultAddress = vmgr.getVault(projectToken);
        require(vaultAddress != address(0), "Vault not found");

        console.log("\n=== Vault Info ===");
        console.log("Project Token:", projectToken);
        console.log("Vault Address:", vaultAddress);
        _printVaultInfo(vaultAddress);
    }

    // ========================================================================
    // HELPER FUNCTIONS
    // ========================================================================

    function _printVaultInfo(address vaultAddress) internal view {
        VaultRouter vault = VaultRouter(payable(vaultAddress));

        console.log("\n--- Vault Details ---");
        console.log("Project Token:", vault.projectToken());
        console.log("Version:", vault.version());

        VaultStorageLib.VaultInfo memory info = vault.vaultInfo();
        console.log("Total Liquidity:", info.totalLiquidity);
        console.log("Total Shares:", info.totalShares);
        console.log("Trading Enabled:", info.tradingEnabled);
        console.log("Is Graduated:", info.isGraduated);

        VaultStorageLib.VaultParams memory params = vault.vaultParams();
        console.log("Min Bet Amount:", params.minBetAmount);
        console.log("Max Bet Amount:", params.maxBetAmount);
    }

    function _printVaultSummary(address vaultAddress) internal view {
        VaultRouter vault = VaultRouter(payable(vaultAddress));
        VaultStorageLib.VaultInfo memory info = vault.vaultInfo();

        string memory status;
        if (info.tradingEnabled) {
            status = info.isGraduated ? "Graduated" : "Active";
        } else {
            status = "Inactive";
        }

        console.log("  - Token:", vault.projectToken());
        console.log("  - Liquidity:", info.totalLiquidity);
        console.log("  - Status:", status);
    }
}
