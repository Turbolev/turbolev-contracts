// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./interfaces/IAssetVault.sol";
import "./interfaces/IVaultManager.sol";
import "./BlocksenseOracle.sol";
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
    // VIEW FUNCTIONS
    // ========================================================================

    /**
     * @notice Get vault address for a project token
     * @param _projectToken Project token address
     * @return Vault address
     */
    function getVault(address _projectToken) public view returns (address) {
        return IVaultManager(vaultManager).getVault(_projectToken);
    }

    /**
     * @notice Get all vault addresses
     * @return Array of vault addresses
     */
    function getAllVaults() public view returns (address[] memory) {
        return IVaultManager(vaultManager).getAllVaults();
    }

    /**
     * @notice Get vault info for a token
     */
    function getVaultInfo(address tokenAddress)
        public
        view
        returns (IAssetVault.VaultInfo memory)
    {
        address vaultAddress = IVaultManager(vaultManager).getVault(tokenAddress);
        if (vaultAddress == address(0)) revert VaultNotFound();

        return IAssetVault(vaultAddress).getVaultInfo();
    }

    /**
     * @notice Get vault parameters for a token
     */
    function getVaultParams(address tokenAddress)
        public
        view
        returns (IAssetVault.VaultParams memory)
    {
        address vaultAddress = IVaultManager(vaultManager).getVault(tokenAddress);
        if (vaultAddress == address(0)) revert VaultNotFound();

        return IAssetVault(vaultAddress).getVaultParams();
    }

    /**
     * @notice Check if vault is supported for a project token
     * @param _projectToken Project token address
     * @return supported Whether vault is supported
     */
    function isVaultSupported(address _projectToken) external view returns (bool supported) {
        return IVaultManager(vaultManager).getVault(_projectToken) != address(0);
    }

    /**
     * @notice Get LP position for a user in a specific vault
     */
    function getLPPosition(address tokenAddress, address user)
        external
        view
        returns (IAssetVault.LPPosition memory)
    {
        address vaultAddress = IVaultManager(vaultManager).getVault(tokenAddress);
        if (vaultAddress == address(0)) revert VaultNotFound();

        return IAssetVault(vaultAddress).getLPPosition(user);
    }

    /**
     * @notice Get total liquidity across all vaults (in native token equivalent)
     */
    function getTotalLiquidity() external view returns (uint256 total) {
        address[] memory vaults = IVaultManager(vaultManager).getAllVaults();

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
        address[] memory vaults = IVaultManager(vaultManager).getAllVaults();

        for (uint256 i = 0; i < vaults.length; i++) {
            IAssetVault.VaultInfo memory info = IAssetVault(vaults[i]).getVaultInfo();

            // Get price from vault's oracle
            address adapter = IAssetVault(vaults[i]).oracleAdapter();
            address payable oracle = payable(IAssetVault(vaults[i]).blocksenseOracle());

            if (oracle == address(0) || adapter == address(0)) {
                continue;
            }

            try BlocksenseOracle(oracle).getPriceUnsafe(adapter) returns (int256 price, uint256) {
                if (price > 0) {
                    // Calculate value: totalLiquidity * price / 1e18
                    totalUSD += (info.totalLiquidity * uint256(price)) / 1e18;
                }
            } catch {
                // Skip vault if price unavailable
                continue;
            }
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
    // VAULT ADMIN PROXY FUNCTIONS
    // ========================================================================
    /**
     * @notice Pause a specific vault
     * @param tokenAddress Token address
     * @dev Only callable by owner, forwards call to vault
     */
    function pauseVault(address tokenAddress) external onlyOwner {
        address vaultAddress = IVaultManager(vaultManager).getVault(tokenAddress);
        if (vaultAddress == address(0)) revert VaultNotFound();

        IAssetVault(vaultAddress).pause();
    }

    /**
     * @notice Unpause a specific vault
     * @param tokenAddress Token address
     * @dev Only callable by owner, forwards call to vault
     */
    function unpauseVault(address tokenAddress) external onlyOwner {
        address vaultAddress = IVaultManager(vaultManager).getVault(tokenAddress);
        if (vaultAddress == address(0)) revert VaultNotFound();

        IAssetVault(vaultAddress).unpause();
    }

    /**
     * @notice Add an admin to a vault
     * @param tokenAddress Token address
     * @param admin Admin address to add
     */
    function addVaultAdmin(address tokenAddress, address admin) external onlyOwner {
        address vaultAddress = IVaultManager(vaultManager).getVault(tokenAddress);
        if (vaultAddress == address(0)) revert VaultNotFound();
        if (admin == address(0)) revert InvalidAddress();
        IAssetVault(vaultAddress).addAdmin(admin);
    }

    /**
     * @notice Remove an admin from a vault
     * @param tokenAddress Token address
     * @param admin Admin address to remove
     */
    function removeVaultAdmin(address tokenAddress, address admin) external onlyOwner {
        address vaultAddress = IVaultManager(vaultManager).getVault(tokenAddress);
        if (vaultAddress == address(0)) revert VaultNotFound();
        if (admin == address(0)) revert InvalidAddress();
        IAssetVault(vaultAddress).removeAdmin(admin);
    }

    /**
     * @notice Update vault parameters
     * @param tokenAddress Token address
     * @param minBetAmount Min bet amount
     * @param maxBetAmount Max bet amount
     * @param maxPositionSizePercentBps Max position size percent in basis points
     */
    function updateVaultParams(
        address tokenAddress,
        uint256 minBetAmount,
        uint256 maxBetAmount,
        uint16 maxPositionSizePercentBps
    ) external onlyOwner {
        address vaultAddress = IVaultManager(vaultManager).getVault(tokenAddress);
        if (vaultAddress == address(0)) revert VaultNotFound();

        IAssetVault(vaultAddress).updateVaultParams(
            minBetAmount, maxBetAmount, maxPositionSizePercentBps
        );
    }

    /**
     * @notice Set staking fee BPS for a vault
     * @param tokenAddress Token address
     * @param stakingFeeBps Staking fee BPS
     */
    function setVaultStakingFeeBps(address tokenAddress, uint16 stakingFeeBps) external onlyOwner {
        address vaultAddress = IVaultManager(vaultManager).getVault(tokenAddress);
        if (vaultAddress == address(0)) revert VaultNotFound();
        IAssetVault(vaultAddress).setStakingFeeBps(stakingFeeBps);
    }

    /**
     * @notice Set early withdrawal fee BPS for a vault
     * @param tokenAddress Token address
     * @param earlyWithdrawalFeeBps Early withdrawal fee BPS
     */
    function setVaultEarlyWithdrawalFeeBps(address tokenAddress, uint16 earlyWithdrawalFeeBps)
        external
        onlyOwner
    {
        address vaultAddress = IVaultManager(vaultManager).getVault(tokenAddress);
        if (vaultAddress == address(0)) revert VaultNotFound();
        IAssetVault(vaultAddress).setEarlyWithdrawalFeeBps(earlyWithdrawalFeeBps);
    }

    /**
     * @notice Set graduation threshold for a vault
     * @param tokenAddress Token address
     * @param graduationThreshold Graduation threshold
     */
    function setVaultGraduationThreshold(address tokenAddress, uint256 graduationThreshold)
        external
        onlyOwner
    {
        address vaultAddress = IVaultManager(vaultManager).getVault(tokenAddress);
        if (vaultAddress == address(0)) revert VaultNotFound();
        IAssetVault(vaultAddress).setGraduationThreshold(graduationThreshold);
    }

    /**
     * @notice Set trading enabled for a vault
     * @param tokenAddress Token address
     * @param tradingEnabled Trading enabled
     */
    function setVaultTradingEnabled(address tokenAddress, bool tradingEnabled) external onlyOwner {
        address vaultAddress = IVaultManager(vaultManager).getVault(tokenAddress);
        if (vaultAddress == address(0)) revert VaultNotFound();
        IAssetVault(vaultAddress).setTradingEnabled(tradingEnabled);
    }

    /**
     * @notice Set oracle adapter for a vault
     * @param tokenAddress Token address
     * @param oracleAdapter Oracle adapter address
     */
    function setVaultOracleAdapter(address tokenAddress, address oracleAdapter)
        external
        onlyOwner
    {
        address vaultAddress = IVaultManager(vaultManager).getVault(tokenAddress);
        if (vaultAddress == address(0)) revert VaultNotFound();

        IAssetVault(vaultAddress).setOracleAdapter(oracleAdapter);
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
        address vaultAddress = IVaultManager(vaultManager).getVault(tokenAddress);
        if (vaultAddress == address(0)) revert VaultNotFound();

        IAssetVault(vaultAddress).setBlocksenseOracle(blocksenseOracle);
    }

    /**
     * @notice Set Chainlink feed for a vault
     * @param tokenAddress Token address
     * @param chainlinkFeed Chainlink feed address
     */
    function setVaultChainlinkFeed(address tokenAddress, address chainlinkFeed)
        external
        onlyOwner
    {
        address vaultAddress = IVaultManager(vaultManager).getVault(tokenAddress);
        if (vaultAddress == address(0)) revert VaultNotFound();
        IAssetVault(vaultAddress).setChainlinkFeed(chainlinkFeed);
    }
}
