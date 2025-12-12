// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IVaultAdminProxy
 * @notice Interface for VaultAdminProxy contract
 * @dev Admin proxy for vault batch operations and configuration
 */
interface IVaultAdminProxy {
    // ========================================================================
    // EVENTS
    // ========================================================================

    event VaultPaused(address indexed vault, address indexed caller, uint256 timestamp);
    event VaultUnpaused(address indexed vault, address indexed caller, uint256 timestamp);
    event VaultParamsUpdated(
        address indexed vault, uint256 minBetAmount, uint256 maxBetAmount, uint256 timestamp
    );
    event VaultFeeUpdated(address indexed vault, uint8 feeType, uint16 feeBps, uint256 timestamp);
    event VaultTreasuryUpdated(address indexed vault, address treasury, uint256 timestamp);
    event VaultTradingEnabledUpdated(address indexed vault, bool enabled, uint256 timestamp);
    event VaultGraduationThresholdUpdated(
        address indexed vault, uint256 threshold, uint256 timestamp
    );
    event VaultFundingConfigUpdated(address indexed vault, uint256 timestamp);
    event VaultFundingEnabledUpdated(address indexed vault, bool enabled, uint256 timestamp);
    event FeesWithdrawn(address indexed vault, uint256 amount, uint256 timestamp);
    event BatchFundingUpdated(uint256 vaultsUpdated, uint256 timestamp);
    event PriceFeedManagerUpdated(address indexed oldManager, address indexed newManager);

    // ========================================================================
    // ERRORS
    // ========================================================================

    error InvalidAddress();
    error NotAuthorized();
    error VaultNotFound();
    error VaultNotActive();

    // ========================================================================
    // STATE GETTERS
    // ========================================================================

    function vaultManager() external view returns (address);
    function accessController() external view returns (address);
    function priceFeedManager() external view returns (address);

    // ========================================================================
    // BATCH OPERATIONS (VAULT_KEEPER_ROLE)
    // ========================================================================

    /**
     * @notice Batch update hourly funding rates for all vaults
     * @return updatedCount Number of vaults successfully updated
     */
    function batchUpdateHourlyFunding() external returns (uint256 updatedCount);

    /**
     * @notice Update hourly funding for specific vaults
     * @param vaults Array of vault addresses to update
     * @return updatedCount Number of vaults successfully updated
     */
    function batchUpdateHourlyFundingForVaults(address[] calldata vaults)
        external
        returns (uint256 updatedCount);

    // ========================================================================
    // VAULT ADMIN FUNCTIONS (VAULT_ADMIN_ROLE)
    // ========================================================================

    /**
     * @notice Pause a specific vault
     * @param projectToken Project token address
     */
    function pauseVault(address projectToken) external;

    /**
     * @notice Unpause a specific vault
     * @param projectToken Project token address
     */
    function unpauseVault(address projectToken) external;

    /**
     * @notice Update vault parameters
     * @param projectToken Project token address
     * @param minBetAmount Minimum bet amount
     * @param maxBetAmount Maximum bet amount
     */
    function updateVaultParams(address projectToken, uint256 minBetAmount, uint256 maxBetAmount)
        external;

    /**
     * @notice Withdraw collected fees from a vault
     * @param projectToken Project token address
     * @param amount Amount to withdraw (0 = withdraw all)
     */
    function withdrawFees(address projectToken, uint256 amount) external;

    /**
     * @notice Set staking fee BPS for a vault
     * @param projectToken Project token address
     * @param stakingFeeBps Staking fee in basis points
     */
    function setVaultStakingFeeBps(address projectToken, uint16 stakingFeeBps) external;

    /**
     * @notice Set early withdrawal fee BPS for a vault
     * @param projectToken Project token address
     * @param earlyWithdrawalFeeBps Early withdrawal fee in basis points
     */
    function setVaultEarlyWithdrawalFeeBps(address projectToken, uint16 earlyWithdrawalFeeBps)
        external;

    /**
     * @notice Set open position fee BPS for a vault
     * @param projectToken Project token address
     * @param openPositionFeeBps Open position fee in basis points
     */
    function setVaultOpenPositionFeeBps(address projectToken, uint16 openPositionFeeBps) external;

    /**
     * @notice Set close position fee BPS for a vault
     * @param projectToken Project token address
     * @param closePositionFeeBps Close position fee in basis points
     */
    function setVaultClosePositionFeeBps(address projectToken, uint16 closePositionFeeBps) external;

    /**
     * @notice Set graduation threshold for a vault
     * @param projectToken Project token address
     * @param graduationThreshold Graduation threshold
     */
    function setVaultGraduationThreshold(address projectToken, uint256 graduationThreshold) external;

    /**
     * @notice Set trading enabled for a vault
     * @param projectToken Project token address
     * @param enabled Trading enabled
     */
    function setVaultTradingEnabled(address projectToken, bool enabled) external;

    /**
     * @notice Set treasury address for a specific vault
     * @param projectToken Project token address
     * @param treasury Treasury address
     */
    function setVaultTreasury(address projectToken, address treasury) external;

    /**
     * @notice Set treasury address for all vaults
     * @param treasury Treasury address
     */
    function setTreasuryForAllVaults(address treasury) external;

    /**
     * @notice Set funding configuration for a vault
     * @param projectToken Project token address
     * @param tier1RateBps Rate for < 20% imbalance
     * @param tier2RateBps Rate for 20-40% imbalance
     * @param tier3RateBps Rate for 40-60% imbalance
     * @param tier4RateBps Rate for 60-80% imbalance
     * @param tier5RateBps Rate for > 80% imbalance
     */
    function setVaultFundingConfig(
        address projectToken,
        uint16 tier1RateBps,
        uint16 tier2RateBps,
        uint16 tier3RateBps,
        uint16 tier4RateBps,
        uint16 tier5RateBps
    ) external;

    /**
     * @notice Enable or disable funding for a vault
     * @param projectToken Project token address
     * @param enabled True to enable funding
     */
    function setVaultFundingEnabled(address projectToken, bool enabled) external;

    /**
     * @notice Enable funding for all vaults
     * @param enabled True to enable funding
     */
    function setFundingEnabledForAllVaults(bool enabled) external;

    // ========================================================================
    // ADMIN CONFIGURATION (DEFAULT_ADMIN_ROLE)
    // ========================================================================

    /**
     * @notice Set PriceFeedManager address
     * @param _priceFeedManager PriceFeedManager contract address
     */
    function setPriceFeedManager(address _priceFeedManager) external;

    /**
     * @notice Set VaultManager address
     * @param _vaultManager VaultManager contract address
     */
    function setVaultManager(address _vaultManager) external;

    /**
     * @notice Set VaultAccessController address
     * @param _accessController VaultAccessController contract address
     */
    function setAccessController(address _accessController) external;

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /**
     * @notice Get vault address for a project token
     * @param projectToken Project token address
     * @return vault Vault address
     */
    function getVault(address projectToken) external view returns (address vault);

    /**
     * @notice Get all vault addresses
     * @return vaults Array of vault addresses
     */
    function getAllVaults() external view returns (address[] memory vaults);

    /**
     * @notice Check if vault is supported for a project token
     * @param projectToken Project token address
     * @return supported Whether vault is supported
     */
    function isVaultSupported(address projectToken) external view returns (bool supported);

    /**
     * @notice Get contract version
     * @return Contract version string
     */
    function version() external pure returns (string memory);
}
