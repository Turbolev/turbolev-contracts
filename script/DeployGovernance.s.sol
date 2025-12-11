// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "./DeployHelper.s.sol";
import "../src/governance/MultisigWallet.sol";
import "../src/governance/VersionedBeacon.sol";
import "../src/governance/VaultGovernor.sol";
import "../src/legacy/AssetVaultUpgradeable.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @title DeployGovernance
 * @notice Script to deploy governance contracts
 * @dev Deploys MultisigWallet, VersionedBeacon, TimelockController, and VaultGovernor
 *
 * Deployment Order:
 * 1. MultisigWallet - M-of-N multisig for proposals
 * 2. TimelockController - Time delay for governance actions
 * 3. AssetVaultUpgradeable implementation - Initial vault implementation
 * 4. VersionedBeacon - Beacon with version tracking (owned by Timelock)
 * 5. VaultGovernor - Vault-specific governance
 *
 * Usage:
 *   # Set environment variables first
 *   export MULTISIG_OWNERS="0x1111...,0x2222...,0x3333..."
 *   export MULTISIG_THRESHOLD=2
 *   export TIMELOCK_DELAY=86400  # 1 day
 *   export GUARDIANS="0x4444...,0x5555..."
 *
 *   forge script script/DeployGovernance.s.sol:DeployGovernance \
 *     --rpc-url $RPC_URL --broadcast
 */
contract DeployGovernance is DeployHelper {
    // Deployed contracts (use different names to avoid override conflicts with DeployHelper)
    address public deployedMultisig;
    address public deployedTimelock;
    address public deployedBeacon;
    address public deployedGovernor;
    address public deployedVaultImpl;

    // Config
    uint256 public constant DEFAULT_TIMELOCK_DELAY = 1 days;
    uint256 public constant DEFAULT_THRESHOLD = 2;

    function run() public {
        vm.startBroadcast(deployer);

        console.log("\n===========================================");
        console.log("Deploying Governance Contracts");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("===========================================\n");

        // 1. Deploy MultisigWallet
        _deployMultisigWallet();

        // 2. Deploy TimelockController
        _deployTimelockController();

        // 3. Deploy initial vault implementation
        _deployVaultImplementation();

        // 4. Deploy VersionedBeacon
        _deployVersionedBeacon();

        // 5. Deploy VaultGovernor
        _deployVaultGovernor();

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
            // Parse comma-separated addresses
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
        console.log("\n--- Deploying TimelockController ---");

        uint256 minDelay = vm.envOr("TIMELOCK_DELAY", DEFAULT_TIMELOCK_DELAY);

        // Proposers: MultisigWallet
        address[] memory proposers = new address[](1);
        proposers[0] = deployedMultisig;

        // Executors: MultisigWallet + admin
        address[] memory executors = new address[](2);
        executors[0] = deployedMultisig;
        executors[1] = admin;

        deployedTimelock = address(new TimelockController(minDelay, proposers, executors, deployer));

        console.log("TimelockController deployed:", deployedTimelock);
        console.log("Min Delay:", minDelay, "seconds");
    }

    function _deployVaultImplementation() internal {
        console.log("\n--- Deploying AssetVaultUpgradeable Implementation ---");

        deployedVaultImpl = address(new AssetVaultUpgradeable());

        console.log("Vault Implementation deployed:", deployedVaultImpl);
    }

    function _deployVersionedBeacon() internal {
        console.log("\n--- Deploying VersionedBeacon ---");

        // Owner is Timelock for governance control
        // Initial admin is deployer for emergency operations
        deployedBeacon = address(new VersionedBeacon(deployedVaultImpl, deployedTimelock, deployer));

        console.log("VersionedBeacon deployed:", deployedBeacon);
        console.log("Initial implementation:", deployedVaultImpl);
        console.log("Owner (Timelock):", deployedTimelock);
        console.log("Initial Admin:", deployer);
    }

    function _deployVaultGovernor() internal {
        console.log("\n--- Deploying VaultGovernor ---");

        // Get guardians from env or use defaults
        string memory guardiansEnv = vm.envOr("GUARDIANS", string(""));
        address[] memory guardians;

        if (bytes(guardiansEnv).length > 0) {
            guardians = _parseAddresses(guardiansEnv);
        } else {
            // Default: admin as guardian
            guardians = new address[](1);
            guardians[0] = admin;
            console.log("Using default guardian: admin");
        }

        // VaultManager must be set before deployment
        address _vaultManager = vaultManager;
        if (_vaultManager == address(0)) {
            _vaultManager = vm.envOr("VAULT_MANAGER_ADDRESS", address(0));
        }

        if (_vaultManager == address(0)) {
            console.log(
                "WARNING: VaultManager not set. VaultGovernor will be deployed with address(0)"
            );
            console.log("You must call setVaultManager() after VaultManager is deployed");
            _vaultManager = address(1); // Placeholder - will revert in VaultGovernor constructor
        }

        deployedGovernor = address(
            new VaultGovernor(
                deployedTimelock, deployedMultisig, _vaultManager, deployedBeacon, guardians, admin
            )
        );

        console.log("VaultGovernor deployed:", deployedGovernor);
        console.log("Guardians:", guardians.length);
    }

    function _printSummary() internal view {
        console.log("\n===========================================");
        console.log("GOVERNANCE DEPLOYMENT SUMMARY");
        console.log("===========================================");
        console.log("MultisigWallet:", deployedMultisig);
        console.log("TimelockController:", deployedTimelock);
        console.log("VersionedBeacon:", deployedBeacon);
        console.log("VaultGovernor:", deployedGovernor);
        console.log("Vault Implementation V1:", deployedVaultImpl);
        console.log("===========================================");
        console.log("\n=== Environment Variables ===");
        console.log("Add these to your .env file:");
        console.log("MULTISIG_WALLET_ADDRESS=", deployedMultisig);
        console.log("TIMELOCK_ADDRESS=", deployedTimelock);
        console.log("VAULT_BEACON_ADDRESS=", deployedBeacon);
        console.log("VAULT_GOVERNOR_ADDRESS=", deployedGovernor);
        console.log("VAULT_IMPLEMENTATION_ADDRESS=", deployedVaultImpl);
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
