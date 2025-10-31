// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./BaseTest.sol";

/**
 * @title VaultManagerHelperTest
 * @notice Unit tests for VaultManagerHelper contract
 */
contract VaultManagerHelperTest is BaseTest {
    VaultManagerHelper public helper;

    function setUp() public override {
        super.setUp();
        helper = new VaultManagerHelper(address(vaultManager));

        // Add initial liquidity to have data for tests
        uint256 amount = 1000 ether;
        projectToken.mint(owner, amount);
        projectToken.approve(address(assetVault), amount);
        assetVault.addLiquidity(amount);
    }

    // ========================================================================
    // CONSTRUCTOR & VIEW TESTS
    // ========================================================================

    function test_Constructor_Success() public {
        assertEq(helper.vaultManager(), address(vaultManager), "Vault manager should match");
    }

    function test_Constructor_RevertsOnZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(VaultManagerHelper.InvalidAddress.selector));
        new VaultManagerHelper(address(0));
    }

    function test_GetVaultInfo_Success() public {
        IAssetVault.VaultInfo memory info = helper.getVaultInfo(address(projectToken));

        // After adding liquidity in setUp
        assertGt(info.totalLiquidity, 0, "Should have liquidity");
        assertGt(info.totalShares, 0, "Should have shares");
        assertGt(info.createdAt, 0, "Should have creation time");
    }

    function test_GetVaultInfo_RevertsOnInvalidToken() public {
        address invalidToken = makeAddr("invalidToken");

        vm.expectRevert(abi.encodeWithSelector(VaultManagerHelper.VaultNotFound.selector));
        helper.getVaultInfo(invalidToken);
    }

    function test_GetVaultParams_Success() public {
        IAssetVault.VaultParams memory params = helper.getVaultParams(address(projectToken));

        // Check that params are set (values from BaseTest setup)
        assertGt(params.minBetAmount, 0, "Min bet should be > 0");
        assertGt(params.maxBetAmount, 0, "Max bet should be > 0");
    }

    function test_GetVaultParams_RevertsOnInvalidToken() public {
        address invalidToken = makeAddr("invalidToken");

        vm.expectRevert(abi.encodeWithSelector(VaultManagerHelper.VaultNotFound.selector));
        helper.getVaultParams(invalidToken);
    }

    function test_GetLPPosition_Success() public {
        // Add liquidity first
        uint256 amount = 100 ether;
        vm.startPrank(user1);
        projectToken.mint(user1, amount);
        projectToken.approve(address(assetVault), amount);
        assetVault.addLiquidity(amount);
        vm.stopPrank();

        IAssetVault.LPPosition memory position = helper.getLPPosition(address(projectToken), user1);

        assertEq(position.user, user1, "User should match");
        assertGt(position.shares, 0, "Should have shares");
    }

    function test_GetLPPosition_RevertsOnInvalidToken() public {
        address invalidToken = makeAddr("invalidToken");

        vm.expectRevert(abi.encodeWithSelector(VaultManagerHelper.VaultNotFound.selector));
        helper.getLPPosition(invalidToken, user1);
    }

    function test_GetTotalLiquidity_Success() public {
        uint256 totalLiq = helper.getTotalLiquidity();
        assertGt(totalLiq, 0, "Total liquidity should be > 0");
    }

    function test_GetTotalValueUSD_Success() public {
        // Set price first
        _updatePrice(address(projectToken), address(usdc), 100e18);

        uint256 totalUSD = helper.getTotalValueUSD();
        assertGt(totalUSD, 0, "Total USD value should be > 0");
    }

    // ========================================================================
    // ADMIN FUNCTIONS - REVERT CASES
    // ========================================================================

    function test_PauseVault_RevertsWhenNotOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(VaultManagerHelper.NotAuthorized.selector));
        helper.pauseVault(address(projectToken));
    }

    function test_AdminFunctions_RevertsOnInvalidVault() public {
        address invalidToken = makeAddr("invalidToken");

        // Admin functions should revert when called with invalid vault
        // Note: Will revert with NotAuthorized if caller is not owner, or VaultNotFound if vault doesn't exist
        vm.expectRevert(); // Just check that it reverts
        helper.pauseVault(invalidToken);
    }
}
