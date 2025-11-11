// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface IVaultManagerHelper {
    // ========================================================================
    // EVENT EMISSION FUNCTIONS
    // ========================================================================

    function emitLiquidityAdded(
        address user,
        uint256 amount,
        uint256 shares,
        uint256 totalLiquidity,
        uint8 operationType,
        uint256 timestamp
    ) external;

    function emitStakingFeeCollected(
        address user,
        uint256 fee,
        uint256 netAmount,
        uint256 timestamp
    ) external;

    function emitLiquidityRemoved(
        address user,
        uint256 amount,
        uint256 shares,
        uint256 totalLiquidity,
        uint8 operationType,
        uint256 timestamp
    ) external;

    function emitDailyRewardFinalized(
        uint256 day,
        uint256 totalLiquidity,
        uint256 totalShares,
        int256 netPnL,
        uint256 timestamp
    ) external;

    function emitRewardsClaimed(address user, uint256 amount, uint256 timestamp) external;
}
