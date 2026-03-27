// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "./DeployHelper.s.sol";
import "../src/vault-modular/VaultAccessController.sol";
import "../src/vault-modular/VaultRouter.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployGovernanceModular
 * @notice Deploy governance contracts for modular vault system
 * @dev Deploys:
 *      1. TimelockController (OpenZeppelin) - Time delay for governance
 *      2. VaultRouter implementation - Initial vault implementation
 *      3. VaultAccessController - Centralized access control (single source of truth)
 *
 * Architecture:
 * - TimelockController: DEFAULT_ADMIN_ROLE holder, controls critical operations
 * - Gnosis Safe (external): EMERGENCY_ROLE holder, can pause without delay
 * - VaultAccessController: Central access control for all vault operations
 *
 * Usage:
 *   export GNOSIS_SAFE_ADDRESS="0x..."   # Gnosis Safe address for EMERGENCY_ROLE
 *   export TIMELOCK_DELAY=86400          # 1 day
 *
 *   forge script script/DeployGovernanceModular.s.sol:DeployGovernanceModular \
 *     --rpc-url $RPC_URL --broadcast
 */
contract DeployGovernanceModular is DeployHelper {
    // Deployed contracts
    address public deployedTimelock;
    address public deployedAccessController;
    address public deployedVaultRouterImpl;

    // Config
    uint256 public constant DEFAULT_TIMELOCK_DELAY = 1 days;

    function run() public {
        vm.startBroadcast(deployer);

        console.log("\n===========================================");
        console.log("Deploying Governance Contracts (Modular)");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("===========================================\n");

        // 1. Deploy TimelockController (OpenZeppelin)
        _deployTimelockController();

        // 2. Deploy VaultRouter implementation
        _deployVaultRouterImpl();

        // 3. Deploy VaultAccessController
        _deployVaultAccessController();

        // Print summary
        _printSummary();

        vm.stopBroadcast();
    }

    function _deployTimelockController() internal {
        console.log("\n--- Deploying TimelockController (OpenZeppelin) ---");

        uint256 minDelay = vm.envOr("TIMELOCK_DELAY", DEFAULT_TIMELOCK_DELAY);

        // Proposers: admin
        address[] memory proposers = new address[](1);
        proposers[0] = admin;

        // Executors: admin
        address[] memory executors = new address[](1);
        executors[0] = admin;

        deployedTimelock = address(new TimelockController(minDelay, proposers, executors, deployer));

        console.log("TimelockController deployed:", deployedTimelock);
        console.log("Min Delay:", minDelay, "seconds");
    }

    function _deployVaultRouterImpl() internal {
        console.log("\n--- Deploying VaultRouter Implementation ---");

        deployedVaultRouterImpl = address(new VaultRouter());

        console.log("VaultRouter Implementation deployed:", deployedVaultRouterImpl);
    }

    function _deployVaultAccessController() internal {
        console.log("\n--- Deploying VaultAccessController ---");

        address _vaultManager = vaultManager;
        if (_vaultManager == address(0)) {
            _vaultManager = vm.envOr("VAULT_MANAGER_ADDRESS", address(0));
        }

        address _positionManager = positionManager;
        if (_positionManager == address(0)) {
            _positionManager = vm.envOr("POSITION_MANAGER_ADDRESS", address(0));
        }

        // Gnosis Safe address for EMERGENCY_ROLE (optional)
        address gnosisSafe = vm.envOr("GNOSIS_SAFE_ADDRESS", address(0));

        VaultAccessController accessControllerImpl = new VaultAccessController();

        address initVaultManager = _vaultManager != address(0) ? _vaultManager : deployer;
        address initPositionManager = _positionManager != address(0) ? _positionManager : deployer;

        bytes memory initData = abi.encodeWithSelector(
            VaultAccessController.initialize.selector,
            deployedTimelock, // admin = Timelock
            initVaultManager,
            initPositionManager,
            gnosisSafe // Gnosis Safe for EMERGENCY_ROLE (address(0) = skip)
        );

        ERC1967Proxy accessControllerProxy =
            new ERC1967Proxy(address(accessControllerImpl), initData);
        deployedAccessController = address(accessControllerProxy);

        console.log("VaultAccessController deployed:", deployedAccessController);
        console.log("Admin (Timelock):", deployedTimelock);
        if (gnosisSafe != address(0)) {
            console.log("Emergency Role (Gnosis Safe):", gnosisSafe);
        } else {
            console.log("WARNING: No Gnosis Safe set. Grant EMERGENCY_ROLE manually.");
        }

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
        console.log("TimelockController:", deployedTimelock);
        console.log("VaultAccessController:", deployedAccessController);
        console.log("VaultRouter Implementation:", deployedVaultRouterImpl);
        console.log("===========================================");
        console.log("\n=== Environment Variables ===");
        console.log("Add these to your .env file:");
        console.log("TIMELOCK_ADDRESS=", deployedTimelock);
        console.log("VAULT_ACCESS_CONTROLLER_ADDRESS=", deployedAccessController);
        console.log("VAULT_ROUTER_IMPL_ADDRESS=", deployedVaultRouterImpl);
    }
}
