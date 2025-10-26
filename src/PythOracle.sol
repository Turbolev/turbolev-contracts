// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

/**
 * @title PythOracle
 * @notice Oracle integration contract for Pyth Network price feeds
 * @dev Wraps Pyth Network oracle calls for price data retrieval
 *
 * Reference: https://docs.pyth.network/price-feeds/core/use-real-time-data/pull-integration/evm
 *
 * Key Features:
 * - Get real-time prices from Pyth Network
 * - Validate price updates and freshness
 * - Cache prices for gas optimization
 * - Support for multiple price feeds
 */
contract PythOracle is
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    // ========================================================================
    // STATE VARIABLES
    // ========================================================================

    /// @notice Pyth oracle contract
    IPyth public pyth;

    /// @notice Maximum price age (seconds)
    uint256 public maxPriceAge;

    /// @notice Cached prices
    struct CachedPrice {
        int64 price;
        uint64 conf;
        int32 expo;
        uint256 publishTime;
        uint256 cachedAt;
    }

    mapping(bytes32 => CachedPrice) public cachedPrices;

    /// @notice Price cache duration (seconds)
    uint256 public cacheDuration;

    // ========================================================================
    // CRITICAL FIX: Oracle Price Validation
    // ========================================================================

    /// @notice Maximum confidence interval ratio in bps (500 = 5%)
    uint256 public maxConfidenceRatioBps;

    /// @notice Maximum price change percentage in bps (1000 = 10%)
    uint256 public maxPriceChangeBps;

    /// @notice Minimum time between price updates (seconds) for circuit breaker
    uint256 public minPriceUpdateInterval;

    /// @notice Last validated prices for circuit breaker
    mapping(bytes32 => CachedPrice) public lastValidPrices;

    // ========================================================================
    // EVENTS
    // ========================================================================

    event PythOracleInitialized(
        address indexed pythContract,
        uint256 maxPriceAge
    );

    event PythContractUpdated(
        address indexed oldContract,
        address indexed newContract
    );

    event MaxPriceAgeUpdated(uint256 oldAge, uint256 newAge);

    event CacheDurationUpdated(uint256 oldDuration, uint256 newDuration);

    event PriceCached(
        bytes32 indexed priceFeedId,
        int64 price,
        uint256 publishTime
    );

    event PriceUpdated(
        bytes32 indexed priceFeedId,
        int64 price,
        uint256 publishTime
    );

    event PriceValidationConfigUpdated(
        uint256 maxConfidenceRatioBps,
        uint256 maxPriceChangeBps,
        uint256 minPriceUpdateInterval
    );

    event CircuitBreakerTriggered(
        bytes32 indexed priceFeedId,
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
    error InsufficientUpdateFee();
    error RefundFailed();
    error ConfidenceIntervalTooHigh();
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
     * @param _pyth Pyth oracle contract address
     * @param _maxPriceAge Maximum price age in seconds
     */
    function initialize(
        address initialOwner,
        address _pyth,
        uint256 _maxPriceAge
    ) public initializer {
        if (initialOwner == address(0) || _pyth == address(0))
            revert InvalidAddress();
        if (_maxPriceAge == 0) revert InvalidPriceAge();

        __Ownable_init(initialOwner);
        __Pausable_init();
        __UUPSUpgradeable_init();

        pyth = IPyth(_pyth);
        maxPriceAge = _maxPriceAge;
        cacheDuration = 60; // Default: 1 minute

        // CRITICAL FIX: Initialize validation parameters
        maxConfidenceRatioBps = 500; // 5% max confidence interval
        maxPriceChangeBps = 1000; // 10% max price change
        minPriceUpdateInterval = 1; // 1 second minimum between updates

        emit PythOracleInitialized(_pyth, _maxPriceAge);
    }

    // ========================================================================
    // PRICE FUNCTIONS
    // ========================================================================

    /**
     * @notice Get price with validation
     * @param priceFeedId Pyth price feed ID
     * @return price Price in int256 format (scaled to 18 decimals)
     * @return publishTime When price was published
     */
    function getPrice(
        bytes32 priceFeedId
    ) external view whenNotPaused returns (int256 price, uint256 publishTime) {
        // Try to use cached price first
        CachedPrice memory cached = cachedPrices[priceFeedId];
        if (
            cached.cachedAt > 0 &&
            block.timestamp - cached.cachedAt < cacheDuration
        ) {
            return (_scalePrice(cached.price, cached.expo), cached.publishTime);
        }

        // Get fresh price from Pyth
        PythStructs.Price memory pythPrice = pyth.getPriceUnsafe(priceFeedId);

        // Validate price freshness
        if (block.timestamp - pythPrice.publishTime > maxPriceAge)
            revert PriceStale();

        return (
            _scalePrice(pythPrice.price, pythPrice.expo),
            pythPrice.publishTime
        );
    }

    /**
     * @notice Get price with confidence interval
     * @param priceFeedId Pyth price feed ID
     * @return price Price in int256 format (scaled to 18 decimals)
     * @return conf Confidence interval
     * @return publishTime When price was published
     */
    function getPriceWithConfidence(
        bytes32 priceFeedId
    )
        external
        view
        whenNotPaused
        returns (int256 price, uint256 conf, uint256 publishTime)
    {
        PythStructs.Price memory pythPrice = pyth.getPriceUnsafe(priceFeedId);

        if (block.timestamp - pythPrice.publishTime > maxPriceAge)
            revert PriceStale();

        return (
            _scalePrice(pythPrice.price, pythPrice.expo),
            uint256(uint64(pythPrice.conf)),
            pythPrice.publishTime
        );
    }

    /**
     * @notice Get price unsafe (no staleness check)
     * @param priceFeedId Pyth price feed ID
     * @return price Price in int256 format (scaled to 18 decimals)
     * @return publishTime When price was published
     */
    function getPriceUnsafe(
        bytes32 priceFeedId
    ) external view whenNotPaused returns (int256 price, uint256 publishTime) {
        PythStructs.Price memory pythPrice = pyth.getPriceUnsafe(priceFeedId);
        return (
            _scalePrice(pythPrice.price, pythPrice.expo),
            pythPrice.publishTime
        );
    }

    /**
     * @notice Get price no older than specified age, with automatic price update if needed
     * @param priceFeedId Pyth price feed ID
     * @param maxAge Maximum acceptable age in seconds (e.g., 5 seconds)
     * @param priceUpdate Price update data from Pyth (required if price is stale)
     * @return price Price in int256 format (scaled to 18 decimals)
     * @return publishTime When price was published
     * @dev CRITICAL FIX: Added price validation with confidence check and circuit breaker
     */
    function getPriceNoOlderThan(
        bytes32 priceFeedId,
        uint256 maxAge,
        bytes[] calldata priceUpdate
    )
        external
        payable
        whenNotPaused
        returns (int256 price, uint256 publishTime)
    {
        PythStructs.Price memory pythPrice;

        // Try to get price no older than maxAge
        try pyth.getPriceNoOlderThan(priceFeedId, maxAge) returns (
            PythStructs.Price memory _pythPrice
        ) {
            pythPrice = _pythPrice;
        } catch {
            // Price is stale - need to update
            // Update price feeds first
            uint256 fee = pyth.getUpdateFee(priceUpdate);
            if (msg.value < fee) revert InsufficientUpdateFee();

            pyth.updatePriceFeeds{value: fee}(priceUpdate);

            // Refund excess
            if (msg.value > fee) {
                (bool success, ) = msg.sender.call{value: msg.value - fee}("");
                if (!success) revert RefundFailed();
            }

            // Now get the fresh price
            pythPrice = pyth.getPriceNoOlderThan(priceFeedId, maxAge);
        }

        // CRITICAL FIX: Validate price before returning
        _validatePrice(priceFeedId, pythPrice);

        int256 scaledPrice = _scalePrice(pythPrice.price, pythPrice.expo);

        // Update last valid price for future circuit breaker checks
        lastValidPrices[priceFeedId] = CachedPrice({
            price: pythPrice.price,
            conf: pythPrice.conf,
            expo: pythPrice.expo,
            publishTime: pythPrice.publishTime,
            cachedAt: block.timestamp
        });

        return (scaledPrice, pythPrice.publishTime);
    }

    /**
     * @notice Update price feeds with data from Pyth
     * @param updateData Price update data from Pyth
     */
    function updatePriceFeeds(
        bytes[] calldata updateData
    ) external payable whenNotPaused {
        uint256 fee = pyth.getUpdateFee(updateData);
        if (msg.value < fee) revert InsufficientUpdateFee();

        pyth.updatePriceFeeds{value: fee}(updateData);

        // Refund excess
        if (msg.value > fee) {
            (bool success, ) = msg.sender.call{value: msg.value - fee}("");
            if (!success) revert RefundFailed();
        }
    }

    /**
     * @notice Update price feeds if necessary
     * @param updateData Price update data from Pyth
     * @param priceIds Price feed IDs to update
     * @param minPublishTime Minimum publish time required
     */
    function updatePriceFeedsIfNecessary(
        bytes[] calldata updateData,
        bytes32[] calldata priceIds,
        uint64[] calldata minPublishTime
    ) external payable whenNotPaused {
        uint256 fee = pyth.getUpdateFee(updateData);
        if (msg.value < fee) revert InsufficientUpdateFee();

        pyth.updatePriceFeedsIfNecessary{value: fee}(
            updateData,
            priceIds,
            minPublishTime
        );

        // Refund excess
        if (msg.value > fee) {
            (bool success, ) = msg.sender.call{value: msg.value - fee}("");
            if (!success) revert RefundFailed();
        }
    }

    /**
     * @notice Cache price for gas optimization
     * @param priceFeedId Pyth price feed ID
     */
    function cachePrice(bytes32 priceFeedId) external whenNotPaused {
        PythStructs.Price memory pythPrice = pyth.getPriceUnsafe(priceFeedId);

        if (block.timestamp - pythPrice.publishTime > maxPriceAge)
            revert PriceStale();

        cachedPrices[priceFeedId] = CachedPrice({
            price: pythPrice.price,
            conf: pythPrice.conf,
            expo: pythPrice.expo,
            publishTime: pythPrice.publishTime,
            cachedAt: block.timestamp
        });

        emit PriceCached(priceFeedId, pythPrice.price, pythPrice.publishTime);
    }

    /**
     * @notice Get update fee for price feeds
     * @param updateData Price update data
     * @return fee Fee amount in wei
     */
    function getUpdateFee(
        bytes[] calldata updateData
    ) external view returns (uint256 fee) {
        return pyth.getUpdateFee(updateData);
    }

    /**
     * @notice Parse price feed updates
     * @param updateData Price update data
     * @return priceFeeds Array of price feeds
     */
    function parsePriceFeedUpdates(
        bytes[] calldata updateData,
        bytes32[] calldata priceIds,
        uint64 minPublishTime,
        uint64 maxPublishTime
    ) external payable returns (PythStructs.PriceFeed[] memory priceFeeds) {
        uint256 fee = pyth.getUpdateFee(updateData);
        if (msg.value < fee) revert InsufficientUpdateFee();

        priceFeeds = pyth.parsePriceFeedUpdates{value: fee}(
            updateData,
            priceIds,
            minPublishTime,
            maxPublishTime
        );

        // Refund excess
        if (msg.value > fee) {
            (bool success, ) = msg.sender.call{value: msg.value - fee}("");
            if (!success) revert RefundFailed();
        }

        return priceFeeds;
    }

    // ========================================================================
    // INTERNAL FUNCTIONS
    // ========================================================================

    /**
     * @notice Scale price to standard format (18 decimals)
     * @param price Raw price from Pyth
     * @param expo Price exponent
     * @return scaledPrice Scaled price
     */
    function _scalePrice(
        int64 price,
        int32 expo
    ) internal pure returns (int256 scaledPrice) {
        // Pyth prices come with an exponent (e.g., expo=-8 means price/10^8)
        // We want to convert to 18 decimals
        int256 targetExpo = 18;
        int256 adjustment = targetExpo - int256(int32(expo));

        if (adjustment > 0) {
            // Need to multiply
            return int256(price) * int256(10 ** uint256(adjustment));
        } else if (adjustment < 0) {
            // Need to divide
            return int256(price) / int256(10 ** uint256(-adjustment));
        } else {
            return int256(price);
        }
    }

    /**
     * @notice Validate price against confidence interval and circuit breaker
     * @param priceFeedId Price feed ID
     * @param pythPrice Pyth price data
     * @dev CRITICAL FIX: Prevents oracle manipulation and flash crashes
     */
    function _validatePrice(
        bytes32 priceFeedId,
        PythStructs.Price memory pythPrice
    ) internal {
        // 1. Validate confidence interval
        // Confidence should be small relative to price
        if (pythPrice.price != 0 && maxConfidenceRatioBps > 0) {
            uint256 priceAbs = pythPrice.price > 0
                ? uint256(uint64(pythPrice.price))
                : uint256(uint64(-pythPrice.price));
            uint256 confidenceRatio = (uint256(uint64(pythPrice.conf)) *
                10000) / priceAbs;

            if (confidenceRatio > maxConfidenceRatioBps) {
                revert ConfidenceIntervalTooHigh();
            }
        }

        // 2. Circuit breaker: Check price deviation from last valid price
        CachedPrice memory lastPrice = lastValidPrices[priceFeedId];

        if (lastPrice.cachedAt > 0 && maxPriceChangeBps > 0) {
            // Check if enough time has passed (avoid false positives on legitimate volatility)
            if (
                block.timestamp >= lastPrice.cachedAt + minPriceUpdateInterval
            ) {
                // Calculate price change percentage
                int256 lastPriceScaled = _scalePrice(
                    lastPrice.price,
                    lastPrice.expo
                );
                int256 newPriceScaled = _scalePrice(
                    pythPrice.price,
                    pythPrice.expo
                );

                if (lastPriceScaled > 0) {
                    uint256 priceChange;
                    if (newPriceScaled > lastPriceScaled) {
                        priceChange = uint256(newPriceScaled - lastPriceScaled);
                    } else {
                        priceChange = uint256(lastPriceScaled - newPriceScaled);
                    }

                    uint256 changePercent = (priceChange * 10000) /
                        uint256(lastPriceScaled);

                    if (changePercent > maxPriceChangeBps) {
                        emit CircuitBreakerTriggered(
                            priceFeedId,
                            lastPriceScaled,
                            newPriceScaled,
                            changePercent
                        );
                        revert PriceChangeTooLarge();
                    }
                }
            }
        }
    }

    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================

    /**
     * @notice Update Pyth contract address
     * @param _pyth New Pyth contract address
     */
    function setPythContract(address _pyth) external onlyOwner {
        if (_pyth == address(0)) revert InvalidAddress();
        address oldContract = address(pyth);
        pyth = IPyth(_pyth);
        emit PythContractUpdated(oldContract, _pyth);
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
     * @notice Update cache duration
     * @param _cacheDuration New cache duration in seconds
     */
    function setCacheDuration(uint256 _cacheDuration) external onlyOwner {
        uint256 oldDuration = cacheDuration;
        cacheDuration = _cacheDuration;
        emit CacheDurationUpdated(oldDuration, _cacheDuration);
    }

    /**
     * @notice Update price validation configuration
     * @param _maxConfidenceRatioBps Maximum confidence interval ratio in bps
     * @param _maxPriceChangeBps Maximum price change in bps
     * @param _minPriceUpdateInterval Minimum time between price updates
     * @dev CRITICAL FIX: Allow admin to adjust validation parameters
     */
    function setPriceValidationConfig(
        uint256 _maxConfidenceRatioBps,
        uint256 _maxPriceChangeBps,
        uint256 _minPriceUpdateInterval
    ) external onlyOwner {
        if (_maxConfidenceRatioBps > 5000) revert InvalidValidationConfig(); // Max 50%
        if (_maxPriceChangeBps > 5000) revert InvalidValidationConfig(); // Max 50%

        maxConfidenceRatioBps = _maxConfidenceRatioBps;
        maxPriceChangeBps = _maxPriceChangeBps;
        minPriceUpdateInterval = _minPriceUpdateInterval;

        emit PriceValidationConfigUpdated(
            _maxConfidenceRatioBps,
            _maxPriceChangeBps,
            _minPriceUpdateInterval
        );
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
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    /**
     * @notice Get contract version
     */
    function version() external pure returns (string memory) {
        return "1.0.0-pyth-sdk";
    }

    /**
     * @notice Receive function to accept ETH for price updates
     */
    receive() external payable {}
}
