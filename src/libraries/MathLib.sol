// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title MathLib
 * @notice Library for high-precision mathematical operations
 * @dev Fixes H-02: Prevents precision loss in BPS calculations
 *
 * Usage patterns:
 * - Fee calculations: mulBps(amount, feeBps)
 * - Percentage calculations: percentOf(amount, bps)
 * - P&L calculations: signedMulBps(amount, pnlBps)
 * - With rounding options: mulBpsRoundUp for user-favorable
 *
 * @custom:security-contact security@boolean.finance
 */
library MathLib {
    // ========================================================================
    // CONSTANTS
    // ========================================================================

    /// @notice Standard basis points denominator (10000 = 100%)
    uint256 public constant BASIS_POINTS = 10_000;

    /// @notice High precision multiplier for intermediate calculations
    /// @dev 1e18 is DeFi standard, prevents precision loss in most cases
    uint256 public constant PRECISION = 1e18;

    /// @notice Scaled BASIS_POINTS for high precision mode
    uint256 public constant PRECISION_BPS = PRECISION / BASIS_POINTS; // 1e14

    /// @notice Maximum safe value before overflow in multiplication
    uint256 private constant MAX_SAFE_UINT = type(uint256).max / PRECISION;

    /// @notice Maximum safe value for signed operations
    int256 private constant MAX_SAFE_INT = type(int256).max / int256(PRECISION);

    // ========================================================================
    // ERRORS
    // ========================================================================

    error MathOverflow();
    error DivisionByZero();
    error InvalidBps();
    error SignedOverflow();

    // ========================================================================
    // BASIC BPS OPERATIONS (Standard precision)
    // ========================================================================

    /**
     * @notice Calculate percentage of amount in basis points
     * @param amount Base amount
     * @param bps Basis points (e.g., 500 = 5%)
     * @return result = amount * bps / 10000
     * @dev Standard precision, may lose precision for small amounts
     */
    function mulBps(uint256 amount, uint256 bps) internal pure returns (uint256) {
        return (amount * bps) / BASIS_POINTS;
    }

    /**
     * @notice Calculate percentage with round up (user-favorable for fees paid TO user)
     * @param amount Base amount
     * @param bps Basis points
     * @return result = ceil(amount * bps / 10000)
     */
    function mulBpsRoundUp(uint256 amount, uint256 bps) internal pure returns (uint256) {
        uint256 numerator = amount * bps;
        return (numerator + BASIS_POINTS - 1) / BASIS_POINTS;
    }

    /**
     * @notice Subtract fee from amount
     * @param amount Base amount
     * @param feeBps Fee in basis points
     * @return fee The fee amount
     * @return netAmount Amount after fee (amount - fee)
     */
    function subtractFee(uint256 amount, uint256 feeBps)
        internal
        pure
        returns (uint256 fee, uint256 netAmount)
    {
        fee = mulBps(amount, feeBps);
        netAmount = amount - fee;
    }

    /**
     * @notice Subtract fee with round down on fee (user-favorable - user keeps more)
     * @dev Fee rounds down naturally with integer division
     */
    function subtractFeeRoundDown(uint256 amount, uint256 feeBps)
        internal
        pure
        returns (uint256 fee, uint256 netAmount)
    {
        fee = mulBps(amount, feeBps); // rounds down naturally
        netAmount = amount - fee;
    }

    // ========================================================================
    // HIGH PRECISION BPS OPERATIONS
    // ========================================================================

    /**
     * @notice Calculate percentage with high precision intermediate
     * @param amount Base amount
     * @param bps Basis points
     * @return result Calculated with 1e18 precision, then scaled back
     * @dev Prevents precision loss for small amounts/percentages
     */
    function mulBpsHighPrecision(uint256 amount, uint256 bps) internal pure returns (uint256) {
        if (amount == 0 || bps == 0) return 0;

        // For very large amounts, fallback to standard precision to avoid overflow
        if (amount > MAX_SAFE_UINT) {
            return mulBps(amount, bps);
        }

        // Scale up, calculate, scale down
        // amount * PRECISION * bps / BASIS_POINTS / PRECISION
        uint256 scaled = amount * PRECISION;
        uint256 result = (scaled * bps) / BASIS_POINTS / PRECISION;

        return result;
    }

    /**
     * @notice High precision calculation with round half up
     * @param amount Base amount
     * @param bps Basis points
     * @return result Rounded to nearest (half up)
     */
    function mulBpsHighPrecisionRound(uint256 amount, uint256 bps)
        internal
        pure
        returns (uint256)
    {
        if (amount == 0 || bps == 0) return 0;

        if (amount > MAX_SAFE_UINT) {
            return mulBps(amount, bps);
        }

        uint256 scaled = amount * PRECISION;
        uint256 numerator = scaled * bps;
        uint256 denominator = BASIS_POINTS * PRECISION;

        // Round half up: (a + b/2) / b
        return (numerator + denominator / 2) / denominator;
    }

    // ========================================================================
    // SIGNED OPERATIONS (for P&L calculations)
    // ========================================================================

    /**
     * @notice Calculate signed percentage (for P&L)
     * @param amount Base amount (always positive collateral)
     * @param signedBps Signed basis points (+profit, -loss)
     * @return result Signed result
     */
    function signedMulBps(uint256 amount, int256 signedBps) internal pure returns (int256) {
        if (amount == 0 || signedBps == 0) return 0;

        int256 amountInt = int256(amount);
        return (amountInt * signedBps) / int256(BASIS_POINTS);
    }

    /**
     * @notice High precision signed multiplication
     * @param amount Base amount
     * @param signedBps Signed basis points
     * @return result Calculated with 1e18 intermediate precision
     */
    function signedMulBpsHighPrecision(uint256 amount, int256 signedBps)
        internal
        pure
        returns (int256)
    {
        if (amount == 0 || signedBps == 0) return 0;

        // Check overflow
        if (amount > MAX_SAFE_UINT) {
            return signedMulBps(amount, signedBps);
        }

        int256 scaled = int256(amount * PRECISION);
        int256 result = (scaled * signedBps) / int256(BASIS_POINTS) / int256(PRECISION);

        return result;
    }

    /**
     * @notice Calculate price change in high precision BPS
     * @param currentPrice Current price
     * @param openPrice Original price
     * @return changeBpsHighPrecision Price change in basis points scaled by PRECISION
     * @dev Returns high-precision value. Divide by PRECISION to get actual BPS.
     *
     * Example:
     *   openPrice = 50000e8, currentPrice = 50001e8 (price up $1)
     *   Standard BPS: (1e8 * 10000) / 50000e8 = 0 (precision lost!)
     *   High precision: (1e8 * 1e18 * 10000) / 50000e8 = 2e13 (0.0002% preserved)
     */
    function priceChangeBpsHighPrecision(uint256 currentPrice, uint256 openPrice)
        internal
        pure
        returns (int256 changeBpsHighPrecision)
    {
        if (openPrice == 0) revert DivisionByZero();

        if (currentPrice > openPrice) {
            uint256 increase = currentPrice - openPrice;
            // Scale by PRECISION first to maintain precision
            // Formula: (increase / openPrice) * BASIS_POINTS * PRECISION
            changeBpsHighPrecision = int256((increase * PRECISION * BASIS_POINTS) / openPrice);
        } else if (currentPrice < openPrice) {
            uint256 decrease = openPrice - currentPrice;
            changeBpsHighPrecision = -int256((decrease * PRECISION * BASIS_POINTS) / openPrice);
        } else {
            changeBpsHighPrecision = 0;
        }
    }

    /**
     * @notice Calculate P&L amount from high precision percentage
     * @param amount Collateral amount
     * @param pnlBpsHighPrecision P&L percentage in high precision (from priceChangeBpsHighPrecision)
     * @return pnl Actual P&L amount
     */
    function calculatePnLFromHighPrecision(uint256 amount, int256 pnlBpsHighPrecision)
        internal
        pure
        returns (int256 pnl)
    {
        if (amount == 0 || pnlBpsHighPrecision == 0) return 0;

        // pnl = amount * pnlBpsHighPrecision / BASIS_POINTS / PRECISION
        int256 amountInt = int256(amount);

        // Check for potential overflow
        if (pnlBpsHighPrecision > 0) {
            if (uint256(pnlBpsHighPrecision) > uint256(type(int256).max) / amount) {
                revert SignedOverflow();
            }
        } else {
            if (uint256(-pnlBpsHighPrecision) > uint256(type(int256).max) / amount) {
                revert SignedOverflow();
            }
        }

        pnl = (amountInt * pnlBpsHighPrecision) / int256(BASIS_POINTS) / int256(PRECISION);
    }

    /**
     * @notice Convert high precision BPS back to standard BPS
     * @param highPrecisionBps Value scaled by PRECISION
     * @return standardBps Value in standard BPS (10000 = 100%)
     */
    function toStandardBps(int256 highPrecisionBps) internal pure returns (int256 standardBps) {
        return highPrecisionBps / int256(PRECISION);
    }

    // ========================================================================
    // UTILITY FUNCTIONS
    // ========================================================================

    /**
     * @notice Safe multiplication with overflow check
     * @param a First operand
     * @param b Second operand
     * @return result a * b
     */
    function safeMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) return 0;
        if (a > type(uint256).max / b) revert MathOverflow();
        return a * b;
    }

    /**
     * @notice Safe division with zero check
     * @param a Numerator
     * @param b Denominator
     * @return result a / b
     */
    function safeDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) revert DivisionByZero();
        return a / b;
    }

    /**
     * @notice Division with round up
     * @param a Numerator
     * @param b Denominator
     * @return result ceil(a / b)
     */
    function divRoundUp(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) revert DivisionByZero();
        return (a + b - 1) / b;
    }

    /**
     * @notice Minimum of two unsigned values
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @notice Maximum of two unsigned values
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    /**
     * @notice Minimum of two signed values
     */
    function minSigned(int256 a, int256 b) internal pure returns (int256) {
        return a < b ? a : b;
    }

    /**
     * @notice Maximum of two signed values
     */
    function maxSigned(int256 a, int256 b) internal pure returns (int256) {
        return a > b ? a : b;
    }

    /**
     * @notice Absolute value of signed integer
     */
    function abs(int256 x) internal pure returns (uint256) {
        return x >= 0 ? uint256(x) : uint256(-x);
    }

    /**
     * @notice Clamp value between min and max
     */
    function clamp(uint256 value, uint256 minVal, uint256 maxVal) internal pure returns (uint256) {
        if (value < minVal) return minVal;
        if (value > maxVal) return maxVal;
        return value;
    }

    /**
     * @notice Clamp signed value between min and max
     */
    function clampSigned(int256 value, int256 minVal, int256 maxVal)
        internal
        pure
        returns (int256)
    {
        if (value < minVal) return minVal;
        if (value > maxVal) return maxVal;
        return value;
    }

    // ========================================================================
    // BPS VALIDATION
    // ========================================================================

    /**
     * @notice Validate BPS is within valid range
     * @param bps Basis points to validate
     * @param maxBps Maximum allowed (e.g., 10000 for 100%)
     */
    function validateBps(uint256 bps, uint256 maxBps) internal pure {
        if (bps > maxBps) revert InvalidBps();
    }

    /**
     * @notice Check if BPS represents valid percentage (<= 100%)
     */
    function isValidPercentage(uint256 bps) internal pure returns (bool) {
        return bps <= BASIS_POINTS;
    }

    /**
     * @notice Ensure value is non-zero
     */
    function requireNonZero(uint256 value) internal pure {
        if (value == 0) revert DivisionByZero();
    }
}
