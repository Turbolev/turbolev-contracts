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

    // Maintenance Margin Ratio: 6.25% (configurable via setter)
    // This means liquidation happens when loss = (100% - 6.25%) = 93.75% of collateral
    uint256 public constant DEFAULT_MAINTENANCE_MARGIN_RATIO = 625; // 6.25% in bps

    // Tiered Liquidation Fees (in basis points)
    uint256 public constant LIQUIDATION_FEE_TIER1 = 200; // 2% for leverage 1-5x
    uint256 public constant LIQUIDATION_FEE_TIER2 = 300; // 3% for leverage 6-20x
    uint256 public constant LIQUIDATION_FEE_TIER3 = 400; // 4% for leverage 21-50x
    uint256 public constant LIQUIDATION_FEE_TIER4 = 500; // 5% for leverage 51-100x

    // ========================================================================
    // POSITION DATA STRUCTURE
    // ========================================================================

    struct Position {
        uint64 positionId;
        address user;
        address tokenAddress; // address(0) for native token (MON)
        uint256 amount; // Collateral amount (bet amount) in wei
        uint8 leverage; // Leverage multiplier (1-100)
        uint8 direction; // BET_DIRECTION_UP or BET_DIRECTION_DOWN
        uint8 state; // POSITION_STATE_*
        uint256 openPrice; // Open price (from backend)
        uint256 closePrice; // Close price (from backend)
        uint256 liquidationPrice; // Liquidation price (calculated based on leverage)
        uint256 positionSize; // Position size = amount × leverage (for display)
        uint256 createdTimestamp;
        uint256 lastModifiedTimestamp;
        uint8 closeRequestCount;
        uint8 maxCloseRequests;
    }

    // ========================================================================
    // ERRORS
    // ========================================================================

    error InvalidStateTransition(uint8 from, uint8 to);
    error PositionNotOpen();
    error PositionAlreadyClosed();
    error MaxCloseRequestsExceeded();
    error InvalidDirection();
    error InvalidState();
    error InvalidLeverage();

    // ========================================================================
    // VALIDATION FUNCTIONS
    // ========================================================================

    /**
     * @notice Check if a state is valid
     */
    function isValidState(uint8 state) internal pure returns (bool) {
        return
            state >= POSITION_STATE_OPEN && state <= POSITION_STATE_LIQUIDATED;
    }

    /**
     * @notice Check if a direction is valid
     */
    function isValidDirection(uint8 direction) internal pure returns (bool) {
        return
            direction == BET_DIRECTION_LONG || direction == BET_DIRECTION_SHORT;
    }

    /**
     * @notice Check if leverage is valid
     */
    function isValidLeverage(uint8 leverage) internal pure returns (bool) {
        return leverage >= MIN_LEVERAGE && leverage <= MAX_LEVERAGE;
    }

    /**
     * @notice Check if state transition is valid
     */
    function isValidStateTransition(
        uint8 fromState,
        uint8 toState
    ) internal pure returns (bool) {
        if (fromState == POSITION_STATE_OPEN) {
            return
                toState == POSITION_STATE_CLOSING ||
                toState == POSITION_STATE_CLOSED ||
                toState == POSITION_STATE_CANCELLED;
        } else if (fromState == POSITION_STATE_CLOSING) {
            return
                toState == POSITION_STATE_CLOSED ||
                toState == POSITION_STATE_CANCELLED ||
                toState == POSITION_STATE_WON ||
                toState == POSITION_STATE_LOST;
        }
        return false;
    }

    /**
     * @notice Check if position is in a terminal state
     */
    function isTerminalState(uint8 state) internal pure returns (bool) {
        return
            state == POSITION_STATE_CLOSED ||
            state == POSITION_STATE_CANCELLED ||
            state == POSITION_STATE_WON ||
            state == POSITION_STATE_LOST ||
            state == POSITION_STATE_LIQUIDATED;
    }

    /**
     * @notice Check if position is in active state
     */
    function isActiveState(uint8 state) internal pure returns (bool) {
        return state == POSITION_STATE_OPEN || state == POSITION_STATE_CLOSING;
    }

    // ========================================================================
    // POSITION STATE MANAGEMENT
    // ========================================================================

    /**
     * @notice Create new position with OPEN state and leverage
     */
    function createPosition(
        uint64 positionId,
        address user,
        address tokenAddress,
        uint256 amount,
        uint8 leverage,
        uint8 direction,
        uint256 openPrice,
        uint256 maintenanceMarginRatio
    ) internal view returns (Position memory) {
        if (!isValidDirection(direction)) revert InvalidDirection();
        if (!isValidLeverage(leverage)) revert InvalidLeverage();

        uint256 liquidationPrice = calculateLiquidationPrice(
            openPrice,
            direction,
            leverage,
            maintenanceMarginRatio
        );

        return
            Position({
                positionId: positionId,
                user: user,
                tokenAddress: tokenAddress,
                amount: amount,
                leverage: leverage,
                direction: direction,
                state: POSITION_STATE_OPEN,
                openPrice: openPrice,
                closePrice: 0,
                liquidationPrice: liquidationPrice,
                positionSize: amount * leverage,
                createdTimestamp: block.timestamp,
                lastModifiedTimestamp: block.timestamp,
                closeRequestCount: 0,
                maxCloseRequests: 3
            });
    }

    /**
     * @notice Request to close position (OPEN -> CLOSING)
     */
    function requestClosure(Position storage position) internal {
        if (position.state != POSITION_STATE_OPEN) revert PositionNotOpen();
        if (position.closeRequestCount >= position.maxCloseRequests)
            revert MaxCloseRequestsExceeded();

        position.state = POSITION_STATE_CLOSING;
        position.closeRequestCount++;
        position.lastModifiedTimestamp = block.timestamp;
    }

    /**
     * @notice Confirm position close (CLOSING -> CLOSED/WON/LOST)
     */
    function confirmClosure(
        Position storage position,
        uint8 newState
    ) internal {
        if (
            position.state != POSITION_STATE_CLOSING &&
            position.state != POSITION_STATE_OPEN
        ) {
            revert InvalidStateTransition(position.state, newState);
        }
        if (!isValidStateTransition(position.state, newState)) {
            revert InvalidStateTransition(position.state, newState);
        }

        position.state = newState;
        position.lastModifiedTimestamp = block.timestamp;
    }

    /**
     * @notice Cancel position
     */
    function cancelPosition(Position storage position) internal {
        if (
            position.state != POSITION_STATE_OPEN &&
            position.state != POSITION_STATE_CLOSING
        ) {
            revert InvalidStateTransition(
                position.state,
                POSITION_STATE_CANCELLED
            );
        }

        position.state = POSITION_STATE_CANCELLED;
        position.lastModifiedTimestamp = block.timestamp;
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
     */
    function calculateLiquidationPrice(
        uint256 openPrice,
        uint8 direction,
        uint8 leverage,
        uint256 maintenanceMarginRatio
    ) internal pure returns (uint256) {
        require(
            leverage >= MIN_LEVERAGE && leverage <= MAX_LEVERAGE,
            "Invalid leverage"
        );

        // Calculate liquidation threshold as % of collateral
        // If MMR = 6.25%, then liquidation at 93.75% loss
        uint256 liquidationThreshold = BASIS_POINTS - maintenanceMarginRatio; // 10000 - 625 = 9375 (93.75%)

        // Calculate price deviation percentage
        // priceDeviationBps = liquidationThreshold / leverage
        uint256 priceDeviationBps = liquidationThreshold / leverage;

        if (direction == BET_DIRECTION_LONG) {
            // LONG: liquidation when price decreases
            uint256 priceDecrease = (openPrice * priceDeviationBps) /
                BASIS_POINTS;
            return openPrice - priceDecrease;
        } else {
            // SHORT: liquidation when price rises
            uint256 priceIncrease = (openPrice * priceDeviationBps) /
                BASIS_POINTS;
            return openPrice + priceIncrease;
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
     * @notice Tính toán liquidation fee theo leverage tier
     * @param leverage Leverage multiplier
     * @return fee Fee in basis points
     */
    function calculateLiquidationFee(
        uint8 leverage
    ) internal pure returns (uint256) {
        if (leverage >= 1 && leverage <= 5) return LIQUIDATION_FEE_TIER1; // 2%
        if (leverage >= 6 && leverage <= 20) return LIQUIDATION_FEE_TIER2; // 3%
        if (leverage >= 21 && leverage <= 50) return LIQUIDATION_FEE_TIER3; // 4%
        return LIQUIDATION_FEE_TIER4; // 5% for 51-100x
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
     */
    function calculateUnrealizedPnL(
        Position memory position,
        uint256 currentPrice
    ) internal pure returns (int256 pnl, int256 pnlPercentage) {
        // Calculate price change percentage (in bps)
        int256 priceChangeBps;

        if (currentPrice > position.openPrice) {
            // Price increased
            uint256 priceIncrease = currentPrice - position.openPrice;
            priceChangeBps = int256(
                (priceIncrease * BASIS_POINTS) / position.openPrice
            );
        } else if (currentPrice < position.openPrice) {
            // Price decreased
            uint256 priceDecrease = position.openPrice - currentPrice;
            priceChangeBps = -int256(
                (priceDecrease * BASIS_POINTS) / position.openPrice
            );
        } else {
            // No price change
            return (0, 0);
        }

        // Apply leverage
        int256 leveragedPnLPercentage = priceChangeBps *
            int256(uint256(position.leverage));

        // Reverse sign for SHORT positions
        if (position.direction == BET_DIRECTION_SHORT) {
            leveragedPnLPercentage = -leveragedPnLPercentage;
        }

        // Calculate absolute P&L
        int256 absolutePnL = (int256(position.amount) *
            leveragedPnLPercentage) / int256(BASIS_POINTS);

        return (absolutePnL, leveragedPnLPercentage);
    }

    /**
     * @notice Check win condition when closing position
     */
    function checkWinCondition(
        Position memory position,
        uint256 closePrice
    ) internal pure returns (bool) {
        if (position.direction == BET_DIRECTION_LONG) {
            // LONG: win when closePrice > openPrice
            return closePrice > position.openPrice;
        } else {
            // SHORT: win when closePrice < openPrice
            return closePrice < position.openPrice;
        }
    }

    // ========================================================================
    // STRING HELPERS (for debugging)
    // ========================================================================

    /**
     * @notice Get state as string
     */
    function getStateString(uint8 state) internal pure returns (string memory) {
        if (state == POSITION_STATE_OPEN) return "OPEN";
        if (state == POSITION_STATE_CLOSING) return "CLOSING";
        if (state == POSITION_STATE_CLOSED) return "CLOSED";
        if (state == POSITION_STATE_CANCELLED) return "CANCELLED";
        if (state == POSITION_STATE_WON) return "WON";
        if (state == POSITION_STATE_LOST) return "LOST";
        if (state == POSITION_STATE_LIQUIDATED) return "LIQUIDATED";
        return "UNKNOWN";
    }

    /**
     * @notice Get direction as string
     */
    function getDirectionString(
        uint8 direction
    ) internal pure returns (string memory) {
        if (direction == BET_DIRECTION_LONG) return "LONG";
        if (direction == BET_DIRECTION_SHORT) return "SHORT";
        return "UNKNOWN";
    }
}
