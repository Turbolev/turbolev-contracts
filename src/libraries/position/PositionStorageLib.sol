// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./PositionLib.sol";

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
    string internal constant NAMESPACE_CORE = "turbolev.position.core";

    /// @dev Namespace for router storage
    string internal constant NAMESPACE_ROUTER = "turbolev.position.router";

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
    // ENUMS
    // ========================================================================

    enum PositionClosedBy {
        USER_REQUESTED, // 0 - User requested close
        LIQUIDATION, // 1 - Position liquidated
        TAKE_PROFIT, // 2 - Take profit requested
        STOP_LOSS, // 3 - Stop loss requested
        MAX_PROFIT_REACHED // 4 - Max profit reached
    }

    // ========================================================================
    // NAMESPACED STORAGE STRUCTS
    // ========================================================================

    /// @custom:storage-location erc7201:turbolev.position.core
    struct CoreStorage {
        // External addresses
        address settlementEngine;
        address vaultManager;
        address priceFeedManager;
        address accessController;
        // Position tracking
        uint64 nextPositionId;
        mapping(uint64 => PositionLib.Position) positions;
        // Open position counter (incremented on open, decremented on close/liquidation)
        // Used by updateModule to guard against module swaps while positions are active.
        uint64 openPositionCount;
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

    /// @custom:storage-location erc7201:turbolev.position.router
    struct RouterStorage {
        // Module addresses
        address coreModule;
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

    /// @notice Maximum allowed price age for oracle validation (60 seconds)
    /// @dev Tightened from 1 hour to limit cherry-pick window for Pyth pull oracle (R-05)
    uint256 internal constant MAX_ALLOWED_PRICE_AGE = 60;

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
    function getAllNamespaces() internal pure returns (string[2] memory namespaces) {
        namespaces[0] = NAMESPACE_CORE;
        namespaces[1] = NAMESPACE_ROUTER;
    }

    /**
     * @notice Get all calculated storage slots
     * @return slots Array of all EIP-7201 calculated slots
     */
    function getAllSlots() internal pure returns (bytes32[2] memory slots) {
        slots[0] = calculateEIP7201Slot(NAMESPACE_CORE);
        slots[1] = calculateEIP7201Slot(NAMESPACE_ROUTER);
    }

    /**
     * @notice Verify all storage slots are unique (no collisions)
     * @return unique True if all slots are unique
     */
    function verifyAllSlotsUnique() internal pure returns (bool unique) {
        bytes32[2] memory slots = getAllSlots();
        for (uint256 i = 0; i < 2; i++) {
            for (uint256 j = i + 1; j < 2; j++) {
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

