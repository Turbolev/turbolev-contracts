// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../VaultModuleBase.sol";
import "../../libraries/vault/VaultStorageLib.sol";
import "../../libraries/math/PriceImpactLib.sol";
import "../../libraries/vault/VaultConfigLib.sol";

/**
 * @title VaultFunding
 * @notice Price impact module: settles skew fee upfront at order creation.
 * @dev Called via delegatecall from VaultRouter. Uses shared EIP-7201 storage.
 *
 * Responsibilities:
 * - Execution Price Calculation: getExecutionPrice
 * - Impact Fee Settlement: recordImpactFee (called by VaultManager on depositFromBet)
 * - Exposure Tracking: totalLongExposure, totalShortExposure
 * - Impact Config: setImpactConfig, setImpactEnabled
 *
 * Fee Flow:
 *   crowded-side user opens position
 *   → impactFee = positionSize * impactBps / 10000  (notional-based, consistent with imbalance)
 *   → impactFee credited to feePool (LPs receive skew revenue)
 *   → totalFeesCollected incremented for accounting
 *   → betCollateral[positionId] reduced by impactFee (net collateral backing the position)
 *   → executionPrice stored for display only; PnL calculated from openPrice (mark)
 */
contract VaultFunding is VaultModuleBase {
    // ========================================================================
    // EVENTS
    // ========================================================================

    event PriceImpactApplied(
        uint64 indexed positionId,
        address indexed user,
        uint8 direction,
        uint256 markPrice,
        uint256 executionPrice,
        uint256 impactBps,
        uint256 impactFee,
        bool isCrowdedSide,
        uint256 timestamp
    );

    event ImpactConfigUpdated(
        uint16 tier1ImpactBps,
        uint16 tier2ImpactBps,
        uint16 tier3ImpactBps,
        uint16 tier4ImpactBps,
        uint16 tier5ImpactBps
    );

    event ImpactEnabledUpdated(bool enabled);

    // ========================================================================
    // ERRORS
    // ========================================================================

    error InvalidParameters();

    // ========================================================================
    // PRICE IMPACT FUNCTIONS
    // ========================================================================

    /**
     * @notice Calculate execution price and impact fee for a new position
     * @param markPrice Current oracle mark price
     * @param direction Position direction (1 = LONG, 2 = SHORT)
     * @param positionSize Notional position size (collateral * leverage)
     * @return executionPrice Adjusted price for P&L calculation
     * @return impactFee Fee collected by vault (= positionSize * impactBps / 10000)
     * @return impactBps Applied impact in basis points
     * @return isCrowdedSide True if user opened on the crowded (penalized) side
     */
    function getExecutionPrice(uint256 markPrice, uint8 direction, uint256 positionSize)
        external
        view
        returns (uint256 executionPrice, uint256 impactFee, uint256 impactBps, bool isCrowdedSide)
    {
        VaultStorageLib.FundingStorage storage funding = _funding();

        if (!funding.impactEnabled) {
            return (markPrice, 0, 0, false);
        }

        PriceImpactLib.ImpactResult memory result = PriceImpactLib.calculateExecutionPrice(
            markPrice,
            direction,
            funding.totalLongExposure,
            funding.totalShortExposure,
            funding.impactConfig
        );

        impactFee =
            PriceImpactLib.calculateImpactFee(positionSize, result.impactBps, result.isCrowdedSide);

        return (result.executionPrice, impactFee, result.impactBps, result.isCrowdedSide);
    }

    /**
     * @notice Record impact fee collected and route it to feePool (A-01 fix)
     * @dev Impact fee is a real financial penalty on the crowded side — it must be
     *      credited to the vault's feePool so LPs actually receive the skew revenue.
     *      betCollateral for the position is reduced by impactFee so that executePayout
     *      only pays out net collateral (not the fee portion).
     * @param positionId Position ID
     * @param user User address
     * @param direction Position direction
     * @param markPrice Oracle mark price
     * @param executionPrice Adjusted execution price (display only)
     * @param impactBps Applied impact bps
     * @param impactFee Fee amount collected
     * @param isCrowdedSide True if user was on crowded side
     */
    function recordImpactFee(
        uint64 positionId,
        address user,
        uint8 direction,
        uint256 markPrice,
        uint256 executionPrice,
        uint256 impactBps,
        uint256 impactFee,
        bool isCrowdedSide
    ) external nonReentrant onlyPositionManager {
        VaultStorageLib.FundingStorage storage funding = _funding();
        funding.totalImpactFeesCollected += impactFee;

        if (impactFee > 0) {
            VaultStorageLib.CoreStorage storage core = _core();

            // Route impact fee to feePool so LPs actually receive the skew revenue.
            core.feePool += impactFee;
            core.vaultInfo.totalFeesCollected += impactFee;

            // Reduce betCollateral by impactFee so executePayout only pays net collateral.
            // betCollateral was set to netCollateral (after openFee) in depositFromBet;
            // subtracting impactFee here gives the true "user's skin in the game".
            if (core.betCollateral[positionId] >= impactFee) {
                core.betCollateral[positionId] -= impactFee;
            }
        }

        emit PriceImpactApplied(
            positionId,
            user,
            direction,
            markPrice,
            executionPrice,
            impactBps,
            impactFee,
            isCrowdedSide,
            block.timestamp
        );
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /**
     * @notice Get current price impact rate based on OI imbalance
     * @return impactBps Current impact rate in basis points
     * @return isLongDominant True if longs are dominant
     * @return imbalanceBps Current imbalance in basis points
     */
    function getCurrentImpactRate()
        external
        view
        returns (uint256 impactBps, bool isLongDominant, uint256 imbalanceBps)
    {
        VaultStorageLib.FundingStorage storage funding = _funding();

        if (!funding.impactEnabled) {
            return (0, false, 0);
        }

        if (funding.totalLongExposure + funding.totalShortExposure == 0) {
            return (0, false, 0);
        }

        bool hasCounterparty;
        (imbalanceBps, isLongDominant, hasCounterparty) = PriceImpactLib.calculateImbalance(
            funding.totalLongExposure, funding.totalShortExposure
        );

        impactBps = PriceImpactLib.getTieredImpactBps(imbalanceBps, funding.impactConfig);
    }

    /**
     * @notice Get directional exposure
     * @return longExposure Total long exposure
     * @return shortExposure Total short exposure
     * @return netExposure Net exposure (absolute difference)
     * @return imbalanceBps Imbalance in basis points
     * @return maxDirectionalExposureBps Max allowed exposure in bps
     * @return longsAreDominant True if longs are dominant
     */
    function getDirectionalExposure()
        external
        view
        returns (
            uint256 longExposure,
            uint256 shortExposure,
            uint256 netExposure,
            uint256 imbalanceBps,
            uint256 maxDirectionalExposureBps,
            bool longsAreDominant
        )
    {
        VaultStorageLib.FundingStorage storage funding = _funding();
        VaultStorageLib.RiskStorage storage risk = _risk();

        longExposure = funding.totalLongExposure;
        shortExposure = funding.totalShortExposure;

        if (longExposure >= shortExposure) {
            netExposure = longExposure - shortExposure;
            longsAreDominant = true;
        } else {
            netExposure = shortExposure - longExposure;
            longsAreDominant = false;
        }

        bool hasCounterparty;
        (imbalanceBps, longsAreDominant, hasCounterparty) =
            PriceImpactLib.calculateImbalance(longExposure, shortExposure);

        maxDirectionalExposureBps = risk.maxDirectionalExposureBps;
    }

    /**
     * @notice Get price impact statistics
     * @return longExposure Total long OI
     * @return shortExposure Total short OI
     * @return currentImpactBps Current impact rate in bps
     * @return isLongDominant True if longs are dominant
     * @return imbalanceBps Current imbalance in bps
     * @return totalFeesCollected Lifetime impact fees collected by vault
     */
    function getImpactStats()
        external
        view
        returns (
            uint256 longExposure,
            uint256 shortExposure,
            uint256 currentImpactBps,
            bool isLongDominant,
            uint256 imbalanceBps,
            uint256 totalFeesCollected
        )
    {
        VaultStorageLib.FundingStorage storage funding = _funding();

        longExposure = funding.totalLongExposure;
        shortExposure = funding.totalShortExposure;
        totalFeesCollected = funding.totalImpactFeesCollected;

        bool hasCounterparty;
        (imbalanceBps, isLongDominant, hasCounterparty) =
            PriceImpactLib.calculateImbalance(longExposure, shortExposure);

        currentImpactBps = PriceImpactLib.getTieredImpactBps(imbalanceBps, funding.impactConfig);
    }

    // ========================================================================
    // EXPOSURE GETTERS (for compatibility)
    // ========================================================================

    function totalLongExposure() external view returns (uint256) {
        return _funding().totalLongExposure;
    }

    function totalShortExposure() external view returns (uint256) {
        return _funding().totalShortExposure;
    }

    function isImpactEnabled() external view returns (bool) {
        return _funding().impactEnabled;
    }

    function totalImpactFeesCollected() external view returns (uint256) {
        return _funding().totalImpactFeesCollected;
    }

    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================

    /**
     * @notice Set price impact tier configuration
     * @param tier1ImpactBps Impact for < 20% imbalance
     * @param tier2ImpactBps Impact for 20-40% imbalance
     * @param tier3ImpactBps Impact for 40-60% imbalance
     * @param tier4ImpactBps Impact for 60-80% imbalance
     * @param tier5ImpactBps Impact for > 80% imbalance
     */
    function setImpactConfig(
        uint16 tier1ImpactBps,
        uint16 tier2ImpactBps,
        uint16 tier3ImpactBps,
        uint16 tier4ImpactBps,
        uint16 tier5ImpactBps
    ) external nonReentrant onlyVaultManagerOrHelper {
        VaultStorageLib.FundingStorage storage funding = _funding();

        PriceImpactLib.ImpactConfig memory newConfig = PriceImpactLib.ImpactConfig({
            tier1ImpactBps: tier1ImpactBps,
            tier2ImpactBps: tier2ImpactBps,
            tier3ImpactBps: tier3ImpactBps,
            tier4ImpactBps: tier4ImpactBps,
            tier5ImpactBps: tier5ImpactBps,
            isEnabled: funding.impactEnabled
        });

        if (!PriceImpactLib.validateConfig(newConfig)) {
            revert InvalidParameters();
        }

        funding.impactConfig = newConfig;

        emit ImpactConfigUpdated(
            tier1ImpactBps, tier2ImpactBps, tier3ImpactBps, tier4ImpactBps, tier5ImpactBps
        );
    }

    /**
     * @notice Enable or disable price impact
     * @param enabled True to enable price impact
     */
    function setImpactEnabled(bool enabled) external nonReentrant onlyVaultManagerOrHelper {
        VaultStorageLib.FundingStorage storage funding = _funding();
        funding.impactEnabled = enabled;
        funding.impactConfig.isEnabled = enabled;
        emit ImpactEnabledUpdated(enabled);
    }

    /**
     * @notice Get price impact configuration
     */
    function getImpactConfig()
        external
        view
        returns (
            uint16 tier1ImpactBps,
            uint16 tier2ImpactBps,
            uint16 tier3ImpactBps,
            uint16 tier4ImpactBps,
            uint16 tier5ImpactBps
        )
    {
        VaultStorageLib.FundingStorage storage funding = _funding();
        return (
            funding.impactConfig.tier1ImpactBps,
            funding.impactConfig.tier2ImpactBps,
            funding.impactConfig.tier3ImpactBps,
            funding.impactConfig.tier4ImpactBps,
            funding.impactConfig.tier5ImpactBps
        );
    }
}
