// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title BackendAccessControlUpgradeable
 * @notice Upgradeable access control contract for managing multiple backend addresses
 * @dev Similar to Ownable but for backend role management - Upgradeable version
 *
 * Features:
 * - Support multiple backend addresses
 * - Add/remove backend addresses
 * - Check if address has backend role
 * - Only owner can manage backend addresses
 * - UUPS Upgradeable pattern compatible
 */
abstract contract BackendAccessControlUpgradeable is Initializable {
    // ========================================================================
    // STATE VARIABLES
    // ========================================================================

    /// @notice Mapping to track backend addresses
    mapping(address => bool) private _backends;

    /// @notice Array of all backend addresses for enumeration
    address[] private _backendList;

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
    // INITIALIZER
    // ========================================================================

    /**
     * @notice Initialize backend access control
     * @dev Should be called in the initializer of the inheriting contract
     */
    function __BackendAccessControl_init() internal onlyInitializing {
        __BackendAccessControl_init_unchained();
    }

    function __BackendAccessControl_init_unchained() internal onlyInitializing {
        // No initialization needed
    }

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
     */
    function _addBackend(address backend) internal {
        if (backend == address(0)) revert InvalidBackendAddress();
        if (_backends[backend]) revert BackendAlreadyExists();

        _backends[backend] = true;
        _backendList.push(backend);

        emit BackendAdded(backend);
    }

    /**
     * @notice Remove a backend address (internal)
     * @param backend Address to remove from backends
     */
    function _removeBackend(address backend) internal {
        if (!_backends[backend]) revert BackendNotFound();

        _backends[backend] = false;

        // Remove from array
        for (uint256 i = 0; i < _backendList.length; i++) {
            if (_backendList[i] == backend) {
                _backendList[i] = _backendList[_backendList.length - 1];
                _backendList.pop();
                break;
            }
        }

        emit BackendRemoved(backend);
    }

    /**
     * @notice Clear all backends (internal)
     */
    function _clearBackends() internal {
        for (uint256 i = 0; i < _backendList.length; i++) {
            address backend = _backendList[i];
            _backends[backend] = false;
            emit BackendRemoved(backend);
        }
        delete _backendList;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[48] private __gap;
}
