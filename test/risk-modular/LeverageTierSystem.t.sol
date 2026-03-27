// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../vault-modular/BaseTestModular.sol";

/**
 * @title LeverageTierSystemTest
 * @notice Unit tests for Maximum Leverage Tier System in modular vault
 * @dev Tests cover:
 *      - Leverage tier calculation based on TVL
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
    // LEVERAGE TIER CONFIG TESTS
    // ========================================================================

    function test_GetLeverageTierConfig() public view {
        (
            uint256 tier1Threshold,
            uint256 tier2Threshold,
            uint16 tier1MaxLeverage,
            uint16 tier2MaxLeverage,
            uint16 tier3MaxLeverage
        ) = vault.getLeverageTierConfig();

        // Verify config is set
        assertGt(tier1Threshold, 0, "Tier1 threshold should be > 0");
        assertGt(tier2Threshold, tier1Threshold, "Tier2 threshold should be > tier1");
        assertGt(tier1MaxLeverage, 0, "Tier1 max leverage should be > 0");
        assertGe(tier2MaxLeverage, tier1MaxLeverage, "Tier2 max leverage should be >= tier1");
        assertGe(tier3MaxLeverage, tier2MaxLeverage, "Tier3 max leverage should be >= tier2");
    }

    // ========================================================================
    // LEVERAGE CALCULATION TESTS
    // ========================================================================

    function test_LeverageLimit_SmallVault() public {
        // Add small liquidity (Launch Phase)
        _addLiquidity(liquidityProvider, 50 ether);

        // Get leverage config
        (,, uint16 tier1MaxLeverage,,) = vault.getLeverageTierConfig();

        // Small position should pass
        uint256 smallPositionSize = 10 ether;
        uint8 safeLeverage = uint8(tier1MaxLeverage > 10 ? 10 : tier1MaxLeverage);

        // This should not revert
        vault.checkPositionRisk(smallPositionSize, safeLeverage, 1);
    }

    function test_LeverageLimit_GraduatedVault() public {
        // Graduate the vault (add enough liquidity)
        _graduateVault();

        // Verify graduated
        VaultStorageLib.VaultInfo memory info = vault.vaultInfo();
        assertTrue(info.isGraduated, "Vault should be graduated");

        // Check position risk with moderate leverage
        uint256 positionSize = 100 ether;
        uint8 leverage = 10;

        // This should not revert for graduated vault
        vault.checkPositionRisk(positionSize, leverage, 1);
    }

    // ========================================================================
    // POSITION RISK CHECK TESTS
    // ========================================================================

    function test_CheckPositionRisk_LongPosition() public {
        _addLiquidity(liquidityProvider, 1000 ether);

        // Small long position should pass
        vault.checkPositionRisk(50 ether, 5, 1); // direction = 1 (LONG)
    }

    function test_CheckPositionRisk_ShortPosition() public {
        _addLiquidity(liquidityProvider, 1000 ether);

        // Small short position should pass
        vault.checkPositionRisk(50 ether, 5, 2); // direction = 2 (SHORT)
    }

    function test_CheckPositionRisk_RevertOnExcessiveLeverage() public {
        _addLiquidity(liquidityProvider, 100 ether);

        // Try very high leverage - should revert
        vm.expectRevert();
        vault.checkPositionRisk(10 ether, 200, 1); // 200x leverage
    }

    function test_CheckPositionRisk_RevertOnExcessiveSize() public {
        _addLiquidity(liquidityProvider, 100 ether);

        // Try position larger than vault can handle - should revert
        vm.expectRevert();
        vault.checkPositionRisk(10_000 ether, 10, 1);
    }

    // ========================================================================
    // TVL BASED LEVERAGE TESTS
    // ========================================================================

    function test_LeverageIncreasesWithTVL() public {
        // Start with small TVL
        _addLiquidity(liquidityProvider, 50 ether);

        // Small position with low leverage should pass
        vault.checkPositionRisk(5 ether, 5, 1);

        // Add more liquidity to increase TVL
        _addLiquidity(user1, 500 ether);

        // Now slightly larger positions should pass
        vault.checkPositionRisk(20 ether, 10, 1);
    }

    // ========================================================================
    // EDGE CASES
    // ========================================================================

    function test_LeverageLimit_ZeroLiquidity() public {
        // No liquidity added
        // checkPositionRisk should fail
        vm.expectRevert();
        vault.checkPositionRisk(1 ether, 10, 1);
    }

    function test_LeverageLimit_MinimalLiquidity() public {
        // Add minimal liquidity
        _addLiquidity(liquidityProvider, 1 ether);

        // Very small position might pass
        // But anything significant should fail
        vm.expectRevert();
        vault.checkPositionRisk(10 ether, 50, 1);
    }

    // ========================================================================
    // FUZZ TESTS
    // ========================================================================

    function testFuzz_CheckPositionRisk(uint256 positionSize, uint8 leverage) public {
        // Bound inputs
        leverage = uint8(bound(leverage, 1, 50));
        // positionSize must be >= minBetAmount * leverage for collateral check
        uint256 minPositionSize = DEFAULT_MIN_BET * leverage;
        positionSize = bound(positionSize, minPositionSize, DEFAULT_MAX_BET);

        // Add sufficient liquidity
        _addLiquidity(liquidityProvider, 10_000 ether);

        // This should not revert for reasonable inputs
        vault.checkPositionRisk(positionSize, leverage, 1);
    }
}
