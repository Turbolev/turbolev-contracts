// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IVaultManager
 * @notice Interface for VaultManager contract - Multi-collateral support
 */
interface IVaultManager {
    /**
     * @notice Get vault address for (projectToken, collateralToken) pair
     * @param _projectToken Project token address
     * @param _collateralToken Collateral token address
     * @return vaultAddress Vault contract address
     */
    function getVault(
        address _projectToken,
        address _collateralToken
    ) external view returns (address vaultAddress);

    /**
     * @notice Check if vault is supported for token pair
     * @param _projectToken Project token address
     * @param _collateralToken Collateral token address
     * @return supported Whether vault exists
     */
    function isVaultSupported(
        address _projectToken,
        address _collateralToken
    ) external view returns (bool supported);

    /**
     * @notice Check position risk
     * @param _projectToken Project token address
     * @param _collateralToken Collateral token address
     * @param positionSize Position size (collateral * leverage)
     * @param leverage Leverage multiplier
     * @param priceFeedId Pyth price feed ID of asset being bet on
     * @return canOpen Whether position can be opened
     * @return reason Reason if cannot open
     */
    function checkPositionRisk(
        address _projectToken,
        address _collateralToken,
        uint256 positionSize,
        uint8 leverage,
        bytes32 priceFeedId
    ) external view returns (bool canOpen, string memory reason);

    /**
     * @notice Deposit collateral from bet
     * @param _projectToken Project token address
     * @param _collateralToken Collateral token address
     * @param amount Collateral amount
     * @param positionSize Position size
     * @param priceFeedId Pyth price feed ID of asset being bet on
     * @param direction Position direction (1=LONG, 2=SHORT)
     */
    function depositFromBet(
        address _projectToken,
        address _collateralToken,
        uint256 amount,
        uint256 positionSize,
        bytes32 priceFeedId,
        uint8 direction
    ) external payable;

    /**
     * @notice Execute payout to user
     * @param _projectToken Project token address
     * @param _collateralToken Collateral token address
     * @param user User address
     * @param amount Payout amount
     */
    function executePayout(
        address _projectToken,
        address _collateralToken,
        address user,
        uint256 amount
    ) external;

    /**
     * @notice Update vault P&L with leverage
     * @param _projectToken Project token address
     * @param _collateralToken Collateral token address
     * @param positionId Position ID (for tracking)
     * @param collateral Collateral amount
     * @param vaultPnL Vault P&L
     * @param fee Fee collected
     * @param positionSize Position size
     * @param excessProfit Excess profit from capped trades
     * @param priceFeedId Pyth price feed ID of the asset
     * @param direction Position direction (1=LONG, 2=SHORT)
     */
    function updateVaultPnLWithLeverage(
        address _projectToken,
        address _collateralToken,
        uint64 positionId,
        uint256 collateral,
        int256 vaultPnL,
        uint256 fee,
        uint256 positionSize,
        uint256 excessProfit,
        bytes32 priceFeedId,
        uint8 direction
    ) external;
}
