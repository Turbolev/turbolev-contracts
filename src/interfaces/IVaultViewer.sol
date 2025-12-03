// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IVaultViewer
 * @notice Interface for VaultViewer contract
 */
interface IVaultViewer {
    /**
     * @notice Get total OI breakdown for a vault
     */
    function getTotalOIBreakdown(address vault)
        external
        view
        returns (
            uint256 tvl,
            uint256 longOI,
            uint256 shortOI,
            uint256 totalOI,
            uint256 maxOI,
            uint256 utilizationBps,
            uint256 remainingCapacity,
            uint8 currentTier,
            uint16 currentMultiplierBps
        );

    /**
     * @notice Get total OI cap status for a vault
     */
    function getTotalOICapStatus(address vault)
        external
        view
        returns (
            uint16 currentMultiplierBps,
            uint256 maxTotalOI,
            uint256 currentTotalOI,
            uint256 utilizationBps,
            bool canOpenMore
        );

    /**
     * @notice Get effective max leverage after utilization adjustment
     */
    function getEffectiveMaxLeverage(address vault)
        external
        view
        returns (
            uint16 effectiveMaxLeverage,
            uint16 baseMaxLeverage,
            uint256 utilizationBps,
            uint8 utilizationTier,
            string memory tierDescription
        );

    /**
     * @notice Get vault's current max leverage based on TVL
     */
    function getVaultMaxLeverage(address vault)
        external
        view
        returns (uint16 maxLeverage, uint256 currentTVL, string memory currentPhase);

    /**
     * @notice Get leverage tier configuration
     */
    function getLeverageTierConfig(address vault)
        external
        view
        returns (
            uint256 tier1Threshold,
            uint256 tier2Threshold,
            uint16 tier1Max,
            uint16 tier2Max,
            uint16 tier3Max
        );

    /**
     * @notice Get directional exposure stats
     */
    function getDirectionalExposure(address vault)
        external
        view
        returns (
            uint256 longExposure,
            uint256 shortExposure,
            uint256 netExposure,
            uint256 maxExposure,
            uint256 netUtilization,
            bool isLongBias
        );

    /**
     * @notice Get funding rate statistics
     */
    function getFundingStats(address vault)
        external
        view
        returns (
            int256 cumulativeLongRate,
            int256 cumulativeShortRate,
            uint256 lastUpdateTime,
            uint256 currentHourlyRateBps,
            bool longsPayShorts,
            uint256 imbalanceBps
        );

    /**
     * @notice Check if total OI cap allows new position
     */
    function checkTotalOICap(address vault, uint256 positionSize)
        external
        view
        returns (
            bool canOpen,
            uint256 maxTotalOI,
            uint256 currentTotalOI,
            uint256 remainingCapacity,
            string memory reason
        );

    /**
     * @notice Check if leverage is allowed
     */
    function checkLeverageAllowed(address vault, uint16 requestedLeverage)
        external
        view
        returns (bool isAllowed, uint16 effectiveMaxLeverage, string memory reason);

    /**
     * @notice Simulate TVL change effects
     */
    function simulateTVLChange(address vault, uint256 newTVL)
        external
        view
        returns (
            uint16 newMultiplierBps,
            uint256 newMaxTotalOI,
            uint256 currentTotalOI,
            bool wouldExceedCap
        );

    /**
     * @notice Simulate leverage at different TVL
     */
    function simulateLeverageAtTVL(address vault, uint256 targetTVL)
        external
        view
        returns (uint16 maxLeverageAtTarget, string memory phase);

    /**
     * @notice Get vault utilization metrics
     */
    function getVaultUtilization(address vault)
        external
        view
        returns (uint256 utilizationBps, uint256 totalOI, uint256 tvl, uint256 remainingCapacity);

    /**
     * @notice Calculate withdrawal amount with fees
     */
    function calculateWithdrawalAmount(address vault, address user, uint256 shares)
        external
        view
        returns (uint256 grossAmount, uint256 fee, uint256 netAmount, bool isEarlyWithdrawal);

    /**
     * @notice Calculate pending rewards for a user
     */
    function calculatePendingRewards(address vault, address user)
        external
        view
        returns (uint256 pendingRewards, uint256 lastProcessedDay);
}
