// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../DeployHelper.s.sol";
import "../../src/VaultManager.sol";

/**
 * @title InteractVaultManager
 * @notice Script to interact with VaultManager contract
 * @dev Includes view functions and admin functions
 */
contract InteractVaultManager is DeployHelper {
    VaultManager public vaultMgr;

    function setUp() public override {
        super.setUp();

        // Load vault manager address from env or deployment file
        address vaultMgrAddr = vm.envOr("VAULT_MANAGER_ADDRESS", vaultManager);
        require(vaultMgrAddr != address(0), "Vault Manager address not set");
        vaultMgr = VaultManager(vaultMgrAddr);

        console.log("Vault Manager Address:", address(vaultMgr));
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /**
     * @notice View vault manager configuration
     */
    function viewConfig() public view {
        console.log("\n=== Vault Manager Configuration ===");
        console.log("Owner:", vaultMgr.owner());
        console.log("Position Manager:", vaultMgr.positionManager());
        console.log("Settlement Engine:", vaultMgr.settlementEngine());
        console.log("Paused:", vaultMgr.paused());
        console.log("Total Vaults:", vaultMgr.getVaultCount());
    }

    /**
     * @notice Get vault address for a project token
     */
    function getVault(address projectToken) public view {
        console.log("\n=== Get Vault ===");
        console.log("Project Token:", projectToken);

        try vaultMgr.getVault(projectToken) returns (address vaultAddr) {
            console.log("Vault Address:", vaultAddr);
        } catch Error(string memory reason) {
            console.log("Error:", reason);
        }
    }

    /**
     * @notice Check if vault exists for project token
     */
    function isVaultSupported(address projectToken) public view {
        console.log("\n=== Is Vault Supported ===");
        console.log("Project Token:", projectToken);

        bool supported = vaultMgr.isVaultSupported(projectToken);
        console.log("Is Supported:", supported);
    }

    /**
     * @notice Get all vault addresses
     */
    function getAllVaults() public view {
        console.log("\n=== All Vaults ===");

        address[] memory vaults = vaultMgr.getAllVaults();
        console.log("Total Vaults:", vaults.length);

        for (uint256 i = 0; i < vaults.length; i++) {
            console.log("Vault", i, ":", vaults[i]);
            address projectToken = vaultMgr.getVaultProjectToken(vaults[i]);
            console.log("  Project Token:", projectToken);
        }
    }

    /**
     * @notice Check if vault is graduated
     */
    function isVaultGraduated(address vaultAddress) public view {
        console.log("\n=== Is Vault Graduated ===");
        console.log("Vault Address:", vaultAddress);

        bool graduated = vaultMgr.isVaultGraduated(vaultAddress);
        console.log("Is Graduated:", graduated);
    }

    /**
     * @notice Get vault project token
     */
    function getVaultProjectToken(address vaultAddress) public view {
        console.log("\n=== Get Vault Project Token ===");
        console.log("Vault Address:", vaultAddress);

        address projectToken = vaultMgr.getVaultProjectToken(vaultAddress);
        console.log("Project Token:", projectToken);
    }

    /**
     * @notice Check position risk
     */
    function checkPositionRisk(address projectToken, uint256 positionSize, uint8 leverage)
        public
        view
    {
        console.log("\n=== Check Position Risk ===");
        console.log("Project Token:", projectToken);
        console.log("Position Size:", positionSize);
        console.log("Leverage:", leverage);

        (bool canOpen, string memory reason) =
            vaultMgr.checkPositionRisk(projectToken, positionSize, leverage);

        console.log("Can Open:", canOpen);
        if (!canOpen) {
            console.log("Reason:", reason);
        }
    }

    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================

    /**
     * @notice Create a new vault
     */
    function createVault(
        address projectToken,
        address projectTokenBase,
        address projectTokenQuote,
        uint16 maxPayoutBps,
        uint16 perBetUtilBps,
        uint16 maxUtilizationBps,
        uint256 minBetAmount,
        uint256 maxBetAmount,
        uint256 graduationThreshold
    ) public {
        console.log("\n=== Create Vault ===");
        console.log("Project Token:", projectToken);
        console.log("Project Token Base:", projectTokenBase);
        console.log("Project Token Quote:", projectTokenQuote);
        console.log("Max Payout BPS:", maxPayoutBps);
        console.log("Per Bet Util BPS:", perBetUtilBps);
        console.log("Max Utilization BPS:", maxUtilizationBps);
        console.log("Min Bet Amount:", minBetAmount);
        console.log("Max Bet Amount:", maxBetAmount);
        console.log("Graduation Threshold:", graduationThreshold);

        vm.startBroadcast(deployer);
        address vaultAddr = vaultMgr.createVault(
            projectToken,
            projectTokenBase,
            projectTokenQuote,
            maxPayoutBps,
            perBetUtilBps,
            maxUtilizationBps,
            minBetAmount,
            maxBetAmount,
            graduationThreshold
        );
        console.log("Vault created at:", vaultAddr);
        vm.stopBroadcast();
    }

    /**
     * @notice Set position manager address
     */
    function setPositionManager(address newPositionManager) public {
        console.log("\n=== Set Position Manager ===");
        console.log("New Position Manager:", newPositionManager);

        vm.startBroadcast(deployer);
        vaultMgr.setPositionManager(newPositionManager);
        console.log("Position Manager updated successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Set settlement engine address
     */
    function setSettlementEngine(address newSettlementEngine) public {
        console.log("\n=== Set Settlement Engine ===");
        console.log("New Settlement Engine:", newSettlementEngine);

        vm.startBroadcast(deployer);
        vaultMgr.setSettlementEngine(newSettlementEngine);
        console.log("Settlement Engine updated successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Pause vault manager
     */
    function pauseVaultManager() public {
        console.log("\n=== Pause Vault Manager ===");

        vm.startBroadcast(deployer);
        vaultMgr.pause();
        console.log("Vault Manager paused successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Unpause vault manager
     */
    function unpauseVaultManager() public {
        console.log("\n=== Unpause Vault Manager ===");

        vm.startBroadcast(deployer);
        vaultMgr.unpause();
        console.log("Vault Manager unpaused successfully");
        vm.stopBroadcast();
    }
}
