// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "./DeployHelper.s.sol";
import "../src/governance/MultisigWallet.sol";
import "../src/governance/VersionedBeacon.sol";
import "../src/vault-modular/VaultAccessController.sol";
import "../src/vault-modular/VaultRouter.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployGovernanceModular
 * @notice Deploy governance contracts for modular vault system
 * @dev Deploys:
 *      1. MultisigWallet - M-of-N multisig for proposals
 *      2. TimelockController (OpenZeppelin) - Time delay for governance
 *      3. VaultRouter implementation - Initial vault implementation
 *      4. VersionedBeacon - Beacon with version tracking
 *      5. VaultAccessController - Centralized access control (single source of truth)
 *
 * Architecture:
 * - TimelockController: DEFAULT_ADMIN_ROLE holder, controls critical operations
 * - MultisigWallet: EMERGENCY_ROLE holder, can pause without delay
 * - VaultAccessController: Central access control for all vault operations
 *
 * Usage:
 *   export MULTISIG_OWNERS="0x1111...,0x2222...,0x3333..."
 *   export MULTISIG_THRESHOLD=2
 *   export TIMELOCK_DELAY=86400  # 1 day
 *
 *   forge script script/DeployGovernanceModular.s.sol:DeployGovernanceModular \
 *     --rpc-url $RPC_URL --broadcast
 */
contract DeployGovernanceModular is DeployHelper {
    // Deployed contracts
    address public deployedMultisig;
    address public deployedTimelock;
    address public deployedBeacon;
    address public deployedAccessController;
    address public deployedVaultRouterImpl;

    // Config
    uint256 public constant DEFAULT_TIMELOCK_DELAY = 1 days;
    uint256 public constant DEFAULT_THRESHOLD = 2;

    function run() public {
        vm.startBroadcast(deployer);

        console.log("\n===========================================");
        console.log("Deploying Governance Contracts (Modular)");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("===========================================\n");

        // 1. Deploy MultisigWallet
        _deployMultisigWallet();

        // 2. Deploy TimelockController (OpenZeppelin)
        _deployTimelockController();

        // 3. Deploy VaultRouter implementation
        _deployVaultRouterImpl();

        // 4. Deploy VersionedBeacon
        _deployVersionedBeacon();

        // 5. Deploy VaultAccessController
        _deployVaultAccessController();

        // Print summary
        _printSummary();

        vm.stopBroadcast();
    }

    function _deployMultisigWallet() internal {
        console.log("\n--- Deploying MultisigWallet ---");

        // Get owners from env or use defaults
        string memory ownersEnv = vm.envOr("MULTISIG_OWNERS", string(""));
        address[] memory owners;

        if (bytes(ownersEnv).length > 0) {
            owners = _parseAddresses(ownersEnv);
        } else {
            // Default: deployer and admin
            owners = new address[](2);
            owners[0] = deployer;
            owners[1] = admin;
            console.log("Using default owners: deployer and admin");
        }

        uint256 threshold = vm.envOr("MULTISIG_THRESHOLD", DEFAULT_THRESHOLD);
        require(threshold <= owners.length, "Threshold exceeds owner count");

        deployedMultisig = address(new MultisigWallet(owners, threshold));

        console.log("MultisigWallet deployed:", deployedMultisig);
        console.log("Owners:", owners.length);
        console.log("Threshold:", threshold);
    }

    function _deployTimelockController() internal {
        console.log("\n--- Deploying TimelockController (OpenZeppelin) ---");

        uint256 minDelay = vm.envOr("TIMELOCK_DELAY", DEFAULT_TIMELOCK_DELAY);

        // Proposers: MultisigWallet
        address[] memory proposers = new address[](1);
        proposers[0] = deployedMultisig;

        // Executors: MultisigWallet + admin
        address[] memory executors = new address[](2);
        executors[0] = deployedMultisig;
        executors[1] = admin;

        // Deploy TimelockController
        // admin = deployer initially, will renounce later if needed
        deployedTimelock = address(new TimelockController(minDelay, proposers, executors, deployer));

        console.log("TimelockController deployed:", deployedTimelock);
        console.log("Min Delay:", minDelay, "seconds");
    }

    function _deployVaultRouterImpl() internal {
        console.log("\n--- Deploying VaultRouter Implementation ---");

        deployedVaultRouterImpl = address(new VaultRouter());

        console.log("VaultRouter Implementation deployed:", deployedVaultRouterImpl);
    }

    function _deployVersionedBeacon() internal {
        console.log("\n--- Deploying VersionedBeacon ---");

        // Owner is Timelock for governance control
        // Initial admin is deployer for emergency operations
        deployedBeacon =
            address(new VersionedBeacon(deployedVaultRouterImpl, deployedTimelock, deployer));

        console.log("VersionedBeacon deployed:", deployedBeacon);
        console.log("Initial implementation:", deployedVaultRouterImpl);
        console.log("Owner (Timelock):", deployedTimelock);
        console.log("Initial Admin:", deployer);
    }

    function _deployVaultAccessController() internal {
        console.log("\n--- Deploying VaultAccessController ---");

        // VaultManager must be set before deployment (or set later via setVaultManager)
        address _vaultManager = vaultManager;
        if (_vaultManager == address(0)) {
            _vaultManager = vm.envOr("VAULT_MANAGER_ADDRESS", address(0));
        }

        // PositionManager
        address _positionManager = positionManager;
        if (_positionManager == address(0)) {
            _positionManager = vm.envOr("POSITION_MANAGER_ADDRESS", address(0));
        }

        // Deploy implementation
        VaultAccessController accessControllerImpl = new VaultAccessController();

        // If dependencies not set, use placeholder and configure later
        address initVaultManager = _vaultManager != address(0) ? _vaultManager : deployer;
        address initPositionManager = _positionManager != address(0) ? _positionManager : deployer;

        // Prepare init data
        bytes memory initData = abi.encodeWithSelector(
            VaultAccessController.initialize.selector,
            deployedTimelock, // admin = Timelock
            initVaultManager,
            initPositionManager,
            deployedMultisig // multisig for EMERGENCY_ROLE
        );

        // Deploy proxy
        ERC1967Proxy accessControllerProxy =
            new ERC1967Proxy(address(accessControllerImpl), initData);
        deployedAccessController = address(accessControllerProxy);

        console.log("VaultAccessController deployed:", deployedAccessController);
        console.log("Admin (Timelock):", deployedTimelock);
        console.log("Emergency Role (Multisig):", deployedMultisig);

        if (_vaultManager == address(0)) {
            console.log(
                "WARNING: VaultManager not set. Call setVaultManager() after VaultManager is deployed"
            );
        }
        if (_positionManager == address(0)) {
            console.log(
                "WARNING: PositionManager not set. Grant POSITION_MANAGER_ROLE after deployment"
            );
        }
    }

    function _printSummary() internal view {
        console.log("\n===========================================");
        console.log("GOVERNANCE DEPLOYMENT SUMMARY (MODULAR)");
        console.log("===========================================");
        console.log("MultisigWallet:", deployedMultisig);
        console.log("TimelockController:", deployedTimelock);
        console.log("VersionedBeacon:", deployedBeacon);
        console.log("VaultAccessController:", deployedAccessController);
        console.log("VaultRouter Implementation:", deployedVaultRouterImpl);
        console.log("===========================================");
        console.log("\n=== Environment Variables ===");
        console.log("Add these to your .env file:");
        console.log("MULTISIG_WALLET_ADDRESS=", deployedMultisig);
        console.log("TIMELOCK_ADDRESS=", deployedTimelock);
        console.log("VAULT_BEACON_ADDRESS=", deployedBeacon);
        console.log("VAULT_ACCESS_CONTROLLER_ADDRESS=", deployedAccessController);
        console.log("VAULT_ROUTER_IMPL_ADDRESS=", deployedVaultRouterImpl);
    }

    /**
     * @notice Parse comma-separated addresses from string
     */
    function _parseAddresses(string memory input) internal pure returns (address[] memory) {
        // Count commas to determine array size
        bytes memory inputBytes = bytes(input);
        uint256 count = 1;
        for (uint256 i = 0; i < inputBytes.length; i++) {
            if (inputBytes[i] == ",") {
                count++;
            }
        }

        address[] memory result = new address[](count);

        // Simple parsing - assumes valid input
        uint256 idx = 0;
        uint256 start = 0;
        for (uint256 i = 0; i <= inputBytes.length; i++) {
            if (i == inputBytes.length || inputBytes[i] == ",") {
                bytes memory addrBytes = new bytes(i - start);
                for (uint256 j = start; j < i; j++) {
                    addrBytes[j - start] = inputBytes[j];
                }
                result[idx] = vm.parseAddress(string(addrBytes));
                idx++;
                start = i + 1;
            }
        }

        return result;
    }
}

/**
 * @title DeployMultisigOnly
 * @notice Deploy only MultisigWallet
 */
contract DeployMultisigOnly is DeployHelper {
    function run() public {
        vm.startBroadcast(deployer);

        address[] memory owners = new address[](3);
        owners[0] = deployer;
        owners[1] = admin;
        owners[2] = vm.envOr("THIRD_OWNER", address(0));

        if (owners[2] == address(0)) {
            // Use 2 owners
            address[] memory twoOwners = new address[](2);
            twoOwners[0] = owners[0];
            twoOwners[1] = owners[1];
            owners = twoOwners;
        }

        uint256 threshold = vm.envOr("MULTISIG_THRESHOLD", uint256(2));
        if (threshold > owners.length) threshold = owners.length;

        address multisig = address(new MultisigWallet(owners, threshold));

        _logDeployment("MultisigWallet", multisig);
        console.log("Owners:", owners.length);
        console.log("Threshold:", threshold);

        vm.stopBroadcast();
    }
}
