// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./oracles/IBaseOracle.sol";

/**
 * @title IPriceFeedManager
 * @notice Interface for PriceFeedManager contract V2 with Oracle Registry Pattern
 * @dev Enhanced version with support for:
 * - Oracle Provider Registry (reusable, centralized management)
 * - Multiple oracle types (Push/Pull/Hybrid)
 * - Primary and secondary providers with fallback
 * - Configurable provider priority
 */
interface IPriceFeedManager {
    /**
     * @notice Oracle provider configuration
     */
    struct OracleProvider {
        address oracleContract; // Oracle contract address (BlocksenseOracle, ChainlinkOracle, PythOracle, etc.)
        IBaseOracle.OracleType oracleType; // PUSH or PULL
        bool enabled; // Whether this provider is enabled
    }

    /**
     * @notice Price feed configuration for a project token
     * @param primaryProviderId ID of primary oracle provider
     * @param secondaryProviderId ID of secondary oracle provider (fallback)
     * @param primaryFeed Feed address for primary provider (e.g., Chainlink Aggregator address)
     * @param secondaryFeed Feed address for secondary provider
     * @param usePullMode Whether to use pull mode for oracles that support it
     */
    struct PriceFeedConfig {
        bytes32 primaryProviderId;
        bytes32 secondaryProviderId;
        address primaryFeed; // Feed address for primary provider
        address secondaryFeed; // Feed address for secondary provider
        bool usePullMode; // If true and oracle supports pull, update price before reading if stale
    }

    // ========================================================================
    // ORACLE PROVIDER REGISTRY FUNCTIONS
    // ========================================================================

    /**
     * @notice Register a new oracle provider
     * @param providerId Unique identifier for the provider
     * @param provider Oracle provider configuration
     */
    function registerOracleProvider(bytes32 providerId, OracleProvider calldata provider) external;

    /**
     * @notice Register multiple oracle providers at once
     * @param providerIds Array of provider IDs
     * @param providers Array of provider configurations
     */
    function registerOracleProviders(
        bytes32[] calldata providerIds,
        OracleProvider[] calldata providers
    ) external;

    /**
     * @notice Update an existing oracle provider
     * @param providerId Provider ID to update
     * @param provider New provider configuration
     */
    function updateOracleProvider(bytes32 providerId, OracleProvider calldata provider) external;

    /**
     * @notice Remove an oracle provider
     * @param providerId Provider ID to remove
     * @dev Will fail if any token is currently using this provider
     */
    function removeOracleProvider(bytes32 providerId) external;

    /**
     * @notice Get oracle provider by ID
     * @param providerId Provider ID
     * @return provider Oracle provider configuration
     */
    function getOracleProvider(bytes32 providerId)
        external
        view
        returns (OracleProvider memory provider);

    /**
     * @notice Check if provider exists
     * @param providerId Provider ID
     * @return exists True if provider is registered
     */
    function providerExists(bytes32 providerId) external view returns (bool exists);

    // ========================================================================
    // PRICE FEED CONFIG FUNCTIONS
    // ========================================================================

    /**
     * @notice Get price feed configuration for a project token
     * @param projectToken Project token address
     * @return config Price feed configuration
     */
    function getPriceFeedConfig(address projectToken)
        external
        view
        returns (PriceFeedConfig memory config);

    /**
     * @notice Set price feed configuration for a project token
     * @param projectToken Project token address
     * @param config Complete price feed configuration
     */
    function setPriceFeedConfig(address projectToken, PriceFeedConfig calldata config) external;

    /**
     * @notice Set primary provider for a project token
     * @param projectToken Project token address
     * @param providerId Primary provider ID
     */
    function setPrimaryProvider(address projectToken, bytes32 providerId) external;

    /**
     * @notice Set secondary provider for a project token
     * @param projectToken Project token address
     * @param providerId Secondary provider ID
     */
    function setSecondaryProvider(address projectToken, bytes32 providerId) external;

    /**
     * @notice Enable/disable pull mode for a project token
     * @param projectToken Project token address
     * @param usePullMode Whether to use pull mode
     */
    function setUsePullMode(address projectToken, bool usePullMode) external;

    // ========================================================================
    // PRICE QUERY FUNCTIONS
    // ========================================================================

    /**
     * @notice Get price for project token with custom max age
     * @param projectToken Project token address
     * @param maxAge Maximum acceptable price age in seconds
     * @return price Settlement price (scaled to 18 decimals)
     * @return publishTime When price was last updated
     * @dev Tries primary provider first, falls back to secondary if needed
     * @dev For pull oracles in pull mode: checks staleness and updates if needed
     */
    function getPrice(address projectToken, uint256 maxAge)
        external
        view
        returns (uint256 price, uint256 publishTime);

    /**
     * @notice Get price with fallback and emit event (non-view version)
     * @param projectToken Project token address
     * @param maxAge Maximum acceptable price age in seconds
     * @return price Settlement price (scaled to 18 decimals)
     * @return publishTime When price was last updated
     * @dev Same as getPrice but emits events when fallback is used
     */
    function getPriceWithFallback(address projectToken, uint256 maxAge)
        external
        returns (uint256 price, uint256 publishTime);

    /**
     * @notice Get price with auto-update for pull oracles (non-view)
     * @param projectToken Project token address
     * @param maxAge Maximum acceptable price age in seconds
     * @param updateData Encoded update data for pull oracles (if needed)
     * @return price Settlement price (scaled to 18 decimals)
     * @return publishTime When price was last updated
     * @dev For pull oracles: automatically updates price if stale before reading
     */
    function getPriceWithUpdate(address projectToken, uint256 maxAge, bytes calldata updateData)
        external
        payable
        returns (uint256 price, uint256 publishTime);

    /**
     * @notice Check if price is stale for a project token
     * @param projectToken Project token address
     * @param maxAge Maximum acceptable age in seconds
     * @return isStale True if price is stale for primary provider
     */
    function isPriceStale(address projectToken, uint256 maxAge) external view returns (bool isStale);

    // ========================================================================
    // HELPER FUNCTIONS
    // ========================================================================

    /**
     * @notice Get full provider details for a token (resolves IDs to providers)
     * @param projectToken Project token address
     * @return primaryProvider Primary oracle provider
     * @return secondaryProvider Secondary oracle provider
     * @return usePullMode Whether pull mode is enabled
     */
    function getResolvedConfig(address projectToken)
        external
        view
        returns (
            OracleProvider memory primaryProvider,
            OracleProvider memory secondaryProvider,
            bool usePullMode
        );

    /**
     * @notice Get list of all registered provider IDs
     * @return providerIds Array of provider IDs
     * @dev May return empty slots for removed providers
     */
    function getAllProviderIds() external view returns (bytes32[] memory providerIds);
}
