// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title VaultLiquidityLib
 * @notice Library for vault liquidity calculations
 * @dev Separates liquidity calculation logic from AssetVault for contract size optimization
 *      Used by AssetVaultUpgradeable for LP deposit/withdrawal calculations
 */
library VaultLiquidityLib {
    // ========================================================================
    // CONSTANTS
    // ========================================================================

    uint256 constant BASIS_POINTS = 10_000;
    uint256 constant INITIAL_SHARE_MULTIPLIER = 1e18;

    // ========================================================================
    // CUSTOM ERRORS
    // ========================================================================

    error InvalidAmount();
    error DepositTooSmall();
    error InsufficientLiquidity();
    error InsufficientShares();

    // ========================================================================
    // STRUCTS
    // ========================================================================

    struct DepositParams {
        uint256 amount;
        uint256 stakingFeeBps;
        uint256 minLiquidityAmount;
        uint256 totalShares;
        uint256 totalLiquidity;
    }

    struct DepositResult {
        uint256 netAmount;
        uint256 stakingFee;
        uint256 shares;
    }

    struct WithdrawalParams {
        uint256 shares;
        uint256 totalShares;
        uint256 totalLiquidity;
        uint256 stakedAt;
        uint256 minLockPeriod;
        uint256 earlyWithdrawalFeeBps;
        bool isGraduated;
    }

    struct WithdrawalResult {
        uint256 grossAmount;
        uint256 withdrawalFee;
        uint256 netPayout;
        bool isEarlyWithdrawal;
        uint256 lockEndTime;
    }

    // ========================================================================
    // CALCULATION FUNCTIONS
    // ========================================================================

    /**
     * @notice Calculate deposit result including shares and fees
     * @param params Deposit parameters
     * @return result Deposit calculation result
     */
    function calculateDeposit(DepositParams memory params)
        internal
        pure
        returns (DepositResult memory result)
    {
        if (params.amount == 0) revert InvalidAmount();

        // Calculate staking fee
        result.stakingFee = (params.amount * params.stakingFeeBps) / BASIS_POINTS;
        result.netAmount = params.amount - result.stakingFee;

        if (result.netAmount < params.minLiquidityAmount) {
            revert DepositTooSmall();
        }

        // Calculate shares based on NET amount (after fee)
        if (params.totalShares == 0) {
            // First deposit
            result.shares = result.netAmount * INITIAL_SHARE_MULTIPLIER;
        } else {
            // Subsequent deposits: shares = (netAmount * totalShares) / totalLiquidity
            result.shares = (result.netAmount * params.totalShares) / params.totalLiquidity;
        }

        if (result.shares == 0) revert InvalidAmount();

        return result;
    }

    /**
     * @notice Calculate withdrawal result including fees
     * @param params Withdrawal parameters
     * @return result Withdrawal calculation result
     */
    function calculateWithdrawal(WithdrawalParams memory params)
        internal
        view
        returns (WithdrawalResult memory result)
    {
        if (params.shares == 0) revert InvalidAmount();
        if (params.shares > params.totalShares) revert InsufficientShares();

        // Calculate gross amount based on total liquidity
        result.grossAmount = (params.shares * params.totalLiquidity) / params.totalShares;

        // Check early withdrawal
        result.lockEndTime = params.stakedAt + params.minLockPeriod;
        result.isEarlyWithdrawal = block.timestamp < result.lockEndTime;

        // Calculate fee and net payout
        result.withdrawalFee = 0;
        result.netPayout = result.grossAmount;

        // Early withdrawal penalty only applies AFTER vault has graduated
        if (result.isEarlyWithdrawal && params.isGraduated) {
            result.withdrawalFee =
                (result.grossAmount * params.earlyWithdrawalFeeBps) / BASIS_POINTS;
            result.netPayout = result.grossAmount - result.withdrawalFee;
        }

        if (result.netPayout > params.totalLiquidity) {
            revert InsufficientLiquidity();
        }

        return result;
    }

    /**
     * @notice Calculate shares for a given amount
     * @param amount Net amount after fees
     * @param totalShares Current total shares
     * @param totalLiquidity Current total liquidity
     * @return shares Calculated shares
     */
    function calculateShares(uint256 amount, uint256 totalShares, uint256 totalLiquidity)
        internal
        pure
        returns (uint256 shares)
    {
        if (amount == 0) return 0;

        if (totalShares == 0) {
            shares = amount * INITIAL_SHARE_MULTIPLIER;
        } else {
            shares = (amount * totalShares) / totalLiquidity;
        }

        return shares;
    }

    /**
     * @notice Calculate share value
     * @param shares Number of shares
     * @param totalShares Current total shares
     * @param totalLiquidity Current total liquidity
     * @return value Value of shares in tokens
     */
    function calculateShareValue(uint256 shares, uint256 totalShares, uint256 totalLiquidity)
        internal
        pure
        returns (uint256 value)
    {
        if (totalShares == 0) return 0;
        return (shares * totalLiquidity) / totalShares;
    }

    /**
     * @notice Calculate staking fee
     * @param amount Gross amount
     * @param stakingFeeBps Fee in basis points
     * @return fee Calculated fee
     * @return netAmount Amount after fee
     */
    function calculateStakingFee(uint256 amount, uint256 stakingFeeBps)
        internal
        pure
        returns (uint256 fee, uint256 netAmount)
    {
        fee = (amount * stakingFeeBps) / BASIS_POINTS;
        netAmount = amount - fee;
        return (fee, netAmount);
    }

    /**
     * @notice Calculate early withdrawal fee
     * @param amount Gross withdrawal amount
     * @param earlyWithdrawalFeeBps Fee in basis points
     * @param stakedAt Timestamp when staked
     * @param minLockPeriod Minimum lock period
     * @param isGraduated Whether vault has graduated
     * @return fee Calculated fee (0 if not early or not graduated)
     * @return netAmount Amount after fee
     * @return isEarly Whether this is early withdrawal
     */
    function calculateEarlyWithdrawalFee(
        uint256 amount,
        uint256 earlyWithdrawalFeeBps,
        uint256 stakedAt,
        uint256 minLockPeriod,
        bool isGraduated
    ) internal view returns (uint256 fee, uint256 netAmount, bool isEarly) {
        uint256 lockEndTime = stakedAt + minLockPeriod;
        isEarly = block.timestamp < lockEndTime;

        if (isEarly && isGraduated) {
            fee = (amount * earlyWithdrawalFeeBps) / BASIS_POINTS;
            netAmount = amount - fee;
        } else {
            fee = 0;
            netAmount = amount;
        }

        return (fee, netAmount, isEarly);
    }

    /**
     * @notice Get remaining lock time for a user
     * @param stakedAt Timestamp when staked
     * @param minLockPeriod Minimum lock period
     * @return remainingTime Remaining lock time in seconds (0 if unlocked)
     */
    function getRemainingLockTime(uint256 stakedAt, uint256 minLockPeriod)
        internal
        view
        returns (uint256 remainingTime)
    {
        uint256 lockEndTime = stakedAt + minLockPeriod;
        if (block.timestamp >= lockEndTime) return 0;
        return lockEndTime - block.timestamp;
    }
}
