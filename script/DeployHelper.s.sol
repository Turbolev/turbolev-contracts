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
    address public backend;
    address public deployer;

    // Addresses for Blocksense (need to configure per network)
    address public blocksenseRegistry;

    // ========================================================================
    // DEPLOYED CONTRACTS
    // ========================================================================

    address public blocksenseOracle;
    address public settlementEngine;
    address public positionManager;
    address public vaultManager;
    address public vaultManagerHelper;

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
        backend = vm.envOr("BACKEND_ADDRESS", address(0x1111111111111111111111111111111111111111));

        // Setup Blocksense registry address - check env first, then use chainId-based defaults
        blocksenseRegistry =
            vm.envOr("BLOCKSENSE_REGISTRY_ADDRESS", _getBlocksenseRegistry(block.chainid));

        // Try to load already deployed contract addresses from environment
        _loadDeployedAddressesFromEnv();

        console.log("=== Deployment Configuration ===");
        console.log("Chain ID:", block.chainid);
        console.log("Owner:", owner);
        console.log("Backend:", backend);
        console.log("Deployer:", deployer);
        console.log("Blocksense Registry:", blocksenseRegistry);
        console.log("BlocksenseOracle:", blocksenseOracle);
        console.log("SettlementEngine:", settlementEngine);
        console.log("PositionManager:", positionManager);
        console.log("VaultManager:", vaultManager);
    }

    // ========================================================================
    // HELPER FUNCTIONS
    // ========================================================================

    /**
     * @notice Get Blocksense registry address based on chainId
     * @param chainId Chain ID
     * @return registryAddress Registry address
     */
    function _getBlocksenseRegistry(uint256 chainId)
        internal
        pure
        returns (address registryAddress)
    {
        if (chainId == CHAINID_MAINNET) {
            // Mainnet Blocksense registry address
            // TODO: Update with official registry address
            return address(0);
        } else if (chainId == CHAINID_TESTNET) {
            // Testnet Blocksense registry address
            // TODO: Update with testnet registry address
            return address(0);
        } else {
            // Local/dev network - will deploy mock registry
            return address(0);
        }
    }

    /**
     * @notice Load already deployed contract addresses from environment variables
     * @dev If addresses are set in env, they will be used instead of deploying
     */
    function _loadDeployedAddressesFromEnv() internal {
        // Try to load from environment (returns zero if not found)
        blocksenseOracle = vm.envOr("BLOCKSENSE_ORACLE_ADDRESS", address(0));
        settlementEngine = vm.envOr("SETTLEMENT_ENGINE_ADDRESS", address(0));
        positionManager = vm.envOr("POSITION_MANAGER_ADDRESS", address(0));
        vaultManager = vm.envOr("VAULT_MANAGER_ADDRESS", address(0));
        vaultManagerHelper = vm.envOr("VAULT_MANAGER_HELPER_ADDRESS", address(0));
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
        require(backend != address(0), "Backend address is zero");
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
        json = string.concat(json, '  "backend": "', vm.toString(backend), '",\n');
        json = string.concat(
            json, '  "blocksenseRegistry": "', vm.toString(blocksenseRegistry), '",\n'
        );
        json = string.concat(json, '  "blocksenseOracle": "', vm.toString(blocksenseOracle), '",\n');
        json = string.concat(json, '  "settlementEngine": "', vm.toString(settlementEngine), '",\n');
        json = string.concat(json, '  "positionManager": "', vm.toString(positionManager), '",\n');
        json = string.concat(json, '  "vaultManager": "', vm.toString(vaultManager), '"\n');
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
        backend = vm.parseJsonAddress(json, ".backend");
        blocksenseRegistry = vm.parseJsonAddress(json, ".blocksenseRegistry");
        blocksenseOracle = vm.parseJsonAddress(json, ".blocksenseOracle");
        settlementEngine = vm.parseJsonAddress(json, ".settlementEngine");
        positionManager = vm.parseJsonAddress(json, ".positionManager");
        vaultManager = vm.parseJsonAddress(json, ".vaultManager");

        console.log("Deployment addresses loaded from:", file);
    }
}
