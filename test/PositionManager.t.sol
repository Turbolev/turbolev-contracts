// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./BaseTest.sol";

/**
 * @title PositionManagerTest
 * @notice Unit tests for PositionManager contract
 * @dev Tests core functions: initialize, getters, admin functions
 */
contract PositionManagerTest is BaseTest {
    // ========================================================================
    // INITIALIZATION TESTS
    // ========================================================================

    function test_Initialize_Success() public {
        assertEq(positionManager.maintenanceMarginRatio(), 2000, "MMR should be 2000");
        assertEq(positionManager.minLeverage(), 1, "Min leverage should be 1");
        assertEq(positionManager.maxLeverage(), 100, "Max leverage should be 100");
        // MIN_POSITION_HOLD_TIME is now 30 seconds in PositionLib
        assertEq(positionManager.minPositionHoldTime(), 30, "Min hold time should be 30");
        // maxSlippageBps has been removed, no need to test anymore
    }

    // ========================================================================
    // GETTER TESTS
    // ========================================================================

    function test_Version_ReturnsCorrectVersion() public {
        string memory ver = positionManager.version();
        assertEq(ver, "1.0.0-position-manager", "Version should match");
    }

    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================

    function test_SetSettlementEngine_Success() public {
        address newSE = makeAddr("newSettlementEngine");
        positionManager.setSettlementEngine(newSE);
        assertEq(positionManager.settlementEngine(), newSE, "Settlement engine should be updated");
    }

    function test_SetSettlementEngine_RevertsOnZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(PositionManager.InvalidAddress.selector));
        positionManager.setSettlementEngine(address(0));
    }

    function test_SetVaultManager_Success() public {
        address newVM = makeAddr("newVaultManager");
        positionManager.setVaultManager(newVM);
        assertEq(positionManager.vaultManager(), newVM, "Vault manager should be updated");
    }

    function test_SetVaultManager_RevertsOnZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(PositionManager.InvalidAddress.selector));
        positionManager.setVaultManager(address(0));
    }

    function test_SetPriceFeedManager_Success() public {
        address newPFM = makeAddr("newPriceFeedManager");
        positionManager.setPriceFeedManager(newPFM);
        assertEq(positionManager.priceFeedManager(), newPFM, "PriceFeedManager should be updated");
    }

    function test_SetPriceFeedManager_RevertsOnZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(PositionManager.InvalidAddress.selector));
        positionManager.setPriceFeedManager(address(0));
    }

    function test_SetMaintenanceMarginRatio_Success() public {
        positionManager.setMaintenanceMarginRatio(3000);
        assertEq(positionManager.maintenanceMarginRatio(), 3000, "MMR should be updated");
    }

    function test_SetMaintenanceMarginRatio_RevertsOnTooHigh() public {
        vm.expectRevert(
            abi.encodeWithSelector(PositionManager.InvalidMaintenanceMarginRatio.selector)
        );
        positionManager.setMaintenanceMarginRatio(10_001);
    }

    function test_SetLeverageLimits_Success() public {
        positionManager.setLeverageLimits(2, 50);
        assertEq(positionManager.minLeverage(), 2, "Min leverage should be 2");
        assertEq(positionManager.maxLeverage(), 50, "Max leverage should be 50");
    }

    function test_SetLeverageLimits_RevertsOnInvalid() public {
        vm.expectRevert(abi.encodeWithSelector(PositionManager.InvalidLeverage.selector));
        positionManager.setLeverageLimits(0, 50);
    }

    function test_SetMinPositionHoldTime_Success() public {
        positionManager.setMinPositionHoldTime(120);
        assertEq(positionManager.minPositionHoldTime(), 120, "Min hold time should be 120");
    }

    function test_SetMinPositionHoldTime_RevertsOnTooLong() public {
        vm.expectRevert(abi.encodeWithSelector(PositionManager.InvalidHoldTime.selector));
        positionManager.setMinPositionHoldTime(3601);
    }

    function test_Pause_Success() public {
        positionManager.pause();
        assertTrue(positionManager.paused(), "Should be paused");
    }

    function test_Unpause_Success() public {
        positionManager.pause();
        positionManager.unpause();
        assertFalse(positionManager.paused(), "Should be unpaused");
    }

    // ========================================================================
    // BACKEND ACCESS CONTROL TESTS
    // ========================================================================

    function test_AddBackend_Success() public {
        address newBackend = makeAddr("newBackend");
        positionManager.addAdmin(newBackend);
        assertTrue(positionManager.isAdmin(newBackend), "Should be admin");
    }

    function test_RemoveBackend_Success() public {
        address backend = makeAddr("backendToRemove");
        positionManager.addAdmin(backend);
        positionManager.removeAdmin(backend);
        assertFalse(positionManager.isAdmin(backend), "Should not be backend");
    }

    function test_GetBackendCount_Success() public {
        uint256 count = positionManager.getAdminCount();
        assertGt(count, 0, "Should have at least 1 admin");
    }
}
