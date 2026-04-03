// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
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
contract PythOracle is
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    IHybridOracle
{
    // ========================================================================
    // STATE VARIABLES
    // ========================================================================

    /// @notice Pyth contract address
    address public pythContract;

    /// @notice Mapping: project token address -> Pyth price feed ID (bytes32)
    mapping(address => bytes32) public priceFeedIds;

    /// @notice Maximum acceptable price age for push mode (seconds)
    uint256 public maxPriceAge;

    /// @notice Minimum allowed maxPriceAge (10 seconds)
    uint256 public constant MIN_PRICE_AGE = 10;

    /// @notice Maximum allowed maxPriceAge (1 hour)
    uint256 public constant MAX_PRICE_AGE = 3600;

    /// @notice Default operating mode
    OracleType public defaultMode;

    /// @notice Maximum allowed deviation between spot and EMA price (in bps) for pull-mode updates.
    /// @dev M-20 fix (Layer 2): if |spot - ema| / ema > maxEmaDeviationBps the update is rejected,
    ///      preventing cherry-picked VAAs whose spot price is far from the ~1h EMA baseline.
    ///      Set to 0 to disable the EMA guard entirely.
    uint256 public maxEmaDeviationBps;

    /// @notice Maximum acceptable age of the VAA's publishTime relative to block.timestamp (seconds).
    /// @dev M-20 fix (Layer 1): narrows the cherry-pick window to at most maxVaaStaleness seconds,
    ///      regardless of the broader maxAge passed by the caller.
    ///      Set to 0 to disable the VAA staleness window check.
    uint256 public maxVaaStaleness;

    /// @notice Minimum allowed maxEmaDeviationBps (0.1%)
    uint256 public constant MIN_EMA_DEVIATION_BPS = 10;

    /// @notice Maximum allowed maxEmaDeviationBps (10%)
    uint256 public constant MAX_EMA_DEVIATION_BPS = 1000;

    /// @notice Minimum allowed maxVaaStaleness (10 seconds)
    uint256 public constant MIN_VAA_STALENESS = 10;

    /// @notice Maximum allowed maxVaaStaleness (1 hour)
    uint256 public constant MAX_VAA_STALENESS = 3600;

    // ========================================================================
    // STORAGE GAP
    // ========================================================================

    uint256[44] private __gap;

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
    event ETHWithdrawn(address indexed recipient, uint256 amount);
    event MaxEmaDeviationBpsUpdated(uint256 oldBps, uint256 newBps);
    event MaxVaaStalenessUpdated(uint256 oldStaleness, uint256 newStaleness);

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
    error RefundFailed();
    error LengthMismatch();
    error NoETHBalance();
    error ETHTransferFailed();
    error InvalidPriceAge();
    error InvalidExponent();
    error InvalidEmaDeviationBps();
    error InvalidVaaStaleness();
    error VaaTooOld();
    error EmaDeviationExceeded(uint256 deviationBps, uint256 maxBps);

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
        if (_maxPriceAge < MIN_PRICE_AGE || _maxPriceAge > MAX_PRICE_AGE) revert InvalidPriceAge();

        __Ownable_init(initialOwner);
        __Pausable_init();
        __ReentrancyGuard_init();
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
     * @dev Uses getPriceNoOlderThan with maxPriceAge to enforce staleness check.
     *      Reverts if the on-chain price is older than maxPriceAge seconds.
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

        IPyth.Price memory pythPrice = IPyth(pythContract).getPriceNoOlderThan(priceId, maxPriceAge);

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
        nonReentrant
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
        nonReentrant
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
        // R3-L-01 fix: if price is stale but no updateData was supplied, revert with a
        // clear error immediately rather than letting getPriceNoOlderThan revert with an
        // opaque Pyth error that is hard to diagnose from the call stack.
        if (needsUpdate && updateData.length == 0) revert PriceStale();

        // Update if necessary
        if (needsUpdate && updateData.length > 0) {
            bytes[] memory updateDataArray = abi.decode(updateData, (bytes[]));
            uint256 fee = IPyth(pythContract).getUpdateFee(updateDataArray);

            if (msg.value < fee) revert InsufficientFee();

            IPyth(pythContract).updatePriceFeeds{ value: fee }(updateDataArray);

            // Refund excess
            if (msg.value > fee) {
                (bool success,) = msg.sender.call{ value: msg.value - fee }("");
                if (!success) revert RefundFailed();
            }
        }

        // Get spot price
        IPyth.Price memory pythPrice = IPyth(pythContract).getPriceNoOlderThan(priceId, maxAge);

        if (pythPrice.price <= 0) revert InvalidPrice();

        // M-20 fix Layer 1: VAA publishTime window.
        // Reject VAAs whose publishTime is older than maxVaaStaleness seconds, regardless of
        // the broader maxAge passed by the caller. This shrinks the cherry-pick window from
        // up to 1 hour (maxAge) down to maxVaaStaleness seconds (default 60s), making it
        // economically infeasible to select a favourable spot price from the recent history.
        // Disabled when maxVaaStaleness == 0.
        if (maxVaaStaleness > 0 && block.timestamp - pythPrice.publishTime > maxVaaStaleness) {
            revert VaaTooOld();
        }

        // M-20 fix Layer 2: EMA deviation guard.
        // Read the EMA price from the same on-chain state (updated by updatePriceFeeds above).
        // If the spot price deviates from the EMA by more than maxEmaDeviationBps, the VAA is
        // rejected. This catches cherry-picked VAAs that slip through the staleness window
        // during high-volatility periods.
        // Disabled when maxEmaDeviationBps == 0.
        if (maxEmaDeviationBps > 0) {
            IPyth.Price memory emaPrice =
                IPyth(pythContract).getEmaPriceNoOlderThan(priceId, maxAge);
            if (emaPrice.price > 0) {
                int256 scaledSpot = _scalePythPrice(pythPrice.price, pythPrice.expo);
                int256 scaledEma = _scalePythPrice(emaPrice.price, emaPrice.expo);
                uint256 deviationBps = _calcDeviationBps(scaledSpot, scaledEma);
                if (deviationBps > maxEmaDeviationBps) {
                    revert EmaDeviationExceeded(deviationBps, maxEmaDeviationBps);
                }
            }
        }

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
     * @dev expo must be in [-18, 0] — Pyth real-world feeds always use negative exponents.
     *      Positive exponents are not valid for price feeds and would cause overflow.
     */
    function _scalePythPrice(int64 price, int32 expo) internal pure returns (int256 scaledPrice) {
        // Pyth price feeds always have non-positive exponents (e.g. -8 for USD pairs).
        // A positive exponent is either a malformed feed or an oracle attack — reject it.
        if (expo > 0 || expo < -18) revert InvalidExponent();

        int256 price256 = int256(price);
        int256 expo256 = int256(expo);

        // Target is 18 decimals
        // Formula: scaled = price * 10^(18 + expo)
        // If expo = -8: scaled = price * 10^(18 + (-8)) = price * 10^10
        int256 adjustment = 18 + expo256; // adjustment in [0, 18] given expo in [-18, 0]

        if (adjustment == 0) {
            return price256;
        } else {
            // adjustment > 0: multiply (safe — max 10^18, well within int256)
            return price256 * int256(10 ** uint256(adjustment));
        }
    }

    /**
     * @notice Calculate absolute deviation between two prices in basis points
     * @param a First price (18-decimal scaled)
     * @param b Second price (18-decimal scaled, used as denominator)
     * @return deviationBps |a - b| / b * 10_000
     */
    function _calcDeviationBps(int256 a, int256 b) internal pure returns (uint256 deviationBps) {
        if (b <= 0) return 0;
        int256 diff = a > b ? a - b : b - a;
        return (uint256(diff) * 10_000) / uint256(b);
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
     * @param _maxPriceAge New maximum price age in seconds (must be between MIN_PRICE_AGE and MAX_PRICE_AGE)
     */
    function setMaxPriceAge(uint256 _maxPriceAge) external onlyOwner {
        if (_maxPriceAge < MIN_PRICE_AGE || _maxPriceAge > MAX_PRICE_AGE) revert InvalidPriceAge();
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
     * @notice Set maximum EMA deviation threshold for pull-mode price updates (M-20 Layer 2)
     * @param _bps New threshold in basis points (100 = 1%). Set 0 to disable.
     * @dev When non-zero, must be in [MIN_EMA_DEVIATION_BPS, MAX_EMA_DEVIATION_BPS].
     */
    function setMaxEmaDeviationBps(uint256 _bps) external onlyOwner {
        if (_bps != 0 && (_bps < MIN_EMA_DEVIATION_BPS || _bps > MAX_EMA_DEVIATION_BPS)) {
            revert InvalidEmaDeviationBps();
        }
        uint256 old = maxEmaDeviationBps;
        maxEmaDeviationBps = _bps;
        emit MaxEmaDeviationBpsUpdated(old, _bps);
    }

    /**
     * @notice Set maximum VAA staleness window for pull-mode price updates (M-20 Layer 1)
     * @param _staleness Maximum seconds between VAA publishTime and block.timestamp. Set 0 to disable.
     * @dev When non-zero, must be in [MIN_VAA_STALENESS, MAX_VAA_STALENESS].
     */
    function setMaxVaaStaleness(uint256 _staleness) external onlyOwner {
        if (_staleness != 0 && (_staleness < MIN_VAA_STALENESS || _staleness > MAX_VAA_STALENESS)) {
            revert InvalidVaaStaleness();
        }
        uint256 old = maxVaaStaleness;
        maxVaaStaleness = _staleness;
        emit MaxVaaStalenessUpdated(old, _staleness);
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
     * @notice Withdraw ETH accidentally sent to this contract
     * @param recipient Address to receive the ETH
     * @dev Normal overpayments during oracle updates are already refunded inline.
     *      This function only recovers ETH sent directly outside the update flow.
     */
    function withdrawETH(address payable recipient) external onlyOwner {
        if (recipient == address(0)) revert InvalidAddress();
        uint256 balance = address(this).balance;
        if (balance == 0) revert NoETHBalance();
        (bool success,) = recipient.call{ value: balance }("");
        if (!success) revert ETHTransferFailed();
        emit ETHWithdrawn(recipient, balance);
    }

    /**
     * @notice Receive function to accept ETH
     */
    receive() external payable { }
}
