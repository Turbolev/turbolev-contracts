// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./BaseTest.sol";

/**
 * @title TreasuryAndFeesTest
 * @notice Unit tests for Treasury and Fee Withdrawal functionality
 * @dev Tests cover:
 *      - Treasury address management
 *      - Fee withdrawal to treasury/owner
 *      - Fee configuration (staking, early withdrawal, position fees)
 *      - Fee collection integration
 */
contract TreasuryAndFeesTest is BaseTest {
    address public treasury;

    // ========================================================================
    // SETUP
    // ========================================================================

    function setUp() public override {
        super.setUp();

        treasury = makeAddr("treasury");

        // Enable trading
        vm.prank(owner);
        assetVault.setTradingEnabled(true);
    }

    // ========================================================================
    // TREASURY MANAGEMENT TESTS
    // ========================================================================

    function test_SetTreasury_Success() public {
        vm.prank(owner);
        assetVault.setTreasury(treasury);

        assertEq(assetVault.treasury(), treasury, "Treasury should be updated");
    }

    function test_SetTreasury_CanSetToZero() public {
        // First set a treasury
        vm.prank(owner);
        assetVault.setTreasury(treasury);

        // Then set to zero (falls back to owner)
        vm.prank(owner);
        assetVault.setTreasury(address(0));

        assertEq(assetVault.treasury(), address(0), "Treasury should be zero");
    }

    function test_SetTreasury_OnlyAuthorized() public {
        vm.expectRevert(abi.encodeWithSelector(AssetVaultUpgradeable.NotAuthorized.selector));
        vm.prank(user1);
        assetVault.setTreasury(treasury);
    }

    function test_SetTreasury_EmitsEvent() public {
        vm.expectEmit(true, true, false, false);
        emit AssetVaultUpgradeable.TreasuryUpdated(address(0), treasury);

        vm.prank(owner);
        assetVault.setTreasury(treasury);
    }

    // ========================================================================
    // FEE CONFIGURATION TESTS
    // ========================================================================

    function test_SetStakingFeeBps_Success() public {
        uint16 newFee = 100; // 1%

        vm.prank(owner);
        assetVault.setStakingFeeBps(newFee);

        assertEq(assetVault.stakingFeeBps(), newFee, "Staking fee should be updated");
    }

    function test_SetStakingFeeBps_RevertsOnTooHigh() public {
        // Max is 10% (1000 bps)
        vm.expectRevert(abi.encodeWithSelector(AssetVaultUpgradeable.InvalidParameters.selector));
        vm.prank(owner);
        assetVault.setStakingFeeBps(1001);
    }

    function test_SetEarlyWithdrawalFeeBps_Success() public {
        uint16 newFee = 500; // 5%

        vm.prank(owner);
        assetVault.setEarlyWithdrawalFeeBps(newFee);

        assertEq(
            assetVault.earlyWithdrawalFeeBps(), newFee, "Early withdrawal fee should be updated"
        );
    }

    function test_SetEarlyWithdrawalFeeBps_RevertsOnTooHigh() public {
        // Max is 50% (5000 bps)
        vm.expectRevert(abi.encodeWithSelector(AssetVaultUpgradeable.InvalidParameters.selector));
        vm.prank(owner);
        assetVault.setEarlyWithdrawalFeeBps(5001);
    }

    function test_SetOpenPositionFeeBps_Success() public {
        uint16 newFee = 10; // 0.1%

        vm.prank(owner);
        assetVault.setOpenPositionFeeBps(newFee);

        assertEq(assetVault.openPositionFeeBps(), newFee, "Open position fee should be updated");
    }

    function test_SetOpenPositionFeeBps_RevertsOnTooHigh() public {
        // Max is 10% (1000 bps)
        vm.expectRevert(abi.encodeWithSelector(AssetVaultUpgradeable.InvalidParameters.selector));
        vm.prank(owner);
        assetVault.setOpenPositionFeeBps(1001);
    }

    function test_SetClosePositionFeeBps_Success() public {
        uint16 newFee = 10; // 0.1%

        vm.prank(owner);
        assetVault.setClosePositionFeeBps(newFee);

        assertEq(assetVault.closePositionFeeBps(), newFee, "Close position fee should be updated");
    }

    function test_SetClosePositionFeeBps_RevertsOnTooHigh() public {
        // Max is 10% (1000 bps)
        vm.expectRevert(abi.encodeWithSelector(AssetVaultUpgradeable.InvalidParameters.selector));
        vm.prank(owner);
        assetVault.setClosePositionFeeBps(1001);
    }

    // ========================================================================
    // FEE COLLECTION TESTS
    // ========================================================================

    function test_StakingFeeCollection() public {
        uint256 amount = 100 ether;
        uint16 stakingFeeBps = assetVault.stakingFeeBps();

        uint256 expectedFee = (amount * stakingFeeBps) / 10_000;

        uint256 withdrawableFeeBefore = assetVault.withdrawableFees();

        // Add liquidity (which collects staking fee)
        _addLiquidity(user1, amount);

        uint256 withdrawableFeeAfter = assetVault.withdrawableFees();

        assertEq(
            withdrawableFeeAfter - withdrawableFeeBefore,
            expectedFee,
            "Withdrawable fees should include staking fee"
        );
    }

    // ========================================================================
    // FEE WITHDRAWAL TESTS
    // ========================================================================

    function test_WithdrawFees_ToOwner() public {
        // Collect some fees first
        _addLiquidity(user1, 100 ether);

        uint256 withdrawable = assetVault.withdrawableFees();
        assertTrue(withdrawable > 0, "Should have withdrawable fees");

        uint256 ownerBalanceBefore = projectToken.balanceOf(owner);

        // Withdraw all fees (no treasury set, goes to owner)
        vm.prank(owner);
        assetVault.withdrawFees(0);

        uint256 ownerBalanceAfter = projectToken.balanceOf(owner);

        assertEq(ownerBalanceAfter - ownerBalanceBefore, withdrawable, "Owner should receive fees");
        assertEq(assetVault.withdrawableFees(), 0, "Withdrawable fees should be 0");
    }

    function test_WithdrawFees_ToTreasury() public {
        // Set treasury
        vm.prank(owner);
        assetVault.setTreasury(treasury);

        // Collect some fees
        _addLiquidity(user1, 100 ether);

        uint256 withdrawable = assetVault.withdrawableFees();
        uint256 treasuryBalanceBefore = projectToken.balanceOf(treasury);

        // Withdraw all fees
        vm.prank(owner);
        assetVault.withdrawFees(0);

        uint256 treasuryBalanceAfter = projectToken.balanceOf(treasury);

        assertEq(
            treasuryBalanceAfter - treasuryBalanceBefore,
            withdrawable,
            "Treasury should receive fees"
        );
    }

    function test_WithdrawFees_PartialAmount() public {
        // Collect some fees
        _addLiquidity(user1, 100 ether);

        uint256 withdrawable = assetVault.withdrawableFees();
        uint256 partialAmount = withdrawable / 2;

        vm.prank(owner);
        assetVault.withdrawFees(partialAmount);

        assertEq(
            assetVault.withdrawableFees(),
            withdrawable - partialAmount,
            "Should have remaining fees"
        );
    }

    function test_WithdrawFees_RevertsOnZeroFees() public {
        // No fees collected
        assertEq(assetVault.withdrawableFees(), 0, "Should have no fees");

        vm.expectRevert(abi.encodeWithSelector(AssetVaultUpgradeable.InvalidAmount.selector));
        vm.prank(owner);
        assetVault.withdrawFees(0);
    }

    function test_WithdrawFees_RevertsOnInsufficientFees() public {
        // Collect some fees
        _addLiquidity(user1, 100 ether);

        uint256 withdrawable = assetVault.withdrawableFees();

        vm.expectRevert(
            abi.encodeWithSelector(AssetVaultUpgradeable.InsufficientLiquidity.selector)
        );
        vm.prank(owner);
        assetVault.withdrawFees(withdrawable + 1);
    }

    function test_WithdrawFees_OnlyAuthorized() public {
        _addLiquidity(user1, 100 ether);

        vm.expectRevert(abi.encodeWithSelector(AssetVaultUpgradeable.NotAuthorized.selector));
        vm.prank(user1);
        assetVault.withdrawFees(0);
    }

    function test_WithdrawFees_EmitsEvent() public {
        _addLiquidity(user1, 100 ether);

        uint256 withdrawable = assetVault.withdrawableFees();

        vm.expectEmit(true, false, false, true);
        emit AssetVaultUpgradeable.FeesWithdrawn(owner, withdrawable, 0, block.timestamp);

        vm.prank(owner);
        assetVault.withdrawFees(0);
    }

    function test_WithdrawFees_ReducesTotalLiquidity() public {
        _addLiquidity(user1, 100 ether);

        uint256 liquidityBefore = assetVault.getVaultInfo().totalLiquidity;
        uint256 withdrawable = assetVault.withdrawableFees();

        vm.prank(owner);
        assetVault.withdrawFees(0);

        uint256 liquidityAfter = assetVault.getVaultInfo().totalLiquidity;

        assertEq(
            liquidityBefore - liquidityAfter,
            withdrawable,
            "Total liquidity should be reduced by fee amount"
        );
    }

    // ========================================================================
    // INTEGRATION TESTS
    // ========================================================================

    function test_MultipleFeeTypes_AccumulateCorrectly() public {
        // Set higher staking fee for testing
        vm.prank(owner);
        assetVault.setStakingFeeBps(500); // 5%

        uint256 stakingAmount = 100 ether;
        uint256 expectedStakingFee = (stakingAmount * 500) / 10_000; // 5 ether

        // Add liquidity - collects staking fee
        _addLiquidity(user1, stakingAmount);

        uint256 withdrawableAfterStaking = assetVault.withdrawableFees();
        assertEq(withdrawableAfterStaking, expectedStakingFee, "Staking fee should be collected");

        // Total fees should match
        AssetVaultUpgradeable.VaultInfo memory info = assetVault.getVaultInfo();
        assertEq(info.totalStakingFees, expectedStakingFee, "Total staking fees should be tracked");
    }

    // ========================================================================
    // FUZZ TESTS
    // ========================================================================

    function testFuzz_StakingFeeBps(uint16 fee) public {
        fee = uint16(bound(fee, 0, 1000)); // Max 10%

        vm.prank(owner);
        assetVault.setStakingFeeBps(fee);

        assertEq(assetVault.stakingFeeBps(), fee);
    }

    function testFuzz_EarlyWithdrawalFeeBps(uint16 fee) public {
        fee = uint16(bound(fee, 0, 5000)); // Max 50%

        vm.prank(owner);
        assetVault.setEarlyWithdrawalFeeBps(fee);

        assertEq(assetVault.earlyWithdrawalFeeBps(), fee);
    }

    function testFuzz_WithdrawFees(uint256 amount) public {
        // Add significant liquidity to generate fees
        _addLiquidity(user1, 1000 ether);

        uint256 withdrawable = assetVault.withdrawableFees();
        amount = bound(amount, 1, withdrawable);

        uint256 ownerBalanceBefore = projectToken.balanceOf(owner);

        vm.prank(owner);
        assetVault.withdrawFees(amount);

        uint256 ownerBalanceAfter = projectToken.balanceOf(owner);

        assertEq(ownerBalanceAfter - ownerBalanceBefore, amount);
        assertEq(assetVault.withdrawableFees(), withdrawable - amount);
    }
}
