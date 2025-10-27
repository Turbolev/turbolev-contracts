// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./PythOracle.sol";
import "./libraries/PositionLib.sol";
import "./interfaces/IVaultManager.sol";
import "./interfaces/IAssetVault.sol";

/**
 * @title SettlementEngine
 * @notice Contract for handling settlement and payout calculation - Upgradeable
 * @dev Migrated from settlement_engine.move with native token support
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

    /// @notice PythOracle contract address
    address public pythOracle;

    /// @notice Max profit cap in bps (200 = 2% of vault USD value)
    uint16 public maxProfitCapBps;

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
        uint256 excessProfit; // Profit above cap (Phase 3)
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
        uint16 houseEdgeBps,
        uint16 winMultiplierBps,
        uint256 minBetAmount,
        uint256 maxBetAmount
    );

    event PositionManagerUpdated(
        address indexed oldAddress,
        address indexed newAddress
    );
    event VaultManagerUpdated(
        address indexed oldAddress,
        address indexed newAddress
    );

    event PythOracleUpdated(
        address indexed oldAddress,
        address indexed newAddress
    );

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

        // Default config
        houseEdgeBps = 200; // 2% (changed from 500 = 5%)
        winMultiplierBps = 19500; // 1.95x
        minBetAmount = 0.001 ether; // 0.001 MON
        maxBetAmount = 1000 ether; // 1000 MON
        maxProfitCapBps = 200; // 2% of vault USD value (Phase 3)
    }

    // ========================================================================
    // SETTLEMENT FUNCTIONS
    // ========================================================================

    /**
     * @notice Calculate potential payout (for display)
     * @param amount Bet amount
     * @return potentialPayout Max possible payout
     */
    function calculatePotentialPayout(
        uint256 amount
    ) external view returns (uint256 potentialPayout) {
        uint256 grossPayout = (amount * winMultiplierBps) / 10000;
        uint256 houseEdge = (grossPayout * houseEdgeBps) / 10000;
        potentialPayout = grossPayout - houseEdge;
        return potentialPayout;
    }

    /**
     * @notice Process settlement logic with synthetic leverage
     * @dev Main settlement function - calculates payout, fees, and P&L
     * @param position Position data
     * @param closePrice Close price
     * @param isLiquidation True if this is a liquidation
     * @return result Settlement result with all calculated values
     */
    function processSettlement(
        PositionLib.Position memory position,
        uint256 closePrice,
        bool isLiquidation
    )
        external
        onlyPositionManager
        whenNotPaused
        returns (SettlementResult memory result)
    {
        // Calculate P&L with leverage
        (int256 pnl, ) = PositionLib.calculateUnrealizedPnL(
            position,
            closePrice
        );

        // Determine win/loss
        bool won = !isLiquidation && pnl > 0;

        // Calculate liquidation fee if applicable
        uint256 liquidationFee = 0;
        if (isLiquidation) {
            uint256 liquidationFeeBps = PositionLib.calculateLiquidationFee(
                position.leverage
            );
            liquidationFee = (position.amount * liquidationFeeBps) / 10000;
        }

        // Calculate final payout/settlement
        uint256 payout = 0;
        uint256 fee = 0;

        if (isLiquidation) {
            // Liquidation: User gets remaining collateral minus liquidation fee (if any)
            // Remaining = collateral - abs(loss) - liquidation fee
            uint256 absLoss = pnl < 0 ? uint256(-pnl) : 0;
            uint256 remaining = position.amount > absLoss
                ? position.amount - absLoss
                : 0;
            payout = remaining > liquidationFee
                ? remaining - liquidationFee
                : 0;
            fee = liquidationFee; // Now flat 2% (calculated from PositionLib)
        } else if (won) {
            // Won: User gets collateral + profit - house edge
            uint256 profit = uint256(pnl);

            // Apply profit cap (Phase 3)
            // Cap 1: 3× collateral (stored in position at open time)
            uint256 cap1 = position.maxProfitCap; // 3× collateral

            // Cap 2: 2% of vault token value (at settlement time)
            uint256 cap2 = _calculateVaultCap(
                position.projectToken,
                position.tokenAddress
            );

            // Use minimum of two caps
            uint256 maxProfit = cap1;
            if (cap2 > 0 && cap2 < cap1) {
                maxProfit = cap2;
            }

            uint256 cappedProfit = profit;
            uint256 excessProfit = 0;

            if (profit > maxProfit) {
                cappedProfit = maxProfit;
                excessProfit = profit - maxProfit;

                emit ProfitCapped(
                    position.positionId,
                    profit,
                    cappedProfit,
                    excessProfit,
                    block.timestamp
                );
            }

            uint256 grossPayout = position.amount + cappedProfit;

            // Apply house edge on capped profit
            fee = (cappedProfit * houseEdgeBps) / 10000;
            payout = grossPayout - fee;

            // Store excess profit in result
            result.excessProfit = excessProfit;
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
        int256 vaultPnL = -pnl;

        // Determine final state
        uint8 finalState;
        if (isLiquidation) {
            finalState = PositionLib.POSITION_STATE_LIQUIDATED;
        } else {
            finalState = won
                ? PositionLib.POSITION_STATE_WON
                : PositionLib.POSITION_STATE_LOST;
        }

        // Emit settlement event
        emit SettlementProcessed(
            position.positionId,
            position.user,
            position.amount,
            payout,
            fee,
            won,
            block.timestamp
        );

        // Return result
        return
            SettlementResult({
                won: won,
                payout: payout,
                fee: fee,
                pnl: pnl,
                vaultPnL: vaultPnL,
                finalState: finalState,
                excessProfit: 0 // Will be set if profit was capped
            });
    }

    /**
     * @notice Get settlement price with price update (no older than maxAge)
     * @dev Used by PositionManager to get fresh price from oracle
     * @param priceFeedId Pyth price feed ID
     * @param maxAge Maximum acceptable price age in seconds (e.g., 5)
     * @param priceUpdate Price update data from Pyth
     * @return closePrice Price from oracle (converted to uint256)
     * @return publishTime When price was published
     */
    function getSettlementPriceWithUpdate(
        bytes32 priceFeedId,
        uint256 maxAge,
        bytes[] calldata priceUpdate
    )
        external
        payable
        whenNotPaused
        returns (uint256 closePrice, uint256 publishTime)
    {
        if (pythOracle == address(0)) revert InvalidAddress();

        (int256 price, uint256 pubTime) = PythOracle(payable(pythOracle))
            .getPriceNoOlderThan{value: msg.value}(
            priceFeedId,
            maxAge,
            priceUpdate
        );

        // Convert to uint256 (price should always be positive for assets)
        if (price <= 0) revert InvalidOraclePrice();
        return (uint256(price), pubTime);
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
    ) external onlyOwner {
        // Validate
        if (_houseEdgeBps > 2000) revert InvalidConfig(); // Max 20% house edge
        if (_winMultiplierBps < 10000) revert InvalidConfig(); // Min 1x multiplier
        if (_winMultiplierBps > 50000) revert InvalidConfig(); // Max 5x multiplier
        if (_minBetAmount == 0) revert InvalidConfig();
        if (_maxBetAmount < _minBetAmount) revert InvalidConfig();

        houseEdgeBps = _houseEdgeBps;
        winMultiplierBps = _winMultiplierBps;
        minBetAmount = _minBetAmount;
        maxBetAmount = _maxBetAmount;

        emit ConfigUpdated(
            _houseEdgeBps,
            _winMultiplierBps,
            _minBetAmount,
            _maxBetAmount
        );
    }

    /**
     * @notice Set BinaryBet contract address
     */
    function setPositionManager(address _positionManager) external onlyOwner {
        if (_positionManager == address(0)) revert InvalidAddress();
        address oldAddress = positionManager;
        positionManager = _positionManager;
        emit PositionManagerUpdated(oldAddress, _positionManager);
    }

    /**
     * @notice Set VaultManager address
     */
    function setVaultManager(address _vaultManager) external onlyOwner {
        if (_vaultManager == address(0)) revert InvalidAddress();
        address oldAddress = vaultManager;
        vaultManager = _vaultManager;
        emit VaultManagerUpdated(oldAddress, _vaultManager);
    }

    /**
     * @notice Set PythOracle address
     */
    function setPythOracle(address _pythOracle) external onlyOwner {
        if (_pythOracle == address(0)) revert InvalidAddress();
        address oldAddress = pythOracle;
        pythOracle = _pythOracle;
        emit PythOracleUpdated(oldAddress, _pythOracle);
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
    function setMaxProfitCapBps(uint16 _maxProfitCapBps) external onlyOwner {
        if (_maxProfitCapBps > 1000) revert InvalidConfig(); // Max 10%
        uint16 oldBps = maxProfitCapBps;
        maxProfitCapBps = _maxProfitCapBps;
        emit MaxProfitCapBpsUpdated(oldBps, _maxProfitCapBps);
    }

    /**
     * @notice Authorize upgrade (UUPS pattern)
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    // ========================================================================
    // TRADING CAP FUNCTIONS (Phase 3)
    // ========================================================================

    /**
     * @notice Calculate vault-based cap (2% of vault token value)
     * @param projectToken Project token address
     * @param collateralToken Collateral token address
     * @return vaultCap 2% of vault liquidity in tokens (0 if not available)
     * @dev Used at settlement time to compare with 3× collateral cap
     */
    function _calculateVaultCap(
        address projectToken,
        address collateralToken
    ) internal view returns (uint256) {
        if (vaultManager == address(0)) {
            return 0; // No vault manager
        }

        // Get vault address for (projectToken, collateralToken) pair
        address vaultAddress = IVaultManager(vaultManager).getVault(
            projectToken,
            collateralToken
        );
        if (vaultAddress == address(0)) {
            return 0; // Vault not found
        }

        // Get vault total liquidity (in token amount, NOT USD)
        IAssetVault.VaultInfo memory vaultInfo = IAssetVault(vaultAddress)
            .getVaultInfo();
        uint256 vaultLiquidity = vaultInfo.totalLiquidity;

        if (vaultLiquidity == 0) {
            return 0;
        }

        // Calculate 2% of vault liquidity (in token amount)
        uint256 vaultCap = (vaultLiquidity * maxProfitCapBps) / 10000;

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
        return (
            houseEdgeBps,
            winMultiplierBps,
            minBetAmount,
            maxBetAmount,
            paused()
        );
    }

    /**
     * @notice Get contract version
     */
    function version() external pure returns (string memory) {
        return "2.0.0-upgradeable-native";
    }
}
