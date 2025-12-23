// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title VersionedBeacon
 * @notice UpgradeableBeacon with version tracking and emergency upgrade support
 * @dev Extends OpenZeppelin UpgradeableBeacon, adds version history
 *
 * Features:
 * - Version tracking for all upgrades
 * - Emergency upgrade for critical bug fixes (admin/guardian only)
 * - Changelog hash storage (IPFS or keccak256)
 * - Timestamp tracking for audit trail
 *
 * Security Model:
 * - Owner (Timelock): Normal upgrades via governance
 * - Admin/Guardian: Emergency upgrades when vault is paused
 *
 * Note: Rollback functionality is not supported because:
 * - Storage layout incompatibility (new fields not understood by old code)
 * - Logic incompatibility (new features not handled by old code)
 * Solution: Use emergency upgrade to new hotfix version instead of rollback
 */
contract VersionedBeacon is UpgradeableBeacon, ReentrancyGuard {
    // ========================================================================
    // STATE VARIABLES
    // ========================================================================

    /// @notice Current version number
    uint256 public currentVersion;

    /// @notice Version → Implementation address
    mapping(uint256 => address) public implementations;

    /// @notice Version → Upgrade timestamp
    mapping(uint256 => uint256) public versionTimestamps;

    /// @notice Version → Description/changelog hash (IPFS or keccak256)
    mapping(uint256 => bytes32) public versionInfo;

    /// @notice Version → Is emergency upgrade
    mapping(uint256 => bool) public isEmergencyUpgrade;

    /// @notice Emergency mode - allows emergency upgrades
    bool public emergencyMode;

    /// @notice Admin addresses that can perform emergency upgrades
    mapping(address => bool) public admins;

    /// @notice Guardian addresses that can perform emergency upgrades
    mapping(address => bool) public guardians;

    /// @notice Flag to track if currently in emergency upgrade context
    /// @dev Used to allow admin/guardian to bypass onlyOwner check during emergency upgrade
    bool private _inEmergencyUpgrade;

    // ========================================================================
    // EVENTS
    // ========================================================================

    event VersionRegistered(
        uint256 indexed version,
        address indexed implementation,
        bytes32 infoHash,
        bool isEmergency,
        uint256 timestamp
    );

    event EmergencyModeActivated(address indexed activatedBy, uint256 timestamp);
    event EmergencyModeDeactivated(address indexed deactivatedBy, uint256 timestamp);

    event AdminAdded(address indexed admin, address indexed addedBy);
    event AdminRemoved(address indexed admin, address indexed removedBy);
    event GuardianAdded(address indexed guardian, address indexed addedBy);
    event GuardianRemoved(address indexed guardian, address indexed removedBy);

    // ========================================================================
    // ERRORS
    // ========================================================================

    error InvalidVersion();
    error VersionNotFound();
    error NotInEmergencyMode();
    error AlreadyInEmergencyMode();
    error NotAdminOrGuardian();
    error NotAdmin();
    error ZeroAddress();
    error AlreadyAdmin();
    error AlreadyGuardian();
    error NotGuardian();

    // ========================================================================
    // MODIFIERS
    // ========================================================================

    /// @notice Only admin or guardian can call
    modifier onlyAdminOrGuardian() {
        if (!admins[msg.sender] && !guardians[msg.sender]) {
            revert NotAdminOrGuardian();
        }
        _;
    }

    /// @notice Only admin can call
    modifier onlyAdmin() {
        if (!admins[msg.sender]) {
            revert NotAdmin();
        }
        _;
    }

    // ========================================================================
    // OWNABLE OVERRIDE
    // ========================================================================

    /**
     * @notice Override Ownable._checkOwner to allow admin/guardian during emergency upgrade
     * @dev This allows emergencyUpgrade to call super.upgradeTo() which has onlyOwner modifier
     *      The _inEmergencyUpgrade flag ensures this bypass only works within emergencyUpgrade()
     */
    function _checkOwner() internal view override {
        // Owner always allowed
        if (owner() == _msgSender()) {
            return;
        }

        // Allow admin/guardian ONLY when in emergency upgrade context
        if (_inEmergencyUpgrade && (admins[_msgSender()] || guardians[_msgSender()])) {
            return;
        }

        revert OwnableUnauthorizedAccount(_msgSender());
    }

    // ========================================================================
    // CONSTRUCTOR
    // ========================================================================

    /**
     * @notice Constructor
     * @param initialImplementation Initial implementation address
     * @param initialOwner Owner address (should be Timelock)
     * @param initialAdmin Initial admin address for emergency operations
     */
    constructor(address initialImplementation, address initialOwner, address initialAdmin)
        UpgradeableBeacon(initialImplementation, initialOwner)
    {
        if (initialAdmin == address(0)) revert ZeroAddress();

        // Register V1
        currentVersion = 1;
        implementations[1] = initialImplementation;
        versionTimestamps[1] = block.timestamp;

        // Set initial admin
        admins[initialAdmin] = true;

        emit VersionRegistered(1, initialImplementation, bytes32(0), false, block.timestamp);
        emit AdminAdded(initialAdmin, address(0));
    }

    // ========================================================================
    // ADMIN/GUARDIAN MANAGEMENT (Owner only)
    // ========================================================================

    /**
     * @notice Add an admin
     * @param admin Address to add as admin
     */
    function addAdmin(address admin) external onlyOwner {
        if (admin == address(0)) revert ZeroAddress();
        if (admins[admin]) revert AlreadyAdmin();

        admins[admin] = true;
        emit AdminAdded(admin, msg.sender);
    }

    /**
     * @notice Remove an admin
     * @param admin Address to remove from admin
     */
    function removeAdmin(address admin) external onlyOwner {
        if (!admins[admin]) revert NotAdmin();

        admins[admin] = false;
        emit AdminRemoved(admin, msg.sender);
    }

    /**
     * @notice Add a guardian
     * @param guardian Address to add as guardian
     */
    function addGuardian(address guardian) external onlyOwner {
        if (guardian == address(0)) revert ZeroAddress();
        if (guardians[guardian]) revert AlreadyGuardian();

        guardians[guardian] = true;
        emit GuardianAdded(guardian, msg.sender);
    }

    /**
     * @notice Remove a guardian
     * @param guardian Address to remove from guardian
     */
    function removeGuardian(address guardian) external onlyOwner {
        if (!guardians[guardian]) revert NotGuardian();

        guardians[guardian] = false;
        emit GuardianRemoved(guardian, msg.sender);
    }

    // ========================================================================
    // NORMAL UPGRADE FUNCTIONS (Owner/Timelock only)
    // ========================================================================

    /**
     * @notice Upgrade to new implementation with version tracking
     * @param newImplementation New implementation address
     * @param infoHash IPFS hash or keccak256 of changelog (optional)
     */
    function upgradeToVersion(address newImplementation, bytes32 infoHash) public onlyOwner {
        _registerAndUpgrade(newImplementation, infoHash, false);
    }

    /**
     * @notice Override parent upgradeTo to use versioned upgrade
     * @dev Redirects to _registerAndUpgrade with empty info hash
     * @param newImplementation New implementation address
     */
    function upgradeTo(address newImplementation) public override onlyOwner {
        _registerAndUpgrade(newImplementation, bytes32(0), false);
    }

    // ========================================================================
    // EMERGENCY UPGRADE FUNCTIONS (Admin/Guardian only)
    // ========================================================================

    /**
     * @notice Activate emergency mode
     * @dev Allows emergency upgrades without timelock
     *      Should only be used for critical bug fixes
     */
    function activateEmergencyMode() external onlyAdminOrGuardian {
        if (emergencyMode) revert AlreadyInEmergencyMode();

        emergencyMode = true;
        emit EmergencyModeActivated(msg.sender, block.timestamp);
    }

    /**
     * @notice Deactivate emergency mode
     */
    function deactivateEmergencyMode() external onlyAdminOrGuardian {
        if (!emergencyMode) revert NotInEmergencyMode();

        emergencyMode = false;
        emit EmergencyModeDeactivated(msg.sender, block.timestamp);
    }

    /**
     * @notice Emergency upgrade - use when critical bug is found
     * @param newImplementation Hotfix implementation address
     * @param infoHash Description of the fix (IPFS hash or keccak256)
     * @dev Requirements:
     *      - emergencyMode must be active
     *      - Caller must be admin or guardian
     *      - Vault should be paused before calling this
     *
     * Instead of rolling back to an old version (which can break positions),
     * we upgrade to a new hotfix version that is forward-compatible.
     *
     * SECURITY: Uses _inEmergencyUpgrade flag to temporarily allow admin/guardian
     * to bypass onlyOwner check in super.upgradeTo(). Flag is reset after upgrade.
     */
    function emergencyUpgrade(address newImplementation, bytes32 infoHash)
        external
        nonReentrant
        onlyAdminOrGuardian
    {
        if (!emergencyMode) revert NotInEmergencyMode();

        // Set flag to allow admin/guardian to call super.upgradeTo()
        _inEmergencyUpgrade = true;

        _registerAndUpgrade(newImplementation, infoHash, true);

        // Reset flag immediately after upgrade
        _inEmergencyUpgrade = false;
    }

    // ========================================================================
    // INTERNAL FUNCTIONS
    // ========================================================================

    /**
     * @notice Internal function to register and perform upgrade
     * @param newImplementation New implementation address
     * @param infoHash IPFS hash or keccak256 of changelog
     * @param _isEmergency Whether this is an emergency upgrade
     */
    function _registerAndUpgrade(address newImplementation, bytes32 infoHash, bool _isEmergency)
        internal
    {
        // Increment version
        uint256 newVersion = currentVersion + 1;

        // Store version info
        implementations[newVersion] = newImplementation;
        versionTimestamps[newVersion] = block.timestamp;
        versionInfo[newVersion] = infoHash;
        isEmergencyUpgrade[newVersion] = _isEmergency;

        // Update current version
        currentVersion = newVersion;

        // Call parent upgradeTo (updates the actual beacon implementation)
        super.upgradeTo(newImplementation);

        emit VersionRegistered(
            newVersion, newImplementation, infoHash, _isEmergency, block.timestamp
        );
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /**
     * @notice Get implementation for specific version
     * @param version Version number
     * @return Implementation address
     */
    function getImplementation(uint256 version) external view returns (address) {
        return implementations[version];
    }

    /**
     * @notice Get current version info
     * @return version Current version number
     * @return impl Current implementation address
     * @return timestamp When current version was registered
     * @return info Changelog hash
     * @return _isEmergency Whether current version was emergency upgrade
     */
    function getCurrentVersionInfo()
        external
        view
        returns (uint256 version, address impl, uint256 timestamp, bytes32 info, bool _isEmergency)
    {
        return (
            currentVersion,
            implementations[currentVersion],
            versionTimestamps[currentVersion],
            versionInfo[currentVersion],
            isEmergencyUpgrade[currentVersion]
        );
    }

    /**
     * @notice Get version history
     * @param fromVersion Start version (inclusive)
     * @param toVersion End version (inclusive)
     * @return impls Array of implementation addresses
     * @return timestamps Array of registration timestamps
     * @return infos Array of changelog hashes
     * @return emergencyFlags Array of emergency upgrade flags
     */
    function getVersionHistory(uint256 fromVersion, uint256 toVersion)
        external
        view
        returns (
            address[] memory impls,
            uint256[] memory timestamps,
            bytes32[] memory infos,
            bool[] memory emergencyFlags
        )
    {
        if (fromVersion == 0 || fromVersion > toVersion || toVersion > currentVersion) {
            revert InvalidVersion();
        }

        uint256 count = toVersion - fromVersion + 1;
        impls = new address[](count);
        timestamps = new uint256[](count);
        infos = new bytes32[](count);
        emergencyFlags = new bool[](count);

        for (uint256 i = 0; i < count; i++) {
            uint256 v = fromVersion + i;
            impls[i] = implementations[v];
            timestamps[i] = versionTimestamps[v];
            infos[i] = versionInfo[v];
            emergencyFlags[i] = isEmergencyUpgrade[v];
        }
    }

    /**
     * @notice Check if a version exists
     * @param version Version to check
     * @return exists True if version has been registered
     */
    function versionExists(uint256 version) external view returns (bool) {
        return version > 0 && version <= currentVersion && implementations[version] != address(0);
    }

    /**
     * @notice Check if an address is admin
     * @param account Address to check
     * @return True if admin
     */
    function isAdmin(address account) external view returns (bool) {
        return admins[account];
    }

    /**
     * @notice Check if an address is guardian
     * @param account Address to check
     * @return True if guardian
     */
    function isGuardian(address account) external view returns (bool) {
        return guardians[account];
    }

    /**
     * @notice Check if an address can perform emergency operations
     * @param account Address to check
     * @return True if admin or guardian
     */
    function canEmergencyUpgrade(address account) external view returns (bool) {
        return admins[account] || guardians[account];
    }
}
