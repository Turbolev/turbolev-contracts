// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../interfaces/IVaultManager.sol";

/**
 * @title VaultAccessController
 * @notice Centralized access control for all vault modules
 * @dev Combines OpenZeppelin AccessControl with per-vault role management
 *
 * Global Roles:
 * - DEFAULT_ADMIN_ROLE: Governance (Timelock) - can manage all roles
 * - VAULT_ADMIN_ROLE: VaultManager, VaultManagerHelper - can configure vaults
 * - POSITION_MANAGER_ROLE: PositionManager contract - can interact with positions
 * - VAULT_KEEPER_ROLE: Vault keeper bots - can update funding, finalize rewards
 * - POSITION_KEEPER_ROLE: Position keeper bots - can process settlements, liquidations
 * - EMERGENCY_ROLE: Multisig - can pause without timelock delay
 *
 * Per-Vault Roles:
 * - Allows vault-specific admins (optional, for future use)
 */
contract VaultAccessController is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    // ========================================================================
    // ROLE DEFINITIONS
    // ========================================================================

    /// @notice Role for vault administration (VaultManager, VaultManagerHelper)
    bytes32 public constant VAULT_ADMIN_ROLE = keccak256("VAULT_ADMIN_ROLE");

    /// @notice Role for position management (PositionManager)
    bytes32 public constant POSITION_MANAGER_ROLE = keccak256("POSITION_MANAGER_ROLE");

    /// @notice Role for vault keeper operations (funding updates, reward finalization)
    bytes32 public constant VAULT_KEEPER_ROLE = keccak256("VAULT_KEEPER_ROLE");

    /// @notice Role for position keeper operations (process settlements, liquidations)
    bytes32 public constant POSITION_KEEPER_ROLE = keccak256("POSITION_KEEPER_ROLE");

    /// @notice Role for emergency operations (pause without timelock)
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    /// @notice Role for upgrading contracts
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // ========================================================================
    // STATE VARIABLES
    // ========================================================================

    /// @notice Per-vault role assignments
    /// @dev vaultRoles[vault][role][account] = hasRole
    mapping(address => mapping(bytes32 => mapping(address => bool))) public vaultRoles;

    /// @notice Mapping of vault addresses to track registered vaults
    mapping(address => bool) public registeredVaults;

    /// @notice Array of all registered vault addresses
    address[] public allVaults;

    /// @notice VaultManager contract address for emergency operations
    address public vaultManager;

    // ========================================================================
    // STORAGE GAP
    // ========================================================================

    uint256[46] private __gap;

    // ========================================================================
    // EVENTS
    // ========================================================================

    event VaultRegistered(address indexed vault, uint256 timestamp);
    event VaultUnregistered(address indexed vault, uint256 timestamp);
    event VaultRoleGranted(address indexed vault, bytes32 indexed role, address indexed account);
    event VaultRoleRevoked(address indexed vault, bytes32 indexed role, address indexed account);
    event VaultManagerUpdated(address indexed oldManager, address indexed newManager);
    event EmergencyPause(address indexed vault, address indexed caller);
    event EmergencyUnpause(address indexed vault, address indexed caller);

    // ========================================================================
    // ERRORS
    // ========================================================================

    error InvalidAddress();
    error VaultNotRegistered();
    error VaultAlreadyRegistered();
    error NotAuthorized();
    error VaultManagerNotSet();

    // ========================================================================
    // CONSTRUCTOR / INITIALIZER
    // ========================================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the access controller
     * @param admin Default admin address (typically Timelock)
     * @param _vaultManager VaultManager contract address
     * @param positionManager PositionManager contract address
     * @param multisig Multisig wallet for emergency operations
     */
    function initialize(
        address admin,
        address _vaultManager,
        address positionManager,
        address multisig
    ) external initializer {
        if (admin == address(0)) revert InvalidAddress();
        if (_vaultManager == address(0)) revert InvalidAddress();
        if (positionManager == address(0)) revert InvalidAddress();

        __AccessControl_init();
        __UUPSUpgradeable_init();

        // Store vaultManager reference
        vaultManager = _vaultManager;

        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(VAULT_ADMIN_ROLE, _vaultManager);
        _grantRole(POSITION_MANAGER_ROLE, positionManager);
        _grantRole(UPGRADER_ROLE, admin);

        if (multisig != address(0)) {
            _grantRole(EMERGENCY_ROLE, multisig);
        }
    }

    // ========================================================================
    // GLOBAL ROLE MANAGEMENT (inherited from AccessControl)
    // ========================================================================

    // grantRole, revokeRole, renounceRole inherited from AccessControlUpgradeable

    // ========================================================================
    // PER-VAULT ROLE MANAGEMENT
    // ========================================================================

    /**
     * @notice Register a vault with the access controller
     * @param vault Vault address to register
     * @dev Only callable by VAULT_ADMIN_ROLE
     */
    function registerVault(address vault) external onlyRole(VAULT_ADMIN_ROLE) {
        if (vault == address(0)) revert InvalidAddress();
        if (registeredVaults[vault]) revert VaultAlreadyRegistered();

        registeredVaults[vault] = true;
        allVaults.push(vault);

        emit VaultRegistered(vault, block.timestamp);
    }

    /**
     * @notice Unregister a vault from the access controller
     * @param vault Vault address to unregister
     * @dev Only callable by DEFAULT_ADMIN_ROLE
     */
    function unregisterVault(address vault) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!registeredVaults[vault]) revert VaultNotRegistered();

        registeredVaults[vault] = false;
        // Note: We don't remove from allVaults array to avoid O(n) operation
        // Use isVaultRegistered() to check if vault is active

        emit VaultUnregistered(vault, block.timestamp);
    }

    /**
     * @notice Grant a role for a specific vault
     * @param vault Vault address
     * @param role Role to grant
     * @param account Account to grant role to
     * @dev Only callable by DEFAULT_ADMIN_ROLE or VAULT_ADMIN_ROLE
     */
    function grantVaultRole(address vault, bytes32 role, address account) external {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender) && !hasRole(VAULT_ADMIN_ROLE, msg.sender)) {
            revert NotAuthorized();
        }
        if (vault == address(0) || account == address(0)) revert InvalidAddress();

        vaultRoles[vault][role][account] = true;
        emit VaultRoleGranted(vault, role, account);
    }

    /**
     * @notice Revoke a role for a specific vault
     * @param vault Vault address
     * @param role Role to revoke
     * @param account Account to revoke role from
     * @dev Only callable by DEFAULT_ADMIN_ROLE
     */
    function revokeVaultRole(address vault, bytes32 role, address account)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (vault == address(0) || account == address(0)) revert InvalidAddress();

        vaultRoles[vault][role][account] = false;
        emit VaultRoleRevoked(vault, role, account);
    }

    // ========================================================================
    // ACCESS CHECK FUNCTIONS
    // ========================================================================

    /**
     * @notice Check if account has role (global or vault-specific)
     * @param vault Vault address (can be address(0) for global check only)
     * @param role Role to check
     * @param account Account to check
     * @return hasRoleResult True if account has the role
     */
    function hasVaultRole(address vault, bytes32 role, address account)
        external
        view
        returns (bool hasRoleResult)
    {
        // Check global role first
        if (hasRole(role, account)) {
            return true;
        }

        // Check vault-specific role if vault is provided
        if (vault != address(0)) {
            return vaultRoles[vault][role][account];
        }

        return false;
    }

    /**
     * @notice Check if account is vault admin (global or vault-specific)
     * @param vault Vault address
     * @param account Account to check
     * @return isAdmin True if account is admin
     */
    function isVaultAdmin(address vault, address account) external view returns (bool isAdmin) {
        return hasRole(VAULT_ADMIN_ROLE, account) || vaultRoles[vault][VAULT_ADMIN_ROLE][account];
    }

    /**
     * @notice Check if account is position manager
     * @param account Account to check
     * @return isPositionMgr True if account is position manager
     */
    function isPositionManager(address account) external view returns (bool isPositionMgr) {
        return hasRole(POSITION_MANAGER_ROLE, account);
    }

    /**
     * @notice Check if account is vault keeper
     * @param account Account to check
     * @return isKeeperResult True if account is vault keeper
     */
    function isVaultKeeper(address account) external view returns (bool isKeeperResult) {
        return hasRole(VAULT_KEEPER_ROLE, account);
    }

    /**
     * @notice Check if account is position keeper
     * @param account Account to check
     * @return isKeeperResult True if account is position keeper
     */
    function isPositionKeeper(address account) external view returns (bool isKeeperResult) {
        return hasRole(POSITION_KEEPER_ROLE, account);
    }

    /**
     * @notice Check if account has emergency role
     * @param account Account to check
     * @return hasEmergency True if account has emergency role
     */
    function hasEmergencyRole(address account) external view returns (bool hasEmergency) {
        return hasRole(EMERGENCY_ROLE, account);
    }

    /**
     * @notice Check if vault is registered
     * @param vault Vault address
     * @return isRegistered True if vault is registered
     */
    function isVaultRegistered(address vault) external view returns (bool isRegistered) {
        return registeredVaults[vault];
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /**
     * @notice Get all registered vaults
     * @return vaults Array of vault addresses
     * @dev Note: May include unregistered vaults, check with isVaultRegistered()
     */
    function getAllVaults() external view returns (address[] memory vaults) {
        return allVaults;
    }

    /**
     * @notice Get count of registered vaults
     * @return count Number of vaults in array (may include unregistered)
     */
    function getVaultCount() external view returns (uint256 count) {
        return allVaults.length;
    }

    /**
     * @notice Get active (registered) vault count
     * @return count Number of active vaults
     */
    function getActiveVaultCount() external view returns (uint256 count) {
        for (uint256 i = 0; i < allVaults.length; i++) {
            if (registeredVaults[allVaults[i]]) {
                count++;
            }
        }
        return count;
    }

    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================

    /**
     * @notice Add VaultManagerHelper as vault admin
     * @param helper VaultManagerHelper address
     * @dev Convenience function for setup
     */
    function addVaultManagerHelper(address helper) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (helper == address(0)) revert InvalidAddress();
        _grantRole(VAULT_ADMIN_ROLE, helper);
    }

    /**
     * @notice Add vault keeper address
     * @param keeper Keeper address
     */
    function addVaultKeeper(address keeper) external onlyRole(VAULT_ADMIN_ROLE) {
        if (keeper == address(0)) revert InvalidAddress();
        _grantRole(VAULT_KEEPER_ROLE, keeper);
    }

    /**
     * @notice Remove vault keeper address
     * @param keeper Keeper address
     */
    function removeVaultKeeper(address keeper) external onlyRole(VAULT_ADMIN_ROLE) {
        _revokeRole(VAULT_KEEPER_ROLE, keeper);
    }

    /**
     * @notice Add position keeper address
     * @param keeper Keeper address
     */
    function addPositionKeeper(address keeper) external onlyRole(VAULT_ADMIN_ROLE) {
        if (keeper == address(0)) revert InvalidAddress();
        _grantRole(POSITION_KEEPER_ROLE, keeper);
    }

    /**
     * @notice Remove position keeper address
     * @param keeper Keeper address
     */
    function removePositionKeeper(address keeper) external onlyRole(VAULT_ADMIN_ROLE) {
        _revokeRole(POSITION_KEEPER_ROLE, keeper);
    }

    /**
     * @notice Update VaultManager address
     * @param _vaultManager New VaultManager address
     */
    function setVaultManager(address _vaultManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_vaultManager == address(0)) revert InvalidAddress();
        address oldManager = vaultManager;
        vaultManager = _vaultManager;
        emit VaultManagerUpdated(oldManager, _vaultManager);
    }

    // ========================================================================
    // EMERGENCY FUNCTIONS (NO TIMELOCK DELAY)
    // ========================================================================

    /**
     * @notice Emergency pause vault by project token (NO TIMELOCK DELAY)
     * @param projectToken Project token address
     * @dev Only callable by EMERGENCY_ROLE (typically Multisig)
     */
    function emergencyPauseVault(address projectToken) external onlyRole(EMERGENCY_ROLE) {
        if (vaultManager == address(0)) revert VaultManagerNotSet();
        IVaultManager(vaultManager).emergencyPauseVault(projectToken);
        emit EmergencyPause(projectToken, msg.sender);
    }

    /**
     * @notice Emergency pause vault by address (NO TIMELOCK DELAY)
     * @param vault Vault address
     * @dev Only callable by EMERGENCY_ROLE
     */
    function emergencyPauseVaultByAddress(address vault) external onlyRole(EMERGENCY_ROLE) {
        if (vaultManager == address(0)) revert VaultManagerNotSet();
        IVaultManager(vaultManager).emergencyPauseVaultByAddress(vault);
        emit EmergencyPause(vault, msg.sender);
    }

    /**
     * @notice Emergency batch pause vaults (NO TIMELOCK DELAY)
     * @param vaults Array of vault addresses
     * @dev Only callable by EMERGENCY_ROLE
     */
    function emergencyBatchPause(address[] calldata vaults) external onlyRole(EMERGENCY_ROLE) {
        if (vaultManager == address(0)) revert VaultManagerNotSet();
        IVaultManager(vaultManager).emergencyBatchPauseVaults(vaults);
        for (uint256 i = 0; i < vaults.length; i++) {
            emit EmergencyPause(vaults[i], msg.sender);
        }
    }

    /**
     * @notice Emergency unpause vault by project token (NO TIMELOCK DELAY)
     * @param projectToken Project token address
     * @dev Only callable by DEFAULT_ADMIN_ROLE (Timelock) to prevent abuse
     */
    function emergencyUnpauseVault(address projectToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (vaultManager == address(0)) revert VaultManagerNotSet();
        IVaultManager(vaultManager).emergencyUnpauseVault(projectToken);
        emit EmergencyUnpause(projectToken, msg.sender);
    }

    /**
     * @notice Emergency unpause vault by address (NO TIMELOCK DELAY)
     * @param vault Vault address
     * @dev Only callable by DEFAULT_ADMIN_ROLE (Timelock) to prevent abuse
     */
    function emergencyUnpauseVaultByAddress(address vault) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (vaultManager == address(0)) revert VaultManagerNotSet();
        IVaultManager(vaultManager).emergencyUnpauseVaultByAddress(vault);
        emit EmergencyUnpause(vault, msg.sender);
    }

    /**
     * @notice Emergency batch unpause vaults (NO TIMELOCK DELAY)
     * @param vaults Array of vault addresses
     * @dev Only callable by DEFAULT_ADMIN_ROLE (Timelock) to prevent abuse
     */
    function emergencyBatchUnpause(address[] calldata vaults)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (vaultManager == address(0)) revert VaultManagerNotSet();
        IVaultManager(vaultManager).emergencyBatchUnpauseVaults(vaults);
        for (uint256 i = 0; i < vaults.length; i++) {
            emit EmergencyUnpause(vaults[i], msg.sender);
        }
    }

    // ========================================================================
    // UUPS UPGRADE
    // ========================================================================

    /**
     * @notice Authorize upgrade (UUPS pattern)
     * @param newImplementation New implementation address
     */
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyRole(UPGRADER_ROLE)
    { }

    // ========================================================================
    // VERSION
    // ========================================================================

    /**
     * @notice Get contract version
     * @return version Version string
     */
    function version() external pure returns (string memory) {
        return "2.0.0";
    }
}

