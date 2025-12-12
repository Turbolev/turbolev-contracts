// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../vault-modular/BaseTestModular.sol";

/**
 * @title TotalOICapSystemTest
 * @notice Unit tests for Total Open Interest Cap System in modular vault
 * @dev Tests cover:
 *      - OI tier configuration
 *      - OI cap calculation based on TVL
 *      - Position risk checks with OI limits
 */
contract TotalOICapSystemTest is BaseTestModular {
    // ========================================================================
    // SETUP
    // ========================================================================

    function setUp() public override {
        super.setUp();
        _enableTrading();
    }

    // ========================================================================
    // OI TIER CONFIG TESTS
    // ========================================================================

    function test_GetTotalOITierConfig() public view {
        (
            uint16 fixedMultiplier,
            uint256 tier1Threshold,
            uint256 tier2Threshold,
            uint256 tier3Threshold,
            uint16 tier1Multiplier,
            uint16 tier2Multiplier,
            uint16 tier3Multiplier,
            uint16 tier4Multiplier
        ) = vault.getTotalOITierConfig();

        // Verify config values
        assertGt(fixedMultiplier, 0, "Fixed multiplier should be > 0");
        assertGt(tier1Threshold, 0, "Tier1 threshold should be > 0");
        assertGt(tier2Threshold, tier1Threshold, "Tier2 threshold should be > tier1");
        assertGt(tier3Threshold, tier2Threshold, "Tier3 threshold should be > tier2");

        // Multipliers should increase with tier (larger vaults allow more OI)
        assertGt(tier1Multiplier, 0, "Tier1 multiplier should be > 0");
    }

    // ========================================================================
    // OI CAP CALCULATION TESTS
    // ========================================================================

    function test_OICap_SmallVault() public {
        // Small TVL vault
        _addLiquidity(liquidityProvider, 100 ether);

        // Position within OI cap should pass
        vault.checkPositionRisk(10 ether, 5, 1);
    }

    function test_OICap_MediumVault() public {
        // Medium TVL vault
        _addLiquidity(liquidityProvider, 5000 ether);

        // Larger position should now be allowed
        vault.checkPositionRisk(100 ether, 10, 1);
    }

    function test_OICap_LargeVault() public {
        // Large TVL vault
        _addLiquidity(liquidityProvider, 100_000 ether);

        // Even larger positions should be allowed
        vault.checkPositionRisk(500 ether, 10, 1);
    }

    // ========================================================================
    // OI LIMIT TESTS
    // ========================================================================

    function test_OICap_RejectExcessivePosition() public {
        // Small vault
        _addLiquidity(liquidityProvider, 100 ether);

        // Position that would exceed OI cap should fail
        vm.expectRevert();
        vault.checkPositionRisk(1000 ether, 50, 1); // Way too large for this vault
    }

    function test_OICap_DirectionalExposure_Long() public {
        _addLiquidity(liquidityProvider, 1000 ether);

        // Long position within limits
        vault.checkPositionRisk(50 ether, 5, 1); // LONG
    }

    function test_OICap_DirectionalExposure_Short() public {
        _addLiquidity(liquidityProvider, 1000 ether);

        // Short position within limits
        vault.checkPositionRisk(50 ether, 5, 2); // SHORT
    }

    // ========================================================================
    // TIER TRANSITION TESTS
    // ========================================================================

    function test_OICap_TierTransitionOnLiquidityIncrease() public {
        // Start in tier 1
        _addLiquidity(liquidityProvider, 100 ether);

        // Small position should work
        vault.checkPositionRisk(20 ether, 5, 1);

        // Move to higher tier by adding liquidity
        _addLiquidity(user1, 10_000 ether);

        // Now larger positions should be allowed
        vault.checkPositionRisk(200 ether, 10, 1);
    }

    // ========================================================================
    // DIRECTIONAL EXPOSURE TESTS
    // ========================================================================

    function test_DirectionalExposure_BalancedPositions() public {
        _addLiquidity(liquidityProvider, 1000 ether);

        // Both long and short should pass when balanced
        vault.checkPositionRisk(50 ether, 5, 1); // LONG
        vault.checkPositionRisk(50 ether, 5, 2); // SHORT
    }

    // ========================================================================
    // VAULT INFO VERIFICATION TESTS
    // ========================================================================

    function test_VaultInfo_TotalLeverageExposure() public {
        _addLiquidity(liquidityProvider, 1000 ether);

        VaultStorageLib.VaultInfo memory info = vault.vaultInfo();

        // Verify initial state
        assertEq(info.totalLeverageExposure, 0, "Initial exposure should be 0");
        assertEq(info.totalLiquidity, 1000 ether, "Liquidity should be 1000 ether");
    }

    // ========================================================================
    // EDGE CASES
    // ========================================================================

    function test_OICap_ZeroLiquidity_Revert() public {
        // No liquidity = no OI allowed
        vm.expectRevert();
        vault.checkPositionRisk(1 ether, 2, 1);
    }

    function test_OICap_MinimalPosition() public {
        _addLiquidity(liquidityProvider, 1000 ether);

        // Minimal position should always pass
        vault.checkPositionRisk(DEFAULT_MIN_BET, 2, 1);
    }

    // ========================================================================
    // FUZZ TESTS
    // ========================================================================

    function testFuzz_OICap_VariableTVL(uint256 tvl) public {
        // Bound TVL to reasonable range
        tvl = bound(tvl, 10 ether, 100_000 ether);

        _addLiquidity(liquidityProvider, tvl);

        // Small relative position should always pass
        uint256 smallPosition = tvl / 100; // 1% of TVL
        if (smallPosition >= DEFAULT_MIN_BET) {
            vault.checkPositionRisk(smallPosition, 5, 1);
        }
    }

    function testFuzz_OICap_VariablePosition(uint256 positionSize) public {
        _addLiquidity(liquidityProvider, 10_000 ether);

        // Bound position size
        positionSize = bound(positionSize, DEFAULT_MIN_BET, 100 ether);

        // Reasonable positions should pass
        vault.checkPositionRisk(positionSize, 5, 1);
    }
}
