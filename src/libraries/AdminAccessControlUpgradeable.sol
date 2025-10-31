// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title AdminAccessControlUpgradeable
 * @notice Upgradeable access control contract for managing multiple admin addresses
 * @dev Similar to Ownable but for admin role management
 *
 * Features:
 * - Support multiple admin addresses
 * - Add/remove admin addresses
 * - Check if address has admin role
 * - Only owner can manage admin addresses
 * - UUPS Upgradeable pattern compatible
 */
abstract contract AdminAccessControlUpgradeable is Initializable {
    // ========================================================================
    // STATE VARIABLES
    // ========================================================================

    /// @notice Mapping to track admin addresses
    mapping(address => bool) private _admins;

    /// @notice Array of all admin addresses for enumeration
    address[] private _adminList;

    /// @notice Mapping to track admin index in array
    mapping(address => uint256) private _adminIndex;

    // ========================================================================
    // EVENTS
    // ========================================================================

    event AdminAdded(address indexed admin);
    event AdminRemoved(address indexed admin);

    // ========================================================================
    // ERRORS
    // ========================================================================

    error NotAdmin();
    error InvalidAdminAddress();
    error AdminAlreadyExists();
    error AdminNotFound();

    // ========================================================================
    // INITIALIZER
    // ========================================================================

    /**
     * @notice Initialize admin access control
     * @dev Should be called in the initializer of the inheriting contract
     */
    function __AdminAccessControl_init() internal onlyInitializing {
        __AdminAccessControl_init_unchained();
    }

    function __AdminAccessControl_init_unchained() internal onlyInitializing {
        // No initialization needed
    }

    // ========================================================================
    // MODIFIERS
    // ========================================================================

    /**
     * @notice Modifier to check if caller is an admin
     */
    modifier onlyAdmin() {
        if (!isAdmin(msg.sender)) revert NotAdmin();
        _;
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /**
     * @notice Check if an address has admin role
     * @param account Address to check
     * @return bool True if address is an admin
     */
    function isAdmin(address account) public view returns (bool) {
        return _admins[account];
    }

    /**
     * @notice Get all admin addresses
     * @return address[] Array of admin addresses
     */
    function getAdmins() external view returns (address[] memory) {
        return _adminList;
    }

    /**
     * @notice Get number of admins
     * @return uint256 Number of admin addresses
     */
    function getAdminCount() external view returns (uint256) {
        return _adminList.length;
    }

    // ========================================================================
    // INTERNAL FUNCTIONS
    // ========================================================================

    /**
     * @notice Add an admin address (internal)
     * @param admin Address to add as admin
     */
    function _addAdmin(address admin) internal {
        if (admin == address(0)) revert InvalidAdminAddress();
        if (_admins[admin]) revert AdminAlreadyExists();

        _admins[admin] = true;
        _adminList.push(admin);
        _adminIndex[admin] = _adminList.length;

        emit AdminAdded(admin);
    }

    /**
     * @notice Remove an admin address (internal)
     * @param admin Address to remove from admins
     */
    function _removeAdmin(address admin) internal {
        if (!_admins[admin]) revert AdminNotFound();

        _admins[admin] = false;

        uint256 indexPlusOne = _adminIndex[admin];
        if (indexPlusOne > 0) {
            uint256 index = indexPlusOne - 1;
            uint256 lastIndex = _adminList.length - 1;

            if (index != lastIndex) {
                address lastAdmin = _adminList[lastIndex];
                _adminList[index] = lastAdmin;
                _adminIndex[lastAdmin] = indexPlusOne;
            }

            _adminList.pop();
            delete _adminIndex[admin];
        }

        emit AdminRemoved(admin);
    }

    /**
     * @notice Clear all admins (internal)
     */
    function _clearAdmins() internal {
        uint256 length = _adminList.length;
        for (uint256 i = 0; i < length; i++) {
            address admin = _adminList[i];
            _admins[admin] = false;
            delete _adminIndex[admin];
            emit AdminRemoved(admin);
        }
        delete _adminList;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[47] private __gap;
}
