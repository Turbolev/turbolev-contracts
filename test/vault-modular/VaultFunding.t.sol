// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./BaseTestModular.sol";

/**
 * @title VaultFundingTest
 * @notice Tests for VaultFunding module - price impact calculations
 */
contract VaultFundingTest is BaseTestModular {
    // ========================================================================
    // PRICE IMPACT INITIALIZATION
    // ========================================================================

    function test_ImpactInitialized() public view {
        assertTrue(vault.isImpactEnabled());

        (uint256 longExp, uint256 shortExp,,,,) = vault.getImpactStats();
        assertEq(longExp, 0);
        assertEq(shortExp, 0);
    }

    function test_GetImpactConfig() public view {
        (uint16 t1, uint16 t2, uint16 t3, uint16 t4, uint16 t5) = vault.getImpactConfig();

        assertGe(t1, 0);
        assertGe(t2, t1);
        assertGe(t3, t2);
        assertGe(t4, t3);
        assertGe(t5, t4);
        assertLe(t5, 200); // Max 2%
    }

    // ========================================================================
    // GET EXECUTION PRICE
    // ========================================================================

    function test_GetExecutionPrice_NoExposure() public view {
        uint256 markPrice = 1000e18;
        uint8 direction = 1; // LONG
        uint256 positionSize = 100e18; // notional = collateral * leverage

        (uint256 execPrice, uint256 impactFee, uint256 impactBps, bool isCrowded) =
            vault.getExecutionPrice(markPrice, direction, positionSize);

        // No exposure → no impact
        assertEq(execPrice, markPrice);
        assertEq(impactFee, 0);
        assertEq(impactBps, 0);
        assertFalse(isCrowded);
    }

    function test_GetExecutionPrice_ImpactDisabled() public {
        vm.prank(address(vaultManager));
        vault.setImpactEnabled(false);

        uint256 markPrice = 1000e18;
        uint256 positionSize = 100e18;
        (uint256 execPrice, uint256 impactFee,,) =
            vault.getExecutionPrice(markPrice, 1, positionSize);

        assertEq(execPrice, markPrice);
        assertEq(impactFee, 0);
    }

    // ========================================================================
    // CURRENT IMPACT RATE
    // ========================================================================

    function test_GetCurrentImpactRate_NoExposure() public view {
        (uint256 impactBps, bool isLongDominant, uint256 imbalanceBps) =
            vault.getCurrentImpactRate();

        assertEq(impactBps, 0);
        assertEq(imbalanceBps, 0);
    }

    function test_GetCurrentImpactRate_ImpactDisabled() public {
        vm.prank(address(vaultManager));
        vault.setImpactEnabled(false);

        (uint256 impactBps,,) = vault.getCurrentImpactRate();
        assertEq(impactBps, 0);
    }

    // ========================================================================
    // SET IMPACT CONFIG
    // ========================================================================

    function test_SetImpactConfig() public {
        uint16 newTier1 = 5;
        uint16 newTier2 = 15;
        uint16 newTier3 = 30;
        uint16 newTier4 = 50;
        uint16 newTier5 = 100;

        vm.prank(address(vaultManager));
        vault.setImpactConfig(newTier1, newTier2, newTier3, newTier4, newTier5);

        (uint16 t1, uint16 t2, uint16 t3, uint16 t4, uint16 t5) = vault.getImpactConfig();
        assertEq(t1, newTier1);
        assertEq(t2, newTier2);
        assertEq(t3, newTier3);
        assertEq(t4, newTier4);
        assertEq(t5, newTier5);
    }

    function test_SetImpactConfig_RevertIfNotAuthorized() public {
        vm.prank(user1);
        vm.expectRevert();
        vault.setImpactConfig(5, 15, 30, 50, 100);
    }

    // ========================================================================
    // SET IMPACT ENABLED
    // ========================================================================

    function test_SetImpactEnabled_Disable() public {
        assertTrue(vault.isImpactEnabled());

        vm.prank(address(vaultManager));
        vault.setImpactEnabled(false);

        assertFalse(vault.isImpactEnabled());
    }

    function test_SetImpactEnabled_ReEnable() public {
        vm.prank(address(vaultManager));
        vault.setImpactEnabled(false);
        assertFalse(vault.isImpactEnabled());

        vm.prank(address(vaultManager));
        vault.setImpactEnabled(true);
        assertTrue(vault.isImpactEnabled());
    }

    // ========================================================================
    // EXPOSURE TRACKING
    // ========================================================================

    function test_ExposureTracking_Initial() public view {
        assertEq(vault.totalLongExposure(), 0);
        assertEq(vault.totalShortExposure(), 0);
    }
}
