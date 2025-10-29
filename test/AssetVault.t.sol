// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./BaseTest.sol";

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
        AssetVault.VaultInfo memory info = assetVault.getVaultInfo();

        // Vault may or may not have initial liquidity depending on setup
        assertGt(info.createdAt, 0, "Should have creation time");
    }

    function test_GetVaultParams_Success() public {
        AssetVault.VaultParams memory params = assetVault.getVaultParams();

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

        AssetVault.LPPosition memory position = assetVault.getLPPosition(user1);

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

        // Get shares
        uint256 shares = assetVault.getLPPosition(user1).shares;

        // Remove half
        assetVault.removeLiquidity(shares / 2);

        uint256 sharesAfter = assetVault.getLPPosition(user1).shares;
        assertEq(sharesAfter, shares / 2, "Shares should be halved");
        vm.stopPrank();
    }

    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================

    function test_UpdateVaultParams_Success() public {
        assetVault.updateVaultParams(
            0.01 ether, // minBetAmount
            100 ether, // maxBetAmount
            1000 // maxPositionSizePercentBps
        );

        AssetVault.VaultParams memory params = assetVault.getVaultParams();
        assertEq(params.maxPositionSizePercentBps, 1000, "Max position size should be updated");
        assertEq(params.minBetAmount, 0.01 ether, "Min bet should be updated");
    }

    function test_SetPositionManager_Success() public {
        address newPM = makeAddr("newPositionManager");
        assetVault.setPositionManager(newPM);
        assertEq(assetVault.positionManager(), newPM, "Position manager should be updated");
    }

    function test_SetPositionManager_RevertsOnZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(AssetVault.InvalidAddress.selector));
        assetVault.setPositionManager(address(0));
    }

    function test_SetGraduationThreshold_Success() public {
        uint256 newThreshold = 500 ether;
        assetVault.setGraduationThreshold(newThreshold);

        AssetVault.VaultInfo memory info = assetVault.getVaultInfo();
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
}
