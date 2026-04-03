// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../libraries/position/PositionStorageLib.sol";
import "../vault-modular/VaultAccessController.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title PositionModuleBase
 * @notice Abstract base contract for all position modules
 * @dev Provides:
 *      - Storage accessors via PositionStorageLib
 *      - Access control modifiers via VaultAccessController
 *      - Reentrancy guard using shared storage
 *      - Pausable functionality using shared storage
 *      - Common utility functions
 *
 * All modules (PositionCore, PositionPendingClose) inherit from this contract.
 * Modules are called via delegatecall from PositionRouter, so they share storage.
 */
abstract contract PositionModuleBase {
    using SafeERC20 for IERC20;

    // ========================================================================
    // ERRORS
    // ========================================================================

    error InvalidAddress();
    error InvalidAmount();
    error InvalidDirection();
    error InvalidPrice();
    error InvalidLeverage();
    error PositionNotFound();
    error PositionNotOpen();
    error NotPositionOwner();
    error PositionAlreadyLiquidated();
    error RiskLimitExceeded();
    error SettlementFailed();
    error TransferFailed();
    error InvalidMaintenanceMarginRatio();
    error InvalidPriceFeedId();
    error InvalidCollateralToken();
    error PositionClosedTooEarly();
    error InvalidHoldTime();
    error DeadlineExpired();
    error SlippageExceeded();
    error PriceStale();
    error DirectTransferNotAllowed();
    error NativeTokenNotAllowed();
    error NoPendingCloseRequest();
    error TooManyPendingCloseRequests();
    error TokenDecimalsNotSupported(uint8 decimals);
    error NotPositionKeeper();
    error AccessControllerNotSet();
    error MustPauseBeforeEmergencyUpgrade();
    error NotAuthorized();
    error PositionPaused();
    error PositionNotPaused();
    error ReentrancyGuardReentrantCall();
    error VaultManagerNotSet();
    error ExcessiveMargin();
    error OracleFetchFailed(bytes reason);
    error InconsistentLiquidationParams();
    error EthRefundFailed();

    // ========================================================================
    // MODIFIERS - ACCESS CONTROL
    // ========================================================================

    /**
     * @notice Only position keeper
     */
    modifier onlyPositionKeeper() {
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();
        if (core.accessController == address(0)) revert AccessControllerNotSet();

        VaultAccessController ac = VaultAccessController(core.accessController);
        if (!ac.isPositionKeeper(msg.sender)) {
            revert NotPositionKeeper();
        }
        _;
    }

    /**
     * @notice Only owner (via AccessController DEFAULT_ADMIN_ROLE or VAULT_ADMIN_ROLE)
     */
    modifier onlyOwner() {
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();
        if (core.accessController == address(0)) revert AccessControllerNotSet();

        VaultAccessController ac = VaultAccessController(core.accessController);
        if (
            !ac.hasRole(ac.DEFAULT_ADMIN_ROLE(), msg.sender)
                && !ac.hasRole(ac.VAULT_ADMIN_ROLE(), msg.sender)
        ) {
            revert NotAuthorized();
        }
        _;
    }

    // ========================================================================
    // MODIFIERS - REENTRANCY GUARD (Shared Storage)
    // ========================================================================

    /**
     * @notice Reentrancy guard using shared storage
     * @dev Must use shared storage since modules are called via delegatecall
     */
    modifier nonReentrant() {
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();

        if (core.reentrancyStatus == PositionStorageLib.ENTERED) {
            revert ReentrancyGuardReentrantCall();
        }

        core.reentrancyStatus = PositionStorageLib.ENTERED;
        _;
        core.reentrancyStatus = PositionStorageLib.NOT_ENTERED;
    }

    // ========================================================================
    // MODIFIERS - PAUSABLE (Shared Storage)
    // ========================================================================

    /**
     * @notice Require position manager not paused
     */
    modifier whenNotPaused() {
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();
        if (core.paused) {
            revert PositionPaused();
        }
        _;
    }

    /**
     * @notice Require position manager paused
     */
    modifier whenPaused() {
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();
        if (!core.paused) {
            revert PositionNotPaused();
        }
        _;
    }

    // ========================================================================
    // STORAGE SHORTCUTS
    // ========================================================================

    /**
     * @notice Get core storage
     */
    function _core() internal pure returns (PositionStorageLib.CoreStorage storage) {
        return PositionStorageLib.getCoreStorage();
    }

    /**
     * @notice Get router storage
     */
    function _router() internal pure returns (PositionStorageLib.RouterStorage storage) {
        return PositionStorageLib.getRouterStorage();
    }

    // ========================================================================
    // UTILITY FUNCTIONS
    // ========================================================================

    /**
     * @notice Check if paused
     */
    function _isPaused() internal view returns (bool) {
        return PositionStorageLib.getCoreStorage().paused;
    }

    /**
     * @notice Pause the position manager
     * @dev Internal function, to be exposed by modules with proper access control
     */
    function _pause() internal {
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();
        core.paused = true;
    }

    /**
     * @notice Unpause the position manager
     * @dev Internal function, to be exposed by modules with proper access control
     */
    function _unpause() internal {
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();
        core.paused = false;
    }

    /**
     * @notice Calculate max age for price validation with cap
     * @param deadline The deadline timestamp from user
     * @return maxAge The capped max age for price validation
     */
    function _calculateMaxAge(uint256 deadline) internal view returns (uint256 maxAge) {
        maxAge = deadline - block.timestamp;
        if (maxAge > PositionStorageLib.MAX_ALLOWED_PRICE_AGE) {
            maxAge = PositionStorageLib.MAX_ALLOWED_PRICE_AGE;
        }
    }

    /**
     * @notice Forward any ETH held by the router (e.g. Pyth fee refund from PriceFeedManager) to the caller
     * @dev Called at end of payable flows; delegatecall context => address(this) is PositionRouter
     */
    function _refundRemainingEth() internal {
        uint256 bal = address(this).balance;
        if (bal > 0) {
            (bool sent,) = payable(msg.sender).call{ value: bal }("");
            if (!sent) revert EthRefundFailed();
        }
    }

    /**
     * @notice Validate address is not zero
     */
    modifier validAddress(address addr) {
        if (addr == address(0)) revert InvalidAddress();
        _;
    }
}

