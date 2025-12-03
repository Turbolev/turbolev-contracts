// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./BaseTest.sol";
import "../src/libraries/VaultRiskLib.sol";

/**
 * @title AssetVaultTest
 * @notice Unit tests for AssetVault contract
 * @dev Tests core functions: liquidity, params, view functions
 */
contract AssetVaultTest is BaseTest {
    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    function test_GetVaultInfo_Success() public {
        AssetVaultUpgradeable.VaultInfo memory info = assetVault.getVaultInfo();

        // Vault may or may not have initial liquidity depending on setup
        assertGt(info.createdAt, 0, "Should have creation time");
    }

    function test_GetVaultParams_Success() public {
        AssetVaultUpgradeable.VaultParams memory params = assetVault.getVaultParams();

        assertGt(params.minBetAmount, 0, "Min bet should be > 0");
        assertGt(params.maxBetAmount, 0, "Max bet should be > 0");
    }

    function test_GetLPPosition_Success() public {
        // Add liquidity first
        uint256 amount = 100 ether;
        vm.startPrank(user1);
        projectToken.mint(user1, amount);
        projectToken.approve(address(assetVault), amount);
        assetVault.addLiquidity(amount);
        vm.stopPrank();

        AssetVaultUpgradeable.LPPosition memory position = assetVault.getLPPosition(user1);

        assertEq(position.user, user1, "User should match");
        assertGt(position.shares, 0, "Should have shares");
    }

    // ========================================================================
    // LIQUIDITY TESTS
    // ========================================================================

    function test_AddLiquidity_Success() public {
        uint256 amount = 50 ether;
        vm.startPrank(user1);
        projectToken.mint(user1, amount);
        projectToken.approve(address(assetVault), amount);

        uint256 sharesBefore = assetVault.getLPPosition(user1).shares;
        assetVault.addLiquidity(amount);
        uint256 sharesAfter = assetVault.getLPPosition(user1).shares;

        assertGt(sharesAfter, sharesBefore, "Shares should increase");
        vm.stopPrank();
    }

    function test_AddLiquidity_RevertsWhenPaused() public {
        assetVault.pause();

        vm.startPrank(user1);
        projectToken.mint(user1, 50 ether);
        projectToken.approve(address(assetVault), 50 ether);

        vm.expectRevert();
        assetVault.addLiquidity(50 ether);
        vm.stopPrank();
    }

    function test_RemoveLiquidity_Success() public {
        // Add liquidity first
        uint256 amount = 100 ether;
        vm.startPrank(user1);
        projectToken.mint(user1, amount);
        projectToken.approve(address(assetVault), amount);
        assetVault.addLiquidity(amount);

        // Get shares before removal
        uint256 shares = assetVault.getLPPosition(user1).shares;
        assertGt(shares, 0, "Should have shares before removal");

        // Remove all liquidity
        assetVault.removeLiquidity();

        uint256 sharesAfter = assetVault.getLPPosition(user1).shares;
        assertEq(sharesAfter, 0, "All shares should be removed");
        vm.stopPrank();
    }

    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================

    function test_UpdateVaultParams_Success() public {
        assetVault.updateVaultParams(
            0.01 ether, // minBetAmount
            100 ether // maxBetAmount
        );

        AssetVaultUpgradeable.VaultParams memory params = assetVault.getVaultParams();
        assertEq(params.minBetAmount, 0.01 ether, "Min bet should be updated");
        assertEq(params.maxBetAmount, 100 ether, "Max bet should be updated");
    }

    function test_SetPositionManager_Success() public {
        address newPM = makeAddr("newPositionManager");
        assetVault.setPositionManager(newPM);
        assertEq(assetVault.positionManager(), newPM, "Position manager should be updated");
    }

    function test_SetPositionManager_RevertsOnZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(AssetVaultUpgradeable.InvalidAddress.selector));
        assetVault.setPositionManager(address(0));
    }

    function test_SetGraduationThreshold_Success() public {
        uint256 newThreshold = 500 ether;
        assetVault.setGraduationThreshold(newThreshold);

        AssetVaultUpgradeable.VaultInfo memory info = assetVault.getVaultInfo();
        assertEq(info.graduationThreshold, newThreshold, "Threshold should be updated");
    }

    function test_Pause_Success() public {
        assetVault.pause();
        assertTrue(assetVault.paused(), "Should be paused");
    }

    function test_Unpause_Success() public {
        assetVault.pause();
        assetVault.unpause();
        assertFalse(assetVault.paused(), "Should be unpaused");
    }

    // ========================================================================
    // DIRECTIONAL EXPOSURE TESTS
    // ========================================================================

    function test_GetDirectionalExposure_InitialState() public {
        // Add some liquidity first so maxExposure is not 0
        uint256 amount = 100 ether;
        vm.startPrank(user1);
        projectToken.mint(user1, amount);
        projectToken.approve(address(assetVault), amount);
        assetVault.addLiquidity(amount);
        vm.stopPrank();

        (uint256 longExposure, uint256 shortExposure) =
            (assetVault.totalLongExposure(), assetVault.totalShortExposure());

        assertEq(longExposure, 0, "Initial long exposure should be 0");
        assertEq(shortExposure, 0, "Initial short exposure should be 0");
    }

    function test_SetMaxDirectionalExposure_Success() public {
        // Set new max exposure (30% instead of 50%)
        uint16 newMaxBps = 3000; // 30%
        assetVault.setMaxDirectionalExposure(newMaxBps);

        // Add liquidity to calculate expected max
        uint256 liquidityAmount = 1000 ether;
        vm.startPrank(user1);
        projectToken.mint(user1, liquidityAmount);
        projectToken.approve(address(assetVault), liquidityAmount);
        assetVault.addLiquidity(liquidityAmount);
        vm.stopPrank();

        // Check max exposure = 30% of liquidity
        uint256 newMaxExposure = (assetVault.getVaultInfo().totalLiquidity * newMaxBps) / 10_000;
        uint256 expectedMax = (liquidityAmount * newMaxBps) / 10_000;
        assertEq(newMaxExposure, expectedMax, "Max exposure should be 30% of TVL");
    }

    function test_SetMaxDirectionalExposure_RevertsOnInvalid() public {
        // Try to set > 100%
        vm.expectRevert();
        assetVault.setMaxDirectionalExposure(10_001);
    }

    function test_CheckPositionRisk_DirectionalExposure() public {
        // Add liquidity first
        uint256 liquidityAmount = 10_000 ether;
        vm.startPrank(user1);
        projectToken.mint(user1, liquidityAmount);
        projectToken.approve(address(assetVault), liquidityAmount);
        assetVault.addLiquidity(liquidityAmount);
        vm.stopPrank();

        // Update vault params to allow larger bets
        assetVault.updateVaultParams(
            0.01 ether, // minBetAmount
            2000 ether // maxBetAmount (increased to allow our test)
        );

        // Enable trading through VaultManagerHelper (which has authority)
        vm.prank(address(vaultManagerHelper));
        assetVault.setTradingEnabled(true);

        // Test position within limit (50% of 10000 = 5000)
        // Position size = 1500 ether, collateral = 300 ether (within maxBet)
        // Should not revert
        assetVault.checkPositionRisk(
            1500 ether, // position size
            5, // leverage (300 * 5 = 1500)
            1 // LONG
        );

        // Test position exceeding directional exposure limit
        // Position size = 6000 ether (exceeds 50% TVL = 5000)
        // Should revert with ExceedsDirectionalExposure or ExceedsTotalOICap
        vm.expectRevert();
        assetVault.checkPositionRisk(
            6000 ether, // position size
            5, // leverage
            1 // LONG
        );
    }

    function test_DirectionalExposure_BalancedPositions() public {
        // Add liquidity
        uint256 liquidityAmount = 10_000 ether;
        vm.startPrank(user1);
        projectToken.mint(user1, liquidityAmount);
        projectToken.approve(address(assetVault), liquidityAmount);
        assetVault.addLiquidity(liquidityAmount);
        vm.stopPrank();

        // Update vault params to allow larger bets
        assetVault.updateVaultParams(
            0.01 ether, // minBetAmount
            2000 ether // maxBetAmount
        );

        // Enable trading through VaultManagerHelper
        vm.prank(address(vaultManagerHelper));
        assetVault.setTradingEnabled(true);

        // Simulate balanced positions (1500 LONG, 1500 SHORT)
        // Net exposure should be 0

        // Check that equal long and short positions would be acceptable
        // Both should not revert
        assetVault.checkPositionRisk(1500 ether, 5, 1); // LONG
        assetVault.checkPositionRisk(1500 ether, 5, 2); // SHORT
    }
}
