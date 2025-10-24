// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title VaultManager
 * @notice Manage liquidity vault and LP positions - Upgradeable with native token
 * @dev Migrated from vault_manager.move
 *
 * v3.0: Synthetic Leverage Support
 * - Single vault for native token (MON)
 * - LP staking/unstaking
 * - P&L tracking with leveraged positions
 * - Risk management for leveraged positions
 * - Share-based accounting
 * - Leverage exposure tracking
 * - UUPS Upgradeable pattern
 */
contract VaultManager is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    // ========================================================================
    // STATE VARIABLES
    // ========================================================================

    /// @notice BinaryBet contract address
    address public binaryBetContract;

    /// @notice SettlementEngine contract address
    address public settlementEngine;

    /// @notice Vault information
    VaultInfo public vault;

    /// @notice Vault parameters
    VaultParams public vaultParams;

    /// @notice LP positions mapping: user -> LPPosition
    mapping(address => LPPosition) public lpPositions;

    /// @notice Array of all LPs
    address[] public vaultLPs;

    // ========================================================================
    // STRUCTS
    // ========================================================================

    struct VaultInfo {
        uint256 totalLiquidity; // Total native token trong vault
        uint256 activeLiquidity; // Available cho betting
        uint256 reservedLiquidity; // Reserved cho open positions (collateral)
        uint256 totalShares; // Total LP shares
        uint256 lifetimePnL; // Lifetime profit/loss (absolute value)
        bool isNegativePnL; // True if P&L is negative
        uint256 totalVolume; // Total volume traded (collateral)
        uint256 totalPositionsSettled; // Total positions settled
        uint256 totalLeverageExposure; // Total leverage exposure (position sizes)
        uint256 maxLeverageExposure; // Max leverage exposure at any time
        bool isPaused; // Vault paused
        uint256 createdAt; // Creation timestamp
    }

    struct VaultParams {
        uint16 maxPayoutBps; // Max payout % per bet (default: 500 = 5%)
        uint16 perBetUtilBps; // Max utilization per bet (default: 1000 = 10%)
        uint16 maxUtilizationBps; // Max total utilization (default: 8000 = 80%)
        uint256 minBetAmount; // Min bet amount (collateral)
        uint256 maxBetAmount; // Max bet amount (collateral)
        uint16 maxLeverageExposureBps; // Max leverage exposure vs liquidity (default: 10000 = 100%)
    }

    struct LPPosition {
        address user;
        uint256 shares; // LP shares owned
        uint256 stakedAmount; // Original stake amount (for reference)
        uint256 stakedAt; // Stake timestamp
        uint256 lastRewardClaim; // Last reward claim (future use)
        uint256 totalRewardsClaimed; // Total rewards claimed (future use)
    }

    // ========================================================================
    // EVENTS
    // ========================================================================

    event VaultInitialized(uint256 timestamp);

    event LiquidityAdded(
        address indexed user,
        uint256 amount,
        uint256 shares,
        uint256 totalLiquidity,
        uint256 timestamp
    );

    event LiquidityRemoved(
        address indexed user,
        uint256 amount,
        uint256 shares,
        uint256 totalLiquidity,
        uint256 timestamp
    );

    event BetDeposited(uint256 amount, uint256 newReserved, uint256 timestamp);

    event PayoutExecuted(
        address indexed user,
        uint256 amount,
        uint256 timestamp
    );

    event VaultPnLUpdated(
        uint256 betAmount,
        bool userWon,
        uint256 payout,
        uint256 newLifetimePnL,
        bool isNegative,
        uint256 timestamp
    );

    event VaultPnLUpdatedWithLeverage(
        uint256 collateral,
        int256 vaultPnL,
        uint256 fee,
        uint256 newLifetimePnL,
        bool isNegative,
        uint256 timestamp
    );

    event LeverageExposureUpdated(
        uint256 totalExposure,
        uint256 maxExposure,
        uint256 timestamp
    );

    event VaultParamsUpdated(
        uint16 maxPayoutBps,
        uint16 perBetUtilBps,
        uint16 maxUtilizationBps,
        uint256 minBetAmount,
        uint256 maxBetAmount
    );

    event VaultPausedToggled(bool isPaused);
    event BinaryBetContractUpdated(
        address indexed oldAddress,
        address indexed newAddress
    );
    event SettlementEngineUpdated(
        address indexed oldAddress,
        address indexed newAddress
    );

    // ========================================================================
    // ERRORS
    // ========================================================================

    error VaultIsPaused();
    error VaultNotPaused();
    error InvalidAmount();
    error InvalidConfig();
    error InvalidAddress();
    error InsufficientLiquidity();
    error InsufficientShares();
    error NoLPPosition();
    error NotBinaryBet();
    error RiskLimitExceeded();
    error TransferFailed();

    // ========================================================================
    // MODIFIERS
    // ========================================================================

    modifier whenVaultNotPaused() {
        if (vault.isPaused) revert VaultIsPaused();
        _;
    }

    modifier onlyBinaryBet() {
        if (msg.sender != binaryBetContract) revert NotBinaryBet();
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

        // Initialize vault
        vault = VaultInfo({
            totalLiquidity: 0,
            activeLiquidity: 0,
            reservedLiquidity: 0,
            totalShares: 0,
            lifetimePnL: 0,
            isNegativePnL: false,
            totalVolume: 0,
            totalPositionsSettled: 0,
            totalLeverageExposure: 0,
            maxLeverageExposure: 0,
            isPaused: false,
            createdAt: block.timestamp
        });

        // Default vault params
        vaultParams = VaultParams({
            maxPayoutBps: 500, // 5%
            perBetUtilBps: 1000, // 10%
            maxUtilizationBps: 8000, // 80%
            minBetAmount: 0.001 ether, // 0.001 MON
            maxBetAmount: 1000 ether, // 1000 MON
            maxLeverageExposureBps: 10000 // 100% (1:1 ratio with liquidity)
        });

        emit VaultInitialized(block.timestamp);
    }

    // ========================================================================
    // RECEIVE / FALLBACK
    // ========================================================================

    /// @notice Accept native token transfers
    receive() external payable {}

    /// @notice Fallback function
    fallback() external payable {}

    // ========================================================================
    // LP FUNCTIONS
    // ========================================================================

    /**
     * @notice Stake native token vào vault
     */
    function stake()
        external
        payable
        nonReentrant
        whenNotPaused
        whenVaultNotPaused
    {
        uint256 amount = msg.value;
        if (amount == 0) revert InvalidAmount();

        // Calculate shares
        uint256 shares;
        if (vault.totalShares == 0) {
            // First staker: 1:1 ratio
            shares = amount;
        } else {
            // Subsequent stakers: proportional to current ratio
            shares = (amount * vault.totalShares) / vault.totalLiquidity;
        }

        // Update vault
        vault.totalLiquidity += amount;
        vault.activeLiquidity += amount;
        vault.totalShares += shares;

        // Update/Create LP position
        LPPosition storage lpPos = lpPositions[msg.sender];
        if (lpPos.user == address(0)) {
            // New LP
            lpPos.user = msg.sender;
            lpPos.stakedAt = block.timestamp;
            vaultLPs.push(msg.sender);
        }
        lpPos.shares += shares;
        lpPos.stakedAmount += amount;

        emit LiquidityAdded(
            msg.sender,
            amount,
            shares,
            vault.totalLiquidity,
            block.timestamp
        );
    }

    /**
     * @notice Unstake and withdraw native token
     * @param shares Number of shares to unstake
     */
    function unstake(uint256 shares) external nonReentrant whenNotPaused {
        if (shares == 0) revert InvalidAmount();

        LPPosition storage lpPos = lpPositions[msg.sender];
        if (lpPos.user == address(0)) revert NoLPPosition();
        if (lpPos.shares < shares) revert InsufficientShares();

        // Calculate amount to return
        uint256 amount = (shares * vault.totalLiquidity) / vault.totalShares;

        if (amount > vault.activeLiquidity) revert InsufficientLiquidity();

        // Update LP position
        lpPos.shares -= shares;
        lpPos.stakedAmount =
            (lpPos.shares * vault.totalLiquidity) /
            vault.totalShares;

        // Update vault
        vault.totalLiquidity -= amount;
        vault.activeLiquidity -= amount;
        vault.totalShares -= shares;

        // Transfer native token to user
        (bool success, ) = msg.sender.call{value: amount}("");
        if (!success) revert TransferFailed();

        emit LiquidityRemoved(
            msg.sender,
            amount,
            shares,
            vault.totalLiquidity,
            block.timestamp
        );
    }

    // ========================================================================
    // BETTING FUNCTIONS (Called by BinaryBet)
    // ========================================================================

    /**
     * @notice Deposit from bet (called by BinaryBet)
     * @param amount Collateral amount
     * @param positionSize Position size (amount × leverage) - optional for tracking
     */
    function depositFromBet(
        uint256 amount,
        uint256 positionSize
    ) external payable nonReentrant onlyBinaryBet {
        if (msg.value != amount) revert InvalidAmount();

        // Update vault
        vault.totalLiquidity += amount;
        vault.reservedLiquidity += amount;

        // Track leverage exposure (if position size provided and > collateral)
        if (positionSize > amount) {
            vault.totalLeverageExposure += positionSize;

            // Update max exposure if needed
            if (vault.totalLeverageExposure > vault.maxLeverageExposure) {
                vault.maxLeverageExposure = vault.totalLeverageExposure;

                emit LeverageExposureUpdated(
                    vault.totalLeverageExposure,
                    vault.maxLeverageExposure,
                    block.timestamp
                );
            }
        }

        emit BetDeposited(amount, vault.reservedLiquidity, block.timestamp);
    }

    /**
     * @notice Deposit from bet (overload for backward compatibility)
     * @param amount Bet amount
     */
    function depositFromBet(
        uint256 amount
    ) external payable nonReentrant onlyBinaryBet {
        if (msg.value != amount) revert InvalidAmount();

        // Update vault
        vault.totalLiquidity += amount;
        vault.reservedLiquidity += amount;

        emit BetDeposited(amount, vault.reservedLiquidity, block.timestamp);
    }

    /**
     * @notice Execute payout when user wins
     * @param user User address
     * @param amount Payout amount
     */
    function executePayout(
        address user,
        uint256 amount
    ) external nonReentrant onlyBinaryBet {
        if (amount == 0) return;
        if (amount > vault.totalLiquidity) revert InsufficientLiquidity();

        // Update vault
        vault.totalLiquidity -= amount;

        // Transfer native token to user
        (bool success, ) = user.call{value: amount}("");
        if (!success) revert TransferFailed();

        emit PayoutExecuted(user, amount, block.timestamp);
    }

    /**
     * @notice Update vault P&L after settlement
     * @param betAmount Original bet amount
     * @param userWon True if user won
     * @param payout Payout amount to user
     */
    function updateVaultPnL(
        uint256 betAmount,
        bool userWon,
        uint256 payout
    ) external nonReentrant onlyBinaryBet {
        // Update stats
        vault.totalVolume += betAmount;
        vault.totalPositionsSettled++;

        // Unreserve liquidity
        if (vault.reservedLiquidity >= betAmount) {
            vault.reservedLiquidity -= betAmount;
        }

        // Update active liquidity
        vault.activeLiquidity = vault.totalLiquidity - vault.reservedLiquidity;

        // Update P&L
        if (userWon) {
            // Vault loses (paid out more than received)
            uint256 loss = payout > betAmount ? payout - betAmount : 0;

            if (vault.isNegativePnL) {
                // Already negative, increase loss
                vault.lifetimePnL += loss;
            } else {
                // Currently positive
                if (loss >= vault.lifetimePnL) {
                    vault.lifetimePnL = loss - vault.lifetimePnL;
                    vault.isNegativePnL = true;
                } else {
                    vault.lifetimePnL -= loss;
                }
            }
        } else {
            // Vault gains (kept the bet)
            uint256 gain = betAmount;

            if (vault.isNegativePnL) {
                // Currently negative
                if (gain >= vault.lifetimePnL) {
                    vault.lifetimePnL = gain - vault.lifetimePnL;
                    vault.isNegativePnL = false;
                } else {
                    vault.lifetimePnL -= gain;
                }
            } else {
                // Already positive, increase gain
                vault.lifetimePnL += gain;
            }
        }

        emit VaultPnLUpdated(
            betAmount,
            userWon,
            payout,
            vault.lifetimePnL,
            vault.isNegativePnL,
            block.timestamp
        );
    }

    /**
     * @notice Update vault P&L with leverage (Synthetic Leverage)
     * @dev Called by BinaryBet for leveraged positions
     * @param collateral Original collateral amount
     * @param vaultPnL Vault's P&L (opposite of user's P&L)
     * @param fee Fees collected (liquidation fee or house edge)
     * @param positionSize Position size (for leverage exposure tracking)
     */
    function updateVaultPnLWithLeverage(
        uint256 collateral,
        int256 vaultPnL,
        uint256 fee,
        uint256 positionSize
    ) external nonReentrant onlyBinaryBet {
        // Update stats
        vault.totalVolume += collateral;
        vault.totalPositionsSettled++;

        // Unreserve collateral
        if (vault.reservedLiquidity >= collateral) {
            vault.reservedLiquidity -= collateral;
        }

        // Reduce leverage exposure (position closed)
        if (positionSize > 0 && vault.totalLeverageExposure >= positionSize) {
            vault.totalLeverageExposure -= positionSize;
        }

        // Update active liquidity
        vault.activeLiquidity = vault.totalLiquidity - vault.reservedLiquidity;

        // Update lifetime P&L
        // vaultPnL is positive when vault gains, negative when vault loses
        if (vaultPnL > 0) {
            // Vault gains
            uint256 gain = uint256(vaultPnL) + fee; // Include fee in gain

            if (vault.isNegativePnL) {
                // Currently negative, reduce loss
                if (gain >= vault.lifetimePnL) {
                    // Flip to positive
                    vault.lifetimePnL = gain - vault.lifetimePnL;
                    vault.isNegativePnL = false;
                } else {
                    // Still negative, just reduce
                    vault.lifetimePnL -= gain;
                }
            } else {
                // Already positive, increase gain
                vault.lifetimePnL += gain;
            }
        } else if (vaultPnL < 0) {
            // Vault loses (user wins)
            uint256 loss = uint256(-vaultPnL);

            // Fee partially offsets loss
            if (fee >= loss) {
                // Fee covers loss completely, vault still gains
                uint256 netGain = fee - loss;

                if (vault.isNegativePnL) {
                    if (netGain >= vault.lifetimePnL) {
                        vault.lifetimePnL = netGain - vault.lifetimePnL;
                        vault.isNegativePnL = false;
                    } else {
                        vault.lifetimePnL -= netGain;
                    }
                } else {
                    vault.lifetimePnL += netGain;
                }
            } else {
                // Net loss
                uint256 netLoss = loss - fee;

                if (vault.isNegativePnL) {
                    // Already negative, increase loss
                    vault.lifetimePnL += netLoss;
                } else {
                    // Currently positive
                    if (netLoss >= vault.lifetimePnL) {
                        // Flip to negative
                        vault.lifetimePnL = netLoss - vault.lifetimePnL;
                        vault.isNegativePnL = true;
                    } else {
                        // Still positive, reduce
                        vault.lifetimePnL -= netLoss;
                    }
                }
            }
        } else {
            // vaultPnL == 0, just collect fee
            if (fee > 0) {
                if (vault.isNegativePnL) {
                    if (fee >= vault.lifetimePnL) {
                        vault.lifetimePnL = fee - vault.lifetimePnL;
                        vault.isNegativePnL = false;
                    } else {
                        vault.lifetimePnL -= fee;
                    }
                } else {
                    vault.lifetimePnL += fee;
                }
            }
        }

        emit VaultPnLUpdatedWithLeverage(
            collateral,
            vaultPnL,
            fee,
            vault.lifetimePnL,
            vault.isNegativePnL,
            block.timestamp
        );
    }

    // ========================================================================
    // RISK MANAGEMENT
    // ========================================================================

    /**
     * @notice Check if position can be opened (risk check)
     * @dev For leveraged positions, amount is position size (collateral × leverage)
     * @param amount Position size (for leverage) or collateral (for 1x leverage)
     * @return canOpen True if can open
     * @return reason Reason if cannot open
     */
    function checkPositionRisk(
        uint256 amount
    ) external view returns (bool canOpen, string memory reason) {
        // Check vault paused
        if (vault.isPaused) {
            return (false, "Vault is paused");
        }

        // Note: BinaryBet checks collateral limits, we check position size limits here

        // Check per-bet exposure (position size should not exceed % of active liquidity)
        uint256 maxPerBetExposure = (vault.activeLiquidity *
            vaultParams.perBetUtilBps) / 10000;
        if (amount > maxPerBetExposure) {
            return (false, "Position size exceeds per-bet limit");
        }

        // Check total leverage exposure
        uint256 maxTotalExposure = (vault.totalLiquidity *
            vaultParams.maxLeverageExposureBps) / 10000;
        if (vault.totalLeverageExposure + amount > maxTotalExposure) {
            return (false, "Exceeds total leverage exposure limit");
        }

        // Check sufficient active liquidity
        // For synthetic leverage, we don't actually need to reserve the full position size
        // But we check if vault can theoretically cover the max loss
        if (amount > vault.totalLiquidity) {
            return (false, "Position size exceeds vault capacity");
        }

        return (true, "");
    }

    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================

    /**
     * @notice Update vault parameters
     */
    function updateVaultParams(
        uint16 _maxPayoutBps,
        uint16 _perBetUtilBps,
        uint16 _maxUtilizationBps,
        uint256 _minBetAmount,
        uint256 _maxBetAmount,
        uint16 _maxLeverageExposureBps
    ) external onlyOwner {
        // Validate
        if (_maxPayoutBps > 5000) revert InvalidConfig(); // Max 50%
        if (_perBetUtilBps > 5000) revert InvalidConfig(); // Max 50%
        if (_maxUtilizationBps > 10000) revert InvalidConfig(); // Max 100%
        if (_minBetAmount == 0) revert InvalidConfig();
        if (_maxBetAmount < _minBetAmount) revert InvalidConfig();
        if (_maxLeverageExposureBps > 50000) revert InvalidConfig(); // Max 500% (5:1 leverage ratio)

        vaultParams.maxPayoutBps = _maxPayoutBps;
        vaultParams.perBetUtilBps = _perBetUtilBps;
        vaultParams.maxUtilizationBps = _maxUtilizationBps;
        vaultParams.minBetAmount = _minBetAmount;
        vaultParams.maxBetAmount = _maxBetAmount;
        vaultParams.maxLeverageExposureBps = _maxLeverageExposureBps;

        emit VaultParamsUpdated(
            _maxPayoutBps,
            _perBetUtilBps,
            _maxUtilizationBps,
            _minBetAmount,
            _maxBetAmount
        );
    }

    /**
     * @notice Toggle vault pause
     */
    function setVaultPaused(bool _paused) external onlyOwner {
        vault.isPaused = _paused;
        emit VaultPausedToggled(_paused);
    }

    /**
     * @notice Set BinaryBet contract address
     */
    function setBinaryBetContract(
        address _binaryBetContract
    ) external onlyOwner {
        if (_binaryBetContract == address(0)) revert InvalidAddress();
        address oldAddress = binaryBetContract;
        binaryBetContract = _binaryBetContract;
        emit BinaryBetContractUpdated(oldAddress, _binaryBetContract);
    }

    /**
     * @notice Set SettlementEngine address
     */
    function setSettlementEngine(address _settlementEngine) external onlyOwner {
        if (_settlementEngine == address(0)) revert InvalidAddress();
        address oldAddress = settlementEngine;
        settlementEngine = _settlementEngine;
        emit SettlementEngineUpdated(oldAddress, _settlementEngine);
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

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /**
     * @notice Get vault info
     */
    function getVaultInfo() external view returns (VaultInfo memory) {
        return vault;
    }

    /**
     * @notice Get vault params
     */
    function getVaultParams() external view returns (VaultParams memory) {
        return vaultParams;
    }

    /**
     * @notice Get LP position
     */
    function getLPPosition(
        address user
    ) external view returns (LPPosition memory) {
        return lpPositions[user];
    }

    /**
     * @notice Calculate LP value (current worth in native token)
     * @param user LP user address
     * @return value Current value of LP's shares
     */
    function calculateLPValue(
        address user
    ) external view returns (uint256 value) {
        LPPosition memory lpPos = lpPositions[user];
        if (lpPos.shares == 0 || vault.totalShares == 0) {
            return 0;
        }
        return (lpPos.shares * vault.totalLiquidity) / vault.totalShares;
    }

    /**
     * @notice Get vault utilization (%)
     * @return utilization Utilization in bps (e.g., 5000 = 50%)
     */
    function getVaultUtilization() external view returns (uint256 utilization) {
        if (vault.totalLiquidity == 0) return 0;
        return (vault.reservedLiquidity * 10000) / vault.totalLiquidity;
    }

    /**
     * @notice Get leverage exposure ratio
     * @return exposureRatio Leverage exposure vs liquidity in bps (e.g., 10000 = 100%)
     */
    function getLeverageExposureRatio()
        external
        view
        returns (uint256 exposureRatio)
    {
        if (vault.totalLiquidity == 0) return 0;
        return (vault.totalLeverageExposure * 10000) / vault.totalLiquidity;
    }

    /**
     * @notice Get total TVL (Total Value Locked) - alias for totalLiquidity
     * @return tvl Total liquidity in vault
     */
    function getTotalTVL() external view returns (uint256 tvl) {
        return vault.totalLiquidity;
    }

    /**
     * @notice Get leverage stats
     * @return totalExposure Total leverage exposure
     * @return maxExposure Max leverage exposure reached
     * @return currentRatio Current exposure ratio in bps
     * @return maxAllowedRatio Max allowed ratio in bps
     */
    function getLeverageStats()
        external
        view
        returns (
            uint256 totalExposure,
            uint256 maxExposure,
            uint256 currentRatio,
            uint256 maxAllowedRatio
        )
    {
        totalExposure = vault.totalLeverageExposure;
        maxExposure = vault.maxLeverageExposure;

        if (vault.totalLiquidity == 0) {
            currentRatio = 0;
        } else {
            currentRatio =
                (vault.totalLeverageExposure * 10000) /
                vault.totalLiquidity;
        }

        maxAllowedRatio = vaultParams.maxLeverageExposureBps;
    }

    /**
     * @notice Get number of LPs
     */
    function getLPCount() external view returns (uint256) {
        return vaultLPs.length;
    }

    /**
     * @notice Get contract version
     */
    function version() external pure returns (string memory) {
        return "3.0.0-synthetic-leverage";
    }
}
