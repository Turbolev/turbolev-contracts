// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { MathLib } from "../math/MathLib.sol";

/**
 * @title PositionLib
 * @notice Library containing constants and helper functions for position management
 * @dev Migrated from position_constants.move and position_state_manager.move.
 *      Uses MathLib for high-precision P&L calculations.
 */
library PositionLib {
    // ========================================================================
    // ERRORS
    // ========================================================================

    error InvalidOpenPrice();
    error InvalidLeverage();
    error InvalidMaintenanceMarginRatio();
    error InvalidDirection();
    error LiquidationPriceUnderflow();
    error InvalidLiquidationPrice();
    error LiquidationPriceOverflow();
    error InvalidLiquidationPriceForShort();
    error InvalidCurrentPrice();
    error InvalidPositionAmount();
    error PriceChangeTooLarge();
    error LeverageMultiplicationOverflow();
    error PnLCalculationOverflow();
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
    uint8 public constant POSITION_STATE_PENDING_CLOSE = 8;

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

    uint256 public constant MIN_LEVERAGE = 1;
    uint256 public constant MAX_LEVERAGE = 100;

    // Maintenance Margin Ratio: 20%
    // This means liquidation happens when loss = (100% - 20%) = 80% of collateral
    uint256 public constant DEFAULT_MAINTENANCE_MARGIN_RATIO = 2000; // 20% in bps

    // Minimum time a position must be held before closing
    // 30s is sufficient to prevent flash loan attacks (block time ~12s)
    // and allows oracle prices to update (Chainlink heartbeat ~20s)
    uint256 public constant MIN_POSITION_HOLD_TIME = 30; // 30 seconds

    // Maximum profit is capped at 3× the collateral amount
    uint256 public constant MAX_PROFIT_CAP_MULTIPLIER = 3;

    // Maximum number of times a position can request to close before auto-cancellation
    uint8 public constant MAX_CLOSE_REQUESTS = 3;

    // ========================================================================
    // POSITION DATA STRUCTURE
    // ========================================================================

    struct Position {
        uint64 positionId; // 8 bytes
        uint8 leverage; // 1 byte - Leverage multiplier (1-100)
        uint8 direction; // 1 byte - BET_DIRECTION_UP or BET_DIRECTION_DOWN
        uint8 state; // 1 byte - POSITION_STATE_*
        uint8 closeRequestCount; // 1 byte
        uint8 maxCloseRequests; // 1 byte
        address user;
        address projectToken; // Project token address (the asset being bet on)
        address tokenAddress; // Collateral token: address(0) for native, or ERC20
        uint256 amount; // Collateral amount (includes added margin)
        uint256 openPrice; // Open price (from backend)
        uint256 closePrice; // Close price (from backend)
        uint256 liquidationPrice; // Liquidation price (calculated based on leverage)
        uint256 positionSize; // Position size = amount × leverage (for display)
        uint256 maxProfitCap; // Max profit allowed (Phase 3)
        uint256 createdTimestamp;
        uint256 lastModifiedTimestamp;
        uint256 minCloseTime; // Flash loan protection: earliest close time
        uint256 initialMargin; // Original collateral (before any add margin)
        uint256 addedMargin; // Total margin added after position open
        // ========== PRICE IMPACT FIELDS ==========
        uint256 impactFee; // One-time skew fee paid at open (stays in vault)
        uint256 executionPrice; // Adjusted open price after impact (used for P&L display)
    }

    // ========================================================================
    // LIQUIDATION CALCULATION
    // ========================================================================

    /**
     * @notice Calculate liquidation price with leverage and maintenance margin ratio
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
     */
    function calculateLiquidationPrice(
        uint256 openPrice,
        uint8 direction,
        uint8 leverage,
        uint256 maintenanceMarginRatio
    ) internal pure returns (uint256) {
        if (openPrice == 0) revert InvalidOpenPrice();
        if (leverage < MIN_LEVERAGE || leverage > MAX_LEVERAGE) {
            revert InvalidLeverage();
        }
        if (maintenanceMarginRatio >= MathLib.BASIS_POINTS) {
            revert InvalidMaintenanceMarginRatio();
        }
        if (direction != BET_DIRECTION_LONG && direction != BET_DIRECTION_SHORT) {
            revert InvalidDirection();
        }

        // Calculate liquidation threshold as % of collateral
        // If MMR = 20%, then liquidation at 80% loss
        uint256 liquidationThreshold = MathLib.BASIS_POINTS - maintenanceMarginRatio;

        // Calculate price deviation percentage
        // priceDeviationBps = liquidationThreshold / leverage
        uint256 priceDeviationBps = liquidationThreshold / leverage;

        if (direction == BET_DIRECTION_LONG) {
            // LONG: liquidation when price decreases

            // Calculate price decrease with overflow check
            uint256 priceDecrease = (openPrice * priceDeviationBps) / MathLib.BASIS_POINTS;

            if (priceDecrease >= openPrice) {
                revert LiquidationPriceUnderflow();
            }

            uint256 liquidationPrice = openPrice - priceDecrease;

            // Additional sanity check: liquidation price should be reasonable
            if (liquidationPrice == 0) {
                revert InvalidLiquidationPrice();
            }

            return liquidationPrice;
        } else {
            // SHORT: liquidation when price rises

            // Calculate price increase with overflow check
            uint256 priceIncrease = (openPrice * priceDeviationBps) / MathLib.BASIS_POINTS;

            if (priceIncrease > type(uint256).max - openPrice) {
                revert LiquidationPriceOverflow();
            }

            uint256 liquidationPrice = openPrice + priceIncrease;

            // Additional sanity check
            if (liquidationPrice <= openPrice) {
                revert InvalidLiquidationPriceForShort();
            }

            return liquidationPrice;
        }
    }

    /**
     * @notice Check if position is liquidated
     */
    function isLiquidated(Position memory position, uint256 currentPrice)
        internal
        pure
        returns (bool)
    {
        if (position.direction == BET_DIRECTION_LONG) {
            // LONG: liquidated when currentPrice <= liquidationPrice
            return currentPrice <= position.liquidationPrice;
        } else {
            // SHORT: liquidated when currentPrice >= liquidationPrice
            return currentPrice >= position.liquidationPrice;
        }
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
     * @dev Uses MathLib.priceChangeBpsHighPrecision for accurate calculations
     *      with small price movements. Standard BPS (10000) can lose precision when:
     *      - priceChange is small relative to openPrice
     *      - amount is small (e.g., 1000 wei)
     *
     *      Example: $1 change on $50k price with standard BPS = 0 (lost!)
     *               With high precision (1e18) = correctly calculated
     *
     * @param position Position data
     * @param currentPrice Current market price
     * @return pnl Profit/Loss (positive = profit, negative = loss)
     * @return pnlPercentage P&L as percentage of collateral in standard bps (10000 = 100%)
     */
    function calculateUnrealizedPnL(Position memory position, uint256 currentPrice)
        internal
        pure
        returns (int256 pnl, int256 pnlPercentage)
    {
        if (position.openPrice == 0) revert InvalidOpenPrice();
        if (currentPrice == 0) revert InvalidCurrentPrice();
        if (position.amount == 0) revert InvalidPositionAmount();

        // Use high precision price change calculation
        // Returns price change in BPS scaled by MathLib.PRECISION (1e18)
        // This prevents precision loss for small price movements
        int256 priceChangeBpsHighPrecision =
            MathLib.priceChangeBpsHighPrecision(currentPrice, position.openPrice);

        // No price change
        if (priceChangeBpsHighPrecision == 0) {
            return (0, 0);
        }

        // Apply leverage (still in high precision)
        int256 leverageInt = int256(uint256(position.leverage));

        // Check if multiplication will overflow
        if (priceChangeBpsHighPrecision > 0) {
            if (uint256(priceChangeBpsHighPrecision) > type(uint256).max / uint256(leverageInt)) {
                revert LeverageMultiplicationOverflow();
            }
        } else {
            if (uint256(-priceChangeBpsHighPrecision) > type(uint256).max / uint256(leverageInt)) {
                revert LeverageMultiplicationOverflow();
            }
        }

        int256 leveragedPnLHighPrecision = priceChangeBpsHighPrecision * leverageInt;

        // Reverse sign for SHORT positions
        if (position.direction == BET_DIRECTION_SHORT) {
            leveragedPnLHighPrecision = -leveragedPnLHighPrecision;
        }

        // Calculate absolute P&L using high precision
        // This divides by both MathLib.BASIS_POINTS and PRECISION to get the actual value
        pnl = MathLib.calculatePnLFromHighPrecision(position.amount, leveragedPnLHighPrecision);

        // Convert back to standard BPS for return value compatibility
        // pnlPercentage is in standard BPS (10000 = 100%)
        pnlPercentage = MathLib.toStandardBps(leveragedPnLHighPrecision);

        return (pnl, pnlPercentage);
    }

    /**
     * @notice Calculate unrealized P&L with standard precision (legacy)
     * @dev Kept for backward compatibility and gas-sensitive operations
     *      where precision loss is acceptable (large positions, large price movements)
     * @param position Position data
     * @param currentPrice Current market price
     * @return pnl Profit/Loss
     * @return pnlPercentage P&L percentage in bps
     */
    function calculateUnrealizedPnLStandard(Position memory position, uint256 currentPrice)
        internal
        pure
        returns (int256 pnl, int256 pnlPercentage)
    {
        if (position.openPrice == 0) revert InvalidOpenPrice();
        if (currentPrice == 0) revert InvalidCurrentPrice();
        if (position.amount == 0) revert InvalidPositionAmount();

        // Calculate price change percentage (in bps) - standard precision
        int256 priceChangeBps;

        if (currentPrice > position.openPrice) {
            uint256 priceIncrease = currentPrice - position.openPrice;
            if (priceIncrease > type(uint256).max / MathLib.BASIS_POINTS) {
                revert PriceChangeTooLarge();
            }
            priceChangeBps = int256((priceIncrease * MathLib.BASIS_POINTS) / position.openPrice);
        } else if (currentPrice < position.openPrice) {
            uint256 priceDecrease = position.openPrice - currentPrice;
            if (priceDecrease > type(uint256).max / MathLib.BASIS_POINTS) {
                revert PriceChangeTooLarge();
            }
            priceChangeBps = -int256((priceDecrease * MathLib.BASIS_POINTS) / position.openPrice);
        } else {
            return (0, 0);
        }

        int256 leverageInt = int256(uint256(position.leverage));

        // Overflow checks
        if (priceChangeBps > 0) {
            if (uint256(priceChangeBps) > type(uint256).max / uint256(leverageInt)) {
                revert LeverageMultiplicationOverflow();
            }
        } else if (priceChangeBps < 0) {
            if (uint256(-priceChangeBps) > type(uint256).max / uint256(leverageInt)) {
                revert LeverageMultiplicationOverflow();
            }
        }

        int256 leveragedPnLPercentage = priceChangeBps * leverageInt;

        if (position.direction == BET_DIRECTION_SHORT) {
            leveragedPnLPercentage = -leveragedPnLPercentage;
        }

        int256 amountInt = int256(position.amount);

        if (leveragedPnLPercentage > 0) {
            if (uint256(leveragedPnLPercentage) > type(uint256).max / position.amount) {
                revert PnLCalculationOverflow();
            }
        } else if (leveragedPnLPercentage < 0) {
            if (uint256(-leveragedPnLPercentage) > type(uint256).max / position.amount) {
                revert PnLCalculationOverflow();
            }
        }

        int256 absolutePnL = (amountInt * leveragedPnLPercentage) / int256(MathLib.BASIS_POINTS);

        return (absolutePnL, leveragedPnLPercentage);
    }
}
