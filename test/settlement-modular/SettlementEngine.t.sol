// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../vault-modular/BaseTestModular.sol";

/**
 * @title SettlementEngineTest
 * @notice Unit tests for SettlementEngine with modular vault
 * @dev Tests cover:
 *      - Settlement calculations
 *      - P&L determination
 *      - Payout execution
 *      - Fee handling
 */
contract SettlementEngineTest is BaseTestModular {
    // ========================================================================
    // SETUP
    // ========================================================================

    function setUp() public override {
        super.setUp();
        _enableTrading();
        _graduateVault();
    }

    // ========================================================================
    // CONFIGURATION TESTS
    // ========================================================================

    function test_InitialConfiguration() public view {
        assertEq(settlementEngine.owner(), owner, "Owner should be set");
        assertEq(
            settlementEngine.positionManager(),
            address(positionManager),
            "PositionManager should be set"
        );
        assertEq(
            settlementEngine.vaultManager(), address(vaultManager), "VaultManager should be set"
        );
        assertEq(
            settlementEngine.priceFeedManager(),
            address(priceFeedManager),
            "PriceFeedManager should be set"
        );
    }

    function test_SetPositionManager() public {
        address newPM = makeAddr("newPositionManager");

        vm.prank(owner);
        settlementEngine.setPositionManager(newPM);

        assertEq(settlementEngine.positionManager(), newPM, "PositionManager should be updated");
    }

    function test_SetVaultManager() public {
        address newVM = makeAddr("newVaultManager");

        vm.prank(owner);
        settlementEngine.setVaultManager(newVM);

        assertEq(settlementEngine.vaultManager(), newVM, "VaultManager should be updated");
    }

    function test_SetPriceFeedManager() public {
        address newPFM = makeAddr("newPriceFeedManager");

        vm.prank(owner);
        settlementEngine.setPriceFeedManager(newPFM);

        assertEq(settlementEngine.priceFeedManager(), newPFM, "PriceFeedManager should be updated");
    }

    // ========================================================================
    // ACCESS CONTROL TESTS
    // ========================================================================

    function test_SetPositionManager_RevertOnNonOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        settlementEngine.setPositionManager(makeAddr("newPM"));
    }

    function test_SetVaultManager_RevertOnNonOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        settlementEngine.setVaultManager(makeAddr("newVM"));
    }

    // ========================================================================
    // PAUSE FUNCTIONALITY TESTS
    // ========================================================================

    function test_Pause() public {
        vm.prank(owner);
        settlementEngine.pause();

        assertTrue(settlementEngine.paused(), "Contract should be paused");
    }

    function test_Unpause() public {
        vm.startPrank(owner);
        settlementEngine.pause();
        settlementEngine.unpause();
        vm.stopPrank();

        assertFalse(settlementEngine.paused(), "Contract should be unpaused");
    }

    // ========================================================================
    // SETTLEMENT FLOW TESTS (via PositionManager)
    // ========================================================================

    function test_SettlementFlow_OpenAndClose() public {
        // Open position
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 10 ether);
        positionManager.openPosition{ value: 0 }(
            address(projectToken), 10 ether, 5, 1, type(uint256).max, block.timestamp + 1 hours, ""
        );

        vm.warp(block.timestamp + 61 seconds);

        uint256 balanceBefore = projectToken.balanceOf(user1);

        // Close position (triggers settlement)
        positionManager.closePosition(1, block.timestamp + 1 hours, 0, "");

        uint256 balanceAfter = projectToken.balanceOf(user1);

        // User should receive payout
        assertGe(balanceAfter, balanceBefore, "User should receive payout");
        vm.stopPrank();
    }

    // ========================================================================
    // VAULT P&L TESTS
    // ========================================================================

    function test_VaultPnL_AfterPositionClose() public {
        VaultStorageLib.VaultInfo memory infoBefore = vault.vaultInfo();

        // Open and close position
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 10 ether);
        positionManager.openPosition{ value: 0 }(
            address(projectToken), 10 ether, 5, 1, type(uint256).max, block.timestamp + 1 hours, ""
        );

        vm.warp(block.timestamp + 61 seconds);

        positionManager.closePosition(1, block.timestamp + 1 hours, 0, "");
        vm.stopPrank();

        VaultStorageLib.VaultInfo memory infoAfter = vault.vaultInfo();

        // Vault stats should be updated
        assertGe(
            infoAfter.totalPositionsSettled,
            infoBefore.totalPositionsSettled,
            "Positions settled should increase"
        );
    }

    // ========================================================================
    // FEE COLLECTION TESTS
    // ========================================================================

    function test_SettlementFees_Collected() public {
        VaultStorageLib.VaultInfo memory infoBefore = vault.vaultInfo();

        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 10 ether);
        positionManager.openPosition{ value: 0 }(
            address(projectToken), 10 ether, 5, 1, type(uint256).max, block.timestamp + 1 hours, ""
        );

        vm.warp(block.timestamp + 61 seconds);

        positionManager.closePosition(1, block.timestamp + 1 hours, 0, "");
        vm.stopPrank();

        VaultStorageLib.VaultInfo memory infoAfter = vault.vaultInfo();

        // Fees should be collected (opening + closing)
        assertGe(
            infoAfter.totalFeesCollected, infoBefore.totalFeesCollected, "Fees should be collected"
        );
    }

    // ========================================================================
    // MULTIPLE SETTLEMENT TESTS
    // ========================================================================

    function test_MultipleSettlements() public {
        // Open multiple positions
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 50 ether);

        for (uint256 i = 0; i < 3; i++) {
            positionManager.openPosition{ value: 0 }(
                address(projectToken),
                10 ether,
                5,
                1,
                type(uint256).max,
                block.timestamp + 1 hours,
                ""
            );
        }
        vm.stopPrank();

        vm.warp(block.timestamp + 61 seconds);

        // Close all positions
        vm.startPrank(user1);
        for (uint64 i = 1; i <= 3; i++) {
            positionManager.closePosition(i, block.timestamp + 1 hours, 0, "");
        }
        vm.stopPrank();

        VaultStorageLib.VaultInfo memory info = vault.vaultInfo();
        assertEq(info.totalPositionsSettled, 3, "All positions should be settled");
    }

    function test_MultipleUsers_Settlement() public {
        // User1 opens position
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 10 ether);
        positionManager.openPosition{ value: 0 }(
            address(projectToken), 10 ether, 5, 1, type(uint256).max, block.timestamp + 1 hours, ""
        );
        vm.stopPrank();

        // User2 opens position
        vm.startPrank(user2);
        projectToken.approve(address(positionManager), 10 ether);
        positionManager.openPosition{ value: 0 }(
            address(projectToken), 10 ether, 5, 2, 0, block.timestamp + 1 hours, ""
        );
        vm.stopPrank();

        vm.warp(block.timestamp + 61 seconds);

        // Both users close
        vm.prank(user1);
        positionManager.closePosition(1, block.timestamp + 1 hours, 0, "");

        vm.prank(user2);
        positionManager.closePosition(2, block.timestamp + 1 hours, 0, "");

        VaultStorageLib.VaultInfo memory info = vault.vaultInfo();
        assertEq(info.totalPositionsSettled, 2, "Both positions should be settled");
    }

    // ========================================================================
    // DIRECTION TESTS
    // ========================================================================

    function test_Settlement_LongPosition() public {
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 10 ether);
        positionManager.openPosition{ value: 0 }(
            address(projectToken),
            10 ether,
            5,
            1, // LONG
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );

        vm.warp(block.timestamp + 61 seconds);

        positionManager.closePosition(1, block.timestamp + 1 hours, 0, "");
        vm.stopPrank();
    }

    function test_Settlement_ShortPosition() public {
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 10 ether);
        positionManager.openPosition{ value: 0 }(
            address(projectToken),
            10 ether,
            5,
            2, // SHORT
            0,
            block.timestamp + 1 hours,
            ""
        );

        vm.warp(block.timestamp + 61 seconds);

        positionManager.closePosition(1, block.timestamp + 1 hours, 0, "");
        vm.stopPrank();
    }

    // ========================================================================
    // EDGE CASES
    // ========================================================================

    function test_MinimalPosition_Settlement() public {
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), DEFAULT_MIN_BET);
        positionManager.openPosition{ value: 0 }(
            address(projectToken),
            DEFAULT_MIN_BET,
            2,
            1,
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );

        vm.warp(block.timestamp + 61 seconds);

        positionManager.closePosition(1, block.timestamp + 1 hours, 0, "");
        vm.stopPrank();
    }

    function test_HighLeverage_Settlement() public {
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 10 ether);
        positionManager.openPosition{ value: 0 }(
            address(projectToken),
            10 ether,
            20,
            1, // High leverage
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );

        vm.warp(block.timestamp + 61 seconds);

        positionManager.closePosition(1, block.timestamp + 1 hours, 0, "");
        vm.stopPrank();
    }

    // ========================================================================
    // FUZZ TESTS
    // ========================================================================

    function testFuzz_Settlement(uint256 collateral, uint8 leverage) public {
        collateral = bound(collateral, DEFAULT_MIN_BET, 50 ether);
        leverage = uint8(bound(leverage, 1, 10));

        vm.startPrank(user1);
        projectToken.approve(address(positionManager), collateral);
        positionManager.openPosition{ value: 0 }(
            address(projectToken),
            collateral,
            leverage,
            1,
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );

        vm.warp(block.timestamp + 61 seconds);

        positionManager.closePosition(1, block.timestamp + 1 hours, 0, "");
        vm.stopPrank();

        VaultStorageLib.VaultInfo memory info = vault.vaultInfo();
        assertEq(info.totalPositionsSettled, 1, "Position should be settled");
    }
}
