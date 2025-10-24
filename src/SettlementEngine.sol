// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

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

    /// @notice BinaryBet contract address
    address public binaryBetContract;

    /// @notice VaultManager contract address
    address public vaultManager;

    /// @notice Settlement history
    SettlementRecord[] public settlementHistory;

    // ========================================================================
    // STRUCTS
    // ========================================================================

    struct SettlementRecord {
        uint64 positionId;
        address user;
        uint256 amount;
        uint256 payout;
        uint256 fee;
        bool won;
        uint256 timestamp;
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

    event BinaryBetContractUpdated(
        address indexed oldAddress,
        address indexed newAddress
    );
    event VaultManagerUpdated(
        address indexed oldAddress,
        address indexed newAddress
    );

    // ========================================================================
    // ERRORS
    // ========================================================================

    error InvalidConfig();
    error InvalidAmount();
    error InvalidAddress();
    error NotBinaryBet();

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
        houseEdgeBps = 500; // 5%
        winMultiplierBps = 19500; // 1.95x
        minBetAmount = 0.001 ether; // 0.001 MON
        maxBetAmount = 1000 ether; // 1000 MON
    }

    // ========================================================================
    // SETTLEMENT FUNCTIONS
    // ========================================================================

    /**
     * @notice Calculate payout for position
     * @param amount Bet amount
     * @param direction Bet direction (not used in current formula)
     * @param openPrice Open price (not used in current formula)
     * @param closePrice Close price (not used in current formula)
     * @return payout Net payout to user
     */
    function calculatePayout(
        uint256 amount,
        uint8 direction,
        uint256 openPrice,
        uint256 closePrice
    ) external view whenNotPaused returns (uint256 payout) {
        // Simplified: Does not consider direction, openPrice, closePrice
        // Assume user wins, calculate payout

        // Gross payout = amount * multiplier
        uint256 grossPayout = (amount * winMultiplierBps) / 10000;

        // House edge = grossPayout * houseEdge%
        uint256 houseEdge = (grossPayout * houseEdgeBps) / 10000;

        // Net payout = grossPayout - houseEdge
        payout = grossPayout - houseEdge;

        return payout;
    }

    /**
     * @notice Calculate full settlement details
     * @param amount Bet amount
     * @param direction Bet direction
     * @param openPrice Open price
     * @param closePrice Close price
     * @return won True if user won
     * @return payout Net payout
     * @return fee House edge fee
     */
    function calculateSettlement(
        uint256 amount,
        uint8 direction,
        uint256 openPrice,
        uint256 closePrice
    )
        external
        view
        whenNotPaused
        returns (bool won, uint256 payout, uint256 fee)
    {
        // Determine win/loss
        // direction: 1 = BET_DIRECTION_LONG, 2 = BET_DIRECTION_SHORT
        if (direction == 1) {
            won = closePrice > openPrice; // LONG wins if price goes up
        } else if (direction == 2) {
            won = closePrice < openPrice; // SHORT wins if price goes down
        } else {
            won = false;
        }

        if (won) {
            // User wins
            uint256 grossPayout = (amount * winMultiplierBps) / 10000;
            fee = (grossPayout * houseEdgeBps) / 10000;
            payout = grossPayout - fee;
        } else {
            // User loses
            payout = 0;
            fee = amount; // Vault keeps all
        }

        return (won, payout, fee);
    }

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
     * @notice Record settlement (called by BinaryBet)
     * @param positionId Position ID
     * @param user User address
     * @param amount Bet amount
     * @param payout Net payout
     * @param fee House edge fee
     * @param won True if user won
     */
    function recordSettlement(
        uint64 positionId,
        address user,
        uint256 amount,
        uint256 payout,
        uint256 fee,
        bool won
    ) external nonReentrant {
        if (msg.sender != binaryBetContract) revert NotBinaryBet();

        // Record settlement
        settlementHistory.push(
            SettlementRecord({
                positionId: positionId,
                user: user,
                amount: amount,
                payout: payout,
                fee: fee,
                won: won,
                timestamp: block.timestamp
            })
        );

        emit SettlementProcessed(
            positionId,
            user,
            amount,
            payout,
            fee,
            won,
            block.timestamp
        );
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
    function setBinaryBetContract(
        address _binaryBetContract
    ) external onlyOwner {
        if (_binaryBetContract == address(0)) revert InvalidAddress();
        address oldAddress = binaryBetContract;
        binaryBetContract = _binaryBetContract;
        emit BinaryBetContractUpdated(oldAddress, _binaryBetContract);
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
     * @notice Get settlement history count
     */
    function getSettlementHistoryCount() external view returns (uint256) {
        return settlementHistory.length;
    }

    /**
     * @notice Get settlement record
     */
    function getSettlementRecord(
        uint256 index
    ) external view returns (SettlementRecord memory) {
        return settlementHistory[index];
    }

    /**
     * @notice Get contract version
     */
    function version() external pure returns (string memory) {
        return "2.0.0-upgradeable-native";
    }
}
