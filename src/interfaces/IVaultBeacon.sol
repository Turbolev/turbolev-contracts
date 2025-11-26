// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IVaultBeacon
 * @notice Interface for VaultBeacon contract
 */
interface IVaultBeacon {
    /**
     * @notice Upgrade beacon to new implementation
     * @param newImplementation New implementation address
     */
    function upgradeTo(address newImplementation) external;

    /**
     * @notice Set custom implementation cho một vault cụ thể
     * @param vault Vault address
     * @param implementation_ Custom implementation address
     */
    function setVaultImplementation(address vault, address implementation_) external;

    /**
     * @notice Clear custom implementation cho vault (revert to global)
     * @param vault Vault address
     */
    function clearVaultImplementation(address vault) external;

    /**
     * @notice Get implementation cho một vault cụ thể
     * @param vault Vault address
     * @return implementation_ Implementation address
     */
    function implementation(address vault) external view returns (address implementation_);

    /**
     * @notice Get global implementation
     * @return implementation Global implementation address
     */
    function implementation() external view returns (address implementation);

    /**
     * @notice Enable/disable opt-in enforcement
     * @param enforce True to enforce opt-in
     */
    function setEnforceOptIn(bool enforce) external;

    /**
     * @notice Set OptInUpgradeManager
     * @param manager OptInUpgradeManager address
     */
    function setOptInUpgradeManager(address manager) external;
}
