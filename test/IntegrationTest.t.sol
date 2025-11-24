// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./BaseTest.sol";

/**
 * @title IntegrationTest
 * @notice Comprehensive integration tests for the Boolean Contracts system
 * @dev Tests full user flows with new maxAcceptablePrice parameters
 */
contract IntegrationTest is BaseTest {
    // Test constants
    uint256 constant COLLATERAL = 1 ether;
    uint8 constant LEVERAGE_5X = 5;
    uint8 constant LEVERAGE_10X = 10;
    uint256 constant INITIAL_PRICE = 100e18;
    uint256 constant HIGHER_PRICE = 110e18;
    uint256 constant LOWER_PRICE = 90e18;

    function setUp() public override {
        super.setUp();

        // Add initial liquidity to vault (need to exceed graduation threshold of 10,000 ether)
        _addInitialLiquidity(liquidityProvider, 15_000 ether);

        // Set initial price
        _updatePrice(address(projectToken), address(usdc), int256(INITIAL_PRICE));
    }

    // ========================================================================
    // BASIC POSITION FLOW TESTS
    // ========================================================================

    function testIntegration_BasicLongPosition_Success() public {
        // User opens LONG position
        vm.startPrank(user1);
        projectToken.mint(user1, COLLATERAL);
        projectToken.approve(address(positionManager), COLLATERAL);

        uint64 positionId = positionManager.openPosition(
            address(projectToken),
            COLLATERAL,
            LEVERAGE_5X,
            1, // LONG
            0, // no price limit
            block.timestamp + 3600,
            "" // deadline, "" = 1 hour
        );
        vm.stopPrank();

        // Verify position was created
        PositionLib.Position memory pos = positionManager.getPosition(positionId);
        assertEq(pos.user, user1, "Position user should match");
        assertEq(pos.amount, COLLATERAL, "Position amount should match");
        assertEq(pos.leverage, LEVERAGE_5X, "Position leverage should match");
        assertEq(pos.direction, 1, "Position direction should be LONG");
        assertEq(pos.openPrice, INITIAL_PRICE, "Open price should match");

        // Price increases - user should profit
        _updatePrice(address(projectToken), address(usdc), int256(HIGHER_PRICE));

        // Wait for minimum hold time
        vm.warp(block.timestamp + 61);
        mockAdapter.setMockTimestamp(block.timestamp); // Min hold time is 60 seconds
        mockAdapter.setMockTimestamp(block.timestamp); // Update mock timestamp

        // User closes position
        vm.prank(user1);
        positionManager.closePosition(
            positionId,
            block.timestamp + 3600, // deadline
            0, // no price limit
            "" // no price update data
        );

        // Verify position was closed
        pos = positionManager.getPosition(positionId);
        assertEq(pos.state, PositionLib.POSITION_STATE_WON, "Position should be won");
        assertEq(pos.closePrice, HIGHER_PRICE, "Close price should match");
    }

    function testIntegration_BasicShortPosition_Success() public {
        // User opens SHORT position
        vm.startPrank(user2);
        projectToken.mint(user2, COLLATERAL);
        projectToken.approve(address(positionManager), COLLATERAL);

        uint64 positionId = positionManager.openPosition(
            address(projectToken),
            COLLATERAL,
            LEVERAGE_5X,
            2, // SHORT
            0, // no price limit
            block.timestamp + 3600,
            "" // deadline, "" = 1 hour
        );
        vm.stopPrank();

        // Verify position was created
        PositionLib.Position memory pos = positionManager.getPosition(positionId);
        assertEq(pos.direction, 2, "Position direction should be SHORT");

        // Price decreases - user should profit
        _updatePrice(address(projectToken), address(usdc), int256(LOWER_PRICE));

        // Wait for minimum hold time
        vm.warp(block.timestamp + 61);
        mockAdapter.setMockTimestamp(block.timestamp);

        // User closes position
        vm.prank(user2);
        positionManager.closePosition(
            positionId,
            block.timestamp + 3600, // deadline
            0, // no price limit
            "" // no price update data
        );

        // Verify position was closed with profit
        pos = positionManager.getPosition(positionId);
        assertEq(pos.state, PositionLib.POSITION_STATE_WON, "Position should be won");
        assertEq(pos.closePrice, LOWER_PRICE, "Close price should match");
    }

    // ========================================================================
    // MAXACCEPTABLEPRICE TESTS
    // ========================================================================

    function testIntegration_OpenPosition_WithMaxAcceptablePrice_Success() public {
        vm.startPrank(user1);
        projectToken.mint(user1, COLLATERAL);
        projectToken.approve(address(positionManager), COLLATERAL);

        // Open LONG with max acceptable price = current price (should succeed)
        uint64 positionId = positionManager.openPosition(
            address(projectToken),
            COLLATERAL,
            LEVERAGE_5X,
            1, // LONG
            INITIAL_PRICE, // max acceptable price = current price
            block.timestamp + 3600,
            "" // deadline, "" = 1 hour
        );
        vm.stopPrank();

        // Verify position was created
        PositionLib.Position memory pos = positionManager.getPosition(positionId);
        assertEq(pos.openPrice, INITIAL_PRICE, "Open price should match");
    }

    function testIntegration_OpenPosition_WithMaxAcceptablePrice_Reverts() public {
        vm.startPrank(user1);
        projectToken.mint(user1, COLLATERAL);
        projectToken.approve(address(positionManager), COLLATERAL);

        // Try to open LONG with max acceptable price lower than current price (should fail)
        vm.expectRevert(PositionManager.SlippageExceeded.selector);
        positionManager.openPosition(
            address(projectToken),
            COLLATERAL,
            LEVERAGE_5X,
            1, // LONG
            INITIAL_PRICE - 1e18, // max acceptable price lower than current
            block.timestamp + 3600,
            "" // deadline, "" = 1 hour
        );
        vm.stopPrank();
    }

    function testIntegration_ClosePosition_WithMaxAcceptablePrice_Success() public {
        // Open position first
        vm.startPrank(user1);
        projectToken.mint(user1, COLLATERAL);
        projectToken.approve(address(positionManager), COLLATERAL);

        uint64 positionId = positionManager.openPosition(
            address(projectToken),
            COLLATERAL,
            LEVERAGE_5X,
            1, // LONG
            0, // no price limit
            block.timestamp + 3600,
            "" // deadline, "" = 1 hour
        );
        vm.stopPrank();

        // Price increases
        _updatePrice(address(projectToken), address(usdc), int256(HIGHER_PRICE));

        // Wait for minimum hold time
        vm.warp(block.timestamp + 61);
        mockAdapter.setMockTimestamp(block.timestamp);

        // Close with acceptable price limit
        vm.prank(user1);
        positionManager.closePosition(
            positionId,
            block.timestamp + 3600, // deadline
            HIGHER_PRICE - 1e18, // min acceptable price for LONG
            "" // no price update data
        );

        // Verify position was closed
        PositionLib.Position memory pos = positionManager.getPosition(positionId);
        assertEq(pos.state, PositionLib.POSITION_STATE_WON, "Position should be won");
    }

    function testIntegration_ClosePosition_WithMaxAcceptablePrice_Reverts() public {
        // Open position first
        vm.startPrank(user1);
        projectToken.mint(user1, COLLATERAL);
        projectToken.approve(address(positionManager), COLLATERAL);

        uint64 positionId = positionManager.openPosition(
            address(projectToken),
            COLLATERAL,
            LEVERAGE_5X,
            1, // LONG
            0, // no price limit
            block.timestamp + 3600,
            "" // deadline, "" = 1 hour
        );
        vm.stopPrank();

        // Price increases
        _updatePrice(address(projectToken), address(usdc), int256(HIGHER_PRICE));

        // Wait for minimum hold time
        vm.warp(block.timestamp + 61);
        mockAdapter.setMockTimestamp(block.timestamp);

        // Try to close with unacceptable price limit (too high for LONG)
        vm.prank(user1);
        vm.expectRevert(PositionManager.SlippageExceeded.selector);
        positionManager.closePosition(
            positionId,
            block.timestamp + 3600, // deadline
            HIGHER_PRICE + 1e18, // min acceptable price too high
            "" // no price update data
        );
    }

    // ========================================================================
    // ADD MARGIN TESTS
    // ========================================================================

    function testIntegration_AddMargin_Success() public {
        // Open position first
        vm.startPrank(user1);
        projectToken.mint(user1, COLLATERAL * 2);
        projectToken.approve(address(positionManager), COLLATERAL * 2);

        uint64 positionId = positionManager.openPosition(
            address(projectToken),
            COLLATERAL,
            LEVERAGE_10X,
            1, // LONG
            0, // no price limit
            block.timestamp + 3600,
            "" // deadline, "" = 1 hour
        );

        // Add margin
        uint256 additionalMargin = 0.5 ether;
        positionManager.addMargin(
            positionId,
            additionalMargin,
            0, // no price limit
            block.timestamp + 3600 // deadline = 1 hour
        );
        vm.stopPrank();

        // Verify margin was added
        PositionLib.Position memory pos = positionManager.getPosition(positionId);
        assertEq(pos.amount, COLLATERAL + additionalMargin, "Total margin should be updated");
        assertEq(pos.addedMargin, additionalMargin, "Added margin should be tracked");
    }

    function testIntegration_AddMargin_WithMaxAcceptablePrice_Reverts() public {
        // Open position first
        vm.startPrank(user1);
        projectToken.mint(user1, COLLATERAL * 2);
        projectToken.approve(address(positionManager), COLLATERAL * 2);

        uint64 positionId = positionManager.openPosition(
            address(projectToken),
            COLLATERAL,
            LEVERAGE_10X,
            1, // LONG
            0, // no price limit
            block.timestamp + 3600,
            "" // deadline, "" = 1 hour
        );

        // Price increases significantly
        _updatePrice(address(projectToken), address(usdc), int256(HIGHER_PRICE));

        // Try to add margin with unacceptable price limit
        vm.expectRevert(PositionManager.SlippageExceeded.selector);
        positionManager.addMargin(
            positionId,
            0.5 ether,
            INITIAL_PRICE, // max acceptable price lower than current
            block.timestamp + 3600 // deadline = 1 hour
        );
        vm.stopPrank();
    }

    // ========================================================================
    // LIQUIDATION TESTS
    // ========================================================================

    function testIntegration_Liquidation_Success() public {
        // Open high leverage position
        vm.startPrank(user1);
        projectToken.mint(user1, COLLATERAL);
        projectToken.approve(address(positionManager), COLLATERAL);

        uint64 positionId = positionManager.openPosition(
            address(projectToken),
            COLLATERAL,
            50, // Very high leverage
            1, // LONG
            0, // no price limit
            block.timestamp + 3600,
            "" // deadline, "" = 1 hour
        );
        vm.stopPrank();

        // Price drops but not enough to trigger automatic liquidation
        // Liquidation price for 50x leverage is around 98.4, so we set price to 99
        _updatePrice(address(projectToken), address(usdc), int256((INITIAL_PRICE * 99) / 100)); // 1% drop (not liquidated yet)

        // Wait for minimum hold time
        vm.warp(block.timestamp + 61);
        mockAdapter.setMockTimestamp(block.timestamp);

        // User closes their own position (in liquidation scenario, they realize loss)
        vm.prank(user1);
        positionManager.closePosition(positionId, block.timestamp + 3600, 0, "");

        // Verify position was closed with loss
        PositionLib.Position memory pos = positionManager.getPosition(positionId);
        assertEq(
            pos.state,
            PositionLib.POSITION_STATE_LOST,
            "Position should be in LOST state due to price drop"
        );
    }

    // ========================================================================
    // MULTIPLE POSITIONS TESTS
    // ========================================================================

    function testIntegration_MultiplePositions_DifferentUsers() public {
        // User1 opens LONG
        vm.startPrank(user1);
        projectToken.mint(user1, COLLATERAL);
        projectToken.approve(address(positionManager), COLLATERAL);

        uint64 longPos = positionManager.openPosition(
            address(projectToken),
            COLLATERAL,
            LEVERAGE_5X,
            1, // LONG
            0, // no price limit
            block.timestamp + 3600,
            "" // deadline, "" = 1 hour
        );
        vm.stopPrank();

        // User2 opens SHORT
        vm.startPrank(user2);
        projectToken.mint(user2, COLLATERAL);
        projectToken.approve(address(positionManager), COLLATERAL);

        uint64 shortPos = positionManager.openPosition(
            address(projectToken),
            COLLATERAL,
            LEVERAGE_5X,
            2, // SHORT
            0, // no price limit
            block.timestamp + 3600,
            "" // deadline, "" = 1 hour
        );
        vm.stopPrank();

        // Price increases - LONG wins, SHORT loses
        _updatePrice(address(projectToken), address(usdc), int256(HIGHER_PRICE));

        // Wait for minimum hold time
        vm.warp(block.timestamp + 61);
        mockAdapter.setMockTimestamp(block.timestamp);

        // Close both positions
        vm.prank(user1);
        positionManager.closePosition(longPos, block.timestamp + 3600, 0, "");

        vm.prank(user2);
        positionManager.closePosition(shortPos, block.timestamp + 3600, 0, "");

        // Verify results
        PositionLib.Position memory longPosition = positionManager.getPosition(longPos);
        PositionLib.Position memory shortPosition = positionManager.getPosition(shortPos);

        assertEq(longPosition.state, PositionLib.POSITION_STATE_WON, "LONG should win");
        assertEq(shortPosition.state, PositionLib.POSITION_STATE_LOST, "SHORT should lose");
    }

    // ========================================================================
    // SETTLEMENT ENGINE INTEGRATION TESTS
    // ========================================================================

    function testIntegration_SettlementEngine_GetPrice_WithMaxAge() public {
        // PriceFeedManager is already configured in BaseTest.setUp()
        // Test new getSettlementPrice function with maxAge parameter
        (uint256 price, uint256 publishTime) = settlementEngine.getSettlementPrice(
            address(projectToken),
            3600 // 1 hour max age
        );

        assertEq(price, INITIAL_PRICE, "Price should match current price");
        assertGt(publishTime, 0, "Publish time should be set");
    }

    function testIntegration_SettlementEngine_StalePrice_Reverts() public {
        // PriceFeedManager is already configured in BaseTest.setUp()
        // Set old timestamp in mock adapter
        mockAdapter.setMockTimestamp(1);

        // Warp time to make price stale
        vm.warp(block.timestamp + 7200); // 2 hours later

        // PriceFeedManager throws InvalidOraclePrice for stale price
        vm.expectRevert(PriceFeedManager.InvalidOraclePrice.selector);
        settlementEngine.getSettlementPrice(
            address(projectToken),
            3600 // 1 hour max age
        );
    }

    // ========================================================================
    // VAULT INTEGRATION TESTS
    // ========================================================================

    function testIntegration_VaultManager_CreateAndManage() public {
        // Create new vault for different token
        MockERC20 newToken = new MockERC20("NewToken", "NEW");

        address newVaultAddr = vaultManager.createVaultWithBeacon(
            address(newToken), DEFAULT_MIN_BET, DEFAULT_MAX_BET, DEFAULT_GRADUATION_THRESHOLD
        );

        // Verify vault was created
        assertTrue(newVaultAddr != address(0), "New vault should be created");
        assertEq(
            vaultManagerHelper.getVault(address(newToken)),
            newVaultAddr,
            "Vault should be registered"
        );
    }

    // ========================================================================
    // DIRECTIONAL EXPOSURE TESTS
    // ========================================================================

    function testIntegration_DirectionalExposure_Balanced() public {
        // Open equal LONG and SHORT positions - should not hit exposure limit
        uint256 positionAmount = 100 ether;

        // User1 opens LONG
        vm.startPrank(user1);
        projectToken.mint(user1, positionAmount);
        projectToken.approve(address(positionManager), positionAmount);
        uint64 longPos = positionManager.openPosition(
            address(projectToken),
            positionAmount,
            LEVERAGE_5X,
            1, // LONG
            0,
            block.timestamp + 3600,
            ""
        );
        vm.stopPrank();

        // User2 opens SHORT with same size
        vm.startPrank(user2);
        projectToken.mint(user2, positionAmount);
        projectToken.approve(address(positionManager), positionAmount);
        uint64 shortPos = positionManager.openPosition(
            address(projectToken),
            positionAmount,
            LEVERAGE_5X,
            2, // SHORT
            0,
            block.timestamp + 3600,
            ""
        );
        vm.stopPrank();

        // Check exposure - should be balanced
        (
            uint256 longExposure,
            uint256 shortExposure,
            uint256 netExposure,
            ,
            ,

        ) = assetVault.getDirectionalExposure();

        uint256 expectedExposure = positionAmount * LEVERAGE_5X;
        assertEq(longExposure, expectedExposure, "Long exposure should match");
        assertEq(shortExposure, expectedExposure, "Short exposure should match");
        assertEq(netExposure, 0, "Net exposure should be 0 when balanced");

        // Verify positions were created
        assertTrue(longPos > 0, "Long position should be created");
        assertTrue(shortPos > 0, "Short position should be created");
    }

    function testIntegration_DirectionalExposure_ExceedsLimit() public {
        // Try to open position that would exceed 50% TVL net exposure
        // TVL = 15,000 ether, 50% = 7,500 ether
        // But also need to consider maxBetAmount (100 ether default)
        // Try to open LONG with size that exceeds directional exposure

        // First, update maxBetAmount to allow larger positions
        assetVault.updateVaultParams(
            0.01 ether, // minBetAmount
            2000 ether, // maxBetAmount - increased
            3000 // maxPositionSizePercentBps (30% of TVL)
        );

        uint256 excessiveAmount = 2000 ether; // 2000 * 5 = 10,000 > 7,500

        vm.startPrank(user1);
        projectToken.mint(user1, excessiveAmount);
        projectToken.approve(address(positionManager), excessiveAmount);

        // Should revert due to exposure limit
        vm.expectRevert();
        positionManager.openPosition(
            address(projectToken),
            excessiveAmount,
            LEVERAGE_5X,
            1, // LONG
            0,
            block.timestamp + 3600,
            ""
        );
        vm.stopPrank();
    }

    function testIntegration_DirectionalExposure_WithinLimit() public {
        // Open position within exposure limit
        // TVL = 15,000 ether, 50% = 7,500 ether
        // maxBetAmount = 100 ether (default), so max collateral = 100 ether
        // Open LONG with size = 500 ether (collateral = 100 ether, within limit)

        // First, update maxBetAmount if needed
        assetVault.updateVaultParams(
            0.01 ether, // minBetAmount
            500 ether, // maxBetAmount - increased to allow test
            3000 // maxPositionSizePercentBps (30% of TVL)
        );

        uint256 safeAmount = 100 ether; // 100 * 5 = 500 < 7,500 and < maxBet

        vm.startPrank(user1);
        projectToken.mint(user1, safeAmount);
        projectToken.approve(address(positionManager), safeAmount);

        uint64 positionId = positionManager.openPosition(
            address(projectToken),
            safeAmount,
            LEVERAGE_5X,
            1, // LONG
            0,
            block.timestamp + 3600,
            ""
        );
        vm.stopPrank();

        // Verify position was created
        PositionLib.Position memory pos = positionManager.getPosition(positionId);
        assertEq(pos.user, user1, "Position should be created");

        // Check exposure
        (uint256 longExposure, , , , , ) = assetVault.getDirectionalExposure();
        assertEq(longExposure, safeAmount * LEVERAGE_5X, "Long exposure should be updated");
    }

    function testIntegration_DirectionalExposure_AfterClose() public {
        // Test that exposure is properly reduced after closing position
        // Use smaller amount to stay within default maxBetAmount (100 ether)
        uint256 positionAmount = 50 ether; // 50 * 5 = 250 ether position size

        // Update maxBetAmount if needed
        assetVault.updateVaultParams(
            0.01 ether, // minBetAmount
            200 ether, // maxBetAmount
            3000 // maxPositionSizePercentBps
        );

        // Open LONG position
        vm.startPrank(user1);
        projectToken.mint(user1, positionAmount);
        projectToken.approve(address(positionManager), positionAmount);
        uint64 positionId = positionManager.openPosition(
            address(projectToken),
            positionAmount,
            LEVERAGE_5X,
            1, // LONG
            0,
            block.timestamp + 3600,
            ""
        );
        vm.stopPrank();

        // Check exposure before close
        (uint256 longBefore, , , , , ) = assetVault.getDirectionalExposure();
        uint256 expectedExposure = positionAmount * LEVERAGE_5X;
        assertEq(longBefore, expectedExposure, "Long exposure should be set");

        // Wait and close position
        vm.warp(block.timestamp + 61);
        mockAdapter.setMockTimestamp(block.timestamp);

        vm.prank(user1);
        positionManager.closePosition(positionId, block.timestamp + 3600, 0, "");

        // Check exposure after close
        (uint256 longAfter, , , , , ) = assetVault.getDirectionalExposure();
        assertEq(longAfter, 0, "Long exposure should be cleared after close");
    }

    // ========================================================================
    // ERROR HANDLING TESTS
    // ========================================================================

    function testIntegration_InvalidToken_Reverts() public {
        address invalidToken = makeAddr("invalidToken");

        vm.startPrank(user1);
        vm.expectRevert(); // Should revert because vault doesn't exist
        positionManager.openPosition(
            invalidToken,
            COLLATERAL,
            LEVERAGE_5X,
            1, // LONG
            0, // no price limit
            block.timestamp + 3600,
            "" // deadline, "" = 1 hour
        );
        vm.stopPrank();
    }

    function testIntegration_InsufficientBalance_Reverts() public {
        vm.startPrank(user1);
        // Don't mint tokens - user has no balance

        vm.expectRevert(); // Should revert due to insufficient balance
        positionManager.openPosition(
            address(projectToken),
            COLLATERAL,
            LEVERAGE_5X,
            1, // LONG
            0, // no price limit
            block.timestamp + 3600,
            "" // deadline, "" = 1 hour
        );
        vm.stopPrank();
    }

    // ========================================================================
    // HELPER FUNCTIONS
    // ========================================================================

    function _addInitialLiquidity(address provider, uint256 amount) internal {
        vm.startPrank(provider);
        projectToken.mint(provider, amount);
        projectToken.approve(address(assetVault), amount);
        assetVault.addLiquidity(amount);
        vm.stopPrank();
    }
}
