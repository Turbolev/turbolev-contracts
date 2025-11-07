// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IVaultManager
 * @notice Interface for VaultManager contract - Single project token per vault with dual currency support
 */
interface IVaultManager {
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

    /**
     * @notice Check position risk
     * @param _projectToken Project token address
     * @param positionSize Position size (collateral * leverage)
     * @param leverage Leverage multiplier
     * @return canOpen Whether position can be opened
     * @return reason Reason if cannot open
     */
    function checkPositionRisk(address _projectToken, uint256 positionSize, uint8 leverage)
        external
        view
        returns (bool canOpen, string memory reason);

    /**
     * @notice Deposit collateral from bet (v1: project token only)
     * @param _projectToken Project token address
     * @param positionId Position ID
     * @param amount Collateral amount in project tokens
     * @param positionSize Position size
     * @param isMarginAdd True if adding margin to existing position
     */
    function depositFromBet(
        address _projectToken,
        uint64 positionId,
        uint256 amount,
        uint256 positionSize,
        bool isMarginAdd
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
     */
    function updateVaultPnLWithLeverage(
        address _projectToken,
        uint64 positionId,
        uint256 collateral,
        int256 vaultPnL,
        uint256 fee,
        uint256 positionSize
    ) external;

    /**
     * @notice Get vault address by project token (alias for getVault)
     * @param projectToken Project token address
     * @return vaultAddress Vault address
     */
    function vaultsByProjectToken(address projectToken)
        external
        view
        returns (address vaultAddress);

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
     * @notice Pause a specific vault
     * @param _projectToken Project token address
     */
    function pauseVault(address _projectToken) external;

    /**
     * @notice Unpause a specific vault
     * @param _projectToken Project token address
     */
    function unpauseVault(address _projectToken) external;
}
