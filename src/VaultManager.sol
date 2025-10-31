// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IAssetVault.sol";
import "./AssetVault.sol";

/**
 * @title VaultManager
 * @notice Factory contract to create and manage multiple AssetVault instances
 * @dev Manages vaults for individual project tokens with Blocksense Oracle - UUPS Upgradeable
 *
 * NEW FEATURES:
 * - Create vaults for individual project tokens (one vault per project token)
 * - Each vault accepts both MON and project token
 * - Traders can use either MON or project token to bet
 * - Multiple positions allowed per user per project token
 * - Partial liquidity system support
 * - Blocksense Oracle integration
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

    /// @notice PositionManager contract address
    address public positionManager;

    /// @notice SettlementEngine contract address
    address public settlementEngine;

    /// @notice BlocksenseOracle contract address
    address public blocksenseOracle;

    /// @notice Mapping: projectToken => vault address
    /// @dev One vault per project token
    mapping(address => address) public vaultsByProjectToken;

    /// @notice Array of all vault addresses
    address[] public allVaults;

    /// @notice Mapping: vault address => is valid vault
    mapping(address => bool) public isValidVault;

    /// @notice Mapping: vault address => project token
    mapping(address => address) public vaultProjectToken;

    // ========================================================================
    // STORAGE GAP (for future upgrades)
    // ========================================================================

    /// @dev Storage gap to allow for new variables in future versions
    /// @notice Currently using 7 storage slots (added blocksenseOracle), reserving 43 slots for future use
    uint256[43] private __gap;

    // ========================================================================
    // EVENTS
    // ========================================================================

    event VaultCreated(address indexed projectToken, address vaultAddress, uint256 timestamp);

    event PositionManagerUpdated(address indexed oldAddress, address indexed newAddress);

    event SettlementEngineUpdated(address indexed oldAddress, address indexed newAddress);

    event BlocksenseOracleUpdated(address indexed oldAddress, address indexed newAddress);

    event CollateralDepositedFromBet(
        address indexed vault,
        address indexed projectToken,
        uint256 amount,
        uint256 positionSize,
        uint256 timestamp
    );

    // ========================================================================
    // ERRORS
    // ========================================================================

    error InvalidAddress();
    error VaultAlreadyExists();
    error VaultNotFound();
    error NotAuthorized();
    error NotPositionManager();
    error NotSettlementEngine();
    error DuplicatePriceFeedId();
    error DuplicateProjectToken();
    error InvalidAmount();
    error InvalidPriceFeedId();
    error TransferFailed();
    error DirectTransferNotAllowed();

    // ========================================================================
    // MODIFIERS
    // ========================================================================

    modifier onlyPositionManager() {
        if (msg.sender != positionManager) revert NotPositionManager();
        _;
    }

    modifier onlySettlementEngine() {
        if (msg.sender != settlementEngine) revert NotSettlementEngine();
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
     * @notice Initialize contract (replaces constructor)
     * @param initialOwner Owner address
     */
    function initialize(address initialOwner) public initializer {
        if (initialOwner == address(0)) revert InvalidAddress();

        __Ownable_init(initialOwner);
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
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
    // VAULT CREATION
    // ========================================================================

    /**
     * @notice Create new vault for a project token
     * @param _projectToken Project token address
     * @param _minBetAmount Min bet amount
     * @param _maxBetAmount Max bet amount
     * @param _graduationThreshold Token amount threshold for graduation
     * @return vaultAddress Address of created vault
     */
    function createVault(
        address _projectToken,
        address _oracleAdapter,
        uint256 _minBetAmount,
        uint256 _maxBetAmount,
        uint256 _graduationThreshold
    ) external onlyOwner returns (address vaultAddress) {
        if (_projectToken == address(0)) revert InvalidAddress();
        if (_oracleAdapter == address(0)) revert InvalidAddress();

        if (vaultsByProjectToken[_projectToken] != address(0)) {
            revert DuplicateProjectToken();
        }

        // Note: oracleAdapter will be set separately after vault creation
        // by calling setVaultOracleAdapter() with the appropriate adapter address
        AssetVault vault = new AssetVault(
            _projectToken,
            address(this),
            positionManager,
            blocksenseOracle,
            _oracleAdapter,
            _minBetAmount,
            _maxBetAmount,
            _graduationThreshold
        );

        vaultAddress = address(vault);

        // Register vault
        vaultsByProjectToken[_projectToken] = vaultAddress;
        allVaults.push(vaultAddress);
        isValidVault[vaultAddress] = true;
        vaultProjectToken[vaultAddress] = _projectToken;

        emit VaultCreated(_projectToken, vaultAddress, block.timestamp);

        return vaultAddress;
    }

    // ========================================================================
    // VAULT MANAGEMENT
    // ========================================================================

    /**
     * @notice Get vault address for a project token
     * @param _projectToken Project token address
     * @return vaultAddress Vault address
     */
    function getVault(address _projectToken) external view returns (address vaultAddress) {
        vaultAddress = vaultsByProjectToken[_projectToken];
        if (vaultAddress == address(0)) revert VaultNotFound();
        return vaultAddress;
    }

    /**
     * @notice Get project token for a vault
     * @param _vaultAddress Vault address
     * @return projectToken Project token address
     */
    function getVaultProjectToken(address _vaultAddress)
        external
        view
        returns (address projectToken)
    {
        return vaultProjectToken[_vaultAddress];
    }

    /**
     * @notice Check if vault is supported for a project token
     * @param _projectToken Project token address
     * @return supported Whether vault is supported
     */
    function isVaultSupported(address _projectToken) external view returns (bool supported) {
        return vaultsByProjectToken[_projectToken] != address(0);
    }

    /**
     * @notice Get all vaults
     * @return Array of vault addresses
     */
    function getAllVaults() external view returns (address[] memory) {
        return allVaults;
    }

    // ========================================================================
    // PROXY FUNCTIONS (Route to specific vaults)
    // ========================================================================

    /**
     * @notice Check position risk for a vault
     * @param _projectToken Project token address
     * @param positionSize Position size
     * @param leverage Leverage multiplier
     * @return canOpen Whether position can be opened
     * @return reason Reason if cannot open
     */
    function checkPositionRisk(address _projectToken, uint256 positionSize, uint8 leverage)
        external
        view
        returns (bool canOpen, string memory reason)
    {
        address vaultAddress = vaultsByProjectToken[_projectToken];
        if (vaultAddress == address(0)) {
            return (false, "Vault not found");
        }

        return IAssetVault(vaultAddress).checkPositionRisk(positionSize, leverage);
    }

    /**
     * @notice Deposit collateral from bet (v1: project token only)
     * @param _projectToken Project token address
     * @param positionId Position ID
     * @param amount Collateral amount in project tokens
     * @param positionSize Position size
     * @param isMarginAdd True if adding margin to existing position
     */
    function depositFromBet(
        address _projectToken,
        uint64 positionId,
        uint256 amount,
        uint256 positionSize,
        bool isMarginAdd
    ) external payable onlyPositionManager {
        address vaultAddress = vaultsByProjectToken[_projectToken];
        if (vaultAddress == address(0)) revert VaultNotFound();

        if (vaultAddress.code.length == 0) revert VaultNotFound();

        IAssetVault(vaultAddress).depositFromBet{ value: msg.value }(
            positionId, amount, positionSize, isMarginAdd
        );

        emit CollateralDepositedFromBet(
            vaultAddress, _projectToken, amount, positionSize, block.timestamp
        );
    }

    /**
     * @notice Execute payout to user (v1: project token only)
     * @param _projectToken Project token address
     * @param user User address
     * @param amount Payout amount in project tokens
     * @param positionId Position ID for tracking partial payouts
     */
    function executePayout(address _projectToken, address user, uint256 amount, uint64 positionId)
        external
        onlyPositionManager
    {
        address vaultAddress = vaultsByProjectToken[_projectToken];
        if (vaultAddress == address(0)) revert VaultNotFound();

        IAssetVault(vaultAddress).executePayout(user, amount, positionId);
    }

    /**
     * @notice Update vault P&L
     * @param _projectToken Project token address
     * @param positionId Position ID (for tracking)
     * @param collateral Collateral amount
     * @param vaultPnL Vault P&L
     * @param fee Fee collected
     * @param positionSize Position size
     */
    function updateVaultPnLWithLeverage(
        address _projectToken,
        uint64 positionId,
        uint256 collateral,
        int256 vaultPnL,
        uint256 fee,
        uint256 positionSize
    ) external onlyPositionManager {
        address vaultAddress = vaultsByProjectToken[_projectToken];
        if (vaultAddress == address(0)) revert VaultNotFound();

        IAssetVault(vaultAddress).updateVaultPnL(
            positionId, collateral, vaultPnL, fee, positionSize
        );
    }

    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================

    /**
     * @notice Set PositionManager contract address
     */
    function setPositionManager(address _positionManager) external onlyOwner {
        if (_positionManager == address(0)) revert InvalidAddress();
        address oldAddress = positionManager;
        positionManager = _positionManager;
        emit PositionManagerUpdated(oldAddress, _positionManager);
    }

    /**
     * @notice Set SettlementEngine contract address
     */
    function setSettlementEngine(address _settlementEngine) external onlyOwner {
        if (_settlementEngine == address(0)) revert InvalidAddress();
        address oldAddress = settlementEngine;
        settlementEngine = _settlementEngine;
        emit SettlementEngineUpdated(oldAddress, _settlementEngine);
    }

    /**
     * @notice Set BlocksenseOracle contract address
     */
    function setBlocksenseOracle(address _blocksenseOracle) external onlyOwner {
        if (_blocksenseOracle == address(0)) revert InvalidAddress();
        address oldAddress = blocksenseOracle;
        blocksenseOracle = _blocksenseOracle;
        emit BlocksenseOracleUpdated(oldAddress, _blocksenseOracle);
    }

    /**
     * @notice Pause factory (prevents new vault creation)
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause factory
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // ========================================================================
    // VAULT ADMIN PROXY FUNCTIONS
    // ========================================================================
    /**
     * @notice Pause a specific vault
     * @param _projectToken Project token address
     * @dev Only callable by owner, forwards call to vault
     */
    function pauseVault(address _projectToken) external onlyOwner {
        address vaultAddress = vaultsByProjectToken[_projectToken];
        if (vaultAddress == address(0)) revert VaultNotFound();

        IAssetVault(vaultAddress).pause();
    }

    /**
     * @notice Unpause a specific vault
     * @param _projectToken Project token address
     * @dev Only callable by owner, forwards call to vault
     */
    function unpauseVault(address _projectToken) external onlyOwner {
        address vaultAddress = vaultsByProjectToken[_projectToken];
        if (vaultAddress == address(0)) revert VaultNotFound();

        IAssetVault(vaultAddress).unpause();
    }

    /**
     * @notice Update vault parameters
     * @param _projectToken Project token address
     * @param _minBetAmount Min bet amount
     * @param _maxBetAmount Max bet amount
     * @param _maxPositionSizePercentBps Max position size percent in basis points
     */
    function updateVaultParams(
        address _projectToken,
        uint256 _minBetAmount,
        uint256 _maxBetAmount,
        uint16 _maxPositionSizePercentBps
    ) external onlyOwner {
        address vaultAddress = vaultsByProjectToken[_projectToken];
        if (vaultAddress == address(0)) revert VaultNotFound();

        IAssetVault(vaultAddress).updateVaultParams(
            _minBetAmount, _maxBetAmount, uint16(_maxPositionSizePercentBps)
        );
    }

    /**
     * @notice Set oracle adapter for a vault
     * @param _projectToken Project token address
     * @param _oracleAdapter Oracle adapter address
     * @dev Only callable by owner, forwards call to vault
     */
    function setVaultOracleAdapter(address _projectToken, address _oracleAdapter)
        external
        onlyOwner
    {
        address vaultAddress = vaultsByProjectToken[_projectToken];
        if (vaultAddress == address(0)) revert VaultNotFound();

        IAssetVault(vaultAddress).setOracleAdapter(_oracleAdapter);
    }

    /**
     * @notice Authorize upgrade (UUPS pattern)
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

    /**
     * @notice Get contract version
     */
    function version() external pure returns (string memory) {
        return "1.0.0-vault-manager";
    }
}
