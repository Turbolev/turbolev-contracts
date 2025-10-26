// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IVaultManager
 * @notice Interface for VaultManager contract
 */
interface IVaultManager {
    /**
     * @notice Get vault address for token
     * @param tokenAddress Token address
     * @return vaultAddress Vault contract address
     */
    function getVault(
        address tokenAddress
    ) external view returns (address vaultAddress);

    /**
     * @notice Check if vault is supported for token
     * @param tokenAddress Token address
     * @return supported Whether vault exists
     */
    function isVaultSupported(
        address tokenAddress
    ) external view returns (bool supported);

    /**
     * @notice Check position risk
     * @param tokenAddress Collateral token address
     * @param positionSize Position size (collateral * leverage)
     * @param leverage Leverage multiplier
     * @param priceFeedId Pyth price feed ID of asset being bet on
     * @return canOpen Whether position can be opened
     * @return reason Reason if cannot open
     */
    function checkPositionRisk(
        address tokenAddress,
        uint256 positionSize,
        uint8 leverage,
        bytes32 priceFeedId
    ) external view returns (bool canOpen, string memory reason);

    /**
     * @notice Deposit collateral from bet
     * @param tokenAddress Collateral token address
     * @param amount Collateral amount
     * @param positionSize Position size
     * @param priceFeedId Pyth price feed ID of asset being bet on
     * @param direction Position direction (1=LONG, 2=SHORT)
     */
    function depositFromBet(
        address tokenAddress,
        uint256 amount,
        uint256 positionSize,
        bytes32 priceFeedId,
        uint8 direction
    ) external payable;

    /**
     * @notice Execute payout to user
     * @param tokenAddress Collateral token address
     * @param user User address
     * @param amount Payout amount
     */
    function executePayout(
        address tokenAddress,
        address user,
        uint256 amount
    ) external;

    /**
     * @notice Update vault P&L with leverage
     * @param tokenAddress Collateral token address
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
        address tokenAddress,
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
