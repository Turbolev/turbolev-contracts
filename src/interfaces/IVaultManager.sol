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
    function getVault(
        address _projectToken
    ) external view returns (address vaultAddress);

    /**
     * @notice Check if vault is supported for project token
     * @param _projectToken Project token address
     * @return supported Whether vault exists
     */
    function isVaultSupported(
        address _projectToken
    ) external view returns (bool supported);

    /**
     * @notice Check position risk
     * @param _projectToken Project token address
     * @param positionSize Position size (collateral * leverage)
     * @param leverage Leverage multiplier
     * @param useProjectToken True if using project token, false if using MON
     * @return canOpen Whether position can be opened
     * @return reason Reason if cannot open
     */
    function checkPositionRisk(
        address _projectToken,
        uint256 positionSize,
        uint8 leverage,
        bool useProjectToken
    ) external view returns (bool canOpen, string memory reason);

    /**
     * @notice Deposit collateral from bet (supports MON or project token)
     * @param _projectToken Project token address
     * @param amount Collateral amount
     * @param positionSize Position size
     * @param useProjectToken True if using project token, false if using MON
     * @param direction Position direction (1=LONG, 2=SHORT)
     */
    function depositFromBet(
        address _projectToken,
        uint256 amount,
        uint256 positionSize,
        bool useProjectToken,
        uint8 direction
    ) external payable;

    /**
     * @notice Execute payout to user (supports MON or project token)
     * @param _projectToken Project token address
     * @param user User address
     * @param amount Payout amount
     * @param useProjectToken True if payout should be in project token, false for MON
     * @param positionId Position ID for tracking partial payouts
     */
    function executePayout(
        address _projectToken,
        address user,
        uint256 amount,
        bool useProjectToken,
        uint64 positionId
    ) external;

    /**
     * @notice Update vault P&L with leverage
     * @param _projectToken Project token address
     * @param positionId Position ID (for tracking)
     * @param collateral Collateral amount
     * @param vaultPnL Vault P&L
     * @param fee Fee collected
     * @param positionSize Position size
     * @param excessProfit Excess profit from capped trades
     * @param direction Position direction (1=LONG, 2=SHORT)
     */
    function updateVaultPnLWithLeverage(
        address _projectToken,
        uint64 positionId,
        uint256 collateral,
        int256 vaultPnL,
        uint256 fee,
        uint256 positionSize,
        uint256 excessProfit,
        uint8 direction
    ) external;
}
