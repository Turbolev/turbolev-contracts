// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./libraries/PositionStorageLib.sol";
import "../vault-modular/VaultAccessController.sol";
import "../libraries/PositionLib.sol";
import "../libraries/MathLib.sol";
import "../interfaces/IVaultManager.sol";
import "../interfaces/IAssetVault.sol";
import "../interfaces/ISettlementEngine.sol";
import "../interfaces/IPriceFeedManager.sol";

/**
 * @title PositionRouter
 * @notice Main entry point for modular position management system
 * @dev Routes function calls to appropriate modules via delegatecall.
 *      All storage is managed through EIP-7201 namespaced storage.
 *
 * Architecture:
 * - PositionRouter: Entry point with UUPS upgradeability, routes to modules
 * - PositionCore: Open, close, add margin, admin close, settlement
 * - PositionPendingClose: Pending close requests processing
 *
 * All modules are called via delegatecall, sharing this contract's storage.
 * The storage is organized using EIP-7201 namespaced storage slots.
 */
contract PositionRouter is Initializable, UUPSUpgradeable {
    // ========================================================================
    // EVENTS
    // ========================================================================

    event ModuleUpdated(
        bytes4 indexed moduleId, address oldModule, address newModule, uint256 timestamp
    );
    event Initialized(address indexed accessController, uint256 timestamp);
    event EmergencyUpgrade(
        address indexed newImplementation, address indexed caller, uint256 timestamp
    );

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
    error AccessControllerNotSet();
    error MustPauseBeforeEmergencyUpgrade();

    // ========================================================================
    // MODULE IDs
    // ========================================================================

    bytes4 public constant MODULE_CORE = bytes4(keccak256("POSITION_MODULE_CORE"));
    bytes4 public constant MODULE_PENDING_CLOSE =
        bytes4(keccak256("POSITION_MODULE_PENDING_CLOSE"));

    // ========================================================================
    // CONSTRUCTOR / INITIALIZER
    // ========================================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the position router
     * @param _accessController VaultAccessController address
     * @param _settlementEngine SettlementEngine address
     * @param _vaultManager VaultManager address
     * @param _priceFeedManager PriceFeedManager address
     * @param _coreModule PositionCore module address
     * @param _pendingCloseModule PositionPendingClose module address
     */
    function initialize(
        address _accessController,
        address _settlementEngine,
        address _vaultManager,
        address _priceFeedManager,
        address _coreModule,
        address _pendingCloseModule
    ) external initializer {
        __UUPSUpgradeable_init();

        // Validate addresses
        if (_accessController == address(0)) revert InvalidAddress();
        if (_coreModule == address(0)) revert InvalidModule();
        if (_pendingCloseModule == address(0)) revert InvalidModule();

        // Set router storage
        PositionStorageLib.RouterStorage storage router = PositionStorageLib.getRouterStorage();
        router.coreModule = _coreModule;
        router.pendingCloseModule = _pendingCloseModule;
        router.initialized = true;

        // Initialize core module via delegatecall
        (bool success,) = _coreModule.delegatecall(
            abi.encodeWithSignature(
                "initialize(address,address,address,address)",
                _accessController,
                _settlementEngine,
                _vaultManager,
                _priceFeedManager
            )
        );
        if (!success) revert DelegateCallFailed();

        emit Initialized(_accessController, block.timestamp);
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
    // MODULE ROUTING - CORE (User Functions)
    // ========================================================================

    /**
     * @notice Open position (LONG/SHORT) with leverage
     */
    function openPosition(
        address projectToken,
        uint256 collateralAmount,
        uint8 leverage,
        uint8 direction,
        uint256 maxAcceptablePrice,
        uint256 deadline,
        bytes calldata priceUpdateData
    ) external payable returns (uint64 positionId) {
        bytes memory result = _delegateToCore(
            abi.encodeWithSignature(
                "openPosition(address,uint256,uint8,uint8,uint256,uint256,bytes)",
                projectToken,
                collateralAmount,
                leverage,
                direction,
                maxAcceptablePrice,
                deadline,
                priceUpdateData
            )
        );
        return abi.decode(result, (uint64));
    }

    /**
     * @notice Close position
     */
    function closePosition(
        uint64 positionId,
        uint256 deadline,
        uint256 maxAcceptablePrice,
        bytes calldata priceUpdateData
    ) external payable {
        _delegateToCore(
            abi.encodeWithSignature(
                "closePosition(uint64,uint256,uint256,bytes)",
                positionId,
                deadline,
                maxAcceptablePrice,
                priceUpdateData
            )
        );
    }

    /**
     * @notice Add margin to existing position
     */
    function addMargin(
        uint64 positionId,
        uint256 marginAmount,
        uint256 maxAcceptablePrice,
        uint256 deadline
    ) external payable {
        _delegateToCore(
            abi.encodeWithSignature(
                "addMargin(uint64,uint256,uint256,uint256)",
                positionId,
                marginAmount,
                maxAcceptablePrice,
                deadline
            )
        );
    }

    /**
     * @notice Admin force close position
     */
    function adminClosePosition(
        uint64 positionId,
        uint256 deadline,
        bool isLiquidation,
        PositionStorageLib.PositionClosedBy closedBy
    ) external {
        _delegateToCore(
            abi.encodeWithSignature(
                "adminClosePosition(uint64,uint256,bool,uint8)",
                positionId,
                deadline,
                isLiquidation,
                uint8(closedBy)
            )
        );
    }

    // ========================================================================
    // MODULE ROUTING - PENDING CLOSE
    // ========================================================================

    /**
     * @notice Process pending close positions
     */
    function processPendingClosePositions(uint256 maxPositions) external {
        _delegateToPendingClose(
            abi.encodeWithSignature("processPendingClosePositions(uint256)", maxPositions)
        );
    }

    /**
     * @notice Cancel pending close request
     */
    function cancelPendingClose(uint64 positionId) external {
        _delegateToPendingClose(abi.encodeWithSignature("cancelPendingClose(uint64)", positionId));
    }

    // ========================================================================
    // MODULE ROUTING - ADMIN FUNCTIONS
    // ========================================================================

    /**
     * @notice Set settlement engine address
     */
    function setSettlementEngine(address _settlementEngine) external {
        _delegateToCore(abi.encodeWithSignature("setSettlementEngine(address)", _settlementEngine));
    }

    /**
     * @notice Set vault manager address
     */
    function setVaultManager(address _vaultManager) external {
        _delegateToCore(abi.encodeWithSignature("setVaultManager(address)", _vaultManager));
    }

    /**
     * @notice Set price feed manager address
     */
    function setPriceFeedManager(address _priceFeedManager) external {
        _delegateToCore(abi.encodeWithSignature("setPriceFeedManager(address)", _priceFeedManager));
    }

    /**
     * @notice Set access controller address
     */
    function setAccessController(address _accessController) external {
        _delegateToCore(abi.encodeWithSignature("setAccessController(address)", _accessController));
    }

    /**
     * @notice Pause contract
     */
    function pause() external {
        _delegateToCore(abi.encodeWithSignature("pause()"));
    }

    /**
     * @notice Emergency pause
     */
    function pauseEmergency() external {
        _delegateToCore(abi.encodeWithSignature("pauseEmergency()"));
    }

    /**
     * @notice Unpause contract
     */
    function unpause() external {
        _delegateToCore(abi.encodeWithSignature("unpause()"));
    }

    /**
     * @notice Update maintenance margin ratio
     */
    function setMaintenanceMarginRatio(uint256 newRatio) external {
        _delegateToCore(abi.encodeWithSignature("setMaintenanceMarginRatio(uint256)", newRatio));
    }

    /**
     * @notice Update leverage limits
     */
    function setLeverageLimits(uint8 _minLeverage, uint8 _maxLeverage) external {
        _delegateToCore(
            abi.encodeWithSignature("setLeverageLimits(uint8,uint8)", _minLeverage, _maxLeverage)
        );
    }

    /**
     * @notice Update minimum position hold time
     */
    function setMinPositionHoldTime(uint256 _minPositionHoldTime) external {
        _delegateToCore(
            abi.encodeWithSignature("setMinPositionHoldTime(uint256)", _minPositionHoldTime)
        );
    }

    // ========================================================================
    // VIEW FUNCTIONS (Direct Storage Access)
    // ========================================================================

    /**
     * @notice Get position details
     */
    function getPosition(uint64 positionId) external view returns (PositionLib.Position memory) {
        return PositionStorageLib.getCoreStorage().positions[positionId];
    }

    /**
     * @notice Get position (alias for positions mapping)
     */
    function positions(uint64 positionId) external view returns (PositionLib.Position memory) {
        return PositionStorageLib.getCoreStorage().positions[positionId];
    }

    /**
     * @notice Check if position can be liquidated
     */
    function checkLiquidation(uint64 positionId, uint256 currentPrice)
        external
        view
        returns (bool)
    {
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();
        PositionLib.Position storage pos = core.positions[positionId];

        // Check price-based liquidation first
        if (PositionLib.isLiquidated(pos, currentPrice)) {
            return true;
        }

        // Check funding-based liquidation
        if (core.vaultManager != address(0)) {
            address vaultAddress = IVaultManager(core.vaultManager).getVault(pos.projectToken);
            if (vaultAddress != address(0)) {
                (bool fundingLiquidatable,,) = IAssetVault(vaultAddress)
                    .checkFundingLiquidation(
                        pos.amount,
                        pos.entryFundingRateLong,
                        pos.entryFundingRateShort,
                        pos.positionSize,
                        pos.direction,
                        core.maintenanceMarginRatio
                    );
                if (fundingLiquidatable) {
                    return true;
                }
            }
        }

        return false;
    }

    /**
     * @notice Check liquidation with detailed funding info
     */
    function checkLiquidationDetailed(uint64 positionId, uint256 currentPrice)
        external
        view
        returns (bool isLiquidatable, uint8 reason, int256 fundingOwed, uint256 effectiveCollateral)
    {
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();
        PositionLib.Position storage pos = core.positions[positionId];

        // Check price-based liquidation first
        if (PositionLib.isLiquidated(pos, currentPrice)) {
            return (true, 1, 0, pos.amount); // reason 1 = price
        }

        // Check funding-based liquidation
        if (core.vaultManager != address(0)) {
            address vaultAddress = IVaultManager(core.vaultManager).getVault(pos.projectToken);
            if (vaultAddress != address(0)) {
                (bool fundingLiquidatable, int256 _fundingOwed, uint256 _effectiveCollateral) = IAssetVault(
                        vaultAddress
                    )
                    .checkFundingLiquidation(
                        pos.amount,
                        pos.entryFundingRateLong,
                        pos.entryFundingRateShort,
                        pos.positionSize,
                        pos.direction,
                        core.maintenanceMarginRatio
                    );

                if (fundingLiquidatable) {
                    return (true, 2, _fundingOwed, _effectiveCollateral); // reason 2 = funding
                }

                return (false, 0, _fundingOwed, _effectiveCollateral);
            }
        }

        return (false, 0, 0, pos.amount);
    }

    /**
     * @notice Get leverage configuration
     */
    function getLeverageConfig()
        external
        view
        returns (uint8 _minLeverage, uint8 _maxLeverage, uint256 _maintenanceMarginRatio)
    {
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();
        return (core.minLeverage, core.maxLeverage, core.maintenanceMarginRatio);
    }

    /**
     * @notice Calculate potential liquidation price
     */
    function calculatePotentialLiquidationPrice(uint256 openPrice, uint8 direction, uint8 leverage)
        external
        view
        returns (uint256)
    {
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();
        return PositionLib.calculateLiquidationPrice(
            openPrice, direction, leverage, core.maintenanceMarginRatio
        );
    }

    /**
     * @notice Get position P&L at current price
     */
    function getPositionPnL(uint64 positionId, uint256 currentPrice)
        external
        view
        returns (int256 pnl, int256 pnlPercentage)
    {
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();
        PositionLib.Position storage pos = core.positions[positionId];
        return PositionLib.calculateUnrealizedPnL(pos, currentPrice);
    }

    /**
     * @notice Get position funding information
     */
    function getPositionFundingInfo(uint64 positionId)
        external
        view
        returns (
            int256 fundingOwed,
            uint256 effectiveCollateral,
            uint256 hourlyFundingRate,
            bool isLongPaying
        )
    {
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();
        PositionLib.Position storage pos = core.positions[positionId];
        if (pos.user == address(0)) revert PositionNotFound();

        if (core.vaultManager == address(0)) {
            return (0, pos.amount, 0, false);
        }

        address vaultAddress = IVaultManager(core.vaultManager).getVault(pos.projectToken);
        if (vaultAddress == address(0)) {
            return (0, pos.amount, 0, false);
        }

        // Calculate funding owed
        fundingOwed = IAssetVault(vaultAddress)
            .calculatePositionFunding(
                pos.entryFundingRateLong, pos.entryFundingRateShort, pos.positionSize, pos.direction
            );

        // Calculate effective collateral
        if (fundingOwed > 0) {
            uint256 deduction = uint256(fundingOwed);
            effectiveCollateral = pos.amount > deduction ? pos.amount - deduction : 0;
        } else {
            effectiveCollateral = pos.amount + uint256(-fundingOwed);
        }

        // Get current funding rate
        uint256 imbalanceBps;
        bool hasCounterparty;
        (hourlyFundingRate, isLongPaying, imbalanceBps, hasCounterparty) =
            IAssetVault(vaultAddress).getCurrentHourlyFundingRate();

        return (fundingOwed, effectiveCollateral, hourlyFundingRate, isLongPaying);
    }

    /**
     * @notice Get remaining hold time for a position
     */
    function getRemainingHoldTime(uint64 positionId) external view returns (uint256 remainingTime) {
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();
        PositionLib.Position storage pos = core.positions[positionId];
        if (pos.user == address(0)) revert PositionNotFound();

        if (block.timestamp >= pos.minCloseTime) {
            return 0;
        }

        return pos.minCloseTime - block.timestamp;
    }

    /**
     * @notice Check if position can be closed by user
     */
    function canClosePosition(uint64 positionId)
        external
        view
        returns (bool canClose, string memory reason)
    {
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();
        PositionLib.Position storage pos = core.positions[positionId];

        if (pos.user == address(0)) {
            return (false, "Position not found");
        }

        if (pos.state != PositionLib.POSITION_STATE_OPEN) {
            return (false, "Position not open");
        }

        if (block.timestamp < pos.minCloseTime) {
            return (false, "Minimum hold time not reached");
        }

        return (true, "");
    }

    /**
     * @notice Get cached token decimals
     */
    function getCachedTokenDecimals(address token) external view returns (uint8) {
        return PositionStorageLib.getCoreStorage().tokenDecimalsCache[token];
    }

    /**
     * @notice Get contract version
     */
    function version() external pure returns (string memory) {
        return "2.0.0-modular";
    }

    // ========================================================================
    // PENDING CLOSE VIEW FUNCTIONS
    // ========================================================================

    /**
     * @notice Get all pending close position IDs
     */
    function getPendingClosePositionIds() external view returns (uint64[] memory) {
        return PositionStorageLib.getPendingCloseStorage().pendingClosePositionIds;
    }

    /**
     * @notice Get pending close request details
     */
    function getPendingCloseRequest(uint64 positionId)
        external
        view
        returns (PositionStorageLib.PendingCloseRequest memory)
    {
        PositionStorageLib.PendingCloseStorage storage pending =
            PositionStorageLib.getPendingCloseStorage();
        if (!pending.isPendingClose[positionId]) revert NoPendingCloseRequest();
        return pending.pendingCloseRequests[positionId];
    }

    /**
     * @notice Get count of pending close positions
     */
    function getPendingCloseCount() external view returns (uint256) {
        return PositionStorageLib.getPendingCloseStorage().pendingClosePositionIds.length;
    }

    /**
     * @notice Check if position has a pending close request
     */
    function hasPendingCloseRequest(uint64 positionId) external view returns (bool) {
        return PositionStorageLib.getPendingCloseStorage().isPendingClose[positionId];
    }

    /**
     * @notice Get pending close requests (alias for mapping)
     */
    function pendingCloseRequests(uint64 positionId)
        external
        view
        returns (PositionStorageLib.PendingCloseRequest memory)
    {
        return PositionStorageLib.getPendingCloseStorage().pendingCloseRequests[positionId];
    }

    /**
     * @notice Check if position is pending close (alias)
     */
    function isPendingClose(uint64 positionId) external view returns (bool) {
        return PositionStorageLib.getPendingCloseStorage().isPendingClose[positionId];
    }

    /**
     * @notice Get pending close position IDs (alias)
     */
    function pendingClosePositionIds(uint256 index) external view returns (uint64) {
        return PositionStorageLib.getPendingCloseStorage().pendingClosePositionIds[index];
    }

    /**
     * @notice Get batch of pending close positions with full details
     */
    function getPendingClosePositionsBatch(uint256 offset, uint256 limit)
        external
        view
        returns (
            uint64[] memory positionIds,
            PositionStorageLib.PendingCloseRequest[] memory requests,
            PositionLib.Position[] memory positionsData
        )
    {
        PositionStorageLib.PendingCloseStorage storage pending =
            PositionStorageLib.getPendingCloseStorage();
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();

        uint256 total = pending.pendingClosePositionIds.length;
        if (offset >= total) {
            return (
                new uint64[](0),
                new PositionStorageLib.PendingCloseRequest[](0),
                new PositionLib.Position[](0)
            );
        }

        uint256 end = offset + limit;
        if (end > total) {
            end = total;
        }

        uint256 resultLength = end - offset;
        positionIds = new uint64[](resultLength);
        requests = new PositionStorageLib.PendingCloseRequest[](resultLength);
        positionsData = new PositionLib.Position[](resultLength);

        for (uint256 i = 0; i < resultLength; i++) {
            uint64 posId = pending.pendingClosePositionIds[offset + i];
            positionIds[i] = posId;
            requests[i] = pending.pendingCloseRequests[posId];
            positionsData[i] = core.positions[posId];
        }

        return (positionIds, requests, positionsData);
    }

    // ========================================================================
    // STATE GETTERS (for compatibility)
    // ========================================================================

    /**
     * @notice Get settlement engine address
     */
    function settlementEngine() external view returns (address) {
        return PositionStorageLib.getCoreStorage().settlementEngine;
    }

    /**
     * @notice Get vault manager address
     */
    function vaultManager() external view returns (address) {
        return PositionStorageLib.getCoreStorage().vaultManager;
    }

    /**
     * @notice Get price feed manager address
     */
    function priceFeedManager() external view returns (address) {
        return PositionStorageLib.getCoreStorage().priceFeedManager;
    }

    /**
     * @notice Get access controller
     */
    function accessController() external view returns (address) {
        return PositionStorageLib.getCoreStorage().accessController;
    }

    /**
     * @notice Get maintenance margin ratio
     */
    function maintenanceMarginRatio() external view returns (uint256) {
        return PositionStorageLib.getCoreStorage().maintenanceMarginRatio;
    }

    /**
     * @notice Get min leverage
     */
    function minLeverage() external view returns (uint8) {
        return PositionStorageLib.getCoreStorage().minLeverage;
    }

    /**
     * @notice Get max leverage
     */
    function maxLeverage() external view returns (uint8) {
        return PositionStorageLib.getCoreStorage().maxLeverage;
    }

    /**
     * @notice Get min position hold time
     */
    function minPositionHoldTime() external view returns (uint256) {
        return PositionStorageLib.getCoreStorage().minPositionHoldTime;
    }

    /**
     * @notice Check if paused
     */
    function paused() external view returns (bool) {
        return PositionStorageLib.getCoreStorage().paused;
    }

    // ========================================================================
    // MODULE MANAGEMENT
    // ========================================================================

    /**
     * @notice Get module address
     */
    function getModule(bytes4 moduleId) external view returns (address) {
        PositionStorageLib.RouterStorage storage router = PositionStorageLib.getRouterStorage();

        if (moduleId == MODULE_CORE) return router.coreModule;
        if (moduleId == MODULE_PENDING_CLOSE) return router.pendingCloseModule;

        return address(0);
    }

    /**
     * @notice Update module address
     * @dev Only callable by admin
     */
    function updateModule(bytes4 moduleId, address newModule) external {
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();
        if (core.accessController == address(0)) revert AccessControllerNotSet();

        VaultAccessController ac = VaultAccessController(core.accessController);
        if (!ac.hasRole(ac.DEFAULT_ADMIN_ROLE(), msg.sender)) {
            revert NotAuthorized();
        }

        if (newModule == address(0)) revert InvalidModule();

        PositionStorageLib.RouterStorage storage router = PositionStorageLib.getRouterStorage();
        address oldModule;

        if (moduleId == MODULE_CORE) {
            oldModule = router.coreModule;
            router.coreModule = newModule;
        } else if (moduleId == MODULE_PENDING_CLOSE) {
            oldModule = router.pendingCloseModule;
            router.pendingCloseModule = newModule;
        } else {
            revert InvalidModule();
        }

        emit ModuleUpdated(moduleId, oldModule, newModule, block.timestamp);
    }

    // ========================================================================
    // INTERNAL DELEGATION FUNCTIONS
    // ========================================================================

    function _delegateToCore(bytes memory data) internal returns (bytes memory) {
        PositionStorageLib.RouterStorage storage router = PositionStorageLib.getRouterStorage();
        return _delegate(router.coreModule, data);
    }

    function _delegateToPendingClose(bytes memory data) internal returns (bytes memory) {
        PositionStorageLib.RouterStorage storage router = PositionStorageLib.getRouterStorage();
        return _delegate(router.pendingCloseModule, data);
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

    /**
     * @notice Authorize upgrade with Timelock + Emergency Guardian pattern
     * @dev Two paths for upgrade:
     *      1. Normal path: UPGRADER_ROLE (Timelock) - no restrictions
     *      2. Emergency path: EMERGENCY_ROLE/GUARDIAN_ROLE - requires contract to be paused first
     */
    function _authorizeUpgrade(address newImplementation) internal override {
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();
        if (core.accessController == address(0)) revert AccessControllerNotSet();

        VaultAccessController ac = VaultAccessController(core.accessController);

        // Path 1: Normal upgrade via Timelock (UPGRADER_ROLE)
        if (ac.hasRole(ac.UPGRADER_ROLE(), msg.sender)) {
            return; // Authorized
        }

        // Path 2: Emergency upgrade via Guardian/Multisig - only if paused
        if (
            ac.hasRole(ac.EMERGENCY_ROLE(), msg.sender)
                || ac.hasRole(ac.GUARDIAN_ROLE(), msg.sender)
        ) {
            if (!core.paused) {
                revert MustPauseBeforeEmergencyUpgrade();
            }
            emit EmergencyUpgrade(newImplementation, msg.sender, block.timestamp);
            return; // Authorized
        }

        // No valid role - revert
        revert NotAuthorized();
    }

    // ========================================================================
    // ERRORS (for view functions)
    // ========================================================================

    error PositionNotFound();
    error NoPendingCloseRequest();
}

