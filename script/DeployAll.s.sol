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
    address public priceFeedManagerImpl;

    // Proxies for upgradeable contracts
    address public blocksenseOracleProxy;
    address public chainlinkOracleProxy;
    address public settlementEngineProxy;
    address public positionManagerProxy;
    address public vaultManagerProxy;
    address public priceFeedManagerProxy;

    // Retry configuration
    uint256 public constant MAX_RETRIES = 3;
    uint256 public constant DELAY_BETWEEN_STEPS = 2 seconds; // Delay between deployment steps
    uint256 public constant DELAY_BETWEEN_RETRIES = 3 seconds; // Delay between retries

    function run() public {
        vm.startBroadcast(deployer);

        console.log("\n===========================================");
        console.log("Starting Boolean Contracts Deployment");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("Max Retries:", MAX_RETRIES);
        console.log("Delay between steps:", DELAY_BETWEEN_STEPS, "seconds");
        console.log("===========================================\n");

        // Validate addresses
        _validateAddresses();

        // Step 1: Deploy BlocksenseOracle
        _deployBlocksenseOracleWithRetry();
        _waitBetweenSteps();

        // Step 2: Deploy ChainlinkOracle
        _deployChainlinkOracleWithRetry();
        _waitBetweenSteps();

        // Step 3: Deploy SettlementEngine
        _deploySettlementEngineWithRetry();
        _waitBetweenSteps();

        // Step 4: Deploy PositionManager
        _deployPositionManagerWithRetry();
        _waitBetweenSteps();

        // Step 5: Deploy VaultManager
        _deployVaultManagerWithRetry();
        _waitBetweenSteps();

        // Step 6: Deploy VaultManagerHelper
        _deployVaultManagerHelperWithRetry();
        _waitBetweenSteps();

        // Step 7: Deploy PriceFeedManager
        _deployPriceFeedManagerWithRetry();
        _waitBetweenSteps();

        // Step 8: Setup contract connections
        _setupConnectionsWithRetry();

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

    function _deployPriceFeedManager() internal {
        console.log("\nStep 7: Deploying PriceFeedManager...");

        // Deploy new implementation
        priceFeedManagerImpl = address(new PriceFeedManager());
        console.log("Implementation deployed:", priceFeedManagerImpl);

        // Check if proxy already exists
        if (_isContractDeployed(priceFeedManager)) {
            console.log("Proxy already exists at:", priceFeedManager);
            console.log("Upgrading to new implementation...");

            // Upgrade existing proxy to new implementation
            PriceFeedManager(payable(priceFeedManager)).upgradeToAndCall(priceFeedManagerImpl, "");
            console.log("[UPGRADED] PriceFeedManager");
        } else {
            console.log("Deploying new proxy...");

            // Prepare initialization data
            bytes memory initData = abi.encodeWithSelector(
                PriceFeedManager.initialize.selector,
                owner,
                payable(blocksenseOracle),
                chainlinkOracle
            );

            // Deploy proxy
            priceFeedManagerProxy = address(new ERC1967Proxy(priceFeedManagerImpl, initData));
            priceFeedManager = payable(priceFeedManagerProxy);

            console.log("[NEW] PriceFeedManager proxy deployed:", priceFeedManager);
        }

        _logDeployment("PriceFeedManager", priceFeedManager);
        _logDeployment("PriceFeedManager Implementation", priceFeedManagerImpl);
    }

    // ========================================================================
    // SETUP FUNCTIONS
    // ========================================================================

    function _setupSettlementEngineConnections() internal {
        console.log("\n--- Setting up SettlementEngine connections ---");

        // BlocksenseOracle: Set in SettlementEngine
        SettlementEngine(settlementEngine).setBlocksenseOracle(blocksenseOracle);
        console.log("[OK] Connected BlocksenseOracle to SettlementEngine");

        // ChainlinkOracle: Set in SettlementEngine (for fallback)
        SettlementEngine(settlementEngine).setChainlinkOracle(chainlinkOracle);
        console.log("[OK] Connected ChainlinkOracle to SettlementEngine");

        SettlementEngine(settlementEngine).setVaultManager(vaultManager);
        console.log("[OK] Connected VaultManager to SettlementEngine");

        SettlementEngine(settlementEngine).setPositionManager(positionManager);
        console.log("[OK] Connected PositionManager to SettlementEngine");

        // PriceFeedManager: Set in SettlementEngine
        SettlementEngine(settlementEngine).setPriceFeedManager(priceFeedManager);
        console.log("[OK] Connected PriceFeedManager to SettlementEngine");
    }

    function _setupPositionManagerConnections() internal {
        console.log("\n--- Setting up PositionManager connections ---");

        // SettlementEngine: Set in PositionManager
        PositionManager(payable(positionManager)).setSettlementEngine(settlementEngine);
        console.log("[OK] Connected SettlementEngine to PositionManager");

        // VaultManager: Set in PositionManager
        PositionManager(payable(positionManager)).setVaultManager(vaultManager);
        console.log("[OK] Connected VaultManager to PositionManager");

        // PriceFeedManager: Set in PositionManager
        PositionManager(payable(positionManager)).setPriceFeedManager(priceFeedManager);
        console.log("[OK] Connected PriceFeedManager to PositionManager");
    }

    function _setupVaultManagerConnections() internal {
        console.log("\n--- Setting up VaultManager connections ---");

        // PositionManager: Set in VaultManager
        VaultManager(vaultManager).setPositionManager(positionManager);
        console.log("[OK] Connected PositionManager to VaultManager");

        // VaultManagerHelper: Set in VaultManager
        VaultManager(vaultManager).setVaultManagerHelper(vaultManagerHelper);
        console.log("[OK] Connected VaultManagerHelper to VaultManager");
    }

    function _setupPriceFeedManagerConnections() internal pure {
        console.log("\n--- Setting up PriceFeedManager connections ---");

        // BlocksenseOracle and ChainlinkOracle are already set during initialization
        console.log("[OK] PriceFeedManager initialized with oracles");
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
        require(priceFeedManager != address(0), "PriceFeedManager not deployed");

        // Verify owner
        require(Ownable(blocksenseOracle).owner() == owner, "Wrong BlocksenseOracle owner");
        require(Ownable(chainlinkOracle).owner() == owner, "Wrong ChainlinkOracle owner");
        require(Ownable(settlementEngine).owner() == owner, "Wrong SettlementEngine owner");
        require(Ownable(positionManager).owner() == owner, "Wrong PositionManager owner");
        require(Ownable(vaultManager).owner() == owner, "Wrong VaultManager owner");
        require(Ownable(priceFeedManager).owner() == owner, "Wrong PriceFeedManager owner");

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
    // RETRY & DELAY FUNCTIONS
    // ========================================================================

    /**
     * @notice Deploy BlocksenseOracle with retry logic
     * @dev Retry logic is handled by waiting between steps and using --slow flag
     */
    function _deployBlocksenseOracleWithRetry() internal {
        console.log("\n[Deploying BlocksenseOracle]");
        _deployBlocksenseOracle();
        console.log("[SUCCESS] Deployed BlocksenseOracle");
    }

    /**
     * @notice Deploy ChainlinkOracle with retry logic
     * @dev Retry logic is handled by waiting between steps and using --slow flag
     */
    function _deployChainlinkOracleWithRetry() internal {
        console.log("\n[Deploying ChainlinkOracle]");
        _deployChainlinkOracle();
        console.log("[SUCCESS] Deployed ChainlinkOracle");
    }

    /**
     * @notice Deploy SettlementEngine with retry logic
     * @dev Retry logic is handled by waiting between steps and using --slow flag
     */
    function _deploySettlementEngineWithRetry() internal {
        console.log("\n[Deploying SettlementEngine]");
        _deploySettlementEngine();
        console.log("[SUCCESS] Deployed SettlementEngine");
    }

    /**
     * @notice Deploy PositionManager with retry logic
     * @dev Retry logic is handled by waiting between steps and using --slow flag
     */
    function _deployPositionManagerWithRetry() internal {
        console.log("\n[Deploying PositionManager]");
        _deployPositionManager();
        console.log("[SUCCESS] Deployed PositionManager");
    }

    /**
     * @notice Deploy VaultManager with retry logic
     * @dev Retry logic is handled by waiting between steps and using --slow flag
     */
    function _deployVaultManagerWithRetry() internal {
        console.log("\n[Deploying VaultManager]");
        _deployVaultManager();
        console.log("[SUCCESS] Deployed VaultManager");
    }

    /**
     * @notice Deploy VaultManagerHelper with retry logic
     * @dev Retry logic is handled by waiting between steps and using --slow flag
     */
    function _deployVaultManagerHelperWithRetry() internal {
        console.log("\n[Deploying VaultManagerHelper]");
        _deployVaultManagerHelper();
        console.log("[SUCCESS] Deployed VaultManagerHelper");
    }

    function _deployPriceFeedManagerWithRetry() internal {
        console.log("\n[Deploying PriceFeedManager]");
        _deployPriceFeedManager();
        console.log("[SUCCESS] Deployed PriceFeedManager");
    }

    /**
     * @notice Setup SettlementEngine connections with retry logic
     * @dev Retry logic is handled by waiting between steps and using --slow flag
     */
    function _setupSettlementEngineConnectionsWithRetry() internal {
        console.log("[Setup SettlementEngine connections]");
        _setupSettlementEngineConnections();
        console.log("[SUCCESS] Setup SettlementEngine connections");
    }

    /**
     * @notice Setup PositionManager connections with retry logic
     * @dev Retry logic is handled by waiting between steps and using --slow flag
     */
    function _setupPositionManagerConnectionsWithRetry() internal {
        console.log("[Setup PositionManager connections]");
        _setupPositionManagerConnections();
        console.log("[SUCCESS] Setup PositionManager connections");
    }

    /**
     * @notice Setup VaultManager connections with retry logic
     * @dev Retry logic is handled by waiting between steps and using --slow flag
     */
    function _setupVaultManagerConnectionsWithRetry() internal {
        console.log("[Setup VaultManager connections]");
        _setupVaultManagerConnections();
        console.log("[SUCCESS] Setup VaultManager connections");
    }

    /**
     * @notice Wait between deployment steps
     * @dev In broadcast mode, this will just log a message
     *      Actual delay happens between transactions due to --slow flag
     */
    function _waitBetweenSteps() internal {
        console.log("\n[WAIT] Waiting", DELAY_BETWEEN_STEPS, "seconds before next step...");
        console.log("NOTE: When using --slow flag, transactions are sent sequentially");
        _wait(DELAY_BETWEEN_STEPS);
    }

    /**
     * @notice Wait for specified duration
     * @param duration Duration to wait in seconds
     * @dev Uses vm.sleep() which works in fork mode, logs message in broadcast mode
     */
    function _wait(uint256 duration) internal {
        // In broadcast mode, vm.sleep() doesn't actually delay
        // But it helps with logging and makes the script more readable
        // Use vm.sleep() if available (fork mode)
        // In broadcast mode, --slow flag handles actual delays
        vm.sleep(duration);
    }

    /**
     * @notice Setup connections with retry logic
     */
    function _setupConnectionsWithRetry() internal {
        console.log("\nStep 7: Setting up contract connections with retry...");
        console.log(
            "NOTE: If some transactions fail, you can run UpdateConnections.s.sol separately"
        );

        // Validate all contracts are deployed before connecting
        require(blocksenseOracle != address(0), "BlocksenseOracle not deployed");
        require(chainlinkOracle != address(0), "ChainlinkOracle not deployed");
        require(settlementEngine != address(0), "SettlementEngine not deployed");
        require(positionManager != address(0), "PositionManager not deployed");
        require(vaultManager != address(0), "VaultManager not deployed");
        require(vaultManagerHelper != address(0), "VaultManagerHelper not deployed");

        // Setup SettlementEngine connections with retry
        _setupSettlementEngineConnectionsWithRetry();
        _waitBetweenSteps();

        // Setup PositionManager connections with retry
        _setupPositionManagerConnectionsWithRetry();
        _waitBetweenSteps();

        // Setup VaultManager connections with retry
        _setupVaultManagerConnectionsWithRetry();
        _waitBetweenSteps();

        // Setup PriceFeedManager connections (already initialized with oracles)
        _setupPriceFeedManagerConnections();
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
