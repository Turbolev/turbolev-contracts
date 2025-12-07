// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./BaseTest.sol";

/**
 * @title PositionFeeIntegrationTest
 * @notice Integration tests for Position Fees (open & close fees)
 * @dev Tests cover:
 *      - Open position fee collection
 *      - Close position fee collection
 *      - Fee impact on collateral and payouts
 *      - Fee accumulation in vault
 */
contract PositionFeeIntegrationTest is BaseTest {
    // Test constants
    uint256 constant COLLATERAL = 10 ether;
    uint8 constant LEVERAGE = 5;
    uint8 constant DIRECTION_LONG = 1;
    uint8 constant DIRECTION_SHORT = 2;

    // ========================================================================
    // SETUP
    // ========================================================================

    function setUp() public override {
        super.setUp();

        // Add liquidity
        _addLiquidity(liquidityProvider, 1000 ether);

        // Enable trading
        vm.prank(owner);
        assetVault.setTradingEnabled(true);

        // Set initial price
        _updatePrice(address(projectToken), address(usdc), 100e18);
    }

    // ========================================================================
    // HELPER FUNCTIONS
    // ========================================================================

    function _closePosition(uint64 positionId, address user) internal {
        // Wait for minimum hold time
        vm.warp(block.timestamp + 61);
        mockAdapter.setMockTimestamp(block.timestamp);

        // Close position
        vm.prank(user);
        positionManager.closePosition(
            positionId,
            block.timestamp + 3600, // deadline
            0, // no price limit
            "" // no price update data
        );
    }

    // ========================================================================
    // OPEN POSITION FEE TESTS
    // ========================================================================

    function test_OpenPositionFee_CollectedOnNewPosition() public {
        uint16 openFeeBps = assetVault.openPositionFeeBps();
        uint256 expectedFee = (COLLATERAL * openFeeBps) / 10_000;

        uint256 withdrawableFeeBefore = assetVault.withdrawableFees();
        uint256 feeCollectedBefore = assetVault.getVaultInfo().totalFeesCollected;

        // Open position
        _openPosition(user1, COLLATERAL, LEVERAGE, DIRECTION_LONG);

        uint256 withdrawableFeeAfter = assetVault.withdrawableFees();
        uint256 feeCollectedAfter = assetVault.getVaultInfo().totalFeesCollected;

        assertEq(
            withdrawableFeeAfter - withdrawableFeeBefore,
            expectedFee,
            "Open fee should be added to withdrawable fees"
        );
        assertEq(
            feeCollectedAfter - feeCollectedBefore,
            expectedFee,
            "Open fee should be tracked in total fees"
        );
    }

    function test_OpenPositionFee_CollectedInVault() public {
        uint16 openFeeBps = assetVault.openPositionFeeBps();
        uint256 expectedFee = (COLLATERAL * openFeeBps) / 10_000;
        uint256 expectedNetCollateral = COLLATERAL - expectedFee;

        // Open position
        uint64 positionId = _openPosition(user1, COLLATERAL, LEVERAGE, DIRECTION_LONG);

        // Get position details
        PositionLib.Position memory pos = positionManager.getPosition(positionId);

        // Position size is calculated from original collateral (in PositionManager)
        // positionSize = originalCollateral * leverage
        uint256 expectedPositionSize = COLLATERAL * LEVERAGE;
        assertEq(
            pos.positionSize, expectedPositionSize, "Position size based on original collateral"
        );

        // But vault stores net collateral (after fee deduction) in betCollateral
        uint256 storedCollateral = assetVault.betCollateral(positionId);
        assertEq(
            storedCollateral, expectedNetCollateral, "Vault should store net collateral after fee"
        );
    }

    function test_OpenPositionFee_ZeroFee_Reverts() public {
        // M-06 FIX: Position fees cannot be set to 0 (MIN_OPEN_POSITION_FEE_BPS = 1)
        // Set open fee to 0 should revert
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("InvalidParameters()"));
        assetVault.setFee(2, 0); // openPosition fee type = 2
    }

    function test_OpenPositionFee_MinFee() public {
        // M-06 FIX: Test minimum fee (1 bps = 0.01%)
        vm.prank(owner);
        assetVault.setFee(2, 1); // Minimum allowed

        uint16 openFeeBps = assetVault.openPositionFeeBps();
        assertEq(openFeeBps, 1, "Open fee should be 1 bps");

        uint256 expectedFee = (COLLATERAL * 1) / 10_000;
        uint256 withdrawableFeeBefore = assetVault.withdrawableFees();

        // Open position
        _openPosition(user1, COLLATERAL, LEVERAGE, DIRECTION_LONG);

        uint256 withdrawableFeeAfter = assetVault.withdrawableFees();

        assertEq(
            withdrawableFeeAfter - withdrawableFeeBefore,
            expectedFee,
            "Minimum fee should be collected"
        );
    }

    function test_OpenPositionFee_CustomRate() public {
        // Set custom open fee rate
        uint16 customFeeBps = 50; // 0.5%
        vm.prank(owner);
        assetVault.setFee(2, customFeeBps);

        uint256 expectedFee = (COLLATERAL * customFeeBps) / 10_000;
        uint256 withdrawableFeeBefore = assetVault.withdrawableFees();

        _openPosition(user1, COLLATERAL, LEVERAGE, DIRECTION_LONG);

        uint256 withdrawableFeeAfter = assetVault.withdrawableFees();

        assertEq(
            withdrawableFeeAfter - withdrawableFeeBefore,
            expectedFee,
            "Custom open fee should be collected"
        );
    }

    // ========================================================================
    // CLOSE POSITION FEE TESTS
    // ========================================================================

    function test_ClosePositionFee_CollectedOnClose() public {
        // Open position first
        uint64 positionId = _openPosition(user1, COLLATERAL, LEVERAGE, DIRECTION_LONG);

        uint256 withdrawableFeeBefore = assetVault.withdrawableFees();

        // Close position
        _closePosition(positionId, user1);

        uint256 withdrawableFeeAfter = assetVault.withdrawableFees();

        // Close fee should be added
        assertTrue(withdrawableFeeAfter > withdrawableFeeBefore, "Close fee should be collected");
    }

    function test_ClosePositionFee_ZeroFee_Reverts() public {
        // M-06 FIX: Position fees cannot be set to 0 (MIN_CLOSE_POSITION_FEE_BPS = 1)
        // Set close fee to 0 should revert
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("InvalidParameters()"));
        assetVault.setFee(3, 0); // closePosition fee type = 3
    }

    function test_ClosePositionFee_MinFee() public {
        // M-06 FIX: Test minimum fee (1 bps = 0.01%)
        vm.prank(owner);
        assetVault.setFee(3, 1); // Minimum allowed

        uint16 closeFeeBps = assetVault.closePositionFeeBps();
        assertEq(closeFeeBps, 1, "Close fee should be 1 bps");

        // Open position
        uint64 positionId = _openPosition(user1, COLLATERAL, LEVERAGE, DIRECTION_LONG);

        // Record fees after open
        uint256 withdrawableAfterOpen = assetVault.withdrawableFees();

        // Close position
        _closePosition(positionId, user1);

        uint256 withdrawableAfterClose = assetVault.withdrawableFees();

        // Minimum close fee should be collected
        assertTrue(
            withdrawableAfterClose > withdrawableAfterOpen, "Minimum close fee should be collected"
        );
    }

    function test_ClosePositionFee_CustomRate() public {
        // Set custom close fee rate
        uint16 customFeeBps = 20; // 0.2%
        vm.prank(owner);
        assetVault.setFee(3, customFeeBps);

        // Open position
        uint64 positionId = _openPosition(user1, COLLATERAL, LEVERAGE, DIRECTION_LONG);

        PositionLib.Position memory pos = positionManager.getPosition(positionId);
        uint256 expectedCloseFee = (pos.amount * customFeeBps) / 10_000;

        uint256 withdrawableAfterOpen = assetVault.withdrawableFees();

        // Close position
        _closePosition(positionId, user1);

        uint256 withdrawableAfterClose = assetVault.withdrawableFees();

        assertEq(
            withdrawableAfterClose - withdrawableAfterOpen,
            expectedCloseFee,
            "Custom close fee should be collected"
        );
    }

    // ========================================================================
    // COMBINED FEE TESTS
    // ========================================================================

    function test_TotalFees_OpenAndClose() public {
        uint16 openFeeBps = assetVault.openPositionFeeBps();
        uint16 closeFeeBps = assetVault.closePositionFeeBps();

        uint256 expectedOpenFee = (COLLATERAL * openFeeBps) / 10_000;
        uint256 netCollateral = COLLATERAL - expectedOpenFee;
        uint256 expectedCloseFee = (netCollateral * closeFeeBps) / 10_000;
        uint256 expectedTotalFee = expectedOpenFee + expectedCloseFee;

        uint256 feesBefore = assetVault.withdrawableFees();

        // Open and close position
        uint64 positionId = _openPosition(user1, COLLATERAL, LEVERAGE, DIRECTION_LONG);
        _closePosition(positionId, user1);

        uint256 feesAfter = assetVault.withdrawableFees();

        assertApproxEqRel(
            feesAfter - feesBefore,
            expectedTotalFee,
            0.01e18, // 1% tolerance for rounding
            "Total fees should be open + close"
        );
    }

    function test_Fees_MultiplePositions() public {
        uint256 feesBefore = assetVault.withdrawableFees();

        // Open multiple positions
        uint64 pos1 = _openPosition(user1, COLLATERAL, LEVERAGE, DIRECTION_LONG);
        uint64 pos2 = _openPosition(user2, COLLATERAL * 2, LEVERAGE, DIRECTION_SHORT);

        // Close all positions
        _closePosition(pos1, user1);
        _closePosition(pos2, user2);

        uint256 feesAfter = assetVault.withdrawableFees();

        assertTrue(feesAfter > feesBefore, "Fees should accumulate from multiple positions");
    }

    // ========================================================================
    // FEE IMPACT ON PNL TESTS
    // ========================================================================

    function test_CloseFee_WhenTraderWins() public {
        uint64 positionId = _openPosition(user1, COLLATERAL, LEVERAGE, DIRECTION_LONG);

        // Price goes up 10% - trader wins
        int256 newPrice = 110e18;
        _updatePrice(address(projectToken), address(usdc), newPrice);

        uint256 vaultLiquidityBefore = assetVault.getVaultInfo().totalLiquidity;

        // Close position
        _closePosition(positionId, user1);

        uint256 vaultLiquidityAfter = assetVault.getVaultInfo().totalLiquidity;

        // Vault should have lost some liquidity (trader won)
        // But close fee partially compensates
        assertTrue(
            vaultLiquidityBefore > vaultLiquidityAfter,
            "Vault should lose liquidity when trader wins"
        );
    }

    function test_CloseFee_WhenTraderLoses() public {
        uint64 positionId = _openPosition(user1, COLLATERAL, LEVERAGE, DIRECTION_LONG);

        // Price goes down 10% - trader loses
        int256 newPrice = 90e18;
        _updatePrice(address(projectToken), address(usdc), newPrice);

        uint256 vaultLiquidityBefore = assetVault.getVaultInfo().totalLiquidity;

        // Close position
        _closePosition(positionId, user1);

        uint256 vaultLiquidityAfter = assetVault.getVaultInfo().totalLiquidity;

        // Vault should gain liquidity (trader lost + close fee)
        assertTrue(
            vaultLiquidityAfter > vaultLiquidityBefore,
            "Vault should gain liquidity when trader loses"
        );
    }

    // ========================================================================
    // EDGE CASES
    // ========================================================================

    function test_Fees_SmallCollateral() public {
        uint256 smallCollateral = 0.1 ether;
        uint16 feeBps = assetVault.openPositionFeeBps();

        // Update min bet to allow small positions
        vm.prank(owner);
        assetVault.updateVaultParams(0.01 ether, 100 ether);

        uint256 expectedFee = (smallCollateral * feeBps) / 10_000;

        // If fee rounds to 0, no error should occur
        if (expectedFee == 0) {
            uint256 feesBefore = assetVault.withdrawableFees();
            _openPosition(user1, smallCollateral, LEVERAGE, DIRECTION_LONG);
            uint256 feesAfter = assetVault.withdrawableFees();

            assertEq(feesAfter, feesBefore, "No fee collected for 0 fee");
        } else {
            uint256 feesBefore = assetVault.withdrawableFees();
            _openPosition(user1, smallCollateral, LEVERAGE, DIRECTION_LONG);
            uint256 feesAfter = assetVault.withdrawableFees();

            assertEq(feesAfter - feesBefore, expectedFee, "Small fee should be collected");
        }
    }

    function test_Fees_LargeCollateral() public {
        uint256 largeCollateral = 100 ether;
        uint16 openFeeBps = assetVault.openPositionFeeBps();
        uint256 expectedFee = (largeCollateral * openFeeBps) / 10_000;

        // Update max bet to allow large positions
        vm.prank(owner);
        assetVault.updateVaultParams(0.01 ether, 200 ether);

        uint256 feesBefore = assetVault.withdrawableFees();
        _openPosition(user1, largeCollateral, 2, DIRECTION_LONG); // Lower leverage for large positions

        uint256 feesAfter = assetVault.withdrawableFees();

        assertEq(feesAfter - feesBefore, expectedFee, "Large fee should be collected");
    }

    // ========================================================================
    // FUZZ TESTS
    // ========================================================================

    function testFuzz_OpenPositionFee(uint256 collateral, uint16 feeBps) public {
        // Bound inputs
        collateral = bound(collateral, 0.1 ether, 50 ether);
        // M-06 FIX: MIN_OPEN_POSITION_FEE_BPS = 1, so bound from 1
        feeBps = uint16(bound(feeBps, 1, 1000)); // Min 0.01%, Max 10%

        // Update vault params
        vm.prank(owner);
        assetVault.updateVaultParams(0.01 ether, 100 ether);

        // Set custom fee
        vm.prank(owner);
        assetVault.setFee(2, feeBps);

        uint256 expectedFee = (collateral * feeBps) / 10_000;
        uint256 feesBefore = assetVault.withdrawableFees();

        _openPosition(user1, collateral, LEVERAGE, DIRECTION_LONG);

        uint256 feesAfter = assetVault.withdrawableFees();

        assertEq(feesAfter - feesBefore, expectedFee, "Open fee should match expected");
    }

    function testFuzz_ClosePositionFee(uint256 collateral, uint16 closeFeeBps) public {
        // Bound inputs
        collateral = bound(collateral, 0.1 ether, 50 ether);
        // M-06 FIX: MIN_CLOSE_POSITION_FEE_BPS = 1, so bound from 1
        closeFeeBps = uint16(bound(closeFeeBps, 1, 1000)); // Min 0.01%, Max 10%

        // Update vault params
        vm.prank(owner);
        assetVault.updateVaultParams(0.01 ether, 100 ether);

        // Set custom close fee
        vm.prank(owner);
        assetVault.setFee(3, closeFeeBps);

        // Open position
        uint64 positionId = _openPosition(user1, collateral, LEVERAGE, DIRECTION_LONG);

        PositionLib.Position memory pos = positionManager.getPosition(positionId);
        uint256 expectedCloseFee = (pos.amount * closeFeeBps) / 10_000;

        uint256 feesAfterOpen = assetVault.withdrawableFees();

        // Close position
        _closePosition(positionId, user1);

        uint256 feesAfterClose = assetVault.withdrawableFees();

        assertEq(
            feesAfterClose - feesAfterOpen, expectedCloseFee, "Close fee should match expected"
        );
    }
}
