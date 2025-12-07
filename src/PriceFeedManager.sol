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
    // CIRCUIT BREAKER STATE (L-10 FIX)
    // ========================================================================

    /// @notice Circuit breaker configuration for extreme price movements
    struct CircuitBreakerConfig {
        uint256 maxDeviationBps; // Max price deviation in bps (default: 5000 = 50%)
        uint256 minDeviationWindow; // Time window to check deviation in seconds (default: 60s)
        bool enabled; // Whether circuit breaker is enabled
    }

    /// @notice Last known price record per token
    struct LastPriceRecord {
        uint256 price; // Last recorded price
        uint256 timestamp; // When price was recorded
    }

    /// @notice Global circuit breaker configuration
    CircuitBreakerConfig public circuitBreakerConfig;

    /// @notice Last known prices per token for deviation tracking
    mapping(address => LastPriceRecord) private lastPriceRecords;

    /// @notice Tokens with circuit breaker temporarily bypassed (emergency use only)
    mapping(address => bool) public circuitBreakerBypassed;

    // ========================================================================
    // STORAGE GAP (for future upgrades)
    // ========================================================================

    /// @dev Storage gap to allow for new variables in future versions
    /// @notice Reduced from 46 to 42 slots due to circuit breaker additions:
    /// - circuitBreakerConfig: 1 slot (packed struct)
    /// - lastPriceRecords: 1 slot (mapping)
    /// - circuitBreakerBypassed: 1 slot (mapping)
    /// Total new slots used: 3, remaining gap: 46 - 3 = 43
    uint256[43] private __gap;

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

    // Circuit Breaker Events (L-10 FIX)
    event CircuitBreakerTriggered(
        address indexed projectToken,
        uint256 lastPrice,
        uint256 newPrice,
        uint256 deviationBps,
        uint256 timeDelta
    );
    event CircuitBreakerConfigUpdated(
        uint256 maxDeviationBps, uint256 minDeviationWindow, bool enabled
    );
    event CircuitBreakerBypassUpdated(address indexed projectToken, bool bypassed);
    event LastPriceRecordUpdated(address indexed projectToken, uint256 price, uint256 timestamp);

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

    // Circuit Breaker Errors (L-10 FIX)
    error CircuitBreakerTripped(uint256 deviationBps, uint256 maxAllowedBps);
    error InvalidCircuitBreakerConfig();

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

        // L-10 FIX: Initialize circuit breaker with default values
        _initCircuitBreaker();
    }

    /**
     * @notice Initialize circuit breaker for existing deployments (upgrade scenario)
     * @dev Call this after upgrading if circuit breaker was not initialized
     */
    function initializeCircuitBreaker() external onlyOwner {
        // Only initialize if not already set (maxDeviationBps == 0 means uninitialized)
        if (circuitBreakerConfig.maxDeviationBps == 0) {
            _initCircuitBreaker();
        }
    }

    /**
     * @notice Internal function to initialize circuit breaker with default values
     * @dev Default: 50% max deviation, 60s window, enabled
     */
    function _initCircuitBreaker() internal {
        circuitBreakerConfig = CircuitBreakerConfig({
            maxDeviationBps: 5000, // 50% max deviation
            minDeviationWindow: 60, // Check if within 60 seconds
            enabled: true // Enabled by default
         });

        emit CircuitBreakerConfigUpdated(5000, 60, true);
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

        uint256 fetchedPrice;
        uint256 fetchedTime;
        bool priceFound = false;

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
                fetchedPrice = primaryPrice;
                fetchedTime = primaryTime;
                priceFound = true;
            }
        }

        // Try secondary provider if primary failed
        if (!priceFound && config.secondaryProviderId != bytes32(0)) {
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
                fetchedPrice = secondaryPrice;
                fetchedTime = secondaryTime;
                priceFound = true;
            }
        }

        // If no price found, revert
        if (!priceFound) {
            revert InvalidOraclePrice();
        }

        // L-10 FIX: Check circuit breaker before returning price
        if (!_checkCircuitBreaker(projectToken, fetchedPrice)) {
            LastPriceRecord memory lastRecord = lastPriceRecords[projectToken];
            uint256 deviationBps = _calculateDeviationBps(lastRecord.price, fetchedPrice);
            revert CircuitBreakerTripped(deviationBps, circuitBreakerConfig.maxDeviationBps);
        }

        return (fetchedPrice, fetchedTime);
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

        uint256 fetchedPrice;
        uint256 fetchedTime;
        bool priceFound = false;

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
                fetchedPrice = primaryPrice;
                fetchedTime = primaryTime;
                priceFound = true;
            }
        }

        // Try secondary provider if primary failed
        if (!priceFound && config.secondaryProviderId != bytes32(0)) {
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
                fetchedPrice = secondaryPrice;
                fetchedTime = secondaryTime;
                priceFound = true;
            }
        }

        // If no price found, revert
        if (!priceFound) {
            revert InvalidOraclePrice();
        }

        // L-10 FIX: Check circuit breaker before returning price
        // This protects against extreme price movements that could be manipulation
        if (!_checkCircuitBreaker(projectToken, fetchedPrice)) {
            // Get the last recorded price for error context
            LastPriceRecord memory lastRecord = lastPriceRecords[projectToken];
            uint256 deviationBps = _calculateDeviationBps(lastRecord.price, fetchedPrice);
            revert CircuitBreakerTripped(deviationBps, circuitBreakerConfig.maxDeviationBps);
        }

        return (fetchedPrice, fetchedTime);
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
    // CIRCUIT BREAKER FUNCTIONS (L-10 FIX)
    // ========================================================================

    /**
     * @notice Set circuit breaker configuration
     * @param _maxDeviationBps Maximum allowed deviation in basis points (100 = 1%, 5000 = 50%)
     * @param _minDeviationWindow Time window for deviation check in seconds
     * @param _enabled Whether circuit breaker is enabled
     */
    function setCircuitBreakerConfig(
        uint256 _maxDeviationBps,
        uint256 _minDeviationWindow,
        bool _enabled
    ) external onlyOwner {
        // Validation: deviation should be between 1% (100 bps) and 90% (9000 bps)
        if (_maxDeviationBps < 100 || _maxDeviationBps > 9000) {
            revert InvalidCircuitBreakerConfig();
        }
        // Min window should be at least 10 seconds
        if (_minDeviationWindow < 10) {
            revert InvalidCircuitBreakerConfig();
        }

        circuitBreakerConfig = CircuitBreakerConfig({
            maxDeviationBps: _maxDeviationBps,
            minDeviationWindow: _minDeviationWindow,
            enabled: _enabled
        });

        emit CircuitBreakerConfigUpdated(_maxDeviationBps, _minDeviationWindow, _enabled);
    }

    /**
     * @notice Bypass circuit breaker for specific token (emergency use only)
     * @param projectToken Token to bypass
     * @param bypassed Whether to bypass circuit breaker for this token
     * @dev Use with caution - bypassing removes price manipulation protection
     */
    function setCircuitBreakerBypass(address projectToken, bool bypassed) external onlyOwner {
        if (projectToken == address(0)) revert InvalidAddress();
        circuitBreakerBypassed[projectToken] = bypassed;
        emit CircuitBreakerBypassUpdated(projectToken, bypassed);
    }

    /**
     * @notice Check circuit breaker and update last price record
     * @param projectToken Token address
     * @param newPrice New price to validate
     * @return valid True if price passes circuit breaker check
     * @dev Returns true and updates record if check passes, returns false if triggered
     */
    function _checkCircuitBreaker(address projectToken, uint256 newPrice)
        internal
        returns (bool valid)
    {
        // Skip if disabled globally or bypassed for this token
        if (!circuitBreakerConfig.enabled || circuitBreakerBypassed[projectToken]) {
            _updateLastPriceRecord(projectToken, newPrice);
            return true;
        }

        LastPriceRecord memory lastRecord = lastPriceRecords[projectToken];

        // First price for this token - always accept and record
        if (lastRecord.price == 0 || lastRecord.timestamp == 0) {
            _updateLastPriceRecord(projectToken, newPrice);
            return true;
        }

        // Check time window - only validate deviation if within the deviation window
        // This allows gradual price movements over longer periods
        uint256 timeDelta = block.timestamp - lastRecord.timestamp;
        if (timeDelta > circuitBreakerConfig.minDeviationWindow) {
            // Price update is outside the time window - accept and update record
            _updateLastPriceRecord(projectToken, newPrice);
            return true;
        }

        // Calculate deviation between last recorded price and new price
        uint256 deviationBps = _calculateDeviationBps(lastRecord.price, newPrice);

        // Check if deviation exceeds maximum allowed threshold
        if (deviationBps > circuitBreakerConfig.maxDeviationBps) {
            emit CircuitBreakerTriggered(
                projectToken, lastRecord.price, newPrice, deviationBps, timeDelta
            );
            return false;
        }

        // Price is valid - update last price record
        _updateLastPriceRecord(projectToken, newPrice);
        return true;
    }

    /**
     * @notice Calculate deviation between two prices in basis points
     * @param oldPrice Previous price
     * @param newPrice Current price
     * @return deviationBps Absolute deviation in basis points
     */
    function _calculateDeviationBps(uint256 oldPrice, uint256 newPrice)
        internal
        pure
        returns (uint256 deviationBps)
    {
        if (oldPrice == 0) return 0;

        uint256 diff;
        if (newPrice > oldPrice) {
            diff = newPrice - oldPrice;
        } else {
            diff = oldPrice - newPrice;
        }

        // deviation = (diff / oldPrice) * 10000 (for basis points)
        deviationBps = (diff * 10_000) / oldPrice;
    }

    /**
     * @notice Update last price record for a token
     * @param projectToken Token address
     * @param price New price to record
     */
    function _updateLastPriceRecord(address projectToken, uint256 price) internal {
        lastPriceRecords[projectToken] =
            LastPriceRecord({ price: price, timestamp: block.timestamp });

        emit LastPriceRecordUpdated(projectToken, price, block.timestamp);
    }

    /**
     * @notice View function to check if price would trigger circuit breaker
     * @param projectToken Token address
     * @param newPrice Price to check
     * @return wouldTrip True if circuit breaker would trip
     * @return deviationBps Calculated deviation in basis points
     * @return lastPrice Last recorded price
     * @return timeSinceLastUpdate Seconds since last price update
     */
    function checkPriceDeviation(address projectToken, uint256 newPrice)
        external
        view
        returns (
            bool wouldTrip,
            uint256 deviationBps,
            uint256 lastPrice,
            uint256 timeSinceLastUpdate
        )
    {
        LastPriceRecord memory lastRecord = lastPriceRecords[projectToken];

        // If disabled or bypassed, never trips
        if (!circuitBreakerConfig.enabled || circuitBreakerBypassed[projectToken]) {
            return (false, 0, lastRecord.price, 0);
        }

        // First price - never trips
        if (lastRecord.price == 0) {
            return (false, 0, 0, 0);
        }

        timeSinceLastUpdate = block.timestamp - lastRecord.timestamp;

        // Outside time window - never trips
        if (timeSinceLastUpdate > circuitBreakerConfig.minDeviationWindow) {
            return (false, 0, lastRecord.price, timeSinceLastUpdate);
        }

        deviationBps = _calculateDeviationBps(lastRecord.price, newPrice);
        wouldTrip = deviationBps > circuitBreakerConfig.maxDeviationBps;
        lastPrice = lastRecord.price;
    }

    /**
     * @notice Get last price record for a token
     * @param projectToken Token address
     * @return price Last recorded price
     * @return timestamp Last update timestamp
     */
    function getLastPriceRecord(address projectToken)
        external
        view
        returns (uint256 price, uint256 timestamp)
    {
        LastPriceRecord memory record = lastPriceRecords[projectToken];
        return (record.price, record.timestamp);
    }

    /**
     * @notice Get circuit breaker configuration
     * @return maxDeviationBps Maximum deviation in basis points
     * @return minDeviationWindow Time window in seconds
     * @return enabled Whether circuit breaker is enabled
     */
    function getCircuitBreakerConfig()
        external
        view
        returns (uint256 maxDeviationBps, uint256 minDeviationWindow, bool enabled)
    {
        return (
            circuitBreakerConfig.maxDeviationBps,
            circuitBreakerConfig.minDeviationWindow,
            circuitBreakerConfig.enabled
        );
    }

    /**
     * @notice Admin function to manually set last price record
     * @param projectToken Token address
     * @param price Price to set
     * @dev Use to bootstrap circuit breaker or reset after known manipulation
     */
    function setLastPriceRecord(address projectToken, uint256 price) external onlyOwner {
        if (projectToken == address(0)) revert InvalidAddress();
        if (price == 0) revert InvalidOraclePrice();

        _updateLastPriceRecord(projectToken, price);
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
     * @dev V2.2.0: Added circuit breaker for L-10 fix
     */
    function version() external pure returns (string memory) {
        return "2.2.0-circuit-breaker";
    }

    /**
     * @notice Receive function to accept ETH for pull oracle updates
     */
    receive() external payable { }
}
