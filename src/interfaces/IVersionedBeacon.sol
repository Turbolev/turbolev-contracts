// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IVersionedBeacon
 * @notice Interface for VersionedBeacon contract
 */
interface IVersionedBeacon {
    /// @notice Get current version number
    function currentVersion() external view returns (uint256);

    /// @notice Get implementation for a specific version
    function implementations(uint256 version) external view returns (address);

    /// @notice Get timestamp when a version was registered
    function versionTimestamps(uint256 version) external view returns (uint256);

    /// @notice Get info hash for a version
    function versionInfo(uint256 version) external view returns (bytes32);

    /// @notice Get current implementation (standard beacon interface)
    function implementation() external view returns (address);

    /// @notice Upgrade to new version with tracking
    /// @param newImplementation New implementation address
    /// @param infoHash IPFS hash or keccak256 of changelog
    function upgradeToVersion(address newImplementation, bytes32 infoHash) external;

    /// @notice Rollback to a previous version
    /// @param targetVersion Version to rollback to
    function rollbackTo(uint256 targetVersion) external;

    /// @notice Get implementation for specific version
    /// @param version Version number
    function getImplementation(uint256 version) external view returns (address);

    /// @notice Get current version info
    function getCurrentVersionInfo()
        external
        view
        returns (uint256 version, address impl, uint256 timestamp, bytes32 info);

    /// @notice Get version history
    /// @param fromVersion Start version (inclusive)
    /// @param toVersion End version (inclusive)
    function getVersionHistory(uint256 fromVersion, uint256 toVersion)
        external
        view
        returns (address[] memory impls, uint256[] memory timestamps, bytes32[] memory infos);
}
