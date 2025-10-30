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
    // EVENTS
    // ========================================================================

    event VaultCreated(
        address indexed projectToken,
        address vaultAddress,
        uint256 timestamp
    );

    event PositionManagerUpdated(
        address indexed oldAddress,
        address indexed newAddress
    );

    event SettlementEngineUpdated(
        address indexed oldAddress,
        address indexed newAddress
    );

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
        uint256 _minBetAmount,
        uint256 _maxBetAmount,
        uint256 _graduationThreshold
    ) external onlyOwner returns (address vaultAddress) {
        if (_projectToken == address(0)) revert InvalidAddress();

        if (vaultsByProjectToken[_projectToken] != address(0)) {
            revert DuplicateProjectToken();
        }

        AssetVault vault = new AssetVault(
            _projectToken,
            address(this),
            positionManager,
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
    function getVault(
        address _projectToken
    ) external view returns (address vaultAddress) {
        vaultAddress = vaultsByProjectToken[_projectToken];
        if (vaultAddress == address(0)) revert VaultNotFound();
        return vaultAddress;
    }

    /**
     * @notice Get vault address by project token (same as getVault but returns 0 if not found)
     * @param _projectToken Project token address
     * @return vaultAddress Vault address (address(0) if not found)
     */
    function getVaultByProjectToken(
        address _projectToken
    ) external view returns (address vaultAddress) {
        return vaultsByProjectToken[_projectToken];
    }

    /**
     * @notice Check if vault exists for project token
     * @param _projectToken Project token address
     * @return exists Whether vault exists
     */
    function isVaultSupported(
        address _projectToken
    ) external view returns (bool exists) {
        return vaultsByProjectToken[_projectToken] != address(0);
    }

    /**
     * @notice Get all vault addresses
     * @return vaults Array of all vault addresses
     */
    function getAllVaults() external view returns (address[] memory vaults) {
        return allVaults;
    }

    /**
     * @notice Get vault count
     * @return count Number of vaults
     */
    function getVaultCount() external view returns (uint256 count) {
        return allVaults.length;
    }

    /**
     * @notice Check if a vault is graduated
     * @param _vaultAddress Vault address
     * @return isGraduated Whether the vault is graduated
     * @dev Reads from AssetVault directly
     */
    function isVaultGraduated(
        address _vaultAddress
    ) external view returns (bool isGraduated) {
        if (!isValidVault[_vaultAddress]) return false;

        // Call getVaultInfo() which returns the full VaultInfo struct
        IAssetVault.VaultInfo memory vaultInfo = IAssetVault(_vaultAddress)
            .getVaultInfo();
        return vaultInfo.isGraduated;
    }

    /**
     * @notice Get project token for a vault
     * @param _vaultAddress Vault address
     * @return projectToken Project token address
     */
    function getVaultProjectToken(
        address _vaultAddress
    ) external view returns (address projectToken) {
        return vaultProjectToken[_vaultAddress];
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
    function checkPositionRisk(
        address _projectToken,
        uint256 positionSize,
        uint8 leverage
    ) external view returns (bool canOpen, string memory reason) {
        address vaultAddress = vaultsByProjectToken[_projectToken];
        if (vaultAddress == address(0)) {
            return (false, "Vault not found");
        }

        return
            IAssetVault(vaultAddress).checkPositionRisk(positionSize, leverage);
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

        IAssetVault(vaultAddress).depositFromBet{value: msg.value}(
            positionId,
            amount,
            positionSize,
            isMarginAdd
        );

        emit CollateralDepositedFromBet(
            vaultAddress,
            _projectToken,
            amount,
            positionSize,
            block.timestamp
        );
    }

    /**
     * @notice Execute payout to user (v1: project token only)
     * @param _projectToken Project token address
     * @param user User address
     * @param amount Payout amount in project tokens
     * @param positionId Position ID for tracking partial payouts
     */
    function executePayout(
        address _projectToken,
        address user,
        uint256 amount,
        uint64 positionId
    ) external onlyPositionManager {
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
            positionId,
            collateral,
            vaultPnL,
            fee,
            positionSize
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
     * @notice Update PositionManager for a specific vault
     * @param _projectToken Project token address
     * @param _positionManager New PositionManager address
     * @dev Only callable by owner, forwards call to vault
     */
    function updateVaultPositionManager(
        address _projectToken,
        address _positionManager
    ) external onlyOwner {
        address vaultAddress = vaultsByProjectToken[_projectToken];
        if (vaultAddress == address(0)) revert VaultNotFound();

        IAssetVault(vaultAddress).setPositionManager(_positionManager);
    }

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
     * @notice Set BlocksenseOracle for a vault
     * @param _projectToken Project token address
     * @param _blocksenseOracle BlocksenseOracle address
     * @dev Only callable by owner, forwards call to vault
     */
    function setVaultBlocksenseOracle(
        address _projectToken,
        address _blocksenseOracle
    ) external onlyOwner {
        address vaultAddress = vaultsByProjectToken[_projectToken];
        if (vaultAddress == address(0)) revert VaultNotFound();

        IAssetVault(vaultAddress).setBlocksenseOracle(_blocksenseOracle);
    }

    /**
     * @notice Set graduation threshold for a vault
     * @param _projectToken Project token address
     * @param _threshold New graduation threshold
     * @dev Only callable by owner, forwards call to vault
     */
    function setVaultGraduationThreshold(
        address _projectToken,
        uint256 _threshold
    ) external onlyOwner {
        address vaultAddress = vaultsByProjectToken[_projectToken];
        if (vaultAddress == address(0)) revert VaultNotFound();

        IAssetVault(vaultAddress).setGraduationThreshold(_threshold);
    }

    /**
     * @notice Authorize upgrade (UUPS pattern)
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    /**
     * @notice Get contract version
     */
    function version() external pure returns (string memory) {
        return "1.0.0-vault-manager";
    }
}
