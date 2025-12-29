// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../interfaces/IVaultAccessController.sol";
import "./ModuleRegistry.sol";

/**
 * @title VaultRegistry
 * @notice Registry to track vault configurations and module versions
 * @dev READ-ONLY tracking - does NOT trigger actions on VaultRouter/VaultManager
 *
 * Design Principles:
 * - VaultManager is the source of truth for vault operations
 * - VaultRegistry only mirrors/tracks state
 * - deactivateVault() only updates local state, no side effects
 * - VaultManager calls VaultRegistry to sync state after operations
 *
 * Features:
 * - Track which module versions each vault is using
 * - Track vault configurations and update history
 * - Find vaults using specific module versions
 * - Find vaults using deprecated modules
 */
contract VaultRegistry is Initializable, UUPSUpgradeable {
    // ========================================================================
    // STRUCTS
    // ========================================================================

    struct VaultConfig {
        address vaultAddress;
        address projectToken;
        string routerVersion;
        string coreVersion;
        string fundingVersion;
        string rewardsVersion;
        uint256 deployedAt;
        uint256 lastUpdatedAt;
        bool isActive;
    }

    struct ModuleUpdate {
        bytes32 moduleType;
        string fromVersion;
        string toVersion;
        uint256 timestamp;
        address updatedBy;
    }

    // ========================================================================
    // STATE VARIABLES
    // ========================================================================

    /// @notice VaultAccessController for role checks
    IVaultAccessController public accessController;

    /// @notice ModuleRegistry reference
    ModuleRegistry public moduleRegistry;

    /// @notice Vault address => VaultConfig
    mapping(address => VaultConfig) public vaultConfigs;

    /// @notice All registered vault addresses
    address[] public allVaults;

    /// @notice Vault address => update history
    mapping(address => ModuleUpdate[]) private _updateHistory;

    /// @notice Project token => vault address
    mapping(address => address) public vaultByProjectToken;

    // ========================================================================
    // STORAGE GAP
    // ========================================================================

    uint256[40] private __gap;

    // ========================================================================
    // EVENTS
    // ========================================================================

    event VaultRegistered(
        address indexed vault,
        address indexed projectToken,
        string routerVersion,
        string coreVersion,
        string fundingVersion,
        string rewardsVersion,
        uint256 timestamp
    );

    event VaultModuleUpdated(
        address indexed vault,
        bytes32 indexed moduleType,
        string fromVersion,
        string toVersion,
        address indexed updatedBy,
        uint256 timestamp
    );

    event VaultDeactivated(address indexed vault, uint256 timestamp);
    event VaultReactivated(address indexed vault, uint256 timestamp);
    event AccessControllerUpdated(address indexed oldController, address indexed newController);
    event ModuleRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);

    // ========================================================================
    // ERRORS
    // ========================================================================

    error NotAuthorized();
    error VaultAlreadyRegistered();
    error VaultNotFound();
    error InvalidAddress();

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
     * @param _moduleRegistry ModuleRegistry address
     */
    function initialize(address _accessController, address _moduleRegistry) external initializer {
        if (_accessController == address(0)) revert InvalidAddress();
        if (_moduleRegistry == address(0)) revert InvalidAddress();

        __UUPSUpgradeable_init();

        accessController = IVaultAccessController(_accessController);
        moduleRegistry = ModuleRegistry(_moduleRegistry);
    }

    // ========================================================================
    // REGISTRATION FUNCTIONS
    // ========================================================================

    /**
     * @notice Register a new vault with its initial configuration
     * @param vault Vault address
     * @param projectToken Project token address
     * @param routerVersion Router version string
     * @param coreVersion Core module version string
     * @param fundingVersion Funding module version string
     * @param rewardsVersion Rewards module version string
     */
    function registerVault(
        address vault,
        address projectToken,
        string calldata routerVersion,
        string calldata coreVersion,
        string calldata fundingVersion,
        string calldata rewardsVersion
    ) external onlyVaultAdmin {
        if (vault == address(0) || projectToken == address(0)) {
            revert InvalidAddress();
        }
        if (vaultConfigs[vault].vaultAddress != address(0)) revert VaultAlreadyRegistered();

        vaultConfigs[vault] = VaultConfig({
            vaultAddress: vault,
            projectToken: projectToken,
            routerVersion: routerVersion,
            coreVersion: coreVersion,
            fundingVersion: fundingVersion,
            rewardsVersion: rewardsVersion,
            deployedAt: block.timestamp,
            lastUpdatedAt: block.timestamp,
            isActive: true
        });

        allVaults.push(vault);
        vaultByProjectToken[projectToken] = vault;

        emit VaultRegistered(
            vault,
            projectToken,
            routerVersion,
            coreVersion,
            fundingVersion,
            rewardsVersion,
            block.timestamp
        );
    }

    /**
     * @notice Update vault module version
     * @dev Call this after updating a module in the vault
     * @param vault Vault address
     * @param moduleType Module type (use ModuleRegistry constants)
     * @param newVersion New version string
     */
    function updateVaultModule(address vault, bytes32 moduleType, string calldata newVersion)
        external
        onlyVaultAdmin
    {
        if (vaultConfigs[vault].vaultAddress == address(0)) revert VaultNotFound();

        VaultConfig storage config = vaultConfigs[vault];
        string memory oldVersion;

        if (moduleType == moduleRegistry.MODULE_ROUTER()) {
            oldVersion = config.routerVersion;
            config.routerVersion = newVersion;
        } else if (moduleType == moduleRegistry.MODULE_CORE()) {
            oldVersion = config.coreVersion;
            config.coreVersion = newVersion;
        } else if (moduleType == moduleRegistry.MODULE_FUNDING()) {
            oldVersion = config.fundingVersion;
            config.fundingVersion = newVersion;
        } else if (moduleType == moduleRegistry.MODULE_REWARDS()) {
            oldVersion = config.rewardsVersion;
            config.rewardsVersion = newVersion;
        }

        config.lastUpdatedAt = block.timestamp;

        // Record update history
        _updateHistory[vault].push(
            ModuleUpdate({
                moduleType: moduleType,
                fromVersion: oldVersion,
                toVersion: newVersion,
                timestamp: block.timestamp,
                updatedBy: msg.sender
            })
        );

        emit VaultModuleUpdated(
            vault, moduleType, oldVersion, newVersion, msg.sender, block.timestamp
        );
    }

    /**
     * @notice Batch update vault modules
     * @param vault Vault address
     * @param routerVersion New router version (empty to skip)
     * @param coreVersion New core version (empty to skip)
     * @param fundingVersion New funding version (empty to skip)
     * @param rewardsVersion New rewards version (empty to skip)
     */
    function batchUpdateVaultModules(
        address vault,
        string calldata routerVersion,
        string calldata coreVersion,
        string calldata fundingVersion,
        string calldata rewardsVersion
    ) external onlyVaultAdmin {
        if (vaultConfigs[vault].vaultAddress == address(0)) {
            revert VaultNotFound();
        }

        VaultConfig storage config = vaultConfigs[vault];

        if (
            bytes(routerVersion).length > 0
                && keccak256(bytes(routerVersion)) != keccak256(bytes(config.routerVersion))
        ) {
            _recordUpdate(
                vault, moduleRegistry.MODULE_ROUTER(), config.routerVersion, routerVersion
            );
            config.routerVersion = routerVersion;
        }

        if (
            bytes(coreVersion).length > 0
                && keccak256(bytes(coreVersion)) != keccak256(bytes(config.coreVersion))
        ) {
            _recordUpdate(vault, moduleRegistry.MODULE_CORE(), config.coreVersion, coreVersion);
            config.coreVersion = coreVersion;
        }

        if (
            bytes(fundingVersion).length > 0
                && keccak256(bytes(fundingVersion)) != keccak256(bytes(config.fundingVersion))
        ) {
            _recordUpdate(
                vault, moduleRegistry.MODULE_FUNDING(), config.fundingVersion, fundingVersion
            );
            config.fundingVersion = fundingVersion;
        }

        if (
            bytes(rewardsVersion).length > 0
                && keccak256(bytes(rewardsVersion)) != keccak256(bytes(config.rewardsVersion))
        ) {
            _recordUpdate(
                vault, moduleRegistry.MODULE_REWARDS(), config.rewardsVersion, rewardsVersion
            );
            config.rewardsVersion = rewardsVersion;
        }

        config.lastUpdatedAt = block.timestamp;
    }

    function _recordUpdate(
        address vault,
        bytes32 moduleType,
        string memory oldVersion,
        string memory newVersion
    ) internal {
        _updateHistory[vault].push(
            ModuleUpdate({
                moduleType: moduleType,
                fromVersion: oldVersion,
                toVersion: newVersion,
                timestamp: block.timestamp,
                updatedBy: msg.sender
            })
        );

        emit VaultModuleUpdated(
            vault, moduleType, oldVersion, newVersion, msg.sender, block.timestamp
        );
    }

    /**
     * @notice Deactivate a vault (tracking only, no side effects)
     * @dev This only updates local state. VaultManager is source of truth.
     * @param vault Vault address
     */
    function deactivateVault(address vault) external onlyVaultAdmin {
        if (vaultConfigs[vault].vaultAddress == address(0)) revert VaultNotFound();
        vaultConfigs[vault].isActive = false;
        vaultConfigs[vault].lastUpdatedAt = block.timestamp;
        emit VaultDeactivated(vault, block.timestamp);
    }

    /**
     * @notice Reactivate a vault (tracking only, no side effects)
     * @dev This only updates local state. VaultManager is source of truth.
     * @param vault Vault address
     */
    function reactivateVault(address vault) external onlyVaultAdmin {
        if (vaultConfigs[vault].vaultAddress == address(0)) revert VaultNotFound();
        vaultConfigs[vault].isActive = true;
        vaultConfigs[vault].lastUpdatedAt = block.timestamp;
        emit VaultReactivated(vault, block.timestamp);
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

    /**
     * @notice Update module registry
     * @param _moduleRegistry New module registry address
     */
    function setModuleRegistry(address _moduleRegistry) external onlyAdmin {
        if (_moduleRegistry == address(0)) revert InvalidAddress();
        address oldRegistry = address(moduleRegistry);
        moduleRegistry = ModuleRegistry(_moduleRegistry);
        emit ModuleRegistryUpdated(oldRegistry, _moduleRegistry);
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /**
     * @notice Get vault configuration
     * @param vault Vault address
     * @return Vault configuration
     */
    function getVaultConfig(address vault) external view returns (VaultConfig memory) {
        return vaultConfigs[vault];
    }

    /**
     * @notice Get all vault addresses
     * @return Array of vault addresses
     */
    function getAllVaults() external view returns (address[] memory) {
        return allVaults;
    }

    /**
     * @notice Get vault count
     * @return Number of registered vaults
     */
    function getVaultCount() external view returns (uint256) {
        return allVaults.length;
    }

    /**
     * @notice Get active vaults only
     * @return Array of active vault addresses
     */
    function getActiveVaults() external view returns (address[] memory) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < allVaults.length; i++) {
            if (vaultConfigs[allVaults[i]].isActive) activeCount++;
        }

        address[] memory activeVaults = new address[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < allVaults.length; i++) {
            if (vaultConfigs[allVaults[i]].isActive) {
                activeVaults[index++] = allVaults[i];
            }
        }
        return activeVaults;
    }

    /**
     * @notice Get vaults using a specific module version
     * @param moduleType Module type
     * @param version Version string
     * @return Array of vault addresses
     */
    function getVaultsByModuleVersion(bytes32 moduleType, string calldata version)
        external
        view
        returns (address[] memory)
    {
        // Count matching vaults first
        uint256 count = 0;
        for (uint256 i = 0; i < allVaults.length; i++) {
            if (_matchesVersion(allVaults[i], moduleType, version)) count++;
        }

        // Collect matching vaults
        address[] memory matchingVaults = new address[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < allVaults.length; i++) {
            if (_matchesVersion(allVaults[i], moduleType, version)) {
                matchingVaults[index++] = allVaults[i];
            }
        }
        return matchingVaults;
    }

    function _matchesVersion(address vault, bytes32 moduleType, string calldata version)
        internal
        view
        returns (bool)
    {
        VaultConfig storage config = vaultConfigs[vault];
        bytes32 versionHash = keccak256(bytes(version));

        if (moduleType == moduleRegistry.MODULE_ROUTER()) {
            return keccak256(bytes(config.routerVersion)) == versionHash;
        } else if (moduleType == moduleRegistry.MODULE_CORE()) {
            return keccak256(bytes(config.coreVersion)) == versionHash;
        } else if (moduleType == moduleRegistry.MODULE_FUNDING()) {
            return keccak256(bytes(config.fundingVersion)) == versionHash;
        } else if (moduleType == moduleRegistry.MODULE_REWARDS()) {
            return keccak256(bytes(config.rewardsVersion)) == versionHash;
        }
        return false;
    }

    /**
     * @notice Get update history for a vault
     * @param vault Vault address
     * @return Array of module updates
     */
    function getUpdateHistory(address vault) external view returns (ModuleUpdate[] memory) {
        return _updateHistory[vault];
    }

    /**
     * @notice Get update count for a vault
     * @param vault Vault address
     * @return Number of updates
     */
    function getUpdateCount(address vault) external view returns (uint256) {
        return _updateHistory[vault].length;
    }

    /**
     * @notice Get vaults that need upgrade (using deprecated modules)
     * @return Array of vault addresses using deprecated modules
     */
    function getVaultsNeedingUpgrade() external view returns (address[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < allVaults.length; i++) {
            if (vaultConfigs[allVaults[i]].isActive && _usesDeprecatedModule(allVaults[i])) {
                count++;
            }
        }

        address[] memory vaultsNeedUpgrade = new address[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < allVaults.length; i++) {
            if (vaultConfigs[allVaults[i]].isActive && _usesDeprecatedModule(allVaults[i])) {
                vaultsNeedUpgrade[index++] = allVaults[i];
            }
        }
        return vaultsNeedUpgrade;
    }

    function _usesDeprecatedModule(address vault) internal view returns (bool) {
        VaultConfig storage config = vaultConfigs[vault];

        if (moduleRegistry.isDeprecated(moduleRegistry.MODULE_ROUTER(), config.routerVersion)) {
            return true;
        }
        if (moduleRegistry.isDeprecated(moduleRegistry.MODULE_CORE(), config.coreVersion)) {
            return true;
        }
        if (moduleRegistry.isDeprecated(moduleRegistry.MODULE_FUNDING(), config.fundingVersion)) {
            return true;
        }
        if (moduleRegistry.isDeprecated(moduleRegistry.MODULE_REWARDS(), config.rewardsVersion)) {
            return true;
        }

        return false;
    }

    /**
     * @notice Get full vault info including resolved implementations
     * @param vault Vault address
     * @return config Vault configuration
     * @return routerImpl Router implementation address
     * @return coreImpl Core implementation address
     * @return fundingImpl Funding implementation address
     * @return rewardsImpl Rewards implementation address
     */
    function getVaultFullInfo(address vault)
        external
        view
        returns (
            VaultConfig memory config,
            address routerImpl,
            address coreImpl,
            address fundingImpl,
            address rewardsImpl
        )
    {
        config = vaultConfigs[vault];
        routerImpl =
        moduleRegistry.getModule(moduleRegistry.MODULE_ROUTER(), config.routerVersion)
        .implementation;
        coreImpl =
        moduleRegistry.getModule(moduleRegistry.MODULE_CORE(), config.coreVersion).implementation;
        fundingImpl =
        moduleRegistry.getModule(moduleRegistry.MODULE_FUNDING(), config.fundingVersion)
        .implementation;
        rewardsImpl =
        moduleRegistry.getModule(moduleRegistry.MODULE_REWARDS(), config.rewardsVersion)
        .implementation;
    }

    /**
     * @notice Check if vault exists
     * @param vault Vault address
     * @return exists True if vault is registered
     */
    function vaultExists(address vault) external view returns (bool) {
        return vaultConfigs[vault].vaultAddress != address(0);
    }

    // ========================================================================
    // UPGRADE
    // ========================================================================

    function _authorizeUpgrade(address) internal override onlyAdmin { }
}

