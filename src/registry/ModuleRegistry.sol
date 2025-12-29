// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../interfaces/IVaultAccessController.sol";

/**
 * @title ModuleRegistry
 * @notice Registry for all module versions in the Boolean Protocol
 * @dev Tracks module implementations and their versions using SemVer strings
 *
 * Module Types:
 * - ROUTER: VaultRouter implementations
 * - CORE: VaultCore module implementations
 * - FUNDING: VaultFunding module implementations
 * - REWARDS: VaultRewards module implementations
 *
 * Features:
 * - Register new module versions with commit hash for traceability
 * - Deprecate old versions
 * - Track latest version per module type
 * - Query version history
 */
contract ModuleRegistry is Initializable, UUPSUpgradeable {
    // ========================================================================
    // CONSTANTS
    // ========================================================================

    /// @notice Module type for VaultRouter
    bytes32 public constant MODULE_ROUTER = keccak256("ROUTER");

    /// @notice Module type for VaultCore
    bytes32 public constant MODULE_CORE = keccak256("CORE");

    /// @notice Module type for VaultFunding
    bytes32 public constant MODULE_FUNDING = keccak256("FUNDING");

    /// @notice Module type for VaultRewards
    bytes32 public constant MODULE_REWARDS = keccak256("REWARDS");

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
    // STATE VARIABLES
    // ========================================================================

    /// @notice VaultAccessController for role checks
    IVaultAccessController public accessController;

    /// @notice Module type => version string => ModuleVersion
    mapping(bytes32 => mapping(string => ModuleVersion)) public modules;

    /// @notice Module type => latest version string
    mapping(bytes32 => string) public latestVersions;

    /// @notice Module type => all version strings (for enumeration)
    mapping(bytes32 => string[]) private _versionHistory;

    /// @notice Implementation address => module type
    mapping(address => bytes32) public implementationToType;

    /// @notice Implementation address => version string
    mapping(address => string) public implementationToVersion;

    // ========================================================================
    // STORAGE GAP
    // ========================================================================

    uint256[40] private __gap;

    // ========================================================================
    // EVENTS
    // ========================================================================

    event ModuleRegistered(
        bytes32 indexed moduleType,
        string version,
        address indexed implementation,
        bytes32 commitHash,
        uint256 timestamp
    );

    event ModuleDeprecated(bytes32 indexed moduleType, string version, uint256 timestamp);

    event LatestVersionUpdated(bytes32 indexed moduleType, string oldVersion, string newVersion);

    event AccessControllerUpdated(address indexed oldController, address indexed newController);

    // ========================================================================
    // ERRORS
    // ========================================================================

    error NotAuthorized();
    error VersionAlreadyExists();
    error VersionNotFound();
    error InvalidAddress();
    error InvalidVersion();

    // ========================================================================
    // MODIFIERS
    // ========================================================================

    modifier onlyVaultAdmin() {
        if (!accessController.hasRole(accessController.VAULT_ADMIN_ROLE(), msg.sender)) {
            revert NotAuthorized();
        }
        _;
    }

    modifier onlyAdmin() {
        if (!accessController.hasRole(accessController.DEFAULT_ADMIN_ROLE(), msg.sender)) {
            revert NotAuthorized();
        }
        _;
    }

    // ========================================================================
    // CONSTRUCTOR / INITIALIZER
    // ========================================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the registry
     * @param _accessController VaultAccessController address
     */
    function initialize(address _accessController) external initializer {
        if (_accessController == address(0)) revert InvalidAddress();

        __UUPSUpgradeable_init();

        accessController = IVaultAccessController(_accessController);
    }

    // ========================================================================
    // REGISTRATION FUNCTIONS
    // ========================================================================

    /**
     * @notice Register a new module version
     * @param moduleType Module type (ROUTER, CORE, FUNDING, REWARDS)
     * @param version Version string (e.g., "3.0.0")
     * @param implementation Implementation address
     * @param commitHash Git commit hash for traceability
     * @param setAsLatest Whether to set this as the latest version
     */
    function registerModule(
        bytes32 moduleType,
        string calldata version,
        address implementation,
        bytes32 commitHash,
        bool setAsLatest
    ) external onlyVaultAdmin {
        if (implementation == address(0)) revert InvalidAddress();
        if (bytes(version).length == 0) revert InvalidVersion();
        if (modules[moduleType][version].implementation != address(0)) {
            revert VersionAlreadyExists();
        }

        modules[moduleType][version] = ModuleVersion({
            implementation: implementation,
            version: version,
            registeredAt: block.timestamp,
            commitHash: commitHash,
            deprecated: false
        });

        _versionHistory[moduleType].push(version);
        implementationToType[implementation] = moduleType;
        implementationToVersion[implementation] = version;

        if (setAsLatest) {
            string memory oldLatest = latestVersions[moduleType];
            latestVersions[moduleType] = version;
            emit LatestVersionUpdated(moduleType, oldLatest, version);
        }

        emit ModuleRegistered(moduleType, version, implementation, commitHash, block.timestamp);
    }

    /**
     * @notice Batch register multiple module versions
     * @param moduleTypes Array of module types
     * @param versions Array of version strings
     * @param implementations Array of implementation addresses
     * @param commitHashes Array of commit hashes
     * @param setAsLatest Array of whether to set as latest
     */
    function batchRegisterModules(
        bytes32[] calldata moduleTypes,
        string[] calldata versions,
        address[] calldata implementations,
        bytes32[] calldata commitHashes,
        bool[] calldata setAsLatest
    ) external onlyVaultAdmin {
        uint256 length = moduleTypes.length;
        require(
            versions.length == length && implementations.length == length
                && commitHashes.length == length && setAsLatest.length == length,
            "Length mismatch"
        );

        for (uint256 i = 0; i < length; i++) {
            _registerModule(
                moduleTypes[i], versions[i], implementations[i], commitHashes[i], setAsLatest[i]
            );
        }
    }

    function _registerModule(
        bytes32 moduleType,
        string calldata version,
        address implementation,
        bytes32 commitHash,
        bool setAsLatest
    ) internal {
        if (implementation == address(0)) revert InvalidAddress();
        if (bytes(version).length == 0) revert InvalidVersion();
        if (modules[moduleType][version].implementation != address(0)) {
            revert VersionAlreadyExists();
        }

        modules[moduleType][version] = ModuleVersion({
            implementation: implementation,
            version: version,
            registeredAt: block.timestamp,
            commitHash: commitHash,
            deprecated: false
        });

        _versionHistory[moduleType].push(version);
        implementationToType[implementation] = moduleType;
        implementationToVersion[implementation] = version;

        if (setAsLatest) {
            string memory oldLatest = latestVersions[moduleType];
            latestVersions[moduleType] = version;
            emit LatestVersionUpdated(moduleType, oldLatest, version);
        }

        emit ModuleRegistered(moduleType, version, implementation, commitHash, block.timestamp);
    }

    /**
     * @notice Deprecate a module version
     * @dev Deprecated modules should not be used for new deployments
     * @param moduleType Module type
     * @param version Version to deprecate
     */
    function deprecateModule(bytes32 moduleType, string calldata version) external onlyVaultAdmin {
        if (modules[moduleType][version].implementation == address(0)) {
            revert VersionNotFound();
        }

        modules[moduleType][version].deprecated = true;
        emit ModuleDeprecated(moduleType, version, block.timestamp);
    }

    /**
     * @notice Update latest version pointer
     * @param moduleType Module type
     * @param version Version to set as latest
     */
    function setLatestVersion(bytes32 moduleType, string calldata version) external onlyVaultAdmin {
        if (modules[moduleType][version].implementation == address(0)) {
            revert VersionNotFound();
        }

        string memory oldLatest = latestVersions[moduleType];
        latestVersions[moduleType] = version;
        emit LatestVersionUpdated(moduleType, oldLatest, version);
    }

    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================

    /**
     * @notice Update access controller
     * @param _accessController New access controller address
     */
    function setAccessController(address _accessController) external onlyAdmin {
        if (_accessController == address(0)) revert InvalidAddress();
        address oldController = address(accessController);
        accessController = IVaultAccessController(_accessController);
        emit AccessControllerUpdated(oldController, _accessController);
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /**
     * @notice Get module by type and version
     * @param moduleType Module type
     * @param version Version string
     * @return Module version info
     */
    function getModule(bytes32 moduleType, string calldata version)
        external
        view
        returns (ModuleVersion memory)
    {
        return modules[moduleType][version];
    }

    /**
     * @notice Get latest module implementation
     * @param moduleType Module type
     * @return Latest module version info
     */
    function getLatestModule(bytes32 moduleType) external view returns (ModuleVersion memory) {
        string memory version = latestVersions[moduleType];
        return modules[moduleType][version];
    }

    /**
     * @notice Get latest module implementation address
     * @param moduleType Module type
     * @return Implementation address
     */
    function getLatestImplementation(bytes32 moduleType) external view returns (address) {
        string memory version = latestVersions[moduleType];
        return modules[moduleType][version].implementation;
    }

    /**
     * @notice Get all versions for a module type
     * @param moduleType Module type
     * @return Array of version strings
     */
    function getAllVersions(bytes32 moduleType) external view returns (string[] memory) {
        return _versionHistory[moduleType];
    }

    /**
     * @notice Get version count for a module type
     * @param moduleType Module type
     * @return Number of registered versions
     */
    function getVersionCount(bytes32 moduleType) external view returns (uint256) {
        return _versionHistory[moduleType].length;
    }

    /**
     * @notice Get module info from implementation address
     * @param implementation Implementation address
     * @return moduleType Module type
     * @return version Version string
     */
    function getModuleFromImplementation(address implementation)
        external
        view
        returns (bytes32 moduleType, string memory version)
    {
        moduleType = implementationToType[implementation];
        version = implementationToVersion[implementation];
    }

    /**
     * @notice Check if a specific version exists
     * @param moduleType Module type
     * @param version Version to check
     * @return exists True if version exists
     */
    function versionExists(bytes32 moduleType, string calldata version)
        external
        view
        returns (bool)
    {
        return modules[moduleType][version].implementation != address(0);
    }

    /**
     * @notice Check if a version is deprecated
     * @param moduleType Module type
     * @param version Version to check
     * @return deprecated True if deprecated
     */
    function isDeprecated(bytes32 moduleType, string calldata version)
        external
        view
        returns (bool)
    {
        return modules[moduleType][version].deprecated;
    }

    /**
     * @notice Get non-deprecated versions for a module type
     * @param moduleType Module type
     * @return Array of active version strings
     */
    function getActiveVersions(bytes32 moduleType) external view returns (string[] memory) {
        string[] memory allVersions = _versionHistory[moduleType];
        uint256 activeCount = 0;

        // Count active versions
        for (uint256 i = 0; i < allVersions.length; i++) {
            if (!modules[moduleType][allVersions[i]].deprecated) {
                activeCount++;
            }
        }

        // Collect active versions
        string[] memory activeVersions = new string[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < allVersions.length; i++) {
            if (!modules[moduleType][allVersions[i]].deprecated) {
                activeVersions[index] = allVersions[i];
                index++;
            }
        }

        return activeVersions;
    }

    // ========================================================================
    // UPGRADE
    // ========================================================================

    function _authorizeUpgrade(address) internal override onlyAdmin { }
}

