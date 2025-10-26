// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/**
 * @title AssetManager
 * @notice Centralized management of supported assets via Pyth price feed IDs
 * @dev Assets are identified solely by Pyth price feed ID (no token addresses)
 *
 * Key Features:
 * - Manage supported assets for betting via Pyth price feed IDs
 * - Price feed ID validation and whitelist management
 * - Asset metadata and configuration management
 * - Admin-only operations with proper access control
 */
contract AssetManager is
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    // ========================================================================
    // CONSTANTS
    // ========================================================================

    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MAX_SYMBOL_LENGTH = 20;
    uint256 public constant MIN_SYMBOL_LENGTH = 1;
    uint256 public constant PYTH_PRICE_FEED_ID_LENGTH = 32;

    // ========================================================================
    // STRUCTS
    // ========================================================================

    struct AssetInfo {
        uint64 assetId;
        string symbol;
        bytes32 pythPriceFeedId; // Primary identifier
        uint256 minPrice;
        uint256 maxPrice;
        bool enabled;
        uint256 addedAt;
        uint256 lastUpdated;
        address addedBy;
    }

    // ========================================================================
    // STATE VARIABLES
    // ========================================================================

    /// @notice Supported assets by Pyth price feed ID
    mapping(bytes32 => AssetInfo) public supportedAssets;

    /// @notice Whitelist of approved price feed IDs
    mapping(bytes32 => bool) public priceFeedWhitelist;

    /// @notice Asset counter for unique IDs
    uint64 public assetCounter;

    /// @notice Array of all supported price feed IDs
    bytes32[] public supportedPriceFeedIds;

    // ========================================================================
    // EVENTS
    // ========================================================================

    event AssetManagerInitialized(address indexed admin);

    event AssetAdded(
        uint64 indexed assetId,
        string symbol,
        bytes32 indexed priceFeedId,
        address indexed addedBy
    );

    event AssetUpdated(
        uint64 indexed assetId,
        string symbol,
        bytes32 indexed priceFeedId,
        address indexed updatedBy
    );

    event AssetRemoved(
        uint64 indexed assetId,
        string symbol,
        bytes32 indexed priceFeedId,
        address indexed removedBy
    );

    event AssetEnabled(
        uint64 indexed assetId,
        string symbol,
        bool enabled,
        address indexed updatedBy
    );

    event PriceFeedWhitelisted(
        bytes32 indexed priceFeedId,
        bool whitelisted,
        address indexed updatedBy
    );

    // ========================================================================
    // ERRORS
    // ========================================================================

    error InvalidSymbol();
    error InvalidPriceBounds();
    error InvalidPriceFeedId();
    error AssetAlreadyExists();
    error AssetNotFound();
    error AssetNotEnabled();
    error PriceFeedNotWhitelisted();

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
        if (initialOwner == address(0)) revert();

        __Ownable_init(initialOwner);
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        emit AssetManagerInitialized(initialOwner);
    }

    // ========================================================================
    // ASSET MANAGEMENT FUNCTIONS
    // ========================================================================

    /**
     * @notice Add new asset
     * @param symbol Token symbol (e.g., "BTC", "ETH")
     * @param priceFeedId Pyth price feed ID
     * @param minPrice Minimum acceptable price
     * @param maxPrice Maximum acceptable price
     */
    function addAsset(
        string calldata symbol,
        bytes32 priceFeedId,
        uint256 minPrice,
        uint256 maxPrice
    ) external onlyOwner whenNotPaused {
        if (priceFeedId == bytes32(0)) revert InvalidPriceFeedId();
        if (supportedAssets[priceFeedId].assetId != 0)
            revert AssetAlreadyExists();

        // Validate inputs
        if (!_validateSymbol(symbol)) revert InvalidSymbol();
        if (!_validatePriceBounds(minPrice, maxPrice))
            revert InvalidPriceBounds();

        // Create asset info
        uint64 assetId = assetCounter + 1;
        uint256 currentTime = block.timestamp;

        AssetInfo memory assetInfo = AssetInfo({
            assetId: assetId,
            symbol: symbol,
            pythPriceFeedId: priceFeedId,
            minPrice: minPrice,
            maxPrice: maxPrice,
            enabled: true,
            addedAt: currentTime,
            lastUpdated: currentTime,
            addedBy: msg.sender
        });

        // Add to mappings and array
        supportedAssets[priceFeedId] = assetInfo;
        supportedPriceFeedIds.push(priceFeedId);
        assetCounter = assetId;

        // Add to whitelist automatically
        priceFeedWhitelist[priceFeedId] = true;

        emit AssetAdded(assetId, symbol, priceFeedId, msg.sender);
    }

    /**
     * @notice Update asset configuration
     * @param priceFeedId Pyth price feed ID
     * @param minPrice New minimum price
     * @param maxPrice New maximum price
     */
    function updateAsset(
        bytes32 priceFeedId,
        uint256 minPrice,
        uint256 maxPrice
    ) external onlyOwner whenNotPaused {
        AssetInfo storage asset = supportedAssets[priceFeedId];
        if (asset.assetId == 0) revert AssetNotFound();

        if (!_validatePriceBounds(minPrice, maxPrice))
            revert InvalidPriceBounds();

        asset.minPrice = minPrice;
        asset.maxPrice = maxPrice;
        asset.lastUpdated = block.timestamp;

        emit AssetUpdated(asset.assetId, asset.symbol, priceFeedId, msg.sender);
    }

    /**
     * @notice Enable/disable asset
     * @param priceFeedId Pyth price feed ID
     * @param enabled Enable status
     */
    function setAssetEnabled(
        bytes32 priceFeedId,
        bool enabled
    ) external onlyOwner {
        AssetInfo storage asset = supportedAssets[priceFeedId];
        if (asset.assetId == 0) revert AssetNotFound();

        asset.enabled = enabled;
        asset.lastUpdated = block.timestamp;

        emit AssetEnabled(asset.assetId, asset.symbol, enabled, msg.sender);
    }

    /**
     * @notice Remove asset
     * @param priceFeedId Pyth price feed ID
     */
    function removeAsset(bytes32 priceFeedId) external onlyOwner {
        AssetInfo storage asset = supportedAssets[priceFeedId];
        if (asset.assetId == 0) revert AssetNotFound();

        uint64 assetId = asset.assetId;
        string memory symbol = asset.symbol;

        // Remove from mapping
        delete supportedAssets[priceFeedId];
        priceFeedWhitelist[priceFeedId] = false;

        // Remove from array (find and swap with last)
        for (uint256 i = 0; i < supportedPriceFeedIds.length; i++) {
            if (supportedPriceFeedIds[i] == priceFeedId) {
                supportedPriceFeedIds[i] = supportedPriceFeedIds[
                    supportedPriceFeedIds.length - 1
                ];
                supportedPriceFeedIds.pop();
                break;
            }
        }

        emit AssetRemoved(assetId, symbol, priceFeedId, msg.sender);
    }

    /**
     * @notice Whitelist price feed ID
     * @param priceFeedId Pyth price feed ID
     * @param whitelisted Whitelist status
     */
    function whitelistPriceFeed(
        bytes32 priceFeedId,
        bool whitelisted
    ) external onlyOwner {
        if (priceFeedId == bytes32(0)) revert InvalidPriceFeedId();
        priceFeedWhitelist[priceFeedId] = whitelisted;
        emit PriceFeedWhitelisted(priceFeedId, whitelisted, msg.sender);
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /**
     * @notice Check if asset is supported
     * @param priceFeedId Pyth price feed ID
     * @return supported Whether asset exists
     */
    function isAssetSupported(
        bytes32 priceFeedId
    ) external view returns (bool supported) {
        return supportedAssets[priceFeedId].assetId != 0;
    }

    /**
     * @notice Check if asset is enabled
     * @param priceFeedId Pyth price feed ID
     * @return enabled Whether asset is enabled
     */
    function isAssetEnabled(
        bytes32 priceFeedId
    ) external view returns (bool enabled) {
        return supportedAssets[priceFeedId].enabled;
    }

    /**
     * @notice Get asset info
     * @param priceFeedId Pyth price feed ID
     * @return asset Asset information
     */
    function getAssetInfo(
        bytes32 priceFeedId
    ) external view returns (AssetInfo memory asset) {
        return supportedAssets[priceFeedId];
    }

    /**
     * @notice Get all supported price feed IDs
     * @return priceFeedIds Array of price feed IDs
     */
    function getAllSupportedPriceFeedIds()
        external
        view
        returns (bytes32[] memory priceFeedIds)
    {
        return supportedPriceFeedIds;
    }

    /**
     * @notice Get total number of supported assets
     * @return count Total count
     */
    function getSupportedAssetsCount() external view returns (uint256 count) {
        return supportedPriceFeedIds.length;
    }

    /**
     * @notice Check if price feed ID is whitelisted
     * @param priceFeedId Pyth price feed ID
     * @return whitelisted Whether price feed ID is whitelisted
     */
    function isPriceFeedWhitelisted(
        bytes32 priceFeedId
    ) external view returns (bool whitelisted) {
        return priceFeedWhitelist[priceFeedId];
    }

    // ========================================================================
    // INTERNAL VALIDATION FUNCTIONS
    // ========================================================================

    /**
     * @notice Validate symbol
     * @param symbol Token symbol
     * @return valid Whether symbol is valid
     */
    function _validateSymbol(
        string calldata symbol
    ) internal pure returns (bool valid) {
        bytes memory symbolBytes = bytes(symbol);
        uint256 length = symbolBytes.length;

        if (length < MIN_SYMBOL_LENGTH || length > MAX_SYMBOL_LENGTH) {
            return false;
        }

        // Check if all characters are uppercase letters or numbers
        for (uint256 i = 0; i < length; i++) {
            bytes1 char = symbolBytes[i];
            if (
                !(char >= 0x41 && char <= 0x5A) && // A-Z
                !(char >= 0x30 && char <= 0x39) // 0-9
            ) {
                return false;
            }
        }

        return true;
    }

    /**
     * @notice Validate price bounds
     * @param minPrice Minimum price
     * @param maxPrice Maximum price
     * @return valid Whether price bounds are valid
     */
    function _validatePriceBounds(
        uint256 minPrice,
        uint256 maxPrice
    ) internal pure returns (bool valid) {
        if (minPrice == 0) return false;
        if (maxPrice == 0) return false;
        if (minPrice >= maxPrice) return false;
        return true;
    }

    /**
     * @notice Validate price feed ID (must be whitelisted)
     * @param priceFeedId Pyth price feed ID
     * @return valid Whether price feed ID is valid
     */
    function _validatePriceFeedId(
        bytes32 priceFeedId
    ) internal view returns (bool valid) {
        return priceFeedWhitelist[priceFeedId];
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
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    /**
     * @notice Get contract version
     * @return version Version string
     */
    function version() external pure returns (string memory) {
        return "2.0.0-oracle-integrated";
    }
}
