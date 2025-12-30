// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../interfaces/IVaultRouter.sol";
import "../interfaces/IVaultManager.sol";
import "../interfaces/IPriceFeedManager.sol";
import "../libraries/VaultRiskLib.sol";
import "../libraries/FundingRateLib.sol";
import "../libraries/MathLib.sol";

/**
 * @title VaultViewerModular
 * @notice External view-only contract for querying vault-modular (VaultRouter) data
 * @dev Contains both single-vault queries and aggregated multi-vault queries
 *      Frontend/backend can call this contract directly
 *      Compatible with VaultRouter (vault-modular system)
 */
contract VaultViewerModular {
    // ========================================================================
    // CONSTANTS
    // ========================================================================

    uint256 public constant MAX_PRICE_AGE = 3600; // 1 hour

    // ========================================================================
    // STATE VARIABLES
    // ========================================================================

    /// @notice VaultManager contract address for aggregated queries
    address public vaultManager;

    /// @notice PriceFeedManager contract address for USD calculations
    address public priceFeedManager;

    // ========================================================================
    // CONSTRUCTOR
    // ========================================================================

    /**
     * @notice Constructor
     * @param _vaultManager VaultManager contract address
     * @param _priceFeedManager PriceFeedManager contract address (can be address(0))
     */
    constructor(address _vaultManager, address _priceFeedManager) {
        vaultManager = _vaultManager;
        priceFeedManager = _priceFeedManager;
    }

    // ========================================================================
    // TOTAL OI FUNCTIONS
    // ========================================================================

    /**
     * @notice Get detailed breakdown of OI utilization
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
        )
    {
        IVaultRouter v = IVaultRouter(vault);
        IVaultRouter.VaultInfo memory info = v.getVaultInfo();

        tvl = info.totalLiquidity;
        longOI = v.totalLongExposure();
        shortOI = v.totalShortExposure();
        totalOI = longOI + shortOI;

        // Get tier config
        (
            uint16 fixedMultiplier,
            uint256 t1Threshold,
            uint256 t2Threshold,
            uint256 t3Threshold,
            uint16 t1Mult,
            uint16 t2Mult,
            uint16 t3Mult,
            uint16 t4Mult
        ) = v.getTotalOITierConfig();

        // Calculate current multiplier
        currentMultiplierBps = _calculateRiskMultiplier(
            tvl,
            fixedMultiplier,
            t1Threshold,
            t2Threshold,
            t3Threshold,
            t1Mult,
            t2Mult,
            t3Mult,
            t4Mult
        );

        // Determine current tier
        if (t1Threshold == 0 && t2Threshold == 0 && t3Threshold == 0) {
            currentTier = 0; // Fixed multiplier mode
        } else if (tvl < t1Threshold) {
            currentTier = 1;
        } else if (tvl < t2Threshold) {
            currentTier = 2;
        } else if (tvl < t3Threshold) {
            currentTier = 3;
        } else {
            currentTier = 4;
        }

        if (tvl > 0) {
            maxOI = (tvl * currentMultiplierBps) / MathLib.BASIS_POINTS;

            if (maxOI > 0) {
                utilizationBps = (totalOI * MathLib.BASIS_POINTS) / maxOI;
            }

            if (totalOI < maxOI) {
                remainingCapacity = maxOI - totalOI;
            }
        }
    }

    /**
     * @notice Get total OI cap status
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
        )
    {
        IVaultRouter v = IVaultRouter(vault);
        IVaultRouter.VaultInfo memory info = v.getVaultInfo();
        uint256 tvl = info.totalLiquidity;

        // Get tier config and calculate multiplier
        (
            uint16 fixedMultiplier,
            uint256 t1,
            uint256 t2,
            uint256 t3,
            uint16 m1,
            uint16 m2,
            uint16 m3,
            uint16 m4
        ) = v.getTotalOITierConfig();

        currentMultiplierBps =
            _calculateRiskMultiplier(tvl, fixedMultiplier, t1, t2, t3, m1, m2, m3, m4);

        if (tvl > 0) {
            maxTotalOI = (tvl * currentMultiplierBps) / MathLib.BASIS_POINTS;
            currentTotalOI = v.totalLongExposure() + v.totalShortExposure();

            if (maxTotalOI > 0) {
                utilizationBps = (currentTotalOI * MathLib.BASIS_POINTS) / maxTotalOI;
            }

            canOpenMore = currentTotalOI < maxTotalOI;
        }
    }

    // ========================================================================
    // LEVERAGE FUNCTIONS
    // ========================================================================

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
        )
    {
        IVaultRouter v = IVaultRouter(vault);
        IVaultRouter.VaultInfo memory info = v.getVaultInfo();
        uint256 tvl = info.totalLiquidity;

        // Get leverage config
        (uint256 t1Threshold, uint256 t2Threshold, uint16 t1Max, uint16 t2Max, uint16 t3Max) =
            v.getLeverageTierConfig();

        baseMaxLeverage = _calculateMaxLeverage(tvl, t1Threshold, t2Threshold, t1Max, t2Max, t3Max);

        // Get effective leverage from VaultRiskLib
        (effectiveMaxLeverage, utilizationBps, utilizationTier) =
            VaultRiskLib.getEffectiveMaxLeverage(
                tvl, v.totalLongExposure(), v.totalShortExposure(), baseMaxLeverage
            );

        // Set tier description
        if (utilizationTier == 1) {
            tierDescription = "Normal (0-30% utilization): Full leverage";
        } else if (utilizationTier == 2) {
            tierDescription = "Moderate (30-60% utilization): 50% leverage";
        } else if (utilizationTier == 3) {
            tierDescription = "High (60-80% utilization): 20% leverage";
        } else {
            tierDescription = "Emergency (80%+ utilization): 4% leverage";
        }
    }

    /**
     * @notice Get vault's current max leverage based on TVL
     */
    function getVaultMaxLeverage(address vault)
        external
        view
        returns (uint16 maxLeverage, uint256 currentTVL, string memory currentPhase)
    {
        IVaultRouter v = IVaultRouter(vault);
        IVaultRouter.VaultInfo memory info = v.getVaultInfo();
        currentTVL = info.totalLiquidity;

        (uint256 t1Threshold, uint256 t2Threshold, uint16 t1Max, uint16 t2Max, uint16 t3Max) =
            v.getLeverageTierConfig();

        maxLeverage =
            _calculateMaxLeverage(currentTVL, t1Threshold, t2Threshold, t1Max, t2Max, t3Max);

        if (currentTVL < t1Threshold) {
            currentPhase = "Launch";
        } else if (currentTVL < t2Threshold) {
            currentPhase = "Growth";
        } else {
            currentPhase = "Mature";
        }
    }

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
        )
    {
        return IVaultRouter(vault).getLeverageTierConfig();
    }

    /**
     * @notice Check if leverage is allowed
     */
    function checkLeverageAllowed(address vault, uint16 requestedLeverage)
        external
        view
        returns (bool isAllowed, uint16 effectiveMaxLeverage, string memory reason)
    {
        IVaultRouter v = IVaultRouter(vault);
        IVaultRouter.VaultInfo memory info = v.getVaultInfo();
        uint256 tvl = info.totalLiquidity;

        (uint256 t1Threshold, uint256 t2Threshold, uint16 t1Max, uint16 t2Max, uint16 t3Max) =
            v.getLeverageTierConfig();

        uint16 baseMaxLeverage =
            _calculateMaxLeverage(tvl, t1Threshold, t2Threshold, t1Max, t2Max, t3Max);

        (effectiveMaxLeverage,,) = VaultRiskLib.getEffectiveMaxLeverage(
            tvl, v.totalLongExposure(), v.totalShortExposure(), baseMaxLeverage
        );

        if (requestedLeverage > effectiveMaxLeverage) {
            return (false, effectiveMaxLeverage, "Exceeds effective max leverage");
        }

        return (true, effectiveMaxLeverage, "");
    }

    /**
     * @notice Simulate leverage at different TVL
     */
    function simulateLeverageAtTVL(address vault, uint256 targetTVL)
        external
        view
        returns (uint16 maxLeverageAtTarget, string memory phase)
    {
        (uint256 t1Threshold, uint256 t2Threshold, uint16 t1Max, uint16 t2Max, uint16 t3Max) =
            IVaultRouter(vault).getLeverageTierConfig();

        maxLeverageAtTarget =
            _calculateMaxLeverage(targetTVL, t1Threshold, t2Threshold, t1Max, t2Max, t3Max);

        if (targetTVL < t1Threshold) {
            phase = "Launch";
        } else if (targetTVL < t2Threshold) {
            phase = "Growth";
        } else {
            phase = "Mature";
        }
    }

    // ========================================================================
    // DIRECTIONAL EXPOSURE FUNCTIONS
    // ========================================================================

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
        )
    {
        IVaultRouter v = IVaultRouter(vault);
        IVaultRouter.VaultInfo memory info = v.getVaultInfo();

        longExposure = v.totalLongExposure();
        shortExposure = v.totalShortExposure();

        if (longExposure > shortExposure) {
            netExposure = longExposure - shortExposure;
            isLongBias = true;
        } else {
            netExposure = shortExposure - longExposure;
            isLongBias = false;
        }

        uint16 maxDirectionalBps = v.maxDirectionalExposureBps();
        if (info.totalLiquidity > 0 && maxDirectionalBps > 0) {
            maxExposure = (info.totalLiquidity * maxDirectionalBps) / MathLib.BASIS_POINTS;
            if (maxExposure > 0) {
                netUtilization = (netExposure * MathLib.BASIS_POINTS) / maxExposure;
            }
        }
    }

    // ========================================================================
    // FUNDING RATE FUNCTIONS
    // ========================================================================

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
        )
    {
        IVaultRouter v = IVaultRouter(vault);

        (cumulativeLongRate, cumulativeShortRate) = v.getCumulativeFundingRates();
        lastUpdateTime = v.lastFundingUpdateTime();

        bool hasCounterparty;
        (imbalanceBps, longsPayShorts, hasCounterparty) =
            FundingRateLib.calculateImbalance(v.totalLongExposure(), v.totalShortExposure());

        // Get funding config and create struct
        (uint16 t1Rate, uint16 t2Rate, uint16 t3Rate, uint16 t4Rate, uint16 t5Rate) =
            v.getFundingConfig();

        FundingRateLib.FundingConfig memory config = FundingRateLib.FundingConfig({
            tier1RateBps: t1Rate,
            tier2RateBps: t2Rate,
            tier3RateBps: t3Rate,
            tier4RateBps: t4Rate,
            tier5RateBps: t5Rate,
            isEnabled: true // Assume enabled if we're querying
        });
        currentHourlyRateBps = FundingRateLib.getHourlyRate(imbalanceBps, config);
    }

    /**
     * @notice Check if position is liquidatable due to funding
     * @param vault Vault address
     * @param collateral Position collateral
     * @param entryRateLong Entry funding rate for long
     * @param entryRateShort Entry funding rate for short
     * @param positionSize Position size
     * @param direction Position direction (1 = LONG, 2 = SHORT)
     * @param maintenanceMarginRatio Maintenance margin ratio in bps
     * @return isLiquidatable True if position should be liquidated
     * @return fundingOwed Amount of funding owed
     * @return effectiveCollateral Collateral after funding deduction
     */
    function checkFundingLiquidation(
        address vault,
        uint256 collateral,
        int256 entryRateLong,
        int256 entryRateShort,
        uint256 positionSize,
        uint8 direction,
        uint256 maintenanceMarginRatio
    ) external view returns (bool isLiquidatable, int256 fundingOwed, uint256 effectiveCollateral) {
        IVaultRouter v = IVaultRouter(vault);

        if (!v.fundingEnabled()) {
            return (false, 0, collateral);
        }

        // Get cumulative rates from vault
        (int256 cumulativeLongRate, int256 cumulativeShortRate) = v.getCumulativeFundingRates();

        // Calculate funding owed using library (zero-sum is baked into cumulative rates)
        fundingOwed = FundingRateLib.calculatePositionFunding(
            entryRateLong,
            entryRateShort,
            cumulativeLongRate,
            cumulativeShortRate,
            positionSize,
            direction
        );

        // Calculate effective collateral
        bool isNegative;
        (effectiveCollateral, isNegative) =
            FundingRateLib.calculateEffectiveCollateral(collateral, fundingOwed);

        if (isNegative) {
            return (true, fundingOwed, 0);
        }

        // Check if below maintenance margin
        isLiquidatable =
            FundingRateLib.checkFundingLiquidation(collateral, fundingOwed, maintenanceMarginRatio);

        return (isLiquidatable, fundingOwed, effectiveCollateral);
    }

    /**
     * @notice Calculate position funding owed
     * @dev Helper function using vault's cumulative rates
     */
    function calculatePositionFundingOwed(
        address vault,
        int256 entryRateLong,
        int256 entryRateShort,
        uint256 positionSize,
        uint8 direction
    ) external view returns (int256 fundingOwed) {
        IVaultRouter v = IVaultRouter(vault);

        if (!v.fundingEnabled()) {
            return 0;
        }

        (int256 cumulativeLongRate, int256 cumulativeShortRate) = v.getCumulativeFundingRates();

        return FundingRateLib.calculatePositionFunding(
            entryRateLong,
            entryRateShort,
            cumulativeLongRate,
            cumulativeShortRate,
            positionSize,
            direction
        );
    }

    /**
     * @notice Get current hourly funding rate based on imbalance
     */
    function getCurrentHourlyFundingRate(address vault)
        external
        view
        returns (uint256 rateBps, bool longsPayShorts, uint256 imbalanceBps, bool hasCounterparty)
    {
        IVaultRouter v = IVaultRouter(vault);

        (imbalanceBps, longsPayShorts, hasCounterparty) =
            FundingRateLib.calculateImbalance(v.totalLongExposure(), v.totalShortExposure());

        (uint16 t1Rate, uint16 t2Rate, uint16 t3Rate, uint16 t4Rate, uint16 t5Rate) =
            v.getFundingConfig();

        FundingRateLib.FundingConfig memory config = FundingRateLib.FundingConfig({
            tier1RateBps: t1Rate,
            tier2RateBps: t2Rate,
            tier3RateBps: t3Rate,
            tier4RateBps: t4Rate,
            tier5RateBps: t5Rate,
            isEnabled: true
        });

        rateBps = FundingRateLib.getHourlyRate(imbalanceBps, config);
    }

    // ========================================================================
    // SIMULATION FUNCTIONS
    // ========================================================================

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
        )
    {
        IVaultRouter v = IVaultRouter(vault);
        IVaultRouter.VaultInfo memory info = v.getVaultInfo();
        uint256 tvl = info.totalLiquidity;

        if (tvl == 0) {
            return (false, 0, 0, 0, "Vault has no liquidity");
        }

        (
            uint16 fixedMultiplier,
            uint256 t1,
            uint256 t2,
            uint256 t3,
            uint16 m1,
            uint16 m2,
            uint16 m3,
            uint16 m4
        ) = v.getTotalOITierConfig();

        uint16 currentMultiplier =
            _calculateRiskMultiplier(tvl, fixedMultiplier, t1, t2, t3, m1, m2, m3, m4);
        maxTotalOI = (tvl * currentMultiplier) / MathLib.BASIS_POINTS;
        currentTotalOI = v.totalLongExposure() + v.totalShortExposure();

        uint256 newTotalOI = currentTotalOI + positionSize;
        if (newTotalOI > maxTotalOI) {
            uint256 available = maxTotalOI > currentTotalOI ? maxTotalOI - currentTotalOI : 0;
            return (false, maxTotalOI, currentTotalOI, available, "Exceeds max total OI cap");
        }

        remainingCapacity = maxTotalOI - newTotalOI;
        return (true, maxTotalOI, currentTotalOI, remainingCapacity, "");
    }

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
        )
    {
        IVaultRouter v = IVaultRouter(vault);

        (
            uint16 fixedMultiplier,
            uint256 t1,
            uint256 t2,
            uint256 t3,
            uint16 m1,
            uint16 m2,
            uint16 m3,
            uint16 m4
        ) = v.getTotalOITierConfig();

        newMultiplierBps =
            _calculateRiskMultiplier(newTVL, fixedMultiplier, t1, t2, t3, m1, m2, m3, m4);

        if (newTVL > 0) {
            newMaxTotalOI = (newTVL * newMultiplierBps) / MathLib.BASIS_POINTS;
        }

        currentTotalOI = v.totalLongExposure() + v.totalShortExposure();
        wouldExceedCap = currentTotalOI > newMaxTotalOI;
    }

    /**
     * @notice Get vault utilization metrics
     */
    function getVaultUtilization(address vault)
        external
        view
        returns (uint256 utilizationBps, uint256 totalOI, uint256 tvl, uint256 remainingCapacity)
    {
        IVaultRouter v = IVaultRouter(vault);
        IVaultRouter.VaultInfo memory info = v.getVaultInfo();

        tvl = info.totalLiquidity;
        totalOI = v.totalLongExposure() + v.totalShortExposure();

        if (tvl > 0) {
            utilizationBps = (totalOI * MathLib.BASIS_POINTS) / tvl;
            remainingCapacity = totalOI < tvl ? tvl - totalOI : 0;
        }
    }

    // ========================================================================
    // LP FUNCTIONS
    // ========================================================================

    /**
     * @notice Calculate withdrawal amount with fees
     */
    function calculateWithdrawalAmount(address vault, address user, uint256 shares)
        external
        view
        returns (uint256 grossAmount, uint256 fee, uint256 netAmount, bool isEarlyWithdrawal)
    {
        IVaultRouter v = IVaultRouter(vault);
        IVaultRouter.VaultInfo memory info = v.getVaultInfo();
        IVaultRouter.LPPosition memory lpPos = v.getLPPosition(user);

        if (shares > lpPos.shares) {
            shares = lpPos.shares;
        }

        if (info.totalShares == 0) {
            return (0, 0, 0, false);
        }

        grossAmount = (shares * info.totalLiquidity) / info.totalShares;

        (, uint16 earlyWithdrawalFee, uint256 minLockPeriod) = v.getFeeConfig();

        uint256 lockEndTime = lpPos.stakedAt + minLockPeriod;
        isEarlyWithdrawal = block.timestamp < lockEndTime;

        if (isEarlyWithdrawal && info.isGraduated) {
            fee = (grossAmount * earlyWithdrawalFee) / MathLib.BASIS_POINTS;
            netAmount = grossAmount - fee;
        } else {
            fee = 0;
            netAmount = grossAmount;
        }
    }

    /**
     * @notice Calculate pending rewards for a user
     */
    function calculatePendingRewards(address vault, address user)
        external
        view
        returns (uint256 pendingRewards, uint256 lastProcessedDay)
    {
        IVaultRouter v = IVaultRouter(vault);
        IVaultRouter.LPPosition memory lpPos = v.getLPPosition(user);

        if (lpPos.shares == 0) {
            return (0, 0);
        }

        pendingRewards = v.claimableRewards(user);
        lastProcessedDay = lpPos.lastProcessedDay;
    }

    // ========================================================================
    // LP ARRAY VIEW FUNCTIONS
    // ========================================================================

    /**
     * @notice Get total number of active LPs
     * @param vault Address of the vault
     * @return count Number of LPs currently in the vault
     */
    function getVaultLPsCount(address vault) external view returns (uint256 count) {
        return IVaultRouter(vault).getVaultLPsLength();
    }

    /**
     * @notice Get LP address at specific index
     * @param vault Address of the vault
     * @param index Index in the LP array (0-based)
     * @return lp LP address at the given index
     */
    function getVaultLPAt(address vault, uint256 index) external view returns (address lp) {
        return IVaultRouter(vault).vaultLPs(index);
    }

    /**
     * @notice Check if address is an active LP
     * @param vault Address of the vault
     * @param account Address to check
     * @return isLP True if address is in the LP array
     */
    function isVaultLP(address vault, address account) external view returns (bool isLP) {
        return IVaultRouter(vault).lpIndex(account) != 0;
    }

    /**
     * @notice Get all active LPs (use with caution for large arrays)
     * @param vault Address of the vault
     * @return lps Array of all LP addresses
     * @dev May be gas-expensive for large LP counts
     */
    function getAllVaultLPs(address vault) external view returns (address[] memory lps) {
        IVaultRouter v = IVaultRouter(vault);
        uint256 count = v.getVaultLPsLength();
        lps = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            lps[i] = v.vaultLPs(i);
        }
    }

    /**
     * @notice Get effective queue length (items not yet processed)
     * @param vault Address of the vault
     * @return effectiveLength Number of pending payout items
     */
    function getEffectiveQueueLength(address vault)
        external
        view
        returns (uint256 effectiveLength)
    {
        IVaultRouter v = IVaultRouter(vault);
        uint256 startIdx = v.queueStartIndex();
        uint256 totalLength = v.getPendingPayoutQueueLength();

        if (totalLength > startIdx) {
            return totalLength - startIdx;
        }
        return 0;
    }

    // ========================================================================
    // AGGREGATED VIEW FUNCTIONS
    // ========================================================================

    /**
     * @notice Get total liquidity across all vaults
     * @return total Total liquidity in native token equivalent
     */
    function getTotalLiquidity() external view returns (uint256 total) {
        if (vaultManager == address(0)) return 0;

        address[] memory vaults = IVaultManager(vaultManager).getAllVaults();

        for (uint256 i = 0; i < vaults.length; i++) {
            IVaultManager.VaultInfo memory info =
                IVaultManager(vaultManager).getVaultInfo(vaults[i]);
            if (!info.isActive) continue;

            try IVaultRouter(vaults[i]).getVaultInfo() returns (
                IVaultRouter.VaultInfo memory vInfo
            ) {
                total += vInfo.totalLiquidity;
            } catch {
                continue;
            }
        }
        return total;
    }

    /**
     * @notice Get total USD value across all vaults
     * @return totalUSD Total value in USD (18 decimals)
     */
    function getTotalValueUSD() external view returns (uint256 totalUSD) {
        if (vaultManager == address(0) || priceFeedManager == address(0)) {
            return 0;
        }

        address[] memory vaults = IVaultManager(vaultManager).getAllVaults();

        for (uint256 i = 0; i < vaults.length; i++) {
            IVaultManager.VaultInfo memory info =
                IVaultManager(vaultManager).getVaultInfo(vaults[i]);
            if (!info.isActive) continue;

            try IVaultRouter(vaults[i]).getVaultInfo() returns (
                IVaultRouter.VaultInfo memory vInfo
            ) {
                // Get price from PriceFeedManager
                try IPriceFeedManager(priceFeedManager)
                    .getPrice(info.projectToken, MAX_PRICE_AGE) returns (
                    uint256 price, uint256
                ) {
                    if (price > 0) {
                        totalUSD += (vInfo.totalLiquidity * price) / 1e18;
                    }
                } catch {
                    continue;
                }
            } catch {
                continue;
            }
        }
        return totalUSD;
    }

    /**
     * @notice Get funding statistics for all vaults
     * @return vaultAddresses Array of vault addresses
     * @return longRates Array of cumulative long rates
     * @return shortRates Array of cumulative short rates
     * @return imbalances Array of current imbalances in bps
     * @return hourlyRates Array of current hourly rates in bps
     */
    function getAllVaultsFundingStats()
        external
        view
        returns (
            address[] memory vaultAddresses,
            int256[] memory longRates,
            int256[] memory shortRates,
            uint256[] memory imbalances,
            uint256[] memory hourlyRates
        )
    {
        if (vaultManager == address(0)) {
            return (
                new address[](0),
                new int256[](0),
                new int256[](0),
                new uint256[](0),
                new uint256[](0)
            );
        }

        vaultAddresses = IVaultManager(vaultManager).getAllVaults();
        uint256 length = vaultAddresses.length;

        longRates = new int256[](length);
        shortRates = new int256[](length);
        imbalances = new uint256[](length);
        hourlyRates = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            try IVaultRouter(vaultAddresses[i]).getCumulativeFundingRates() returns (
                int256 cumulativeLong, int256 cumulativeShort
            ) {
                longRates[i] = cumulativeLong;
                shortRates[i] = cumulativeShort;

                // Calculate current imbalance and rate
                uint256 longExp = IVaultRouter(vaultAddresses[i]).totalLongExposure();
                uint256 shortExp = IVaultRouter(vaultAddresses[i]).totalShortExposure();

                (uint256 imbalanceBps,,) = FundingRateLib.calculateImbalance(longExp, shortExp);
                imbalances[i] = imbalanceBps;

                // Get funding config and calculate hourly rate
                try IVaultRouter(vaultAddresses[i]).getFundingConfig() returns (
                    uint16 t1Rate, uint16 t2Rate, uint16 t3Rate, uint16 t4Rate, uint16 t5Rate
                ) {
                    FundingRateLib.FundingConfig memory config = FundingRateLib.FundingConfig({
                        tier1RateBps: t1Rate,
                        tier2RateBps: t2Rate,
                        tier3RateBps: t3Rate,
                        tier4RateBps: t4Rate,
                        tier5RateBps: t5Rate,
                        isEnabled: true
                    });
                    hourlyRates[i] = FundingRateLib.getHourlyRate(imbalanceBps, config);
                } catch {
                    hourlyRates[i] = 0;
                }
            } catch {
                // Default values on failure
                longRates[i] = 0;
                shortRates[i] = 0;
                imbalances[i] = 0;
                hourlyRates[i] = 0;
            }
        }

        return (vaultAddresses, longRates, shortRates, imbalances, hourlyRates);
    }

    /**
     * @notice Get funding info for a specific vault by project token
     * @param projectToken Project token address
     * @return cumulativeLongRate Cumulative long rate
     * @return cumulativeShortRate Cumulative short rate
     * @return lastUpdateTime Last funding update time
     * @return currentHourlyRateBps Current hourly rate in bps
     * @return longsPayShorts True if longs pay shorts
     * @return imbalanceBps Current imbalance in bps
     */
    function getVaultFundingInfo(address projectToken)
        external
        view
        returns (
            int256 cumulativeLongRate,
            int256 cumulativeShortRate,
            uint256 lastUpdateTime,
            uint256 currentHourlyRateBps,
            bool longsPayShorts,
            uint256 imbalanceBps
        )
    {
        if (vaultManager == address(0)) return (0, 0, 0, 0, false, 0);

        address vault = IVaultManager(vaultManager).getVault(projectToken);
        if (vault == address(0)) return (0, 0, 0, 0, false, 0);

        IVaultRouter v = IVaultRouter(vault);

        (cumulativeLongRate, cumulativeShortRate) = v.getCumulativeFundingRates();
        lastUpdateTime = v.lastFundingUpdateTime();

        // Calculate current imbalance
        uint256 longExp = v.totalLongExposure();
        uint256 shortExp = v.totalShortExposure();
        (imbalanceBps, longsPayShorts,) = FundingRateLib.calculateImbalance(longExp, shortExp);

        // Get funding config and calculate hourly rate
        (uint16 t1Rate, uint16 t2Rate, uint16 t3Rate, uint16 t4Rate, uint16 t5Rate) =
            v.getFundingConfig();

        FundingRateLib.FundingConfig memory config = FundingRateLib.FundingConfig({
            tier1RateBps: t1Rate,
            tier2RateBps: t2Rate,
            tier3RateBps: t3Rate,
            tier4RateBps: t4Rate,
            tier5RateBps: t5Rate,
            isEnabled: true
        });
        currentHourlyRateBps = FundingRateLib.getHourlyRate(imbalanceBps, config);
    }

    // ========================================================================
    // HEALTH METRICS
    // ========================================================================

    /**
     * @notice Vault health metrics struct
     */
    struct VaultHealthMetrics {
        address vault;
        address projectToken;
        uint256 totalLiquidity;
        uint256 totalShares;
        uint256 totalLongExposure;
        uint256 totalShortExposure;
        uint256 netExposure;
        uint256 utilizationBps;
        uint256 pendingPayoutsCount;
        uint256 pendingPayoutsValue;
        bool isPaused;
        bool isActive;
        bool isFundingEnabled;
        uint256 healthScore; // 0-10000 (higher is healthier)
    }

    /**
     * @notice Get health metrics for a specific vault
     * @param projectToken Project token address
     * @return metrics VaultHealthMetrics struct
     */
    function getVaultHealthMetrics(address projectToken)
        external
        view
        returns (VaultHealthMetrics memory metrics)
    {
        if (vaultManager == address(0)) return metrics;

        address vault = IVaultManager(vaultManager).getVault(projectToken);
        if (vault == address(0)) return metrics;

        return _getVaultHealthMetrics(vault);
    }

    /**
     * @notice Get health metrics for all vaults
     * @return allMetrics Array of VaultHealthMetrics
     */
    function getAllVaultsHealthMetrics()
        external
        view
        returns (VaultHealthMetrics[] memory allMetrics)
    {
        if (vaultManager == address(0)) return new VaultHealthMetrics[](0);

        address[] memory vaults = IVaultManager(vaultManager).getAllVaults();
        allMetrics = new VaultHealthMetrics[](vaults.length);

        for (uint256 i = 0; i < vaults.length; i++) {
            allMetrics[i] = _getVaultHealthMetrics(vaults[i]);
        }

        return allMetrics;
    }

    /**
     * @notice Get aggregated health metrics across all vaults
     * @return totalLiquidity Total liquidity across all vaults
     * @return totalLongExposure Total long exposure across all vaults
     * @return totalShortExposure Total short exposure across all vaults
     * @return totalNetExposure Total net exposure across all vaults
     * @return avgUtilizationBps Average utilization in bps
     * @return avgHealthScore Average health score (0-10000)
     * @return pausedVaultsCount Number of paused vaults
     * @return unhealthyVaultsCount Number of vaults with health score < 5000
     */
    function getAggregatedHealthMetrics()
        external
        view
        returns (
            uint256 totalLiquidity,
            uint256 totalLongExposure,
            uint256 totalShortExposure,
            uint256 totalNetExposure,
            uint256 avgUtilizationBps,
            uint256 avgHealthScore,
            uint256 pausedVaultsCount,
            uint256 unhealthyVaultsCount
        )
    {
        if (vaultManager == address(0)) {
            return (0, 0, 0, 0, 0, 0, 0, 0);
        }

        address[] memory vaults = IVaultManager(vaultManager).getAllVaults();
        uint256 totalUtilization = 0;
        uint256 totalHealthScore = 0;
        uint256 activeVaultsCount = 0;

        for (uint256 i = 0; i < vaults.length; i++) {
            VaultHealthMetrics memory metrics = _getVaultHealthMetrics(vaults[i]);

            totalLiquidity += metrics.totalLiquidity;
            totalLongExposure += metrics.totalLongExposure;
            totalShortExposure += metrics.totalShortExposure;
            totalNetExposure += metrics.netExposure;
            totalUtilization += metrics.utilizationBps;
            totalHealthScore += metrics.healthScore;

            if (metrics.isPaused) {
                pausedVaultsCount++;
            }

            if (metrics.healthScore < 5000) {
                unhealthyVaultsCount++;
            }

            if (metrics.isActive) {
                activeVaultsCount++;
            }
        }

        // Calculate averages
        if (activeVaultsCount > 0) {
            avgUtilizationBps = totalUtilization / activeVaultsCount;
            avgHealthScore = totalHealthScore / activeVaultsCount;
        }

        return (
            totalLiquidity,
            totalLongExposure,
            totalShortExposure,
            totalNetExposure,
            avgUtilizationBps,
            avgHealthScore,
            pausedVaultsCount,
            unhealthyVaultsCount
        );
    }

    /**
     * @notice Internal function to get health metrics for a vault
     * @param vault Vault address
     * @return metrics VaultHealthMetrics struct
     */
    function _getVaultHealthMetrics(address vault)
        internal
        view
        returns (VaultHealthMetrics memory metrics)
    {
        IVaultManager.VaultInfo memory managerInfo = IVaultManager(vaultManager).getVaultInfo(vault);

        metrics.vault = vault;
        metrics.projectToken = managerInfo.projectToken;
        metrics.isActive = managerInfo.isActive;

        IVaultRouter v = IVaultRouter(vault);

        // Get vault info
        try v.getVaultInfo() returns (IVaultRouter.VaultInfo memory info) {
            metrics.totalLiquidity = info.totalLiquidity;
            metrics.totalShares = info.totalShares;
            metrics.pendingPayoutsCount = info.pendingPositions;
        } catch {
            // Default values
        }

        // Get exposure data
        try v.totalLongExposure() returns (uint256 longExp) {
            metrics.totalLongExposure = longExp;
        } catch { }

        try v.totalShortExposure() returns (uint256 shortExp) {
            metrics.totalShortExposure = shortExp;
        } catch { }

        // Calculate net exposure
        if (metrics.totalLongExposure > metrics.totalShortExposure) {
            metrics.netExposure = metrics.totalLongExposure - metrics.totalShortExposure;
        } else {
            metrics.netExposure = metrics.totalShortExposure - metrics.totalLongExposure;
        }

        // Calculate utilization
        if (metrics.totalLiquidity > 0) {
            metrics.utilizationBps =
                (metrics.netExposure * MathLib.BASIS_POINTS) / metrics.totalLiquidity;
        }

        // Check if paused
        try v.paused() returns (bool isPaused) {
            metrics.isPaused = isPaused;
        } catch {
            // Default false
        }

        // Check funding enabled
        try v.fundingEnabled() returns (bool enabled) {
            metrics.isFundingEnabled = enabled;
        } catch {
            // Default false
        }

        // Calculate health score (0-10000)
        metrics.healthScore = _calculateHealthScore(metrics);

        return metrics;
    }

    /**
     * @notice Calculate health score for a vault (0-10000)
     * @param metrics Vault health metrics
     * @return score Health score
     */
    function _calculateHealthScore(VaultHealthMetrics memory metrics)
        internal
        pure
        returns (uint256 score)
    {
        uint256 utilizationScore = 0;
        uint256 liquidityScore = 0;
        uint256 balanceScore = 0;
        uint256 statusScore = 0;

        // 1. Utilization score (40% weight) - lower utilization = higher score
        // 0% utilization = 4000 points, 100% utilization = 0 points
        if (metrics.utilizationBps <= MathLib.BASIS_POINTS) {
            utilizationScore = 4000 - ((metrics.utilizationBps * 4000) / MathLib.BASIS_POINTS);
        }

        // 2. Liquidity vs Pending Payouts score (30% weight)
        if (metrics.totalLiquidity > 0) {
            if (metrics.pendingPayoutsValue == 0) {
                liquidityScore = 3000;
            } else {
                uint256 ratio =
                    (metrics.totalLiquidity * MathLib.BASIS_POINTS) / metrics.pendingPayoutsValue;
                if (ratio >= 20_000) {
                    liquidityScore = 3000; // 2x or more = full score
                } else if (ratio >= MathLib.BASIS_POINTS) {
                    liquidityScore = 2000; // 1x-2x = partial score
                } else {
                    liquidityScore = (ratio * 2000) / MathLib.BASIS_POINTS; // < 1x = proportional
                }
            }
        }

        // 3. Exposure balance score (20% weight)
        uint256 totalExposure = metrics.totalLongExposure + metrics.totalShortExposure;
        if (totalExposure > 0) {
            uint256 imbalanceBps = (metrics.netExposure * MathLib.BASIS_POINTS) / totalExposure;
            balanceScore = 2000 - ((imbalanceBps * 2000) / MathLib.BASIS_POINTS);
        } else {
            balanceScore = 2000; // No exposure = balanced
        }

        // 4. Status score (10% weight)
        if (metrics.isActive && !metrics.isPaused) {
            statusScore = 1000;
        } else if (metrics.isActive) {
            statusScore = 500; // Active but paused
        }

        score = utilizationScore + liquidityScore + balanceScore + statusScore;

        // Cap at 10000
        if (score > MathLib.BASIS_POINTS) {
            score = MathLib.BASIS_POINTS;
        }

        return score;
    }

    // ========================================================================
    // INTERNAL HELPERS
    // ========================================================================

    function _calculateRiskMultiplier(
        uint256 tvl,
        uint16 fixedMultiplier,
        uint256 t1Threshold,
        uint256 t2Threshold,
        uint256 t3Threshold,
        uint16 t1Mult,
        uint16 t2Mult,
        uint16 t3Mult,
        uint16 t4Mult
    ) internal pure returns (uint16) {
        if (t1Threshold == 0 && t2Threshold == 0 && t3Threshold == 0) {
            return fixedMultiplier;
        }

        if (tvl < t1Threshold) {
            return t1Mult;
        } else if (tvl < t2Threshold) {
            return t2Mult;
        } else if (tvl < t3Threshold) {
            return t3Mult;
        } else {
            return t4Mult;
        }
    }

    function _calculateMaxLeverage(
        uint256 tvl,
        uint256 t1Threshold,
        uint256 t2Threshold,
        uint16 t1Max,
        uint16 t2Max,
        uint16 t3Max
    ) internal pure returns (uint16) {
        if (tvl < t1Threshold) {
            return t1Max;
        } else if (tvl < t2Threshold) {
            return t2Max;
        } else {
            return t3Max;
        }
    }
}
