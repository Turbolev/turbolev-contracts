// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./VaultAccessController.sol";
import "../interfaces/IVaultManager.sol";
import "../interfaces/IVaultRouter.sol";

/**
 * @title VaultAdminProxy
 * @notice Admin proxy contract for vault operations
 * @dev Provides batch operations and admin functions for vault management
 *      Uses VaultAccessController for role-based access control
 *
 * Roles:
 * - VAULT_ADMIN_ROLE: Can configure individual vault parameters
 * - VAULT_KEEPER_ROLE: Can perform batch operations (funding updates)
 * - DEFAULT_ADMIN_ROLE: Can update contract configuration
 *
 * This contract replaces VaultManagerHelper for admin operations.
 */
contract VaultAdminProxy is Initializable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    // ========================================================================
    // STATE VARIABLES
    // ========================================================================

    /// @notice VaultManager contract address
    address public vaultManager;

    /// @notice VaultAccessController contract address
    address public accessController;

    /// @notice PriceFeedManager contract address (for USD calculations)
    address public priceFeedManager;

    // ========================================================================
    // STORAGE GAP
    // ========================================================================

    uint256[47] private __gap;

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
    event VaultTreasuryUpdateFailed(address indexed vault, uint256 timestamp);
    event BatchTreasuryUpdateCompleted(uint256 successCount, uint256 failCount, uint256 timestamp);
    event VaultTradingEnabledUpdated(address indexed vault, bool enabled, uint256 timestamp);
    event VaultGraduationThresholdUpdated(
        address indexed vault, uint256 threshold, uint256 timestamp
    );
    event VaultFundingConfigUpdated(address indexed vault, uint256 timestamp);
    event VaultFundingEnabledUpdated(address indexed vault, bool enabled, uint256 timestamp);
    event VaultFundingEnabledUpdateFailed(address indexed vault, uint256 timestamp);
    event BatchFundingEnabledUpdateCompleted(
        uint256 successCount, uint256 failCount, uint256 timestamp
    );
    event FeesWithdrawn(address indexed vault, uint256 amount, uint256 timestamp);

    event PriceFeedManagerUpdated(address indexed oldManager, address indexed newManager);
    event VaultMaxLeverageUpdated(address indexed vault, uint16 maxLeverage, uint256 timestamp);
    event VaultTotalOITierConfigUpdated(address indexed vault, uint256 timestamp);
    event VaultMaxDirectionalExposureUpdated(
        address indexed vault, uint16 maxDirectionalExposureBps, uint256 timestamp
    );
    event VaultMaxProfitCapMultiplierUpdated(
        address indexed vault, uint8 multiplier, uint256 timestamp
    );

    // ========================================================================
    // ERRORS
    // ========================================================================

    error InvalidAddress();
    error NotAuthorized();
    error VaultNotFound();
    error VaultNotActive();

    // ========================================================================
    // CONSTRUCTOR / INITIALIZER
    // ========================================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the admin proxy
     * @param _vaultManager VaultManager contract address
     * @param _accessController VaultAccessController contract address
     * @param _priceFeedManager PriceFeedManager contract address
     */
    function initialize(address _vaultManager, address _accessController, address _priceFeedManager)
        external
        initializer
    {
        if (_vaultManager == address(0)) revert InvalidAddress();
        if (_accessController == address(0)) revert InvalidAddress();
        if (_priceFeedManager == address(0)) revert InvalidAddress();

        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        vaultManager = _vaultManager;
        accessController = _accessController;
        priceFeedManager = _priceFeedManager;
    }

    // ========================================================================
    // MODIFIERS
    // ========================================================================

    /**
     * @notice Check if caller has VAULT_ADMIN_ROLE
     */
    modifier onlyVaultAdmin() {
        VaultAccessController ac = VaultAccessController(accessController);
        if (!ac.hasRole(ac.VAULT_ADMIN_ROLE(), msg.sender)) {
            revert NotAuthorized();
        }
        _;
    }

    /**
     * @notice Check if caller has VAULT_KEEPER_ROLE
     */
    modifier onlyVaultKeeper() {
        VaultAccessController ac = VaultAccessController(accessController);
        if (!ac.hasRole(ac.VAULT_KEEPER_ROLE(), msg.sender)) {
            revert NotAuthorized();
        }
        _;
    }

    /**
     * @notice Check if caller has DEFAULT_ADMIN_ROLE
     */
    modifier onlyDefaultAdmin() {
        VaultAccessController ac = VaultAccessController(accessController);
        if (!ac.hasRole(ac.DEFAULT_ADMIN_ROLE(), msg.sender)) {
            revert NotAuthorized();
        }
        _;
    }

    // ========================================================================
    // BATCH OPERATIONS (VAULT_KEEPER_ROLE)
    // ========================================================================

    // ========================================================================
    // VAULT ADMIN FUNCTIONS (VAULT_ADMIN_ROLE)
    // ========================================================================

    /**
     * @notice Pause a specific vault
     *  collateralToken Collateral token address
     *  priceToken Price token address
     */
    function pauseVault(address collateralToken, address priceToken) external onlyVaultAdmin {
        address vault = _getVault(collateralToken, priceToken);
        IVaultRouter(vault).pause();
        emit VaultPaused(vault, msg.sender, block.timestamp);
    }

    /**
     * @notice Unpause a specific vault
     *  collateralToken Collateral token address
     *  priceToken Price token address
     */
    function unpauseVault(address collateralToken, address priceToken) external onlyVaultAdmin {
        address vault = _getVault(collateralToken, priceToken);
        IVaultRouter(vault).unpause();
        emit VaultUnpaused(vault, msg.sender, block.timestamp);
    }

    /**
     * @notice Update vault parameters
     *  collateralToken Collateral token address
     *  priceToken Price token address
     * @param minBetAmount Minimum bet amount
     * @param maxBetAmount Maximum bet amount
     */
    function updateVaultParams(
        address collateralToken,
        address priceToken,
        uint256 minBetAmount,
        uint256 maxBetAmount
    ) external onlyVaultAdmin {
        address vault = _getVault(collateralToken, priceToken);
        IVaultRouter(vault).updateVaultParams(minBetAmount, maxBetAmount);
        emit VaultParamsUpdated(vault, minBetAmount, maxBetAmount, block.timestamp);
    }

    /**
     * @notice Withdraw collected fees from a vault
     *  collateralToken Collateral token address
     *  priceToken Price token address
     * @param amount Amount to withdraw (0 = withdraw all)
     */
    function withdrawFees(address collateralToken, address priceToken, uint256 amount)
        external
        onlyVaultAdmin
    {
        address vault = _getVault(collateralToken, priceToken);
        IVaultRouter(vault).withdrawFees(amount);
        emit FeesWithdrawn(vault, amount, block.timestamp);
    }

    /**
     * @notice Set staking fee BPS for a vault
     *  collateralToken Collateral token address
     *  priceToken Price token address
     * @param stakingFeeBps Staking fee in basis points
     */
    function setVaultStakingFeeBps(
        address collateralToken,
        address priceToken,
        uint16 stakingFeeBps
    ) external onlyVaultAdmin {
        address vault = _getVault(collateralToken, priceToken);
        IVaultRouter(vault).setFee(0, stakingFeeBps); // feeType 0 = staking
        emit VaultFeeUpdated(vault, 0, stakingFeeBps, block.timestamp);
    }

    /**
     * @notice Set early withdrawal fee BPS for a vault
     *  collateralToken Collateral token address
     *  priceToken Price token address
     * @param earlyWithdrawalFeeBps Early withdrawal fee in basis points
     */
    function setVaultEarlyWithdrawalFeeBps(
        address collateralToken,
        address priceToken,
        uint16 earlyWithdrawalFeeBps
    ) external onlyVaultAdmin {
        address vault = _getVault(collateralToken, priceToken);
        IVaultRouter(vault).setFee(1, earlyWithdrawalFeeBps); // feeType 1 = earlyWithdrawal
        emit VaultFeeUpdated(vault, 1, earlyWithdrawalFeeBps, block.timestamp);
    }

    /**
     * @notice Set open position fee BPS for a vault
     *  collateralToken Collateral token address
     *  priceToken Price token address
     * @param openPositionFeeBps Open position fee in basis points
     */
    function setVaultOpenPositionFeeBps(
        address collateralToken,
        address priceToken,
        uint16 openPositionFeeBps
    ) external onlyVaultAdmin {
        address vault = _getVault(collateralToken, priceToken);
        IVaultRouter(vault).setFee(2, openPositionFeeBps); // feeType 2 = openPosition
        emit VaultFeeUpdated(vault, 2, openPositionFeeBps, block.timestamp);
    }

    /**
     * @notice Set close position fee BPS for a vault
     *  collateralToken Collateral token address
     *  priceToken Price token address
     * @param closePositionFeeBps Close position fee in basis points
     */
    function setVaultClosePositionFeeBps(
        address collateralToken,
        address priceToken,
        uint16 closePositionFeeBps
    ) external onlyVaultAdmin {
        address vault = _getVault(collateralToken, priceToken);
        IVaultRouter(vault).setFee(3, closePositionFeeBps); // feeType 3 = closePosition
        emit VaultFeeUpdated(vault, 3, closePositionFeeBps, block.timestamp);
    }

    /**
     * @notice Set graduation threshold for a vault
     *  collateralToken Collateral token address
     *  priceToken Price token address
     * @param graduationThreshold Graduation threshold
     */
    function setVaultGraduationThreshold(
        address collateralToken,
        address priceToken,
        uint256 graduationThreshold
    ) external onlyVaultAdmin {
        address vault = _getVault(collateralToken, priceToken);
        IVaultRouter(vault).setGraduationThreshold(graduationThreshold);
        emit VaultGraduationThresholdUpdated(vault, graduationThreshold, block.timestamp);
    }

    /**
     * @notice Set trading enabled for a vault
     *  collateralToken Collateral token address
     *  priceToken Price token address
     * @param enabled Trading enabled
     */
    function setVaultTradingEnabled(address collateralToken, address priceToken, bool enabled)
        external
        onlyVaultAdmin
    {
        address vault = _getVault(collateralToken, priceToken);
        IVaultRouter(vault).setTradingEnabled(enabled);
        emit VaultTradingEnabledUpdated(vault, enabled, block.timestamp);
    }

    /**
     * @notice Set treasury address for a specific vault
     *  collateralToken Collateral token address
     *  priceToken Price token address
     * @param treasury Treasury address
     */
    function setVaultTreasury(address collateralToken, address priceToken, address treasury)
        external
        onlyVaultAdmin
    {
        address vault = _getVault(collateralToken, priceToken);
        IVaultRouter(vault).setTreasury(treasury);
        emit VaultTreasuryUpdated(vault, treasury, block.timestamp);
    }

    /**
     * @notice Set treasury address for all vaults
     * @param treasury Treasury address
     * @dev Emits events for both successful and failed updates
     *      VaultTreasuryUpdated for successful updates
     *      VaultTreasuryUpdateFailed for failed updates
     *      BatchTreasuryUpdateCompleted with summary counts
     */
    function setTreasuryForAllVaults(address treasury) external nonReentrant onlyVaultAdmin {
        address[] memory vaults = IVaultManager(vaultManager).getAllVaults();
        uint256 successCount = 0;
        uint256 failCount = 0;

        for (uint256 i = 0; i < vaults.length; i++) {
            IVaultManager.VaultInfo memory info =
                IVaultManager(vaultManager).getVaultInfo(vaults[i]);
            if (!info.isActive) continue;

            try IVaultRouter(vaults[i]).setTreasury(treasury) {
                emit VaultTreasuryUpdated(vaults[i], treasury, block.timestamp);
                successCount++;
            } catch {
                // Log failed vaults instead of silently skipping
                emit VaultTreasuryUpdateFailed(vaults[i], block.timestamp);
                failCount++;
                continue;
            }
        }

        // Emit summary event
        emit BatchTreasuryUpdateCompleted(successCount, failCount, block.timestamp);
    }

    /**
     * @notice Set price impact tier configuration for a vault
     *  collateralToken Collateral token address
     *  priceToken Price token address
     * @param tier1ImpactBps Impact for < 20% imbalance
     * @param tier2ImpactBps Impact for 20-40% imbalance
     * @param tier3ImpactBps Impact for 40-60% imbalance
     * @param tier4ImpactBps Impact for 60-80% imbalance
     * @param tier5ImpactBps Impact for > 80% imbalance
     */
    function setVaultImpactConfig(
        address collateralToken,
        address priceToken,
        uint16 tier1ImpactBps,
        uint16 tier2ImpactBps,
        uint16 tier3ImpactBps,
        uint16 tier4ImpactBps,
        uint16 tier5ImpactBps
    ) external onlyVaultAdmin {
        address vault = _getVault(collateralToken, priceToken);
        IVaultRouter(vault)
            .setImpactConfig(
                tier1ImpactBps, tier2ImpactBps, tier3ImpactBps, tier4ImpactBps, tier5ImpactBps
            );
        emit VaultFundingConfigUpdated(vault, block.timestamp);
    }

    /**
     * @notice Enable or disable price impact for a vault
     *  collateralToken Collateral token address
     *  priceToken Price token address
     * @param enabled True to enable price impact
     */
    function setVaultImpactEnabled(address collateralToken, address priceToken, bool enabled)
        external
        onlyVaultAdmin
    {
        address vault = _getVault(collateralToken, priceToken);
        IVaultRouter(vault).setImpactEnabled(enabled);
        emit VaultFundingEnabledUpdated(vault, enabled, block.timestamp);
    }

    /**
     * @notice Enable or disable price impact for all vaults
     * @param enabled True to enable price impact
     * @dev Emits events for both successful and failed updates
     */
    function setImpactEnabledForAllVaults(bool enabled) external nonReentrant onlyVaultAdmin {
        address[] memory vaults = IVaultManager(vaultManager).getAllVaults();
        uint256 successCount = 0;
        uint256 failCount = 0;

        for (uint256 i = 0; i < vaults.length; i++) {
            IVaultManager.VaultInfo memory info =
                IVaultManager(vaultManager).getVaultInfo(vaults[i]);
            if (!info.isActive) continue;

            try IVaultRouter(vaults[i]).setImpactEnabled(enabled) {
                emit VaultFundingEnabledUpdated(vaults[i], enabled, block.timestamp);
                successCount++;
            } catch {
                emit VaultFundingEnabledUpdateFailed(vaults[i], block.timestamp);
                failCount++;
                continue;
            }
        }

        emit BatchFundingEnabledUpdateCompleted(successCount, failCount, block.timestamp);
    }

    // ========================================================================
    // RISK CONFIG ADMIN (VAULT_ADMIN_ROLE)
    // ========================================================================

    /**
     * @notice Set maximum leverage for a vault
     *  collateralToken Collateral token address
     *  priceToken Price token address
     * @param maxLeverage New maximum leverage (1 to 1000)
     */
    function setVaultMaxLeverage(address collateralToken, address priceToken, uint16 maxLeverage)
        external
        onlyVaultAdmin
    {
        address vault = _getVault(collateralToken, priceToken);
        IVaultRouter(vault).setMaxLeverage(maxLeverage);
        emit VaultMaxLeverageUpdated(vault, maxLeverage, block.timestamp);
    }

    /**
     * @notice Set total OI tier configuration for a vault
     *  collateralToken Collateral token address
     *  priceToken Price token address
     * @param totalOIRiskMultiplierBps Fixed multiplier when tiers disabled
     * @param tier1Threshold Small vault threshold
     * @param tier2Threshold Medium vault threshold
     * @param tier3Threshold Large vault threshold
     * @param tier1MultiplierBps Multiplier for tier 1
     * @param tier2MultiplierBps Multiplier for tier 2
     * @param tier3MultiplierBps Multiplier for tier 3
     * @param tier4MultiplierBps Multiplier for tier 4
     */
    function setVaultTotalOITierConfig(
        address collateralToken,
        address priceToken,
        uint16 totalOIRiskMultiplierBps,
        uint256 tier1Threshold,
        uint256 tier2Threshold,
        uint256 tier3Threshold,
        uint16 tier1MultiplierBps,
        uint16 tier2MultiplierBps,
        uint16 tier3MultiplierBps,
        uint16 tier4MultiplierBps
    ) external onlyVaultAdmin {
        address vault = _getVault(collateralToken, priceToken);
        IVaultRouter(vault)
            .setTotalOITierConfig(
                totalOIRiskMultiplierBps,
                tier1Threshold,
                tier2Threshold,
                tier3Threshold,
                tier1MultiplierBps,
                tier2MultiplierBps,
                tier3MultiplierBps,
                tier4MultiplierBps
            );
        emit VaultTotalOITierConfigUpdated(vault, block.timestamp);
    }

    /**
     * @notice Set max directional exposure for a vault
     *  collateralToken Collateral token address
     *  priceToken Price token address
     * @param maxDirectionalExposureBps Max directional exposure in basis points
     */
    function setVaultMaxDirectionalExposure(
        address collateralToken,
        address priceToken,
        uint16 maxDirectionalExposureBps
    ) external onlyVaultAdmin {
        address vault = _getVault(collateralToken, priceToken);
        IVaultRouter(vault).setMaxDirectionalExposure(maxDirectionalExposureBps);
        emit VaultMaxDirectionalExposureUpdated(vault, maxDirectionalExposureBps, block.timestamp);
    }

    /**
     * @notice Set max profit cap multiplier for a vault
     *  collateralToken Collateral token address
     *  priceToken Price token address
     * @param multiplier Max profit cap multiplier
     */
    function setVaultMaxProfitCapMultiplier(
        address collateralToken,
        address priceToken,
        uint8 multiplier
    ) external onlyVaultAdmin {
        address vault = _getVault(collateralToken, priceToken);
        IVaultRouter(vault).setMaxProfitCapMultiplier(multiplier);
        emit VaultMaxProfitCapMultiplierUpdated(vault, multiplier, block.timestamp);
    }

    // ========================================================================
    // ADMIN CONFIGURATION (DEFAULT_ADMIN_ROLE)
    // ========================================================================

    /**
     * @notice Set PriceFeedManager address
     * @param _priceFeedManager PriceFeedManager contract address
     */
    function setPriceFeedManager(address _priceFeedManager) external onlyDefaultAdmin {
        if (_priceFeedManager == address(0)) revert InvalidAddress();
        address oldManager = priceFeedManager;
        priceFeedManager = _priceFeedManager;
        emit PriceFeedManagerUpdated(oldManager, _priceFeedManager);
    }

    /**
     * @notice Set VaultManager address
     * @param _vaultManager VaultManager contract address
     */
    function setVaultManager(address _vaultManager) external onlyDefaultAdmin {
        if (_vaultManager == address(0)) revert InvalidAddress();
        vaultManager = _vaultManager;
    }

    /**
     * @notice Set VaultAccessController address
     * @param _accessController VaultAccessController contract address
     */
    function setAccessController(address _accessController) external onlyDefaultAdmin {
        if (_accessController == address(0)) revert InvalidAddress();
        accessController = _accessController;
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /**
     * @notice Get vault address for a (collateralToken, priceToken) pair
     * @param collateralToken Collateral token address
     * @param priceToken Price token address
     * @return vault Vault address
     */
    function getVault(address collateralToken, address priceToken)
        external
        view
        returns (address vault)
    {
        return IVaultManager(vaultManager).getVault(collateralToken, priceToken);
    }

    /**
     * @notice Get all vault addresses
     * @return vaults Array of vault addresses
     */
    function getAllVaults() external view returns (address[] memory vaults) {
        return IVaultManager(vaultManager).getAllVaults();
    }

    /**
     * @notice Check if vault is supported for a (collateralToken, priceToken) pair
     * @param collateralToken Collateral token address
     * @param priceToken Price token address
     * @return supported Whether vault is supported
     */
    function isVaultSupported(address collateralToken, address priceToken)
        external
        view
        returns (bool supported)
    {
        return IVaultManager(vaultManager).getVault(collateralToken, priceToken) != address(0);
    }

    // ========================================================================
    // INTERNAL FUNCTIONS
    // ========================================================================

    /**
     * @notice Get vault address from (collateralToken, priceToken) pair
     * @param collateralToken Collateral token address
     * @param priceToken Price token address
     * @return vault Vault address
     */
    function _getVault(address collateralToken, address priceToken)
        internal
        view
        returns (address vault)
    {
        vault = IVaultManager(vaultManager).getVault(collateralToken, priceToken);
        if (vault == address(0)) revert VaultNotFound();

        // Check if vault is active
        IVaultManager.VaultInfo memory info = IVaultManager(vaultManager).getVaultInfo(vault);
        if (!info.isActive) revert VaultNotActive();

        return vault;
    }

    // ========================================================================
    // UUPS UPGRADE
    // ========================================================================

    /**
     * @notice Authorize upgrade (UUPS pattern)
     * @param newImplementation New implementation address
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyDefaultAdmin { }

    // ========================================================================
    // VERSION
    // ========================================================================

    /**
     * @notice Get contract version
     * @return Contract version string
     */
    function version() external pure returns (string memory) {
        return "1.0.0";
    }
}
