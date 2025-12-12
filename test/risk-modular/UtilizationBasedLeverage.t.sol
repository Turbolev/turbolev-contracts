// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../vault-modular/BaseTestModular.sol";

/**
 * @title UtilizationBasedLeverageTest
 * @notice Unit tests for Utilization-Based Leverage System in modular vault
 * @dev Tests cover:
 *      - Leverage limits based on vault utilization
 *      - Dynamic leverage adjustment
 *      - Position risk checks with utilization
 */
contract UtilizationBasedLeverageTest is BaseTestModular {
    // ========================================================================
    // SETUP
    // ========================================================================

    function setUp() public override {
        super.setUp();
        _enableTrading();
    }

    // ========================================================================
    // BASIC UTILIZATION TESTS
    // ========================================================================

    function test_LowUtilization_HighLeverageAllowed() public {
        // High liquidity = low utilization
        _addLiquidity(liquidityProvider, 10_000 ether);

        // Higher leverage should be allowed at low utilization
        vault.checkPositionRisk(100 ether, 20, 1);
    }

    function test_VaultState_InitialUtilization() public {
        _addLiquidity(liquidityProvider, 1000 ether);

        VaultStorageLib.VaultInfo memory info = vault.vaultInfo();

        // Initial utilization should be 0 (no positions)
        assertEq(info.totalLeverageExposure, 0, "Initial exposure should be 0");
    }

    // ========================================================================
    // POSITION RISK TESTS
    // ========================================================================

    function test_PositionRisk_MultipleSmallPositions() public {
        _addLiquidity(liquidityProvider, 5000 ether);

        // Multiple small positions should pass
        vault.checkPositionRisk(50 ether, 10, 1);
        vault.checkPositionRisk(50 ether, 10, 2);
        vault.checkPositionRisk(50 ether, 10, 1);
    }

    function test_PositionRisk_SingleLargePosition() public {
        _addLiquidity(liquidityProvider, 10_000 ether);

        // Single larger position
        vault.checkPositionRisk(500 ether, 10, 1);
    }

    // ========================================================================
    // LEVERAGE LIMIT TESTS
    // ========================================================================

    function test_LeverageLimit_ExceedMaxLeverage() public {
        _addLiquidity(liquidityProvider, 1000 ether);

        // Extremely high leverage should fail
        vm.expectRevert();
        vault.checkPositionRisk(10 ether, 250, 1); // 250x is way too high
    }

    function test_LeverageLimit_AtMaxLeverage() public {
        _addLiquidity(liquidityProvider, 100_000 ether); // Large vault

        // Get current max leverage config
        (,, uint16 tier1MaxLeverage,,) = vault.getLeverageTierConfig();

        // Position at max leverage should work for large vaults
        uint8 safeLeverage = uint8(tier1MaxLeverage > 100 ? 100 : tier1MaxLeverage);
        vault.checkPositionRisk(100 ether, safeLeverage, 1);
    }

    // ========================================================================
    // GRADUATED VAULT TESTS
    // ========================================================================

    function test_GraduatedVault_HigherLeverageAllowed() public {
        // Graduate the vault
        _graduateVault();

        // Graduated vaults should allow higher leverage
        vault.checkPositionRisk(100 ether, 20, 1);
    }

    function test_GraduatedVault_LargerPositionsAllowed() public {
        _graduateVault();

        // Graduated vaults can handle larger positions
        vault.checkPositionRisk(500 ether, 10, 1);
    }

    // ========================================================================
    // DIRECTIONAL EXPOSURE TESTS
    // ========================================================================

    function test_DirectionalExposure_LongOnly() public {
        _addLiquidity(liquidityProvider, 5000 ether);

        // Long positions should work
        vault.checkPositionRisk(100 ether, 10, 1); // LONG
        vault.checkPositionRisk(100 ether, 10, 1); // LONG
    }

    function test_DirectionalExposure_ShortOnly() public {
        _addLiquidity(liquidityProvider, 5000 ether);

        // Short positions should work
        vault.checkPositionRisk(100 ether, 10, 2); // SHORT
        vault.checkPositionRisk(100 ether, 10, 2); // SHORT
    }

    function test_DirectionalExposure_Balanced() public {
        _addLiquidity(liquidityProvider, 5000 ether);

        // Balanced positions
        vault.checkPositionRisk(100 ether, 10, 1); // LONG
        vault.checkPositionRisk(100 ether, 10, 2); // SHORT
    }

    // ========================================================================
    // EDGE CASES
    // ========================================================================

    function test_EdgeCase_MinimalLiquidity() public {
        // Very small vault
        _addLiquidity(liquidityProvider, 10 ether);

        // Only tiny positions should work
        vault.checkPositionRisk(DEFAULT_MIN_BET, 2, 1);
    }

    function test_EdgeCase_ZeroLeverage_Revert() public {
        _addLiquidity(liquidityProvider, 1000 ether);

        // Zero leverage should fail
        vm.expectRevert();
        vault.checkPositionRisk(10 ether, 0, 1);
    }

    function test_EdgeCase_InvalidDirection() public {
        _addLiquidity(liquidityProvider, 1000 ether);

        // Invalid direction (0 = NONE) should fail
        vm.expectRevert();
        vault.checkPositionRisk(10 ether, 5, 0);
    }

    // ========================================================================
    // TVL SCALING TESTS
    // ========================================================================

    function test_TVLScaling_SmallToMedium() public {
        // Start small
        _addLiquidity(liquidityProvider, 100 ether);
        vault.checkPositionRisk(10 ether, 5, 1);

        // Scale up
        _addLiquidity(user1, 1000 ether);
        vault.checkPositionRisk(50 ether, 10, 1);
    }

    function test_TVLScaling_MediumToLarge() public {
        // Medium vault
        _addLiquidity(liquidityProvider, 10_000 ether);
        vault.checkPositionRisk(100 ether, 15, 1);

        // Large vault
        _addLiquidity(user1, 100_000 ether);
        vault.checkPositionRisk(500 ether, 20, 1);
    }

    // ========================================================================
    // FUZZ TESTS
    // ========================================================================

    function testFuzz_Utilization_RandomInputs(
        uint256 liquidityAmount,
        uint256 positionSize,
        uint8 leverage
    ) public {
        // Bound inputs to reasonable ranges
        liquidityAmount = bound(liquidityAmount, 100 ether, 100_000 ether);
        positionSize = bound(positionSize, DEFAULT_MIN_BET, liquidityAmount / 10);
        leverage = uint8(bound(leverage, 1, 20));

        _addLiquidity(liquidityProvider, liquidityAmount);

        // Should not revert for reasonable inputs
        vault.checkPositionRisk(positionSize, leverage, 1);
    }

    function testFuzz_Utilization_LeverageVsTVL(uint256 tvl) public {
        tvl = bound(tvl, 1000 ether, 500_000 ether);

        _addLiquidity(liquidityProvider, tvl);

        // Higher TVL should allow higher leverage
        uint256 maxPositionSize = tvl / 20; // 5% of TVL
        uint8 leverage = uint8(bound(tvl / 10_000 ether, 5, 20));

        if (maxPositionSize >= DEFAULT_MIN_BET) {
            vault.checkPositionRisk(maxPositionSize, leverage, 1);
        }
    }
}
