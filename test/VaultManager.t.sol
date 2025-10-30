// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./BaseTest.sol";

/**
 * @title VaultManagerTest
 * @notice Unit tests for VaultManager contract
 */
contract VaultManagerTest is BaseTest {
    function test_GetVault_Success() public {
        address vaultAddr = vaultManager.getVault(address(projectToken));

        assertEq(vaultAddr, address(assetVault), "Vault should match");
        assertTrue(vaultManager.isValidVault(vaultAddr), "Vault should be valid");
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
        assertEq(ver, "1.0.0-vault-manager", "Version should match");
    }
}
