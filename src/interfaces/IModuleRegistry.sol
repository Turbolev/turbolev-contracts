// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IModuleRegistry
 * @notice Interface for the ModuleRegistry contract
 */
interface IModuleRegistry {
    // ========================================================================
    // STRUCTS
    // ========================================================================

    struct ModuleVersion {
        address implementation;
        string version;
        uint256 registeredAt;
        bytes32 commitHash;
        bool deprecated;
    }

    // ========================================================================
    // CONSTANTS
    // ========================================================================

    function MODULE_ROUTER() external view returns (bytes32);
    function MODULE_CORE() external view returns (bytes32);
    function MODULE_FUNDING() external view returns (bytes32);
    function MODULE_REWARDS() external view returns (bytes32);

    // ========================================================================
    // REGISTRATION FUNCTIONS
    // ========================================================================

    function registerModule(
        bytes32 moduleType,
        string calldata version,
        address implementation,
        bytes32 commitHash,
        bool setAsLatest
    ) external;

    function batchRegisterModules(
        bytes32[] calldata moduleTypes,
        string[] calldata versions,
        address[] calldata implementations,
        bytes32[] calldata commitHashes,
        bool[] calldata setAsLatest
    ) external;

    function deprecateModule(bytes32 moduleType, string calldata version) external;

    function setLatestVersion(bytes32 moduleType, string calldata version) external;

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    function getModule(bytes32 moduleType, string calldata version)
        external
        view
        returns (ModuleVersion memory);

    function getLatestModule(bytes32 moduleType) external view returns (ModuleVersion memory);

    function getLatestImplementation(bytes32 moduleType) external view returns (address);

    function getAllVersions(bytes32 moduleType) external view returns (string[] memory);

    function getVersionCount(bytes32 moduleType) external view returns (uint256);

    function getModuleFromImplementation(address implementation)
        external
        view
        returns (bytes32 moduleType, string memory version);

    function versionExists(bytes32 moduleType, string calldata version) external view returns (bool);

    function isDeprecated(bytes32 moduleType, string calldata version) external view returns (bool);

    function getActiveVersions(bytes32 moduleType) external view returns (string[] memory);

    function latestVersions(bytes32 moduleType) external view returns (string memory);
}

