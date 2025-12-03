// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

/**
 * @title VersionedBeacon
 * @notice UpgradeableBeacon with version tracking for rollback support
 * @dev Extends OpenZeppelin UpgradeableBeacon, adds version history
 *
 * Features:
 * - Version tracking for all upgrades
 * - Rollback to any previous version
 * - Changelog hash storage (IPFS or keccak256)
 * - Timestamp tracking for audit trail
 *
 * Owner should be Timelock for governance control.
 */
contract VersionedBeacon is UpgradeableBeacon {
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

    // ========================================================================
    // EVENTS
    // ========================================================================

    event VersionRegistered(
        uint256 indexed version, address indexed implementation, bytes32 infoHash, uint256 timestamp
    );

    event RolledBack(
        uint256 indexed fromVersion,
        uint256 indexed toVersion,
        address indexed implementation,
        uint256 timestamp
    );

    // ========================================================================
    // ERRORS
    // ========================================================================

    error InvalidVersion();
    error VersionNotFound();

    // ========================================================================
    // CONSTRUCTOR
    // ========================================================================

    /**
     * @notice Constructor
     * @param initialImplementation Initial implementation address
     * @param initialOwner Owner address (should be Timelock)
     */
    constructor(address initialImplementation, address initialOwner)
        UpgradeableBeacon(initialImplementation, initialOwner)
    {
        // Register V1
        currentVersion = 1;
        implementations[1] = initialImplementation;
        versionTimestamps[1] = block.timestamp;

        emit VersionRegistered(1, initialImplementation, bytes32(0), block.timestamp);
    }

    // ========================================================================
    // UPGRADE FUNCTIONS
    // ========================================================================

    /**
     * @notice Upgrade to new implementation with version tracking
     * @param newImplementation New implementation address
     * @param infoHash IPFS hash or keccak256 of changelog (optional)
     */
    function upgradeToVersion(address newImplementation, bytes32 infoHash) public onlyOwner {
        _upgradeToVersionInternal(newImplementation, infoHash);
    }

    /**
     * @notice Internal function to perform versioned upgrade
     * @param newImplementation New implementation address
     * @param infoHash IPFS hash or keccak256 of changelog
     */
    function _upgradeToVersionInternal(address newImplementation, bytes32 infoHash) internal {
        // Increment version
        uint256 newVersion = currentVersion + 1;

        // Store version info
        implementations[newVersion] = newImplementation;
        versionTimestamps[newVersion] = block.timestamp;
        versionInfo[newVersion] = infoHash;

        // Update current version
        currentVersion = newVersion;

        // Call parent upgradeTo (updates the actual beacon implementation)
        super.upgradeTo(newImplementation);

        emit VersionRegistered(newVersion, newImplementation, infoHash, block.timestamp);
    }

    /**
     * @notice Rollback to a previous version
     * @param targetVersion Version to rollback to
     * @dev Does not create new version entry, just points beacon to old impl
     */
    function rollbackTo(uint256 targetVersion) external onlyOwner {
        if (targetVersion == 0 || targetVersion > currentVersion) {
            revert InvalidVersion();
        }

        address targetImpl = implementations[targetVersion];
        if (targetImpl == address(0)) {
            revert VersionNotFound();
        }

        uint256 fromVersion = currentVersion;

        // Update beacon to point to old implementation
        super.upgradeTo(targetImpl);

        emit RolledBack(fromVersion, targetVersion, targetImpl, block.timestamp);
    }

    /**
     * @notice Override parent upgradeTo to use versioned upgrade
     * @dev Redirects to _upgradeToVersionInternal with empty info hash
     * @param newImplementation New implementation address
     */
    function upgradeTo(address newImplementation) public override onlyOwner {
        _upgradeToVersionInternal(newImplementation, bytes32(0));
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
     */
    function getCurrentVersionInfo()
        external
        view
        returns (uint256 version, address impl, uint256 timestamp, bytes32 info)
    {
        return (
            currentVersion,
            implementations[currentVersion],
            versionTimestamps[currentVersion],
            versionInfo[currentVersion]
        );
    }

    /**
     * @notice Get version history
     * @param fromVersion Start version (inclusive)
     * @param toVersion End version (inclusive)
     * @return impls Array of implementation addresses
     * @return timestamps Array of registration timestamps
     * @return infos Array of changelog hashes
     */
    function getVersionHistory(uint256 fromVersion, uint256 toVersion)
        external
        view
        returns (address[] memory impls, uint256[] memory timestamps, bytes32[] memory infos)
    {
        if (fromVersion == 0 || fromVersion > toVersion || toVersion > currentVersion) {
            revert InvalidVersion();
        }

        uint256 count = toVersion - fromVersion + 1;
        impls = new address[](count);
        timestamps = new uint256[](count);
        infos = new bytes32[](count);

        for (uint256 i = 0; i < count; i++) {
            uint256 v = fromVersion + i;
            impls[i] = implementations[v];
            timestamps[i] = versionTimestamps[v];
            infos[i] = versionInfo[v];
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
}
