// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../BaseTest.sol";

/**
 * @title VaultManagerTest
 * @notice Unit tests for VaultManager contract
 */
contract VaultManagerTest is BaseTest {
    function test_GetVault_Success() public {
        address vaultAddr = vaultManager.getVault(address(projectToken));

        assertEq(vaultAddr, address(assetVault), "Vault should match");
    }

    function test_SetPositionManager_Success() public {
        address newPM = makeAddr("newPositionManager");
        vaultManager.setPositionManager(newPM);

        assertEq(vaultManager.positionManager(), newPM, "Position manager should be updated");
    }

    function test_SetPositionManager_RevertsOnZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(VaultManager.InvalidAddress.selector));
        vaultManager.setPositionManager(address(0));
    }

    function test_Pause_Success() public {
        vaultManager.pause();
        assertTrue(vaultManager.paused(), "Should be paused");
    }

    function test_Unpause_Success() public {
        vaultManager.pause();
        vaultManager.unpause();
        assertFalse(vaultManager.paused(), "Should be unpaused");
    }

    function test_Version_ReturnsCorrectVersion() public {
        string memory ver = vaultManager.version();
        assertEq(ver, "2.0.0-with-governance", "Version should match");
    }

    // ========================================================================
    // PAUSE/UNPAUSE VAULT TESTS WITH MULTISIG
    // ========================================================================

    function test_PauseVault_WithMultisig_Success() public {
        // Pause vault by multisig
        vm.prank(mockMultisigWallet);
        vaultManager.pauseVault(address(projectToken));

        // Verify vault is paused
        assertTrue(assetVault.paused(), "Vault should be paused");
    }

    function test_UnpauseVault_WithMultisig_Success() public {
        // First pause
        vm.prank(mockMultisigWallet);
        vaultManager.pauseVault(address(projectToken));

        // Then unpause
        vm.prank(mockMultisigWallet);
        vaultManager.unpauseVault(address(projectToken));

        // Verify vault is unpaused
        assertFalse(assetVault.paused(), "Vault should be unpaused");
    }

    function test_PauseVault_WithoutMultisig_Reverts() public {
        // Try to pause with random user
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(VaultManager.NotAuthorized.selector));
        vaultManager.pauseVault(address(projectToken));
    }

    function test_UnpauseVault_WithoutMultisig_Reverts() public {
        // First pause with multisig
        vm.prank(mockMultisigWallet);
        vaultManager.pauseVault(address(projectToken));

        // Try to unpause with random user
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(VaultManager.NotAuthorized.selector));
        vaultManager.unpauseVault(address(projectToken));
    }

    function test_PauseVaultByAddress_WithMultisig_Success() public {
        // Pause vault by address
        vm.prank(mockMultisigWallet);
        vaultManager.pauseVaultByAddress(address(assetVault));

        // Verify vault is paused
        assertTrue(assetVault.paused(), "Vault should be paused");
    }

    function test_UnpauseVaultByAddress_WithMultisig_Success() public {
        // First pause
        vm.prank(mockMultisigWallet);
        vaultManager.pauseVaultByAddress(address(assetVault));

        // Then unpause
        vm.prank(mockMultisigWallet);
        vaultManager.unpauseVaultByAddress(address(assetVault));

        // Verify vault is unpaused
        assertFalse(assetVault.paused(), "Vault should be unpaused");
    }

    function test_BatchPauseVaults_WithMultisig_Success() public {
        // Create another vault for batch testing
        vm.prank(owner);
        address mockToken = makeAddr("mockToken");
        address vault2 = vaultManager.createVaultWithBeacon(
            mockToken, DEFAULT_MIN_BET, DEFAULT_MAX_BET, DEFAULT_GRADUATION_THRESHOLD
        );

        // Prepare array of vaults
        address[] memory vaults = new address[](2);
        vaults[0] = address(assetVault);
        vaults[1] = vault2;

        // Batch pause with multisig
        vm.prank(mockMultisigWallet);
        vaultManager.batchPauseVaults(vaults);

        // Verify both vaults are paused
        assertTrue(assetVault.paused(), "Vault 1 should be paused");
        assertTrue(IAssetVault(vault2).paused(), "Vault 2 should be paused");
    }

    function test_BatchUnpauseVaults_WithMultisig_Success() public {
        // Create another vault
        vm.prank(owner);
        address mockToken = makeAddr("mockToken");
        address vault2 = vaultManager.createVaultWithBeacon(
            mockToken, DEFAULT_MIN_BET, DEFAULT_MAX_BET, DEFAULT_GRADUATION_THRESHOLD
        );

        // Prepare array of vaults
        address[] memory vaults = new address[](2);
        vaults[0] = address(assetVault);
        vaults[1] = vault2;

        // First pause both
        vm.prank(mockMultisigWallet);
        vaultManager.batchPauseVaults(vaults);

        // Then unpause both
        vm.prank(mockMultisigWallet);
        vaultManager.batchUnpauseVaults(vaults);

        // Verify both vaults are unpaused
        assertFalse(assetVault.paused(), "Vault 1 should be unpaused");
        assertFalse(IAssetVault(vault2).paused(), "Vault 2 should be unpaused");
    }

    function test_TimelockController_CannotPauseVault() public {
        // TimelockController should no longer be able to pause vault
        vm.prank(mockTimelockController);
        vm.expectRevert(abi.encodeWithSelector(VaultManager.NotAuthorized.selector));
        vaultManager.pauseVault(address(projectToken));
    }
}
