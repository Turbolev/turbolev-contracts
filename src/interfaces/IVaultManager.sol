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
        address priceToken;
        address collateralToken;
        address vaultAddress;
        uint256 deployedAt;
        bool isActive;
        bool isBeaconProxy;
    }
    /**
     * @notice Get vault address for a (collateralToken, priceToken) pair
     * @param collateralToken Token used for LP liquidity and user collateral (e.g. USDC)
     * @param priceToken Token whose price is tracked by the oracle (e.g. SEI)
     * @return vaultAddress Vault contract address
     */
    function getVault(address collateralToken, address priceToken)
        external
        view
        returns (address vaultAddress);

    /**
     * @notice Check if vault is supported for a (collateralToken, priceToken) pair
     * @param collateralToken Collateral token address
     * @param priceToken Price token address
     * @return supported Whether vault exists
     */
    function isVaultSupported(address collateralToken, address priceToken)
        external
        view
        returns (bool supported);

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
     * @notice Deposit collateral from bet
     * @param _priceToken Token whose price is tracked (e.g. SEI)
     * @param _collateralToken Token used as collateral (e.g. USDC)
     * @param positionId Position ID
     * @param amount Collateral amount
     * @param positionSize Position size
     * @param isMarginAdd True if adding margin to existing position
     * @param direction Position direction (1 = LONG, 2 = SHORT)
     * @dev Not payable — collateral is ERC-20 only (R3-I-04).
     */
    function depositFromBet(
        address _priceToken,
        address _collateralToken,
        uint64 positionId,
        uint256 amount,
        uint256 positionSize,
        bool isMarginAdd,
        uint8 direction
    ) external;

    /**
     * @notice Execute payout to user
     * @param _priceToken Price token address (used to look up vault)
     * @param _collateralToken Collateral token address (used to look up vault and transfer)
     * @param user User address
     * @param amount Payout amount
     * @param positionId Position ID for tracking partial payouts
     */
    function executePayout(
        address _priceToken,
        address _collateralToken,
        address user,
        uint256 amount,
        uint64 positionId
    ) external;

    /**
     * @notice Update vault P&L with leverage
     * @param _priceToken Price token address (used to look up vault)
     * @param _collateralToken Collateral token address (used to look up vault)
     * @param positionId Position ID (for tracking)
     * @param collateral Collateral amount
     * @param vaultPnL Vault P&L
     * @param positionSize Position size
     * @param direction Position direction (1 = LONG, 2 = SHORT)
     * @param user User address for event tracking
     */
    function updateVaultPnLWithLeverage(
        address _priceToken,
        address _collateralToken,
        uint64 positionId,
        uint256 collateral,
        int256 vaultPnL,
        uint256 positionSize,
        uint8 direction,
        address user,
        uint256 payout
    ) external returns (uint256 closeFee);

    /**
     * @notice Get vault address by pair key (collateralToken, priceToken)
     * @param pairKey keccak256(abi.encode(collateralToken, priceToken))
     * @return vaultAddress Vault address
     */
    function vaultsByPair(bytes32 pairKey) external view returns (address vaultAddress);

    /**
     * @notice Get all vaults
     * @return Array of vault addresses
     */
    function getAllVaults() external view returns (address[] memory);

    /**
     * @notice Get price token address for a vault
     * @param vaultAddress Vault address
     * @return priceToken Price token address
     */
    function vaultPriceToken(address vaultAddress) external view returns (address priceToken);

    /**
     * @notice Get collateral token address for a vault
     * @param vaultAddress Vault address
     * @return collateralToken Collateral token address
     */
    function vaultCollateralToken(address vaultAddress)
        external
        view
        returns (address collateralToken);

    /**
     * @notice Pause factory
     */
    function pause() external;

    /**
     * @notice Unpause factory
     */
    function unpause() external;

    /**
     * @notice Pause vault by (collateralToken, priceToken) pair
     * @param collateralToken Collateral token address
     * @param priceToken Price token address
     */
    function pauseVault(address collateralToken, address priceToken) external;

    /**
     * @notice Unpause vault by (collateralToken, priceToken) pair
     * @param collateralToken Collateral token address
     * @param priceToken Price token address
     * @dev R3-M-01 fix: restricted to owner (Timelock) only.
     */
    function unpauseVault(address collateralToken, address priceToken) external;

    /**
     * @notice Pause vault by vault address directly
     * @param vault Vault address
     */
    function pauseVaultByAddress(address vault) external;

    /**
     * @notice Unpause vault by vault address directly
     * @param vault Vault address
     * @dev R3-M-01 fix: restricted to owner (Timelock) only.
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
     * @dev R3-M-01 fix: restricted to owner (Timelock) only.
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
    // EMERGENCY FUNCTIONS
    // Pause: EMERGENCY_ROLE (no delay)
    // Unpause: owner/Timelock only (R3-M-01 fix)
    // ========================================================================

    /**
     * @notice Emergency pause vault by (collateralToken, priceToken) pair (NO TIMELOCK DELAY)
     * @param collateralToken Collateral token address
     * @param priceToken Price token address
     */
    function emergencyPauseVault(address collateralToken, address priceToken) external;

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
     * @notice Emergency unpause vault by (collateralToken, priceToken) pair
     * @param collateralToken Collateral token address
     * @param priceToken Price token address
     * @dev Restricted to owner (Timelock) only.
     */
    function emergencyUnpauseVault(address collateralToken, address priceToken) external;

    /**
     * @notice Emergency unpause vault by address
     * @param vault Vault address
     * @dev Restricted to owner (Timelock) only.
     */
    function emergencyUnpauseVaultByAddress(address vault) external;

    /**
     * @notice Emergency batch unpause vaults
     * @param vaults Array of vault addresses
     * @dev Restricted to owner (Timelock) only.
     */
    function emergencyBatchUnpauseVaults(address[] calldata vaults) external;
}
