// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "../../src/libraries/VaultPayoutLib.sol";

contract VaultPayoutLibTest is Test {
    // Constants from library
    uint256 constant BASIS_POINTS = 10_000;

    // ========================================================================
    // CALCULATE PAYOUT TESTS
    // ========================================================================

    function test_CalculatePayout_Profit() public pure {
        // Trader won: payout > collateral
        VaultPayoutLib.PayoutParams memory params = VaultPayoutLib.PayoutParams({
            totalAmount: 150 ether, // Total payout
            collateral: 100 ether, // Original collateral
            availableLiquidity: 100 ether // Vault liquidity
        });

        VaultPayoutLib.PayoutResult memory result = VaultPayoutLib.calculatePayout(params);

        assertEq(result.rewardsFromVault, 50 ether); // 150 - 100 = 50 from vault
        assertEq(result.requiredLiquidity, 50 ether);
        assertTrue(result.canPayout);
    }

    function test_CalculatePayout_Loss() public pure {
        // Trader lost: payout < collateral (but still returns something)
        VaultPayoutLib.PayoutParams memory params = VaultPayoutLib.PayoutParams({
            totalAmount: 50 ether, // Partial return
            collateral: 100 ether,
            availableLiquidity: 100 ether
        });

        VaultPayoutLib.PayoutResult memory result = VaultPayoutLib.calculatePayout(params);

        assertEq(result.rewardsFromVault, 0); // No vault rewards needed
        assertEq(result.requiredLiquidity, 0);
        assertTrue(result.canPayout);
    }

    function test_CalculatePayout_InsufficientLiquidity() public pure {
        VaultPayoutLib.PayoutParams memory params = VaultPayoutLib.PayoutParams({
            totalAmount: 200 ether,
            collateral: 100 ether,
            availableLiquidity: 50 ether // Only 50, need 100
        });

        VaultPayoutLib.PayoutResult memory result = VaultPayoutLib.calculatePayout(params);

        assertEq(result.rewardsFromVault, 100 ether);
        assertEq(result.requiredLiquidity, 100 ether);
        assertFalse(result.canPayout); // Cannot payout
    }

    function test_CalculatePayout_ExactLiquidity() public pure {
        VaultPayoutLib.PayoutParams memory params = VaultPayoutLib.PayoutParams({
            totalAmount: 150 ether,
            collateral: 100 ether,
            availableLiquidity: 50 ether // Exactly what's needed
        });

        VaultPayoutLib.PayoutResult memory result = VaultPayoutLib.calculatePayout(params);

        assertEq(result.rewardsFromVault, 50 ether);
        assertTrue(result.canPayout);
    }

    function test_CalculatePayout_ZeroCollateral() public pure {
        VaultPayoutLib.PayoutParams memory params = VaultPayoutLib.PayoutParams({
            totalAmount: 100 ether, collateral: 0, availableLiquidity: 100 ether
        });

        VaultPayoutLib.PayoutResult memory result = VaultPayoutLib.calculatePayout(params);

        assertEq(result.rewardsFromVault, 100 ether); // All from vault
        assertTrue(result.canPayout);
    }

    // ========================================================================
    // CALCULATE CLOSE FEE TESTS
    // ========================================================================

    function test_CalculateCloseFee_Normal() public pure {
        // 100 collateral, 50 bps fee = 0.5%
        uint256 fee = VaultPayoutLib.calculateCloseFee(100 ether, 50);
        assertEq(fee, 0.5 ether);
    }

    function test_CalculateCloseFee_ZeroCollateral() public pure {
        uint256 fee = VaultPayoutLib.calculateCloseFee(0, 50);
        assertEq(fee, 0);
    }

    function test_CalculateCloseFee_ZeroFee() public pure {
        uint256 fee = VaultPayoutLib.calculateCloseFee(100 ether, 0);
        assertEq(fee, 0);
    }

    function test_CalculateCloseFee_MaxFee() public pure {
        // 100% fee (extreme case)
        uint256 fee = VaultPayoutLib.calculateCloseFee(100 ether, 10_000);
        assertEq(fee, 100 ether);
    }

    function test_CalculateCloseFee_SmallAmount() public pure {
        // Small amount might round down
        uint256 fee = VaultPayoutLib.calculateCloseFee(1, 50);
        assertEq(fee, 0); // 1 * 50 / 10000 = 0
    }

    // ========================================================================
    // CALCULATE OPEN FEE TESTS
    // ========================================================================

    function test_CalculateOpenFee_Normal() public pure {
        // 100 deposit, 50 bps fee
        (uint256 fee, uint256 netAmount) = VaultPayoutLib.calculateOpenFee(100 ether, 50);

        assertEq(fee, 0.5 ether);
        assertEq(netAmount, 99.5 ether);
    }

    function test_CalculateOpenFee_ZeroAmount() public pure {
        (uint256 fee, uint256 netAmount) = VaultPayoutLib.calculateOpenFee(0, 50);

        assertEq(fee, 0);
        assertEq(netAmount, 0);
    }

    function test_CalculateOpenFee_ZeroFee() public pure {
        (uint256 fee, uint256 netAmount) = VaultPayoutLib.calculateOpenFee(100 ether, 0);

        assertEq(fee, 0);
        assertEq(netAmount, 100 ether);
    }

    function test_CalculateOpenFee_LargeAmount() public pure {
        (uint256 fee, uint256 netAmount) = VaultPayoutLib.calculateOpenFee(1_000_000 ether, 100);

        assertEq(fee, 10_000 ether); // 1%
        assertEq(netAmount, 990_000 ether);
    }

    // ========================================================================
    // CALCULATE PNL UPDATE TESTS
    // ========================================================================

    function test_CalculatePnLUpdate_VaultGains() public pure {
        // Vault gains (trader loses)
        VaultPayoutLib.PnLUpdateParams memory params = VaultPayoutLib.PnLUpdateParams({
            collateral: 100 ether,
            vaultPnL: 50 ether, // Positive = vault gains
            closeFeeBps: 50, // 0.5%
            currentLifetimePnL: 0,
            isNegativePnL: false
        });

        VaultPayoutLib.PnLUpdateResult memory result = VaultPayoutLib.calculatePnLUpdate(params);

        assertEq(result.closeFee, 0.5 ether);
        assertEq(result.liquidityChange, 50 ether);
        assertTrue(result.isLiquidityIncrease);
        assertEq(result.newLifetimePnL, 50.5 ether); // 50 + 0.5 fee
        assertFalse(result.newIsNegativePnL);
    }

    function test_CalculatePnLUpdate_VaultLoses() public pure {
        // Vault loses (trader wins)
        VaultPayoutLib.PnLUpdateParams memory params = VaultPayoutLib.PnLUpdateParams({
            collateral: 100 ether,
            vaultPnL: -50 ether, // Negative = vault loses
            closeFeeBps: 50,
            currentLifetimePnL: 100 ether,
            isNegativePnL: false
        });

        VaultPayoutLib.PnLUpdateResult memory result = VaultPayoutLib.calculatePnLUpdate(params);

        assertEq(result.closeFee, 0.5 ether);
        assertEq(result.liquidityChange, 0); // Losses handled via payout
        assertFalse(result.isLiquidityIncrease);

        // Loss 50 - closeFee 0.5 = net loss 49.5
        // 100 - 49.5 = 50.5
        assertEq(result.newLifetimePnL, 50.5 ether);
        assertFalse(result.newIsNegativePnL);
    }

    function test_CalculatePnLUpdate_FlipsToNegative() public pure {
        // Large loss flips lifetime PnL to negative
        VaultPayoutLib.PnLUpdateParams memory params = VaultPayoutLib.PnLUpdateParams({
            collateral: 100 ether,
            vaultPnL: -200 ether,
            closeFeeBps: 50,
            currentLifetimePnL: 50 ether,
            isNegativePnL: false
        });

        VaultPayoutLib.PnLUpdateResult memory result = VaultPayoutLib.calculatePnLUpdate(params);

        // Loss 200 - fee 0.5 = 199.5 net loss
        // 50 (current) - 199.5 = -149.5, flip sign: 149.5 negative
        assertTrue(result.newIsNegativePnL);
        assertEq(result.newLifetimePnL, 149.5 ether);
    }

    function test_CalculatePnLUpdate_RecoverFromNegative() public pure {
        // Vault gain recovers from negative lifetime PnL
        VaultPayoutLib.PnLUpdateParams memory params = VaultPayoutLib.PnLUpdateParams({
            collateral: 100 ether,
            vaultPnL: 200 ether, // Large gain
            closeFeeBps: 0,
            currentLifetimePnL: 50 ether,
            isNegativePnL: true // Currently negative
        });

        VaultPayoutLib.PnLUpdateResult memory result = VaultPayoutLib.calculatePnLUpdate(params);

        // 200 gain - 50 (existing loss) = 150 profit
        assertFalse(result.newIsNegativePnL);
        assertEq(result.newLifetimePnL, 150 ether);
    }

    function test_CalculatePnLUpdate_ZeroFee() public pure {
        VaultPayoutLib.PnLUpdateParams memory params = VaultPayoutLib.PnLUpdateParams({
            collateral: 100 ether,
            vaultPnL: 50 ether,
            closeFeeBps: 0, // No fee
            currentLifetimePnL: 0,
            isNegativePnL: false
        });

        VaultPayoutLib.PnLUpdateResult memory result = VaultPayoutLib.calculatePnLUpdate(params);

        assertEq(result.closeFee, 0);
        assertEq(result.newLifetimePnL, 50 ether);
    }

    function test_CalculatePnLUpdate_ZeroCollateral() public pure {
        VaultPayoutLib.PnLUpdateParams memory params = VaultPayoutLib.PnLUpdateParams({
            collateral: 0,
            vaultPnL: 50 ether,
            closeFeeBps: 50,
            currentLifetimePnL: 0,
            isNegativePnL: false
        });

        VaultPayoutLib.PnLUpdateResult memory result = VaultPayoutLib.calculatePnLUpdate(params);

        assertEq(result.closeFee, 0); // No collateral = no fee
        assertEq(result.newLifetimePnL, 50 ether);
    }

    // ========================================================================
    // CALCULATE ADJUSTED PNL TESTS
    // ========================================================================

    function test_CalculateAdjustedPnL_Positive() public pure {
        int256 adjusted = VaultPayoutLib.calculateAdjustedPnL(100 ether, 5 ether);
        assertEq(adjusted, 105 ether);
    }

    function test_CalculateAdjustedPnL_Negative() public pure {
        int256 adjusted = VaultPayoutLib.calculateAdjustedPnL(-100 ether, 5 ether);
        assertEq(adjusted, -95 ether);
    }

    function test_CalculateAdjustedPnL_Zero() public pure {
        int256 adjusted = VaultPayoutLib.calculateAdjustedPnL(0, 5 ether);
        assertEq(adjusted, 5 ether);
    }

    // ========================================================================
    // SHOULD QUEUE PAYOUT TESTS
    // ========================================================================

    function test_ShouldQueuePayout_True() public pure {
        bool shouldQueue = VaultPayoutLib.shouldQueuePayout(100 ether, 50 ether);
        assertTrue(shouldQueue);
    }

    function test_ShouldQueuePayout_False() public pure {
        bool shouldQueue = VaultPayoutLib.shouldQueuePayout(50 ether, 100 ether);
        assertFalse(shouldQueue);
    }

    function test_ShouldQueuePayout_Exact() public pure {
        bool shouldQueue = VaultPayoutLib.shouldQueuePayout(100 ether, 100 ether);
        assertFalse(shouldQueue); // Equal, can payout
    }

    // ========================================================================
    // CALCULATE EXPOSURE CHANGE TESTS
    // ========================================================================

    function test_CalculateExposureChange_Long() public pure {
        (uint256 longChange, uint256 shortChange) =
            VaultPayoutLib.calculateExposureChange(100 ether, 1);

        assertEq(longChange, 100 ether);
        assertEq(shortChange, 0);
    }

    function test_CalculateExposureChange_Short() public pure {
        (uint256 longChange, uint256 shortChange) =
            VaultPayoutLib.calculateExposureChange(100 ether, 2);

        assertEq(longChange, 0);
        assertEq(shortChange, 100 ether);
    }

    function test_CalculateExposureChange_InvalidDirection() public pure {
        (uint256 longChange, uint256 shortChange) =
            VaultPayoutLib.calculateExposureChange(100 ether, 0);

        assertEq(longChange, 0);
        assertEq(shortChange, 0);
    }

    // ========================================================================
    // FUZZ TESTS
    // ========================================================================

    function testFuzz_CalculatePayout_ConsistentRewards(
        uint128 totalAmount,
        uint128 collateral,
        uint128 liquidity
    ) public pure {
        vm.assume(totalAmount >= collateral);

        VaultPayoutLib.PayoutParams memory params = VaultPayoutLib.PayoutParams({
            totalAmount: totalAmount, collateral: collateral, availableLiquidity: liquidity
        });

        VaultPayoutLib.PayoutResult memory result = VaultPayoutLib.calculatePayout(params);

        // Rewards should be total - collateral
        assertEq(result.rewardsFromVault, totalAmount - collateral);

        // canPayout should be consistent with liquidity comparison
        if (result.rewardsFromVault <= liquidity) {
            assertTrue(result.canPayout);
        } else {
            assertFalse(result.canPayout);
        }
    }

    function testFuzz_CalculateFees_NeverExceedsAmount(uint128 amount, uint16 feeBps) public pure {
        vm.assume(feeBps <= BASIS_POINTS);

        uint256 closeFee = VaultPayoutLib.calculateCloseFee(amount, feeBps);
        assertLe(closeFee, amount);

        (uint256 openFee, uint256 netAmount) = VaultPayoutLib.calculateOpenFee(amount, feeBps);
        assertLe(openFee, amount);
        assertEq(openFee + netAmount, amount);
    }

    function testFuzz_CalculateExposureChange_OnlyOneChanges(uint128 positionSize, uint8 direction)
        public
        pure
    {
        direction = uint8(bound(direction, 1, 2));

        (uint256 longChange, uint256 shortChange) =
            VaultPayoutLib.calculateExposureChange(positionSize, direction);

        // One should be positionSize, other should be 0
        if (direction == 1) {
            assertEq(longChange, positionSize);
            assertEq(shortChange, 0);
        } else {
            assertEq(longChange, 0);
            assertEq(shortChange, positionSize);
        }
    }

    function testFuzz_ShouldQueuePayout_Consistent(uint128 rewardsNeeded, uint128 liquidity)
        public
        pure
    {
        bool shouldQueue = VaultPayoutLib.shouldQueuePayout(rewardsNeeded, liquidity);

        // Should match direct comparison
        assertEq(shouldQueue, rewardsNeeded > liquidity);
    }
}

