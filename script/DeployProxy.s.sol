// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/BinaryBet.sol";
import "../src/SettlementEngine.sol";
import "../src/VaultManager.sol";

/**
 * @title DeployProxy
 * @notice Deployment script for Boolean Contracts với UUPS Proxy pattern
 * @dev Deploy order:
 *      1. SettlementEngine (implementation + proxy)
 *      2. VaultManager (implementation + proxy)
 *      3. BinaryBet (implementation + proxy)
 *      4. Configure contract addresses
 *      5. Initialize vault parameters
 */
contract DeployProxy is Script {
    // Deployment addresses
    BinaryBet public binaryBet;
    SettlementEngine public settlementEngine;
    VaultManager public vaultManager;

    ERC1967Proxy public binaryBetProxy;
    ERC1967Proxy public settlementEngineProxy;
    ERC1967Proxy public vaultManagerProxy;

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
        // STEP 1: Deploy SettlementEngine
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
        // STEP 2: Deploy VaultManager
        // ============================================================
        console.log("\n=== Deploying VaultManager ===");

        // Deploy implementation
        VaultManager vaultManagerImpl = new VaultManager();
        console.log("VaultManager implementation:", address(vaultManagerImpl));

        // Encode initialize data
        bytes memory vaultInitData = abi.encodeWithSelector(
            VaultManager.initialize.selector,
            owner
        );

        // Deploy proxy
        vaultManagerProxy = new ERC1967Proxy(
            address(vaultManagerImpl),
            vaultInitData
        );
        console.log("VaultManager proxy:", address(vaultManagerProxy));

        // Wrap proxy with interface
        vaultManager = VaultManager(payable(address(vaultManagerProxy)));

        // ============================================================
        // STEP 3: Deploy BinaryBet
        // ============================================================
        console.log("\n=== Deploying BinaryBet ===");

        // Deploy implementation
        BinaryBet binaryBetImpl = new BinaryBet();
        console.log("BinaryBet implementation:", address(binaryBetImpl));

        // Encode initialize data
        bytes memory binaryBetInitData = abi.encodeWithSelector(
            BinaryBet.initialize.selector,
            owner,
            backend
        );

        // Deploy proxy
        binaryBetProxy = new ERC1967Proxy(
            address(binaryBetImpl),
            binaryBetInitData
        );
        console.log("BinaryBet proxy:", address(binaryBetProxy));

        // Wrap proxy with interface
        binaryBet = BinaryBet(payable(address(binaryBetProxy)));

        // ============================================================
        // STEP 4: Configure Contract Addresses
        // ============================================================
        console.log("\n=== Configuring Contract Addresses ===");

        // BinaryBet -> SettlementEngine, VaultManager
        binaryBet.setSettlementEngine(address(settlementEngine));
        console.log(
            "BinaryBet.settlementEngine set to:",
            address(settlementEngine)
        );

        binaryBet.setVaultManager(address(vaultManager));
        console.log("BinaryBet.vaultManager set to:", address(vaultManager));

        // SettlementEngine -> BinaryBet, VaultManager
        settlementEngine.setBinaryBetContract(address(binaryBet));
        console.log(
            "SettlementEngine.binaryBetContract set to:",
            address(binaryBet)
        );

        settlementEngine.setVaultManager(address(vaultManager));
        console.log(
            "SettlementEngine.vaultManager set to:",
            address(vaultManager)
        );

        // VaultManager -> BinaryBet, SettlementEngine
        vaultManager.setBinaryBetContract(address(binaryBet));
        console.log(
            "VaultManager.binaryBetContract set to:",
            address(binaryBet)
        );

        vaultManager.setSettlementEngine(address(settlementEngine));
        console.log(
            "VaultManager.settlementEngine set to:",
            address(settlementEngine)
        );

        // ============================================================
        // STEP 5: Configure Default Parameters
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

        // VaultManager config
        vaultManager.updateVaultParams(
            500, // maxPayoutBps: 5%
            1000, // perBetUtilBps: 10%
            8000, // maxUtilizationBps: 80%
            0.001 ether, // minBetAmount: 0.001 MON
            1000 ether, // maxBetAmount: 1000 MON
            10000 // maxLeverageExposureBps: 100% (1:1 ratio)
        );
        console.log("VaultManager params updated");

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
        console.log("BinaryBet Implementation:", address(binaryBetImpl));
        console.log(
            "SettlementEngine Implementation:",
            address(settlementEngineImpl)
        );
        console.log("VaultManager Implementation:", address(vaultManagerImpl));
        console.log("");
        console.log("=== Proxies (Use these addresses!) ===");
        console.log("BinaryBet Proxy:", address(binaryBet));
        console.log("SettlementEngine Proxy:", address(settlementEngine));
        console.log("VaultManager Proxy:", address(vaultManager));
        console.log("");
        console.log("=== Next Steps ===");
        console.log("1. Add initial liquidity to VaultManager");
        console.log(
            "   cast send",
            address(vaultManager),
            '"stake()" --value 100ether --private-key $PRIVATE_KEY'
        );
        console.log("");
        console.log("2. Verify contracts on explorer");
        console.log(
            "   forge verify-contract",
            address(binaryBetImpl),
            "src/BinaryBet.sol:BinaryBet"
        );
        console.log(
            "   forge verify-contract",
            address(settlementEngineImpl),
            "src/SettlementEngine.sol:SettlementEngine"
        );
        console.log(
            "   forge verify-contract",
            address(vaultManagerImpl),
            "src/VaultManager.sol:VaultManager"
        );
        console.log("");
        console.log("3. Test betting");
        console.log(
            "   cast send",
            address(binaryBet),
            '"openPosition(uint8,uint256)" 1 43250500000 --value 1ether --private-key $PRIVATE_KEY'
        );
        console.log("====================================");
    }
}
