// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/IBlocksenseOracle.sol";
import "./interfaces/ICLAggregatorAdapter.sol";
import "./interfaces/IChainlinkAggregatorV3.sol";

/**
 * @title ChainlinkOracle
 * @notice Hybrid Oracle với fallback mechanism từ Blocksense sang Chainlink
 * @dev Thử lấy giá từ Blocksense trước, nếu fail (stale/invalid) thì fallback sang Chainlink
 *
 * Key Features:
 * - Primary: Blocksense Oracle (qua CLAggregatorAdapter)
 * - Fallback: Chainlink Price Feed (khi Blocksense fail)
 * - Automatic fallback khi giá Blocksense cũ hoặc invalid
 * - Scale tất cả giá về 18 decimals
 * - Configurable max price age
 */
contract ChainlinkOracle is OwnableUpgradeable, PausableUpgradeable, UUPSUpgradeable {
    // ========================================================================
    // STATE VARIABLES
    // ========================================================================

    /// @notice BlocksenseOracle contract address
    address public blocksenseOracle;

    /// @notice Maximum acceptable price age in seconds (default: 5 minutes)
    uint256 public maxPriceAge;

    /// @notice Mapping: adapter address => chainlink feed address (for fallback)
    mapping(address => address) public chainlinkFeeds;

    /// @notice Track fallback usage
    mapping(address => uint256) public fallbackCount;

    // ========================================================================
    // EVENTS
    // ========================================================================

    event BlocksenseOracleUpdated(address indexed oldOracle, address indexed newOracle);
    event MaxPriceAgeUpdated(uint256 oldMaxAge, uint256 newMaxAge);
    event ChainlinkFeedSet(address indexed adapter, address indexed chainlinkFeed);
    event ChainlinkFeedRemoved(address indexed adapter);
    event FallbackUsed(
        address indexed adapter,
        address indexed chainlinkFeed,
        int256 price,
        uint256 updatedAt,
        string reason
    );

    // ========================================================================
    // ERRORS
    // ========================================================================

    error InvalidAddress();
    error InvalidPrice();
    error PriceStale();
    error NoFallbackAvailable();
    error BothSourcesFailed();

    // ========================================================================
    // INITIALIZATION
    // ========================================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize contract
     * @param _blocksenseOracle BlocksenseOracle contract address
     * @param _maxPriceAge Maximum acceptable price age (seconds)
     */
    function initialize(address _blocksenseOracle, uint256 _maxPriceAge) external initializer {
        if (_blocksenseOracle == address(0)) revert InvalidAddress();

        __Ownable_init(msg.sender);
        __Pausable_init();
        __UUPSUpgradeable_init();

        blocksenseOracle = _blocksenseOracle;
        maxPriceAge = _maxPriceAge;
    }

    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================

    /**
     * @notice Update BlocksenseOracle address
     * @param _newOracle New oracle address
     */
    function setBlocksenseOracle(address _newOracle) external onlyOwner {
        if (_newOracle == address(0)) revert InvalidAddress();
        address oldOracle = blocksenseOracle;
        blocksenseOracle = _newOracle;
        emit BlocksenseOracleUpdated(oldOracle, _newOracle);
    }

    /**
     * @notice Update max price age
     * @param _newMaxAge New max price age in seconds
     */
    function setMaxPriceAge(uint256 _newMaxAge) external onlyOwner {
        uint256 oldMaxAge = maxPriceAge;
        maxPriceAge = _newMaxAge;
        emit MaxPriceAgeUpdated(oldMaxAge, _newMaxAge);
    }

    /**
     * @notice Set Chainlink feed address cho một adapter (for fallback)
     * @param adapter CLAggregatorAdapter address (Blocksense)
     * @param chainlinkFeed Chainlink price feed address
     */
    function setChainlinkFeed(address adapter, address chainlinkFeed) external onlyOwner {
        if (adapter == address(0) || chainlinkFeed == address(0)) revert InvalidAddress();
        chainlinkFeeds[adapter] = chainlinkFeed;
        emit ChainlinkFeedSet(adapter, chainlinkFeed);
    }

    /**
     * @notice Set multiple Chainlink feeds (batch)
     * @param adapters Array of adapter addresses
     * @param feeds Array of Chainlink feed addresses
     */
    function setChainlinkFeeds(address[] calldata adapters, address[] calldata feeds)
        external
        onlyOwner
    {
        if (adapters.length != feeds.length) revert InvalidAddress();

        for (uint256 i = 0; i < adapters.length; i++) {
            if (adapters[i] == address(0) || feeds[i] == address(0)) revert InvalidAddress();
            chainlinkFeeds[adapters[i]] = feeds[i];
            emit ChainlinkFeedSet(adapters[i], feeds[i]);
        }
    }

    /**
     * @notice Remove Chainlink feed cho một adapter
     * @param adapter CLAggregatorAdapter address
     */
    function removeChainlinkFeed(address adapter) external onlyOwner {
        delete chainlinkFeeds[adapter];
        emit ChainlinkFeedRemoved(adapter);
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

    // ========================================================================
    // MAIN FUNCTIONS - HYBRID ORACLE WITH FALLBACK
    // ========================================================================

    /**
     * @notice Get price với fallback mechanism
     * @param adapter CLAggregatorAdapter address (Blocksense primary source)
     * @return price Price in int256 format (scaled to 18 decimals)
     * @return updatedAt When price was last updated
     * @return usedFallback True if fallback to Chainlink was used
     * @dev Thử Blocksense trước, nếu fail thì fallback sang Chainlink
     */
    function getPrice(address adapter)
        external
        view
        whenNotPaused
        returns (int256 price, uint256 updatedAt, bool usedFallback)
    {
        if (adapter == address(0)) revert InvalidAddress();

        // Try Blocksense first
        (
            bool blocksenseSuccess,
            int256 blocksensePrice,
            uint256 blocksenseUpdatedAt,
            string memory failReason
        ) = _tryGetBlocksensePrice(adapter);

        if (blocksenseSuccess) {
            return (blocksensePrice, blocksenseUpdatedAt, false);
        }

        // Blocksense failed, try Chainlink fallback
        address chainlinkFeed = chainlinkFeeds[adapter];
        if (chainlinkFeed == address(0)) {
            revert NoFallbackAvailable();
        }

        (bool chainlinkSuccess, int256 chainlinkPrice, uint256 chainlinkUpdatedAt) =
            _tryGetChainlinkPrice(chainlinkFeed);

        if (!chainlinkSuccess) {
            revert BothSourcesFailed();
        }

        return (chainlinkPrice, chainlinkUpdatedAt, true);
    }

    /**
     * @notice Get price với fallback và emit event khi dùng fallback
     * @param adapter CLAggregatorAdapter address
     * @return price Price in int256 format (scaled to 18 decimals)
     * @return updatedAt When price was last updated
     * @dev Non-view version để có thể emit events và update counters
     */
    function getPriceWithFallback(address adapter)
        external
        whenNotPaused
        returns (int256 price, uint256 updatedAt)
    {
        if (adapter == address(0)) revert InvalidAddress();

        // Try Blocksense first
        (
            bool blocksenseSuccess,
            int256 blocksensePrice,
            uint256 blocksenseUpdatedAt,
            string memory failReason
        ) = _tryGetBlocksensePrice(adapter);

        if (blocksenseSuccess) {
            return (blocksensePrice, blocksenseUpdatedAt);
        }

        // Blocksense failed, try Chainlink fallback
        address chainlinkFeed = chainlinkFeeds[adapter];
        if (chainlinkFeed == address(0)) {
            revert NoFallbackAvailable();
        }

        (bool chainlinkSuccess, int256 chainlinkPrice, uint256 chainlinkUpdatedAt) =
            _tryGetChainlinkPrice(chainlinkFeed);

        if (!chainlinkSuccess) {
            revert BothSourcesFailed();
        }

        // Update fallback counter
        fallbackCount[adapter]++;

        // Emit fallback event
        emit FallbackUsed(adapter, chainlinkFeed, chainlinkPrice, chainlinkUpdatedAt, failReason);

        return (chainlinkPrice, chainlinkUpdatedAt);
    }

    /**
     * @notice Get price từ cả 2 sources (for comparison/monitoring)
     * @param adapter CLAggregatorAdapter address
     * @return blocksensePrice Price from Blocksense
     * @return blocksenseUpdatedAt Blocksense update time
     * @return blocksenseSuccess Whether Blocksense succeeded
     * @return chainlinkPrice Price from Chainlink
     * @return chainlinkUpdatedAt Chainlink update time
     * @return chainlinkSuccess Whether Chainlink succeeded
     */
    function getPriceBothSources(address adapter)
        external
        view
        returns (
            int256 blocksensePrice,
            uint256 blocksenseUpdatedAt,
            bool blocksenseSuccess,
            int256 chainlinkPrice,
            uint256 chainlinkUpdatedAt,
            bool chainlinkSuccess
        )
    {
        // Try Blocksense
        (blocksenseSuccess, blocksensePrice, blocksenseUpdatedAt,) = _tryGetBlocksensePrice(adapter);

        // Try Chainlink
        address chainlinkFeed = chainlinkFeeds[adapter];
        if (chainlinkFeed != address(0)) {
            (chainlinkSuccess, chainlinkPrice, chainlinkUpdatedAt) =
                _tryGetChainlinkPrice(chainlinkFeed);
        }

        return (
            blocksensePrice,
            blocksenseUpdatedAt,
            blocksenseSuccess,
            chainlinkPrice,
            chainlinkUpdatedAt,
            chainlinkSuccess
        );
    }

    /**
     * @notice Check nếu adapter có Chainlink fallback
     * @param adapter CLAggregatorAdapter address
     * @return hasFallback True if Chainlink fallback is configured
     * @return chainlinkFeed Chainlink feed address (or zero address)
     */
    function hasFallback(address adapter)
        external
        view
        returns (bool hasFallback, address chainlinkFeed)
    {
        chainlinkFeed = chainlinkFeeds[adapter];
        hasFallback = chainlinkFeed != address(0);
    }

    // ========================================================================
    // INTERNAL FUNCTIONS
    // ========================================================================

    /**
     * @notice Try to get price from Blocksense Oracle
     * @param adapter CLAggregatorAdapter address
     * @return success Whether the call succeeded and price is valid
     * @return price Price (scaled to 18 decimals)
     * @return updatedAt Update timestamp
     * @return failReason Reason for failure (if any)
     */
    function _tryGetBlocksensePrice(address adapter)
        internal
        view
        returns (bool success, int256 price, uint256 updatedAt, string memory failReason)
    {
        try IBlocksenseOracle(blocksenseOracle).getPrice(adapter) returns (
            int256 _price, uint256 _updatedAt
        ) {
            // Check price validity
            if (_price <= 0) {
                return (false, 0, 0, "Invalid price from Blocksense");
            }

            // Check price age
            if (block.timestamp - _updatedAt > maxPriceAge) {
                return (false, 0, 0, "Stale price from Blocksense");
            }

            return (true, _price, _updatedAt, "");
        } catch {
            return (false, 0, 0, "Blocksense call failed");
        }
    }

    /**
     * @notice Try to get price from Chainlink
     * @param chainlinkFeed Chainlink price feed address
     * @return success Whether the call succeeded and price is valid
     * @return price Price (scaled to 18 decimals)
     * @return updatedAt Update timestamp
     */
    function _tryGetChainlinkPrice(address chainlinkFeed)
        internal
        view
        returns (bool success, int256 price, uint256 updatedAt)
    {
        try IChainlinkAggregatorV3(chainlinkFeed).latestRoundData() returns (
            uint80 roundId, int256 answer, uint256, uint256 _updatedAt, uint80 answeredInRound
        ) {
            // Check round consistency
            if (answeredInRound < roundId) {
                return (false, 0, 0);
            }

            // Check price validity
            if (answer <= 0) {
                return (false, 0, 0);
            }

            // Check price age
            if (block.timestamp - _updatedAt > maxPriceAge) {
                return (false, 0, 0);
            }

            // Get decimals and scale price to 18 decimals
            uint8 decimals = IChainlinkAggregatorV3(chainlinkFeed).decimals();
            int256 scaledPrice = _scalePrice(answer, decimals);

            return (true, scaledPrice, _updatedAt);
        } catch {
            return (false, 0, 0);
        }
    }

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
     * @notice Authorize upgrade (required by UUPSUpgradeable)
     * @param newImplementation Address of new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }
}
