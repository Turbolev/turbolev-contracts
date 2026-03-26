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
    address payable public priceFeedManager;
    address payable public pythOracle;
    address payable public tokenFaucet;
    address payable public vaultAdminProxy;

    // Governance contracts
    address public multisigWallet;
    address public timelockController;
    address public vaultBeacon;
    address public vaultAccessController;
    address public vaultViewerModular;

    // Modular Vault components
    address public vaultRouterImpl;
    address public vaultCoreModule;
    address public vaultFundingModule;
    address public vaultRewardsModule;

    // ========================================================================
    // CONFIGURATION CONSTANTS
    // ========================================================================

    // Blocksense Oracle config
    uint256 public constant ORACLE_MAX_PRICE_AGE = 3600; // 1 hour (seconds)

    // Settlement Engine config
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
    // VAULT RISK CONTROLS
    // ========================================================================

    // Directional exposure limits
    uint16 public constant MAX_DIRECTIONAL_EXPOSURE_BPS = 5000; // 50% of TVL

    // Total OI Risk Multipliers per tier
    uint16 public constant TIER1_OI_MULTIPLIER_BPS = 15_000; // 1.5x for small vaults
    uint16 public constant TIER2_OI_MULTIPLIER_BPS = 20_000; // 2.0x for medium vaults
    uint16 public constant TIER3_OI_MULTIPLIER_BPS = 25_000; // 2.5x for large vaults
    uint16 public constant TIER4_OI_MULTIPLIER_BPS = 30_000; // 3.0x for very large vaults

    // TVL thresholds for OI tiers
    uint256 public constant TIER1_OI_THRESHOLD = 50_000 ether;
    uint256 public constant TIER2_OI_THRESHOLD = 200_000 ether;
    uint256 public constant TIER3_OI_THRESHOLD = 500_000 ether;

    // ========================================================================
    // LEVERAGE TIER SYSTEM
    // ========================================================================

    // TVL thresholds for leverage tiers
    uint256 public constant LEVERAGE_TIER1_THRESHOLD = 100_000 ether; // 100K
    uint256 public constant LEVERAGE_TIER2_THRESHOLD = 500_000 ether; // 500K

    // Max leverage per tier
    uint16 public constant TIER1_MAX_LEVERAGE = 100; // Launch Phase: 100x
    uint16 public constant TIER2_MAX_LEVERAGE = 200; // Growth Phase: 200x
    uint16 public constant TIER3_MAX_LEVERAGE = 500; // Mature Phase: 500x

    // ========================================================================
    // POSITION FEES
    // ========================================================================

    uint16 public constant OPEN_POSITION_FEE_BPS = 5; // 0.05%
    uint16 public constant CLOSE_POSITION_FEE_BPS = 5; // 0.05%
    uint16 public constant STAKING_FEE_BPS = 50; // 0.5%
    uint16 public constant EARLY_WITHDRAWAL_FEE_BPS = 50; // 0.5%

    // ========================================================================
    // FUNDING RATE CONFIG
    // ========================================================================

    bool public constant FUNDING_ENABLED = true;
    uint256 public constant FUNDING_INTERVAL = 1 hours;

    // Funding rate tiers (in basis points per hour)
    int256 public constant FUNDING_TIER1_RATE = 1; // 0.01% for <20% imbalance
    int256 public constant FUNDING_TIER2_RATE = 3; // 0.03% for 20-40% imbalance
    int256 public constant FUNDING_TIER3_RATE = 5; // 0.05% for 40-60% imbalance
    int256 public constant FUNDING_TIER4_RATE = 8; // 0.08% for 60-80% imbalance
    int256 public constant FUNDING_TIER5_RATE = 10; // 0.10% for >80% imbalance

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
        console.log("PythOracle:", pythOracle);
        console.log("SettlementEngine:", settlementEngine);
        console.log("PositionManager:", positionManager);
        console.log("VaultManager:", vaultManager);
        console.log("VaultAdminProxy:", vaultAdminProxy);
        console.log("PriceFeedManager:", priceFeedManager);
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
        pythOracle = payable(vm.envOr("PYTH_ORACLE_ADDRESS", address(0)));
        settlementEngine = payable(vm.envOr("SETTLEMENT_ENGINE_ADDRESS", address(0)));
        positionManager = payable(vm.envOr("POSITION_MANAGER_ADDRESS", address(0)));
        vaultManager = payable(vm.envOr("VAULT_MANAGER_ADDRESS", address(0)));
        vaultAdminProxy = payable(vm.envOr("VAULT_ADMIN_PROXY_ADDRESS", address(0)));
        priceFeedManager = payable(vm.envOr("PRICE_FEED_MANAGER_ADDRESS", address(0)));
        tokenFaucet = payable(vm.envOr("TOKEN_FAUCET_ADDRESS", address(0)));

        // Governance contracts
        multisigWallet = vm.envOr("MULTISIG_WALLET_ADDRESS", address(0));
        timelockController = vm.envOr("TIMELOCK_ADDRESS", address(0));
        vaultBeacon = vm.envOr("VAULT_BEACON_ADDRESS", address(0));
        vaultAccessController = vm.envOr("VAULT_ACCESS_CONTROLLER_ADDRESS", address(0));
        vaultViewerModular = vm.envOr("VAULT_VIEWER_MODULAR_ADDRESS", address(0));

        // Modular Vault components
        vaultRouterImpl = vm.envOr("VAULT_ROUTER_IMPL_ADDRESS", address(0));
        vaultCoreModule = vm.envOr("VAULT_CORE_MODULE_ADDRESS", address(0));
        vaultFundingModule = vm.envOr("VAULT_FUNDING_MODULE_ADDRESS", address(0));
        vaultRewardsModule = vm.envOr("VAULT_REWARDS_MODULE_ADDRESS", address(0));
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
        json = string.concat(json, '  "pythOracle": "', vm.toString(pythOracle), '",\n');
        json = string.concat(json, '  "settlementEngine": "', vm.toString(settlementEngine), '",\n');
        json = string.concat(json, '  "positionManager": "', vm.toString(positionManager), '",\n');
        json = string.concat(json, '  "vaultManager": "', vm.toString(vaultManager), '",\n');
        json = string.concat(json, '  "vaultAdminProxy": "', vm.toString(vaultAdminProxy), '",\n');
        json = string.concat(json, '  "priceFeedManager": "', vm.toString(priceFeedManager), '",\n');
        json = string.concat(json, '  "tokenFaucet": "', vm.toString(tokenFaucet), '",\n');
        // Governance contracts
        json = string.concat(json, '  "multisigWallet": "', vm.toString(multisigWallet), '",\n');
        json = string.concat(
            json, '  "timelockController": "', vm.toString(timelockController), '",\n'
        );
        json = string.concat(json, '  "vaultBeacon": "', vm.toString(vaultBeacon), '",\n');
        json = string.concat(
            json, '  "vaultAccessController": "', vm.toString(vaultAccessController), '",\n'
        );
        // Modular Vault components
        json = string.concat(json, '  "vaultRouterImpl": "', vm.toString(vaultRouterImpl), '",\n');
        json = string.concat(json, '  "vaultCoreModule": "', vm.toString(vaultCoreModule), '",\n');
        json = string.concat(
            json, '  "vaultFundingModule": "', vm.toString(vaultFundingModule), '",\n'
        );
        json = string.concat(
            json, '  "vaultRewardsModule": "', vm.toString(vaultRewardsModule), '"\n'
        );
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
        pythOracle = payable(vm.parseJsonAddress(json, ".pythOracle"));
        settlementEngine = payable(vm.parseJsonAddress(json, ".settlementEngine"));
        positionManager = payable(vm.parseJsonAddress(json, ".positionManager"));
        vaultManager = payable(vm.parseJsonAddress(json, ".vaultManager"));
        vaultAdminProxy = payable(vm.parseJsonAddress(json, ".vaultAdminProxy"));
        priceFeedManager = payable(vm.parseJsonAddress(json, ".priceFeedManager"));
        tokenFaucet = payable(vm.parseJsonAddress(json, ".tokenFaucet"));

        // Governance contracts
        multisigWallet = vm.parseJsonAddress(json, ".multisigWallet");
        timelockController = vm.parseJsonAddress(json, ".timelockController");
        vaultBeacon = vm.parseJsonAddress(json, ".vaultBeacon");
        vaultAccessController = vm.parseJsonAddress(json, ".vaultAccessController");

        // Modular Vault components
        vaultRouterImpl = vm.parseJsonAddress(json, ".vaultRouterImpl");
        vaultCoreModule = vm.parseJsonAddress(json, ".vaultCoreModule");
        vaultFundingModule = vm.parseJsonAddress(json, ".vaultFundingModule");
        vaultRewardsModule = vm.parseJsonAddress(json, ".vaultRewardsModule");

        console.log("Deployment addresses loaded from:", file);
    }
}
