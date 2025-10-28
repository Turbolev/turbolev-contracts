// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/ICLFeedRegistryAdapter.sol";

/**
 * @title BlocksenseOracle
 * @notice Oracle integration contract for Blocksense price feeds
 * @dev Wraps Blocksense CL Feed Registry Adapter for price data retrieval
 *
 * Reference: https://docs.blocksense.network/docs/contracts/integration-guide/using-data-feeds/cl-feed-registry-adapter
 *
 * Key Features:
 * - Get real-time prices from Blocksense Network via base/quote pairs
 * - Validate price updates and freshness
 * - Circuit breaker for price manipulation protection
 * - Simple interface: just pass base and quote addresses directly
 */
contract BlocksenseOracle is OwnableUpgradeable, PausableUpgradeable, UUPSUpgradeable {
    // ========================================================================
    // STATE VARIABLES
    // ========================================================================

    /// @notice Blocksense CL Feed Registry Adapter contract
    ICLFeedRegistryAdapter public registry;

    /// @notice Maximum price age (seconds)
    uint256 public maxPriceAge;

    /// @notice Last validated prices for circuit breaker
    struct LastPrice {
        int256 price;
        uint256 timestamp;
    }

    mapping(address => mapping(address => LastPrice)) public lastValidPrices;

    // ========================================================================
    // PRICE VALIDATION
    // ========================================================================

    /// @notice Maximum price change percentage in bps (1000 = 10%)
    uint256 public maxPriceChangeBps;

    /// @notice Minimum time between price updates (seconds) for circuit breaker
    uint256 public minPriceUpdateInterval;

    // ========================================================================
    // EVENTS
    // ========================================================================

    event BlocksenseOracleInitialized(address indexed registryContract, uint256 maxPriceAge);

    event RegistryContractUpdated(address indexed oldContract, address indexed newContract);

    event MaxPriceAgeUpdated(uint256 oldAge, uint256 newAge);

    event PriceValidationConfigUpdated(uint256 maxPriceChangeBps, uint256 minPriceUpdateInterval);

    event CircuitBreakerTriggered(
        address indexed base,
        address indexed quote,
        int256 oldPrice,
        int256 newPrice,
        uint256 changePercent
    );

    // ========================================================================
    // ERRORS
    // ========================================================================

    error InvalidAddress();
    error InvalidPriceAge();
    error PriceStale();
    error InvalidPrice();
    error PriceChangeTooLarge();
    error InvalidValidationConfig();

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
     * @param _registry Blocksense CL Feed Registry Adapter address
     * @param _maxPriceAge Maximum price age in seconds
     */
    function initialize(address initialOwner, address _registry, uint256 _maxPriceAge)
        public
        initializer
    {
        if (initialOwner == address(0) || _registry == address(0)) {
            revert InvalidAddress();
        }
        if (_maxPriceAge == 0) revert InvalidPriceAge();

        __Ownable_init(initialOwner);
        __Pausable_init();
        __UUPSUpgradeable_init();

        registry = ICLFeedRegistryAdapter(_registry);
        maxPriceAge = _maxPriceAge;

        maxPriceChangeBps = 1000;
        minPriceUpdateInterval = 1;

        emit BlocksenseOracleInitialized(_registry, _maxPriceAge);
    }

    // ========================================================================
    // PRICE FUNCTIONS
    // ========================================================================

    /**
     * @notice Get price with validation
     * @param base Base asset address (e.g., WETH)
     * @param quote Quote asset address (e.g., USDC)
     * @return price Price in int256 format (scaled to 18 decimals)
     * @return updatedAt When price was last updated
     */
    function getPrice(address base, address quote)
        external
        view
        whenNotPaused
        returns (int256 price, uint256 updatedAt)
    {
        if (base == address(0) || quote == address(0)) revert InvalidAddress();

        (, int256 answer,, uint256 timestamp,) = registry.latestRoundData(base, quote);

        if (block.timestamp - timestamp > maxPriceAge) revert PriceStale();
        if (answer <= 0) revert InvalidPrice();

        uint8 feedDecimals = registry.decimals(base, quote);
        int256 scaledPrice = _scalePrice(answer, feedDecimals);

        return (scaledPrice, timestamp);
    }

    /**
     * @notice Get price unsafe (no staleness check)
     * @param base Base asset address
     * @param quote Quote asset address
     * @return price Price in int256 format (scaled to 18 decimals)
     * @return updatedAt When price was last updated
     */
    function getPriceUnsafe(address base, address quote)
        external
        view
        whenNotPaused
        returns (int256 price, uint256 updatedAt)
    {
        if (base == address(0) || quote == address(0)) revert InvalidAddress();

        (, int256 answer,, uint256 timestamp,) = registry.latestRoundData(base, quote);

        if (answer <= 0) revert InvalidPrice();

        uint8 feedDecimals = registry.decimals(base, quote);
        int256 scaledPrice = _scalePrice(answer, feedDecimals);

        return (scaledPrice, timestamp);
    }

    /**
     * @notice Get price no older than specified age with validation
     * @param base Base asset address
     * @param quote Quote asset address
     * @param maxAge Maximum acceptable age in seconds
     * @return price Price in int256 format (scaled to 18 decimals)
     * @return updatedAt When price was last updated
     * @dev Includes circuit breaker validation
     */
    function getPriceNoOlderThan(address base, address quote, uint256 maxAge)
        external
        whenNotPaused
        returns (int256 price, uint256 updatedAt)
    {
        if (base == address(0) || quote == address(0)) revert InvalidAddress();

        (, int256 answer,, uint256 timestamp,) = registry.latestRoundData(base, quote);

        if (block.timestamp - timestamp > maxAge) revert PriceStale();
        if (answer <= 0) revert InvalidPrice();

        uint8 feedDecimals = registry.decimals(base, quote);
        int256 scaledPrice = _scalePrice(answer, feedDecimals);

        _validatePrice(base, quote, scaledPrice, timestamp);

        return (scaledPrice, timestamp);
    }

    // ========================================================================
    // INTERNAL FUNCTIONS
    // ========================================================================

    /**
     * @notice Scale price to 18 decimals
     * @param price Raw price from feed
     * @param decimals Feed decimals
     * @return scaledPrice Scaled price
     */
    function _scalePrice(int256 price, uint8 decimals) internal pure returns (int256 scaledPrice) {
        if (decimals == 18) {
            return price;
        } else if (decimals < 18) {
            return price * int256(10 ** (18 - decimals));
        } else {
            return price / int256(10 ** (decimals - 18));
        }
    }

    /**
     * @notice Validate price with circuit breaker
     * @param base Base asset address
     * @param quote Quote asset address
     * @param price Scaled price
     * @param timestamp Update timestamp
     */
    function _validatePrice(address base, address quote, int256 price, uint256 timestamp)
        internal
    {
        LastPrice memory lastPrice = lastValidPrices[base][quote];

        if (lastPrice.timestamp == 0 || maxPriceChangeBps == 0) {
            _updateLastValidPrice(base, quote, price, timestamp);
            return;
        }

        if (block.timestamp < lastPrice.timestamp + minPriceUpdateInterval) {
            _updateLastValidPrice(base, quote, price, timestamp);
            return;
        }

        if (lastPrice.price <= 0) {
            _updateLastValidPrice(base, quote, price, timestamp);
            return;
        }

        uint256 priceChange = price > lastPrice.price
            ? uint256(price - lastPrice.price)
            : uint256(lastPrice.price - price);

        uint256 BASIS_POINTS = 10_000;
        uint256 changePercent = (priceChange * BASIS_POINTS) / uint256(lastPrice.price);

        if (changePercent > maxPriceChangeBps) {
            emit CircuitBreakerTriggered(base, quote, lastPrice.price, price, changePercent);
            revert PriceChangeTooLarge();
        }

        _updateLastValidPrice(base, quote, price, timestamp);
    }

    /**
     * @notice Update last valid price for circuit breaker
     * @param base Base asset address
     * @param quote Quote asset address
     * @param price Validated price
     * @param timestamp Price timestamp
     */
    function _updateLastValidPrice(address base, address quote, int256 price, uint256 timestamp)
        internal
    {
        lastValidPrices[base][quote] = LastPrice({ price: price, timestamp: timestamp });
    }

    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================

    /**
     * @notice Update registry contract address
     * @param _registry New registry contract address
     */
    function setRegistryContract(address _registry) external onlyOwner {
        if (_registry == address(0)) revert InvalidAddress();
        address oldContract = address(registry);
        registry = ICLFeedRegistryAdapter(_registry);
        emit RegistryContractUpdated(oldContract, _registry);
    }

    /**
     * @notice Update maximum price age
     * @param _maxPriceAge New maximum price age in seconds
     */
    function setMaxPriceAge(uint256 _maxPriceAge) external onlyOwner {
        if (_maxPriceAge == 0) revert InvalidPriceAge();
        uint256 oldAge = maxPriceAge;
        maxPriceAge = _maxPriceAge;
        emit MaxPriceAgeUpdated(oldAge, _maxPriceAge);
    }

    /**
     * @notice Update price validation configuration
     * @param _maxPriceChangeBps Maximum price change in bps
     * @param _minPriceUpdateInterval Minimum time between price updates
     */
    function setPriceValidationConfig(uint256 _maxPriceChangeBps, uint256 _minPriceUpdateInterval)
        external
        onlyOwner
    {
        if (_maxPriceChangeBps > 5000) revert InvalidValidationConfig();

        maxPriceChangeBps = _maxPriceChangeBps;
        minPriceUpdateInterval = _minPriceUpdateInterval;

        emit PriceValidationConfigUpdated(_maxPriceChangeBps, _minPriceUpdateInterval);
    }

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
        return "1.0.0-blocksense";
    }
}
