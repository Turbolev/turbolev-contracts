// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "./DeployHelper.s.sol";

import "../src/BlocksenseOracle.sol";
import "../src/SettlementEngine.sol";
import "../src/PositionManager.sol";
import "../src/VaultManager.sol";
import "../src/VaultManagerHelper.sol";

/**
 * @title UpgradeAll
 * @notice Script to upgrade all upgradeable contracts to new implementations
 * @dev Requires existing proxy addresses to be set in environment variables
 *
 * Usage:
 * 1. Set environment variables for existing proxy addresses:
 *    - BLOCKSENSE_ORACLE_ADDRESS
 *    - SETTLEMENT_ENGINE_ADDRESS
 *    - POSITION_MANAGER_ADDRESS
 *    - VAULT_MANAGER_ADDRESS
 *    - VAULT_MANAGER_HELPER_ADDRESS (optional - will redeploy if missing)
 * 2. Run: forge script script/UpgradeAll.s.sol --rpc-url <RPC_URL> --broadcast
 */
contract UpgradeAll is DeployHelper {
    // New implementations
    address public newBlocksenseOracleImpl;
    address public newSettlementEngineImpl;
    address public newPositionManagerImpl;
    address public newVaultManagerImpl;

    function run() public {
        vm.startBroadcast(deployer);

        console.log("\n===========================================");
        console.log("Starting Boolean Contracts Upgrade");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("===========================================\n");

        // Validate that proxies exist
        _validateProxyAddresses();

        // Step 1: Upgrade BlocksenseOracle
        _upgradeBlocksenseOracle();

        // Step 2: Upgrade SettlementEngine
        _upgradeSettlementEngine();

        // Step 3: Upgrade PositionManager
        _upgradePositionManager();

        // Step 4: Upgrade VaultManager
        _upgradeVaultManager();

        // Step 5: Redeploy VaultManagerHelper if needed
        _redeployVaultManagerHelper();

        // Step 6: Verify upgrade
        _verifyUpgrade();

        console.log("\n===========================================");
        console.log("Upgrade Completed Successfully!");
        console.log("===========================================\n");

        _printUpgradeSummary();

        vm.stopBroadcast();
    }

    // ========================================================================
    // VALIDATION
    // ========================================================================

    function _validateProxyAddresses() internal view {
        require(blocksenseOracle != address(0), "BlocksenseOracle proxy address not set");
        require(settlementEngine != address(0), "SettlementEngine proxy address not set");
        require(positionManager != address(0), "PositionManager proxy address not set");
        require(vaultManager != address(0), "VaultManager proxy address not set");

        console.log("=== Existing Proxy Addresses ===");
        console.log("BlocksenseOracle:", blocksenseOracle);
        console.log("SettlementEngine:", settlementEngine);
        console.log("PositionManager:", positionManager);
        console.log("VaultManager:", vaultManager);
        console.log("VaultManagerHelper:", vaultManagerHelper);
        console.log("");
    }

    // ========================================================================
    // UPGRADE FUNCTIONS
    // ========================================================================

    function _upgradeBlocksenseOracle() internal {
        console.log("\nStep 1: Upgrading BlocksenseOracle...");

        // Deploy new implementation
        newBlocksenseOracleImpl = address(new BlocksenseOracle());
        console.log("New implementation deployed:", newBlocksenseOracleImpl);

        // Upgrade proxy to new implementation
        BlocksenseOracle(blocksenseOracle).upgradeToAndCall(newBlocksenseOracleImpl, "");

        console.log("[UPGRADED] BlocksenseOracle");
        _logDeployment("BlocksenseOracle New Implementation", newBlocksenseOracleImpl);
    }

    function _upgradeSettlementEngine() internal {
        console.log("\nStep 2: Upgrading SettlementEngine...");

        // Deploy new implementation
        newSettlementEngineImpl = address(new SettlementEngine());
        console.log("New implementation deployed:", newSettlementEngineImpl);

        // Upgrade proxy to new implementation
        SettlementEngine(settlementEngine).upgradeToAndCall(newSettlementEngineImpl, "");

        console.log("[UPGRADED] SettlementEngine");
        _logDeployment("SettlementEngine New Implementation", newSettlementEngineImpl);
    }

    function _upgradePositionManager() internal {
        console.log("\nStep 3: Upgrading PositionManager...");

        // Deploy new implementation
        newPositionManagerImpl = address(new PositionManager());
        console.log("New implementation deployed:", newPositionManagerImpl);

        // Upgrade proxy to new implementation
        PositionManager(payable(positionManager)).upgradeToAndCall(newPositionManagerImpl, "");

        console.log("[UPGRADED] PositionManager");
        _logDeployment("PositionManager New Implementation", newPositionManagerImpl);
    }

    function _upgradeVaultManager() internal {
        console.log("\nStep 4: Upgrading VaultManager...");

        // Deploy new implementation
        newVaultManagerImpl = address(new VaultManager());
        console.log("New implementation deployed:", newVaultManagerImpl);

        // Upgrade proxy to new implementation
        VaultManager(vaultManager).upgradeToAndCall(newVaultManagerImpl, "");

        console.log("[UPGRADED] VaultManager");
        _logDeployment("VaultManager New Implementation", newVaultManagerImpl);
    }

    function _redeployVaultManagerHelper() internal {
        console.log("\nStep 5: VaultManagerHelper...");

        if (vaultManagerHelper != address(0)) {
            console.log("VaultManagerHelper already exists at:", vaultManagerHelper);
            console.log(
                "Note: VaultManagerHelper is not upgradeable - manual redeployment required if changes needed"
            );

            // Ensure VaultManager is connected to VaultManagerHelper
            VaultManager(vaultManager).setVaultManagerHelper(vaultManagerHelper);
            console.log("Reconnected VaultManagerHelper to VaultManager");
            return;
        }

        console.log("Deploying new VaultManagerHelper...");
        vaultManagerHelper = payable(address(new VaultManagerHelper(payable(vaultManager))));

        // Connect VaultManagerHelper to VaultManager
        VaultManager(vaultManager).setVaultManagerHelper(vaultManagerHelper);
        console.log("Connected VaultManagerHelper to VaultManager");

        _logDeployment("VaultManagerHelper", vaultManagerHelper);
    }

    // ========================================================================
    // VERIFICATION
    // ========================================================================

    function _verifyUpgrade() internal view {
        console.log("\nStep 6: Verifying upgrade...");

        // Verify proxies still exist
        require(blocksenseOracle != address(0), "BlocksenseOracle proxy missing");
        require(settlementEngine != address(0), "SettlementEngine proxy missing");
        require(positionManager != address(0), "PositionManager proxy missing");
        require(vaultManager != address(0), "VaultManager proxy missing");

        // Verify ownership (should remain unchanged after upgrade)
        require(Ownable(blocksenseOracle).owner() == owner, "Wrong BlocksenseOracle owner");
        require(Ownable(settlementEngine).owner() == owner, "Wrong SettlementEngine owner");
        require(Ownable(positionManager).owner() == owner, "Wrong PositionManager owner");
        require(Ownable(vaultManager).owner() == owner, "Wrong VaultManager owner");

        console.log("[OK] All verifications passed");
    }

    // ========================================================================
    // HELPER FUNCTIONS
    // ========================================================================

    function _printUpgradeSummary() internal view {
        console.log("=== UPGRADE SUMMARY ===");
        console.log("Network Chain ID:", block.chainid);
        console.log("\nProxy Addresses (unchanged):");
        console.log("- BlocksenseOracle:", blocksenseOracle);
        console.log("- SettlementEngine:", settlementEngine);
        console.log("- PositionManager:", positionManager);
        console.log("- VaultManager:", vaultManager);
        console.log("- VaultManagerHelper:", vaultManagerHelper);
        console.log("\nNew Implementations:");
        console.log("- BlocksenseOracle Impl:", newBlocksenseOracleImpl);
        console.log("- SettlementEngine Impl:", newSettlementEngineImpl);
        console.log("- PositionManager Impl:", newPositionManagerImpl);
        console.log("- VaultManager Impl:", newVaultManagerImpl);
        console.log("\nOwners (unchanged):");
        console.log("- Contract Owner:", owner);
        console.log("- Backend Address:", backend);
        console.log("==========================\n");
    }
}
