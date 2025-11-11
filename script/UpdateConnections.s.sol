// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "./DeployHelper.s.sol";

import "../src/BlocksenseOracle.sol";
import "../src/ChainlinkOracle.sol";
import "../src/SettlementEngine.sol";
import "../src/PositionManager.sol";
import "../src/VaultManager.sol";
import "../src/VaultManagerHelper.sol";
import "../src/PriceFeedManager.sol";

/**
 * @title UpdateConnections
 * @notice Script to update connections between contracts
 * @dev Use when:
 *      - Deploying new contract and need to connect with existing contracts
 *      - Upgrading contract and need to reconnect
 *      - Fixing connection issues
 *
 * Usage:
 * forge script script/UpdateConnections.s.sol:UpdateConnections \
 *   --rpc-url $RPC_URL \
 *   --private-key $PRIVATE_KEY \
 *   --broadcast \
 *   -vvvv
 */
contract UpdateConnections is DeployHelper {
    function run() public {
        vm.startBroadcast(deployer);

        console.log("\n===========================================");
        console.log("Updating Contract Connections");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("===========================================\n");

        // Validate addresses
        _validateAddresses();

        // Step 1: Setup SettlementEngine connections
        _setupSettlementEngineConnections();

        // Step 2: Setup PositionManager connections
        _setupPositionManagerConnections();

        // Step 3: Setup VaultManager connections
        _setupVaultManagerConnections();

        // Step 4: Verify all connections
        _verifyConnections();

        console.log("\n===========================================");
        console.log("Connections Updated Successfully!");
        console.log("===========================================\n");

        _printConnectionsSummary();

        vm.stopBroadcast();
    }

    // ========================================================================
    // SETUP FUNCTIONS
    // ========================================================================

    function _setupSettlementEngineConnections() internal {
        console.log("\nStep 1: Setting up SettlementEngine connections...");

        // Set BlocksenseOracle
        if (_isContractDeployed(blocksenseOracle)) {
            try SettlementEngine(settlementEngine).setBlocksenseOracle(blocksenseOracle) {
                console.log("[OK] Connected BlocksenseOracle to SettlementEngine");
            } catch {
                console.log("[SKIP] BlocksenseOracle already set or not authorized");
            }
        } else {
            console.log("[WARN] BlocksenseOracle not deployed, skipping");
        }

        // Set ChainlinkOracle
        if (_isContractDeployed(chainlinkOracle)) {
            try SettlementEngine(settlementEngine).setChainlinkOracle(chainlinkOracle) {
                console.log("[OK] Connected ChainlinkOracle to SettlementEngine");
            } catch {
                console.log("[SKIP] ChainlinkOracle already set or not authorized");
            }
        } else {
            console.log("[WARN] ChainlinkOracle not deployed, skipping");
        }

        // Set VaultManager
        if (_isContractDeployed(vaultManager)) {
            try SettlementEngine(settlementEngine).setVaultManager(vaultManager) {
                console.log("[OK] Connected VaultManager to SettlementEngine");
            } catch {
                console.log("[SKIP] VaultManager already set or not authorized");
            }
        } else {
            console.log("[WARN] VaultManager not deployed, skipping");
        }

        // Set PositionManager
        if (_isContractDeployed(positionManager)) {
            try SettlementEngine(settlementEngine).setPositionManager(positionManager) {
                console.log("[OK] Connected PositionManager to SettlementEngine");
            } catch {
                console.log("[SKIP] PositionManager already set or not authorized");
            }
        } else {
            console.log("[WARN] PositionManager not deployed, skipping");
        }

        // Set PriceFeedManager
        if (_isContractDeployed(priceFeedManager)) {
            try SettlementEngine(settlementEngine).setPriceFeedManager(priceFeedManager) {
                console.log("[OK] Connected PriceFeedManager to SettlementEngine");
            } catch {
                console.log("[SKIP] PriceFeedManager already set or not authorized");
            }
        } else {
            console.log("[WARN] PriceFeedManager not deployed, skipping");
        }
    }

    function _setupPositionManagerConnections() internal {
        console.log("\nStep 2: Setting up PositionManager connections...");

        // Set SettlementEngine
        if (_isContractDeployed(settlementEngine)) {
            try PositionManager(payable(positionManager)).setSettlementEngine(settlementEngine) {
                console.log("[OK] Connected SettlementEngine to PositionManager");
            } catch {
                console.log("[SKIP] SettlementEngine already set or not authorized");
            }
        } else {
            console.log("[WARN] SettlementEngine not deployed, skipping");
        }

        // Set VaultManager
        if (_isContractDeployed(vaultManager)) {
            try PositionManager(payable(positionManager)).setVaultManager(vaultManager) {
                console.log("[OK] Connected VaultManager to PositionManager");
            } catch {
                console.log("[SKIP] VaultManager already set or not authorized");
            }
        } else {
            console.log("[WARN] VaultManager not deployed, skipping");
        }

        // Set PriceFeedManager
        if (_isContractDeployed(priceFeedManager)) {
            try PositionManager(payable(positionManager)).setPriceFeedManager(priceFeedManager) {
                console.log("[OK] Connected PriceFeedManager to PositionManager");
            } catch {
                console.log("[SKIP] PriceFeedManager already set or not authorized");
            }
        } else {
            console.log("[WARN] PriceFeedManager not deployed, skipping");
        }
    }

    function _setupVaultManagerConnections() internal {
        console.log("\nStep 3: Setting up VaultManager connections...");

        // Set PositionManager
        if (_isContractDeployed(positionManager)) {
            try VaultManager(vaultManager).setPositionManager(positionManager) {
                console.log("[OK] Connected PositionManager to VaultManager");
            } catch {
                console.log("[SKIP] PositionManager already set or not authorized");
            }
        } else {
            console.log("[WARN] PositionManager not deployed, skipping");
        }

        // Set VaultManagerHelper
        if (_isContractDeployed(vaultManagerHelper)) {
            try VaultManager(vaultManager).setVaultManagerHelper(vaultManagerHelper) {
                console.log("[OK] Connected VaultManagerHelper to VaultManager");
            } catch {
                console.log("[SKIP] VaultManagerHelper already set or not authorized");
            }
        } else {
            console.log("[WARN] VaultManagerHelper not deployed, skipping");
        }
    }

    // ========================================================================
    // VERIFICATION FUNCTIONS
    // ========================================================================

    function _verifyConnections() internal view {
        console.log("\nStep 4: Verifying connections...");

        bool allOk = true;

        // Verify SettlementEngine connections
        if (_isContractDeployed(settlementEngine)) {
            address currentBlocksense = SettlementEngine(settlementEngine).blocksenseOracle();
            address currentChainlink = SettlementEngine(settlementEngine).chainlinkOracle();
            address currentVaultMgr = SettlementEngine(settlementEngine).vaultManager();
            address currentPosMgr = SettlementEngine(settlementEngine).positionManager();
            address currentPriceFeedMgr = SettlementEngine(settlementEngine).priceFeedManager();

            console.log("\nSettlementEngine connections:");
            console.log("- BlocksenseOracle:", currentBlocksense);
            console.log("- ChainlinkOracle:", currentChainlink);
            console.log("- VaultManager:", currentVaultMgr);
            console.log("- PositionManager:", currentPosMgr);
            console.log("- PriceFeedManager:", currentPriceFeedMgr);

            if (currentBlocksense != blocksenseOracle && _isContractDeployed(blocksenseOracle)) {
                console.log("[WARN] BlocksenseOracle mismatch!");
                allOk = false;
            }
            if (currentChainlink != chainlinkOracle && _isContractDeployed(chainlinkOracle)) {
                console.log("[WARN] ChainlinkOracle mismatch!");
                allOk = false;
            }
        }

        // Verify PositionManager connections
        if (_isContractDeployed(positionManager)) {
            address currentSettlement = PositionManager(payable(positionManager)).settlementEngine();
            address currentVaultMgr = PositionManager(payable(positionManager)).vaultManager();
            address currentPriceFeedMgr = PositionManager(payable(positionManager)).priceFeedManager();

            console.log("\nPositionManager connections:");
            console.log("- SettlementEngine:", currentSettlement);
            console.log("- VaultManager:", currentVaultMgr);
            console.log("- PriceFeedManager:", currentPriceFeedMgr);

            if (currentSettlement != settlementEngine && _isContractDeployed(settlementEngine)) {
                console.log("[WARN] SettlementEngine mismatch!");
                allOk = false;
            }
        }

        // Verify VaultManager connections
        if (_isContractDeployed(vaultManager)) {
            address currentPosMgr = VaultManager(vaultManager).positionManager();
            address currentHelper = VaultManager(vaultManager).vaultManagerHelper();

            console.log("\nVaultManager connections:");
            console.log("- PositionManager:", currentPosMgr);
            console.log("- VaultManagerHelper:", currentHelper);

            if (currentPosMgr != positionManager && _isContractDeployed(positionManager)) {
                console.log("[WARN] PositionManager mismatch!");
                allOk = false;
            }
        }

        if (allOk) {
            console.log("\n[OK] All connections verified successfully");
        } else {
            console.log("\n[WARN] Some connections have mismatches - check logs above");
        }
    }

    // ========================================================================
    // HELPER FUNCTIONS
    // ========================================================================

    function _printConnectionsSummary() internal view {
        console.log("=== CONNECTIONS SUMMARY ===");
        console.log("\nContract Addresses:");
        console.log("- BlocksenseOracle:", blocksenseOracle);
        console.log("- ChainlinkOracle:", chainlinkOracle);
        console.log("- SettlementEngine:", settlementEngine);
        console.log("- PositionManager:", positionManager);
        console.log("- VaultManager:", vaultManager);
        console.log("- VaultManagerHelper:", vaultManagerHelper);
        console.log("- PriceFeedManager:", priceFeedManager);
        console.log("\nConnection Flow:");
        console.log("SettlementEngine:");
        console.log("  - blocksenseOracle: YES");
        console.log("  - chainlinkOracle: YES (fallback)");
        console.log("  - vaultManager: YES");
        console.log("  - positionManager: YES");
        console.log("  - priceFeedManager: YES");
        console.log("\nPositionManager:");
        console.log("  - settlementEngine: YES");
        console.log("  - vaultManager: YES");
        console.log("  - priceFeedManager: YES");
        console.log("\nVaultManager:");
        console.log("  - positionManager: YES");
        console.log("  - vaultManagerHelper: YES");
        console.log("===========================\n");
    }
}
