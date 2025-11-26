// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title VaultBeacon
 * @notice Beacon contract để quản lý implementation của AssetVault proxies với opt-in upgrade support
 * @dev Cho phép upgrade toàn bộ vaults hoặc chỉ vaults đã opt-in
 *
 * Chức năng:
 * - Lưu trữ implementation address hiện tại
 * - Cho phép upgrade implementation (chỉ owner - thường là Timelock)
 * - Tích hợp với OptInUpgradeManager để kiểm soát opt-in upgrades
 * - Hỗ trợ cả global upgrade và per-vault implementation
 */
contract VaultBeacon is UpgradeableBeacon {
    // ========================================================================
    // STATE VARIABLES
    // ========================================================================

    /// @notice OptInUpgradeManager contract
    address public optInUpgradeManager;

    /// @notice Custom implementation cho specific vaults (override global)
    /// @dev vault address => custom implementation
    mapping(address => address) public vaultImplementations;

    /// @notice Flag to enable/disable opt-in check (for emergency upgrades)
    bool public enforceOptIn;

    // ========================================================================
    // EVENTS
    // ========================================================================

    event BeaconUpgraded(address indexed oldImplementation, address indexed newImplementation);

    event VaultImplementationSet(address indexed vault, address indexed implementation);

    event OptInUpgradeManagerUpdated(address indexed oldManager, address indexed newManager);

    event OptInEnforcementUpdated(bool enforced);

    // ========================================================================
    // ERRORS
    // ========================================================================

    error VaultNotOptedIn();
    error InvalidAddress();

    // ========================================================================
    // CONSTRUCTOR
    // ========================================================================

    /**
     * @notice Constructor
     * @param initialImplementation Initial implementation address
     * @param initialOwner Owner address (thường là Timelock)
     * @param _optInUpgradeManager OptInUpgradeManager address
     */
    constructor(address initialImplementation, address initialOwner, address _optInUpgradeManager)
        UpgradeableBeacon(initialImplementation, initialOwner)
    {
        optInUpgradeManager = _optInUpgradeManager;
        enforceOptIn = true; // Default: enforce opt-in
    }

    // ========================================================================
    // UPGRADE FUNCTIONS
    // ========================================================================

    /**
     * @notice Upgrade global implementation
     * @param newImplementation New implementation address
     * @dev Chỉ vaults đã opt-in (hoặc emergency override) mới dùng implementation mới
     */
    function upgradeTo(address newImplementation) public virtual override onlyOwner {
        address oldImplementation = implementation();
        super.upgradeTo(newImplementation);
        emit BeaconUpgraded(oldImplementation, newImplementation);
    }

    /**
     * @notice Set custom implementation cho một vault cụ thể
     * @param vault Vault address
     * @param implementation_ Custom implementation address
     * @dev Vault phải opt-in để set custom implementation
     */
    function setVaultImplementation(address vault, address implementation_) external onlyOwner {
        if (vault == address(0) || implementation_ == address(0)) {
            revert InvalidAddress();
        }

        // Check opt-in if enforcement is enabled
        if (enforceOptIn && optInUpgradeManager != address(0)) {
            (bool success, bytes memory data) = optInUpgradeManager.staticcall(
                abi.encodeWithSignature("canVaultUpgrade(address)", vault)
            );
            require(success, "Failed to check opt-in");

            bool canUpgrade = abi.decode(data, (bool));
            if (!canUpgrade) revert VaultNotOptedIn();
        }

        vaultImplementations[vault] = implementation_;
        emit VaultImplementationSet(vault, implementation_);
    }

    /**
     * @notice Clear custom implementation cho vault (revert to global)
     * @param vault Vault address
     */
    function clearVaultImplementation(address vault) external onlyOwner {
        delete vaultImplementations[vault];
        emit VaultImplementationSet(vault, address(0));
    }

    /**
     * @notice Get implementation cho một vault cụ thể
     * @param vault Vault address
     * @return implementation_ Implementation address
     * @dev Trả về custom implementation nếu có, otherwise trả về global implementation
     *      CHỈ trả về nếu vault đã opt-in (hoặc opt-in enforcement disabled)
     */
    function implementation(address vault) public view returns (address implementation_) {
        // Check opt-in if enforcement is enabled
        if (enforceOptIn && optInUpgradeManager != address(0)) {
            (bool success, bytes memory data) = optInUpgradeManager.staticcall(
                abi.encodeWithSignature("canVaultUpgrade(address)", vault)
            );

            // If check successful and vault can upgrade, return new implementation
            if (success) {
                bool canUpgrade = abi.decode(data, (bool));
                if (!canUpgrade) {
                    // Vault not opted in - return their current implementation
                    // This prevents automatic upgrade
                    return address(0); // Signal that vault should not upgrade
                }
            }
        }

        // Check for custom implementation first
        address customImpl = vaultImplementations[vault];
        if (customImpl != address(0)) {
            return customImpl;
        }

        // Return global implementation
        return implementation();
    }

    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================

    /**
     * @notice Update OptInUpgradeManager
     * @param _optInUpgradeManager New manager address
     */
    function setOptInUpgradeManager(address _optInUpgradeManager) external onlyOwner {
        address oldManager = optInUpgradeManager;
        optInUpgradeManager = _optInUpgradeManager;

        emit OptInUpgradeManagerUpdated(oldManager, _optInUpgradeManager);
    }

    /**
     * @notice Enable/disable opt-in enforcement
     * @param _enforceOptIn True to enforce opt-in
     * @dev Use false for emergency upgrades
     */
    function setOptInEnforcement(bool _enforceOptIn) external onlyOwner {
        enforceOptIn = _enforceOptIn;
        emit OptInEnforcementUpdated(_enforceOptIn);
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /**
     * @notice Check if vault has custom implementation
     * @param vault Vault address
     * @return hasCustom True if has custom implementation
     */
    function hasCustomImplementation(address vault) external view returns (bool) {
        return vaultImplementations[vault] != address(0);
    }
}
