// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IVaultRegistry
 * @notice Interface for the VaultRegistry contract
 */
interface IVaultRegistry {
    // ========================================================================
    // STRUCTS
    // ========================================================================

    struct VaultConfig {
        address vaultAddress;
        address projectToken;
        string routerVersion;
        string coreVersion;
        string fundingVersion;
        string rewardsVersion;
        uint256 deployedAt;
        uint256 lastUpdatedAt;
        bool isActive;
    }

    struct ModuleUpdate {
        bytes32 moduleType;
        string fromVersion;
        string toVersion;
        uint256 timestamp;
        address updatedBy;
    }

    // ========================================================================
    // REGISTRATION FUNCTIONS
    // ========================================================================

    function registerVault(
        address vault,
        address projectToken,
        string calldata routerVersion,
        string calldata coreVersion,
        string calldata fundingVersion,
        string calldata rewardsVersion
    ) external;

    function updateVaultModule(address vault, bytes32 moduleType, string calldata newVersion)
        external;

    function batchUpdateVaultModules(
        address vault,
        string calldata routerVersion,
        string calldata coreVersion,
        string calldata fundingVersion,
        string calldata rewardsVersion
    ) external;

    function deactivateVault(address vault) external;

    function reactivateVault(address vault) external;

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    function getVaultConfig(address vault) external view returns (VaultConfig memory);

    function getAllVaults() external view returns (address[] memory);

    function getVaultCount() external view returns (uint256);

    function getActiveVaults() external view returns (address[] memory);

    function getVaultsByModuleVersion(bytes32 moduleType, string calldata version)
        external
        view
        returns (address[] memory);

    function getUpdateHistory(address vault) external view returns (ModuleUpdate[] memory);

    function getUpdateCount(address vault) external view returns (uint256);

    function getVaultsNeedingUpgrade() external view returns (address[] memory);

    function getVaultFullInfo(address vault)
        external
        view
        returns (
            VaultConfig memory config,
            address routerImpl,
            address coreImpl,
            address fundingImpl,
            address rewardsImpl
        );

    function vaultExists(address vault) external view returns (bool);

    function vaultByProjectToken(address projectToken) external view returns (address);
}

