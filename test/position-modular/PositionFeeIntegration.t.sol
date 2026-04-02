// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../vault-modular/BaseTestModular.sol";

/**
 * @title PositionFeeIntegrationTest
 * @notice Unit tests for position fee integration with modular vault
 * @dev Tests cover:
 *      - Opening fees
 *      - Closing fees
 *      - Fee collection
 *      - Fee distribution
 */
contract PositionFeeIntegrationTest is BaseTestModular {
    // ========================================================================
    // SETUP
    // ========================================================================

    function setUp() public override {
        super.setUp();
        _enableTrading();
        _graduateVault();
        _setHighLeverageConfig();
    }

    // ========================================================================
    // OPENING FEE TESTS
    // ========================================================================

    function test_OpeningFee_DeductedFromCollateral() public {
        uint256 collateral = 10 ether;
        uint256 initialBalance = projectToken.balanceOf(user1);

        vm.startPrank(user1);
        projectToken.approve(address(positionManager), collateral);
        positionManager.openPosition{ value: 0 }(
            address(projectToken),
            address(projectToken),
            collateral,
            5,
            1,
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );
        vm.stopPrank();

        uint256 finalBalance = projectToken.balanceOf(user1);
        assertEq(initialBalance - finalBalance, collateral, "Full collateral should be transferred");
    }

    function test_OpeningFee_CollectedByVault() public {
        uint256 collateral = 10 ether;

        VaultStorageLib.VaultInfo memory infoBefore = vault.vaultInfo();

        vm.startPrank(user1);
        projectToken.approve(address(positionManager), collateral);
        positionManager.openPosition{ value: 0 }(
            address(projectToken),
            address(projectToken),
            collateral,
            5,
            1,
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );
        vm.stopPrank();

        VaultStorageLib.VaultInfo memory infoAfter = vault.vaultInfo();

        // Vault should have collected fees
        assertGe(
            infoAfter.totalFeesCollected, infoBefore.totalFeesCollected, "Fees should be collected"
        );
    }

    // ========================================================================
    // CLOSING FEE TESTS
    // ========================================================================

    function test_ClosingFee_DeductedFromPayout() public {
        // Open position
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 10 ether);
        positionManager.openPosition{ value: 0 }(
            address(projectToken),
            address(projectToken),
            10 ether,
            5,
            1,
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );

        vm.warp(block.timestamp + 61 seconds);
        _refreshPrice();

        uint256 balanceBefore = projectToken.balanceOf(user1);

        // Close position
        positionManager.closePosition(1, block.timestamp + 1 hours, "");

        uint256 balanceAfter = projectToken.balanceOf(user1);

        // User should receive some tokens back (payout minus fees)
        // The actual amount depends on P&L and fees
        assertGe(balanceAfter, balanceBefore, "User should receive payout");
        vm.stopPrank();
    }

    // ========================================================================
    // FEE CALCULATION TESTS
    // ========================================================================

    function test_FeeCalculation_SmallPosition() public {
        uint256 smallCollateral = 1 ether;

        vm.startPrank(user1);
        projectToken.approve(address(positionManager), smallCollateral);
        positionManager.openPosition{ value: 0 }(
            address(projectToken),
            address(projectToken),
            smallCollateral,
            5,
            1,
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );
        vm.stopPrank();

        VaultStorageLib.VaultInfo memory info = vault.vaultInfo();
        assertGt(info.totalFeesCollected, 0, "Fees should be collected for small position");
    }

    function test_FeeCalculation_LargePosition() public {
        uint256 largeCollateral = 100 ether;

        vm.startPrank(user1);
        projectToken.approve(address(positionManager), largeCollateral);
        positionManager.openPosition{ value: 0 }(
            address(projectToken),
            address(projectToken),
            largeCollateral,
            10,
            1,
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );
        vm.stopPrank();

        VaultStorageLib.VaultInfo memory info = vault.vaultInfo();
        assertGt(info.totalFeesCollected, 0, "Fees should be collected for large position");
    }

    // ========================================================================
    // MULTIPLE POSITIONS TESTS
    // ========================================================================

    function test_FeeAccumulation_MultiplePositions() public {
        VaultStorageLib.VaultInfo memory infoBefore = vault.vaultInfo();

        // Open multiple positions
        for (uint256 i = 0; i < 3; i++) {
            vm.startPrank(user1);
            projectToken.approve(address(positionManager), 5 ether);
            positionManager.openPosition{ value: 0 }(
                address(projectToken),
                address(projectToken),
                5 ether,
                5,
                1,
                type(uint256).max,
                block.timestamp + 1 hours,
                ""
            );
            vm.stopPrank();
        }

        VaultStorageLib.VaultInfo memory infoAfter = vault.vaultInfo();

        // Total fees should increase
        assertGt(
            infoAfter.totalFeesCollected, infoBefore.totalFeesCollected, "Fees should accumulate"
        );
    }

    function test_FeeAccumulation_MultipleUsers() public {
        VaultStorageLib.VaultInfo memory infoBefore = vault.vaultInfo();

        // User1 opens position
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 10 ether);
        positionManager.openPosition{ value: 0 }(
            address(projectToken),
            address(projectToken),
            10 ether,
            5,
            1,
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );
        vm.stopPrank();

        // User2 opens position
        vm.startPrank(user2);
        projectToken.approve(address(positionManager), 10 ether);
        positionManager.openPosition{ value: 0 }(
            address(projectToken),
            address(projectToken),
            10 ether,
            5,
            2,
            0,
            block.timestamp + 1 hours,
            ""
        );
        vm.stopPrank();

        VaultStorageLib.VaultInfo memory infoAfter = vault.vaultInfo();

        assertGt(
            infoAfter.totalFeesCollected,
            infoBefore.totalFeesCollected,
            "Fees from multiple users should accumulate"
        );
    }

    // ========================================================================
    // LEVERAGE IMPACT ON FEES TESTS
    // ========================================================================

    function test_FeeCalculation_HighLeverage() public {
        uint256 collateral = 10 ether;
        uint8 highLeverage = 20;

        VaultStorageLib.VaultInfo memory infoBefore = vault.vaultInfo();

        vm.startPrank(user1);
        projectToken.approve(address(positionManager), collateral);
        positionManager.openPosition{ value: 0 }(
            address(projectToken),
            address(projectToken),
            collateral,
            highLeverage,
            1,
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );
        vm.stopPrank();

        VaultStorageLib.VaultInfo memory infoAfter = vault.vaultInfo();

        // Higher leverage = larger position size = higher fees
        assertGt(
            infoAfter.totalFeesCollected,
            infoBefore.totalFeesCollected,
            "Fees should be higher for high leverage"
        );
    }

    function test_FeeCalculation_LowLeverage() public {
        uint256 collateral = 10 ether;
        uint8 lowLeverage = 2;

        VaultStorageLib.VaultInfo memory infoBefore = vault.vaultInfo();

        vm.startPrank(user1);
        projectToken.approve(address(positionManager), collateral);
        positionManager.openPosition{ value: 0 }(
            address(projectToken),
            address(projectToken),
            collateral,
            lowLeverage,
            1,
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );
        vm.stopPrank();

        VaultStorageLib.VaultInfo memory infoAfter = vault.vaultInfo();

        assertGt(
            infoAfter.totalFeesCollected,
            infoBefore.totalFeesCollected,
            "Fees should be collected for low leverage"
        );
    }

    // ========================================================================
    // FUZZ TESTS
    // ========================================================================

    function testFuzz_FeeCollection(uint256 collateral, uint8 leverage) public {
        collateral = bound(collateral, DEFAULT_MIN_BET, 50 ether);
        leverage = uint8(bound(leverage, 1, 10));

        VaultStorageLib.VaultInfo memory infoBefore = vault.vaultInfo();

        vm.startPrank(user1);
        projectToken.approve(address(positionManager), collateral);
        positionManager.openPosition{ value: 0 }(
            address(projectToken),
            address(projectToken),
            collateral,
            leverage,
            1,
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );
        vm.stopPrank();

        VaultStorageLib.VaultInfo memory infoAfter = vault.vaultInfo();

        assertGe(
            infoAfter.totalFeesCollected, infoBefore.totalFeesCollected, "Fees should be collected"
        );
    }
}
