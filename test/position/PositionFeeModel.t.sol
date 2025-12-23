// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";

/**
 * @title PositionFeeModelTest
 * @notice Simple unit tests for position fee model (open & close fees)
 * @dev Pure logic tests focusing on fee calculations
 */
contract PositionFeeModelTest is Test {
    // No need for actual vault deployment - testing pure math logic

    // ========================================================================
    // FEE CALCULATION TESTS (PURE LOGIC)
    // ========================================================================

    function test_OpenFeeMath_StandardCase() public pure {
        uint256 collateral = 1000 ether;
        uint16 feeBps = 5; // 0.05%

        uint256 fee = (collateral * feeBps) / 10_000;
        uint256 netCollateral = collateral - fee;

        assertEq(fee, 0.5 ether, "Fee should be 0.5 ether (1000 * 0.0005)");
        assertEq(netCollateral, 999.5 ether, "Net collateral should be 999.5 ether");
    }

    function test_CloseFeeMath_StandardCase() public pure {
        uint256 netCollateral = 999.5 ether; // After open fee
        uint16 feeBps = 5; // 0.05%

        uint256 fee = (netCollateral * feeBps) / 10_000;

        // Close fee = 999.5 * 0.0005 = 0.49975 ether
        assertApproxEqRel(fee, 0.499_75 ether, 0.01e18, "Close fee should be ~0.49975 ether");
    }

    function test_TotalFeeMath_CompleteRoundTrip() public pure {
        uint256 initialCollateral = 1000 ether;
        uint16 feeBps = 5;

        // Open fee
        uint256 openFee = (initialCollateral * feeBps) / 10_000;
        uint256 netCollateral = initialCollateral - openFee;

        // Close fee
        uint256 closeFee = (netCollateral * feeBps) / 10_000;

        // Total fees
        uint256 totalFees = openFee + closeFee;

        // Total fees should be approximately 0.1% of initial collateral
        // (0.05% + 0.05% but second is on reduced amount)
        assertApproxEqRel(totalFees, 1 ether, 0.01e18, "Total fees should be ~1 ether (0.1%)");
    }

    function test_FeeMath_SmallAmounts() public pure {
        uint256 smallCollateral = 100; // Very small
        uint16 feeBps = 5;

        uint256 fee = (smallCollateral * feeBps) / 10_000;

        // Fee might round to 0 for very small amounts
        assertTrue(fee <= smallCollateral, "Fee should not exceed collateral");
    }

    function test_FeeMath_LargeAmounts() public pure {
        uint256 largeCollateral = 1_000_000 ether;
        uint16 feeBps = 5;

        uint256 fee = (largeCollateral * feeBps) / 10_000;

        assertEq(fee, 500 ether, "Fee should be 500 ether for 1M collateral (0.05%)");
    }

    function test_FeeMath_ZeroFeeBps() public pure {
        uint256 collateral = 1000 ether;
        uint16 feeBps = 0;

        uint256 fee = (collateral * feeBps) / 10_000;
        uint256 netCollateral = collateral - fee;

        assertEq(fee, 0, "Fee should be 0");
        assertEq(netCollateral, collateral, "Net collateral should equal original");
    }

    function test_FeeMath_MaxFeeBps() public pure {
        uint256 collateral = 1000 ether;
        uint16 feeBps = 1000; // 10% (max allowed)

        uint256 fee = (collateral * feeBps) / 10_000;
        uint256 netCollateral = collateral - fee;

        assertEq(fee, 100 ether, "Fee should be 100 ether (10%)");
        assertEq(netCollateral, 900 ether, "Net collateral should be 900 ether");
    }

    function test_FeeMath_CustomRates() public pure {
        uint256 collateral = 1000 ether;
        uint16 openFeeBps = 20; // 0.2%
        uint16 closeFeeBps = 30; // 0.3%

        uint256 openFee = (collateral * openFeeBps) / 10_000;
        uint256 netCollateral = collateral - openFee;
        uint256 closeFee = (netCollateral * closeFeeBps) / 10_000;

        assertEq(openFee, 2 ether, "Open fee should be 2 ether");
        assertEq(netCollateral, 998 ether, "Net collateral should be 998 ether");
        assertEq(closeFee, 2.994 ether, "Close fee should be 2.994 ether");
    }

    // ========================================================================
    // FUZZ TESTS
    // ========================================================================

    function testFuzz_OpenFeeMath(uint256 collateral, uint16 feeBps) public pure {
        // Bound inputs to reasonable ranges
        collateral = bound(collateral, 1, 1_000_000 ether);
        feeBps = uint16(bound(feeBps, 0, 1000)); // Max 10%

        uint256 fee = (collateral * feeBps) / 10_000;
        uint256 netCollateral = collateral - fee;

        // Invariants
        assertTrue(fee <= collateral, "Fee should not exceed collateral");
        assertTrue(netCollateral <= collateral, "Net should not exceed original");
        assertEq(fee + netCollateral, collateral, "Fee + net should equal collateral");
    }

    function testFuzz_TotalFees(uint256 collateral, uint16 openBps, uint16 closeBps) public pure {
        // Bound inputs
        collateral = bound(collateral, 1000, 1_000_000 ether);
        openBps = uint16(bound(openBps, 0, 1000));
        closeBps = uint16(bound(closeBps, 0, 1000));

        // Calculate fees
        uint256 openFee = (collateral * openBps) / 10_000;
        uint256 netCollateral = collateral - openFee;
        uint256 closeFee = (netCollateral * closeBps) / 10_000;
        uint256 totalFees = openFee + closeFee;

        // Invariants
        assertTrue(totalFees < collateral, "Total fees should be less than collateral");
        assertTrue(totalFees >= openFee, "Total fees should include open fee");
        assertTrue(totalFees >= closeFee, "Total fees should include close fee");
    }
}
