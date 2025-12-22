// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IVaultManager
 * @notice Interface for VaultManager contract - Beacon proxy factory with governance
 * @dev V2.0 with Timelock + Multisig + Opt-in upgrades
 */
interface IVaultManager {
    // ========================================================================
    // STRUCTS
    // ========================================================================

    struct VaultInfo {
        address projectToken;
        address vaultAddress;
        uint256 deployedAt;
        bool isActive;
        bool isBeaconProxy;
    }
    /**
     * @notice Get vault address for project token
     * @param _projectToken Project token address
     * @return vaultAddress Vault contract address
     */

    function getVault(address _projectToken) external view returns (address vaultAddress);

    /**
     * @notice Check if vault is supported for project token
     * @param _projectToken Project token address
     * @return supported Whether vault exists
     */
    function isVaultSupported(address _projectToken) external view returns (bool supported);

    // /**
    //  * @notice Check position risk
    //  * @param _projectToken Project token address
    //  * @param positionSize Position size (collateral * leverage)
    //  * @param leverage Leverage multiplier
    //  * @return canOpen Whether position can be opened
    //  * @return reason Reason if cannot open
    //  */
    // function checkPositionRisk(address _projectToken, uint256 positionSize, uint8 leverage)
    //     external
    //     view
    //     returns (bool canOpen, string memory reason);

    /**
     * @notice Deposit collateral from bet (v1: project token only)
     * @param _projectToken Project token address
     * @param positionId Position ID
     * @param amount Collateral amount in project tokens
     * @param positionSize Position size
     * @param isMarginAdd True if adding margin to existing position
     * @param direction Position direction (1 = LONG, 2 = SHORT)
     */
    function depositFromBet(
        address _projectToken,
        uint64 positionId,
        uint256 amount,
        uint256 positionSize,
        bool isMarginAdd,
        uint8 direction
    ) external payable;

    /**
     * @notice Execute payout to user (v1: project token only)
     * @param _projectToken Project token address
     * @param user User address
     * @param amount Payout amount in project tokens
     * @param positionId Position ID for tracking partial payouts
     */
    function executePayout(address _projectToken, address user, uint256 amount, uint64 positionId)
        external;

    /**
     * @notice Update vault P&L with leverage
     * @param _projectToken Project token address
     * @param positionId Position ID (for tracking)
     * @param collateral Collateral amount
     * @param vaultPnL Vault P&L
     * @param fee Fee collected
     * @param positionSize Position size
     * @param direction Position direction (1 = LONG, 2 = SHORT)
     * @param user User address for event tracking (M-05 FIX: Replace tx.origin)
     */
    function updateVaultPnLWithLeverage(
        address _projectToken,
        uint64 positionId,
        uint256 collateral,
        int256 vaultPnL,
        uint256 fee,
        uint256 positionSize,
        uint8 direction,
        address user
    ) external returns (uint256 closeFee);

    /**
     * @notice Get vault address by project token (alias for getVault)
     * @param projectToken Project token address
     * @return vaultAddress Vault address
     */
    function vaultsByProjectToken(address projectToken) external view returns (address vaultAddress);

    /**
     * @notice Get all vaults
     * @return Array of vault addresses
     */
    function getAllVaults() external view returns (address[] memory);

    /**
     * @notice Get project token address for a vault
     * @param vaultAddress Vault address
     * @return projectToken Project token address
     */
    function vaultProjectToken(address vaultAddress) external view returns (address projectToken);

    /**
     * @notice Pause factory
     */
    function pause() external;

    /**
     * @notice Unpause factory
     */
    function unpause() external;

    /**
     * @notice Pause vault by project token
     * @param _projectToken Project token address
     */
    function pauseVault(address _projectToken) external;

    /**
     * @notice Unpause vault by project token
     * @param _projectToken Project token address
     */
    function unpauseVault(address _projectToken) external;

    /**
     * @notice Pause vault by vault address directly
     * @param vault Vault address
     */
    function pauseVaultByAddress(address vault) external;

    /**
     * @notice Unpause vault by vault address directly
     * @param vault Vault address
     */
    function unpauseVaultByAddress(address vault) external;

    /**
     * @notice Batch pause multiple vaults
     * @param vaults Array of vault addresses
     */
    function batchPauseVaults(address[] calldata vaults) external;

    /**
     * @notice Batch unpause multiple vaults
     * @param vaults Array of vault addresses
     */
    function batchUnpauseVaults(address[] calldata vaults) external;

    /**
     * @notice Get vault info
     * @param vault Vault address
     * @return info VaultInfo struct
     */
    function getVaultInfo(address vault) external view returns (VaultInfo memory info);

    /**
     * @notice Get active vaults only
     * @return active Array of active vault addresses
     */
    function getActiveVaults() external view returns (address[] memory active);

    /**
     * @notice Get beacon proxy vaults only
     * @return beaconVaults Array of beacon proxy vault addresses
     */
    function getBeaconProxyVaults() external view returns (address[] memory beaconVaults);

    /**
     * @notice Deactivate vault
     * @param vault Vault address
     */
    function deactivateVault(address vault) external;

    /**
     * @notice Reactivate vault
     * @param vault Vault address
     */
    function reactivateVault(address vault) external;

    // ========================================================================
    // EMERGENCY FUNCTIONS (NO TIMELOCK DELAY)
    // ========================================================================

    /**
     * @notice Emergency pause vault by project token (NO TIMELOCK DELAY)
     * @param _projectToken Project token address
     */
    function emergencyPauseVault(address _projectToken) external;

    /**
     * @notice Emergency pause vault by address (NO TIMELOCK DELAY)
     * @param vault Vault address
     */
    function emergencyPauseVaultByAddress(address vault) external;

    /**
     * @notice Emergency batch pause vaults (NO TIMELOCK DELAY)
     * @param vaults Array of vault addresses
     */
    function emergencyBatchPauseVaults(address[] calldata vaults) external;

    /**
     * @notice Emergency unpause vault by project token (NO TIMELOCK DELAY)
     * @param _projectToken Project token address
     */
    function emergencyUnpauseVault(address _projectToken) external;

    /**
     * @notice Emergency unpause vault by address (NO TIMELOCK DELAY)
     * @param vault Vault address
     */
    function emergencyUnpauseVaultByAddress(address vault) external;

    /**
     * @notice Emergency batch unpause vaults (NO TIMELOCK DELAY)
     * @param vaults Array of vault addresses
     */
    function emergencyBatchUnpauseVaults(address[] calldata vaults) external;
}
