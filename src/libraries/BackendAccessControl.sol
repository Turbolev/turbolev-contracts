// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title BackendAccessControl
 * @notice Access control contract for managing multiple backend addresses
 * @dev Similar to Ownable but for backend role management
 *
 * Features:
 * - Support multiple backend addresses
 * - Add/remove backend addresses
 * - Check if address has backend role
 * - Only owner can manage backend addresses
 */
abstract contract BackendAccessControl {
    // ========================================================================
    // STATE VARIABLES
    // ========================================================================

    /// @notice Mapping to track backend addresses
    mapping(address => bool) private _backends;

    /// @notice Array of all backend addresses for enumeration
    address[] private _backendList;

    /// @notice MEDIUM-04 FIX: Mapping to track backend index in array (prevent gas griefing)
    /// @dev Index is stored as (actualIndex + 1) to distinguish from non-existent (0)
    mapping(address => uint256) private _backendIndex;

    // ========================================================================
    // EVENTS
    // ========================================================================

    event BackendAdded(address indexed backend);
    event BackendRemoved(address indexed backend);

    // ========================================================================
    // ERRORS
    // ========================================================================

    error NotBackend();
    error InvalidBackendAddress();
    error BackendAlreadyExists();
    error BackendNotFound();

    // ========================================================================
    // MODIFIERS
    // ========================================================================

    /**
     * @notice Modifier to check if caller is a backend
     */
    modifier onlyBackend() {
        if (!isBackend(msg.sender)) revert NotBackend();
        _;
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /**
     * @notice Check if an address has backend role
     * @param account Address to check
     * @return bool True if address is a backend
     */
    function isBackend(address account) public view returns (bool) {
        return _backends[account];
    }

    /**
     * @notice Get all backend addresses
     * @return address[] Array of backend addresses
     */
    function getBackends() external view returns (address[] memory) {
        return _backendList;
    }

    /**
     * @notice Get number of backends
     * @return uint256 Number of backend addresses
     */
    function getBackendCount() external view returns (uint256) {
        return _backendList.length;
    }

    // ========================================================================
    // INTERNAL FUNCTIONS
    // ========================================================================

    /**
     * @notice Add a backend address (internal)
     * @param backend Address to add as backend
     * @dev MEDIUM-04 FIX: Store index mapping for O(1) removal
     */
    function _addBackend(address backend) internal {
        if (backend == address(0)) revert InvalidBackendAddress();
        if (_backends[backend]) revert BackendAlreadyExists();

        _backends[backend] = true;
        _backendList.push(backend);
        _backendIndex[backend] = _backendList.length; // Store as (index + 1)

        emit BackendAdded(backend);
    }

    /**
     * @notice Remove a backend address (internal)
     * @param backend Address to remove from backends
     * @dev MEDIUM-04 FIX: Use index mapping for O(1) removal instead of loop
     */
    function _removeBackend(address backend) internal {
        if (!_backends[backend]) revert BackendNotFound();

        _backends[backend] = false;

        // MEDIUM-04 FIX: O(1) removal using index mapping
        uint256 indexPlusOne = _backendIndex[backend];
        if (indexPlusOne > 0) {
            uint256 index = indexPlusOne - 1;
            uint256 lastIndex = _backendList.length - 1;

            if (index != lastIndex) {
                // Swap with last element
                address lastBackend = _backendList[lastIndex];
                _backendList[index] = lastBackend;
                _backendIndex[lastBackend] = indexPlusOne; // Update swapped element's index
            }

            _backendList.pop();
            delete _backendIndex[backend];
        }

        emit BackendRemoved(backend);
    }

    /**
     * @notice Clear all backends (internal)
     * @dev MEDIUM-04 NOTE: Loop accepted here as this is rare admin operation
     */
    function _clearBackends() internal {
        uint256 length = _backendList.length;
        for (uint256 i = 0; i < length; i++) {
            address backend = _backendList[i];
            _backends[backend] = false;
            delete _backendIndex[backend]; // MEDIUM-04 FIX: Clear index mapping
            emit BackendRemoved(backend);
        }
        delete _backendList;
    }
}
