// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./libraries/VaultStorageLib.sol";
import "./VaultAccessController.sol";

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

    event ModuleUpdated(bytes4 indexed moduleId, address oldModule, address newModule, uint256 timestamp);
    event Initialized(address indexed projectToken, address indexed accessController, uint256 timestamp);

    // ========================================================================
    // ERRORS
    // ========================================================================

    error NotAuthorized();
    error InvalidAddress();
    error InvalidModule();
    error DelegateCallFailed();
    error AlreadyInitialized();
    error NotInitialized();
    error DirectTransferNotAllowed();

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
     * @param _projectToken Project token address
     * @param _vaultManager VaultManager address
     * @param _vaultManagerHelper VaultManagerHelper address
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
        address _projectToken,
        address _vaultManager,
        address _vaultManagerHelper,
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
        if (_projectToken == address(0)) revert InvalidAddress();
        if (_vaultManager == address(0)) revert InvalidAddress();
        if (_vaultManagerHelper == address(0)) revert InvalidAddress();
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
                _projectToken,
                _vaultManager,
                _vaultManagerHelper,
                _positionManager,
                _accessController,
                _minBetAmount,
                _maxBetAmount,
                _graduationThreshold
            )
        );
        if (!success) revert DelegateCallFailed();

        emit Initialized(_projectToken, _accessController, block.timestamp);
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
                positionId, amount, positionSize, isMarginAdd, direction
            )
        );
    }

    /**
     * @notice Execute payout to user
     */
    function executePayout(address user, uint256 amount, uint64 positionId) external {
        _delegateToCore(
            abi.encodeWithSignature(
                "executePayout(address,uint256,uint64)",
                user, amount, positionId
            )
        );
    }

    /**
     * @notice Update vault P&L after position settlement
     */
    function updateVaultPnL(
        uint64 positionId,
        uint256 collateral,
        int256 vaultPnL,
        uint256 fee,
        uint256 positionSize,
        uint8 direction,
        address user
    ) external {
        _delegateToCore(
            abi.encodeWithSignature(
                "updateVaultPnL(uint64,uint256,int256,uint256,uint256,uint8,address)",
                positionId, collateral, vaultPnL, fee, positionSize, direction, user
            )
        );
    }

    /**
     * @notice Check position risk
     */
    function checkPositionRisk(uint256 positionSize, uint8 leverage, uint8 direction) external view {
        _staticDelegateToCore(
            abi.encodeWithSignature(
                "checkPositionRisk(uint256,uint8,uint8)",
                positionSize, leverage, direction
            )
        );
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
            abi.encodeWithSignature("updateVaultParams(uint256,uint256)", minBetAmount, maxBetAmount)
        );
    }

    // ========================================================================
    // MODULE ROUTING - FUNDING
    // ========================================================================

    /**
     * @notice Update hourly funding
     */
    function updateHourlyFunding()
        external
        returns (int256 newLongRate, int256 newShortRate, uint256 imbalanceBps, bool hasCounterparty)
    {
        bytes memory result = _delegateToFunding(abi.encodeWithSignature("updateHourlyFunding()"));
        return abi.decode(result, (int256, int256, uint256, bool));
    }

    /**
     * @notice Get cumulative funding rates
     */
    function getCumulativeFundingRates()
        external
        view
        returns (int256 cumulativeLongRate, int256 cumulativeShortRate)
    {
        VaultStorageLib.FundingStorage storage funding = VaultStorageLib.getFundingStorage();
        return (funding.cumulativeFundingRateLong, funding.cumulativeFundingRateShort);
    }

    /**
     * @notice Calculate position funding
     */
    function calculatePositionFunding(
        int256 entryRateLong,
        int256 entryRateShort,
        uint256 positionSize,
        uint8 direction
    ) external view returns (int256) {
        bytes memory result = _staticDelegateToFunding(
            abi.encodeWithSignature(
                "calculatePositionFunding(int256,int256,uint256,uint8)",
                entryRateLong, entryRateShort, positionSize, direction
            )
        );
        return abi.decode(result, (int256));
    }

    /**
     * @notice Get current hourly funding rate
     */
    function getCurrentHourlyFundingRate()
        external
        view
        returns (uint256 rateBps, bool longsPayShorts, uint256 imbalanceBps, bool hasCounterparty)
    {
        bytes memory result = _staticDelegateToFunding(
            abi.encodeWithSignature("getCurrentHourlyFundingRate()")
        );
        return abi.decode(result, (uint256, bool, uint256, bool));
    }

    /**
     * @notice Check funding liquidation
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
        returns (bool isLiquidatable, int256 fundingOwed, uint256 effectiveCollateral)
    {
        bytes memory result = _staticDelegateToFunding(
            abi.encodeWithSignature(
                "checkFundingLiquidation(uint256,int256,int256,uint256,uint8,uint256)",
                collateral, entryRateLong, entryRateShort, positionSize, direction, maintenanceMarginRatio
            )
        );
        return abi.decode(result, (bool, int256, uint256));
    }

    /**
     * @notice Set funding config
     */
    function setFundingConfig(
        uint16 tier1RateBps,
        uint16 tier2RateBps,
        uint16 tier3RateBps,
        uint16 tier4RateBps,
        uint16 tier5RateBps
    ) external {
        _delegateToFunding(
            abi.encodeWithSignature(
                "setFundingConfig(uint16,uint16,uint16,uint16,uint16)",
                tier1RateBps, tier2RateBps, tier3RateBps, tier4RateBps, tier5RateBps
            )
        );
    }

    /**
     * @notice Set funding enabled
     */
    function setFundingEnabled(bool enabled) external {
        _delegateToFunding(abi.encodeWithSignature("setFundingEnabled(bool)", enabled));
    }

    /**
     * @notice Get funding config
     */
    function getFundingConfig()
        external
        view
        returns (uint16, uint16, uint16, uint16, uint16)
    {
        bytes memory result = _staticDelegateToFunding(abi.encodeWithSignature("getFundingConfig()"));
        return abi.decode(result, (uint16, uint16, uint16, uint16, uint16));
    }

    // ========================================================================
    // MODULE ROUTING - REWARDS
    // ========================================================================

    /**
     * @notice Finalize daily reward
     */
    function finalizeDailyReward() external returns (bool isComplete) {
        bytes memory result = _delegateToRewards(abi.encodeWithSignature("finalizeDailyReward()"));
        return abi.decode(result, (bool));
    }

    /**
     * @notice Finalize daily reward remaining
     */
    function finalizeDailyRewardRemaining() external returns (bool isComplete) {
        bytes memory result = _delegateToRewards(abi.encodeWithSignature("finalizeDailyRewardRemaining()"));
        return abi.decode(result, (bool));
    }

    /**
     * @notice Claim rewards
     */
    function claimRewards() external {
        _delegateToRewards(abi.encodeWithSignature("claimRewards()"));
    }

    /**
     * @notice Claim rewards with protection
     */
    function claimRewardsProtected(uint256 minExpectedRewards) external {
        _delegateToRewards(
            abi.encodeWithSignature("claimRewardsProtected(uint256)", minExpectedRewards)
        );
    }

    /**
     * @notice Get claimable rewards
     */
    function getClaimableRewards(address user) external view returns (uint256) {
        return VaultStorageLib.getRewardsStorage().claimableRewards[user];
    }

    /**
     * @notice Calculate pending rewards
     */
    function calculatePendingRewards(address user) external view returns (uint256) {
        bytes memory result = _staticDelegateToRewards(
            abi.encodeWithSignature("calculatePendingRewards(address)", user)
        );
        return abi.decode(result, (uint256));
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
     * @notice Get project token
     */
    function projectToken() external view returns (address) {
        return VaultStorageLib.getCoreStorage().projectToken;
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
     * @notice Get withdrawable fees
     */
    function withdrawableFees() external view returns (uint256) {
        return VaultStorageLib.getCoreStorage().withdrawableFees;
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
     * @notice Get cumulative funding rate long
     */
    function cumulativeFundingRateLong() external view returns (int256) {
        return VaultStorageLib.getFundingStorage().cumulativeFundingRateLong;
    }

    /**
     * @notice Get cumulative funding rate short
     */
    function cumulativeFundingRateShort() external view returns (int256) {
        return VaultStorageLib.getFundingStorage().cumulativeFundingRateShort;
    }

    /**
     * @notice Get last funding update time
     */
    function lastFundingUpdateTime() external view returns (uint256) {
        return VaultStorageLib.getFundingStorage().lastFundingUpdateTime;
    }

    /**
     * @notice Check if funding is enabled
     */
    function fundingEnabled() external view returns (bool) {
        return VaultStorageLib.getFundingStorage().fundingEnabled;
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
     * @dev Only callable by admin via VaultManager or governance
     */
    function updateModule(bytes4 moduleId, address newModule) external {
        // Check caller is VaultManager or admin
        VaultStorageLib.CoreStorage storage core = VaultStorageLib.getCoreStorage();
        if (msg.sender != core.vaultManager) {
            VaultAccessController ac = VaultAccessController(core.accessController);
            if (!ac.hasRole(ac.DEFAULT_ADMIN_ROLE(), msg.sender)) {
                revert NotAuthorized();
            }
        }

        if (newModule == address(0)) revert InvalidModule();

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

    function _staticDelegateToCore(bytes memory data) internal view returns (bytes memory) {
        VaultStorageLib.RouterStorage storage router = VaultStorageLib.getRouterStorage();
        return _staticDelegate(router.coreModule, data);
    }

    function _staticDelegateToFunding(bytes memory data) internal view returns (bytes memory) {
        VaultStorageLib.RouterStorage storage router = VaultStorageLib.getRouterStorage();
        return _staticDelegate(router.fundingModule, data);
    }

    function _staticDelegateToRewards(bytes memory data) internal view returns (bytes memory) {
        VaultStorageLib.RouterStorage storage router = VaultStorageLib.getRouterStorage();
        return _staticDelegate(router.rewardsModule, data);
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

    function _staticDelegate(address module, bytes memory data) internal view returns (bytes memory) {
        (bool success, bytes memory result) = module.staticcall(data);
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

        // Only VaultManager or admin can upgrade
        if (msg.sender != core.vaultManager) {
            VaultAccessController ac = VaultAccessController(core.accessController);
            if (!ac.hasRole(ac.UPGRADER_ROLE(), msg.sender)) {
                revert NotAuthorized();
            }
        }
    }
}

