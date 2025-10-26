// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IAssetManager
 * @notice Interface for AssetManager contract
 */
interface IAssetManager {
    /**
     * @notice Check if asset is supported
     * @param priceFeedId Pyth price feed ID
     * @return supported Whether asset is supported
     */
    function isAssetSupported(
        bytes32 priceFeedId
    ) external view returns (bool supported);

    /**
     * @notice Check if asset is enabled
     * @param priceFeedId Pyth price feed ID
     * @return enabled Whether asset is enabled
     */
    function isAssetEnabled(
        bytes32 priceFeedId
    ) external view returns (bool enabled);

    /**
     * @notice Get asset info
     * @param priceFeedId Pyth price feed ID
     */
    function getAssetInfo(
        bytes32 priceFeedId
    )
        external
        view
        returns (
            uint64 assetId,
            string memory symbol,
            bytes32 pythPriceFeedId,
            uint256 minPrice,
            uint256 maxPrice,
            bool enabled,
            uint256 addedAt,
            uint256 lastUpdated,
            address addedBy
        );
}
