// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../vault-modular/BaseTestModular.sol";

/**
 * @title MaxLeverageSystemTest
 * @notice Unit tests for Fixed Maximum Leverage System in modular vault
 * @dev Tests cover:
 *      - Fixed max leverage (default 100x)
 *      - Admin can update max leverage
 *      - Risk checks via checkPositionRisk
 */
contract LeverageTierSystemTest is BaseTestModular {
    // ========================================================================
    // SETUP
    // ========================================================================

    function setUp() public override {
        super.setUp();

        // Enable trading
        _enableTrading();
        _setHighLeverageConfig();
    }

    // ========================================================================
    // MAX LEVERAGE CONFIG TESTS
    // ========================================================================

    function test_GetMaxLeverage_Default() public view {
        uint16 maxLeverage = vault.getMaxLeverage();
        // _setHighLeverageConfig sets to 50x
        assertEq(maxLeverage, 50, "Max leverage should be 50x after setup");
    }

    function test_SetMaxLeverage_AdminCanUpdate() public {
        vm.prank(address(vaultManager));
        vault.setMaxLeverage(100);

        uint16 maxLeverage = vault.getMaxLeverage();
        assertEq(maxLeverage, 100, "Max leverage should be updated to 100x");
    }

    function test_SetMaxLeverage_RevertOnZero() public {
        vm.prank(address(vaultManager));
        vm.expectRevert();
        vault.setMaxLeverage(0);
    }

    function test_SetMaxLeverage_RevertOnExceedsCap() public {
        vm.prank(address(vaultManager));
        vm.expectRevert();
        vault.setMaxLeverage(1001); // MAX_LEVERAGE_ALLOWED = 1000
    }

    // ========================================================================
    // LEVERAGE CALCULATION TESTS
    // ========================================================================

    function test_LeverageLimit_SmallVault() public {
        _addLiquidity(liquidityProvider, 50 ether);

        uint16 maxLeverage = vault.getMaxLeverage();

        // Small position should pass
        uint256 smallPositionSize = 10 ether;
        uint8 safeLeverage = uint8(maxLeverage > 10 ? 10 : maxLeverage);

        vault.checkPositionRisk(smallPositionSize, safeLeverage, 1);
    }

    function test_LeverageLimit_GraduatedVault() public {
        _graduateVault();

        VaultStorageLib.VaultInfo memory info = vault.vaultInfo();
        assertTrue(info.isGraduated, "Vault should be graduated");

        uint256 positionSize = 100 ether;
        uint8 leverage = 10;

        vault.checkPositionRisk(positionSize, leverage, 1);
    }

    // ========================================================================
    // POSITION RISK CHECK TESTS
    // ========================================================================

    function test_CheckPositionRisk_LongPosition() public {
        _addLiquidity(liquidityProvider, 1000 ether);

        vault.checkPositionRisk(50 ether, 5, 1); // direction = 1 (LONG)
    }

    function test_CheckPositionRisk_ShortPosition() public {
        _addLiquidity(liquidityProvider, 1000 ether);

        vault.checkPositionRisk(50 ether, 5, 2); // direction = 2 (SHORT)
    }

    function test_CheckPositionRisk_RevertOnExcessiveLeverage() public {
        _addLiquidity(liquidityProvider, 100 ether);

        // Try leverage above max (50x set in setUp) - should revert
        vm.expectRevert();
        vault.checkPositionRisk(10 ether, 200, 1); // 200x leverage
    }

    function test_CheckPositionRisk_RevertOnExcessiveSize() public {
        _addLiquidity(liquidityProvider, 100 ether);

        vm.expectRevert();
        vault.checkPositionRisk(10_000 ether, 10, 1);
    }

    // ========================================================================
    // FIXED LEVERAGE (NOT TVL-DEPENDENT)
    // ========================================================================

    function test_LeverageIsFixedRegardlessOfTVL() public {
        // Small TVL
        _addLiquidity(liquidityProvider, 50 ether);
        uint16 maxLeverageSmall = vault.getMaxLeverage();

        // Add more liquidity
        _addLiquidity(user1, 500 ether);
        uint16 maxLeverageLarge = vault.getMaxLeverage();

        // Max leverage should be the same regardless of TVL
        assertEq(maxLeverageSmall, maxLeverageLarge, "Max leverage should not change with TVL");
    }

    // ========================================================================
    // EDGE CASES
    // ========================================================================

    function test_LeverageLimit_ZeroLiquidity() public {
        vm.expectRevert();
        vault.checkPositionRisk(1 ether, 10, 1);
    }

    function test_LeverageLimit_MinimalLiquidity() public {
        _addLiquidity(liquidityProvider, 1 ether);

        vm.expectRevert();
        vault.checkPositionRisk(10 ether, 50, 1);
    }

    // ========================================================================
    // FUZZ TESTS
    // ========================================================================

    function testFuzz_CheckPositionRisk(uint256 positionSize, uint8 leverage) public {
        leverage = uint8(bound(leverage, 1, 50));
        uint256 minPositionSize = DEFAULT_MIN_BET * leverage;
        positionSize = bound(positionSize, minPositionSize, DEFAULT_MAX_BET);

        _addLiquidity(liquidityProvider, 10_000 ether);

        vault.checkPositionRisk(positionSize, leverage, 1);
    }
}
