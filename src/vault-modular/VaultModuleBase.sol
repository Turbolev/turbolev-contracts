// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../libraries/vault/VaultStorageLib.sol";
import "./VaultAccessController.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title VaultModuleBase
 * @notice Abstract base contract for all vault modules
 * @dev Provides:
 *      - Storage accessors via VaultStorageLib
 *      - Access control modifiers via VaultAccessController
 *      - Reentrancy guard using shared storage
 *      - Pausable functionality using shared storage
 *      - Common utility functions
 *
 * All modules (VaultCore, VaultFunding, VaultRewards) inherit from this contract.
 * Modules are called via delegatecall from VaultRouter, so they share storage.
 */
abstract contract VaultModuleBase {
    using SafeERC20 for IERC20;

    // ========================================================================
    // ERRORS
    // ========================================================================

    error NotVaultAdmin();
    error NotPositionManager();
    error NotEmergency();
    error NotVaultManagerOrHelper();
    error InvalidAddress();
    error VaultPaused();
    error VaultNotPaused();
    error ReentrancyGuardReentrantCall();
    error TradingNotEnabled();
    error VaultNotGraduated();

    // ========================================================================
    // MODIFIERS - ACCESS CONTROL
    // ========================================================================

    /**
     * @notice Only vault admin (VaultManager or VAULT_ADMIN_ROLE)
     */
    modifier onlyVaultAdmin() {
        VaultStorageLib.CoreStorage storage core = VaultStorageLib.getCoreStorage();
        if (core.accessController == address(0)) revert InvalidAddress();

        VaultAccessController ac = VaultAccessController(core.accessController);
        if (!ac.isVaultAdmin(address(this), msg.sender)) {
            revert NotVaultAdmin();
        }
        _;
    }

    /**
     * @notice Only VaultManager or VAULT_ADMIN_ROLE
     * @dev Used for admin functions that need direct access control
     */
    modifier onlyVaultManagerOrHelper() {
        VaultStorageLib.CoreStorage storage core = VaultStorageLib.getCoreStorage();
        if (msg.sender != core.vaultManager) {
            VaultAccessController ac = VaultAccessController(core.accessController);
            if (!ac.hasRole(ac.VAULT_ADMIN_ROLE(), msg.sender)) {
                revert NotVaultManagerOrHelper();
            }
        }
        _;
    }

    /**
     * @notice Only PositionManager
     */
    modifier onlyPositionManager() {
        VaultStorageLib.CoreStorage storage core = VaultStorageLib.getCoreStorage();
        if (msg.sender != core.positionManager) {
            revert NotPositionManager();
        }
        _;
    }

    /**
     * @notice Only emergency role (multisig)
     */
    modifier onlyEmergency() {
        VaultStorageLib.CoreStorage storage core = VaultStorageLib.getCoreStorage();
        if (core.accessController == address(0)) revert InvalidAddress();

        VaultAccessController ac = VaultAccessController(core.accessController);
        if (!ac.hasEmergencyRole(msg.sender)) {
            revert NotEmergency();
        }
        _;
    }

    // ========================================================================
    // MODIFIERS - REENTRANCY GUARD (Shared Storage)
    // ========================================================================

    /**
     * @notice Reentrancy guard using shared storage
     * @dev Must use shared storage since modules are called via delegatecall
     */
    modifier nonReentrant() {
        VaultStorageLib.CoreStorage storage core = VaultStorageLib.getCoreStorage();

        if (core.reentrancyStatus == VaultStorageLib.ENTERED) {
            revert ReentrancyGuardReentrantCall();
        }

        core.reentrancyStatus = VaultStorageLib.ENTERED;
        _;
        core.reentrancyStatus = VaultStorageLib.NOT_ENTERED;
    }

    // ========================================================================
    // MODIFIERS - PAUSABLE (Shared Storage)
    // ========================================================================

    /**
     * @notice Require vault not paused
     */
    modifier whenNotPaused() {
        VaultStorageLib.CoreStorage storage core = VaultStorageLib.getCoreStorage();
        if (core.paused) {
            revert VaultPaused();
        }
        _;
    }

    /**
     * @notice Require vault paused
     */
    modifier whenPaused() {
        VaultStorageLib.CoreStorage storage core = VaultStorageLib.getCoreStorage();
        if (!core.paused) {
            revert VaultNotPaused();
        }
        _;
    }

    /**
     * @notice Require vault not paused (alias for compatibility)
     */
    modifier whenVaultNotPaused() {
        VaultStorageLib.CoreStorage storage core = VaultStorageLib.getCoreStorage();
        if (core.paused) {
            revert VaultPaused();
        }
        _;
    }

    // ========================================================================
    // MODIFIERS - TRADING STATUS
    // ========================================================================

    /**
     * @notice Require trading enabled
     */
    modifier whenTradingEnabled() {
        VaultStorageLib.CoreStorage storage core = VaultStorageLib.getCoreStorage();
        if (!core.vaultInfo.tradingEnabled) {
            revert TradingNotEnabled();
        }
        _;
    }

    /**
     * @notice Require vault graduated
     */
    modifier whenGraduated() {
        VaultStorageLib.CoreStorage storage core = VaultStorageLib.getCoreStorage();
        if (!core.vaultInfo.isGraduated) {
            revert VaultNotGraduated();
        }
        _;
    }

    // ========================================================================
    // STORAGE SHORTCUTS
    // ========================================================================

    /**
     * @notice Get core storage
     */
    function _core() internal pure returns (VaultStorageLib.CoreStorage storage) {
        return VaultStorageLib.getCoreStorage();
    }

    /**
     * @notice Get funding storage
     */
    function _funding() internal pure returns (VaultStorageLib.FundingStorage storage) {
        return VaultStorageLib.getFundingStorage();
    }

    /**
     * @notice Get rewards storage
     */
    function _rewards() internal pure returns (VaultStorageLib.RewardsStorage storage) {
        return VaultStorageLib.getRewardsStorage();
    }

    /**
     * @notice Get risk storage
     */
    function _risk() internal pure returns (VaultStorageLib.RiskStorage storage) {
        return VaultStorageLib.getRiskStorage();
    }

    /**
     * @notice Get router storage
     */
    function _router() internal pure returns (VaultStorageLib.RouterStorage storage) {
        return VaultStorageLib.getRouterStorage();
    }

    // ========================================================================
    // UTILITY FUNCTIONS
    // ========================================================================

    /**
     * @notice Get project token address
     */
    function _projectToken() internal view returns (address) {
        return VaultStorageLib.getCoreStorage().projectToken;
    }

    /**
     * @notice Get total liquidity
     */
    function _totalLiquidity() internal view returns (uint256) {
        return VaultStorageLib.getCoreStorage().vaultInfo.totalLiquidity;
    }

    /**
     * @notice Get total shares
     */
    function _totalShares() internal view returns (uint256) {
        return VaultStorageLib.getCoreStorage().vaultInfo.totalShares;
    }

    /**
     * @notice Check if vault is paused
     */
    function _isPaused() internal view returns (bool) {
        return VaultStorageLib.getCoreStorage().paused;
    }

    /**
     * @notice Check if trading is enabled
     */
    function _isTradingEnabled() internal view returns (bool) {
        return VaultStorageLib.getCoreStorage().vaultInfo.tradingEnabled;
    }

    /**
     * @notice Check if vault is graduated
     */
    function _isGraduated() internal view returns (bool) {
        return VaultStorageLib.getCoreStorage().vaultInfo.isGraduated;
    }

    // ========================================================================
    // PAUSABLE FUNCTIONS
    // ========================================================================

    /**
     * @notice Pause the vault
     * @dev Internal function, to be exposed by modules with proper access control
     */
    function _pause() internal {
        VaultStorageLib.CoreStorage storage core = VaultStorageLib.getCoreStorage();
        core.paused = true;
    }

    /**
     * @notice Unpause the vault
     * @dev Internal function, to be exposed by modules with proper access control
     */
    function _unpause() internal {
        VaultStorageLib.CoreStorage storage core = VaultStorageLib.getCoreStorage();
        core.paused = false;
    }

    // ========================================================================
    // SAFE TRANSFER HELPERS
    // ========================================================================

    /**
     * @notice Safe transfer project token
     * @param to Recipient address
     * @param amount Amount to transfer
     */
    function _safeTransferProjectToken(address to, uint256 amount) internal {
        if (amount == 0) return;
        address token = _projectToken();
        if (token == address(0)) revert InvalidAddress();
        IERC20(token).safeTransfer(to, amount);
    }

    /**
     * @notice Safe transfer project token from
     * @param from Sender address
     * @param to Recipient address
     * @param amount Amount to transfer
     */
    function _safeTransferFromProjectToken(address from, address to, uint256 amount) internal {
        if (amount == 0) return;
        address token = _projectToken();
        if (token == address(0)) revert InvalidAddress();
        IERC20(token).safeTransferFrom(from, to, amount);
    }
}

