// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "./DeployHelper.s.sol";

import "../src/oracles/BlocksenseOracle.sol";
import "../src/oracles/ChainlinkOracle.sol";
import "../src/SettlementEngine.sol";
import "../src/PriceFeedManager.sol";
import "../src/interfaces/IPriceFeedManager.sol";
import "../src/interfaces/oracles/IBaseOracle.sol";

// Modular Vault imports
import "../src/vault-modular/VaultManager.sol";
import "../src/vault-modular/VaultAccessController.sol";
import "../src/vault-modular/VaultRouter.sol";
import "../src/vault-modular/modules/VaultCore.sol";
import "../src/vault-modular/modules/VaultFunding.sol";
import "../src/vault-modular/modules/VaultRewards.sol";

// Modular Position imports
import "../src/position-modular/PositionRouter.sol";
import "../src/position-modular/modules/PositionCore.sol";

// Governance
import "../src/vault-modular/VaultAdminProxy.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployAllModular
 * @notice Script to deploy the entire Boolean Contracts system with Modular Vault
 * @dev Deploy all contracts in the correct order and configure dependencies
 */
contract DeployAllModular is DeployHelper {
    // Implementations for upgradeable contracts
    address public blocksenseOracleImpl;
    address public chainlinkOracleImpl;
    address public settlementEngineImpl;
    address public vaultManagerImpl;
    address public priceFeedManagerImpl;
    address public accessControllerImpl;

    // Modular Position components
    address public positionRouterImpl;
    address public positionCoreModule;

    // Modular vault components (inherited from DeployHelper)

    // Governance
    address public deployedTimelock;

    // Config
    uint256 public constant DEFAULT_TIMELOCK_DELAY = 1 days;
    uint256 public constant DELAY_BETWEEN_STEPS = 2 seconds;

    function run() public {
        vm.startBroadcast(deployer);

        console.log("\n===========================================");
        console.log("Starting Boolean Contracts Deployment (Modular)");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("===========================================\n");

        _validateAddresses();

        // Phase 1: Deploy Governance
        _deployGovernance();

        // Phase 2: Deploy Oracles
        _deployOracles();

        // Phase 3: Deploy Vault Modules
        _deployVaultModules();

        // Phase 4: Deploy Position Modules
        _deployPositionModules();

        // Phase 5: Deploy VaultAccessController
        _deployVaultAccessController();

        // Phase 6: Deploy VaultManager
        _deployVaultManager();

        // Phase 7: Deploy Core Contracts (Settlement, Position Router)
        _deployCoreContracts();

        // Phase 9: Setup Connections
        _setupConnections();

        // Phase 10: Verify Deployment
        _verifyDeployment();

        console.log("\n===========================================");
        console.log("Deployment Completed Successfully!");
        console.log("===========================================\n");

        _printSummary();

        vm.stopBroadcast();
    }

    // ========================================================================
    // GOVERNANCE DEPLOYMENT
    // ========================================================================

    function _deployGovernance() internal {
        console.log("\n--- Phase 1: Deploying Governance ---");

        // Deploy TimelockController
        uint256 minDelay = vm.envOr("TIMELOCK_DELAY", DEFAULT_TIMELOCK_DELAY);
        address[] memory proposers = new address[](1);
        proposers[0] = admin;
        address[] memory executors = new address[](1);
        executors[0] = admin;

        deployedTimelock = address(new TimelockController(minDelay, proposers, executors, deployer));
        console.log("TimelockController deployed:", deployedTimelock);
    }

    // ========================================================================
    // ORACLE DEPLOYMENT
    // ========================================================================

    function _deployOracles() internal {
        console.log("\n--- Phase 2: Deploying Oracles ---");

        // BlocksenseOracle
        blocksenseOracleImpl = address(new BlocksenseOracle());
        bytes memory blocksenseInitData = abi.encodeWithSelector(
            BlocksenseOracle.initialize.selector, owner, ORACLE_MAX_PRICE_AGE
        );
        blocksenseOracle =
            payable(address(new ERC1967Proxy(blocksenseOracleImpl, blocksenseInitData)));
        console.log("BlocksenseOracle deployed:", blocksenseOracle);

        // ChainlinkOracle
        chainlinkOracleImpl = address(new ChainlinkOracle());
        bytes memory chainlinkInitData =
            abi.encodeWithSelector(ChainlinkOracle.initialize.selector, ORACLE_MAX_PRICE_AGE);
        chainlinkOracle = payable(address(new ERC1967Proxy(chainlinkOracleImpl, chainlinkInitData)));
        console.log("ChainlinkOracle deployed:", chainlinkOracle);

        // PriceFeedManager
        priceFeedManagerImpl = address(new PriceFeedManager());
        bytes memory priceFeedInitData =
            abi.encodeWithSelector(PriceFeedManager.initialize.selector, owner);
        priceFeedManager =
            payable(address(new ERC1967Proxy(priceFeedManagerImpl, priceFeedInitData)));
        console.log("PriceFeedManager deployed:", priceFeedManager);
    }

    // ========================================================================
    // VAULT MODULES DEPLOYMENT
    // ========================================================================

    function _deployVaultModules() internal {
        console.log("\n--- Phase 3: Deploying Vault Modules ---");

        vaultRouterImpl = address(new VaultRouter());
        console.log("VaultRouter Implementation deployed:", vaultRouterImpl);

        vaultCoreModule = address(new VaultCore());
        console.log("VaultCore Module deployed:", vaultCoreModule);

        vaultFundingModule = address(new VaultFunding());
        console.log("VaultFunding Module deployed:", vaultFundingModule);

        vaultRewardsModule = address(new VaultRewards());
        console.log("VaultRewards Module deployed:", vaultRewardsModule);
    }

    // ========================================================================
    // POSITION MODULES DEPLOYMENT
    // ========================================================================

    function _deployPositionModules() internal {
        console.log("\n--- Phase 4: Deploying Position Modules ---");

        positionRouterImpl = address(new PositionRouter());
        console.log("PositionRouter Implementation deployed:", positionRouterImpl);

        positionCoreModule = address(new PositionCore());
        console.log("PositionCore Module deployed:", positionCoreModule);
    }

    // ========================================================================
    // VAULT ACCESS CONTROLLER DEPLOYMENT
    // ========================================================================

    function _deployVaultAccessController() internal {
        console.log("\n--- Phase 5: Deploying VaultAccessController ---");

        accessControllerImpl = address(new VaultAccessController());

        // Gnosis Safe address for EMERGENCY_ROLE (optional, set via env)
        address gnosisSafe = vm.envOr("GNOSIS_SAFE_ADDRESS", address(0));

        // Initialize with placeholder for vaultManager (will be set later)
        bytes memory accessControllerInitData = abi.encodeWithSelector(
            VaultAccessController.initialize.selector,
            deployedTimelock, // admin = Timelock
            deployer, // vaultManager placeholder (will be updated)
            deployer, // positionManager placeholder (will be updated)
            gnosisSafe // Gnosis Safe for EMERGENCY_ROLE (address(0) = skip)
        );

        vaultAccessController =
            address(new ERC1967Proxy(accessControllerImpl, accessControllerInitData));
        console.log("VaultAccessController deployed:", vaultAccessController);
    }

    // ========================================================================
    // VAULT MANAGER DEPLOYMENT
    // ========================================================================

    function _deployVaultManager() internal {
        console.log("\n--- Phase 6: Deploying VaultManager ---");

        vaultManagerImpl = address(new VaultManager());

        bytes memory vaultManagerInitData = abi.encodeWithSelector(
            VaultManager.initialize.selector,
            owner,
            vaultAccessController,
            vaultRouterImpl,
            vaultCoreModule,
            vaultFundingModule,
            vaultRewardsModule
        );

        vaultManager = payable(address(new ERC1967Proxy(vaultManagerImpl, vaultManagerInitData)));
        console.log("VaultManager deployed:", vaultManager);
    }

    // ========================================================================
    // CORE CONTRACTS DEPLOYMENT
    // ========================================================================

    function _deployCoreContracts() internal {
        console.log("\n--- Phase 8: Deploying Core Contracts ---");

        // SettlementEngine
        settlementEngineImpl = address(new SettlementEngine());
        bytes memory settlementInitData =
            abi.encodeWithSelector(SettlementEngine.initialize.selector, owner);
        settlementEngine =
            payable(address(new ERC1967Proxy(settlementEngineImpl, settlementInitData)));
        console.log("SettlementEngine deployed:", settlementEngine);

        // PositionRouter (Modular Position Manager)
        bytes memory positionInitData = abi.encodeWithSelector(
            PositionRouter.initialize.selector,
            vaultAccessController, // accessController
            settlementEngine, // settlementEngine
            vaultManager, // vaultManager
            priceFeedManager, // priceFeedManager
            positionCoreModule // coreModule
        );
        positionManager = payable(address(new ERC1967Proxy(positionRouterImpl, positionInitData)));
        console.log("PositionRouter (PositionManager) deployed:", positionManager);
    }

    // ========================================================================
    // SETUP CONNECTIONS
    // ========================================================================

    function _setupConnections() internal {
        console.log("\n--- Phase 9: Setting up Connections ---");

        // PositionRouter is already initialized with connections
        // But we can update if needed using setters
        console.log("[OK] PositionRouter configured (via initialize)");

        // VaultManager connections
        VaultManager(vaultManager).setPositionManager(positionManager);
        console.log("[OK] VaultManager configured");

        // SettlementEngine connections
        SettlementEngine(settlementEngine).setPositionManager(positionManager);
        SettlementEngine(settlementEngine).setVaultManager(vaultManager);
        SettlementEngine(settlementEngine).setPriceFeedManager(priceFeedManager);
        console.log("[OK] SettlementEngine configured");

        // VaultAccessController - update with correct addresses
        VaultAccessController(vaultAccessController).setVaultManager(vaultManager);
        // Grant VAULT_ADMIN_ROLE to VaultManager
        VaultAccessController(vaultAccessController)
            .grantRole(
                VaultAccessController(vaultAccessController).VAULT_ADMIN_ROLE(), vaultManager
            );
        // Grant POSITION_MANAGER_ROLE to PositionRouter
        VaultAccessController(vaultAccessController)
            .grantRole(
                VaultAccessController(vaultAccessController).POSITION_MANAGER_ROLE(),
                positionManager
            );
        console.log("[OK] VaultAccessController configured");

        // Setup PriceFeedManager with oracle providers
        _setupPriceFeedManager();
    }

    function _setupPriceFeedManager() internal {
        console.log("\n--- Setting up PriceFeedManager ---");

        PriceFeedManager manager = PriceFeedManager(payable(priceFeedManager));

        // Register Chainlink Provider
        IPriceFeedManager.OracleProvider memory chainlinkProvider = IPriceFeedManager.OracleProvider({
            oracleContract: chainlinkOracle, oracleType: IBaseOracle.OracleType.PUSH, enabled: true
        });

        if (!manager.providerExists(manager.CHAINLINK_PROVIDER())) {
            manager.registerOracleProvider(manager.CHAINLINK_PROVIDER(), chainlinkProvider);
            console.log("[OK] Registered CHAINLINK_PROVIDER");
        }

        // Register Blocksense Provider
        IPriceFeedManager.OracleProvider memory blocksenseProvider = IPriceFeedManager.OracleProvider({
            oracleContract: blocksenseOracle, oracleType: IBaseOracle.OracleType.PUSH, enabled: true
        });

        if (!manager.providerExists(manager.BLOCKSENSE_PROVIDER())) {
            manager.registerOracleProvider(manager.BLOCKSENSE_PROVIDER(), blocksenseProvider);
            console.log("[OK] Registered BLOCKSENSE_PROVIDER");
        }
    }

    // ========================================================================
    // VERIFICATION
    // ========================================================================

    function _verifyDeployment() internal view {
        console.log("\n--- Phase 10: Verifying Deployment ---");

        require(blocksenseOracle != address(0), "BlocksenseOracle not deployed");
        require(chainlinkOracle != address(0), "ChainlinkOracle not deployed");
        require(settlementEngine != address(0), "SettlementEngine not deployed");
        require(positionManager != address(0), "PositionRouter not deployed");
        require(vaultManager != address(0), "VaultManager not deployed");
        require(priceFeedManager != address(0), "PriceFeedManager not deployed");
        require(vaultAccessController != address(0), "VaultAccessController not deployed");
        require(positionCoreModule != address(0), "PositionCore not deployed");

        console.log("[OK] All contracts deployed and verified");
    }

    // ========================================================================
    // SUMMARY
    // ========================================================================

    function _printSummary() internal view {
        console.log("=== DEPLOYMENT SUMMARY (MODULAR) ===");
        console.log("Network Chain ID:", block.chainid);
        console.log("\n--- Governance ---");
        console.log("TimelockController:", deployedTimelock);
        console.log("VaultAccessController:", vaultAccessController);
        console.log("\n--- Oracles ---");
        console.log("BlocksenseOracle:", blocksenseOracle);
        console.log("ChainlinkOracle:", chainlinkOracle);
        console.log("PriceFeedManager:", priceFeedManager);
        console.log("\n--- Core Contracts ---");
        console.log("SettlementEngine:", settlementEngine);
        console.log("PositionRouter (PositionManager):", positionManager);
        console.log("VaultManager:", vaultManager);
        console.log("\n--- Vault Modules ---");
        console.log("VaultRouter Impl:", vaultRouterImpl);
        console.log("VaultCore Module:", vaultCoreModule);
        console.log("VaultFunding Module:", vaultFundingModule);
        console.log("VaultRewards Module:", vaultRewardsModule);
        console.log("\n--- Position Modules ---");
        console.log("PositionRouter Impl:", positionRouterImpl);
        console.log("PositionCore Module:", positionCoreModule);
        console.log("\n--- Accounts ---");
        console.log("Contract Owner:", owner);
        console.log("Admin Address:", admin);
        console.log("==========================\n");
    }
}
