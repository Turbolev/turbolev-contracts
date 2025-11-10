// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/IChainlinkAggregatorV3.sol";

/**
 * @title ChainlinkOracle
 * @notice Oracle contract to get prices from Chainlink Price Feeds
 * @dev Gets prices directly from Chainlink feed address passed in
 *
 * Key Features:
 * - Get prices from Chainlink Price Feed
 * - Scale all prices to 18 decimals
 * - Configurable max price age
 * - Validate price freshness and validity
 */
contract ChainlinkOracle is OwnableUpgradeable, PausableUpgradeable, UUPSUpgradeable {
    // ========================================================================
    // STATE VARIABLES
    // ========================================================================

    /// @notice Maximum acceptable price age in seconds (default: 5 minutes)
    uint256 public maxPriceAge;

    // ========================================================================
    // EVENTS
    // ========================================================================

    event MaxPriceAgeUpdated(uint256 oldMaxAge, uint256 newMaxAge);
    event PriceFetched(address indexed chainlinkFeed, int256 price, uint256 updatedAt);

    // ========================================================================
    // ERRORS
    // ========================================================================

    error InvalidAddress();
    error InvalidPrice();
    error PriceStale();
    error ChainlinkCallFailed();

    // ========================================================================
    // INITIALIZATION
    // ========================================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize contract
     * @param _maxPriceAge Maximum acceptable price age (seconds)
     */
    function initialize(uint256 _maxPriceAge) external initializer {
        __Ownable_init(msg.sender);
        __Pausable_init();
        __UUPSUpgradeable_init();

        maxPriceAge = _maxPriceAge;
    }

    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================

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
    // MAIN FUNCTIONS
    // ========================================================================

    /**
     * @notice Get price from Chainlink feed
     * @param chainlinkFeed Chainlink price feed address
     * @return price Price in int256 format (scaled to 18 decimals)
     * @return updatedAt When price was last updated
     * @dev Gets price directly from the provided Chainlink feed
     */
    function getPrice(address chainlinkFeed)
        external
        view
        whenNotPaused
        returns (int256 price, uint256 updatedAt)
    {
        if (chainlinkFeed == address(0)) revert InvalidAddress();

        (bool success, int256 chainlinkPrice, uint256 chainlinkUpdatedAt) =
            _tryGetChainlinkPrice(chainlinkFeed);

        if (!success) {
            revert ChainlinkCallFailed();
        }

        return (chainlinkPrice, chainlinkUpdatedAt);
    }

    /**
     * @notice Get price from Chainlink feed (non-view version with event)
     * @param chainlinkFeed Chainlink price feed address
     * @return price Price in int256 format (scaled to 18 decimals)
     * @return updatedAt When price was last updated
     * @dev Non-view version to enable event emission
     */
    function getPriceWithEvent(address chainlinkFeed)
        external
        whenNotPaused
        returns (int256 price, uint256 updatedAt)
    {
        if (chainlinkFeed == address(0)) revert InvalidAddress();

        (bool success, int256 chainlinkPrice, uint256 chainlinkUpdatedAt) =
            _tryGetChainlinkPrice(chainlinkFeed);

        if (!success) {
            revert ChainlinkCallFailed();
        }

        emit PriceFetched(chainlinkFeed, chainlinkPrice, chainlinkUpdatedAt);

        return (chainlinkPrice, chainlinkUpdatedAt);
    }

    // ========================================================================
    // INTERNAL FUNCTIONS
    // ========================================================================

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
