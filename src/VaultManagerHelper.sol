// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./interfaces/IAssetVault.sol";
import "./interfaces/IVaultManager.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title VaultManagerHelper
 * @notice Helper contract for VaultManager view and admin functions
 * @dev Extracted from VaultManager to reduce contract size below 24KB limit
 *
 * Purpose: Separate read-only and admin forwarding logic from core VaultManager
 * This pattern allows VaultManager to stay under EIP-170 contract size limit
 */
contract VaultManagerHelper {
    // ========================================================================
    // STATE VARIABLES (Reference to main VaultManager)
    // ========================================================================

    /// @notice Main VaultManager contract
    address public immutable vaultManager;

    // ========================================================================
    // ERRORS
    // ========================================================================

    error InvalidAddress();
    error VaultNotFound();
    error NotAuthorized();

    // ========================================================================
    // CONSTRUCTOR
    // ========================================================================

    /**
     * @notice Constructor
     * @param _vaultManager Address of main VaultManager contract
     */
    constructor(address _vaultManager) {
        if (_vaultManager == address(0)) revert InvalidAddress();
        vaultManager = _vaultManager;
    }

    // ========================================================================
    // MODIFIERS
    // ========================================================================

    modifier onlyOwner() {
        address owner = Ownable(vaultManager).owner();
        if (msg.sender != owner) revert NotAuthorized();
        _;
    }

    // ========================================================================
    // INTERNAL HELPERS
    // ========================================================================

    /**
     * @notice Get vault address from VaultManager
     */
    function _getVault(address tokenAddress) internal view returns (address) {
        return IVaultManager(vaultManager).getVault(tokenAddress);
    }

    /**
     * @notice Get all vaults from VaultManager
     */
    function _getAllVaults() internal view returns (address[] memory) {
        return IVaultManager(vaultManager).getAllVaults();
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /**
     * @notice Get vault info for a token
     */
    function getVaultInfo(address tokenAddress)
        external
        view
        returns (IAssetVault.VaultInfo memory)
    {
        address vaultAddress = _getVault(tokenAddress);
        if (vaultAddress == address(0)) revert VaultNotFound();

        return IAssetVault(vaultAddress).getVaultInfo();
    }

    /**
     * @notice Get vault parameters for a token
     */
    function getVaultParams(address tokenAddress)
        external
        view
        returns (IAssetVault.VaultParams memory)
    {
        address vaultAddress = _getVault(tokenAddress);
        if (vaultAddress == address(0)) revert VaultNotFound();

        return IAssetVault(vaultAddress).getVaultParams();
    }

    /**
     * @notice Get LP position for a user in a specific vault
     */
    function getLPPosition(address tokenAddress, address user)
        external
        view
        returns (IAssetVault.LPPosition memory)
    {
        address vaultAddress = _getVault(tokenAddress);
        if (vaultAddress == address(0)) revert VaultNotFound();

        return IAssetVault(vaultAddress).getLPPosition(user);
    }

    /**
     * @notice Get total liquidity across all vaults (in native token equivalent)
     */
    function getTotalLiquidity() external view returns (uint256 total) {
        address[] memory vaults = _getAllVaults();

        for (uint256 i = 0; i < vaults.length; i++) {
            IAssetVault.VaultInfo memory info = IAssetVault(vaults[i]).getVaultInfo();
            total += info.totalLiquidity;
        }
        return total;
    }

    /**
     * @notice Get total USD value across all vaults
     * @return totalUSD Total value in USD (18 decimals)
     */
    function getTotalValueUSD() external view returns (uint256 totalUSD) {
        address[] memory vaults = _getAllVaults();

        for (uint256 i = 0; i < vaults.length; i++) {
            totalUSD += IAssetVault(vaults[i]).getVaultValueUSD();
        }
        return totalUSD;
    }

    // ========================================================================
    // ADMIN FORWARDING FUNCTIONS
    // ========================================================================

    /**
     * @notice Update PositionManager contract for a specific vault
     */
    function updateVaultPositionManager(address tokenAddress, address _positionManager)
        external
        onlyOwner
    {
        address vaultAddress = _getVault(tokenAddress);
        if (vaultAddress == address(0)) revert VaultNotFound();

        IAssetVault(vaultAddress).setPositionManager(_positionManager);
    }

    /**
     * @notice Pause a specific vault
     */
    function pauseVault(address tokenAddress) external onlyOwner {
        address vaultAddress = _getVault(tokenAddress);
        if (vaultAddress == address(0)) revert VaultNotFound();

        IAssetVault(vaultAddress).pause();
    }

    /**
     * @notice Unpause a specific vault
     */
    function unpauseVault(address tokenAddress) external onlyOwner {
        address vaultAddress = _getVault(tokenAddress);
        if (vaultAddress == address(0)) revert VaultNotFound();

        IAssetVault(vaultAddress).unpause();
    }

    /**
     * @notice Set Blocksense Oracle for a vault
     * @param tokenAddress Token address
     * @param blocksenseOracle BlocksenseOracle contract address
     */
    function setVaultBlocksenseOracle(address tokenAddress, address blocksenseOracle)
        external
        onlyOwner
    {
        address vaultAddress = _getVault(tokenAddress);
        if (vaultAddress == address(0)) revert VaultNotFound();

        IAssetVault(vaultAddress).setBlocksenseOracle(blocksenseOracle);
    }

    /**
     * @notice Set graduation threshold for a vault
     * @param tokenAddress Token address
     * @param threshold New threshold in token amount (same decimals as token)
     */
    function setVaultGraduationThreshold(address tokenAddress, uint256 threshold)
        external
        onlyOwner
    {
        address vaultAddress = _getVault(tokenAddress);
        if (vaultAddress == address(0)) revert VaultNotFound();

        IAssetVault(vaultAddress).setGraduationThreshold(threshold);
    }

    /**
     * @notice Pause VaultManager factory
     */
    function pauseFactory() external onlyOwner {
        IVaultManager(vaultManager).pause();
    }

    /**
     * @notice Unpause VaultManager factory
     */
    function unpauseFactory() external onlyOwner {
        IVaultManager(vaultManager).unpause();
    }
}
