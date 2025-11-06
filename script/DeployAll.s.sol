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
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployAll
 * @notice Script to deploy the entire Boolean Contracts system
 * @dev Deploy all contracts in the correct order and configure dependencies
 */
contract DeployAll is DeployHelper {
    // Implementations (logic contracts) for upgradeable contracts
    address public blocksenseOracleImpl;
    address public chainlinkOracleImpl;
    address public settlementEngineImpl;
    address public positionManagerImpl;
    address public vaultManagerImpl;

    // Proxies for upgradeable contracts
    address public blocksenseOracleProxy;
    address public chainlinkOracleProxy;
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

        // Step 2: Deploy ChainlinkOracle
        _deployChainlinkOracle();

        // Step 3: Deploy SettlementEngine
        _deploySettlementEngine();

        // Step 4: Deploy PositionManager
        _deployPositionManager();

        // Step 5: Deploy VaultManager
        _deployVaultManager();

        // Step 6: Deploy VaultManagerHelper
        _deployVaultManagerHelper();

        // Step 7: Setup contract connections
        _setupConnections();

        // Step 8: Verify deployment
        _verifyDeployment();

        // Step 9: Save addresses
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

        // Deploy new implementation
        blocksenseOracleImpl = address(new BlocksenseOracle());
        console.log("Implementation deployed:", blocksenseOracleImpl);

        // Check if proxy already exists
        if (_isContractDeployed(blocksenseOracle)) {
            console.log("Proxy already exists at:", blocksenseOracle);
            console.log("Upgrading to new implementation...");

            // Upgrade existing proxy to new implementation
            BlocksenseOracle(blocksenseOracle).upgradeToAndCall(blocksenseOracleImpl, "");
            console.log("[UPGRADED] BlocksenseOracle");
        } else {
            console.log("Deploying new proxy...");

            // Prepare initialization data
            bytes memory initData = abi.encodeWithSelector(
                BlocksenseOracle.initialize.selector, owner, ORACLE_MAX_PRICE_AGE
            );

            // Deploy proxy
            blocksenseOracleProxy = address(new ERC1967Proxy(blocksenseOracleImpl, initData));
            blocksenseOracle = payable(blocksenseOracleProxy);

            console.log("[NEW] BlocksenseOracle proxy deployed:", blocksenseOracle);
        }

        _logDeployment("BlocksenseOracle", blocksenseOracle);
        _logDeployment("BlocksenseOracle Implementation", blocksenseOracleImpl);
    }

    function _deployChainlinkOracle() internal {
        console.log("\nStep 2: Deploying ChainlinkOracle...");

        // Deploy new implementation
        chainlinkOracleImpl = address(new ChainlinkOracle());
        console.log("Implementation deployed:", chainlinkOracleImpl);

        // Check if proxy already exists
        if (_isContractDeployed(chainlinkOracle)) {
            console.log("Proxy already exists at:", chainlinkOracle);
            console.log("Upgrading to new implementation...");

            // Upgrade existing proxy to new implementation
            ChainlinkOracle(chainlinkOracle).upgradeToAndCall(chainlinkOracleImpl, "");
            console.log("[UPGRADED] ChainlinkOracle");
        } else {
            console.log("Deploying new proxy...");

            // Prepare initialization data
            bytes memory initData = abi.encodeWithSelector(
                ChainlinkOracle.initialize.selector, blocksenseOracle, ORACLE_MAX_PRICE_AGE
            );

            // Deploy proxy
            chainlinkOracleProxy = address(new ERC1967Proxy(chainlinkOracleImpl, initData));
            chainlinkOracle = payable(chainlinkOracleProxy);

            console.log("[NEW] ChainlinkOracle proxy deployed:", chainlinkOracle);
        }

        _logDeployment("ChainlinkOracle", chainlinkOracle);
        _logDeployment("ChainlinkOracle Implementation", chainlinkOracleImpl);
    }

    function _deploySettlementEngine() internal {
        console.log("\nStep 3: Deploying SettlementEngine...");

        // Deploy new implementation
        settlementEngineImpl = address(new SettlementEngine());
        console.log("Implementation deployed:", settlementEngineImpl);

        // Check if proxy already exists
        if (_isContractDeployed(settlementEngine)) {
            console.log("Proxy already exists at:", settlementEngine);
            console.log("Upgrading to new implementation...");

            // Upgrade existing proxy to new implementation
            SettlementEngine(settlementEngine).upgradeToAndCall(settlementEngineImpl, "");
            console.log("[UPGRADED] SettlementEngine");
        } else {
            console.log("Deploying new proxy...");

            // Prepare initialization data
            bytes memory initData =
                abi.encodeWithSelector(SettlementEngine.initialize.selector, owner);

            // Deploy proxy
            settlementEngineProxy = address(new ERC1967Proxy(settlementEngineImpl, initData));
            settlementEngine = payable(settlementEngineProxy);

            // Update settlement config (only for new deployments)
            SettlementEngine(settlementEngine).updateConfig(
                HOUSE_EDGE_BPS, WIN_MULTIPLIER_BPS, MIN_BET_AMOUNT, MAX_BET_AMOUNT
            );
            SettlementEngine(settlementEngine).setMaxProfitCapBps(MAX_PROFIT_CAP_BPS);

            console.log("[NEW] SettlementEngine proxy deployed:", settlementEngine);
        }

        _logDeployment("SettlementEngine", settlementEngine);
        _logDeployment("SettlementEngine Implementation", settlementEngineImpl);
    }

    function _deployPositionManager() internal {
        console.log("\nStep 4: Deploying PositionManager...");

        // Deploy new implementation
        positionManagerImpl = address(new PositionManager());
        console.log("Implementation deployed:", positionManagerImpl);

        // Check if proxy already exists
        if (_isContractDeployed(positionManager)) {
            console.log("Proxy already exists at:", positionManager);
            console.log("Upgrading to new implementation...");

            // Upgrade existing proxy to new implementation
            PositionManager(payable(positionManager)).upgradeToAndCall(positionManagerImpl, "");
            console.log("[UPGRADED] PositionManager");
        } else {
            console.log("Deploying new proxy...");

            // Prepare initialization data
            bytes memory initData =
                abi.encodeWithSelector(PositionManager.initialize.selector, owner, admin);

            // Deploy proxy
            positionManagerProxy = address(new ERC1967Proxy(positionManagerImpl, initData));
            positionManager = payable(positionManagerProxy);

            // Update config (only for new deployments)
            PositionManager(payable(positionManager)).setMaintenanceMarginRatio(
                MAINTENANCE_MARGIN_RATIO
            );
            PositionManager(payable(positionManager)).setLeverageLimits(MIN_LEVERAGE, MAX_LEVERAGE);
            PositionManager(payable(positionManager)).setMinPositionHoldTime(MIN_POSITION_HOLD_TIME);

            console.log("[NEW] PositionManager proxy deployed:", positionManager);
        }

        _logDeployment("PositionManager", positionManager);
        _logDeployment("PositionManager Implementation", positionManagerImpl);
    }

    function _deployVaultManager() internal {
        console.log("\nStep 5: Deploying VaultManager...");

        // Deploy new implementation
        vaultManagerImpl = address(new VaultManager());
        console.log("Implementation deployed:", vaultManagerImpl);

        // Check if proxy already exists
        if (_isContractDeployed(vaultManager)) {
            console.log("Proxy already exists at:", vaultManager);
            console.log("Upgrading to new implementation...");

            // Upgrade existing proxy to new implementation
            VaultManager(vaultManager).upgradeToAndCall(vaultManagerImpl, "");
            console.log("[UPGRADED] VaultManager");
        } else {
            console.log("Deploying new proxy...");

            // Prepare initialization data
            bytes memory initData = abi.encodeWithSelector(VaultManager.initialize.selector, owner);

            // Deploy proxy
            vaultManagerProxy = address(new ERC1967Proxy(vaultManagerImpl, initData));
            vaultManager = payable(vaultManagerProxy);

            console.log("[NEW] VaultManager proxy deployed:", vaultManager);
        }

        _logDeployment("VaultManager", vaultManager);
        _logDeployment("VaultManager Implementation", vaultManagerImpl);
    }

    function _deployVaultManagerHelper() internal {
        // Check if already deployed
        if (_isContractDeployed(vaultManagerHelper)) {
            console.log("\nVaultManagerHelper already deployed, skipping...");
            return;
        }

        console.log("\nStep 6: Deploying VaultManagerHelper...");

        // Deploy VaultManagerHelper (non-upgradeable)
        vaultManagerHelper = payable(address(new VaultManagerHelper(payable(vaultManager))));

        _logDeployment("VaultManagerHelper", vaultManagerHelper);
    }

    // ========================================================================
    // SETUP FUNCTIONS
    // ========================================================================

    function _setupConnections() internal {
        console.log("\nStep 7: Setting up contract connections...");

        // BlocksenseOracle: Set in SettlementEngine
        SettlementEngine(settlementEngine).setBlocksenseOracle(blocksenseOracle);
        console.log("Connected BlocksenseOracle to SettlementEngine");

        // ChainlinkOracle: Set in SettlementEngine (for fallback)
        SettlementEngine(settlementEngine).setChainlinkOracle(chainlinkOracle);
        console.log("Connected ChainlinkOracle to SettlementEngine");

        SettlementEngine(settlementEngine).setVaultManager(vaultManager);
        console.log("Connected VaultManager to SettlementEngine");

        SettlementEngine(settlementEngine).setPositionManager(positionManager);
        console.log("Connected PositionManager to SettlementEngine");

        // SettlementEngine: Set in PositionManager
        PositionManager(payable(positionManager)).setSettlementEngine(settlementEngine);
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

        // BlocksenseOracle: Set in VaultManager
        VaultManager(vaultManager).setBlocksenseOracle(blocksenseOracle);
        console.log("Connected BlocksenseOracle to VaultManager");

        // VaultManagerHelper: Set in VaultManager
        VaultManager(vaultManager).setVaultManagerHelper(vaultManagerHelper);
        console.log("Connected VaultManagerHelper to VaultManager");
    }

    // ========================================================================
    // VERIFICATION FUNCTIONS
    // ========================================================================

    function _verifyDeployment() internal view {
        console.log("\nStep 8: Verifying deployment...");

        require(blocksenseOracle != address(0), "BlocksenseOracle not deployed");
        require(chainlinkOracle != address(0), "ChainlinkOracle not deployed");
        require(settlementEngine != address(0), "SettlementEngine not deployed");
        require(positionManager != address(0), "PositionManager not deployed");
        require(vaultManager != address(0), "VaultManager not deployed");
        require(vaultManagerHelper != address(0), "VaultManagerHelper not deployed");

        // Verify owner
        require(Ownable(blocksenseOracle).owner() == owner, "Wrong BlocksenseOracle owner");
        require(Ownable(chainlinkOracle).owner() == owner, "Wrong ChainlinkOracle owner");
        require(Ownable(settlementEngine).owner() == owner, "Wrong SettlementEngine owner");
        require(Ownable(positionManager).owner() == owner, "Wrong PositionManager owner");
        require(Ownable(vaultManager).owner() == owner, "Wrong VaultManager owner");

        // Verify connections
        require(
            SettlementEngine(settlementEngine).blocksenseOracle() == blocksenseOracle,
            "SettlementEngine blocksense oracle not set"
        );

        require(
            SettlementEngine(settlementEngine).chainlinkOracle() == chainlinkOracle,
            "SettlementEngine chainlink oracle not set"
        );

        require(
            PositionManager(payable(positionManager)).settlementEngine() == settlementEngine,
            "PositionManager settlement engine not set"
        );

        require(
            PositionManager(payable(positionManager)).vaultManager() == vaultManager,
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
        console.log("- ChainlinkOracle:", chainlinkOracle);
        console.log("- SettlementEngine:", settlementEngine);
        console.log("- PositionManager:", positionManager);
        console.log("- VaultManager:", vaultManager);
        console.log("- VaultManagerHelper:", vaultManagerHelper);
        console.log("\nImplementations:");
        console.log("- BlocksenseOracle Impl:", blocksenseOracleImpl);
        console.log("- ChainlinkOracle Impl:", chainlinkOracleImpl);
        console.log("- SettlementEngine Impl:", settlementEngineImpl);
        console.log("- PositionManager Impl:", positionManagerImpl);
        console.log("- VaultManager Impl:", vaultManagerImpl);
        console.log("\nInfrastructure:");
        console.log("- Backend:", backend);
        console.log("\nOwners:");
        console.log("- Contract Owner:", owner);
        console.log("- Admin Address:", admin);
        console.log("==========================\n");
    }
}
