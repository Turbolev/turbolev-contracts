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
 * - VAULT_ADMIN_ROLE: VaultManager, VaultAdminProxy - can configure vaults
 * - POSITION_MANAGER_ROLE: PositionManager contract - can interact with positions
 * - VAULT_KEEPER_ROLE: Vault keeper bots - can update funding, finalize rewards
 * - POSITION_KEEPER_ROLE: Position keeper bots - can process settlements, liquidations
 * - GUARDIAN_ROLE: Emergency guardians - 2-of-N required to pause vaults
 * - EMERGENCY_ROLE: (DEPRECATED) Use GUARDIAN_ROLE instead
 *
 * Per-Vault Roles:
 * - Allows vault-specific admins (optional, for future use)
 *
 * Emergency Actions (2-of-N Guardian Pattern):
 * - Pause actions require 2 different guardians to initiate and confirm
 * - Confirmation window is configurable (30min - 24hr, default 1hr) (L-V4-01 FIX)
 * - Guardian count tracked with min/max limits (2-10) (L-V4-02 FIX)
 * - Unpause actions still require DEFAULT_ADMIN_ROLE (Timelock)
 */
contract VaultAccessController is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    // ========================================================================
    // ROLE DEFINITIONS
    // ========================================================================

    /// @notice Role for vault administration (VaultManager, VaultAdminProxy)
    bytes32 public constant VAULT_ADMIN_ROLE = keccak256("VAULT_ADMIN_ROLE");

    /// @notice Role for position management (PositionManager)
    bytes32 public constant POSITION_MANAGER_ROLE = keccak256("POSITION_MANAGER_ROLE");

    /// @notice Role for vault keeper operations (funding updates, reward finalization)
    bytes32 public constant VAULT_KEEPER_ROLE = keccak256("VAULT_KEEPER_ROLE");

    /// @notice Role for position keeper operations (process settlements, liquidations)
    bytes32 public constant POSITION_KEEPER_ROLE = keccak256("POSITION_KEEPER_ROLE");

    /// @notice Role for emergency operations (pause without timelock) - DEPRECATED, use GUARDIAN_ROLE
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    /// @notice Role for upgrading contracts
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /// @notice Role for guardians (2-of-N required for emergency actions)
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    // ========================================================================
    // GUARDIAN CONFIGURATION CONSTANTS (L-V4-01, L-V4-02 FIX)
    // ========================================================================

    /// @notice Minimum confirmation window for guardian actions (30 minutes)
    uint256 public constant MIN_CONFIRMATION_WINDOW = 30 minutes;

    /// @notice Maximum confirmation window for guardian actions (24 hours)
    uint256 public constant MAX_CONFIRMATION_WINDOW = 24 hours;

    /// @notice Default confirmation window (1 hour)
    uint256 public constant DEFAULT_CONFIRMATION_WINDOW = 1 hours;

    /// @notice Minimum number of guardians required (for 2-of-N pattern)
    uint256 public constant MIN_GUARDIANS = 2;

    /// @notice Maximum number of guardians allowed
    uint256 public constant MAX_GUARDIANS = 10;

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
    // 2-OF-N GUARDIAN STATE (for emergency actions)
    // ========================================================================

    /// @notice Hash of pending emergency action
    bytes32 public pendingEmergencyHash;

    /// @notice Address of guardian who initiated the pending action
    address public emergencyInitiator;

    /// @notice Timestamp when pending action was initiated
    uint256 public emergencyInitiatedAt;

    // ========================================================================
    // GUARDIAN CONFIGURATION STATE (L-V4-01, L-V4-02 FIX)
    // ========================================================================

    /// @notice Configurable confirmation window for 2-of-N guardian actions
    /// @dev L-V4-01 FIX: Made configurable instead of constant
    uint256 public emergencyConfirmationWindow;

    /// @notice Current number of guardians
    /// @dev L-V4-02 FIX: Track guardian count for min/max enforcement
    uint256 public guardianCount;

    // ========================================================================
    // STORAGE GAP
    // ========================================================================

    uint256[41] private __gap;

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

    // 2-of-N Guardian Events
    event EmergencyActionInitiated(
        bytes32 indexed actionHash, address indexed initiator, bytes4 selector, uint256 timestamp
    );
    event EmergencyActionConfirmed(
        bytes32 indexed actionHash, address indexed confirmer, uint256 timestamp
    );
    event EmergencyActionCancelled(bytes32 indexed actionHash, address indexed canceller);
    event GuardianAdded(
        address indexed guardian, address indexed addedBy, uint256 newGuardianCount
    );
    event GuardianRemoved(
        address indexed guardian, address indexed removedBy, uint256 newGuardianCount
    );
    event ConfirmationWindowUpdated(uint256 oldWindow, uint256 newWindow, uint256 timestamp);

    // ========================================================================
    // ERRORS
    // ========================================================================

    error InvalidAddress();
    error VaultNotRegistered();
    error VaultAlreadyRegistered();
    error NotAuthorized();
    error VaultManagerNotSet();

    // 2-of-N Guardian Errors
    error NoPendingEmergencyAction();
    error EmergencyActionExpired();
    error CannotSelfConfirm();
    error EmergencyActionAlreadyPending();
    error EmergencyActionMismatch();

    // Guardian Configuration Errors (L-V4-01, L-V4-02 FIX)
    error InvalidConfirmationWindow();
    error TooManyGuardians();
    error TooFewGuardians();
    error GuardianAlreadyExists();
    error NotAGuardian();

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

        // L-V4-01 FIX: Initialize configurable confirmation window
        emergencyConfirmationWindow = DEFAULT_CONFIRMATION_WINDOW;

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
     * @notice Add VaultAdminProxy as vault admin
     * @param adminProxy VaultAdminProxy address
     * @dev Convenience function for setup
     */
    function addVaultAdminProxy(address adminProxy) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (adminProxy == address(0)) revert InvalidAddress();
        _grantRole(VAULT_ADMIN_ROLE, adminProxy);
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
    // GUARDIAN MANAGEMENT (L-V4-02 FIX: Added count tracking with min/max)
    // ========================================================================

    /**
     * @notice Add a guardian for 2-of-N emergency actions
     * @param guardian Guardian address to add
     * @dev Only callable by DEFAULT_ADMIN_ROLE
     *      L-V4-02 FIX: Enforces MAX_GUARDIANS limit and tracks count
     */
    function addGuardian(address guardian) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (guardian == address(0)) revert InvalidAddress();

        // L-V4-02 FIX: Check if already a guardian
        if (hasRole(GUARDIAN_ROLE, guardian)) {
            revert GuardianAlreadyExists();
        }

        // L-V4-02 FIX: Check max limit
        if (guardianCount >= MAX_GUARDIANS) {
            revert TooManyGuardians();
        }

        _grantRole(GUARDIAN_ROLE, guardian);
        guardianCount++;

        emit GuardianAdded(guardian, msg.sender, guardianCount);
    }

    /**
     * @notice Remove a guardian
     * @param guardian Guardian address to remove
     * @dev Only callable by DEFAULT_ADMIN_ROLE
     *      L-V4-02 FIX: Enforces MIN_GUARDIANS limit and tracks count
     */
    function removeGuardian(address guardian) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // L-V4-02 FIX: Check if actually a guardian
        if (!hasRole(GUARDIAN_ROLE, guardian)) {
            revert NotAGuardian();
        }

        // L-V4-02 FIX: Check min limit (must keep at least MIN_GUARDIANS for 2-of-N)
        if (guardianCount <= MIN_GUARDIANS) {
            revert TooFewGuardians();
        }

        _revokeRole(GUARDIAN_ROLE, guardian);
        guardianCount--;

        emit GuardianRemoved(guardian, msg.sender, guardianCount);
    }

    /**
     * @notice Check if account is a guardian
     * @param account Account to check
     * @return isGuardianResult True if account is guardian
     */
    function isGuardian(address account) external view returns (bool isGuardianResult) {
        return hasRole(GUARDIAN_ROLE, account);
    }

    /**
     * @notice Get current guardian count
     * @return count Number of guardians
     * @dev L-V4-02 FIX: Added for transparency
     */
    function getGuardianCount() external view returns (uint256 count) {
        return guardianCount;
    }

    /**
     * @notice Get guardian configuration
     * @return minGuardians Minimum guardians required
     * @return maxGuardians Maximum guardians allowed
     * @return currentCount Current guardian count
     * @dev L-V4-02 FIX: Added for transparency
     */
    function getGuardianConfig()
        external
        view
        returns (uint256 minGuardians, uint256 maxGuardians, uint256 currentCount)
    {
        return (MIN_GUARDIANS, MAX_GUARDIANS, guardianCount);
    }

    // ========================================================================
    // CONFIRMATION WINDOW CONFIGURATION (L-V4-01 FIX)
    // ========================================================================

    /**
     * @notice Set confirmation window for 2-of-N guardian actions
     * @param newWindow New confirmation window in seconds
     * @dev Only callable by DEFAULT_ADMIN_ROLE
     *      L-V4-01 FIX: Made configurable with min/max bounds
     */
    function setConfirmationWindow(uint256 newWindow) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newWindow < MIN_CONFIRMATION_WINDOW || newWindow > MAX_CONFIRMATION_WINDOW) {
            revert InvalidConfirmationWindow();
        }

        uint256 oldWindow = emergencyConfirmationWindow;
        emergencyConfirmationWindow = newWindow;

        emit ConfirmationWindowUpdated(oldWindow, newWindow, block.timestamp);
    }

    /**
     * @notice Get confirmation window configuration
     * @return minWindow Minimum allowed window
     * @return maxWindow Maximum allowed window
     * @return currentWindow Current confirmation window
     * @dev L-V4-01 FIX: Added for transparency
     */
    function getConfirmationWindowConfig()
        external
        view
        returns (uint256 minWindow, uint256 maxWindow, uint256 currentWindow)
    {
        return (MIN_CONFIRMATION_WINDOW, MAX_CONFIRMATION_WINDOW, emergencyConfirmationWindow);
    }

    // ========================================================================
    // 2-OF-N EMERGENCY FUNCTIONS (Requires 2 guardians)
    // ========================================================================

    /**
     * @notice Initiate emergency pause for a vault (Step 1 of 2)
     * @param vault Vault address to pause
     * @dev Requires second guardian to confirm within EMERGENCY_CONFIRMATION_WINDOW
     */
    function initiatePauseVault(address vault) external onlyRole(GUARDIAN_ROLE) {
        if (vaultManager == address(0)) revert VaultManagerNotSet();
        _initiateEmergencyAction(this.confirmPauseVault.selector, abi.encode(vault));
    }

    /**
     * @notice Confirm emergency pause for a vault (Step 2 of 2)
     * @param vault Vault address to pause (must match initiated action)
     * @dev Must be called by different guardian than initiator
     */
    function confirmPauseVault(address vault) external onlyRole(GUARDIAN_ROLE) {
        if (vaultManager == address(0)) revert VaultManagerNotSet();
        _confirmEmergencyAction(this.confirmPauseVault.selector, abi.encode(vault));

        IVaultManager(vaultManager).emergencyPauseVaultByAddress(vault);
        emit EmergencyPause(vault, msg.sender);
    }

    /**
     * @notice Initiate emergency batch pause (Step 1 of 2)
     * @param vaults Array of vault addresses to pause
     * @dev Requires second guardian to confirm within EMERGENCY_CONFIRMATION_WINDOW
     */
    function initiateBatchPause(address[] calldata vaults) external onlyRole(GUARDIAN_ROLE) {
        if (vaultManager == address(0)) revert VaultManagerNotSet();
        _initiateEmergencyAction(this.confirmBatchPause.selector, abi.encode(vaults));
    }

    /**
     * @notice Confirm emergency batch pause (Step 2 of 2)
     * @param vaults Array of vault addresses (must match initiated action)
     * @dev Must be called by different guardian than initiator
     */
    function confirmBatchPause(address[] calldata vaults) external onlyRole(GUARDIAN_ROLE) {
        if (vaultManager == address(0)) revert VaultManagerNotSet();
        _confirmEmergencyAction(this.confirmBatchPause.selector, abi.encode(vaults));

        IVaultManager(vaultManager).emergencyBatchPauseVaults(vaults);
        for (uint256 i = 0; i < vaults.length; i++) {
            emit EmergencyPause(vaults[i], msg.sender);
        }
    }

    /**
     * @notice Cancel pending emergency action
     * @dev Can be called by any guardian
     */
    function cancelEmergencyAction() external onlyRole(GUARDIAN_ROLE) {
        bytes32 actionHash = pendingEmergencyHash;
        _clearPendingAction();
        emit EmergencyActionCancelled(actionHash, msg.sender);
    }

    /**
     * @notice Get pending emergency action details
     * @return actionHash Hash of pending action
     * @return initiator Address of initiator
     * @return initiatedAt Timestamp of initiation
     * @return expiresAt Timestamp when action expires
     */
    function getPendingEmergencyAction()
        external
        view
        returns (bytes32 actionHash, address initiator, uint256 initiatedAt, uint256 expiresAt)
    {
        // L-V4-01 FIX: Use configurable window instead of constant
        return (
            pendingEmergencyHash,
            emergencyInitiator,
            emergencyInitiatedAt,
            emergencyInitiatedAt + emergencyConfirmationWindow
        );
    }

    // ========================================================================
    // INTERNAL HELPERS FOR 2-OF-N PATTERN
    // ========================================================================

    function _initiateEmergencyAction(bytes4 selector, bytes memory data) internal {
        // L-V4-01 FIX: Use configurable window instead of constant
        // Check if there's already a pending non-expired action
        if (
            pendingEmergencyHash != bytes32(0)
                && block.timestamp < emergencyInitiatedAt + emergencyConfirmationWindow
        ) {
            revert EmergencyActionAlreadyPending();
        }

        bytes32 actionHash = keccak256(abi.encode(selector, data));
        pendingEmergencyHash = actionHash;
        emergencyInitiator = msg.sender;
        emergencyInitiatedAt = block.timestamp;

        emit EmergencyActionInitiated(actionHash, msg.sender, selector, block.timestamp);
    }

    function _confirmEmergencyAction(bytes4 selector, bytes memory data) internal {
        if (pendingEmergencyHash == bytes32(0)) revert NoPendingEmergencyAction();

        // L-V4-01 FIX: Use configurable window instead of constant
        if (block.timestamp > emergencyInitiatedAt + emergencyConfirmationWindow) {
            _clearPendingAction();
            revert EmergencyActionExpired();
        }

        if (msg.sender == emergencyInitiator) revert CannotSelfConfirm();

        bytes32 actionHash = keccak256(abi.encode(selector, data));
        if (actionHash != pendingEmergencyHash) revert EmergencyActionMismatch();

        emit EmergencyActionConfirmed(actionHash, msg.sender, block.timestamp);
        _clearPendingAction();
    }

    function _clearPendingAction() internal {
        pendingEmergencyHash = bytes32(0);
        emergencyInitiator = address(0);
        emergencyInitiatedAt = 0;
    }

    // ========================================================================
    // EMERGENCY UNPAUSE (Requires DEFAULT_ADMIN_ROLE / Timelock)
    // ========================================================================

    /**
     * @notice Emergency unpause vault by project token
     * @param projectToken Project token address
     * @dev Only callable by DEFAULT_ADMIN_ROLE (Timelock) to prevent abuse
     */
    function emergencyUnpauseVault(address projectToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (vaultManager == address(0)) revert VaultManagerNotSet();
        IVaultManager(vaultManager).emergencyUnpauseVault(projectToken);
        emit EmergencyUnpause(projectToken, msg.sender);
    }

    /**
     * @notice Emergency unpause vault by address
     * @param vault Vault address
     * @dev Only callable by DEFAULT_ADMIN_ROLE (Timelock) to prevent abuse
     */
    function emergencyUnpauseVaultByAddress(address vault) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (vaultManager == address(0)) revert VaultManagerNotSet();
        IVaultManager(vaultManager).emergencyUnpauseVaultByAddress(vault);
        emit EmergencyUnpause(vault, msg.sender);
    }

    /**
     * @notice Emergency batch unpause vaults
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
        return "2.2.0";
    }
}

