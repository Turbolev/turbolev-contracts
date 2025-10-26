// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/PositionManager.sol";
import "../src/SettlementEngine.sol";
import "../src/VaultManager.sol";
import "../src/AssetVault.sol";
import "../src/AssetManager.sol";
import "../src/PythOracle.sol";

/**
 * @title DeployProxy
 * @notice Deployment script for Boolean Contracts với UUPS Proxy pattern
 * @dev Deploy order:
 *      1. PythOracle (implementation + proxy)
 *      2. AssetManager (implementation + proxy)
 *      3. SettlementEngine (implementation + proxy)
 *      4. VaultManager (non-upgradeable)
 *      5. PositionManager (implementation + proxy)
 *      6. Create native token vault
 *      7. Configure contract addresses
 *      8. Configure default parameters
 */
contract DeployProxy is Script {
    // Deployment addresses
    PythOracle public pythOracle;
    PositionManager public positionManager;
    SettlementEngine public settlementEngine;
    VaultManager public vaultManager;
    AssetManager public assetManager;

    ERC1967Proxy public pythOracleProxy;
    ERC1967Proxy public positionManagerProxy;
    ERC1967Proxy public settlementEngineProxy;
    ERC1967Proxy public assetManagerProxy;

    // Config
    address public owner;
    address public backend;

    function run() external {
        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer address:", deployer);
        console.log("Deployer balance:", deployer.balance);

        // Set owner and backend (can be same as deployer for testing)
        owner = deployer;
        backend = vm.envOr("BACKEND_ADDRESS", deployer);

        console.log("Owner:", owner);
        console.log("Backend:", backend);

        vm.startBroadcast(deployerPrivateKey);

        // ============================================================
        // STEP 1: Deploy PythOracle
        // ============================================================
        console.log("\n=== Deploying PythOracle ===");

        // Get Pyth contract address from environment
        address pythContractAddress = vm.envAddress("PYTH_CONTRACT_ADDRESS");
        console.log("Pyth contract address:", pythContractAddress);

        // Deploy implementation
        PythOracle pythOracleImpl = new PythOracle();
        console.log("PythOracle implementation:", address(pythOracleImpl));

        // Encode initialize data (owner, pyth address, max price age = 60 seconds)
        bytes memory pythOracleInitData = abi.encodeWithSelector(
            PythOracle.initialize.selector,
            owner,
            pythContractAddress,
            60 // 60 seconds max price age
        );

        // Deploy proxy
        pythOracleProxy = new ERC1967Proxy(
            address(pythOracleImpl),
            pythOracleInitData
        );
        console.log("PythOracle proxy:", address(pythOracleProxy));

        // Wrap proxy with interface
        pythOracle = PythOracle(payable(address(pythOracleProxy)));

        // ============================================================
        // STEP 2: Deploy AssetManager
        // ============================================================
        console.log("\n=== Deploying AssetManager ===");

        // Deploy implementation
        AssetManager assetManagerImpl = new AssetManager();
        console.log("AssetManager implementation:", address(assetManagerImpl));

        // Encode initialize data
        bytes memory assetManagerInitData = abi.encodeWithSelector(
            AssetManager.initialize.selector,
            owner
        );

        // Deploy proxy
        assetManagerProxy = new ERC1967Proxy(
            address(assetManagerImpl),
            assetManagerInitData
        );
        console.log("AssetManager proxy:", address(assetManagerProxy));

        // Wrap proxy with interface
        assetManager = AssetManager(address(assetManagerProxy));

        // ============================================================
        // STEP 2: Deploy SettlementEngine
        // ============================================================
        console.log("\n=== Deploying SettlementEngine ===");

        // Deploy implementation
        SettlementEngine settlementEngineImpl = new SettlementEngine();
        console.log(
            "SettlementEngine implementation:",
            address(settlementEngineImpl)
        );

        // Encode initialize data
        bytes memory settlementInitData = abi.encodeWithSelector(
            SettlementEngine.initialize.selector,
            owner
        );

        // Deploy proxy
        settlementEngineProxy = new ERC1967Proxy(
            address(settlementEngineImpl),
            settlementInitData
        );
        console.log("SettlementEngine proxy:", address(settlementEngineProxy));

        // Wrap proxy with interface
        settlementEngine = SettlementEngine(address(settlementEngineProxy));

        // ============================================================
        // STEP 3: Deploy VaultManager (non-upgradeable)
        // ============================================================
        console.log("\n=== Deploying VaultManager ===");

        // Deploy VaultManager directly (non-upgradeable)
        vaultManager = new VaultManager(owner);
        console.log("VaultManager deployed at:", address(vaultManager));

        // ============================================================
        // STEP 4: Deploy PositionManager
        // ============================================================
        console.log("\n=== Deploying PositionManager ===");

        // Deploy implementation
        PositionManager positionManagerImpl = new PositionManager();
        console.log(
            "PositionManager implementation:",
            address(positionManagerImpl)
        );

        // Encode initialize data with AssetManager
        bytes memory positionManagerInitData = abi.encodeWithSelector(
            PositionManager.initialize.selector,
            owner,
            backend,
            address(assetManager)
        );

        // Deploy proxy
        positionManagerProxy = new ERC1967Proxy(
            address(positionManagerImpl),
            positionManagerInitData
        );
        console.log("PositionManager proxy:", address(positionManagerProxy));

        // Wrap proxy with interface
        positionManager = PositionManager(
            payable(address(positionManagerProxy))
        );

        // ============================================================
        // STEP 5: Create Native Token Vault
        // ============================================================
        console.log("\n=== Creating Native Token Vault ===");

        // Create vault for native token (address(0))
        address nativeVault = vaultManager.createVault(
            address(0), // native token
            500, // maxPayoutBps: 5%
            1000, // perBetUtilBps: 10%
            8000, // maxUtilizationBps: 80%
            0.001 ether, // minBetAmount: 0.001 MON
            1000 ether // maxBetAmount: 1000 MON
        );
        console.log("Native token vault created at:", nativeVault);

        // ============================================================
        // STEP 6: Configure Contract Addresses
        // ============================================================
        console.log("\n=== Configuring Contract Addresses ===");

        // PositionManager -> SettlementEngine, VaultManager
        positionManager.setSettlementEngine(address(settlementEngine));
        console.log(
            "PositionManager.settlementEngine set to:",
            address(settlementEngine)
        );

        positionManager.setVaultManager(address(vaultManager));
        console.log(
            "PositionManager.vaultManager set to:",
            address(vaultManager)
        );

        // SettlementEngine -> PositionManager, VaultManager
        settlementEngine.setPositionManager(address(positionManager));
        console.log(
            "SettlementEngine.positionManager set to:",
            address(positionManager)
        );

        settlementEngine.setVaultManager(address(vaultManager));
        console.log(
            "SettlementEngine.vaultManager set to:",
            address(vaultManager)
        );

        settlementEngine.setPythOracle(address(pythOracle));
        console.log("SettlementEngine.pythOracle set to:", address(pythOracle));

        // VaultManager -> PositionManager, SettlementEngine
        vaultManager.setPositionManager(address(positionManager));
        console.log(
            "VaultManager.positionManager set to:",
            address(positionManager)
        );

        vaultManager.setSettlementEngine(address(settlementEngine));
        console.log(
            "VaultManager.settlementEngine set to:",
            address(settlementEngine)
        );

        // Configure native token vault
        vaultManager.updateVaultPositionManager(
            address(0),
            address(positionManager)
        );
        console.log(
            "Native Vault.positionManager set to:",
            address(positionManager)
        );

        // ============================================================
        // STEP 7: Configure Default Parameters
        // ============================================================
        console.log("\n=== Configuring Default Parameters ===");

        // SettlementEngine config
        settlementEngine.updateConfig(
            500, // houseEdgeBps: 5%
            19500, // winMultiplierBps: 1.95x
            0.001 ether, // minBetAmount: 0.001 MON
            1000 ether // maxBetAmount: 1000 MON
        );
        console.log("SettlementEngine config updated");

        vm.stopBroadcast();

        // ============================================================
        // Summary
        // ============================================================
        console.log("\n====================================");
        console.log("DEPLOYMENT SUMMARY");
        console.log("====================================");
        console.log("Network:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("Owner:", owner);
        console.log("Backend:", backend);
        console.log("");
        console.log("=== Implementations ===");
        console.log("PythOracle Implementation:", address(pythOracleImpl));
        console.log("AssetManager Implementation:", address(assetManagerImpl));
        console.log(
            "SettlementEngine Implementation:",
            address(settlementEngineImpl)
        );
        console.log(
            "PositionManager Implementation:",
            address(positionManagerImpl)
        );
        console.log("");
        console.log("=== Deployed Contracts (Use these addresses!) ===");
        console.log("PythOracle Proxy:", address(pythOracle));
        console.log("AssetManager Proxy:", address(assetManager));
        console.log("SettlementEngine Proxy:", address(settlementEngine));
        console.log("VaultManager (non-upgradeable):", address(vaultManager));
        console.log("PositionManager Proxy:", address(positionManager));
        console.log("");
        console.log("=== Vaults ===");
        console.log("Native Token Vault:", nativeVault);
        console.log("");
        console.log("=== Next Steps ===");
        console.log("1. Add initial liquidity to Native Token Vault");
        console.log(
            "   cast send",
            nativeVault,
            '"stake()" --value 100ether --private-key $PRIVATE_KEY'
        );
        console.log("");
        console.log("2. Add supported assets to AssetManager");
        console.log(
            "   cast send",
            address(assetManager),
            '"addAsset(string,address,bytes32,uint256,uint256)" "BTC" <metadata_address> <price_feed_id> <min_price> <max_price> --private-key $PRIVATE_KEY'
        );
        console.log("");
        console.log("3. Verify contracts on explorer");
        console.log(
            "   forge verify-contract",
            address(pythOracleImpl),
            "src/PythOracle.sol:PythOracle"
        );
        console.log(
            "   forge verify-contract",
            address(assetManagerImpl),
            "src/AssetManager.sol:AssetManager"
        );
        console.log(
            "   forge verify-contract",
            address(settlementEngineImpl),
            "src/SettlementEngine.sol:SettlementEngine"
        );
        console.log(
            "   forge verify-contract",
            address(vaultManager),
            "src/VaultManager.sol:VaultManager"
        );
        console.log(
            "   forge verify-contract",
            address(positionManagerImpl),
            "src/PositionManager.sol:PositionManager"
        );
        console.log("");
        console.log("4. Test betting (after adding assets)");
        console.log(
            "   cast send",
            address(positionManager),
            '"openPosition(address,address,uint256,uint8,uint8,uint256)" 0x0000000000000000000000000000000000000000 <asset_address> 0 1 1 43250500000 --value 1ether --private-key $PRIVATE_KEY'
        );
        console.log("====================================");
    }
}
