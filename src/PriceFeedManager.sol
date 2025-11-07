// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/IPriceFeedManager.sol";
import "./BlocksenseOracle.sol";
import "./ChainlinkOracle.sol";

/**
 * @title PriceFeedManager
 * @notice Contract quản lý mapping project token address với các adapter/price feed address
 * @dev Contract upgradeable sử dụng UUPS pattern
 *
 * Features:
 * - Mapping project token address với price feed configs (nhiều provider)
 * - Có thể update adapter/price feed address cho mỗi token
 * - Hỗ trợ nhiều provider: Blocksense, Chainlink
 * - UUPS Upgradeable pattern
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

    /// @notice Mapping project token address -> PriceFeedConfig
    mapping(address => PriceFeedConfig) private priceFeedConfigs;

    /// @notice BlocksenseOracle contract address
    address payable public blocksenseOracle;

    /// @notice ChainlinkOracle contract address (for fallback)
    address public chainlinkOracle;

    // ========================================================================
    // STORAGE GAP (for future upgrades)
    // ========================================================================

    /// @dev Storage gap to allow for new variables in future versions
    /// @notice Currently using 3 storage slots, reserving 47 slots for future use
    uint256[47] private __gap;

    // ========================================================================
    // EVENTS
    // ========================================================================

    event PriceFeedConfigUpdated(
        address indexed projectToken,
        address indexed blocksenseAdapter,
        address indexed chainlinkFeed
    );

    event BlocksenseAdapterUpdated(
        address indexed projectToken, address indexed oldAdapter, address indexed newAdapter
    );

    event ChainlinkFeedUpdated(
        address indexed projectToken, address indexed oldFeed, address indexed newFeed
    );

    event BlocksenseOracleUpdated(address indexed oldAddress, address indexed newAddress);

    event ChainlinkOracleUpdated(address indexed oldAddress, address indexed newAddress);

    event PriceFallbackUsed(
        address indexed projectToken,
        address indexed chainlinkFeed,
        address indexed blocksenseAdapter,
        string reason
    );

    // ========================================================================
    // ERRORS
    // ========================================================================

    error InvalidAddress();
    error InvalidConfig();
    error InvalidOraclePrice();

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
     * @param _blocksenseOracle BlocksenseOracle contract address
     * @param _chainlinkOracle ChainlinkOracle contract address
     */
    function initialize(
        address initialOwner,
        address payable _blocksenseOracle,
        address _chainlinkOracle
    ) public initializer {
        if (initialOwner == address(0)) revert InvalidAddress();

        __Ownable_init(initialOwner);
        __Pausable_init();
        __UUPSUpgradeable_init();

        blocksenseOracle = _blocksenseOracle;
        chainlinkOracle = _chainlinkOracle;
    }

    // ========================================================================
    // VIEW FUNCTIONS
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
     * @notice Get Blocksense adapter for a project token
     * @param projectToken Project token address
     * @return adapter Blocksense adapter address (address(0) if not configured)
     */
    function getBlocksenseAdapter(address projectToken)
        external
        view
        override
        returns (address adapter)
    {
        return priceFeedConfigs[projectToken].blocksenseAdapter;
    }

    /**
     * @notice Get Chainlink feed for a project token
     * @param projectToken Project token address
     * @return feed Chainlink feed address (address(0) if not configured)
     */
    function getChainlinkFeed(address projectToken) external view override returns (address feed) {
        return priceFeedConfigs[projectToken].chainlinkFeed;
    }

    /**
     * @notice Get price for project token with custom max age
     * @param projectToken Project token address
     * @param maxAge Maximum acceptable price age in seconds
     * @return price Settlement price
     * @return publishTime When price was last updated
     * @dev Gets price from ChainlinkOracle first, falls back to BlocksenseOracle if needed
     */
    function getPrice(address projectToken, uint256 maxAge)
        external
        view
        whenNotPaused
        returns (uint256 price, uint256 publishTime)
    {
        // Get price feed config
        PriceFeedConfig memory config = priceFeedConfigs[projectToken];
        address chainlinkFeed = config.chainlinkFeed;
        address adapter = config.blocksenseAdapter;

        // Try ChainlinkOracle first
        (bool chainlinkSuccess, uint256 chainlinkPrice, uint256 chainlinkUpdatedAt) =
            _tryGetChainlinkPrice(chainlinkFeed, maxAge);

        if (chainlinkSuccess) {
            return (chainlinkPrice, chainlinkUpdatedAt);
        }

        // Chainlink failed, try BlocksenseOracle fallback
        (bool blocksenseSuccess, uint256 blocksensePrice, uint256 blocksenseUpdatedAt) =
            _tryGetBlocksensePrice(adapter, maxAge);

        if (blocksenseSuccess) {
            return (blocksensePrice, blocksenseUpdatedAt);
        }

        // Both sources failed
        revert InvalidOraclePrice();
    }

    /**
     * @notice Get price with fallback and emit event (non-view version)
     * @param projectToken Project token address
     * @param maxAge Maximum acceptable price age in seconds
     * @return price Settlement price
     * @return publishTime When price was last updated
     * @dev Same as getPrice but emits events when fallback is used
     */
    function getPriceWithFallback(address projectToken, uint256 maxAge)
        external
        whenNotPaused
        returns (uint256 price, uint256 publishTime)
    {
        // Get price feed config
        PriceFeedConfig memory config = priceFeedConfigs[projectToken];
        address chainlinkFeed = config.chainlinkFeed;
        address adapter = config.blocksenseAdapter;

        // Try ChainlinkOracle first
        (bool chainlinkSuccess, uint256 chainlinkPrice, uint256 chainlinkUpdatedAt) =
            _tryGetChainlinkPrice(chainlinkFeed, maxAge);

        if (chainlinkSuccess) {
            return (chainlinkPrice, chainlinkUpdatedAt);
        }

        // Chainlink failed, try BlocksenseOracle fallback
        (bool blocksenseSuccess, uint256 blocksensePrice, uint256 blocksenseUpdatedAt) =
            _tryGetBlocksensePrice(adapter, maxAge);

        if (blocksenseSuccess) {
            // Emit fallback event (using Blocksense as fallback from Chainlink)
            emit PriceFallbackUsed(
                projectToken, chainlinkFeed, adapter, "Chainlink failed, using Blocksense"
            );
            return (blocksensePrice, blocksenseUpdatedAt);
        }

        // Both sources failed
        revert InvalidOraclePrice();
    }

    /**
     * @notice Try to get price from ChainlinkOracle
     * @param chainlinkFeed Chainlink price feed address
     * @param maxAge Maximum acceptable price age
     * @return success Whether the call succeeded and price is valid
     * @return price Price (if successful)
     * @return updatedAt Update timestamp (if successful)
     */
    function _tryGetChainlinkPrice(address chainlinkFeed, uint256 maxAge)
        internal
        view
        returns (bool success, uint256 price, uint256 updatedAt)
    {
        // Check if ChainlinkOracle configured
        if (chainlinkOracle == address(0)) {
            return (false, 0, 0);
        }

        // Check if chainlinkFeed configured
        if (chainlinkFeed == address(0)) {
            return (false, 0, 0);
        }

        // Try to get price from ChainlinkOracle
        try ChainlinkOracle(chainlinkOracle).getPrice(chainlinkFeed) returns (
            int256 _price, uint256 _updatedAt
        ) {
            // Validate price
            if (_price <= 0) {
                return (false, 0, 0);
            }

            // Check staleness
            if (block.timestamp - _updatedAt > maxAge) {
                return (false, 0, 0);
            }

            // Success
            return (true, uint256(_price), _updatedAt);
        } catch {
            return (false, 0, 0);
        }
    }

    /**
     * @notice Try to get price from Blocksense Oracle
     * @param adapter CLAggregatorAdapter address
     * @param maxAge Maximum acceptable price age
     * @return success Whether the call succeeded and price is valid
     * @return price Price (if successful)
     * @return updatedAt Update timestamp (if successful)
     */
    function _tryGetBlocksensePrice(address adapter, uint256 maxAge)
        internal
        view
        returns (bool success, uint256 price, uint256 updatedAt)
    {
        // Check if Blocksense Oracle configured
        if (blocksenseOracle == address(0)) {
            return (false, 0, 0);
        }

        // Check if adapter configured
        if (adapter == address(0)) {
            return (false, 0, 0);
        }

        // Try to get price
        try BlocksenseOracle(blocksenseOracle).getPrice(adapter) returns (
            int256 _price, uint256 _updatedAt
        ) {
            // Validate price
            if (_price <= 0) {
                return (false, 0, 0);
            }

            // Check staleness
            if (block.timestamp - _updatedAt > maxAge) {
                return (false, 0, 0);
            }

            // Success
            return (true, uint256(_price), _updatedAt);
        } catch {
            return (false, 0, 0);
        }
    }

    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================

    /**
     * @notice Set price feed configuration for a project token
     * @param projectToken Project token address
     * @param blocksenseAdapter Blocksense adapter address (can be address(0) to disable)
     * @param chainlinkFeed Chainlink feed address (can be address(0) to disable)
     */
    function setPriceFeedConfig(
        address projectToken,
        address blocksenseAdapter,
        address chainlinkFeed
    ) external override onlyOwner whenNotPaused {
        if (projectToken == address(0)) revert InvalidAddress();

        // At least one provider must be configured
        if (blocksenseAdapter == address(0) && chainlinkFeed == address(0)) {
            revert InvalidConfig();
        }

        PriceFeedConfig storage config = priceFeedConfigs[projectToken];
        address oldBlocksenseAdapter = config.blocksenseAdapter;
        address oldChainlinkFeed = config.chainlinkFeed;

        config.blocksenseAdapter = blocksenseAdapter;
        config.chainlinkFeed = chainlinkFeed;

        emit PriceFeedConfigUpdated(projectToken, blocksenseAdapter, chainlinkFeed);

        if (oldBlocksenseAdapter != blocksenseAdapter) {
            emit BlocksenseAdapterUpdated(projectToken, oldBlocksenseAdapter, blocksenseAdapter);
        }

        if (oldChainlinkFeed != chainlinkFeed) {
            emit ChainlinkFeedUpdated(projectToken, oldChainlinkFeed, chainlinkFeed);
        }
    }

    /**
     * @notice Update Blocksense adapter for a project token
     * @param projectToken Project token address
     * @param blocksenseAdapter New Blocksense adapter address (can be address(0) to disable)
     */
    function setBlocksenseAdapter(address projectToken, address blocksenseAdapter)
        external
        override
        onlyOwner
        whenNotPaused
    {
        if (projectToken == address(0)) revert InvalidAddress();

        // Cannot disable both providers
        PriceFeedConfig storage config = priceFeedConfigs[projectToken];
        if (blocksenseAdapter == address(0) && config.chainlinkFeed == address(0)) {
            revert InvalidConfig();
        }

        address oldAdapter = config.blocksenseAdapter;
        config.blocksenseAdapter = blocksenseAdapter;

        emit BlocksenseAdapterUpdated(projectToken, oldAdapter, blocksenseAdapter);
        emit PriceFeedConfigUpdated(projectToken, blocksenseAdapter, config.chainlinkFeed);
    }

    /**
     * @notice Update Chainlink feed for a project token
     * @param projectToken Project token address
     * @param chainlinkFeed New Chainlink feed address (can be address(0) to disable)
     */
    function setChainlinkFeed(address projectToken, address chainlinkFeed)
        external
        override
        onlyOwner
        whenNotPaused
    {
        if (projectToken == address(0)) revert InvalidAddress();

        // Cannot disable both providers
        PriceFeedConfig storage config = priceFeedConfigs[projectToken];
        if (chainlinkFeed == address(0) && config.blocksenseAdapter == address(0)) {
            revert InvalidConfig();
        }

        address oldFeed = config.chainlinkFeed;
        config.chainlinkFeed = chainlinkFeed;

        emit ChainlinkFeedUpdated(projectToken, oldFeed, chainlinkFeed);
        emit PriceFeedConfigUpdated(projectToken, config.blocksenseAdapter, chainlinkFeed);
    }

    /**
     * @notice Set BlocksenseOracle address
     */
    function setBlocksenseOracle(address payable _blocksenseOracle) external onlyOwner {
        if (_blocksenseOracle == address(0)) revert InvalidAddress();
        address oldAddress = blocksenseOracle;
        blocksenseOracle = _blocksenseOracle;
        emit BlocksenseOracleUpdated(oldAddress, _blocksenseOracle);
    }

    /**
     * @notice Set ChainlinkOracle address (for fallback)
     */
    function setChainlinkOracle(address _chainlinkOracle) external onlyOwner {
        address oldOracle = chainlinkOracle;
        chainlinkOracle = _chainlinkOracle;
        emit ChainlinkOracleUpdated(oldOracle, _chainlinkOracle);
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
        return "1.0.0-price-feed-manager";
    }
}
