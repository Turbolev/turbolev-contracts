// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./GovernanceManager.sol";
import "../interfaces/IVaultManager.sol";
import "../interfaces/IVaultBeacon.sol";

/**
 * @title VaultGovernor
 * @notice Vault-specific governor extending GovernanceManager (OpenZeppelin-based)
 * @dev Extends base governance với vault-specific functions + emergency guardians
 *
 * Key Features:
 * - Inherits generic governance logic từ GovernanceManager (OZ TimelockController + AccessControl)
 * - Adds vault-specific helpers (pause, unpause, upgrade)
 * - Emergency pause guardians (no timelock delay)
 * - Integration với VaultBeacon và OptInUpgradeManager
 *
 * Architecture:
 * GovernanceManager (base - OZ)
 *   └─> VaultGovernor (vault-specific)
 *       └─> Used by VaultManager
 */
contract VaultGovernor is GovernanceManager {
    // ========================================================================
    // ROLES (Additional vault-specific)
    // ========================================================================

    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    // ========================================================================
    // STATE VARIABLES
    // ========================================================================

    /// @notice VaultManager contract
    address public vaultManager;

    /// @notice VaultBeacon contract
    address public vaultBeacon;

    /// @notice OptInUpgradeManager contract
    address public optInUpgradeManager;

    /// @notice Emergency multisig (higher threshold)
    address public emergencyMultisig;

    // ========================================================================
    // EVENTS
    // ========================================================================

    event VaultManagerUpdated(
        address indexed oldManager,
        address indexed newManager
    );

    event VaultBeaconUpdated(
        address indexed oldBeacon,
        address indexed newBeacon
    );

    event OptInUpgradeManagerUpdated(
        address indexed oldManager,
        address indexed newManager
    );

    event EmergencyMultisigUpdated(
        address indexed oldMultisig,
        address indexed newMultisig
    );

    event GuardianAdded(address indexed guardian);

    event GuardianRemoved(address indexed guardian);

    event EmergencyPause(address indexed vault, address indexed guardian);

    // ========================================================================
    // ERRORS
    // ========================================================================

    error NotGuardian();
    error VaultManagerNotSet();
    error InvalidGuardian();

    // ========================================================================
    // MODIFIERS
    // ========================================================================

    modifier onlyGuardian() {
        if (!hasRole(GUARDIAN_ROLE, msg.sender)) revert NotGuardian();
        _;
    }

    // ========================================================================
    // CONSTRUCTOR
    // ========================================================================

    /**
     * @notice Constructor
     * @param _timelockController Timelock address
     * @param _multisigWallet Multisig address
     * @param _vaultManager VaultManager address
     * @param _vaultBeacon VaultBeacon address
     * @param _optInUpgradeManager OptInUpgradeManager address
     * @param _guardians Array of pause guardians
     * @param _admin Admin address
     */
    constructor(
        address _timelockController,
        address _multisigWallet,
        address _vaultManager,
        address _vaultBeacon,
        address _optInUpgradeManager,
        address[] memory _guardians,
        address _admin
    ) GovernanceManager(_timelockController, _admin, _multisigWallet) {
        if (
            _vaultManager == address(0) ||
            _vaultBeacon == address(0) ||
            _optInUpgradeManager == address(0)
        ) {
            revert InvalidAddress();
        }

        vaultManager = _vaultManager;
        vaultBeacon = _vaultBeacon;
        optInUpgradeManager = _optInUpgradeManager;

        // Set guardians via AccessControl
        for (uint256 i = 0; i < _guardians.length; i++) {
            if (_guardians[i] != address(0)) {
                _grantRole(GUARDIAN_ROLE, _guardians[i]);
            }
        }
    }

    // ========================================================================
    // VAULT-SPECIFIC HELPERS
    // ========================================================================

    /**
     * @notice Propose pause vault via governance
     * @param projectToken Project token address
     * @param salt Salt for operation uniqueness
     * @return operationHash Operation hash
     */
    function proposePauseVault(
        address projectToken,
        bytes32 salt
    ) external onlyProposer returns (bytes32) {
        if (vaultManager == address(0)) revert VaultManagerNotSet();

        bytes memory data = abi.encodeWithSignature(
            "pauseVault(address)",
            projectToken
        );

        return scheduleOperation(vaultManager, 0, data, bytes32(0), salt, 0);
    }

    /**
     * @notice Propose unpause vault via governance
     * @param projectToken Project token address
     * @param salt Salt for operation uniqueness
     * @return operationHash Operation hash
     */
    function proposeUnpauseVault(
        address projectToken,
        bytes32 salt
    ) external onlyProposer returns (bytes32) {
        if (vaultManager == address(0)) revert VaultManagerNotSet();

        bytes memory data = abi.encodeWithSignature(
            "unpauseVault(address)",
            projectToken
        );

        return scheduleOperation(vaultManager, 0, data, bytes32(0), salt, 0);
    }

    /**
     * @notice Propose pause vault by address via governance
     * @param vault Vault address
     * @param salt Salt for operation uniqueness
     * @return operationHash Operation hash
     */
    function proposePauseVaultByAddress(
        address vault,
        bytes32 salt
    ) external onlyProposer returns (bytes32) {
        if (vaultManager == address(0)) revert VaultManagerNotSet();

        bytes memory data = abi.encodeWithSignature(
            "pauseVaultByAddress(address)",
            vault
        );

        return scheduleOperation(vaultManager, 0, data, bytes32(0), salt, 0);
    }

    /**
     * @notice Propose batch pause vaults
     * @param vaults Array of vault addresses
     * @param salt Salt
     * @return operationHash Operation hash
     */
    function proposeBatchPauseVaults(
        address[] calldata vaults,
        bytes32 salt
    ) external onlyProposer returns (bytes32) {
        if (vaultManager == address(0)) revert VaultManagerNotSet();

        bytes memory data = abi.encodeWithSignature(
            "batchPauseVaults(address[])",
            vaults
        );

        return scheduleOperation(vaultManager, 0, data, bytes32(0), salt, 0);
    }

    /**
     * @notice Propose beacon upgrade
     * @param newImplementation New implementation address
     * @param salt Salt
     * @return operationHash Operation hash
     */
    function proposeBeaconUpgrade(
        address newImplementation,
        bytes32 salt
    ) external onlyProposer returns (bytes32) {
        if (vaultBeacon == address(0)) revert InvalidAddress();

        bytes memory data = abi.encodeWithSignature(
            "upgradeTo(address)",
            newImplementation
        );

        return scheduleOperation(vaultBeacon, 0, data, bytes32(0), salt, 0);
    }

    /**
     * @notice Propose opt-in upgrade
     * @param vault Vault address
     * @param newImplementation New implementation
     * @param gracePeriod Grace period
     * @param salt Salt
     * @return operationHash Operation hash
     */
    function proposeOptInUpgrade(
        address vault,
        address newImplementation,
        uint256 gracePeriod,
        bytes32 salt
    ) external onlyProposer returns (bytes32) {
        if (optInUpgradeManager == address(0)) revert InvalidAddress();

        bytes memory data = abi.encodeWithSignature(
            "proposeUpgrade(address,address,uint256)",
            vault,
            newImplementation,
            gracePeriod
        );

        return
            scheduleOperation(
                optInUpgradeManager,
                0,
                data,
                bytes32(0),
                salt,
                0
            );
    }

    // ========================================================================
    // EMERGENCY FUNCTIONS (NO TIMELOCK)
    // ========================================================================

    /**
     * @notice Emergency pause vault (guardians only, NO DELAY)
     * @param projectToken Project token address
     * @dev Bypasses timelock for critical situations
     */
    function emergencyPauseVault(address projectToken) external onlyGuardian {
        if (vaultManager == address(0)) revert VaultManagerNotSet();

        IVaultManager(vaultManager).pauseVault(projectToken);

        emit EmergencyPause(projectToken, msg.sender);
    }

    /**
     * @notice Emergency pause vault by address (guardians only, NO DELAY)
     * @param vault Vault address
     * @dev Bypasses timelock for critical situations
     */
    function emergencyPauseVaultByAddress(address vault) external onlyGuardian {
        if (vaultManager == address(0)) revert VaultManagerNotSet();

        IVaultManager(vaultManager).pauseVaultByAddress(vault);

        emit EmergencyPause(vault, msg.sender);
    }

    /**
     * @notice Emergency batch pause (guardians only)
     * @param vaults Array of vault addresses
     */
    function emergencyBatchPause(
        address[] calldata vaults
    ) external onlyGuardian {
        if (vaultManager == address(0)) revert VaultManagerNotSet();

        IVaultManager(vaultManager).batchPauseVaults(vaults);

        for (uint256 i = 0; i < vaults.length; i++) {
            emit EmergencyPause(vaults[i], msg.sender);
        }
    }

    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================

    /**
     * @notice Update VaultManager address
     * @param _vaultManager New vault manager
     */
    function updateVaultManager(
        address _vaultManager
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_vaultManager == address(0)) revert InvalidAddress();

        address oldManager = vaultManager;
        vaultManager = _vaultManager;

        emit VaultManagerUpdated(oldManager, _vaultManager);
    }

    /**
     * @notice Update VaultBeacon address
     * @param _vaultBeacon New beacon
     */
    function updateVaultBeacon(
        address _vaultBeacon
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_vaultBeacon == address(0)) revert InvalidAddress();

        address oldBeacon = vaultBeacon;
        vaultBeacon = _vaultBeacon;

        emit VaultBeaconUpdated(oldBeacon, _vaultBeacon);
    }

    /**
     * @notice Update OptInUpgradeManager address
     * @param _optInUpgradeManager New manager
     */
    function updateOptInUpgradeManager(
        address _optInUpgradeManager
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_optInUpgradeManager == address(0)) revert InvalidAddress();

        address oldManager = optInUpgradeManager;
        optInUpgradeManager = _optInUpgradeManager;

        emit OptInUpgradeManagerUpdated(oldManager, _optInUpgradeManager);
    }

    /**
     * @notice Update emergency multisig
     * @param _emergencyMultisig New emergency multisig
     */
    function updateEmergencyMultisig(
        address _emergencyMultisig
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address oldMultisig = emergencyMultisig;
        emergencyMultisig = _emergencyMultisig;

        emit EmergencyMultisigUpdated(oldMultisig, _emergencyMultisig);
    }

    /**
     * @notice Add pause guardian
     * @param guardian Guardian address
     */
    function addGuardian(
        address guardian
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (guardian == address(0)) revert InvalidGuardian();

        grantRole(GUARDIAN_ROLE, guardian);

        emit GuardianAdded(guardian);
    }

    /**
     * @notice Remove pause guardian
     * @param guardian Guardian address
     */
    function removeGuardian(
        address guardian
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (guardian == address(0)) revert InvalidGuardian();

        revokeRole(GUARDIAN_ROLE, guardian);

        emit GuardianRemoved(guardian);
    }

    /**
     * @notice Batch add guardians
     * @param guardians Array of guardian addresses
     */
    function batchAddGuardians(
        address[] calldata guardians
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < guardians.length; i++) {
            if (guardians[i] != address(0)) {
                grantRole(GUARDIAN_ROLE, guardians[i]);
                emit GuardianAdded(guardians[i]);
            }
        }
    }

    /**
     * @notice Check if address is guardian
     * @param account Address to check
     */
    function isGuardian(address account) external view returns (bool) {
        return hasRole(GUARDIAN_ROLE, account);
    }
}
