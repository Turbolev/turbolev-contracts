// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../libraries/vault/VaultStorageLib.sol";
import "./VaultAccessController.sol";
import "../libraries/vault/VaultRiskLib.sol";
import "../libraries/vault/VaultConfigLib.sol";
import "../libraries/math/PriceImpactLib.sol";
import "../libraries/vault/VaultRewardsLib.sol";

/**
 * @title VaultRouter
 * @notice Main entry point for modular vault system
 * @dev Routes function calls to appropriate modules via delegatecall.
 *      All storage is managed through EIP-7201 namespaced storage.
 *
 * Architecture:
 * - VaultRouter: Entry point with UUPS upgradeability, routes to modules
 * - VaultCore: Liquidity, payouts, risk checks, admin functions
 * - VaultFunding: Funding rate calculations and updates
 * - VaultRewards: Daily snapshots and reward claiming
 *
 * All modules are called via delegatecall, sharing this contract's storage.
 * The storage is organized using EIP-7201 namespaced storage slots.
 */
contract VaultRouter is Initializable, UUPSUpgradeable {
    // ========================================================================
    // EVENTS
    // ========================================================================

    event ModuleUpdated(
        bytes4 indexed moduleId, address oldModule, address newModule, uint256 timestamp
    );
    event Initialized(
        address indexed projectToken, address indexed accessController, uint256 timestamp
    );
    event EmergencyUpgrade(
        address indexed newImplementation, address indexed caller, uint256 timestamp
    );

    // ========================================================================
    // ERRORS
    // ========================================================================

    error NotAuthorized();
    error InvalidAddress();
    error InvalidModule();
    error InvalidContractAddress(address addr);
    error DelegateCallFailed();
    error AlreadyInitialized();
    error NotInitialized();
    error DirectTransferNotAllowed();
    error PendingOperationsExist(uint256 pendingPositions, uint256 pendingPayouts);
    error MustPauseBeforeEmergencyUpgrade();

    // ========================================================================
    // MODULE IDs
    // ========================================================================

    bytes4 public constant MODULE_CORE = bytes4(keccak256("MODULE_CORE"));
    bytes4 public constant MODULE_FUNDING = bytes4(keccak256("MODULE_FUNDING"));
    bytes4 public constant MODULE_REWARDS = bytes4(keccak256("MODULE_REWARDS"));

    // ========================================================================
    // CONSTRUCTOR / INITIALIZER
    // ========================================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the vault router
     * @param _priceToken Token whose price is tracked by the oracle (e.g. SEI, ETH)
     * @param _collateralToken Token used for LP liquidity and user collateral (e.g. USDC, USDT)
     * @param _vaultManager VaultManager address
     * @param _positionManager PositionManager address
     * @param _accessController VaultAccessController address
     * @param _coreModule VaultCore module address
     * @param _fundingModule VaultFunding module address
     * @param _rewardsModule VaultRewards module address
     * @param _minBetAmount Minimum bet amount
     * @param _maxBetAmount Maximum bet amount
     * @param _graduationThreshold Graduation threshold
     */
    function initialize(
        address _priceToken,
        address _collateralToken,
        address _vaultManager,
        address _positionManager,
        address _accessController,
        address _coreModule,
        address _fundingModule,
        address _rewardsModule,
        uint256 _minBetAmount,
        uint256 _maxBetAmount,
        uint256 _graduationThreshold
    ) external initializer {
        __UUPSUpgradeable_init();

        // Validate addresses
        if (_priceToken == address(0)) revert InvalidAddress();
        if (_collateralToken == address(0)) revert InvalidAddress();
        if (_vaultManager == address(0)) revert InvalidAddress();
        if (_positionManager == address(0)) revert InvalidAddress();
        if (_accessController == address(0)) revert InvalidAddress();
        if (_coreModule == address(0)) revert InvalidModule();
        if (_fundingModule == address(0)) revert InvalidModule();
        if (_rewardsModule == address(0)) revert InvalidModule();

        // Set router storage
        VaultStorageLib.RouterStorage storage router = VaultStorageLib.getRouterStorage();
        router.coreModule = _coreModule;
        router.fundingModule = _fundingModule;
        router.rewardsModule = _rewardsModule;
        router.initialized = true;

        // Initialize core module via delegatecall
        (bool success,) = _coreModule.delegatecall(
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,uint256,uint256,uint256)",
                _priceToken,
                _collateralToken,
                _vaultManager,
                _positionManager,
                _accessController,
                _minBetAmount,
                _maxBetAmount,
                _graduationThreshold
            )
        );
        if (!success) revert DelegateCallFailed();

        emit Initialized(_priceToken, _accessController, block.timestamp);
    }

    // ========================================================================
    // RECEIVE / FALLBACK
    // ========================================================================

    receive() external payable {
        revert DirectTransferNotAllowed();
    }

    fallback() external payable {
        revert DirectTransferNotAllowed();
    }

    // ========================================================================
    // MODULE ROUTING - CORE
    // ========================================================================

    /**
     * @notice Add liquidity to vault
     */
    function addLiquidity(uint256 amount) external payable {
        _delegateToCore(abi.encodeWithSignature("addLiquidity(uint256)", amount));
    }

    /**
     * @notice Remove liquidity from vault
     */
    function removeLiquidity() external {
        _delegateToCore(abi.encodeWithSignature("removeLiquidity()"));
    }

    /**
     * @notice Deposit collateral from bet
     */
    function depositFromBet(
        uint64 positionId,
        uint256 amount,
        uint256 positionSize,
        bool isMarginAdd,
        uint8 direction
    ) external payable {
        _delegateToCore(
            abi.encodeWithSignature(
                "depositFromBet(uint64,uint256,uint256,bool,uint8)",
                positionId,
                amount,
                positionSize,
                isMarginAdd,
                direction
            )
        );
    }

    /**
     * @notice Execute payout to user
     */
    function executePayout(address user, uint256 amount, uint64 positionId) external {
        _delegateToCore(
            abi.encodeWithSignature(
                "executePayout(address,uint256,uint64)", user, amount, positionId
            )
        );
    }

    /**
     * @notice Update vault P&L after position settlement
     * @return closeFee The close fee collected (to be deducted from trader payout)
     */
    function updateVaultPnL(
        uint64 positionId,
        uint256 collateral,
        int256 vaultPnL,
        uint256 positionSize,
        uint8 direction,
        address user,
        uint256 payout
    ) external returns (uint256 closeFee) {
        bytes memory result = _delegateToCore(
            abi.encodeWithSignature(
                "updateVaultPnL(uint64,uint256,int256,uint256,uint8,address,uint256)",
                positionId,
                collateral,
                vaultPnL,
                positionSize,
                direction,
                user,
                payout
            )
        );
        return abi.decode(result, (uint256));
    }

    /**
     * @notice Check position risk
     * @dev Reads storage directly to avoid staticcall storage context issues
     */
    function checkPositionRisk(uint256 positionSize, uint16 leverage, uint8 direction)
        external
        view
    {
        VaultStorageLib.CoreStorage storage core = VaultStorageLib.getCoreStorage();
        VaultStorageLib.FundingStorage storage funding = VaultStorageLib.getFundingStorage();
        VaultStorageLib.RiskStorage storage risk = VaultStorageLib.getRiskStorage();

        uint16 currentMultiplier = _calculateRiskMultiplier(core.vaultInfo.totalLiquidity, risk);

        VaultRiskLib.RiskCheckParams memory params = VaultRiskLib.RiskCheckParams({
            isPaused: core.paused,
            tradingEnabled: core.vaultInfo.tradingEnabled,
            totalLiquidity: core.vaultInfo.totalLiquidity,
            positionSize: positionSize,
            leverage: leverage,
            direction: direction,
            minBetAmount: core.vaultParams.minBetAmount,
            maxBetAmount: core.vaultParams.maxBetAmount,
            totalLongExposure: funding.totalLongExposure,
            totalShortExposure: funding.totalShortExposure,
            maxDirectionalExposureBps: risk.maxDirectionalExposureBps,
            vaultMaxLeverage: risk.maxLeverage,
            totalOIRiskMultiplierBps: currentMultiplier
        });

        VaultRiskLib.checkPositionRisk(params);
    }

    /**
     * @notice Calculate risk multiplier based on TVL tier
     */
    function _calculateRiskMultiplier(uint256 tvl, VaultStorageLib.RiskStorage storage risk)
        internal
        view
        returns (uint16)
    {
        if (risk.tier1Threshold == 0 && risk.tier2Threshold == 0 && risk.tier3Threshold == 0) {
            return risk.totalOIRiskMultiplierBps;
        }

        if (tvl < risk.tier1Threshold) {
            return risk.tier1MultiplierBps;
        } else if (tvl < risk.tier2Threshold) {
            return risk.tier2MultiplierBps;
        } else if (tvl < risk.tier3Threshold) {
            return risk.tier3MultiplierBps;
        } else {
            return risk.tier4MultiplierBps;
        }
    }

    /**
     * @notice Pause vault
     */
    function pause() external {
        _delegateToCore(abi.encodeWithSignature("pause()"));
    }

    /**
     * @notice Unpause vault
     */
    function unpause() external {
        _delegateToCore(abi.encodeWithSignature("unpause()"));
    }

    /**
     * @notice Set fee
     */
    function setFee(uint8 feeType, uint16 feeBps) external {
        _delegateToCore(abi.encodeWithSignature("setFee(uint8,uint16)", feeType, feeBps));
    }

    /**
     * @notice Set treasury
     */
    function setTreasury(address treasury) external {
        _delegateToCore(abi.encodeWithSignature("setTreasury(address)", treasury));
    }

    /**
     * @notice Set trading enabled
     */
    function setTradingEnabled(bool enabled) external {
        _delegateToCore(abi.encodeWithSignature("setTradingEnabled(bool)", enabled));
    }

    /**
     * @notice Set graduation threshold
     */
    function setGraduationThreshold(uint256 threshold) external {
        _delegateToCore(abi.encodeWithSignature("setGraduationThreshold(uint256)", threshold));
    }

    /**
     * @notice Withdraw fees
     */
    function withdrawFees(uint256 amount) external {
        _delegateToCore(abi.encodeWithSignature("withdrawFees(uint256)", amount));
    }

    /**
     * @notice Set position manager
     */
    function setPositionManager(address positionManager) external {
        _delegateToCore(abi.encodeWithSignature("setPositionManager(address)", positionManager));
    }

    /**
     * @notice Update vault params
     */
    function updateVaultParams(uint256 minBetAmount, uint256 maxBetAmount) external {
        _delegateToCore(
            abi.encodeWithSignature(
                "updateVaultParams(uint256,uint256)", minBetAmount, maxBetAmount
            )
        );
    }

    // ========================================================================
    // MODULE ROUTING - RISK CONFIG
    // ========================================================================

    /**
     * @notice Set maximum leverage (admin-configurable)
     */
    function setMaxLeverage(uint16 newMaxLeverage) external {
        _delegateToCore(abi.encodeWithSignature("setMaxLeverage(uint16)", newMaxLeverage));
    }

    /**
     * @notice Set total OI tier configuration
     */
    function setTotalOITierConfig(
        uint16 totalOIRiskMultiplierBps,
        uint256 tier1Threshold,
        uint256 tier2Threshold,
        uint256 tier3Threshold,
        uint16 tier1MultiplierBps,
        uint16 tier2MultiplierBps,
        uint16 tier3MultiplierBps,
        uint16 tier4MultiplierBps
    ) external {
        _delegateToCore(
            abi.encodeWithSignature(
                "setTotalOITierConfig(uint16,uint256,uint256,uint256,uint16,uint16,uint16,uint16)",
                totalOIRiskMultiplierBps,
                tier1Threshold,
                tier2Threshold,
                tier3Threshold,
                tier1MultiplierBps,
                tier2MultiplierBps,
                tier3MultiplierBps,
                tier4MultiplierBps
            )
        );
    }

    /**
     * @notice Set max directional exposure cap
     */
    function setMaxDirectionalExposure(uint16 maxDirectionalExposureBps) external {
        _delegateToCore(
            abi.encodeWithSignature("setMaxDirectionalExposure(uint16)", maxDirectionalExposureBps)
        );
    }

    /**
     * @notice Set max profit cap multiplier (per-vault)
     */
    function setMaxProfitCapMultiplier(uint8 multiplier) external {
        _delegateToCore(abi.encodeWithSignature("setMaxProfitCapMultiplier(uint8)", multiplier));
    }

    /**
     * @notice Get max profit cap multiplier
     */
    function getMaxProfitCapMultiplier() external view returns (uint8) {
        return VaultStorageLib.getRiskStorage().maxProfitCapMultiplier;
    }

    // ========================================================================
    // MODULE ROUTING - PRICE IMPACT
    // ========================================================================

    /**
     * @notice Calculate execution price and impact fee for a new position
     * @param positionSize Notional position size (collateral * leverage)
     */
    function getExecutionPrice(uint256 markPrice, uint8 direction, uint256 positionSize)
        external
        view
        returns (uint256 executionPrice, uint256 impactFee, uint256 impactBps, bool isCrowdedSide)
    {
        VaultStorageLib.FundingStorage storage funding = VaultStorageLib.getFundingStorage();

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
     * @notice Record impact fee (called by PositionCore after open)
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
    ) external {
        _delegateToFunding(
            abi.encodeWithSignature(
                "recordImpactFee(uint64,address,uint8,uint256,uint256,uint256,uint256,bool)",
                positionId,
                user,
                direction,
                markPrice,
                executionPrice,
                impactBps,
                impactFee,
                isCrowdedSide
            )
        );
    }

    /**
     * @notice Get current price impact rate based on OI imbalance
     */
    function getCurrentImpactRate()
        external
        view
        returns (uint256 impactBps, bool isLongDominant, uint256 imbalanceBps)
    {
        VaultStorageLib.FundingStorage storage funding = VaultStorageLib.getFundingStorage();

        if (!funding.impactEnabled) {
            return (0, false, 0);
        }

        if (funding.totalLongExposure + funding.totalShortExposure == 0) {
            return (0, false, 0);
        }

        (imbalanceBps, isLongDominant,) = PriceImpactLib.calculateImbalance(
            funding.totalLongExposure, funding.totalShortExposure
        );

        impactBps = PriceImpactLib.getTieredImpactBps(imbalanceBps, funding.impactConfig);
    }

    /**
     * @notice Get price impact statistics
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
        VaultStorageLib.FundingStorage storage funding = VaultStorageLib.getFundingStorage();

        longExposure = funding.totalLongExposure;
        shortExposure = funding.totalShortExposure;
        totalFeesCollected = funding.totalImpactFeesCollected;

        (imbalanceBps, isLongDominant,) =
            PriceImpactLib.calculateImbalance(longExposure, shortExposure);

        currentImpactBps = PriceImpactLib.getTieredImpactBps(imbalanceBps, funding.impactConfig);
    }

    /**
     * @notice Set price impact tier config
     */
    function setImpactConfig(
        uint16 tier1ImpactBps,
        uint16 tier2ImpactBps,
        uint16 tier3ImpactBps,
        uint16 tier4ImpactBps,
        uint16 tier5ImpactBps
    ) external {
        _delegateToFunding(
            abi.encodeWithSignature(
                "setImpactConfig(uint16,uint16,uint16,uint16,uint16)",
                tier1ImpactBps,
                tier2ImpactBps,
                tier3ImpactBps,
                tier4ImpactBps,
                tier5ImpactBps
            )
        );
    }

    /**
     * @notice Set price impact enabled
     */
    function setImpactEnabled(bool enabled) external {
        _delegateToFunding(abi.encodeWithSignature("setImpactEnabled(bool)", enabled));
    }

    /**
     * @notice Check if price impact is enabled
     */
    function isImpactEnabled() external view returns (bool) {
        return VaultStorageLib.getFundingStorage().impactEnabled;
    }

    /**
     * @notice Get price impact config
     */
    function getImpactConfig() external view returns (uint16, uint16, uint16, uint16, uint16) {
        VaultStorageLib.FundingStorage storage funding = VaultStorageLib.getFundingStorage();
        return (
            funding.impactConfig.tier1ImpactBps,
            funding.impactConfig.tier2ImpactBps,
            funding.impactConfig.tier3ImpactBps,
            funding.impactConfig.tier4ImpactBps,
            funding.impactConfig.tier5ImpactBps
        );
    }

    /**
     * @notice Get total impact fees collected
     */
    function totalImpactFeesCollected() external view returns (uint256) {
        return VaultStorageLib.getFundingStorage().totalImpactFeesCollected;
    }

    // ========================================================================
    // MODULE ROUTING - REWARDS
    // ========================================================================

    /**
     * @notice Claim rewards (Option D — no keeper finalize needed).
     */
    function claimRewards() external {
        _delegateToRewards(abi.encodeWithSignature("claimRewards()"));
    }

    /**
     * @notice Claim rewards with slippage protection.
     */
    function claimRewardsProtected(uint256 minExpectedRewards) external {
        _delegateToRewards(
            abi.encodeWithSignature("claimRewardsProtected(uint256)", minExpectedRewards)
        );
    }

    /**
     * @notice Get already-settled claimable rewards for a user.
     */
    function getClaimableRewards(address user) external view returns (uint256) {
        return VaultStorageLib.getRewardsStorage().claimableRewards[user];
    }

    /**
     * @notice Preview total pending rewards (settled + accrued since last settlement).
     * @dev Uses accumulator directly — no keeper required (Option D).
     */
    function calculatePendingRewards(address user) external view returns (uint256 pendingRewards) {
        VaultStorageLib.CoreStorage storage core = VaultStorageLib.getCoreStorage();
        VaultStorageLib.RewardsStorage storage rewards = VaultStorageLib.getRewardsStorage();

        VaultStorageLib.LPPosition storage lpPos = core.lpPositions[user];

        pendingRewards = rewards.claimableRewards[user];
        if (lpPos.shares == 0) return pendingRewards;

        uint256 eligibilityTs =
            lpPos.lastTopUpAt > lpPos.stakedAt ? lpPos.lastTopUpAt : lpPos.stakedAt;
        if (block.timestamp < eligibilityTs + VaultStorageLib.REWARD_MIN_STAKE_PERIOD) {
            return pendingRewards;
        }

        pendingRewards += VaultRewardsLib.computePendingReward(
            lpPos.shares, rewards.rewardPerShareStored, lpPos.rewardPerSharePaid
        );
    }

    /**
     * @notice Get the global reward-per-share accumulator value.
     */
    function rewardPerShareStored() external view returns (uint256) {
        return VaultStorageLib.getRewardsStorage().rewardPerShareStored;
    }

    // ========================================================================
    // VIEW FUNCTIONS (Direct Storage Access)
    // ========================================================================

    /**
     * @notice Get vault info
     */
    function vaultInfo() external view returns (VaultStorageLib.VaultInfo memory) {
        return VaultStorageLib.getCoreStorage().vaultInfo;
    }

    /**
     * @notice Get vault params
     */
    function vaultParams() external view returns (VaultStorageLib.VaultParams memory) {
        return VaultStorageLib.getCoreStorage().vaultParams;
    }

    /**
     * @notice Get LP position
     */
    function lpPositions(address user) external view returns (VaultStorageLib.LPPosition memory) {
        return VaultStorageLib.getCoreStorage().lpPositions[user];
    }

    /**
     * @notice Get price token (token whose price is tracked by the oracle)
     */
    function priceToken() external view returns (address) {
        return VaultStorageLib.getCoreStorage().projectToken;
    }

    /**
     * @notice Get collateral token (token used for LP liquidity and user collateral)
     */
    function collateralToken() external view returns (address) {
        return VaultStorageLib.getCoreStorage().collateralToken;
    }

    /**
     * @notice Check if paused
     */
    function paused() external view returns (bool) {
        return VaultStorageLib.getCoreStorage().paused;
    }

    /**
     * @notice Get vault manager
     */
    function vaultManager() external view returns (address) {
        return VaultStorageLib.getCoreStorage().vaultManager;
    }

    /**
     * @notice Get position manager
     */
    function positionManager() external view returns (address) {
        return VaultStorageLib.getCoreStorage().positionManager;
    }

    /**
     * @notice Get total long exposure
     */
    function totalLongExposure() external view returns (uint256) {
        return VaultStorageLib.getFundingStorage().totalLongExposure;
    }

    /**
     * @notice Get total short exposure
     */
    function totalShortExposure() external view returns (uint256) {
        return VaultStorageLib.getFundingStorage().totalShortExposure;
    }

    /**
     * @notice Get bet collateral
     */
    function betCollateral(uint64 positionId) external view returns (uint256) {
        return VaultStorageLib.getCoreStorage().betCollateral[positionId];
    }

    /**
     * @notice Get position payouts
     */
    function positionPayouts(uint64 positionId) external view returns (uint256) {
        return VaultStorageLib.getCoreStorage().positionPayouts[positionId];
    }

    /**
     * @notice Get vault LPs length
     */
    function getVaultLPsLength() external view returns (uint256) {
        return VaultStorageLib.getCoreStorage().vaultLPs.length;
    }

    /**
     * @notice Get pending payout queue length
     */
    function getPendingPayoutQueueLength() external view returns (uint256) {
        return VaultStorageLib.getCoreStorage().pendingPayoutQueue.length;
    }

    /**
     * @notice Get version
     */
    function version() external pure returns (string memory) {
        return "1.0.0-modular";
    }

    // ========================================================================
    // IAssetVault COMPATIBILITY ALIASES
    // ========================================================================

    /**
     * @notice Get vault info (alias for vaultInfo() - IAssetVault compatible)
     */
    function getVaultInfo() external view returns (VaultStorageLib.VaultInfo memory) {
        return VaultStorageLib.getCoreStorage().vaultInfo;
    }

    /**
     * @notice Get vault params (alias for vaultParams() - IAssetVault compatible)
     */
    function getVaultParams() external view returns (VaultStorageLib.VaultParams memory) {
        return VaultStorageLib.getCoreStorage().vaultParams;
    }

    /**
     * @notice Get LP position (alias for lpPositions(address) - IAssetVault compatible)
     */
    function getLPPosition(address user) external view returns (VaultStorageLib.LPPosition memory) {
        return VaultStorageLib.getCoreStorage().lpPositions[user];
    }

    /**
     * @notice Get trading enabled status
     */
    function tradingEnabled() external view returns (bool) {
        return VaultStorageLib.getCoreStorage().vaultInfo.tradingEnabled;
    }

    /**
     * @notice Check if vault is graduated
     */
    function isGraduated() external view returns (bool) {
        return VaultStorageLib.getCoreStorage().vaultInfo.isGraduated;
    }

    /**
     * @notice Get vault LPs at index (for iteration)
     */
    function vaultLPs(uint256 index) external view returns (address) {
        return VaultStorageLib.getCoreStorage().vaultLPs[index];
    }

    /**
     * @notice Get withdrawable fees (from fee pool)
     */
    function withdrawableFees() external view returns (uint256) {
        return VaultStorageLib.getCoreStorage().feePool;
    }

    /**
     * @notice Get fee pool balance
     */
    function feePool() external view returns (uint256) {
        return VaultStorageLib.getCoreStorage().feePool;
    }

    /**
     * @notice Get current day
     */
    function currentDay() external view returns (uint256) {
        return VaultStorageLib.getRewardsStorage().currentDay;
    }

    /**
     * @notice Get last snapshot day
     */
    function lastSnapshotDay() external view returns (uint256) {
        return VaultStorageLib.getRewardsStorage().lastSnapshotDay;
    }

    /**
     * @notice Get daily net PnL
     */
    function dailyNetPnL() external view returns (int256) {
        return VaultStorageLib.getRewardsStorage().dailyNetPnL;
    }

    /**
     * @notice Get finalize LP index
     */
    function finalizeLPIndex() external view returns (uint256) {
        return VaultStorageLib.getRewardsStorage().finalizeLPIndex;
    }

    /**
     * @notice Get max directional exposure in bps
     */
    function maxDirectionalExposureBps() external view returns (uint16) {
        return VaultStorageLib.getRiskStorage().maxDirectionalExposureBps;
    }

    /**
     * @notice Get claimable rewards for user
     */
    function claimableRewards(address user) external view returns (uint256) {
        return VaultStorageLib.getRewardsStorage().claimableRewards[user];
    }

    // ========================================================================
    // RISK CONFIG GETTERS (for VaultViewerModular)
    // ========================================================================

    /**
     * @notice Get total OI tier configuration
     * @return fixedMultiplier Fixed multiplier in bps (if thresholds are 0)
     * @return tier1Threshold TVL threshold for tier 1
     * @return tier2Threshold TVL threshold for tier 2
     * @return tier3Threshold TVL threshold for tier 3
     * @return tier1Multiplier Multiplier for tier 1 in bps
     * @return tier2Multiplier Multiplier for tier 2 in bps
     * @return tier3Multiplier Multiplier for tier 3 in bps
     * @return tier4Multiplier Multiplier for tier 4 in bps
     */
    function getTotalOITierConfig()
        external
        view
        returns (
            uint16 fixedMultiplier,
            uint256 tier1Threshold,
            uint256 tier2Threshold,
            uint256 tier3Threshold,
            uint16 tier1Multiplier,
            uint16 tier2Multiplier,
            uint16 tier3Multiplier,
            uint16 tier4Multiplier
        )
    {
        VaultStorageLib.RiskStorage storage risk = VaultStorageLib.getRiskStorage();
        return (
            risk.totalOIRiskMultiplierBps,
            risk.tier1Threshold,
            risk.tier2Threshold,
            risk.tier3Threshold,
            risk.tier1MultiplierBps,
            risk.tier2MultiplierBps,
            risk.tier3MultiplierBps,
            risk.tier4MultiplierBps
        );
    }

    /**
     * @notice Get maximum leverage (fixed, admin-configurable)
     * @return maxLeverage Current maximum leverage
     */
    function getMaxLeverage() external view returns (uint16 maxLeverage) {
        return VaultStorageLib.getRiskStorage().maxLeverage;
    }

    /**
     * @notice Get fee configuration
     * @return stakingFeeBps Staking fee in bps
     * @return earlyWithdrawalFeeBps Early withdrawal fee in bps
     * @return minLockPeriod Minimum lock period in seconds
     */
    function getFeeConfig()
        external
        view
        returns (uint16 stakingFeeBps, uint16 earlyWithdrawalFeeBps, uint256 minLockPeriod)
    {
        VaultStorageLib.CoreStorage storage core = VaultStorageLib.getCoreStorage();
        return (
            core.feeConfig.stakingFeeBps,
            core.feeConfig.earlyWithdrawalFeeBps,
            VaultStorageLib.MIN_LOCK_PERIOD
        );
    }

    /**
     * @notice Get LP index for an address (1-based, 0 means not an LP)
     * @param account Address to check
     * @return index 1-based index in the LP array, 0 if not an LP
     */
    function lpIndex(address account) external view returns (uint256) {
        return VaultStorageLib.getCoreStorage().lpIndex[account];
    }

    /**
     * @notice Get queue start index for pending payouts
     * @return startIndex Current start index in the payout queue
     */
    function queueStartIndex() external view returns (uint256) {
        return VaultStorageLib.getCoreStorage().queueStartIndex;
    }

    // ========================================================================
    // MODULE MANAGEMENT
    // ========================================================================

    /**
     * @notice Get module address
     */
    function getModule(bytes4 moduleId) external view returns (address) {
        VaultStorageLib.RouterStorage storage router = VaultStorageLib.getRouterStorage();

        if (moduleId == MODULE_CORE) return router.coreModule;
        if (moduleId == MODULE_FUNDING) return router.fundingModule;
        if (moduleId == MODULE_REWARDS) return router.rewardsModule;

        return address(0);
    }

    /**
     * @notice Update module address
     * @dev Only callable by UPGRADER_ROLE or DEFAULT_ADMIN_ROLE.
     *      vaultManager is also accepted but must additionally hold UPGRADER_ROLE —
     *      this prevents a compromised vaultManager from silently swapping vault logic
     *      without explicit upgrade authorization.
     *      Requires no pending operations to ensure safe module swap.
     */
    function updateModule(bytes4 moduleId, address newModule) external {
        VaultStorageLib.CoreStorage storage core = VaultStorageLib.getCoreStorage();
        VaultAccessController ac = VaultAccessController(core.accessController);

        // All callers (including vaultManager) must hold UPGRADER_ROLE or DEFAULT_ADMIN_ROLE
        if (
            !ac.hasRole(ac.UPGRADER_ROLE(), msg.sender)
                && !ac.hasRole(ac.DEFAULT_ADMIN_ROLE(), msg.sender)
        ) {
            revert NotAuthorized();
        }

        if (newModule == address(0)) revert InvalidModule();
        if (newModule.code.length == 0) revert InvalidContractAddress(newModule);

        // Check no pending operations before allowing module swap
        uint256 pendingPositions = core.vaultInfo.pendingPositions;
        uint256 pendingPayouts = core.pendingPayoutQueue.length > core.queueStartIndex
            ? core.pendingPayoutQueue.length - core.queueStartIndex
            : 0;
        if (pendingPositions > 0 || pendingPayouts > 0) {
            revert PendingOperationsExist(pendingPositions, pendingPayouts);
        }

        VaultStorageLib.RouterStorage storage router = VaultStorageLib.getRouterStorage();
        address oldModule;

        if (moduleId == MODULE_CORE) {
            oldModule = router.coreModule;
            router.coreModule = newModule;
        } else if (moduleId == MODULE_FUNDING) {
            oldModule = router.fundingModule;
            router.fundingModule = newModule;
        } else if (moduleId == MODULE_REWARDS) {
            oldModule = router.rewardsModule;
            router.rewardsModule = newModule;
        } else {
            revert InvalidModule();
        }

        emit ModuleUpdated(moduleId, oldModule, newModule, block.timestamp);
    }

    // ========================================================================
    // INTERNAL DELEGATION FUNCTIONS
    // ========================================================================

    function _delegateToCore(bytes memory data) internal returns (bytes memory) {
        VaultStorageLib.RouterStorage storage router = VaultStorageLib.getRouterStorage();
        return _delegate(router.coreModule, data);
    }

    function _delegateToFunding(bytes memory data) internal returns (bytes memory) {
        VaultStorageLib.RouterStorage storage router = VaultStorageLib.getRouterStorage();
        return _delegate(router.fundingModule, data);
    }

    function _delegateToRewards(bytes memory data) internal returns (bytes memory) {
        VaultStorageLib.RouterStorage storage router = VaultStorageLib.getRouterStorage();
        return _delegate(router.rewardsModule, data);
    }

    function _delegate(address module, bytes memory data) internal returns (bytes memory) {
        (bool success, bytes memory result) = module.delegatecall(data);
        if (!success) {
            // Bubble up the revert reason
            if (result.length > 0) {
                assembly {
                    let returndata_size := mload(result)
                    revert(add(32, result), returndata_size)
                }
            } else {
                revert DelegateCallFailed();
            }
        }
        return result;
    }

    // ========================================================================
    // UUPS UPGRADE
    // ========================================================================

    function _authorizeUpgrade(address newImplementation) internal override {
        VaultStorageLib.CoreStorage storage core = VaultStorageLib.getCoreStorage();
        VaultAccessController ac = VaultAccessController(core.accessController);

        // Path 1: Normal upgrade via Timelock (UPGRADER_ROLE)
        if (ac.hasRole(ac.UPGRADER_ROLE(), msg.sender)) {
            return;
        }

        // Path 2: Emergency upgrade via Emergency/Guardian role — only if vault is paused
        if (
            ac.hasRole(ac.EMERGENCY_ROLE(), msg.sender)
                || ac.hasRole(ac.GUARDIAN_ROLE(), msg.sender)
        ) {
            if (!core.paused) revert MustPauseBeforeEmergencyUpgrade();
            emit EmergencyUpgrade(newImplementation, msg.sender, block.timestamp);
            return;
        }

        revert NotAuthorized();
    }
}

