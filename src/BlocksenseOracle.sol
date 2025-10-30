// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/ICLAggregatorAdapter.sol";

/**
 * @title BlocksenseOracle
 * @notice Oracle integration contract for Blocksense price feeds
 * @dev Wraps Blocksense CL Aggregator Adapters for price data retrieval
 *
 * Reference: https://docs.blocksense.network/docs/contracts/integration-guide/using-data-feeds/cl-aggregator-adapter
 *
 * Key Features:
 * - Get real-time prices from Blocksense Network via individual aggregator adapters
 * - Validate price updates and freshness
 * - Circuit breaker for price manipulation protection
 * - Manage multiple feed adapters for different asset pairs
 */
contract BlocksenseOracle is OwnableUpgradeable, PausableUpgradeable, UUPSUpgradeable {
    // ========================================================================
    // STATE VARIABLES
    // ========================================================================

    /// @notice Maximum price age (seconds)
    uint256 public maxPriceAge;

    /// @notice Last validated prices for circuit breaker
    struct LastPrice {
        int256 price;
        uint256 timestamp;
    }

    mapping(address => LastPrice) public lastValidPrices;

    // ========================================================================
    // PRICE VALIDATION
    // ========================================================================

    /// @notice Maximum price change percentage in bps (1000 = 10%)
    uint256 public maxPriceChangeBps;

    /// @notice Minimum time between price updates (seconds) for circuit breaker
    uint256 public minPriceUpdateInterval;

    // ========================================================================
    // STORAGE GAP (for future upgrades)
    // ========================================================================

    /// @dev Storage gap to allow for new variables in future versions
    /// @notice Currently using 4 storage slots, reserving 46 slots for future use
    uint256[46] private __gap;

    // ========================================================================
    // EVENTS
    // ========================================================================

    event BlocksenseOracleInitialized(uint256 maxPriceAge);

    event MaxPriceAgeUpdated(uint256 oldAge, uint256 newAge);

    event PriceValidationConfigUpdated(uint256 maxPriceChangeBps, uint256 minPriceUpdateInterval);

    event CircuitBreakerTriggered(
        address indexed adapter, int256 oldPrice, int256 newPrice, uint256 changePercent
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
    error DirectTransferNotAllowed();

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
     * @param _maxPriceAge Maximum price age in seconds
     */
    function initialize(address initialOwner, uint256 _maxPriceAge) public initializer {
        if (initialOwner == address(0)) {
            revert InvalidAddress();
        }
        if (_maxPriceAge == 0) revert InvalidPriceAge();

        __Ownable_init(initialOwner);
        __Pausable_init();
        __UUPSUpgradeable_init();

        maxPriceAge = _maxPriceAge;

        maxPriceChangeBps = 1000;
        minPriceUpdateInterval = 1;

        emit BlocksenseOracleInitialized(_maxPriceAge);
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
    // PRICE FUNCTIONS
    // ========================================================================

    /**
     * @notice Get price with validation
     * @param adapter CLAggregatorAdapter address for the specific feed
     * @return price Price in int256 format (scaled to 18 decimals)
     * @return updatedAt When price was last updated
     */
    function getPrice(address adapter)
        external
        view
        whenNotPaused
        returns (int256 price, uint256 updatedAt)
    {
        if (adapter == address(0)) revert InvalidAddress();

        ICLAggregatorAdapter feed = ICLAggregatorAdapter(adapter);

        (, int256 answer,, uint256 timestamp,) = feed.latestRoundData();

        if (block.timestamp - timestamp > maxPriceAge) revert PriceStale();
        if (answer <= 0) revert InvalidPrice();

        uint8 feedDecimals = feed.decimals();
        int256 scaledPrice = _scalePrice(answer, feedDecimals);

        return (scaledPrice, timestamp);
    }

    /**
     * @notice Get price unsafe (no staleness check)
     * @param adapter CLAggregatorAdapter address for the specific feed
     * @return price Price in int256 format (scaled to 18 decimals)
     * @return updatedAt When price was last updated
     */
    function getPriceUnsafe(address adapter)
        external
        view
        whenNotPaused
        returns (int256 price, uint256 updatedAt)
    {
        if (adapter == address(0)) revert InvalidAddress();

        ICLAggregatorAdapter feed = ICLAggregatorAdapter(adapter);

        (, int256 answer,, uint256 timestamp,) = feed.latestRoundData();

        if (answer <= 0) revert InvalidPrice();

        uint8 feedDecimals = feed.decimals();
        int256 scaledPrice = _scalePrice(answer, feedDecimals);

        return (scaledPrice, timestamp);
    }

    /**
     * @notice Get price no older than specified age with validation
     * @param adapter CLAggregatorAdapter address for the specific feed
     * @param maxAge Maximum acceptable age in seconds
     * @return price Price in int256 format (scaled to 18 decimals)
     * @return updatedAt When price was last updated
     * @dev Includes circuit breaker validation
     */
    function getPriceNoOlderThan(address adapter, uint256 maxAge)
        external
        whenNotPaused
        returns (int256 price, uint256 updatedAt)
    {
        if (adapter == address(0)) revert InvalidAddress();

        ICLAggregatorAdapter feed = ICLAggregatorAdapter(adapter);

        (, int256 answer,, uint256 timestamp,) = feed.latestRoundData();

        if (block.timestamp - timestamp > maxAge) revert PriceStale();
        if (answer <= 0) revert InvalidPrice();

        uint8 feedDecimals = feed.decimals();
        int256 scaledPrice = _scalePrice(answer, feedDecimals);

        _validatePrice(adapter, scaledPrice, timestamp);

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
     * @param adapter CLAggregatorAdapter address
     * @param price Scaled price
     * @param timestamp Update timestamp
     */
    function _validatePrice(address adapter, int256 price, uint256 timestamp) internal {
        LastPrice memory lastPrice = lastValidPrices[adapter];

        if (lastPrice.timestamp == 0 || maxPriceChangeBps == 0) {
            _updateLastValidPrice(adapter, price, timestamp);
            return;
        }

        if (block.timestamp < lastPrice.timestamp + minPriceUpdateInterval) {
            _updateLastValidPrice(adapter, price, timestamp);
            return;
        }

        if (lastPrice.price <= 0) {
            _updateLastValidPrice(adapter, price, timestamp);
            return;
        }

        uint256 priceChange = price > lastPrice.price
            ? uint256(price - lastPrice.price)
            : uint256(lastPrice.price - price);

        uint256 BASIS_POINTS = 10_000;
        uint256 changePercent = (priceChange * BASIS_POINTS) / uint256(lastPrice.price);

        if (changePercent > maxPriceChangeBps) {
            emit CircuitBreakerTriggered(adapter, lastPrice.price, price, changePercent);
            revert PriceChangeTooLarge();
        }

        _updateLastValidPrice(adapter, price, timestamp);
    }

    /**
     * @notice Update last valid price for circuit breaker
     * @param adapter CLAggregatorAdapter address
     * @param price Validated price
     * @param timestamp Price timestamp
     */
    function _updateLastValidPrice(address adapter, int256 price, uint256 timestamp) internal {
        lastValidPrices[adapter] = LastPrice({ price: price, timestamp: timestamp });
    }

    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================

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
