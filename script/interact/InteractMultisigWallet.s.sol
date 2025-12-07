// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../DeployHelper.s.sol";
import "../../src/governance/MultisigWallet.sol";

/**
 * @title InteractMultisigWallet
 * @notice Script to interact with MultisigWallet contract
 * @dev Usage: Set MULTISIG_WALLET_ADDRESS in .env
 */
contract InteractMultisigWallet is DeployHelper {
    MultisigWallet public multisig;

    function setUp() public override {
        super.setUp();
        address multisigAddr = vm.envAddress("MULTISIG_WALLET_ADDRESS");
        require(multisigAddr != address(0), "MULTISIG_WALLET_ADDRESS not set");
        multisig = MultisigWallet(payable(multisigAddr));
        console.log("MultisigWallet Address:", address(multisig));
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    function viewInfo() public view {
        console.log("\n=== MultisigWallet Info ===");
        console.log("Address:", address(multisig));
        console.log("Owner Count:", multisig.getOwnerCount());
        console.log("Threshold:", multisig.threshold());
        console.log("Transaction Count:", multisig.transactionCount());
        console.log("Balance:", address(multisig).balance);
    }

    function viewOwners() public view {
        console.log("\n=== Owners ===");
        address[] memory owners = multisig.getOwners();
        for (uint256 i = 0; i < owners.length; i++) {
            console.log("Owner", i, ":", owners[i]);
        }
    }

    function viewTransaction(uint256 txId) public view {
        console.log("\n=== Transaction", txId, "===");
        (address to, uint256 value, bytes memory data, bool executed, uint256 confirmationCount) =
            multisig.getTransaction(txId);

        console.log("To:", to);
        console.log("Value:", value);
        console.log("Data Length:", data.length);
        console.log("Executed:", executed);
        console.log("Confirmations:", confirmationCount);
        console.log("Required:", multisig.threshold());
    }

    function viewPendingTransactions() public view {
        console.log("\n=== Pending Transactions ===");
        uint256 count = multisig.transactionCount();

        uint256 pendingCount = 0;
        for (uint256 i = 0; i < count; i++) {
            (,,, bool executed, uint256 confirmations) = multisig.getTransaction(i);
            if (!executed) {
                pendingCount++;
                console.log("Tx", i);
                console.log("  Confirmations:", confirmations, "/", multisig.threshold());
            }
        }

        if (pendingCount == 0) {
            console.log("No pending transactions");
        }
    }

    // ========================================================================
    // TRANSACTION FUNCTIONS
    // ========================================================================

    /**
     * @notice Submit a new transaction
     * @param to Target address
     * @param value ETH value
     * @param data Call data (hex encoded)
     */
    function submitTransaction(address to, uint256 value, bytes calldata data) public {
        vm.startBroadcast(deployer);
        uint256 txId = multisig.submitTransaction(to, value, data);
        console.log("Transaction submitted with ID:", txId);
        vm.stopBroadcast();
    }

    /**
     * @notice Submit a simple ETH transfer
     */
    function submitETHTransfer(address to, uint256 value) public {
        vm.startBroadcast(deployer);
        uint256 txId = multisig.submitTransaction(to, value, "");
        console.log("ETH transfer transaction submitted with ID:", txId);
        vm.stopBroadcast();
    }

    /**
     * @notice Confirm a pending transaction
     * @param txId Transaction ID
     */
    function confirmTransaction(uint256 txId) public {
        vm.startBroadcast(deployer);
        multisig.confirmTransaction(txId);
        console.log("Transaction confirmed:", txId);
        vm.stopBroadcast();
    }

    /**
     * @notice Revoke confirmation
     * @param txId Transaction ID
     */
    function revokeConfirmation(uint256 txId) public {
        vm.startBroadcast(deployer);
        multisig.revokeConfirmation(txId);
        console.log("Confirmation revoked:", txId);
        vm.stopBroadcast();
    }

    /**
     * @notice Execute a confirmed transaction
     * @param txId Transaction ID
     */
    function executeTransaction(uint256 txId) public {
        vm.startBroadcast(deployer);
        multisig.executeTransaction(txId);
        console.log("Transaction executed:", txId);
        vm.stopBroadcast();
    }

    // ========================================================================
    // OWNER MANAGEMENT (requires multisig approval)
    // ========================================================================

    /**
     * @notice Submit proposal to add owner
     * @param newOwner New owner address
     */
    function proposeAddOwner(address newOwner) public {
        bytes memory data = abi.encodeWithSignature("addOwner(address)", newOwner);
        vm.startBroadcast(deployer);
        uint256 txId = multisig.submitTransaction(address(multisig), 0, data);
        console.log("Add owner proposal submitted with ID:", txId);
        console.log("New Owner:", newOwner);
        vm.stopBroadcast();
    }

    /**
     * @notice Submit proposal to remove owner
     * @param ownerToRemove Owner address to remove
     */
    function proposeRemoveOwner(address ownerToRemove) public {
        bytes memory data = abi.encodeWithSignature("removeOwner(address)", ownerToRemove);
        vm.startBroadcast(deployer);
        uint256 txId = multisig.submitTransaction(address(multisig), 0, data);
        console.log("Remove owner proposal submitted with ID:", txId);
        console.log("Owner to Remove:", ownerToRemove);
        vm.stopBroadcast();
    }

    /**
     * @notice Submit proposal to change threshold
     * @param newThreshold New threshold value
     */
    function proposeChangeThreshold(uint256 newThreshold) public {
        bytes memory data = abi.encodeWithSignature("changeThreshold(uint256)", newThreshold);
        vm.startBroadcast(deployer);
        uint256 txId = multisig.submitTransaction(address(multisig), 0, data);
        console.log("Change threshold proposal submitted with ID:", txId);
        console.log("New Threshold:", newThreshold);
        vm.stopBroadcast();
    }

    // ========================================================================
    // HELPER FUNCTIONS
    // ========================================================================

    /**
     * @notice Check if an address is an owner
     */
    function isOwner(address addr) public view {
        console.log("\n=== Owner Check ===");
        console.log("Address:", addr);
        console.log("Is Owner:", multisig.isOwner(addr));
    }

    /**
     * @notice Check confirmation status for a transaction
     */
    function checkConfirmation(uint256 txId, address owner) public view {
        console.log("\n=== Confirmation Check ===");
        console.log("Transaction ID:", txId);
        console.log("Owner:", owner);
        console.log("Has Confirmed:", multisig.isConfirmed(txId, owner));
    }
}
