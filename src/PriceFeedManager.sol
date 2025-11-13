// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/IPriceFeedManager.sol";
import "./interfaces/oracles/IPushOracle.sol";
import "./interfaces/oracles/IPullOracle.sol";
import "./interfaces/oracles/IHybridOracle.sol";

/**
 * @title PriceFeedManager V2 with Oracle Registry Pattern
 * @notice Enhanced contract managing price feeds with centralized oracle provider registry
 * @dev Upgradeable contract using UUPS pattern
 *
 * KEY IMPROVEMENTS V2:
 * - Oracle Provider Registry: Reusable, centralized management of oracle providers
 * - Reference-based Config: Tokens reference providers by ID instead of duplicating data
 * - Support for Push, Pull, and Hybrid oracles
 * - Primary and secondary provider configuration (customizable order)
 * - Automatic price updates for pull oracles when stale
 * - Unified interface for all oracle types
 *
 * BENEFITS:
 * - Gas savings: Providers stored once, tokens only store references
 * - Easy updates: Update oracle address once → affects all tokens using it
 * - Organized: Clear separation between provider management and token config
 * - Reusable: Multiple tokens can share same provider configuration
 */
contract PriceFeedManager is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    IPriceFeedManager
{
    // ========================================================================
    // STATE VARIABLES
    // ========================================================================

    /// @notice Registry of oracle providers (providerId => OracleProvider)
    mapping(bytes32 => OracleProvider) public oracleProviders;

    /// @notice Mapping project token address -> PriceFeedConfig (with provider IDs)
    mapping(address => PriceFeedConfig) private priceFeedConfigs;

    /// @notice List of all registered provider IDs (for enumeration)
    bytes32[] private providerIdsList;

    /// @notice Mapping to check if provider ID is registered
    mapping(bytes32 => bool) private providerRegistered;

    // ========================================================================
    // PREDEFINED PROVIDER IDs (for common use)
    // ========================================================================

    bytes32 public constant CHAINLINK_PROVIDER = keccak256("CHAINLINK");
    bytes32 public constant BLOCKSENSE_PROVIDER = keccak256("BLOCKSENSE");
    bytes32 public constant PYTH_PROVIDER = keccak256("PYTH");

    // ========================================================================
    // STORAGE GAP (for future upgrades)
    // ========================================================================

    /// @dev Storage gap to allow for new variables in future versions
    uint256[46] private __gap;

    // ========================================================================
    // EVENTS
    // ========================================================================

    event OracleProviderRegistered(
        bytes32 indexed providerId,
        address indexed oracleContract,
        IBaseOracle.OracleType oracleType
    );
    event OracleProviderUpdated(bytes32 indexed providerId, address indexed oracleContract);
    event OracleProviderRemoved(bytes32 indexed providerId);

    event PriceFeedConfigUpdated(
        address indexed projectToken,
        bytes32 indexed primaryProviderId,
        bytes32 indexed secondaryProviderId
    );
    event PrimaryProviderSet(address indexed projectToken, bytes32 indexed providerId);
    event SecondaryProviderSet(address indexed projectToken, bytes32 indexed providerId);
    event UsePullModeUpdated(address indexed projectToken, bool usePullMode);

    event PriceFallbackUsed(
        address indexed projectToken,
        bytes32 indexed primaryProviderId,
        bytes32 indexed secondaryProviderId,
        string reason
    );

    event PriceUpdateTriggered(
        address indexed projectToken, bytes32 indexed providerId, uint256 updateFee
    );

    // ========================================================================
    // ERRORS
    // ========================================================================

    error InvalidAddress();
    error InvalidConfig();
    error InvalidOraclePrice();
    error NoPrimaryProvider();
    error PullOracleUpdateFailed();
    error InsufficientUpdateFee();
    error ProviderNotFound(bytes32 providerId);
    error ProviderAlreadyExists(bytes32 providerId);
    error ProviderInUse(bytes32 providerId);
    error ArrayLengthMismatch();

    // ========================================================================
    // CONSTRUCTOR / INITIALIZER
    // ========================================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize contract
     * @param initialOwner Owner address
     */
    function initialize(address initialOwner) public initializer {
        if (initialOwner == address(0)) revert InvalidAddress();

        __Ownable_init(initialOwner);
        __Pausable_init();
        __UUPSUpgradeable_init();
    }

    // ========================================================================
    // ORACLE PROVIDER REGISTRY FUNCTIONS
    // ========================================================================

    /**
     * @notice Register a new oracle provider
     * @param providerId Unique identifier for the provider
     * @param provider Oracle provider configuration
     */
    function registerOracleProvider(bytes32 providerId, OracleProvider calldata provider)
        external
        override
        onlyOwner
        whenNotPaused
    {
        if (providerId == bytes32(0)) revert InvalidConfig();
        if (providerRegistered[providerId]) {
            revert ProviderAlreadyExists(providerId);
        }
        if (provider.oracleContract == address(0)) revert InvalidAddress();

        oracleProviders[providerId] = provider;
        providerRegistered[providerId] = true;
        providerIdsList.push(providerId);

        emit OracleProviderRegistered(providerId, provider.oracleContract, provider.oracleType);
    }

    /**
     * @notice Register multiple oracle providers at once
     * @param providerIds Array of provider IDs
     * @param providers Array of provider configurations
     */
    function registerOracleProviders(
        bytes32[] calldata providerIds,
        OracleProvider[] calldata providers
    ) external override onlyOwner whenNotPaused {
        if (providerIds.length != providers.length) {
            revert ArrayLengthMismatch();
        }

        for (uint256 i = 0; i < providerIds.length; i++) {
            bytes32 providerId = providerIds[i];
            OracleProvider calldata provider = providers[i];

            if (providerId == bytes32(0)) revert InvalidConfig();
            if (providerRegistered[providerId]) {
                revert ProviderAlreadyExists(providerId);
            }
            if (provider.oracleContract == address(0)) revert InvalidAddress();

            oracleProviders[providerId] = provider;
            providerRegistered[providerId] = true;
            providerIdsList.push(providerId);

            emit OracleProviderRegistered(providerId, provider.oracleContract, provider.oracleType);
        }
    }

    /**
     * @notice Update an existing oracle provider
     * @param providerId Provider ID to update
     * @param provider New provider configuration
     */
    function updateOracleProvider(bytes32 providerId, OracleProvider calldata provider)
        external
        override
        onlyOwner
        whenNotPaused
    {
        if (!providerRegistered[providerId]) {
            revert ProviderNotFound(providerId);
        }
        if (provider.oracleContract == address(0)) revert InvalidAddress();

        oracleProviders[providerId] = provider;

        emit OracleProviderUpdated(providerId, provider.oracleContract);
    }

    /**
     * @notice Remove an oracle provider
     * @param providerId Provider ID to remove
     * @dev Will fail if any token is currently using this provider
     */
    function removeOracleProvider(bytes32 providerId) external override onlyOwner whenNotPaused {
        if (!providerRegistered[providerId]) {
            revert ProviderNotFound(providerId);
        }

        // Note: In production, you might want to check if any token is using this provider
        // For simplicity, we allow removal here

        delete oracleProviders[providerId];
        providerRegistered[providerId] = false;

        emit OracleProviderRemoved(providerId);
    }

    /**
     * @notice Get oracle provider by ID
     * @param providerId Provider ID
     * @return provider Oracle provider configuration
     */
    function getOracleProvider(bytes32 providerId)
        external
        view
        override
        returns (OracleProvider memory provider)
    {
        if (!providerRegistered[providerId]) {
            revert ProviderNotFound(providerId);
        }
        return oracleProviders[providerId];
    }

    /**
     * @notice Check if provider exists
     * @param providerId Provider ID
     * @return exists True if provider is registered
     */
    function providerExists(bytes32 providerId) external view override returns (bool) {
        return providerRegistered[providerId];
    }

    /**
     * @notice Get list of all registered provider IDs
     * @return providerIds Array of provider IDs
     */
    function getAllProviderIds() external view override returns (bytes32[] memory) {
        return providerIdsList;
    }

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
        override
        returns (PriceFeedConfig memory config)
    {
        return priceFeedConfigs[projectToken];
    }

    /**
     * @notice Set price feed configuration for a project token
     * @param projectToken Project token address
     * @param config Complete price feed configuration
     */
    function setPriceFeedConfig(address projectToken, PriceFeedConfig calldata config)
        external
        override
        onlyOwner
        whenNotPaused
    {
        if (projectToken == address(0)) revert InvalidAddress();
        if (config.primaryProviderId == bytes32(0)) revert NoPrimaryProvider();
        if (!providerRegistered[config.primaryProviderId]) {
            revert ProviderNotFound(config.primaryProviderId);
        }
        if (
            config.secondaryProviderId != bytes32(0)
                && !providerRegistered[config.secondaryProviderId]
        ) {
            revert ProviderNotFound(config.secondaryProviderId);
        }

        priceFeedConfigs[projectToken] = config;

        emit PriceFeedConfigUpdated(
            projectToken, config.primaryProviderId, config.secondaryProviderId
        );
    }

    /**
     * @notice Set primary provider for a project token
     * @param projectToken Project token address
     * @param providerId Primary provider ID
     */
    function setPrimaryProvider(address projectToken, bytes32 providerId)
        external
        override
        onlyOwner
        whenNotPaused
    {
        if (projectToken == address(0)) revert InvalidAddress();
        if (providerId == bytes32(0)) revert NoPrimaryProvider();
        if (!providerRegistered[providerId]) {
            revert ProviderNotFound(providerId);
        }

        priceFeedConfigs[projectToken].primaryProviderId = providerId;

        emit PrimaryProviderSet(projectToken, providerId);
        emit PriceFeedConfigUpdated(
            projectToken, providerId, priceFeedConfigs[projectToken].secondaryProviderId
        );
    }

    /**
     * @notice Set secondary provider for a project token
     * @param projectToken Project token address
     * @param providerId Secondary provider ID (can be bytes32(0) to disable)
     */
    function setSecondaryProvider(address projectToken, bytes32 providerId)
        external
        override
        onlyOwner
        whenNotPaused
    {
        if (projectToken == address(0)) revert InvalidAddress();
        if (providerId != bytes32(0) && !providerRegistered[providerId]) {
            revert ProviderNotFound(providerId);
        }

        priceFeedConfigs[projectToken].secondaryProviderId = providerId;

        emit SecondaryProviderSet(projectToken, providerId);
        emit PriceFeedConfigUpdated(
            projectToken, priceFeedConfigs[projectToken].primaryProviderId, providerId
        );
    }

    /**
     * @notice Enable/disable pull mode for a project token
     * @param projectToken Project token address
     * @param usePullMode Whether to use pull mode
     */
    function setUsePullMode(address projectToken, bool usePullMode)
        external
        override
        onlyOwner
        whenNotPaused
    {
        if (projectToken == address(0)) revert InvalidAddress();

        priceFeedConfigs[projectToken].usePullMode = usePullMode;

        emit UsePullModeUpdated(projectToken, usePullMode);
    }

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
        override
        returns (
            OracleProvider memory primaryProvider,
            OracleProvider memory secondaryProvider,
            bool usePullMode
        )
    {
        PriceFeedConfig memory config = priceFeedConfigs[projectToken];

        if (config.primaryProviderId != bytes32(0) && providerRegistered[config.primaryProviderId])
        {
            primaryProvider = oracleProviders[config.primaryProviderId];
        }

        if (
            config.secondaryProviderId != bytes32(0)
                && providerRegistered[config.secondaryProviderId]
        ) {
            secondaryProvider = oracleProviders[config.secondaryProviderId];
        }

        usePullMode = config.usePullMode;
    }

    // ========================================================================
    // PRICE QUERY FUNCTIONS
    // ========================================================================

    /**
     * @notice Get price for project token with custom max age (view function)
     * @param projectToken Project token address
     * @param maxAge Maximum acceptable price age in seconds
     * @return price Settlement price (scaled to 18 decimals)
     * @return publishTime When price was last updated
     * @dev Tries primary provider first, falls back to secondary if needed
     * @dev This is VIEW only - cannot update pull oracles
     */
    function getPrice(address projectToken, uint256 maxAge)
        external
        view
        override
        whenNotPaused
        returns (uint256 price, uint256 publishTime)
    {
        PriceFeedConfig memory config = priceFeedConfigs[projectToken];

        // Try primary provider
        if (config.primaryProviderId != bytes32(0)) {
            OracleProvider memory primary = oracleProviders[config.primaryProviderId];
            (bool success, uint256 primaryPrice, uint256 primaryTime) =
                _tryGetPriceFromProvider(primary, config.primaryFeed, maxAge);

            if (success) {
                return (primaryPrice, primaryTime);
            }
        }

        // Try secondary provider
        if (config.secondaryProviderId != bytes32(0)) {
            OracleProvider memory secondary = oracleProviders[config.secondaryProviderId];
            (bool success, uint256 secondaryPrice, uint256 secondaryTime) =
                _tryGetPriceFromProvider(secondary, config.secondaryFeed, maxAge);

            if (success) {
                return (secondaryPrice, secondaryTime);
            }
        }

        // Both failed
        revert InvalidOraclePrice();
    }

    /**
     * @notice Get price with fallback and emit event (non-view version)
     * @param projectToken Project token address
     * @param maxAge Maximum acceptable price age in seconds
     * @return price Settlement price
     * @return publishTime When price was last updated
     */
    function getPriceWithFallback(address projectToken, uint256 maxAge)
        external
        override
        whenNotPaused
        returns (uint256 price, uint256 publishTime)
    {
        PriceFeedConfig memory config = priceFeedConfigs[projectToken];

        // Try primary provider
        if (config.primaryProviderId != bytes32(0)) {
            OracleProvider memory primary = oracleProviders[config.primaryProviderId];
            (bool success, uint256 primaryPrice, uint256 primaryTime) =
            _tryGetPriceFromProviderWithUpdate(
                primary,
                config.primaryFeed,
                config.primaryProviderId,
                config.usePullMode,
                maxAge,
                "" // No update data in this version
            );

            if (success) {
                return (primaryPrice, primaryTime);
            }
        }

        // Try secondary provider
        if (config.secondaryProviderId != bytes32(0)) {
            OracleProvider memory secondary = oracleProviders[config.secondaryProviderId];
            (bool success, uint256 secondaryPrice, uint256 secondaryTime) =
            _tryGetPriceFromProviderWithUpdate(
                secondary,
                config.secondaryFeed,
                config.secondaryProviderId,
                config.usePullMode,
                maxAge,
                "" // No update data
            );

            if (success) {
                emit PriceFallbackUsed(
                    projectToken,
                    config.primaryProviderId,
                    config.secondaryProviderId,
                    "Primary provider failed, using secondary"
                );
                return (secondaryPrice, secondaryTime);
            }
        }

        // Both failed
        revert InvalidOraclePrice();
    }

    /**
     * @notice Get price with auto-update for pull oracles (non-view)
     * @param projectToken Project token address
     * @param maxAge Maximum acceptable price age in seconds
     * @param updateData Encoded update data for pull oracles
     * @return price Settlement price
     * @return publishTime When price was last updated
     * @dev For pull oracles: checks staleness and updates before reading if necessary
     */
    function getPriceWithUpdate(address projectToken, uint256 maxAge, bytes calldata updateData)
        external
        payable
        override
        whenNotPaused
        returns (uint256 price, uint256 publishTime)
    {
        PriceFeedConfig storage config = priceFeedConfigs[projectToken];

        // Try primary provider with update if needed
        if (config.primaryProviderId != bytes32(0)) {
            OracleProvider memory primary = oracleProviders[config.primaryProviderId];
            (bool success, uint256 primaryPrice, uint256 primaryTime) =
            _tryGetPriceFromProviderWithUpdate(
                primary,
                config.primaryFeed,
                config.primaryProviderId,
                config.usePullMode,
                maxAge,
                updateData
            );

            if (success) {
                return (primaryPrice, primaryTime);
            }
        }

        // Try secondary provider with update if needed
        if (config.secondaryProviderId != bytes32(0)) {
            OracleProvider memory secondary = oracleProviders[config.secondaryProviderId];
            (bool success, uint256 secondaryPrice, uint256 secondaryTime) =
            _tryGetPriceFromProviderWithUpdate(
                secondary,
                config.secondaryFeed,
                config.secondaryProviderId,
                config.usePullMode,
                maxAge,
                updateData
            );

            if (success) {
                emit PriceFallbackUsed(
                    projectToken,
                    config.primaryProviderId,
                    config.secondaryProviderId,
                    "Primary provider failed, using secondary"
                );
                return (secondaryPrice, secondaryTime);
            }
        }

        // Both failed
        revert InvalidOraclePrice();
    }

    /**
     * @notice Check if price is stale for a project token
     * @param projectToken Project token address
     * @param maxAge Maximum acceptable age in seconds
     * @return isStale True if primary provider's price is stale
     */
    function isPriceStale(address projectToken, uint256 maxAge)
        external
        view
        override
        returns (bool)
    {
        PriceFeedConfig memory config = priceFeedConfigs[projectToken];

        if (config.primaryProviderId == bytes32(0)) {
            return true;
        }

        OracleProvider memory provider = oracleProviders[config.primaryProviderId];

        if (
            !provider.enabled || provider.oracleContract == address(0)
                || config.primaryFeed == address(0)
        ) {
            return true;
        }

        // Check based on oracle type
        if (provider.oracleType == IBaseOracle.OracleType.PUSH) {
            try IPushOracle(provider.oracleContract).isPriceStale(config.primaryFeed, maxAge)
            returns (bool stale) {
                return stale;
            } catch {
                return true;
            }
        } else {
            // PULL oracle
            try IPullOracle(provider.oracleContract).isPriceStale(config.primaryFeed, maxAge)
            returns (bool stale) {
                return stale;
            } catch {
                return true;
            }
        }
    }

    // ========================================================================
    // INTERNAL FUNCTIONS
    // ========================================================================

    /**
     * @notice Try to get price from a provider (view version - no updates)
     * @param provider Oracle provider config
     * @param maxAge Maximum acceptable price age
     * @return success Whether price was retrieved successfully
     * @return price Price (scaled to 18 decimals)
     * @return updatedAt Update timestamp
     */
    function _tryGetPriceFromProvider(OracleProvider memory provider, address feed, uint256 maxAge)
        internal
        view
        returns (bool success, uint256 price, uint256 updatedAt)
    {
        // Check if provider is configured and enabled
        if (!provider.enabled || provider.oracleContract == address(0) || feed == address(0)) {
            return (false, 0, 0);
        }

        // Get price based on oracle type
        if (provider.oracleType == IBaseOracle.OracleType.PUSH) {
            return _tryGetPushPrice(provider.oracleContract, feed, maxAge);
        } else {
            // PULL oracle - just read current price (may be stale)
            return _tryGetPullPrice(provider.oracleContract, feed, maxAge);
        }
    }

    /**
     * @notice Try to get price from provider with update support (non-view)
     * @param provider Oracle provider config
     * @param feed Feed address for this provider
     * @param providerId Provider ID (for events)
     * @param usePullMode Whether to use pull mode (auto-update if stale)
     * @param maxAge Maximum acceptable price age
     * @param updateData Update data for pull oracles
     * @return success Whether price was retrieved successfully
     * @return price Price (scaled to 18 decimals)
     * @return updatedAt Update timestamp
     */
    function _tryGetPriceFromProviderWithUpdate(
        OracleProvider memory provider,
        address feed,
        bytes32 providerId,
        bool usePullMode,
        uint256 maxAge,
        bytes memory updateData
    ) internal returns (bool success, uint256 price, uint256 updatedAt) {
        // Check if provider is configured and enabled
        if (!provider.enabled || provider.oracleContract == address(0) || feed == address(0)) {
            return (false, 0, 0);
        }

        // For PUSH oracles, just read
        if (provider.oracleType == IBaseOracle.OracleType.PUSH) {
            return _tryGetPushPrice(provider.oracleContract, feed, maxAge);
        }

        // For PULL oracles
        if (!usePullMode) {
            // Pull mode disabled - just read (may be stale)
            return _tryGetPullPrice(provider.oracleContract, feed, maxAge);
        }

        // Pull mode enabled - check staleness and update if needed
        IPullOracle pullOracle = IPullOracle(provider.oracleContract);

        // Check if stale
        bool isStale;
        try pullOracle.isPriceStale(feed, maxAge) returns (bool _isStale) {
            isStale = _isStale;
        } catch {
            return (false, 0, 0);
        }
        // Update if stale
        if (isStale && updateData.length > 0) {
            try pullOracle.getPriceWithUpdate{ value: msg.value }(feed, maxAge, updateData)
            returns (int256 _price, uint256 _updatedAt) {
                if (_price <= 0) {
                    return (false, 0, 0);
                }

                emit PriceUpdateTriggered(feed, providerId, msg.value);

                return (true, uint256(_price), _updatedAt);
            } catch {
                return (false, 0, 0);
            }
        }

        // Not stale or no update data - just read
        return _tryGetPullPrice(provider.oracleContract, feed, maxAge);
    }

    /**
     * @notice Try to get price from push oracle
     * @param oracleContract Oracle contract address
     * @param feed Feed address
     * @param maxAge Maximum acceptable age
     * @return success Whether successful
     * @return price Price (scaled to 18 decimals)
     * @return updatedAt Update timestamp
     */
    function _tryGetPushPrice(address oracleContract, address feed, uint256 maxAge)
        internal
        view
        returns (bool success, uint256 price, uint256 updatedAt)
    {
        try IPushOracle(oracleContract).getPriceNoOlderThan(feed, maxAge) returns (
            int256 _price, uint256 _updatedAt
        ) {
            if (_price <= 0) {
                return (false, 0, 0);
            }
            return (true, uint256(_price), _updatedAt);
        } catch {
            return (false, 0, 0);
        }
    }

    /**
     * @notice Try to get price from pull oracle (read only - no update)
     * @param oracleContract Oracle contract address
     * @param feed Feed address
     * @param maxAge Maximum acceptable age
     * @return success Whether successful
     * @return price Price (scaled to 18 decimals)
     * @return updatedAt Update timestamp
     */
    function _tryGetPullPrice(address oracleContract, address feed, uint256 maxAge)
        internal
        view
        returns (bool success, uint256 price, uint256 updatedAt)
    {
        try IPullOracle(oracleContract).getPrice(feed) returns (int256 _price, uint256 _updatedAt) {
            if (_price <= 0) {
                return (false, 0, 0);
            }

            // Check staleness
            if (block.timestamp - _updatedAt > maxAge) {
                return (false, 0, 0);
            }

            return (true, uint256(_price), _updatedAt);
        } catch {
            return (false, 0, 0);
        }
    }

    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================

    /**
     * @notice Pause contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Authorize upgrade (UUPS pattern)
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

    /**
     * @notice Get contract version
     */
    function version() external pure returns (string memory) {
        return "2.1.0-oracle-registry";
    }

    /**
     * @notice Receive function to accept ETH for pull oracle updates
     */
    receive() external payable { }
}
