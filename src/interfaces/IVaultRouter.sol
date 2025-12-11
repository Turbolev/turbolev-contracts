// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../vault-modular/libraries/VaultStorageLib.sol";

/**
 * @title IVaultRouter
 * @notice Interface for modular vault router
 * @dev Compatible with AssetVaultUpgradeable API for seamless migration
 */
interface IVaultRouter {
    // ========================================================================
    // LIQUIDITY FUNCTIONS
    // ========================================================================

    /**
     * @notice Add liquidity to vault
     * @param amount Amount of project tokens to add
     */
    function addLiquidity(uint256 amount) external payable;

    /**
     * @notice Remove liquidity from vault
     */
    function removeLiquidity() external;

    // ========================================================================
    // POSITION FUNCTIONS (called by PositionManager)
    // ========================================================================

    /**
     * @notice Deposit collateral from bet
     * @param positionId Position ID
     * @param amount Collateral amount
     * @param positionSize Position size
     * @param isMarginAdd True if adding margin to existing position
     * @param direction Position direction (1 = LONG, 2 = SHORT)
     */
    function depositFromBet(
        uint64 positionId,
        uint256 amount,
        uint256 positionSize,
        bool isMarginAdd,
        uint8 direction
    ) external payable;

    /**
     * @notice Execute payout to user
     * @param user User address
     * @param amount Payout amount
     * @param positionId Position ID
     */
    function executePayout(address user, uint256 amount, uint64 positionId) external;

    /**
     * @notice Update vault P&L after position settlement
     * @param positionId Position ID
     * @param collateral Collateral amount
     * @param vaultPnL Vault P&L
     * @param fee Fee amount
     * @param positionSize Position size
     * @param direction Position direction
     * @param user User address
     */
    function updateVaultPnL(
        uint64 positionId,
        uint256 collateral,
        int256 vaultPnL,
        uint256 fee,
        uint256 positionSize,
        uint8 direction,
        address user
    ) external;

    /**
     * @notice Check position risk
     * @param positionSize Position size
     * @param leverage Leverage
     * @param direction Position direction
     */
    function checkPositionRisk(uint256 positionSize, uint8 leverage, uint8 direction) external view;

    // ========================================================================
    // FUNDING FUNCTIONS
    // ========================================================================

    /**
     * @notice Update hourly funding
     * @return newLongRate New cumulative long rate
     * @return newShortRate New cumulative short rate
     * @return imbalanceBps Imbalance in basis points
     * @return hasCounterparty True if counterparty exists
     */
    function updateHourlyFunding()
        external
        returns (int256 newLongRate, int256 newShortRate, uint256 imbalanceBps, bool hasCounterparty);

    /**
     * @notice Get cumulative funding rates
     * @return cumulativeLongRate Cumulative long rate
     * @return cumulativeShortRate Cumulative short rate
     */
    function getCumulativeFundingRates()
        external
        view
        returns (int256 cumulativeLongRate, int256 cumulativeShortRate);

    /**
     * @notice Calculate position funding
     * @param entryRateLong Entry long rate
     * @param entryRateShort Entry short rate
     * @param positionSize Position size
     * @param direction Position direction
     * @return fundingOwed Funding owed
     */
    function calculatePositionFunding(
        int256 entryRateLong,
        int256 entryRateShort,
        uint256 positionSize,
        uint8 direction
    ) external view returns (int256 fundingOwed);

    /**
     * @notice Get current hourly funding rate
     * @return rateBps Hourly rate in bps
     * @return longsPayShorts True if longs pay shorts
     * @return imbalanceBps Imbalance in bps
     * @return hasCounterparty True if counterparty exists
     */
    function getCurrentHourlyFundingRate()
        external
        view
        returns (uint256 rateBps, bool longsPayShorts, uint256 imbalanceBps, bool hasCounterparty);

    /**
     * @notice Check funding liquidation
     * @param collateral Position collateral
     * @param entryRateLong Entry long rate
     * @param entryRateShort Entry short rate
     * @param positionSize Position size
     * @param direction Position direction
     * @param maintenanceMarginRatio Maintenance margin ratio
     * @return isLiquidatable True if liquidatable
     * @return fundingOwed Funding owed
     * @return effectiveCollateral Effective collateral
     */
    function checkFundingLiquidation(
        uint256 collateral,
        int256 entryRateLong,
        int256 entryRateShort,
        uint256 positionSize,
        uint8 direction,
        uint256 maintenanceMarginRatio
    )
        external
        view
        returns (bool isLiquidatable, int256 fundingOwed, uint256 effectiveCollateral);

    /**
     * @notice Set funding config
     */
    function setFundingConfig(
        uint16 tier1RateBps,
        uint16 tier2RateBps,
        uint16 tier3RateBps,
        uint16 tier4RateBps,
        uint16 tier5RateBps
    ) external;

    /**
     * @notice Set funding enabled
     */
    function setFundingEnabled(bool enabled) external;

    /**
     * @notice Get funding config
     */
    function getFundingConfig() external view returns (uint16, uint16, uint16, uint16, uint16);

    // ========================================================================
    // REWARDS FUNCTIONS
    // ========================================================================

    /**
     * @notice Finalize daily reward
     * @return isComplete True if all LPs processed
     */
    function finalizeDailyReward() external returns (bool isComplete);

    /**
     * @notice Finalize daily reward remaining
     * @return isComplete True if complete
     */
    function finalizeDailyRewardRemaining() external returns (bool isComplete);

    /**
     * @notice Claim rewards
     */
    function claimRewards() external;

    /**
     * @notice Claim rewards with protection
     * @param minExpectedRewards Minimum expected rewards
     */
    function claimRewardsProtected(uint256 minExpectedRewards) external;

    /**
     * @notice Get claimable rewards
     * @param user User address
     * @return amount Claimable amount
     */
    function getClaimableRewards(address user) external view returns (uint256 amount);

    /**
     * @notice Calculate pending rewards
     * @param user User address
     * @return pendingRewards Pending rewards
     */
    function calculatePendingRewards(address user) external view returns (uint256 pendingRewards);

    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================

    /**
     * @notice Pause vault
     */
    function pause() external;

    /**
     * @notice Unpause vault
     */
    function unpause() external;

    /**
     * @notice Set fee
     * @param feeType Fee type (0=staking, 1=earlyWithdrawal, 2=openPosition, 3=closePosition)
     * @param feeBps Fee in basis points
     */
    function setFee(uint8 feeType, uint16 feeBps) external;

    /**
     * @notice Set treasury
     * @param treasury Treasury address
     */
    function setTreasury(address treasury) external;

    /**
     * @notice Set trading enabled
     * @param enabled True to enable trading
     */
    function setTradingEnabled(bool enabled) external;

    /**
     * @notice Set graduation threshold
     * @param threshold Graduation threshold
     */
    function setGraduationThreshold(uint256 threshold) external;

    /**
     * @notice Withdraw fees
     * @param amount Amount to withdraw (0 = all)
     */
    function withdrawFees(uint256 amount) external;

    /**
     * @notice Set position manager
     * @param positionManager PositionManager address
     */
    function setPositionManager(address positionManager) external;

    /**
     * @notice Update vault params
     * @param minBetAmount Minimum bet amount
     * @param maxBetAmount Maximum bet amount
     */
    function updateVaultParams(uint256 minBetAmount, uint256 maxBetAmount) external;

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /**
     * @notice Get vault info
     */
    function vaultInfo() external view returns (VaultStorageLib.VaultInfo memory);

    /**
     * @notice Get vault params
     */
    function vaultParams() external view returns (VaultStorageLib.VaultParams memory);

    /**
     * @notice Get LP position
     */
    function lpPositions(address user) external view returns (VaultStorageLib.LPPosition memory);

    /**
     * @notice Get project token
     */
    function projectToken() external view returns (address);

    /**
     * @notice Check if paused
     */
    function paused() external view returns (bool);

    /**
     * @notice Get vault manager
     */
    function vaultManager() external view returns (address);

    /**
     * @notice Get position manager
     */
    function positionManager() external view returns (address);

    /**
     * @notice Get total long exposure
     */
    function totalLongExposure() external view returns (uint256);

    /**
     * @notice Get total short exposure
     */
    function totalShortExposure() external view returns (uint256);

    /**
     * @notice Get bet collateral
     */
    function betCollateral(uint64 positionId) external view returns (uint256);

    /**
     * @notice Get position payouts
     */
    function positionPayouts(uint64 positionId) external view returns (uint256);

    /**
     * @notice Get vault LPs length
     */
    function getVaultLPsLength() external view returns (uint256);

    /**
     * @notice Get pending payout queue length
     */
    function getPendingPayoutQueueLength() external view returns (uint256);

    /**
     * @notice Get version
     */
    function version() external pure returns (string memory);

    // ========================================================================
    // MODULE MANAGEMENT
    // ========================================================================

    /**
     * @notice Get module address
     * @param moduleId Module ID
     * @return module Module address
     */
    function getModule(bytes4 moduleId) external view returns (address module);

    /**
     * @notice Update module address
     * @param moduleId Module ID
     * @param newModule New module address
     */
    function updateModule(bytes4 moduleId, address newModule) external;
}

