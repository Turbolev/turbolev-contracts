// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../interfaces/oracles/IHybridOracle.sol";
import "../interfaces/oracles/IPyth.sol";

/**
 * @title PythOracle
 * @notice Hybrid oracle implementation for Pyth Network
 * @dev Supports both PUSH and PULL modes
 * @dev Reference: https://docs.pyth.network/price-feeds/core/use-real-time-data/pull-integration/evm
 *
 * Key Features:
 * - Pull mode: Update prices on-demand before reading
 * - Push mode: Read already-updated prices (if recent enough)
 * - Hybrid: Can work in both modes depending on use case
 * - All prices scaled to 18 decimals
 */
contract PythOracle is OwnableUpgradeable, PausableUpgradeable, UUPSUpgradeable, IHybridOracle {
    // ========================================================================
    // STATE VARIABLES
    // ========================================================================

    /// @notice Pyth contract address
    address public pythContract;

    /// @notice Mapping: project token address -> Pyth price feed ID (bytes32)
    mapping(address => bytes32) public priceFeedIds;

    /// @notice Maximum acceptable price age for push mode (seconds)
    uint256 public maxPriceAge;

    /// @notice Default operating mode
    OracleType public defaultMode;

    // ========================================================================
    // STORAGE GAP
    // ========================================================================

    uint256[46] private __gap;

    // ========================================================================
    // EVENTS
    // ========================================================================

    event PythContractUpdated(address indexed oldContract, address indexed newContract);
    event PriceFeedIdSet(address indexed token, bytes32 indexed priceId);
    event PriceUpdated(
        address indexed token, bytes32 indexed priceId, int256 price, uint256 publishTime
    );
    event MaxPriceAgeUpdated(uint256 oldAge, uint256 newAge);
    event DefaultModeUpdated(OracleType oldMode, OracleType newMode);

    // ========================================================================
    // ERRORS
    // ========================================================================

    error InvalidAddress();
    error InvalidPriceFeedId();
    error PriceStale();
    error InvalidPrice();
    error InsufficientFee();
    error PythCallFailed();
    error PriceFeedNotConfigured();
    error RefundFailed(); // L-03 FIX: Custom error instead of string
    error LengthMismatch(); // L-03 FIX: Custom error instead of string

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
     * @param _pythContract Pyth contract address
     * @param _maxPriceAge Maximum price age in seconds
     */
    function initialize(address initialOwner, address _pythContract, uint256 _maxPriceAge)
        public
        initializer
    {
        if (initialOwner == address(0) || _pythContract == address(0)) {
            revert InvalidAddress();
        }

        __Ownable_init(initialOwner);
        __Pausable_init();
        __UUPSUpgradeable_init();

        pythContract = _pythContract;
        maxPriceAge = _maxPriceAge;
        defaultMode = OracleType.PULL; // Default to PULL mode
    }

    // ========================================================================
    // BASE ORACLE INTERFACE
    // ========================================================================

    /**
     * @notice Get oracle type
     * @return oracleType Always returns PULL as default (but supports both)
     */
    function getOracleType() external view override returns (OracleType) {
        return defaultMode;
    }

    /**
     * @notice Check if oracle supports hybrid mode
     * @return supported Always true for Pyth
     */
    function supportsHybridMode() external pure override returns (bool) {
        return true;
    }

    /**
     * @notice Get oracle version
     * @return Version string
     */
    function version() external pure override returns (string memory) {
        return "1.0.0-pyth-hybrid";
    }

    // ========================================================================
    // HYBRID ORACLE INTERFACE
    // ========================================================================

    /**
     * @notice Get current operating mode
     * @return mode Current mode
     */
    function getCurrentMode() external view override returns (OracleType) {
        return defaultMode;
    }

    /**
     * @notice Check if feed supports pull mode
     * @param feed Token address
     * @return supported Always true for Pyth (all feeds support pull)
     */
    function supportsPullMode(address feed) external view override returns (bool) {
        return priceFeedIds[feed] != bytes32(0);
    }

    // ========================================================================
    // PUSH ORACLE INTERFACE
    // ========================================================================

    /**
     * @notice Get latest price (push mode - view only)
     * @param feed Token address (maps to Pyth price feed ID)
     * @return price Latest price (scaled to 18 decimals)
     * @return updatedAt Timestamp when price was published
     * @dev Reads from already-updated prices on Pyth contract
     */
    function getPrice(address feed)
        external
        view
        override
        whenNotPaused
        returns (int256 price, uint256 updatedAt)
    {
        bytes32 priceId = priceFeedIds[feed];
        if (priceId == bytes32(0)) revert PriceFeedNotConfigured();

        IPyth.Price memory pythPrice = IPyth(pythContract).getPriceUnsafe(priceId);

        if (pythPrice.price <= 0) revert InvalidPrice();

        // Scale to 18 decimals
        int256 scaledPrice = _scalePythPrice(pythPrice.price, pythPrice.expo);

        return (scaledPrice, pythPrice.publishTime);
    }

    /**
     * @notice Get price with staleness check
     * @param feed Token address
     * @param maxAge Maximum acceptable age in seconds
     * @return price Latest price (scaled to 18 decimals)
     * @return updatedAt Timestamp when price was published
     */
    function getPriceNoOlderThan(address feed, uint256 maxAge)
        external
        view
        override
        whenNotPaused
        returns (int256 price, uint256 updatedAt)
    {
        bytes32 priceId = priceFeedIds[feed];
        if (priceId == bytes32(0)) revert PriceFeedNotConfigured();

        IPyth.Price memory pythPrice = IPyth(pythContract).getPriceNoOlderThan(priceId, maxAge);

        if (pythPrice.price <= 0) revert InvalidPrice();

        // Scale to 18 decimals
        int256 scaledPrice = _scalePythPrice(pythPrice.price, pythPrice.expo);

        return (scaledPrice, pythPrice.publishTime);
    }

    /**
     * @notice Check if price is stale
     * @param feed Token address
     * @param maxAge Maximum acceptable age in seconds
     * @return isStale True if price is stale
     */
    function isPriceStale(address feed, uint256 maxAge) external view override returns (bool) {
        bytes32 priceId = priceFeedIds[feed];
        if (priceId == bytes32(0)) return true;

        try IPyth(pythContract).getPriceUnsafe(priceId) returns (IPyth.Price memory pythPrice) {
            if (pythPrice.publishTime == 0) return true;
            return (block.timestamp - pythPrice.publishTime) > maxAge;
        } catch {
            return true;
        }
    }

    // ========================================================================
    // PULL ORACLE INTERFACE
    // ========================================================================

    /**
     * @notice Update price on-chain
     * @param feed Token address (maps to Pyth price feed ID)
     * @param updateData Pyth update data (from Pyth API)
     * @dev Must send enough ETH to cover Pyth update fee
     */
    function updatePrice(address feed, bytes calldata updateData)
        external
        payable
        override
        whenNotPaused
    {
        bytes32 priceId = priceFeedIds[feed];
        if (priceId == bytes32(0)) revert PriceFeedNotConfigured();

        // Decode updateData as array
        bytes[] memory updateDataArray = abi.decode(updateData, (bytes[]));

        // Get required fee
        uint256 fee = IPyth(pythContract).getUpdateFee(updateDataArray);
        if (msg.value < fee) revert InsufficientFee();

        // Update price feeds
        try IPyth(pythContract).updatePriceFeeds{ value: fee }(updateDataArray) {
            // Get updated price for event
            IPyth.Price memory pythPrice = IPyth(pythContract).getPriceUnsafe(priceId);
            int256 scaledPrice = _scalePythPrice(pythPrice.price, pythPrice.expo);

            emit PriceUpdated(feed, priceId, scaledPrice, pythPrice.publishTime);

            // Refund excess fee
            if (msg.value > fee) {
                (bool success,) = msg.sender.call{ value: msg.value - fee }("");
                // L-03 FIX: Use custom error instead of string
                if (!success) revert RefundFailed();
            }
        } catch {
            revert PythCallFailed();
        }
    }

    /**
     * @notice Get price and update if stale (pull mode)
     * @param feed Token address
     * @param maxAge Maximum acceptable age in seconds
     * @param updateData Pyth update data (used if price is stale)
     * @return resultPrice Latest price (scaled to 18 decimals)
     * @return resultUpdatedAt Timestamp when price was published
     */
    function getPriceWithUpdate(address feed, uint256 maxAge, bytes calldata updateData)
        external
        payable
        override
        whenNotPaused
        returns (int256 resultPrice, uint256 resultUpdatedAt)
    {
        bytes32 priceId = priceFeedIds[feed];
        if (priceId == bytes32(0)) revert PriceFeedNotConfigured();

        // Check if price is stale
        bool needsUpdate = false;
        try IPyth(pythContract).getPriceUnsafe(priceId) returns (IPyth.Price memory priceData) {
            if (priceData.publishTime == 0 || (block.timestamp - priceData.publishTime) > maxAge) {
                needsUpdate = true;
            }
        } catch {
            needsUpdate = true;
        }
        // Update if necessary
        if (needsUpdate && updateData.length > 0) {
            bytes[] memory updateDataArray = abi.decode(updateData, (bytes[]));
            uint256 fee = IPyth(pythContract).getUpdateFee(updateDataArray);

            if (msg.value < fee) revert InsufficientFee();

            IPyth(pythContract).updatePriceFeeds{ value: fee }(updateDataArray);

            // Refund excess
            if (msg.value > fee) {
                (bool success,) = msg.sender.call{ value: msg.value - fee }("");
                // L-03 FIX: Use custom error instead of string
                if (!success) revert RefundFailed();
            }
        }

        // Get price
        IPyth.Price memory pythPrice = IPyth(pythContract).getPriceNoOlderThan(priceId, maxAge);

        if (pythPrice.price <= 0) revert InvalidPrice();

        int256 scaledPrice = _scalePythPrice(pythPrice.price, pythPrice.expo);

        emit PriceUpdated(feed, priceId, scaledPrice, pythPrice.publishTime);

        return (scaledPrice, pythPrice.publishTime);
    }

    /**
     * @notice Get update fee for updating price
     * @param updateData Pyth update data
     * @return fee Fee in wei
     */
    function getUpdateFee(
        address,
        /* feed */
        bytes calldata updateData
    )
        external
        view
        override
        returns (uint256 fee)
    {
        bytes[] memory updateDataArray = abi.decode(updateData, (bytes[]));
        return IPyth(pythContract).getUpdateFee(updateDataArray);
    }

    // ========================================================================
    // INTERNAL FUNCTIONS
    // ========================================================================

    /**
     * @notice Scale Pyth price to 18 decimals
     * @param price Pyth price (int64)
     * @param expo Pyth price exponent (int32)
     * @return scaledPrice Price scaled to 18 decimals
     * @dev Pyth price = price * 10^expo
     * @dev We want: price * 10^18
     * @dev So: price * 10^expo * 10^(18-expo) = price * 10^18
     */
    function _scalePythPrice(int64 price, int32 expo) internal pure returns (int256 scaledPrice) {
        int256 price256 = int256(price);
        int256 expo256 = int256(expo);

        // Target is 18 decimals
        // Formula: scaled = price * 10^(18 + expo)
        // If expo = -8: scaled = price * 10^(18 + (-8)) = price * 10^10
        int256 targetDecimals = 18;
        int256 adjustment = targetDecimals + expo256;

        if (adjustment == 0) {
            return price256;
        } else if (adjustment > 0) {
            // Need to multiply
            return price256 * int256(10 ** uint256(adjustment));
        } else {
            // Need to divide
            return price256 / int256(10 ** uint256(-adjustment));
        }
    }

    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================

    /**
     * @notice Set Pyth contract address
     * @param _pythContract New Pyth contract address
     */
    function setPythContract(address _pythContract) external onlyOwner {
        if (_pythContract == address(0)) revert InvalidAddress();
        address oldContract = pythContract;
        pythContract = _pythContract;
        emit PythContractUpdated(oldContract, _pythContract);
    }

    /**
     * @notice Set price feed ID for a token
     * @param token Token address
     * @param priceId Pyth price feed ID (bytes32)
     */
    function setPriceFeedId(address token, bytes32 priceId) external onlyOwner {
        if (token == address(0)) revert InvalidAddress();
        if (priceId == bytes32(0)) revert InvalidPriceFeedId();

        priceFeedIds[token] = priceId;
        emit PriceFeedIdSet(token, priceId);
    }

    /**
     * @notice Set multiple price feed IDs
     * @param tokens Array of token addresses
     * @param priceIds Array of Pyth price feed IDs
     */
    function setPriceFeedIds(address[] calldata tokens, bytes32[] calldata priceIds)
        external
        onlyOwner
    {
        // L-03 FIX: Use custom error instead of string
        if (tokens.length != priceIds.length) revert LengthMismatch();

        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == address(0)) revert InvalidAddress();
            if (priceIds[i] == bytes32(0)) revert InvalidPriceFeedId();

            priceFeedIds[tokens[i]] = priceIds[i];
            emit PriceFeedIdSet(tokens[i], priceIds[i]);
        }
    }

    /**
     * @notice Set maximum price age
     * @param _maxPriceAge New maximum price age in seconds
     */
    function setMaxPriceAge(uint256 _maxPriceAge) external onlyOwner {
        uint256 oldAge = maxPriceAge;
        maxPriceAge = _maxPriceAge;
        emit MaxPriceAgeUpdated(oldAge, _maxPriceAge);
    }

    /**
     * @notice Set default operating mode
     * @param mode New default mode (PUSH or PULL)
     */
    function setDefaultMode(OracleType mode) external onlyOwner {
        OracleType oldMode = defaultMode;
        defaultMode = mode;
        emit DefaultModeUpdated(oldMode, mode);
    }

    /**
     * @notice Get price feed ID for a token
     * @param token Token address
     * @return priceId Pyth price feed ID
     */
    function getPriceFeedId(address token) external view returns (bytes32) {
        return priceFeedIds[token];
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
     * @notice Receive function to accept ETH
     */
    receive() external payable { }
}
