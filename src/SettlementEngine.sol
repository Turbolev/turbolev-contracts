// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
// NOTE: Direct oracle imports removed - all oracle logic via PriceFeedManager
import "./libraries/PositionLib.sol";
import "./interfaces/IVaultManager.sol";
import "./interfaces/IAssetVault.sol";
import "./interfaces/IPriceFeedManager.sol";

/**
 * @title SettlementEngine
 * @notice Contract for handling settlement and payout calculation - Upgradeable
 *
 * Features:
 * - Calculate payout based on win/loss
 * - House edge management
 * - Win multiplier configuration
 * - Settlement history tracking
 * - UUPS Upgradeable pattern
 */
contract SettlementEngine is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    // ========================================================================
    // CONSTANTS (L-01 FIX: Replace magic numbers)
    // ========================================================================

    /// @notice Default house edge in bps (2%)
    uint16 public constant DEFAULT_HOUSE_EDGE_BPS = 200;

    /// @notice Default win multiplier in bps (3x)
    uint16 public constant DEFAULT_WIN_MULTIPLIER_BPS = 30_000;

    /// @notice Default min bet amount (0.001 ether)
    uint256 public constant DEFAULT_MIN_BET_AMOUNT = 0.001 ether;

    /// @notice Default max bet amount (1000 ether)
    uint256 public constant DEFAULT_MAX_BET_AMOUNT = 1000 ether;

    /// @notice Default max profit cap in bps (2%)
    uint16 public constant DEFAULT_MAX_PROFIT_CAP_BPS = 200;

    /// @notice Basis points denominator
    /// @dev 8.4 FIX: This value MUST match MathLib.BASIS_POINTS (10_000)
    ///      Kept as local constant for gas efficiency (compiler inlines constants)
    uint256 public constant BASIS_POINTS = 10_000;

    // ========================================================================
    // STATE VARIABLES
    // ========================================================================

    /// @notice House edge in bps (500 = 5%)
    uint16 public houseEdgeBps;

    /// @notice Win multiplier in bps (19500 = 1.95x)
    uint16 public winMultiplierBps;

    /// @notice Minimum bet amount (wei)
    uint256 public minBetAmount;

    /// @notice Maximum bet amount (wei)
    uint256 public maxBetAmount;

    /// @notice PositionManager contract address
    address public positionManager;

    /// @notice VaultManager contract address
    address public vaultManager;

    /// @notice PriceFeedManager contract address (handles all oracle logic)
    address public priceFeedManager;

    /// @notice Max profit cap in bps (200 = 2% of vault USD value)
    uint16 public maxProfitCapBps;

    // ========================================================================
    // STORAGE GAP (for future upgrades)
    // ========================================================================

    /// @dev Storage gap to allow for new variables in future versions
    /// @notice Currently using 10 storage slots, reserving 40 slots for future use
    uint256[40] private __gap;

    // ========================================================================
    // STRUCTS
    // ========================================================================

    struct SettlementResult {
        bool won;
        uint256 payout;
        uint256 fee;
        int256 pnl;
        int256 vaultPnL;
        uint8 finalState;
        uint256 excessProfit;
    }

    // ========================================================================
    // EVENTS
    // ========================================================================

    event SettlementProcessed(
        uint64 indexed positionId,
        address indexed user,
        uint256 amount,
        uint256 payout,
        uint256 fee,
        bool won,
        uint256 timestamp
    );

    event ConfigUpdated(
        uint16 houseEdgeBps, uint16 winMultiplierBps, uint256 minBetAmount, uint256 maxBetAmount
    );

    event PositionManagerUpdated(address indexed oldAddress, address indexed newAddress);
    event VaultManagerUpdated(address indexed oldAddress, address indexed newAddress);
    event PriceFeedManagerUpdated(address indexed oldAddress, address indexed newAddress);

    event ProfitCapped(
        uint64 indexed positionId,
        uint256 originalProfit,
        uint256 cappedProfit,
        uint256 excessProfit,
        uint256 timestamp
    );

    event MaxProfitCapBpsUpdated(uint16 oldBps, uint16 newBps);

    // ========================================================================
    // ERRORS
    // ========================================================================

    error InvalidConfig();
    error InvalidAmount();
    error InvalidAddress();
    error NotPositionManager();
    error InvalidOraclePrice();
    error DirectTransferNotAllowed();

    // ========================================================================
    // MODIFIERS
    // ========================================================================

    modifier onlyPositionManager() {
        if (msg.sender != positionManager) revert NotPositionManager();
        _;
    }

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
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        // Default config (L-01 FIX: Using constants instead of magic numbers)
        houseEdgeBps = DEFAULT_HOUSE_EDGE_BPS;
        winMultiplierBps = DEFAULT_WIN_MULTIPLIER_BPS;
        minBetAmount = DEFAULT_MIN_BET_AMOUNT;
        maxBetAmount = DEFAULT_MAX_BET_AMOUNT;
        maxProfitCapBps = DEFAULT_MAX_PROFIT_CAP_BPS;
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
    // SETTLEMENT FUNCTIONS
    // ========================================================================

    /**
     * @notice Calculate potential payout (for display)
     * @param amount Bet amount
     * @return potentialPayout Max possible payout
     */
    function calculatePotentialPayout(uint256 amount)
        external
        view
        returns (uint256 potentialPayout)
    {
        uint256 grossPayout = (amount * winMultiplierBps) / BASIS_POINTS;
        uint256 houseEdge = (grossPayout * houseEdgeBps) / BASIS_POINTS;
        potentialPayout = grossPayout - houseEdge;
        return potentialPayout;
    }

    /**
     * @notice Process settlement logic with synthetic leverage
     * @dev Main settlement function - calculates payout, fees, and P&L
     * @param position Position data
     * @param closePrice Close price
     * @param isLiquidation True if this is a liquidation
     * @return won Whether user won
     * @return payout Payout amount to user
     * @return fee Fee collected
     * @return pnl User P&L
     * @return vaultPnL Vault P&L (opposite of user)
     * @return finalState Final position state
     * @return excessProfit Excess profit from capped trades
     */
    function processSettlement(
        PositionLib.Position calldata position,
        uint256 closePrice,
        bool isLiquidation
    )
        external
        onlyPositionManager
        whenNotPaused
        returns (
            bool won,
            uint256 payout,
            uint256 fee,
            int256 pnl,
            int256 vaultPnL,
            uint8 finalState,
            uint256 excessProfit
        )
    {
        // Calculate P&L with leverage
        (pnl,) = PositionLib.calculateUnrealizedPnL(position, closePrice);

        // Determine win/loss
        won = !isLiquidation && pnl > 0;

        // Calculate liquidation fee if applicable
        uint256 liquidationFee = 0;
        if (isLiquidation) {
            uint256 liquidationFeeBps = PositionLib.calculateLiquidationFee();
            liquidationFee = (position.amount * liquidationFeeBps) / BASIS_POINTS;
        }

        // Calculate final payout/settlement
        payout = 0;
        fee = 0;

        if (isLiquidation) {
            // Liquidation: User gets remaining collateral minus liquidation fee (if any)
            // Remaining = collateral - abs(loss) - liquidation fee
            uint256 absLoss = pnl < 0 ? uint256(-pnl) : 0;
            uint256 remaining = position.amount > absLoss ? position.amount - absLoss : 0;
            payout = remaining > liquidationFee ? remaining - liquidationFee : 0;
            fee = liquidationFee; // Now flat 2% (calculated from PositionLib)
        } else if (won) {
            // Won: User gets collateral + profit - house edge
            uint256 profit = uint256(pnl);

            // Apply profit cap
            // Cap 1: 3× collateral (stored in position at open time)
            uint256 cap1 = position.maxProfitCap; // 3× collateral

            // Cap 2: 2% of vault token value (at settlement time)
            uint256 cap2 = _calculateVaultCap(position.projectToken);

            // Use minimum of two caps
            uint256 maxProfit = cap1;
            if (cap2 > 0 && cap2 < cap1) {
                maxProfit = cap2;
            }

            uint256 cappedProfit = profit;
            excessProfit = 0;

            if (profit > maxProfit) {
                cappedProfit = maxProfit;
                excessProfit = profit - maxProfit;

                emit ProfitCapped(
                    position.positionId, profit, cappedProfit, excessProfit, block.timestamp
                );
            }

            uint256 grossPayout = position.amount + cappedProfit;

            // Apply house edge on capped profit
            fee = (cappedProfit * houseEdgeBps) / BASIS_POINTS;
            payout = grossPayout - fee;
        } else {
            // Lost: User gets collateral minus loss
            uint256 absLoss = uint256(-pnl); // pnl is negative when user loses

            if (absLoss >= position.amount) {
                // Loss exceeds collateral - user gets nothing
                payout = 0;
                fee = position.amount; // Vault keeps all collateral
            } else {
                // Loss is less than collateral - user gets remaining
                payout = position.amount - absLoss;
                fee = absLoss; // Vault keeps the loss amount
            }
        }

        // Vault P&L = -user P&L (vault loses when user wins, gains when user loses)
        vaultPnL = -pnl;

        // Determine final state
        if (isLiquidation) {
            finalState = PositionLib.POSITION_STATE_LIQUIDATED;
        } else {
            finalState = won ? PositionLib.POSITION_STATE_WON : PositionLib.POSITION_STATE_LOST;
        }

        // Emit settlement event
        emit SettlementProcessed(
            position.positionId, position.user, position.amount, payout, fee, won, block.timestamp
        );

        // Return values directly (no struct)
        return (won, payout, fee, pnl, vaultPnL, finalState, excessProfit);
    }

    /**
     * @notice Get settlement price for project token with custom max age
     * @param projectToken Project token address
     * @param maxAge Maximum acceptable price age in seconds
     * @return closePrice Settlement price
     * @return publishTime When price was last updated
     * @dev Gets price from ChainlinkOracle first, falls back to BlocksenseOracle if needed
     *      Now uses PriceFeedManager to get price feed addresses
     */
    function getSettlementPrice(address projectToken, uint256 maxAge)
        external
        view
        whenNotPaused
        returns (uint256 closePrice, uint256 publishTime)
    {
        if (priceFeedManager == address(0)) revert InvalidAddress();

        // Delegate to PriceFeedManager
        return IPriceFeedManager(priceFeedManager).getPrice(projectToken, maxAge);
    }

    /**
     * @notice Get settlement price with fallback and emit event (non-view version)
     * @param projectToken Project token address
     * @param maxAge Maximum acceptable price age in seconds
     * @return closePrice Settlement price
     * @return publishTime When price was last updated
     * @dev Delegates to PriceFeedManager with fallback support
     */
    function getSettlementPriceWithFallback(address projectToken, uint256 maxAge)
        external
        whenNotPaused
        returns (uint256 closePrice, uint256 publishTime)
    {
        if (priceFeedManager == address(0)) revert InvalidAddress();

        // Delegate to PriceFeedManager with fallback
        return IPriceFeedManager(priceFeedManager).getPriceWithFallback(projectToken, maxAge);
    }

    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================

    /**
     * @notice Update settlement config
     */
    function updateConfig(
        uint16 _houseEdgeBps,
        uint16 _winMultiplierBps,
        uint256 _minBetAmount,
        uint256 _maxBetAmount
    ) external onlyOwner whenNotPaused {
        // Validate
        if (_houseEdgeBps > 1000) revert InvalidConfig(); // Max 10% house edge
        if (_winMultiplierBps < BASIS_POINTS) revert InvalidConfig(); // Min 1x multiplier (10000 bps)
        if (_winMultiplierBps > BASIS_POINTS * 100) revert InvalidConfig(); // Max 100x multiplier
        if (_minBetAmount == 0) revert InvalidConfig();
        if (_maxBetAmount < _minBetAmount) revert InvalidConfig();

        houseEdgeBps = _houseEdgeBps;
        winMultiplierBps = _winMultiplierBps;
        minBetAmount = _minBetAmount;
        maxBetAmount = _maxBetAmount;

        emit ConfigUpdated(_houseEdgeBps, _winMultiplierBps, _minBetAmount, _maxBetAmount);
    }

    /**
     * @notice Set BinaryBet contract address
     */
    function setPositionManager(address _positionManager) external onlyOwner whenNotPaused {
        if (_positionManager == address(0)) revert InvalidAddress();
        address oldAddress = positionManager;
        positionManager = _positionManager;
        emit PositionManagerUpdated(oldAddress, _positionManager);
    }

    /**
     * @notice Set VaultManager address
     */
    function setVaultManager(address _vaultManager) external onlyOwner whenNotPaused {
        if (_vaultManager == address(0)) revert InvalidAddress();
        address oldAddress = vaultManager;
        vaultManager = _vaultManager;
        emit VaultManagerUpdated(oldAddress, _vaultManager);
    }

    /**
     * @notice Set PriceFeedManager address
     */
    function setPriceFeedManager(address _priceFeedManager) external onlyOwner whenNotPaused {
        if (_priceFeedManager == address(0)) revert InvalidAddress();
        address oldAddress = priceFeedManager;
        priceFeedManager = _priceFeedManager;
        emit PriceFeedManagerUpdated(oldAddress, _priceFeedManager);
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
     * @notice Set max profit cap in basis points
     * @param _maxProfitCapBps New max profit cap (max 1000 = 10%)
     */
    function setMaxProfitCapBps(uint16 _maxProfitCapBps) external onlyOwner whenNotPaused {
        if (_maxProfitCapBps > 1000) revert InvalidConfig();
        uint16 oldBps = maxProfitCapBps;
        maxProfitCapBps = _maxProfitCapBps;
        emit MaxProfitCapBpsUpdated(oldBps, _maxProfitCapBps);
    }

    /**
     * @notice Authorize upgrade (UUPS pattern)
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

    // ========================================================================
    // TRADING CAP FUNCTIONS
    // ========================================================================

    /**
     * @notice Calculate vault-based cap (2% of vault token value)
     * @param projectToken Project token address
     * @return vaultCap 2% of vault liquidity in tokens (0 if not available)
     * @dev Used at settlement time to compare with 3× collateral cap
     */
    function _calculateVaultCap(address projectToken) internal view returns (uint256) {
        if (vaultManager == address(0)) {
            return 0;
        }

        address vaultAddress = IVaultManager(vaultManager).getVault(projectToken);
        if (vaultAddress == address(0)) {
            return 0;
        }

        IAssetVault.VaultInfo memory vaultInfo = IAssetVault(vaultAddress).getVaultInfo();
        uint256 vaultLiquidity = vaultInfo.totalLiquidity; // Use total LP liquidity for cap calculation

        if (vaultLiquidity == 0) {
            return 0;
        }

        uint256 vaultCap = (vaultLiquidity * maxProfitCapBps) / BASIS_POINTS;

        return vaultCap;
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /**
     * @notice Check if bet amount is valid
     */
    function isValidBetAmount(uint256 amount) external view returns (bool) {
        return amount >= minBetAmount && amount <= maxBetAmount;
    }

    /**
     * @notice Get settlement config
     */
    function getSettlementConfig()
        external
        view
        returns (
            uint16 _houseEdgeBps,
            uint16 _winMultiplierBps,
            uint256 _minBetAmount,
            uint256 _maxBetAmount,
            bool _paused
        )
    {
        return (houseEdgeBps, winMultiplierBps, minBetAmount, maxBetAmount, paused());
    }

    /**
     * @notice Get contract version
     */
    function version() external pure returns (string memory) {
        return "1.0.0-settlement-engine";
    }
}
