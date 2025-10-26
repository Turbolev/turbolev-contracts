// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title PositionLib
 * @notice Library containing constants and helper functions for position management
 * @dev Migrated from position_constants.move and position_state_manager.move
 *
 * v3.0: Synthetic Leverage Support
 * - Leverage 1x-100x
 * - Maintenance Margin Ratio: 6.25% (configurable)
 * - Tiered liquidation fees: 2-5% based on leverage
 * - Native token (MON) only: tokenAddress = address(0)
 */
library PositionLib {
    // ========================================================================
    // POSITION STATE CONSTANTS
    // ========================================================================

    uint8 public constant POSITION_STATE_OPEN = 1;
    uint8 public constant POSITION_STATE_CLOSING = 2;
    uint8 public constant POSITION_STATE_CLOSED = 3;
    uint8 public constant POSITION_STATE_CANCELLED = 4;
    uint8 public constant POSITION_STATE_WON = 5;
    uint8 public constant POSITION_STATE_LOST = 6;
    uint8 public constant POSITION_STATE_LIQUIDATED = 7;

    // ========================================================================
    // BET DIRECTION CONSTANTS
    // ========================================================================

    uint8 public constant BET_DIRECTION_LONG = 1; // Long (predict price increase)
    uint8 public constant BET_DIRECTION_SHORT = 2; // Short (predict price decrease)

    // Legacy aliases for backward compatibility
    uint8 public constant BET_DIRECTION_UP = 1; // Alias for LONG
    uint8 public constant BET_DIRECTION_DOWN = 2; // Alias for SHORT

    // ========================================================================
    // LEVERAGE & LIQUIDATION CONSTANTS
    // ========================================================================

    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MIN_LEVERAGE = 1;
    uint256 public constant MAX_LEVERAGE = 100;

    // Maintenance Margin Ratio: 20% (Phase 5 update)
    // This means liquidation happens when loss = (100% - 20%) = 80% of collateral
    uint256 public constant DEFAULT_MAINTENANCE_MARGIN_RATIO = 2000; // 20% in bps

    // Flat Liquidation Fee (in basis points)
    uint256 public constant LIQUIDATION_FEE_BPS = 200; // Flat 2% for all leverage levels

    // HIGH FIX: Flash Loan Protection
    // Minimum time a position must be held before closing (60 seconds = 1 minute)
    uint256 public constant MIN_POSITION_HOLD_TIME = 60; // 60 seconds

    // REFACTOR: Max Profit Cap Multiplier (Phase 3)
    // Maximum profit is capped at 3× the collateral amount
    uint256 public constant MAX_PROFIT_CAP_MULTIPLIER = 3;

    // REFACTOR: Max Close Requests
    // Maximum number of times a position can request to close before auto-cancellation
    uint8 public constant MAX_CLOSE_REQUESTS = 3;

    // ========================================================================
    // POSITION DATA STRUCTURE
    // ========================================================================

    struct Position {
        uint64 positionId;
        address user;
        address tokenAddress; // Collateral token address: address(0) for native token, or ERC20 token address
        bytes32 priceFeedId; // Pyth price feed ID of the asset being bet on
        uint256 amount; // Collateral amount in token's decimals (includes added margin)
        uint8 leverage; // Leverage multiplier (1-100)
        uint8 direction; // BET_DIRECTION_UP or BET_DIRECTION_DOWN
        uint8 state; // POSITION_STATE_*
        uint256 openPrice; // Open price (from backend)
        uint256 closePrice; // Close price (from backend)
        uint256 liquidationPrice; // Liquidation price (calculated based on leverage)
        uint256 positionSize; // Position size = amount × leverage (for display)
        uint256 maxProfitCap; // Max profit allowed for this position (Phase 3)
        uint256 createdTimestamp;
        uint256 lastModifiedTimestamp;
        uint256 minCloseTime; // HIGH FIX: Earliest time position can be closed (flash loan protection)
        uint8 closeRequestCount;
        uint8 maxCloseRequests;
        uint256 initialMargin; // HIGH-04 FIX: Original collateral amount (before any add margin)
        uint256 addedMargin; // HIGH-04 FIX: Total margin added after position open
    }

    // ========================================================================
    // LIQUIDATION CALCULATION (Synthetic Leverage)
    // ========================================================================

    /**
     * @notice Calculate liquidation price with leverage and maintenance margin ratio
     * @dev Synthetic Leverage Formula:
     *      Liquidation happens when unrealized loss = (100% - maintenanceMarginRatio) of collateral
     *
     *      For LONG (predict price increase):
     *      Loss per point = collateral × leverage / openPrice
     *      Loss at liq = collateral × (1 - maintenanceMarginRatio/10000)
     *      Price drop = Loss at liq / Loss per point
     *      Liq Price = openPrice - price drop
     *
     *      Simplified:
     *      Liq Price = openPrice × (1 - (1 - MMR/10000) / leverage)
     *
     *      For SHORT (predict price decrease):
     *      Liq Price = openPrice × (1 + (1 - MMR/10000) / leverage)
     *
     * @param openPrice Entry price
     * @param direction BET_DIRECTION_LONG or BET_DIRECTION_SHORT
     * @param leverage Leverage multiplier (1-100)
     * @param maintenanceMarginRatio Maintenance margin in bps (e.g., 625 = 6.25%)
     * @return liquidationPrice Price at which position gets liquidated
     * @dev CRITICAL FIX: Added overflow/underflow protection
     */
    function calculateLiquidationPrice(
        uint256 openPrice,
        uint8 direction,
        uint8 leverage,
        uint256 maintenanceMarginRatio
    ) internal pure returns (uint256) {
        // CRITICAL FIX: Comprehensive input validation
        require(openPrice > 0, "Invalid open price: must be > 0");
        require(
            leverage >= MIN_LEVERAGE && leverage <= MAX_LEVERAGE,
            "Invalid leverage: must be 1-100"
        );
        require(
            maintenanceMarginRatio < BASIS_POINTS,
            "Invalid MMR: must be < 10000"
        );
        require(
            direction == BET_DIRECTION_LONG || direction == BET_DIRECTION_SHORT,
            "Invalid direction"
        );

        // Calculate liquidation threshold as % of collateral
        // If MMR = 20%, then liquidation at 80% loss
        uint256 liquidationThreshold = BASIS_POINTS - maintenanceMarginRatio;

        // Calculate price deviation percentage
        // priceDeviationBps = liquidationThreshold / leverage
        uint256 priceDeviationBps = liquidationThreshold / leverage;

        if (direction == BET_DIRECTION_LONG) {
            // LONG: liquidation when price decreases

            // Calculate price decrease with overflow check
            uint256 priceDecrease = (openPrice * priceDeviationBps) /
                BASIS_POINTS;

            // CRITICAL FIX: Check for underflow
            require(
                priceDecrease < openPrice,
                "Liquidation price calculation underflow: decrease >= openPrice"
            );

            uint256 liquidationPrice = openPrice - priceDecrease;

            // Additional sanity check: liquidation price should be reasonable
            require(
                liquidationPrice > 0,
                "Invalid liquidation price: must be > 0"
            );

            return liquidationPrice;
        } else {
            // SHORT: liquidation when price rises

            // Calculate price increase with overflow check
            uint256 priceIncrease = (openPrice * priceDeviationBps) /
                BASIS_POINTS;

            // CRITICAL FIX: Check for overflow
            require(
                priceIncrease <= type(uint256).max - openPrice,
                "Liquidation price calculation overflow"
            );

            uint256 liquidationPrice = openPrice + priceIncrease;

            // Additional sanity check
            require(
                liquidationPrice > openPrice,
                "Invalid liquidation price: must be > openPrice for SHORT"
            );

            return liquidationPrice;
        }
    }

    /**
     * @notice Check if position is liquidated
     */
    function isLiquidated(
        Position memory position,
        uint256 currentPrice
    ) internal pure returns (bool) {
        if (position.direction == BET_DIRECTION_LONG) {
            // LONG: liquidated when currentPrice <= liquidationPrice
            return currentPrice <= position.liquidationPrice;
        } else {
            // SHORT: liquidated when currentPrice >= liquidationPrice
            return currentPrice >= position.liquidationPrice;
        }
    }

    /**
     * @notice Calculate liquidation fee (flat rate for all leverage levels)
     * @param leverage Leverage multiplier (unused, kept for interface compatibility)
     * @return fee Fee in basis points (always 2%)
     */
    function calculateLiquidationFee(
        uint8 leverage
    ) internal pure returns (uint256) {
        // Simplified to flat 2% fee regardless of leverage
        // Parameter kept for backward compatibility
        leverage; // Silence unused variable warning
        return LIQUIDATION_FEE_BPS; // Always 2%
    }

    /**
     * @notice Calculate unrealized P&L with leverage (Synthetic Leverage)
     * @dev P&L Formula:
     *      Price change % = (currentPrice - openPrice) / openPrice
     *      P&L = collateral × leverage × priceChange%
     *
     *      For LONG: positive if price goes up
     *      For SHORT: positive if price goes down
     *
     * @param position Position data
     * @param currentPrice Current market price
     * @return pnl Profit/Loss (positive = profit, negative = loss)
     * @return pnlPercentage P&L as percentage of collateral in bps
     * @dev CRITICAL FIX: Added overflow protection for large price moves
     */
    function calculateUnrealizedPnL(
        Position memory position,
        uint256 currentPrice
    ) internal pure returns (int256 pnl, int256 pnlPercentage) {
        // CRITICAL FIX: Validate inputs
        require(position.openPrice > 0, "Invalid open price");
        require(currentPrice > 0, "Invalid current price");
        require(position.amount > 0, "Invalid position amount");

        // Calculate price change percentage (in bps)
        int256 priceChangeBps;

        if (currentPrice > position.openPrice) {
            // Price increased
            uint256 priceIncrease = currentPrice - position.openPrice;

            // CRITICAL FIX: Check for overflow before multiplication
            require(
                priceIncrease <= type(uint256).max / BASIS_POINTS,
                "Price change too large: overflow risk"
            );

            priceChangeBps = int256(
                (priceIncrease * BASIS_POINTS) / position.openPrice
            );
        } else if (currentPrice < position.openPrice) {
            // Price decreased
            uint256 priceDecrease = position.openPrice - currentPrice;

            // CRITICAL FIX: Check for overflow before multiplication
            require(
                priceDecrease <= type(uint256).max / BASIS_POINTS,
                "Price change too large: overflow risk"
            );

            priceChangeBps = -int256(
                (priceDecrease * BASIS_POINTS) / position.openPrice
            );
        } else {
            // No price change
            return (0, 0);
        }

        // Apply leverage
        // CRITICAL FIX: Check for overflow when applying leverage
        int256 leverageInt = int256(uint256(position.leverage));

        // Check if multiplication will overflow
        if (priceChangeBps > 0) {
            require(
                uint256(priceChangeBps) <=
                    type(uint256).max / uint256(leverageInt),
                "Leverage multiplication overflow"
            );
        } else if (priceChangeBps < 0) {
            require(
                uint256(-priceChangeBps) <=
                    type(uint256).max / uint256(leverageInt),
                "Leverage multiplication overflow"
            );
        }

        int256 leveragedPnLPercentage = priceChangeBps * leverageInt;

        // Reverse sign for SHORT positions
        if (position.direction == BET_DIRECTION_SHORT) {
            leveragedPnLPercentage = -leveragedPnLPercentage;
        }

        // Calculate absolute P&L
        // CRITICAL FIX: Check for overflow before final calculation
        int256 amountInt = int256(position.amount);

        if (leveragedPnLPercentage > 0) {
            require(
                uint256(leveragedPnLPercentage) <=
                    type(uint256).max / position.amount,
                "PnL calculation overflow"
            );
        } else if (leveragedPnLPercentage < 0) {
            require(
                uint256(-leveragedPnLPercentage) <=
                    type(uint256).max / position.amount,
                "PnL calculation overflow"
            );
        }

        int256 absolutePnL = (amountInt * leveragedPnLPercentage) /
            int256(BASIS_POINTS);

        return (absolutePnL, leveragedPnLPercentage);
    }
}
