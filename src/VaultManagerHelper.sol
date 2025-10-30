// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./interfaces/IAssetVault.sol";
import "./interfaces/IVaultManager.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

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
    error DirectTransferNotAllowed();

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
    // RECEIVE / FALLBACK
    // ========================================================================

    /// @notice Reject direct native token transfers
    receive() external payable {
        revert DirectTransferNotAllowed();
    }

    /// @notice Reject fallback calls
    fallback() external payable {
        revert DirectTransferNotAllowed();
    }

    // ========================================================================
    // MODIFIERS
    // ========================================================================

    modifier onlyOwner() {
        address owner = OwnableUpgradeable(vaultManager).owner();
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

    /**
     * @notice Get balance of native tokens in VaultManager
     * @return balance Native token balance
     */
    function getNativeBalance() external view returns (uint256 balance) {
        return address(this).balance;
    }

    /**
     * @notice Get balance of ERC20 tokens in VaultManager
     * @param token Token address
     * @return balance Token balance
     */
    function getTokenBalance(address token) external view returns (uint256 balance) {
        if (token == address(0)) revert InvalidAddress();
        return IERC20(token).balanceOf(address(this));
    }

    // ========================================================================
    // ADMIN FORWARDING FUNCTIONS (via VaultManager proxy)
    // ========================================================================

    /**
     * @notice Update PositionManager contract for a specific vault
     * @dev Forwards call through VaultManager to avoid ownership issues
     */
    function updateVaultPositionManager(address tokenAddress, address _positionManager)
        external
        onlyOwner
    {
        IVaultManager(vaultManager).updateVaultPositionManager(tokenAddress, _positionManager);
    }

    /**
     * @notice Pause a specific vault
     * @dev Forwards call through VaultManager to avoid ownership issues
     */
    function pauseVault(address tokenAddress) external onlyOwner {
        IVaultManager(vaultManager).pauseVault(tokenAddress);
    }

    /**
     * @notice Unpause a specific vault
     * @dev Forwards call through VaultManager to avoid ownership issues
     */
    function unpauseVault(address tokenAddress) external onlyOwner {
        IVaultManager(vaultManager).unpauseVault(tokenAddress);
    }

    /**
     * @notice Set Blocksense Oracle for a vault
     * @param tokenAddress Token address
     * @param blocksenseOracle BlocksenseOracle contract address
     * @dev Forwards call through VaultManager to avoid ownership issues
     */
    function setVaultBlocksenseOracle(address tokenAddress, address blocksenseOracle)
        external
        onlyOwner
    {
        IVaultManager(vaultManager).setVaultBlocksenseOracle(tokenAddress, blocksenseOracle);
    }

    /**
     * @notice Set graduation threshold for a vault
     * @param tokenAddress Token address
     * @param threshold New threshold in token amount (same decimals as token)
     * @dev Forwards call through VaultManager to avoid ownership issues
     */
    function setVaultGraduationThreshold(address tokenAddress, uint256 threshold)
        external
        onlyOwner
    {
        IVaultManager(vaultManager).setVaultGraduationThreshold(tokenAddress, threshold);
    }
}
