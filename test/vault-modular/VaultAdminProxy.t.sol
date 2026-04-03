// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./BaseTestModular.sol";
import "../../src/vault-modular/VaultAdminProxy.sol";
import "../../src/interfaces/IVaultAdminProxy.sol";

/**
 * @title VaultAdminProxyTest
 * @notice Tests for VaultAdminProxy contract
 */
contract VaultAdminProxyTest is BaseTestModular {
    VaultAdminProxy public vaultAdminProxy;

    // Cache role for gas efficiency and avoid prank issues
    bytes32 public VAULT_ADMIN_ROLE;

    // Events from VaultAdminProxy
    event VaultPaused(address indexed vault, address indexed caller, uint256 timestamp);
    event VaultUnpaused(address indexed vault, address indexed caller, uint256 timestamp);
    event VaultParamsUpdated(
        address indexed vault, uint256 minBetAmount, uint256 maxBetAmount, uint256 timestamp
    );
    event VaultFeeUpdated(address indexed vault, uint8 feeType, uint16 feeBps, uint256 timestamp);
    event BatchFundingUpdated(uint256 vaultsUpdated, uint256 timestamp);

    function setUp() public override {
        super.setUp();

        // Cache roles to avoid prank consumption issues
        VAULT_ADMIN_ROLE = vaultAccessController.VAULT_ADMIN_ROLE();

        _deployVaultAdminProxy();
    }

    function _deployVaultAdminProxy() internal {
        // Deploy implementation
        VaultAdminProxy impl = new VaultAdminProxy();

        // Deploy proxy
        bytes memory initData = abi.encodeCall(
            VaultAdminProxy.initialize,
            (address(vaultManager), address(vaultAccessController), address(priceFeedManager))
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        vaultAdminProxy = VaultAdminProxy(address(proxy));

        // Grant VAULT_ADMIN_ROLE to VaultAdminProxy
        vm.startPrank(mockTimelockController);
        vaultAccessController.addVaultAdminProxy(address(vaultAdminProxy));
        vaultAccessController.grantRole(VAULT_ADMIN_ROLE, owner);
        vm.stopPrank();
    }

    // ========================================================================
    // INITIALIZATION TESTS
    // ========================================================================

    function test_Initialize() public view {
        assertEq(vaultAdminProxy.vaultManager(), address(vaultManager));
        assertEq(vaultAdminProxy.accessController(), address(vaultAccessController));
        assertEq(vaultAdminProxy.priceFeedManager(), address(priceFeedManager));
        assertEq(vaultAdminProxy.version(), "1.0.0");
    }

    function test_Initialize_RevertIfZeroAddress() public {
        VaultAdminProxy impl = new VaultAdminProxy();

        bytes memory initData = abi.encodeCall(
            VaultAdminProxy.initialize,
            (address(0), address(vaultAccessController), address(priceFeedManager))
        );

        vm.expectRevert(IVaultAdminProxy.InvalidAddress.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    // ========================================================================
    // BATCH OPERATIONS TESTS
    // ========================================================================

    // ========================================================================
    // VAULT ADMIN FUNCTIONS TESTS
    // ========================================================================

    function test_PauseVault() public {
        // Grant VAULT_ADMIN_ROLE to test account
        vm.startPrank(mockTimelockController);
        vaultAccessController.grantRole(VAULT_ADMIN_ROLE, admin);
        vm.stopPrank();

        vm.prank(admin);
        vaultAdminProxy.pauseVault(address(projectToken), address(projectToken));

        assertTrue(IVaultRouter(testVault).paused());
    }

    function test_UnpauseVault() public {
        // Grant VAULT_ADMIN_ROLE
        vm.startPrank(mockTimelockController);
        vaultAccessController.grantRole(VAULT_ADMIN_ROLE, admin);
        vm.stopPrank();

        // First pause
        vm.prank(admin);
        vaultAdminProxy.pauseVault(address(projectToken), address(projectToken));

        // Then unpause
        vm.prank(admin);
        vaultAdminProxy.unpauseVault(address(projectToken), address(projectToken));

        assertFalse(IVaultRouter(testVault).paused());
    }

    function test_PauseVault_RevertIfNotVaultAdmin() public {
        vm.prank(user1);
        vm.expectRevert(IVaultAdminProxy.NotAuthorized.selector);
        vaultAdminProxy.pauseVault(address(projectToken), address(projectToken));
    }

    function test_UpdateVaultParams() public {
        vm.startPrank(mockTimelockController);
        vaultAccessController.grantRole(VAULT_ADMIN_ROLE, admin);
        vm.stopPrank();

        uint256 newMinBet = 0.01 ether;
        uint256 newMaxBet = 100 ether;

        vm.prank(admin);
        vaultAdminProxy.updateVaultParams(
            address(projectToken), address(projectToken), newMinBet, newMaxBet
        );

        IVaultRouter.VaultParams memory params = IVaultRouter(testVault).getVaultParams();
        assertEq(params.minBetAmount, newMinBet);
        assertEq(params.maxBetAmount, newMaxBet);
    }

    function test_SetVaultStakingFeeBps() public {
        vm.startPrank(mockTimelockController);
        vaultAccessController.grantRole(VAULT_ADMIN_ROLE, admin);
        vm.stopPrank();

        uint16 newFeeBps = 50; // 0.5%

        vm.prank(admin);
        vaultAdminProxy.setVaultStakingFeeBps(
            address(projectToken), address(projectToken), newFeeBps
        );

        (uint16 stakingFeeBps,,) = IVaultRouter(testVault).getFeeConfig();
        assertEq(stakingFeeBps, newFeeBps);
    }

    function test_SetVaultEarlyWithdrawalFeeBps() public {
        vm.startPrank(mockTimelockController);
        vaultAccessController.grantRole(VAULT_ADMIN_ROLE, admin);
        vm.stopPrank();

        uint16 newFeeBps = 200; // 2%

        vm.prank(admin);
        vaultAdminProxy.setVaultEarlyWithdrawalFeeBps(
            address(projectToken), address(projectToken), newFeeBps
        );

        (, uint16 earlyWithdrawalFeeBps,) = IVaultRouter(testVault).getFeeConfig();
        assertEq(earlyWithdrawalFeeBps, newFeeBps);
    }

    function test_SetVaultGraduationThreshold() public {
        vm.startPrank(mockTimelockController);
        vaultAccessController.grantRole(VAULT_ADMIN_ROLE, admin);
        vm.stopPrank();

        uint256 newThreshold = 200 ether;

        vm.prank(admin);
        vaultAdminProxy.setVaultGraduationThreshold(
            address(projectToken), address(projectToken), newThreshold
        );

        IVaultRouter.VaultInfo memory info = IVaultRouter(testVault).getVaultInfo();
        assertEq(info.graduationThreshold, newThreshold);
    }

    function test_SetVaultTradingEnabled() public {
        vm.startPrank(mockTimelockController);
        vaultAccessController.grantRole(VAULT_ADMIN_ROLE, admin);
        vm.stopPrank();

        vm.prank(admin);
        vaultAdminProxy.setVaultTradingEnabled(address(projectToken), address(projectToken), true);

        assertTrue(IVaultRouter(testVault).tradingEnabled());
    }

    function test_SetVaultTreasury() public {
        vm.startPrank(mockTimelockController);
        vaultAccessController.grantRole(VAULT_ADMIN_ROLE, admin);
        vm.stopPrank();

        address newTreasury = makeAddr("newTreasury");

        vm.prank(admin);
        vaultAdminProxy.setVaultTreasury(address(projectToken), address(projectToken), newTreasury);

        // Treasury should be updated (no getter in interface, so we just verify no revert)
    }

    function test_SetVaultImpactEnabled() public {
        vm.startPrank(mockTimelockController);
        vaultAccessController.grantRole(VAULT_ADMIN_ROLE, admin);
        vm.stopPrank();

        vm.prank(admin);
        vaultAdminProxy.setVaultImpactEnabled(address(projectToken), address(projectToken), false);

        assertFalse(IVaultRouter(testVault).isImpactEnabled());

        vm.prank(admin);
        vaultAdminProxy.setVaultImpactEnabled(address(projectToken), address(projectToken), true);

        assertTrue(IVaultRouter(testVault).isImpactEnabled());
    }

    function test_SetVaultImpactConfig() public {
        vm.startPrank(mockTimelockController);
        vaultAccessController.grantRole(VAULT_ADMIN_ROLE, admin);
        vm.stopPrank();

        // Values must be <= MAX_IMPACT_BPS (200) and in ascending order.
        vm.prank(admin);
        vaultAdminProxy.setVaultImpactConfig(
            address(projectToken),
            address(projectToken),
            5, // tier1: 0.05%
            15, // tier2: 0.15%
            30, // tier3: 0.30%
            50, // tier4: 0.50%
            100 // tier5: 1.00%
        );
        // No assertion - just verify no revert
    }

    // ========================================================================
    // VIEW FUNCTIONS TESTS
    // ========================================================================

    function test_GetVault() public view {
        address vault = vaultAdminProxy.getVault(address(projectToken), address(projectToken));
        assertEq(vault, testVault);
    }

    function test_GetAllVaults() public view {
        address[] memory vaults = vaultAdminProxy.getAllVaults();
        assertGe(vaults.length, 1);
        assertEq(vaults[0], testVault);
    }

    function test_IsVaultSupported() public view {
        assertTrue(vaultAdminProxy.isVaultSupported(address(projectToken), address(projectToken)));
        assertFalse(vaultAdminProxy.isVaultSupported(address(0x123), address(0x123)));
    }

    // ========================================================================
    // ADMIN CONFIG TESTS
    // ========================================================================

    function test_SetPriceFeedManager() public {
        address newPfm = makeAddr("newPriceFeedManager");

        vm.prank(mockTimelockController);
        vaultAdminProxy.setPriceFeedManager(newPfm);

        assertEq(vaultAdminProxy.priceFeedManager(), newPfm);
    }

    function test_SetVaultManager() public {
        address newVm = makeAddr("newVaultManager");

        vm.prank(mockTimelockController);
        vaultAdminProxy.setVaultManager(newVm);

        assertEq(vaultAdminProxy.vaultManager(), newVm);
    }

    function test_SetAccessController() public {
        address newAc = makeAddr("newAccessController");

        vm.prank(mockTimelockController);
        vaultAdminProxy.setAccessController(newAc);

        assertEq(vaultAdminProxy.accessController(), newAc);
    }

    function test_SetVaultManager_RevertIfZeroAddress() public {
        vm.prank(mockTimelockController);
        vm.expectRevert(IVaultAdminProxy.InvalidAddress.selector);
        vaultAdminProxy.setVaultManager(address(0));
    }

    // ========================================================================
    // ERROR CASES
    // ========================================================================

    function test_VaultNotFound() public {
        address fakeToken = makeAddr("fakeToken");

        vm.startPrank(mockTimelockController);
        vaultAccessController.grantRole(VAULT_ADMIN_ROLE, admin);
        vm.stopPrank();

        vm.prank(admin);
        vm.expectRevert(IVaultAdminProxy.VaultNotFound.selector);
        vaultAdminProxy.pauseVault(fakeToken, fakeToken);
    }

    function test_VaultNotActive() public {
        // Deactivate the vault
        vm.prank(owner);
        vaultManager.deactivateVault(testVault);

        vm.startPrank(mockTimelockController);
        vaultAccessController.grantRole(VAULT_ADMIN_ROLE, admin);
        vm.stopPrank();

        vm.prank(admin);
        vm.expectRevert(IVaultAdminProxy.VaultNotActive.selector);
        vaultAdminProxy.pauseVault(address(projectToken), address(projectToken));

        // Reactivate for other tests
        vm.prank(owner);
        vaultManager.reactivateVault(testVault);
    }

    // ========================================================================
    // ADDITIONAL COVERAGE TESTS
    // ========================================================================

    function test_SetTreasuryForAllVaults() public {
        vm.startPrank(mockTimelockController);
        vaultAccessController.grantRole(VAULT_ADMIN_ROLE, admin);
        vm.stopPrank();

        address newTreasury = makeAddr("globalTreasury");

        vm.prank(admin);
        vaultAdminProxy.setTreasuryForAllVaults(newTreasury);
        // Verify no revert
    }

    function test_SetImpactEnabledForAllVaults() public {
        vm.startPrank(mockTimelockController);
        vaultAccessController.grantRole(VAULT_ADMIN_ROLE, admin);
        vm.stopPrank();

        vm.prank(admin);
        vaultAdminProxy.setImpactEnabledForAllVaults(false);

        assertFalse(IVaultRouter(testVault).isImpactEnabled());

        vm.prank(admin);
        vaultAdminProxy.setImpactEnabledForAllVaults(true);

        assertTrue(IVaultRouter(testVault).isImpactEnabled());
    }

    function test_WithdrawFees() public {
        vm.startPrank(mockTimelockController);
        vaultAccessController.grantRole(VAULT_ADMIN_ROLE, admin);
        vm.stopPrank();

        // First add some liquidity to generate potential fees
        _addLiquidity(liquidityProvider, 100 ether);

        vm.prank(admin);
        // This should not revert even if there are no fees to withdraw (0 = withdraw all)
        vaultAdminProxy.withdrawFees(address(projectToken), address(projectToken), 0);
    }

    function test_SetVaultOpenPositionFeeBps() public {
        vm.startPrank(mockTimelockController);
        vaultAccessController.grantRole(VAULT_ADMIN_ROLE, admin);
        vm.stopPrank();

        uint16 newFeeBps = 30; // 0.3%

        vm.prank(admin);
        vaultAdminProxy.setVaultOpenPositionFeeBps(
            address(projectToken), address(projectToken), newFeeBps
        );

        // Just verify no revert since getFeeConfig doesn't return openPositionFeeBps
    }

    function test_SetVaultClosePositionFeeBps() public {
        vm.startPrank(mockTimelockController);
        vaultAccessController.grantRole(VAULT_ADMIN_ROLE, admin);
        vm.stopPrank();

        uint16 newFeeBps = 25; // 0.25%

        vm.prank(admin);
        vaultAdminProxy.setVaultClosePositionFeeBps(
            address(projectToken), address(projectToken), newFeeBps
        );

        // Just verify no revert since getFeeConfig doesn't return closePositionFeeBps
    }

    function test_VaultAdminProxy_HasCorrectRole() public view {
        assertTrue(
            vaultAccessController.hasRole(VAULT_ADMIN_ROLE, address(vaultAdminProxy)),
            "VaultAdminProxy should have VAULT_ADMIN_ROLE"
        );
    }

    // ========================================================================
    // RISK CONFIG SETTERS TESTS
    // ========================================================================

    function test_SetVaultMaxLeverage() public {
        vm.startPrank(mockTimelockController);
        vaultAccessController.grantRole(VAULT_ADMIN_ROLE, admin);
        vm.stopPrank();

        vm.prank(admin);
        vaultAdminProxy.setVaultMaxLeverage(address(projectToken), address(projectToken), 200);

        assertEq(IVaultRouter(testVault).getMaxLeverage(), 200);
    }

    function test_SetVaultMaxLeverage_RevertNotAuthorized() public {
        vm.prank(user1);
        vm.expectRevert(IVaultAdminProxy.NotAuthorized.selector);
        vaultAdminProxy.setVaultMaxLeverage(address(projectToken), address(projectToken), 200);
    }

    function test_SetVaultTotalOITierConfig() public {
        vm.startPrank(mockTimelockController);
        vaultAccessController.grantRole(VAULT_ADMIN_ROLE, admin);
        vm.stopPrank();

        vm.prank(admin);
        vaultAdminProxy.setVaultTotalOITierConfig(
            address(projectToken),
            address(projectToken),
            15_000, // totalOIRiskMultiplierBps (1.5x — max allowed)
            100_000 * 1e18, // tier1Threshold
            500_000 * 1e18, // tier2Threshold
            1_000_000 * 1e18, // tier3Threshold
            10_000, // tier1MultiplierBps (1.0x)
            12_000, // tier2MultiplierBps (1.2x)
            13_000, // tier3MultiplierBps (1.3x)
            15_000 // tier4MultiplierBps (1.5x — max allowed)
        );

        // Verify new values
        (
            uint16 fixedMultiplier,
            uint256 tier1Threshold,
            uint256 tier2Threshold,
            uint256 tier3Threshold,
            uint16 tier1Multiplier,
            uint16 tier2Multiplier,
            uint16 tier3Multiplier,
            uint16 tier4Multiplier
        ) = IVaultRouter(testVault).getTotalOITierConfig();

        assertEq(fixedMultiplier, 15_000);
        assertEq(tier1Threshold, 100_000 * 1e18);
        assertEq(tier2Threshold, 500_000 * 1e18);
        assertEq(tier3Threshold, 1_000_000 * 1e18);
        assertEq(tier1Multiplier, 10_000);
        assertEq(tier2Multiplier, 12_000);
        assertEq(tier3Multiplier, 13_000);
        assertEq(tier4Multiplier, 15_000);
    }

    function test_SetVaultTotalOITierConfig_RevertNotAuthorized() public {
        vm.prank(user1);
        vm.expectRevert(IVaultAdminProxy.NotAuthorized.selector);
        vaultAdminProxy.setVaultTotalOITierConfig(
            address(projectToken),
            address(projectToken),
            25_000,
            100_000 * 1e18,
            500_000 * 1e18,
            1_000_000 * 1e18,
            12_000,
            18_000,
            24_000,
            35_000
        );
    }

    function test_SetVaultMaxDirectionalExposure() public {
        vm.startPrank(mockTimelockController);
        vaultAccessController.grantRole(VAULT_ADMIN_ROLE, admin);
        vm.stopPrank();

        vm.prank(admin);
        vaultAdminProxy.setVaultMaxDirectionalExposure(
            address(projectToken),
            address(projectToken),
            7500 // 75%
        );

        // Verify new value
        assertEq(IVaultRouter(testVault).maxDirectionalExposureBps(), 7500);
    }

    function test_SetVaultMaxDirectionalExposure_RevertNotAuthorized() public {
        vm.prank(user1);
        vm.expectRevert(IVaultAdminProxy.NotAuthorized.selector);
        vaultAdminProxy.setVaultMaxDirectionalExposure(
            address(projectToken), address(projectToken), 7500
        );
    }

    function test_SetVaultMaxProfitCapMultiplier() public {
        vm.startPrank(mockTimelockController);
        vaultAccessController.grantRole(VAULT_ADMIN_ROLE, admin);
        vm.stopPrank();

        vm.prank(admin);
        vaultAdminProxy.setVaultMaxProfitCapMultiplier(
            address(projectToken),
            address(projectToken),
            5 // 5x collateral
        );

        // Verify new value
        assertEq(IVaultRouter(testVault).getMaxProfitCapMultiplier(), 5);
    }

    function test_SetVaultMaxProfitCapMultiplier_RevertNotAuthorized() public {
        vm.prank(user1);
        vm.expectRevert(IVaultAdminProxy.NotAuthorized.selector);
        vaultAdminProxy.setVaultMaxProfitCapMultiplier(
            address(projectToken), address(projectToken), 5
        );
    }
}
