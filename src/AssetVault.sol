// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title AssetVault
 * @notice Individual vault for a specific token (native or ERC20)
 * @dev Handles liquidity management, LP positions, and P&L tracking for one token - Non-upgradeable
 *
 * Features:
 * - LP staking/unstaking with share-based accounting
 * - Collateral management for betting positions
 * - P&L tracking with leveraged positions
 * - Risk management per vault
 * - Support for both native token and ERC20 tokens
 */
contract AssetVault is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ========================================================================
    // STATE VARIABLES
    // ========================================================================

    /// @notice VaultManager contract address (factory)
    address public vaultManager;

    /// @notice PositionManager contract address
    address public positionManager;

    /// @notice Token address for this vault (address(0) for native token)
    address public tokenAddress;

    /// @notice Vault information
    VaultInfo public vaultInfo;

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
        uint256 totalLiquidity; // Total tokens in vault
        uint256 activeLiquidity; // Available for betting
        uint256 reservedLiquidity; // Reserved for open positions
        uint256 totalShares; // Total LP shares
        uint256 lifetimePnL; // Lifetime profit/loss (absolute value)
        bool isNegativePnL; // True if P&L is negative
        uint256 totalVolume; // Total volume traded (collateral)
        uint256 totalPositionsSettled; // Total positions settled
        uint256 totalLeverageExposure; // Total leverage exposure (position sizes)
        uint256 maxLeverageExposure; // Max leverage exposure at any time
        uint256 createdAt; // Creation timestamp
    }

    struct VaultParams {
        uint16 maxPayoutBps; // Max payout % per bet (e.g., 500 = 5%)
        uint16 perBetUtilBps; // Max utilization per bet (e.g., 1000 = 10%)
        uint16 maxUtilizationBps; // Max total utilization (e.g., 8000 = 80%)
        uint256 minBetAmount; // Min bet amount (collateral)
        uint256 maxBetAmount; // Max bet amount (collateral)
        uint16 maxLeverageExposureBps; // Max leverage exposure vs liquidity (e.g., 10000 = 100%)
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
    // CONSTANTS
    // ========================================================================

    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant INITIAL_SHARE_MULTIPLIER = 1e18;

    // ========================================================================
    // EVENTS
    // ========================================================================

    event VaultInitialized(address indexed tokenAddress, uint256 timestamp);

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

    event CollateralDeposited(
        uint256 amount,
        uint256 positionSize,
        uint256 newReserved,
        uint256 timestamp
    );

    event PayoutExecuted(
        address indexed user,
        uint256 amount,
        uint256 timestamp
    );

    event VaultPnLUpdated(
        uint256 collateral,
        int256 vaultPnL,
        uint256 fee,
        uint256 newLifetimePnL,
        bool isNegative,
        uint256 timestamp
    );

    event LeverageExposureUpdated(
        uint256 newExposure,
        uint256 maxExposure,
        uint256 timestamp
    );

    event VaultParamsUpdated(
        uint16 maxPayoutBps,
        uint16 perBetUtilBps,
        uint16 maxUtilizationBps,
        uint256 timestamp
    );

    // ========================================================================
    // ERRORS
    // ========================================================================

    error InvalidAddress();
    error InvalidAmount();
    error InsufficientLiquidity();
    error InsufficientShares();
    error RiskLimitExceeded();
    error NotAuthorized();
    error InvalidParameters();
    error TransferFailed();
    error VaultPaused();

    // ========================================================================
    // MODIFIERS
    // ========================================================================

    modifier onlyPositionManager() {
        if (msg.sender != positionManager) revert NotAuthorized();
        _;
    }

    modifier onlyVaultManager() {
        if (msg.sender != vaultManager) revert NotAuthorized();
        _;
    }

    modifier whenVaultNotPaused() {
        if (paused()) revert VaultPaused();
        _;
    }

    // ========================================================================
    // CONSTRUCTOR
    // ========================================================================

    /**
     * @notice Constructor
     * @param _tokenAddress Token address (address(0) for native token)
     * @param _vaultManager VaultManager address
     * @param _positionManager PositionManager contract address
     * @param _maxPayoutBps Max payout in bps
     * @param _perBetUtilBps Per bet utilization in bps
     * @param _maxUtilizationBps Max utilization in bps
     * @param _minBetAmount Min bet amount
     * @param _maxBetAmount Max bet amount
     */
    constructor(
        address _tokenAddress,
        address _vaultManager,
        address _positionManager,
        uint16 _maxPayoutBps,
        uint16 _perBetUtilBps,
        uint16 _maxUtilizationBps,
        uint256 _minBetAmount,
        uint256 _maxBetAmount
    ) Ownable(msg.sender) {
        if (_vaultManager == address(0) || _positionManager == address(0))
            revert InvalidAddress();

        tokenAddress = _tokenAddress;
        vaultManager = _vaultManager;
        positionManager = _positionManager;

        vaultInfo.createdAt = block.timestamp;

        vaultParams = VaultParams({
            maxPayoutBps: _maxPayoutBps,
            perBetUtilBps: _perBetUtilBps,
            maxUtilizationBps: _maxUtilizationBps,
            minBetAmount: _minBetAmount,
            maxBetAmount: _maxBetAmount,
            maxLeverageExposureBps: 10000 // 100% default
        });

        emit VaultInitialized(_tokenAddress, block.timestamp);
    }

    // ========================================================================
    // RECEIVE / FALLBACK (for native token)
    // ========================================================================

    receive() external payable {
        // Accept native token transfers
    }

    fallback() external payable {}

    // ========================================================================
    // LP FUNCTIONS
    // ========================================================================

    /**
     * @notice Add liquidity to vault
     * @param amount Amount of tokens to add
     */
    function addLiquidity(
        uint256 amount
    ) external payable nonReentrant whenVaultNotPaused {
        if (amount == 0) revert InvalidAmount();

        // Handle token transfer
        if (tokenAddress == address(0)) {
            // Native token
            if (msg.value != amount) revert InvalidAmount();
        } else {
            // ERC20 token
            if (msg.value != 0) revert InvalidAmount();
            IERC20(tokenAddress).safeTransferFrom(
                msg.sender,
                address(this),
                amount
            );
        }

        // Calculate shares
        uint256 shares;
        if (vaultInfo.totalShares == 0) {
            // First deposit
            shares = amount * INITIAL_SHARE_MULTIPLIER;
        } else {
            // Subsequent deposits: shares = (amount * totalShares) / totalLiquidity
            shares =
                (amount * vaultInfo.totalShares) /
                vaultInfo.totalLiquidity;
        }

        if (shares == 0) revert InvalidAmount();

        // Update LP position
        LPPosition storage lpPos = lpPositions[msg.sender];
        if (lpPos.user == address(0)) {
            // New LP
            lpPos.user = msg.sender;
            lpPos.stakedAt = block.timestamp;
            vaultLPs.push(msg.sender);
        }

        lpPos.shares += shares;
        lpPos.stakedAmount += amount;

        // Update vault info
        vaultInfo.totalLiquidity += amount;
        vaultInfo.activeLiquidity += amount;
        vaultInfo.totalShares += shares;

        emit LiquidityAdded(
            msg.sender,
            amount,
            shares,
            vaultInfo.totalLiquidity,
            block.timestamp
        );
    }

    /**
     * @notice Remove liquidity from vault
     * @param shares Amount of shares to burn
     */
    function removeLiquidity(
        uint256 shares
    ) external nonReentrant whenVaultNotPaused {
        if (shares == 0) revert InvalidAmount();

        LPPosition storage lpPos = lpPositions[msg.sender];
        if (lpPos.shares < shares) revert InsufficientShares();

        // Calculate amount: amount = (shares * totalLiquidity) / totalShares
        uint256 amount = (shares * vaultInfo.totalLiquidity) /
            vaultInfo.totalShares;

        if (amount > vaultInfo.activeLiquidity) revert InsufficientLiquidity();

        // Update LP position
        lpPos.shares -= shares;
        if (lpPos.stakedAmount > amount) {
            lpPos.stakedAmount -= amount;
        } else {
            lpPos.stakedAmount = 0;
        }

        // Update vault info
        vaultInfo.totalLiquidity -= amount;
        vaultInfo.activeLiquidity -= amount;
        vaultInfo.totalShares -= shares;

        // Transfer tokens
        if (tokenAddress == address(0)) {
            // Native token
            (bool success, ) = msg.sender.call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            // ERC20 token
            IERC20(tokenAddress).safeTransfer(msg.sender, amount);
        }

        emit LiquidityRemoved(
            msg.sender,
            amount,
            shares,
            vaultInfo.totalLiquidity,
            block.timestamp
        );
    }

    // ========================================================================
    // BETTING FUNCTIONS (called by PositionManager)
    // ========================================================================

    /**
     * @notice Deposit collateral from bet
     * @param amount Collateral amount
     * @param positionSize Position size (amount * leverage)
     */
    function depositFromBet(
        uint256 amount,
        uint256 positionSize
    ) external payable onlyPositionManager nonReentrant {
        if (amount == 0) revert InvalidAmount();

        // Handle token transfer
        if (tokenAddress == address(0)) {
            // Native token
            if (msg.value != amount) revert InvalidAmount();
        } else {
            // ERC20 token - already transferred by PositionManager
            if (msg.value != 0) revert InvalidAmount();
        }

        // Update vault state
        vaultInfo.totalLiquidity += amount;
        vaultInfo.reservedLiquidity += amount;
        vaultInfo.totalVolume += amount;

        // Update leverage exposure
        vaultInfo.totalLeverageExposure += positionSize;
        if (vaultInfo.totalLeverageExposure > vaultInfo.maxLeverageExposure) {
            vaultInfo.maxLeverageExposure = vaultInfo.totalLeverageExposure;
        }

        emit CollateralDeposited(
            amount,
            positionSize,
            vaultInfo.reservedLiquidity,
            block.timestamp
        );

        emit LeverageExposureUpdated(
            vaultInfo.totalLeverageExposure,
            vaultInfo.maxLeverageExposure,
            block.timestamp
        );
    }

    /**
     * @notice Execute payout to user
     * @param user User address
     * @param amount Payout amount
     */
    function executePayout(
        address user,
        uint256 amount
    ) external onlyPositionManager nonReentrant {
        if (user == address(0)) revert InvalidAddress();
        if (amount == 0) return; // No payout

        if (amount > vaultInfo.totalLiquidity) revert InsufficientLiquidity();

        // Update vault state
        vaultInfo.totalLiquidity -= amount;
        if (vaultInfo.reservedLiquidity >= amount) {
            vaultInfo.reservedLiquidity -= amount;
        } else {
            vaultInfo.reservedLiquidity = 0;
        }

        // Transfer tokens
        if (tokenAddress == address(0)) {
            // Native token
            (bool success, ) = user.call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            // ERC20 token
            IERC20(tokenAddress).safeTransfer(user, amount);
        }

        emit PayoutExecuted(user, amount, block.timestamp);
    }

    /**
     * @notice Update vault P&L after position settlement
     * @param collateral Collateral amount
     * @param vaultPnL Vault P&L (negative of user P&L)
     * @param fee Fee collected
     * @param positionSize Position size to remove from exposure
     */
    function updateVaultPnL(
        uint256 collateral,
        int256 vaultPnL,
        uint256 fee,
        uint256 positionSize
    ) external onlyPositionManager {
        // Update lifetime P&L
        if (vaultPnL >= 0) {
            // Vault gained
            uint256 gain = uint256(vaultPnL);
            if (vaultInfo.isNegativePnL) {
                if (gain >= vaultInfo.lifetimePnL) {
                    vaultInfo.lifetimePnL = gain - vaultInfo.lifetimePnL;
                    vaultInfo.isNegativePnL = false;
                } else {
                    vaultInfo.lifetimePnL -= gain;
                }
            } else {
                vaultInfo.lifetimePnL += gain;
            }
        } else {
            // Vault lost
            uint256 loss = uint256(-vaultPnL);
            if (vaultInfo.isNegativePnL) {
                vaultInfo.lifetimePnL += loss;
            } else {
                if (loss >= vaultInfo.lifetimePnL) {
                    vaultInfo.lifetimePnL = loss - vaultInfo.lifetimePnL;
                    vaultInfo.isNegativePnL = true;
                } else {
                    vaultInfo.lifetimePnL -= loss;
                }
            }
        }

        // Update reserved liquidity
        if (vaultInfo.reservedLiquidity >= collateral) {
            vaultInfo.reservedLiquidity -= collateral;
        } else {
            vaultInfo.reservedLiquidity = 0;
        }

        // Update active liquidity
        vaultInfo.activeLiquidity =
            vaultInfo.totalLiquidity -
            vaultInfo.reservedLiquidity;

        // Update leverage exposure
        if (vaultInfo.totalLeverageExposure >= positionSize) {
            vaultInfo.totalLeverageExposure -= positionSize;
        } else {
            vaultInfo.totalLeverageExposure = 0;
        }

        // Update positions settled
        vaultInfo.totalPositionsSettled++;

        emit VaultPnLUpdated(
            collateral,
            vaultPnL,
            fee,
            vaultInfo.lifetimePnL,
            vaultInfo.isNegativePnL,
            block.timestamp
        );

        emit LeverageExposureUpdated(
            vaultInfo.totalLeverageExposure,
            vaultInfo.maxLeverageExposure,
            block.timestamp
        );
    }

    // ========================================================================
    // RISK MANAGEMENT
    // ========================================================================

    /**
     * @notice Check if position can be opened (risk check)
     * @param positionSize Position size (collateral * leverage)
     * @param leverage Leverage multiplier
     * @return canOpen Whether position can be opened
     * @return reason Reason if cannot open
     */
    function checkPositionRisk(
        uint256 positionSize,
        uint8 leverage
    ) external view returns (bool canOpen, string memory reason) {
        // Check if vault is paused
        if (paused()) {
            return (false, "Vault is paused");
        }

        // Check min/max bet amount (based on collateral)
        // collateral = positionSize / leverage
        uint256 collateral = leverage > 0
            ? positionSize / leverage
            : positionSize;
        if (collateral < vaultParams.minBetAmount) {
            return (false, "Below minimum bet amount");
        }
        if (collateral > vaultParams.maxBetAmount) {
            return (false, "Exceeds maximum bet amount");
        }

        // Check per-bet utilization
        uint256 maxPerBetUtil = (vaultInfo.activeLiquidity *
            vaultParams.perBetUtilBps) / BASIS_POINTS;
        if (positionSize > maxPerBetUtil) {
            return (false, "Exceeds per-bet utilization limit");
        }

        // Check total utilization
        uint256 maxTotalUtil = (vaultInfo.totalLiquidity *
            vaultParams.maxUtilizationBps) / BASIS_POINTS;
        if (vaultInfo.reservedLiquidity + collateral > maxTotalUtil) {
            return (false, "Exceeds total utilization limit");
        }

        // Check leverage exposure
        uint256 maxLevExposure = (vaultInfo.totalLiquidity *
            vaultParams.maxLeverageExposureBps) / BASIS_POINTS;
        if (vaultInfo.totalLeverageExposure + positionSize > maxLevExposure) {
            return (false, "Exceeds leverage exposure limit");
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
        if (
            _maxPayoutBps > BASIS_POINTS ||
            _perBetUtilBps > BASIS_POINTS ||
            _maxUtilizationBps > BASIS_POINTS ||
            _maxLeverageExposureBps > BASIS_POINTS
        ) revert InvalidParameters();

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
            block.timestamp
        );
    }

    /**
     * @notice Set PositionManager contract address
     */
    function setPositionManager(address _positionManager) external onlyOwner {
        if (_positionManager == address(0)) revert InvalidAddress();
        positionManager = _positionManager;
    }

    /**
     * @notice Pause vault
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause vault
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /**
     * @notice Get LP position
     */
    function getLPPosition(
        address user
    ) external view returns (LPPosition memory) {
        return lpPositions[user];
    }

    /**
     * @notice Get vault info
     */
    function getVaultInfo() external view returns (VaultInfo memory) {
        return vaultInfo;
    }

    /**
     * @notice Get vault parameters
     */
    function getVaultParams() external view returns (VaultParams memory) {
        return vaultParams;
    }

    /**
     * @notice Get all LPs
     */
    function getAllLPs() external view returns (address[] memory) {
        return vaultLPs;
    }

    /**
     * @notice Calculate share value
     * @param shares Number of shares
     * @return value Value in tokens
     */
    function calculateShareValue(
        uint256 shares
    ) external view returns (uint256 value) {
        if (vaultInfo.totalShares == 0) return 0;
        return (shares * vaultInfo.totalLiquidity) / vaultInfo.totalShares;
    }

    /**
     * @notice Get vault utilization rate
     * @return utilizationBps Utilization rate in basis points
     */
    function getUtilizationRate()
        external
        view
        returns (uint256 utilizationBps)
    {
        if (vaultInfo.totalLiquidity == 0) return 0;
        return
            (vaultInfo.reservedLiquidity * BASIS_POINTS) /
            vaultInfo.totalLiquidity;
    }
}
