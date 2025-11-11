// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";

/**
 * @title DeployHelper
 * @notice Helper contract containing common configuration for deployment
 * @dev Used as base class for all deploy scripts
 */
contract DeployHelper is Script {
    // ========================================================================
    // ACCOUNTS & ADDRESSES
    // ========================================================================

    address public owner;
    address public admin;
    address public deployer;
    address public backend;

    // ========================================================================
    // DEPLOYED CONTRACTS
    // ========================================================================

    address payable public blocksenseOracle;
    address payable public chainlinkOracle;
    address payable public settlementEngine;
    address payable public positionManager;
    address payable public vaultManager;
    address payable public vaultManagerHelper;
    address payable public priceFeedManager;

    // ========================================================================
    // CONFIGURATION CONSTANTS
    // ========================================================================

    // Blocksense Oracle config
    uint256 public constant ORACLE_MAX_PRICE_AGE = 3600; // 1 hour (seconds)

    // Settlement Engine config
    uint16 public constant HOUSE_EDGE_BPS = 200; // 2%
    uint16 public constant WIN_MULTIPLIER_BPS = 30_000; // 3x
    uint256 public constant MIN_BET_AMOUNT = 0.001 ether;
    uint256 public constant MAX_BET_AMOUNT = 1000 ether;
    uint16 public constant MAX_PROFIT_CAP_BPS = 200; // 2% of vault

    // Position Manager config
    uint256 public constant MAINTENANCE_MARGIN_RATIO = 2000; // 20% (in bps)
    uint8 public constant MIN_LEVERAGE = 1;
    uint8 public constant MAX_LEVERAGE = 100;
    uint256 public constant MIN_POSITION_HOLD_TIME = 60; // 60 seconds

    // Vault config
    uint256 public constant GRADUATION_THRESHOLD = 10_000 ether;

    // ========================================================================
    // NETWORK CONFIG
    // ========================================================================

    uint256 public constant CHAINID_MAINNET = 1;
    uint256 public constant CHAINID_TESTNET = 31_337; // Foundry default

    // ========================================================================
    // EVENTS
    // ========================================================================

    event ContractDeployed(string name, address indexed contractAddress);
    event ConfigUpdated(string configName, string value);

    // ========================================================================
    // SETUP FUNCTIONS
    // ========================================================================

    function setUp() public virtual {
        // Get deployer from environment or use msg.sender
        deployer = msg.sender;

        // Setup accounts from environment variables or use defaults
        owner = vm.envOr("OWNER_ADDRESS", deployer);
        admin = vm.envOr("ADMIN_ADDRESS", address(0x1111111111111111111111111111111111111111));

        // Try to load already deployed contract addresses from environment
        _loadDeployedAddressesFromEnv();

        console.log("=== Deployment Configuration ===");
        console.log("Chain ID:", block.chainid);
        console.log("Owner:", owner);
        console.log("Admin:", admin);
        console.log("Deployer:", deployer);
        console.log("Backend:", backend);
        console.log("BlocksenseOracle:", blocksenseOracle);
        console.log("ChainlinkOracle:", chainlinkOracle);
        console.log("SettlementEngine:", settlementEngine);
        console.log("PositionManager:", positionManager);
        console.log("VaultManager:", vaultManager);
    }

    // ========================================================================
    // HELPER FUNCTIONS
    // ========================================================================

    /**
     * @notice Load already deployed contract addresses from environment variables
     * @dev If addresses are set in env, they will be used instead of deploying
     */
    function _loadDeployedAddressesFromEnv() internal {
        // Try to load from environment (returns zero if not found)
        backend = vm.envOr("BACKEND_ADDRESS", address(0));
        blocksenseOracle = payable(vm.envOr("BLOCKSENSE_ORACLE_ADDRESS", address(0)));
        chainlinkOracle = payable(vm.envOr("CHAINLINK_ORACLE_ADDRESS", address(0)));
        settlementEngine = payable(vm.envOr("SETTLEMENT_ENGINE_ADDRESS", address(0)));
        positionManager = payable(vm.envOr("POSITION_MANAGER_ADDRESS", address(0)));
        vaultManager = payable(vm.envOr("VAULT_MANAGER_ADDRESS", address(0)));
        vaultManagerHelper = payable(vm.envOr("VAULT_MANAGER_HELPER_ADDRESS", address(0)));
        priceFeedManager = payable(vm.envOr("PRICE_FEED_MANAGER_ADDRESS", address(0)));
    }

    /**
     * @notice Check if a contract is already deployed
     * @param addr Contract address
     * @return true if address is not zero
     */
    function _isContractDeployed(address addr) internal pure returns (bool) {
        return addr != address(0);
    }

    /**
     * @notice Validate addresses before deployment
     */
    function _validateAddresses() internal view {
        require(owner != address(0), "Owner address is zero");
        require(admin != address(0), "Admin address is zero");
    }

    /**
     * @notice Log deployment info
     * @param name Contract name
     * @param contractAddress Contract address
     */
    function _logDeployment(string memory name, address contractAddress) internal {
        console.log("");
        console.log("===================================");
        console.log("Deployed:", name);
        console.log("Address:", contractAddress);
        console.log("===================================");
        emit ContractDeployed(name, contractAddress);
    }

    /**
     * @notice Get current chainId
     */
    function getChainId() internal view returns (uint256 chainId) {
        return block.chainid;
    }

    /**
     * @notice Check if we're on mainnet
     */
    function isMainnet() internal view returns (bool) {
        return block.chainid == CHAINID_MAINNET;
    }

    /**
     * @notice Get transaction gas price (adjusted for network)
     */
    function getGasPrice() internal view returns (uint256 gasPrice) {
        return tx.gasprice;
    }

    /**
     * @notice Save deployment addresses to file
     */
    function _saveDeploymentAddresses() internal {
        uint256 chainId = block.chainid;
        string memory file = string.concat("deployments/", vm.toString(chainId), ".json");

        // Create JSON object
        string memory json = "{\n";
        json = string.concat(json, '  "network": ', vm.toString(block.chainid), ",\n");
        json = string.concat(json, '  "owner": "', vm.toString(owner), '",\n');
        json = string.concat(json, '  "admin": "', vm.toString(admin), '",\n');
        json = string.concat(json, '  "backend": "', vm.toString(backend), '",\n');
        json = string.concat(json, '  "blocksenseOracle": "', vm.toString(blocksenseOracle), '",\n');
        json = string.concat(json, '  "chainlinkOracle": "', vm.toString(chainlinkOracle), '",\n');
        json = string.concat(json, '  "settlementEngine": "', vm.toString(settlementEngine), '",\n');
        json = string.concat(json, '  "positionManager": "', vm.toString(positionManager), '",\n');
        json = string.concat(json, '  "vaultManager": "', vm.toString(vaultManager), '",\n');
        json = string.concat(json, '  "vaultManagerHelper": "', vm.toString(vaultManagerHelper), '",\n');
        json = string.concat(json, '  "priceFeedManager": "', vm.toString(priceFeedManager), '"\n');
        json = string.concat(json, "}");

        vm.writeFile(file, json);

        console.log("Deployment addresses saved to:", file);
    }

    /**
     * @notice Load deployment addresses from file
     */
    function _loadDeploymentAddresses() internal {
        uint256 chainId = block.chainid;
        string memory file = string.concat("deployments/", vm.toString(chainId), ".json");

        string memory json = vm.readFile(file);

        owner = vm.parseJsonAddress(json, ".owner");
        admin = vm.parseJsonAddress(json, ".admin");
        backend = vm.parseJsonAddress(json, ".backend");
        blocksenseOracle = payable(vm.parseJsonAddress(json, ".blocksenseOracle"));
        chainlinkOracle = payable(vm.parseJsonAddress(json, ".chainlinkOracle"));
        settlementEngine = payable(vm.parseJsonAddress(json, ".settlementEngine"));
        positionManager = payable(vm.parseJsonAddress(json, ".positionManager"));
        vaultManager = payable(vm.parseJsonAddress(json, ".vaultManager"));
        vaultManagerHelper = payable(vm.parseJsonAddress(json, ".vaultManagerHelper"));
        priceFeedManager = payable(vm.parseJsonAddress(json, ".priceFeedManager"));

        console.log("Deployment addresses loaded from:", file);
    }
}
