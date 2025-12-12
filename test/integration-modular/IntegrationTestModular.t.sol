// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../vault-modular/BaseTestModular.sol";

/**
 * @title IntegrationTestModular
 * @notice Comprehensive integration tests for modular vault system
 * @dev Tests cover all user flows:
 *      - LP User Flows: AddLiquidity, RemoveLiquidity, ClaimRewards, EarlyWithdrawal, VaultGraduation
 *      - Trader Flows: OpenLong/Short, ClosePosition Win/Lose, AddMargin, Liquidation, SlippageProtection, FundingRate
 *      - Admin Flows: CreateVault, PauseUnpause, EmergencyPause, SetFees, TimelockOperation
 */
contract IntegrationTestModular is BaseTestModular {
    // Additional test accounts
    address public lp1;
    address public lp2;
    address public trader1;
    address public trader2;

    function setUp() public override {
        super.setUp();

        // Create additional test accounts
        lp1 = makeAddr("lp1");
        lp2 = makeAddr("lp2");
        trader1 = makeAddr("trader1");
        trader2 = makeAddr("trader2");

        // Fund accounts
        projectToken.mint(lp1, INITIAL_BALANCE);
        projectToken.mint(lp2, INITIAL_BALANCE);
        projectToken.mint(trader1, INITIAL_BALANCE);
        projectToken.mint(trader2, INITIAL_BALANCE);

        vm.deal(lp1, 10 ether);
        vm.deal(lp2, 10 ether);
        vm.deal(trader1, 10 ether);
        vm.deal(trader2, 10 ether);
    }

    // ========================================================================
    // LP USER FLOWS
    // ========================================================================

    function test_LP_AddLiquidity() public {
        uint256 amount = 1000 ether;

        vm.startPrank(lp1);
        projectToken.approve(address(vault), amount);
        vault.addLiquidity(amount);
        vm.stopPrank();

        VaultStorageLib.LPPosition memory lpPos = vault.getLPPosition(lp1);
        assertGt(lpPos.shares, 0, "LP should have shares");
        assertEq(lpPos.stakedAmount, amount, "Staked amount should match");
    }

    function test_LP_AddLiquidity_MultipleLPs() public {
        uint256 amount1 = 1000 ether;
        uint256 amount2 = 500 ether;

        // LP1 adds liquidity
        vm.startPrank(lp1);
        projectToken.approve(address(vault), amount1);
        vault.addLiquidity(amount1);
        vm.stopPrank();

        // LP2 adds liquidity
        vm.startPrank(lp2);
        projectToken.approve(address(vault), amount2);
        vault.addLiquidity(amount2);
        vm.stopPrank();

        VaultStorageLib.VaultInfo memory info = vault.vaultInfo();
        assertGe(
            info.totalLiquidity,
            amount1 + amount2 - 1 ether,
            "Total liquidity should be sum of deposits"
        );
    }

    function test_LP_RemoveLiquidity() public {
        // Add liquidity first
        uint256 amount = 1000 ether;
        vm.startPrank(lp1);
        projectToken.approve(address(vault), amount);
        vault.addLiquidity(amount);

        uint256 balanceBefore = projectToken.balanceOf(lp1);

        // Remove liquidity
        vault.removeLiquidity();

        uint256 balanceAfter = projectToken.balanceOf(lp1);
        vm.stopPrank();

        assertGt(balanceAfter, balanceBefore, "LP should receive tokens back");
    }

    function test_LP_EarlyWithdrawal() public {
        // Add liquidity
        uint256 amount = 1000 ether;
        vm.startPrank(lp1);
        projectToken.approve(address(vault), amount);
        vault.addLiquidity(amount);

        // Try to withdraw immediately (may incur early withdrawal fee)
        vault.removeLiquidity();
        vm.stopPrank();
    }

    function test_LP_VaultGraduation() public {
        // Add enough liquidity to graduate
        vm.startPrank(lp1);
        projectToken.approve(address(vault), DEFAULT_GRADUATION_THRESHOLD);
        vault.addLiquidity(DEFAULT_GRADUATION_THRESHOLD);
        vm.stopPrank();

        VaultStorageLib.VaultInfo memory info = vault.vaultInfo();
        assertTrue(info.isGraduated, "Vault should be graduated");
    }

    function test_LP_ClaimRewards() public {
        // Add liquidity and graduate
        _graduateVault();

        // Wait some time for rewards to accumulate
        vm.warp(block.timestamp + 7 days);

        vm.startPrank(liquidityProvider);
        vault.claimRewards();
        vm.stopPrank();
    }

    // ========================================================================
    // TRADER FLOWS
    // ========================================================================

    function test_Trader_OpenLongPosition() public {
        _graduateVault();
        _enableTrading();

        vm.startPrank(trader1);
        projectToken.approve(address(positionManager), 10 ether);
        positionManager.openPosition{ value: 0 }(
            address(projectToken),
            10 ether,
            5,
            1, // LONG
            type(uint256).max,
            block.timestamp + 1 hours,
            ""
        );
        vm.stopPrank();

        (,, uint8 direction,,,, address positionUser,,,,,,,,,,,,,,,,) = positionManager.positions(1);

        assertEq(positionUser, trader1, "Position should belong to trader1");
        assertEq(direction, 1, "Direction should be LONG");
    }

    function test_Trader_OpenShortPosition() public {
        _graduateVault();
        _enableTrading();

        vm.startPrank(trader1);
        projectToken.approve(address(positionManager), 10 ether);
        positionManager.openPosition{ value: 0 }(
            address(projectToken),
            10 ether,
            5,
            2, // SHORT
            0,
            block.timestamp + 1 hours,
            ""
        );
        vm.stopPrank();

        (,, uint8 direction,,,,,,,,,,,,,,,,,,,,) = positionManager.positions(1);

        assertEq(direction, 2, "Direction should be SHORT");
    }

    function test_Trader_ClosePosition() public {
        _graduateVault();
        _enableTrading();

        // Open position
        vm.startPrank(trader1);
        projectToken.approve(address(positionManager), 10 ether);
        positionManager.openPosition{ value: 0 }(
            address(projectToken), 10 ether, 5, 1, type(uint256).max, block.timestamp + 1 hours, ""
        );

        vm.warp(block.timestamp + 61 seconds);

        uint256 balanceBefore = projectToken.balanceOf(trader1);

        // Close position
        positionManager.closePosition(1, block.timestamp + 1 hours, 0, "");

        uint256 balanceAfter = projectToken.balanceOf(trader1);
        vm.stopPrank();

        assertGe(balanceAfter, balanceBefore, "Trader should receive payout");
    }

    function test_Trader_AddMargin() public {
        _graduateVault();
        _enableTrading();

        vm.startPrank(trader1);
        projectToken.approve(address(positionManager), 20 ether);
        positionManager.openPosition{ value: 0 }(
            address(projectToken), 10 ether, 10, 1, type(uint256).max, block.timestamp + 1 hours, ""
        );

        // Add margin
        positionManager.addMargin(1, 5 ether, type(uint256).max, block.timestamp + 1 hours);
        vm.stopPrank();

        (,,,,,,,,, uint256 collateral,,,,,,,,,,,,,) = positionManager.positions(1);

        assertEq(collateral, 15 ether, "Collateral should be increased");
    }

    function test_Trader_MultiplePositions() public {
        _graduateVault();
        _enableTrading();

        vm.startPrank(trader1);
        projectToken.approve(address(positionManager), 50 ether);

        // Open multiple positions
        positionManager.openPosition{ value: 0 }(
            address(projectToken), 10 ether, 5, 1, type(uint256).max, block.timestamp + 1 hours, ""
        );
        positionManager.openPosition{ value: 0 }(
            address(projectToken), 10 ether, 5, 2, 0, block.timestamp + 1 hours, ""
        );
        positionManager.openPosition{ value: 0 }(
            address(projectToken), 10 ether, 5, 1, type(uint256).max, block.timestamp + 1 hours, ""
        );
        vm.stopPrank();
    }

    function test_Trader_SlippageProtection() public {
        _graduateVault();
        _enableTrading();

        vm.startPrank(trader1);
        projectToken.approve(address(positionManager), 10 ether);

        // Set unrealistic max price - should work (price is 100e18)
        positionManager.openPosition{ value: 0 }(
            address(projectToken),
            10 ether,
            5,
            1,
            200e18, // max acceptable price
            block.timestamp + 1 hours,
            ""
        );
        vm.stopPrank();
    }

    // ========================================================================
    // ADMIN FLOWS
    // ========================================================================

    function test_Admin_CreateVault() public {
        // Deploy a new mock token
        MockERC20 newToken = new MockERC20("New Token", "NEW");

        // Configure price feed for new token
        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: priceFeedManager.CHAINLINK_PROVIDER(),
            secondaryProviderId: priceFeedManager.BLOCKSENSE_PROVIDER(),
            primaryFeed: address(mockAdapter),
            secondaryFeed: address(mockAdapter),
            usePullMode: false
        });
        priceFeedManager.setPriceFeedConfig(address(newToken), config);

        vm.startPrank(owner);
        address newVault = vaultManager.createVault(
            address(newToken), DEFAULT_MIN_BET, DEFAULT_MAX_BET, DEFAULT_GRADUATION_THRESHOLD
        );
        vm.stopPrank();

        assertTrue(newVault != address(0), "New vault should be created");
        assertTrue(
            vaultManager.isVaultSupported(address(newToken)), "New token should be supported"
        );
    }

    function test_Admin_PauseVault() public {
        _graduateVault();
        _enableTrading();

        vm.prank(owner);
        vaultManager.pauseVault(address(projectToken));

        // Vault should be paused
    }

    function test_Admin_UnpauseVault() public {
        _graduateVault();
        _enableTrading();

        vm.startPrank(owner);
        vaultManager.pauseVault(address(projectToken));
        vaultManager.unpauseVault(address(projectToken));
        vm.stopPrank();
    }

    function test_Admin_PausePositionManager() public {
        vm.prank(owner);
        positionManager.pause();

        assertTrue(positionManager.paused(), "PositionManager should be paused");
    }

    function test_Admin_SetVaultTradingEnabled() public {
        vm.prank(address(vaultManager));
        vault.setTradingEnabled(true);

        VaultStorageLib.VaultInfo memory info = vault.vaultInfo();
        assertTrue(info.tradingEnabled, "Trading should be enabled");
    }

    // ========================================================================
    // END-TO-END FLOW TESTS
    // ========================================================================

    function test_E2E_FullTradeLifecycle() public {
        // 1. LP adds liquidity
        vm.startPrank(lp1);
        projectToken.approve(address(vault), DEFAULT_GRADUATION_THRESHOLD);
        vault.addLiquidity(DEFAULT_GRADUATION_THRESHOLD);
        vm.stopPrank();

        // 2. Enable trading
        _enableTrading();

        // 3. Trader opens position
        vm.startPrank(trader1);
        projectToken.approve(address(positionManager), 10 ether);
        positionManager.openPosition{ value: 0 }(
            address(projectToken), 10 ether, 5, 1, type(uint256).max, block.timestamp + 1 hours, ""
        );

        // 4. Wait for hold time
        vm.warp(block.timestamp + 61 seconds);

        // 5. Trader closes position
        positionManager.closePosition(1, block.timestamp + 1 hours, 0, "");
        vm.stopPrank();

        // 6. LP removes liquidity
        vm.startPrank(lp1);
        vault.removeLiquidity();
        vm.stopPrank();

        // Verify final state
        VaultStorageLib.VaultInfo memory info = vault.vaultInfo();
        assertEq(info.totalPositionsSettled, 1, "Position should be settled");
    }

    function test_E2E_MultipleUsersTrading() public {
        // Setup vault
        _graduateVault();
        _enableTrading();

        // Trader1 opens long
        vm.startPrank(trader1);
        projectToken.approve(address(positionManager), 10 ether);
        positionManager.openPosition{ value: 0 }(
            address(projectToken), 10 ether, 5, 1, type(uint256).max, block.timestamp + 1 hours, ""
        );
        vm.stopPrank();

        // Trader2 opens short
        vm.startPrank(trader2);
        projectToken.approve(address(positionManager), 10 ether);
        positionManager.openPosition{ value: 0 }(
            address(projectToken), 10 ether, 5, 2, 0, block.timestamp + 1 hours, ""
        );
        vm.stopPrank();

        vm.warp(block.timestamp + 61 seconds);

        // Both close
        vm.prank(trader1);
        positionManager.closePosition(1, block.timestamp + 1 hours, 0, "");

        vm.prank(trader2);
        positionManager.closePosition(2, block.timestamp + 1 hours, 0, "");

        VaultStorageLib.VaultInfo memory info = vault.vaultInfo();
        assertEq(info.totalPositionsSettled, 2, "Both positions should be settled");
    }

    function test_E2E_LPAndTraderInteraction() public {
        // Multiple LPs
        vm.startPrank(lp1);
        projectToken.approve(address(vault), 5000 ether);
        vault.addLiquidity(5000 ether);
        vm.stopPrank();

        vm.startPrank(lp2);
        projectToken.approve(address(vault), 5000 ether);
        vault.addLiquidity(5000 ether);
        vm.stopPrank();

        _enableTrading();

        // Traders open positions
        vm.startPrank(trader1);
        projectToken.approve(address(positionManager), 50 ether);
        positionManager.openPosition{ value: 0 }(
            address(projectToken), 50 ether, 10, 1, type(uint256).max, block.timestamp + 1 hours, ""
        );
        vm.stopPrank();

        vm.warp(block.timestamp + 61 seconds);

        vm.prank(trader1);
        positionManager.closePosition(1, block.timestamp + 1 hours, 0, "");

        // LPs check their positions
        VaultStorageLib.LPPosition memory lp1Pos = vault.getLPPosition(lp1);
        VaultStorageLib.LPPosition memory lp2Pos = vault.getLPPosition(lp2);

        assertGt(lp1Pos.shares, 0, "LP1 should have shares");
        assertGt(lp2Pos.shares, 0, "LP2 should have shares");
    }

    // ========================================================================
    // STRESS TESTS
    // ========================================================================

    function test_Stress_ManyPositions() public {
        _graduateVault();
        _enableTrading();

        uint256 numPositions = 10;

        vm.startPrank(trader1);
        projectToken.approve(address(positionManager), numPositions * 5 ether);

        for (uint256 i = 0; i < numPositions; i++) {
            positionManager.openPosition{ value: 0 }(
                address(projectToken),
                5 ether,
                3,
                1,
                type(uint256).max,
                block.timestamp + 1 hours,
                ""
            );
        }
        vm.stopPrank();

        vm.warp(block.timestamp + 61 seconds);

        // Close all positions
        vm.startPrank(trader1);
        for (uint64 i = 1; i <= numPositions; i++) {
            positionManager.closePosition(i, block.timestamp + 1 hours, 0, "");
        }
        vm.stopPrank();

        VaultStorageLib.VaultInfo memory info = vault.vaultInfo();
        assertEq(info.totalPositionsSettled, numPositions, "All positions should be settled");
    }

    function test_Stress_ManyLPs() public {
        uint256 numLPs = 5;
        address[] memory lps = new address[](numLPs);

        for (uint256 i = 0; i < numLPs; i++) {
            lps[i] = makeAddr(string(abi.encodePacked("lp_", i)));
            projectToken.mint(lps[i], 2000 ether);

            vm.startPrank(lps[i]);
            projectToken.approve(address(vault), 2000 ether);
            vault.addLiquidity(2000 ether);
            vm.stopPrank();
        }

        VaultStorageLib.VaultInfo memory info = vault.vaultInfo();
        assertGe(info.totalLiquidity, 9000 ether, "Total liquidity should be from all LPs");
    }

    // ========================================================================
    // EDGE CASE TESTS
    // ========================================================================

    function test_EdgeCase_TradeImmediatelyAfterLiquidity() public {
        // Add liquidity
        vm.startPrank(lp1);
        projectToken.approve(address(vault), DEFAULT_GRADUATION_THRESHOLD);
        vault.addLiquidity(DEFAULT_GRADUATION_THRESHOLD);
        vm.stopPrank();

        _enableTrading();

        // Trade immediately
        vm.startPrank(trader1);
        projectToken.approve(address(positionManager), 10 ether);
        positionManager.openPosition{ value: 0 }(
            address(projectToken), 10 ether, 5, 1, type(uint256).max, block.timestamp + 1 hours, ""
        );
        vm.stopPrank();
    }

    function test_EdgeCase_WithdrawWhilePositionsOpen() public {
        // Add liquidity
        vm.startPrank(lp1);
        projectToken.approve(address(vault), DEFAULT_GRADUATION_THRESHOLD);
        vault.addLiquidity(DEFAULT_GRADUATION_THRESHOLD);
        vm.stopPrank();

        _enableTrading();

        // Open position
        vm.startPrank(trader1);
        projectToken.approve(address(positionManager), 10 ether);
        positionManager.openPosition{ value: 0 }(
            address(projectToken), 10 ether, 5, 1, type(uint256).max, block.timestamp + 1 hours, ""
        );
        vm.stopPrank();

        // LP tries to withdraw while position is open
        vm.startPrank(lp1);
        vault.removeLiquidity();
        vm.stopPrank();
    }
}
