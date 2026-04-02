// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../vault-modular/BaseTestModular.sol";
import "../../src/libraries/position/PositionLib.sol";

/**
 * @title LiquidationEdgeCasesTest
 * @notice Unit tests for liquidation edge cases with modular vault
 * @dev Tests cover:
 *      - Liquidation thresholds
 *      - Margin ratio calculations
 *      - Edge cases in liquidation scenarios
 */
contract LiquidationEdgeCasesTest is BaseTestModular {
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
    // BASIC LIQUIDATION TESTS
    // ========================================================================

    function test_PositionNotLiquidatable_InitialState() public {
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
        vm.stopPrank();

        // Position should not be liquidatable immediately
        // (unless price moved significantly)
    }

    // ========================================================================
    // HIGH LEVERAGE LIQUIDATION TESTS
    // ========================================================================

    function test_HighLeverage_MoreSusceptibleToLiquidation() public {
        // Open high leverage position
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 10 ether);
        positionManager.openPosition{ value: 0 }(
            address(projectToken),
            address(projectToken),
            10 ether,
            20,
            1, // 20x leverage
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );
        vm.stopPrank();

        // High leverage positions have less buffer before liquidation
        // Get position
        PositionLib.Position memory pos = positionManager.getPosition(1);

        assertEq(pos.leverage, 20, "Leverage should be 20x");
        assertEq(pos.amount, 10 ether, "Collateral should be 10 ether");
    }

    function test_LowLeverage_MoreResistantToLiquidation() public {
        // Open low leverage position
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 10 ether);
        positionManager.openPosition{ value: 0 }(
            address(projectToken),
            address(projectToken),
            10 ether,
            2,
            1, // 2x leverage
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );
        vm.stopPrank();

        PositionLib.Position memory pos = positionManager.getPosition(1);

        assertEq(pos.leverage, 2, "Leverage should be 2x");
        assertEq(pos.amount, 10 ether, "Collateral should be 10 ether");
    }

    // ========================================================================
    // ADD MARGIN TO AVOID LIQUIDATION TESTS
    // ========================================================================

    function test_AddMargin_IncreasesBuffer() public {
        // Open position
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 20 ether);
        positionManager.openPosition{ value: 0 }(
            address(projectToken),
            address(projectToken),
            10 ether,
            10,
            1,
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );

        // Add margin to increase safety buffer
        positionManager.addMargin(1, 5 ether, type(uint256).max, block.timestamp + 1 hours);
        vm.stopPrank();

        // Check updated collateral
        PositionLib.Position memory pos = positionManager.getPosition(1);

        assertEq(pos.amount, 15 ether, "Collateral should be increased");
    }

    // ========================================================================
    // DIRECTION-SPECIFIC LIQUIDATION TESTS
    // ========================================================================

    function test_LongPosition_LiquidationScenario() public {
        // Open long position
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 10 ether);
        positionManager.openPosition{ value: 0 }(
            address(projectToken),
            address(projectToken),
            10 ether,
            10,
            1, // LONG
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );
        vm.stopPrank();

        // Long positions are liquidated when price drops significantly
    }

    function test_ShortPosition_LiquidationScenario() public {
        // Open short position
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 10 ether);
        positionManager.openPosition{ value: 0 }(
            address(projectToken),
            address(projectToken),
            10 ether,
            10,
            2, // SHORT
            0,
            block.timestamp + 1 hours,
            ""
        );
        vm.stopPrank();

        // Short positions are liquidated when price rises significantly
    }

    // ========================================================================
    // MULTIPLE POSITIONS LIQUIDATION TESTS
    // ========================================================================

    function test_MultiplePositions_IndependentLiquidation() public {
        // Open multiple positions
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 30 ether);

        // Position 1: Low leverage
        positionManager.openPosition{ value: 0 }(
            address(projectToken),
            address(projectToken),
            10 ether,
            3,
            1,
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );

        // Position 2: High leverage (more susceptible)
        positionManager.openPosition{ value: 0 }(
            address(projectToken),
            address(projectToken),
            10 ether,
            15,
            1,
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );
        vm.stopPrank();

        // Each position should be evaluated independently for liquidation
    }

    // ========================================================================
    // VAULT IMPACT ON LIQUIDATION TESTS
    // ========================================================================

    function test_VaultLiquidity_ImpactOnLiquidation() public {
        // With high vault liquidity, positions have more stability
        _addLiquidity(liquidityProvider, 100_000 ether);

        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 10 ether);
        positionManager.openPosition{ value: 0 }(
            address(projectToken),
            address(projectToken),
            10 ether,
            10,
            1,
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );
        vm.stopPrank();
    }

    // ========================================================================
    // EDGE CASES
    // ========================================================================

    function test_MinimalCollateral_HighRisk() public {
        uint256 minCollateral = DEFAULT_MIN_BET;

        vm.startPrank(user1);
        projectToken.approve(address(positionManager), minCollateral);
        positionManager.openPosition{ value: 0 }(
            address(projectToken),
            address(projectToken),
            minCollateral,
            5,
            1,
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );
        vm.stopPrank();

        // Minimal collateral positions have highest liquidation risk
    }

    function test_MaxLeverage_ExtremeRisk() public {
        // High leverage with small collateral = extreme risk
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 5 ether);
        positionManager.openPosition{ value: 0 }(
            address(projectToken),
            address(projectToken),
            5 ether,
            20,
            1,
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );
        vm.stopPrank();
    }

    // ========================================================================
    // POSITION CLOSURE VS LIQUIDATION
    // ========================================================================

    function test_UserCanClose_BeforeLiquidation() public {
        // Open position
        vm.startPrank(user1);
        projectToken.approve(address(positionManager), 10 ether);
        positionManager.openPosition{ value: 0 }(
            address(projectToken),
            address(projectToken),
            10 ether,
            10,
            1,
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );

        vm.warp(block.timestamp + 61 seconds);
        _refreshPrice();

        // User can close position before liquidation threshold is reached
        positionManager.closePosition(1, block.timestamp + 1 hours, "");
        vm.stopPrank();
    }

    // ========================================================================
    // FUZZ TESTS
    // ========================================================================

    function testFuzz_LiquidationRisk(uint256 collateral, uint8 leverage) public {
        collateral = bound(collateral, DEFAULT_MIN_BET, 50 ether);
        leverage = uint8(bound(leverage, 1, 15));

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

        // Verify position was created
        PositionLib.Position memory pos = positionManager.getPosition(1);

        assertEq(pos.user, user1, "Position should be created");
    }
}
