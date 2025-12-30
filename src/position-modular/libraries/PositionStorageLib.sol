// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../../libraries/PositionLib.sol";

/**
 * @title PositionStorageLib
 * @notice EIP-7201 Namespaced Storage Library for Modular PositionManager
 * @dev All storage structs use namespaced storage slots to prevent collisions
 *      when using delegatecall pattern across multiple modules.
 *
 *      Storage Namespaces:
 *      - CoreStorage: Positions, settings, addresses
 *      - PendingCloseStorage: Pending close requests and queue
 *      - RouterStorage: Module addresses, initialization
 *
 *      EIP-7201 Formula:
 *      keccak256(abi.encode(uint256(keccak256("namespace.id")) - 1)) & ~bytes32(uint256(0xff))
 */
library PositionStorageLib {
    // ========================================================================
    // EIP-7201 NAMESPACE CONSTANTS
    // ========================================================================

    /// @dev Namespace for core position storage
    string internal constant NAMESPACE_CORE = "boolean.position.core";

    /// @dev Namespace for pending close storage
    string internal constant NAMESPACE_PENDING_CLOSE = "boolean.position.pending_close";

    /// @dev Namespace for router storage
    string internal constant NAMESPACE_ROUTER = "boolean.position.router";

    // ========================================================================
    // EIP-7201 SLOT CALCULATION
    // ========================================================================

    /**
     * @notice Calculate EIP-7201 storage slot from namespace string
     * @param namespace The namespace identifier
     * @return slot The calculated storage slot
     */
    function calculateEIP7201Slot(string memory namespace) internal pure returns (bytes32 slot) {
        bytes32 namespaceHash = keccak256(bytes(namespace));
        slot = keccak256(abi.encode(uint256(namespaceHash) - 1)) & ~bytes32(uint256(0xff));
    }

    // ========================================================================
    // PENDING CLOSE STRUCTS
    // ========================================================================

    /// @notice Pending close reason enum
    enum PendingCloseReason {
        NONE, // 0 - Default/not set
        PRICE_STALE, // 1 - Oracle price is stale
        PRICE_NOT_ACCEPTABLE, // 2 - Price doesn't meet maxAcceptablePrice
        INVALID_PRICE, // 3 - Price is invalid (zero or negative)
        SETTLEMENT_ENGINE_NOT_SET, // 4 - Settlement engine address not set
        CANCELLED_BY_ADMIN, // 5 - Admin cancelled the pending close
        ORACLE_ERROR // 6 - Oracle call failed
    }

    enum PositionClosedBy {
        USER_REQUESTED, // 0 - User requested close
        LIQUIDATION, // 1 - Position liquidated
        TAKE_PROFIT, // 2 - Take profit requested
        STOP_LOSS, // 3 - Stop loss requested
        MAX_PROFIT_REACHED, // 4 - Max profit reached
        PENDING_CLOSE_REQUESTED // 5 - Pending close requested
    }

    /// @notice Pending close request data
    struct PendingCloseRequest {
        uint64 positionId;
        uint256 requestTime;
        uint256 deadline;
        uint256 maxAcceptablePrice;
        uint256 closePrice;
        uint256 pricePublishTime;
    }

    // ========================================================================
    // NAMESPACED STORAGE STRUCTS
    // ========================================================================

    /// @custom:storage-location erc7201:boolean.position.core
    struct CoreStorage {
        // External addresses
        address settlementEngine;
        address vaultManager;
        address priceFeedManager;
        address accessController;
        // Position tracking
        uint64 nextPositionId;
        mapping(uint64 => PositionLib.Position) positions;
        // Configuration
        uint256 maintenanceMarginRatio;
        uint8 minLeverage;
        uint8 maxLeverage;
        uint256 minPositionHoldTime;
        // Token decimals cache
        mapping(address => uint8) tokenDecimalsCache;
        // Reentrancy guard
        uint256 reentrancyStatus;
        // Paused state
        bool paused;
    }

    /// @custom:storage-location erc7201:boolean.position.pending_close
    struct PendingCloseStorage {
        // Pending close requests
        mapping(uint64 => PendingCloseRequest) pendingCloseRequests;
        uint64[] pendingClosePositionIds;
        mapping(uint64 => bool) isPendingClose;
    }

    /// @custom:storage-location erc7201:boolean.position.router
    struct RouterStorage {
        // Module addresses
        address coreModule;
        address pendingCloseModule;
        // Initialization flag
        bool initialized;
    }

    // ========================================================================
    // STORAGE ACCESSORS
    // ========================================================================

    /**
     * @notice Get core storage
     * @return $ CoreStorage struct pointer
     */
    function getCoreStorage() internal pure returns (CoreStorage storage $) {
        bytes32 slot = calculateEIP7201Slot(NAMESPACE_CORE);
        assembly {
            $.slot := slot
        }
    }

    /**
     * @notice Get pending close storage
     * @return $ PendingCloseStorage struct pointer
     */
    function getPendingCloseStorage() internal pure returns (PendingCloseStorage storage $) {
        bytes32 slot = calculateEIP7201Slot(NAMESPACE_PENDING_CLOSE);
        assembly {
            $.slot := slot
        }
    }

    /**
     * @notice Get router storage
     * @return $ RouterStorage struct pointer
     */
    function getRouterStorage() internal pure returns (RouterStorage storage $) {
        bytes32 slot = calculateEIP7201Slot(NAMESPACE_ROUTER);
        assembly {
            $.slot := slot
        }
    }

    // ========================================================================
    // CONSTANTS
    // ========================================================================

    /// @notice Minimum supported token decimals
    uint8 internal constant MIN_SUPPORTED_DECIMALS = 6;

    /// @notice Maximum supported token decimals
    uint8 internal constant MAX_SUPPORTED_DECIMALS = 18;

    /// @notice Maximum allowed min position hold time (1 hour)
    uint256 internal constant MAX_MIN_POSITION_HOLD_TIME = 3600;

    /// @notice Maximum allowed price age for oracle validation (1 hour)
    uint256 internal constant MAX_ALLOWED_PRICE_AGE = 1 hours;

    // Reentrancy status values
    uint256 internal constant NOT_ENTERED = 1;
    uint256 internal constant ENTERED = 2;

    // ========================================================================
    // SLOT VERIFICATION HELPERS
    // ========================================================================

    /**
     * @notice Get all namespace strings
     * @return namespaces Array of all registered namespace strings
     */
    function getAllNamespaces() internal pure returns (string[3] memory namespaces) {
        namespaces[0] = NAMESPACE_CORE;
        namespaces[1] = NAMESPACE_PENDING_CLOSE;
        namespaces[2] = NAMESPACE_ROUTER;
    }

    /**
     * @notice Get all calculated storage slots
     * @return slots Array of all EIP-7201 calculated slots
     */
    function getAllSlots() internal pure returns (bytes32[3] memory slots) {
        slots[0] = calculateEIP7201Slot(NAMESPACE_CORE);
        slots[1] = calculateEIP7201Slot(NAMESPACE_PENDING_CLOSE);
        slots[2] = calculateEIP7201Slot(NAMESPACE_ROUTER);
    }

    /**
     * @notice Verify all storage slots are unique (no collisions)
     * @return unique True if all slots are unique
     */
    function verifyAllSlotsUnique() internal pure returns (bool unique) {
        bytes32[3] memory slots = getAllSlots();
        for (uint256 i = 0; i < 3; i++) {
            for (uint256 j = i + 1; j < 3; j++) {
                if (slots[i] == slots[j]) {
                    return false;
                }
            }
        }
        return true;
    }

    // ========================================================================
    // ERRORS
    // ========================================================================

    error ReentrancyGuardReentrantCall();
    error Paused();
    error NotPaused();
}

