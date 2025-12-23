// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IVaultAccessController
 * @notice Interface for the centralized access control contract
 */
interface IVaultAccessController {
    // ========================================================================
    // ROLE CONSTANTS
    // ========================================================================

    function VAULT_ADMIN_ROLE() external view returns (bytes32);
    function POSITION_MANAGER_ROLE() external view returns (bytes32);
    function VAULT_KEEPER_ROLE() external view returns (bytes32);
    function POSITION_KEEPER_ROLE() external view returns (bytes32);
    function EMERGENCY_ROLE() external view returns (bytes32);
    function UPGRADER_ROLE() external view returns (bytes32);
    function GUARDIAN_ROLE() external view returns (bytes32);

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
        returns (bool hasRoleResult);

    /**
     * @notice Check if account is vault admin (global or vault-specific)
     * @param vault Vault address
     * @param account Account to check
     * @return isAdmin True if account is admin
     */
    function isVaultAdmin(address vault, address account) external view returns (bool isAdmin);

    /**
     * @notice Check if account is position manager
     * @param account Account to check
     * @return isPositionMgr True if account is position manager
     */
    function isPositionManager(address account) external view returns (bool isPositionMgr);

    /**
     * @notice Check if account is vault keeper
     * @param account Account to check
     * @return isKeeperResult True if account is vault keeper
     */
    function isVaultKeeper(address account) external view returns (bool isKeeperResult);

    /**
     * @notice Check if account is position keeper
     * @param account Account to check
     * @return isKeeperResult True if account is position keeper
     */
    function isPositionKeeper(address account) external view returns (bool isKeeperResult);

    /**
     * @notice Check if account has emergency role
     * @param account Account to check
     * @return hasEmergency True if account has emergency role
     */
    function hasEmergencyRole(address account) external view returns (bool hasEmergency);

    /**
     * @notice Check if vault is registered
     * @param vault Vault address
     * @return isRegistered True if vault is registered
     */
    function isVaultRegistered(address vault) external view returns (bool isRegistered);

    /**
     * @notice Check if account has a specific role (OpenZeppelin AccessControl)
     * @param role Role to check
     * @param account Account to check
     * @return hasRoleResult True if account has the role
     */
    function hasRole(bytes32 role, address account) external view returns (bool hasRoleResult);

    // ========================================================================
    // GUARDIAN FUNCTIONS
    // ========================================================================

    /**
     * @notice Check if account is a guardian
     * @param account Account to check
     * @return isGuardianResult True if account is guardian
     */
    function isGuardian(address account) external view returns (bool isGuardianResult);

    /**
     * @notice Get current guardian count
     * @return count Number of guardians
     */
    function getGuardianCount() external view returns (uint256 count);

    /**
     * @notice Get guardian configuration
     * @return minGuardians Minimum guardians required
     * @return maxGuardians Maximum guardians allowed
     * @return currentCount Current guardian count
     */
    function getGuardianConfig()
        external
        view
        returns (uint256 minGuardians, uint256 maxGuardians, uint256 currentCount);

    // ========================================================================
    // CONFIRMATION WINDOW FUNCTIONS
    // ========================================================================

    /**
     * @notice Get confirmation window configuration
     * @return minWindow Minimum allowed window
     * @return maxWindow Maximum allowed window
     * @return currentWindow Current confirmation window
     */
    function getConfirmationWindowConfig()
        external
        view
        returns (uint256 minWindow, uint256 maxWindow, uint256 currentWindow);
}
