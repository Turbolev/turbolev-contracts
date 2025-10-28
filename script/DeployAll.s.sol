// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "./DeployHelper.s.sol";

import "../src/BlocksenseOracle.sol";
import "../src/SettlementEngine.sol";
import "../src/PositionManager.sol";
import "../src/VaultManager.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployAll
 * @notice Script to deploy the entire Boolean Contracts system
 * @dev Deploy all contracts in the correct order and configure dependencies
 */
contract DeployAll is DeployHelper {
    // Implementations (logic contracts) for upgradeable contracts
    address public blocksenseOracleImpl;
    address public settlementEngineImpl;
    address public positionManagerImpl;
    address public vaultManagerImpl;

    // Proxies for upgradeable contracts
    address public blocksenseOracleProxy;
    address public settlementEngineProxy;
    address public positionManagerProxy;
    address public vaultManagerProxy;

    function run() public {
        vm.startBroadcast(deployer);

        console.log("\n===========================================");
        console.log("Starting Boolean Contracts Deployment");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("===========================================\n");

        // Validate addresses
        _validateAddresses();

        // Step 1: Deploy BlocksenseOracle
        _deployBlocksenseOracle();

        // Step 2: Deploy SettlementEngine
        _deploySettlementEngine();

        // Step 3: Deploy PositionManager
        _deployPositionManager();

        // Step 4: Deploy VaultManager
        _deployVaultManager();

        // Step 5: Setup contract connections
        _setupConnections();

        // Step 6: Verify deployment
        _verifyDeployment();

        // Step 7: Save addresses
        // _saveDeploymentAddresses();

        console.log("\n===========================================");
        console.log("Deployment Completed Successfully!");
        console.log("===========================================\n");

        _printSummary();

        vm.stopBroadcast();
    }

    // ========================================================================
    // DEPLOYMENT FUNCTIONS
    // ========================================================================

    function _deployBlocksenseOracle() internal {
        console.log("\nStep 1: Deploying BlocksenseOracle...");

        // Deploy implementation
        blocksenseOracleImpl = address(new BlocksenseOracle());
        console.log("Implementation deployed:", blocksenseOracleImpl);

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            BlocksenseOracle.initialize.selector,
            owner,
            blocksenseRegistry,
            ORACLE_MAX_PRICE_AGE
        );

        // Deploy proxy
        blocksenseOracleProxy = address(
            new ERC1967Proxy(blocksenseOracleImpl, initData)
        );

        blocksenseOracle = blocksenseOracleProxy;

        _logDeployment("BlocksenseOracle", blocksenseOracle);
        _logDeployment("BlocksenseOracle Implementation", blocksenseOracleImpl);
    }

    function _deploySettlementEngine() internal {
        console.log("\nStep 2: Deploying SettlementEngine...");

        // Deploy implementation
        settlementEngineImpl = address(new SettlementEngine());
        console.log("Implementation deployed:", settlementEngineImpl);

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            SettlementEngine.initialize.selector,
            owner
        );

        // Deploy proxy
        settlementEngineProxy = address(
            new ERC1967Proxy(settlementEngineImpl, initData)
        );

        settlementEngine = settlementEngineProxy;

        // Update settlement config
        SettlementEngine(settlementEngine).updateConfig(
            HOUSE_EDGE_BPS,
            WIN_MULTIPLIER_BPS,
            MIN_BET_AMOUNT,
            MAX_BET_AMOUNT
        );

        SettlementEngine(settlementEngine).setMaxProfitCapBps(
            MAX_PROFIT_CAP_BPS
        );

        _logDeployment("SettlementEngine", settlementEngine);
        _logDeployment("SettlementEngine Implementation", settlementEngineImpl);
    }

    function _deployPositionManager() internal {
        console.log("\nStep 3: Deploying PositionManager...");

        // Deploy implementation
        positionManagerImpl = address(new PositionManager());
        console.log("Implementation deployed:", positionManagerImpl);

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            PositionManager.initialize.selector,
            owner,
            backend
        );

        // Deploy proxy
        positionManagerProxy = address(
            new ERC1967Proxy(positionManagerImpl, initData)
        );

        positionManager = positionManagerProxy;

        // Update config
        PositionManager(payable(positionManager)).setMaintenanceMarginRatio(
            MAINTENANCE_MARGIN_RATIO
        );
        PositionManager(payable(positionManager)).setLeverageLimits(
            MIN_LEVERAGE,
            MAX_LEVERAGE
        );
        PositionManager(payable(positionManager)).setMinPositionHoldTime(
            MIN_POSITION_HOLD_TIME
        );

        _logDeployment("PositionManager", positionManager);
        _logDeployment("PositionManager Implementation", positionManagerImpl);
    }

    function _deployVaultManager() internal {
        console.log("\nStep 4: Deploying VaultManager...");

        // Deploy implementation
        vaultManagerImpl = address(new VaultManager());
        console.log("Implementation deployed:", vaultManagerImpl);

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            VaultManager.initialize.selector,
            owner
        );

        // Deploy proxy
        vaultManagerProxy = address(
            new ERC1967Proxy(vaultManagerImpl, initData)
        );

        vaultManager = vaultManagerProxy;

        _logDeployment("VaultManager", vaultManager);
        _logDeployment("VaultManager Implementation", vaultManagerImpl);
    }

    // ========================================================================
    // SETUP FUNCTIONS
    // ========================================================================

    function _setupConnections() internal {
        console.log("\nStep 5: Setting up contract connections...");

        // BlocksenseOracle: Set in SettlementEngine
        SettlementEngine(settlementEngine).setBlocksenseOracle(
            blocksenseOracle
        );
        console.log("Connected BlocksenseOracle to SettlementEngine");

        // SettlementEngine: Set in PositionManager
        PositionManager(payable(positionManager)).setSettlementEngine(
            settlementEngine
        );
        console.log("Connected SettlementEngine to PositionManager");

        // VaultManager: Set in PositionManager
        PositionManager(payable(positionManager)).setVaultManager(vaultManager);
        console.log("Connected VaultManager to PositionManager");

        // PositionManager: Set in VaultManager
        VaultManager(vaultManager).setPositionManager(positionManager);
        console.log("Connected PositionManager to VaultManager");

        // SettlementEngine: Set in VaultManager
        VaultManager(vaultManager).setSettlementEngine(settlementEngine);
        console.log("Connected SettlementEngine to VaultManager");
    }

    // ========================================================================
    // VERIFICATION FUNCTIONS
    // ========================================================================

    function _verifyDeployment() internal view {
        console.log("\nStep 6: Verifying deployment...");

        require(
            blocksenseOracle != address(0),
            "BlocksenseOracle not deployed"
        );
        require(
            settlementEngine != address(0),
            "SettlementEngine not deployed"
        );
        require(positionManager != address(0), "PositionManager not deployed");
        require(vaultManager != address(0), "VaultManager not deployed");

        // Verify owner
        require(
            Ownable(blocksenseOracle).owner() == owner,
            "Wrong BlocksenseOracle owner"
        );
        require(
            Ownable(settlementEngine).owner() == owner,
            "Wrong SettlementEngine owner"
        );
        require(
            Ownable(positionManager).owner() == owner,
            "Wrong PositionManager owner"
        );
        require(
            Ownable(vaultManager).owner() == owner,
            "Wrong VaultManager owner"
        );

        // Verify connections
        require(
            SettlementEngine(settlementEngine).blocksenseOracle() ==
                blocksenseOracle,
            "SettlementEngine oracle not set"
        );

        require(
            PositionManager(payable(positionManager)).settlementEngine() ==
                settlementEngine,
            "PositionManager settlement engine not set"
        );

        require(
            PositionManager(payable(positionManager)).vaultManager() ==
                vaultManager,
            "PositionManager vault manager not set"
        );

        require(
            VaultManager(vaultManager).positionManager() == positionManager,
            "VaultManager position manager not set"
        );

        console.log("[OK] All verifications passed");
    }

    // ========================================================================
    // HELPER FUNCTIONS
    // ========================================================================

    function _printSummary() internal view {
        console.log("=== DEPLOYMENT SUMMARY ===");
        console.log("Network Chain ID:", block.chainid);
        console.log("\nCore Contracts:");
        console.log("- BlocksenseOracle:", blocksenseOracle);
        console.log("- SettlementEngine:", settlementEngine);
        console.log("- PositionManager:", positionManager);
        console.log("- VaultManager:", vaultManager);
        console.log("\nImplementations:");
        console.log("- BlocksenseOracle Impl:", blocksenseOracleImpl);
        console.log("- SettlementEngine Impl:", settlementEngineImpl);
        console.log("- PositionManager Impl:", positionManagerImpl);
        console.log("- VaultManager Impl:", vaultManagerImpl);
        console.log("\nInfrastructure:");
        console.log("- Blocksense Registry:", blocksenseRegistry);
        console.log("\nOwners:");
        console.log("- Contract Owner:", owner);
        console.log("- Backend Address:", backend);
        console.log("==========================\n");
    }
}
