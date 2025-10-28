// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol"; // HIGH FIX: For emergency withdrawal
import "./interfaces/IAssetVault.sol";
import "./AssetVault.sol";

/**
 * @title VaultManager
 * @notice Factory contract to create and manage multiple AssetVault instances
 * @dev Manages vaults for individual project tokens with Blocksense Oracle - Non-upgradeable
 *
 * NEW FEATURES:
 * - Create vaults for individual project tokens (one vault per project token)
 * - Each vault accepts both MON and project token
 * - Traders can use either MON or project token to bet
 * - Multiple positions allowed per user per project token
 * - Partial liquidity system support
 * - Blocksense Oracle integration
 */
contract VaultManager is Ownable, ReentrancyGuard, Pausable {
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
        address indexed monToken,
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

    // HIGH FIX: Emergency withdrawal events
    event EmergencyWithdrawNative(
        address indexed to,
        uint256 amount,
        uint256 timestamp
    );

    event EmergencyWithdrawToken(
        address indexed token,
        address indexed to,
        uint256 amount,
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
    error DuplicateProjectToken(); // New: Vault for this project token already exists
    error InvalidAmount(); // HIGH FIX: For validation checks
    error InvalidPriceFeedId(); // Validation for price feed ID

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
    // CONSTRUCTOR
    // ========================================================================

    /**
     * @notice Constructor
     * @param initialOwner Owner address
     */
    constructor(address initialOwner) Ownable(initialOwner) {
        if (initialOwner == address(0)) revert InvalidAddress();
    }

    // ========================================================================
    // VAULT CREATION
    // ========================================================================

    /**
     * @notice Create new vault for a project token
     * @param _projectToken Project token address (the asset being bet on - must be on Monad)
     * @param _projectTokenBase Base token address for price feed (project token)
     * @param _projectTokenQuote Quote token address for price feed (usually USDC)
     * @param _monToken MON token address (address(0) for native MON)
     * @param _isStablecoinProject Whether project token is stablecoin (USDC, USDT, DAI) - saves gas
     * @param _maxPayoutBps Max payout in bps
     * @param _perBetUtilBps Per bet utilization in bps
     * @param _maxUtilizationBps Max utilization in bps
     * @param _minBetAmount Min bet amount (in any supported token)
     * @param _maxBetAmount Max bet amount (in any supported token)
     * @return vaultAddress Address of created vault
     * @dev Prevents duplicate vault creation for same project token
     */
    function createVault(
        address _projectToken,
        address _projectTokenBase,
        address _projectTokenQuote,
        address _monToken,
        bool _isStablecoinProject,
        uint16 _maxPayoutBps,
        uint16 _perBetUtilBps,
        uint16 _maxUtilizationBps,
        uint256 _minBetAmount,
        uint256 _maxBetAmount
    ) external onlyOwner returns (address vaultAddress) {
        // Validate inputs
        if (_projectToken == address(0)) revert InvalidAddress();
        // OPTIMIZATION: Stablecoins don't need price feed
        if (
            !_isStablecoinProject &&
            (_projectTokenBase == address(0) ||
                _projectTokenQuote == address(0))
        ) {
            revert InvalidAddress();
        }

        // Check if vault for this project token already exists
        if (vaultsByProjectToken[_projectToken] != address(0)) {
            revert DuplicateProjectToken();
        }

        // Deploy new vault directly (non-upgradeable)
        AssetVault vault = new AssetVault(
            _projectToken,
            _projectTokenBase,
            _projectTokenQuote,
            _monToken,
            _isStablecoinProject,
            address(this),
            positionManager,
            _maxPayoutBps,
            _perBetUtilBps,
            _maxUtilizationBps,
            _minBetAmount,
            _maxBetAmount
        );

        vaultAddress = address(vault);

        // Register vault
        vaultsByProjectToken[_projectToken] = vaultAddress;
        allVaults.push(vaultAddress);
        isValidVault[vaultAddress] = true;
        vaultProjectToken[vaultAddress] = _projectToken;

        emit VaultCreated(
            _projectToken,
            _monToken,
            vaultAddress,
            block.timestamp
        );

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
     * @param useProjectToken True if using project token, false if using MON
     * @return canOpen Whether position can be opened
     * @return reason Reason if cannot open
     */
    function checkPositionRisk(
        address _projectToken,
        uint256 positionSize,
        uint8 leverage,
        bool useProjectToken
    ) external view returns (bool canOpen, string memory reason) {
        address vaultAddress = vaultsByProjectToken[_projectToken];
        if (vaultAddress == address(0)) {
            return (false, "Vault not found");
        }

        return
            IAssetVault(vaultAddress).checkPositionRisk(
                positionSize,
                leverage,
                useProjectToken
            );
    }

    /**
     * @notice Deposit collateral from bet (supports MON or project token)
     * @param _projectToken Project token address
     * @param amount Collateral amount
     * @param positionSize Position size
     * @param useProjectToken True if using project token, false if using MON
     * @param direction Position direction (1=LONG, 2=SHORT)
     * @dev HIGH FIX: Check vault existence BEFORE accepting payment to prevent stuck funds
     */
    function depositFromBet(
        address _projectToken,
        uint256 amount,
        uint256 positionSize,
        bool useProjectToken,
        uint8 direction
    ) external payable onlyPositionManager {
        // HIGH FIX: Validate vault exists BEFORE accepting any payment
        address vaultAddress = vaultsByProjectToken[_projectToken];
        if (vaultAddress == address(0)) revert VaultNotFound();

        // HIGH FIX: Additional validation - ensure vault is actually a contract
        if (vaultAddress.code.length == 0) revert VaultNotFound();

        // Forward call to vault
        IAssetVault(vaultAddress).depositFromBet{value: msg.value}(
            amount,
            positionSize,
            useProjectToken,
            direction
        );
    }

    /**
     * @notice Execute payout to user (supports MON or project token)
     * @param _projectToken Project token address
     * @param user User address
     * @param amount Payout amount
     * @param useProjectToken True if payout should be in project token, false for MON
     * @param positionId Position ID for tracking partial payouts
     */
    function executePayout(
        address _projectToken,
        address user,
        uint256 amount,
        bool useProjectToken,
        uint64 positionId
    ) external onlyPositionManager {
        address vaultAddress = vaultsByProjectToken[_projectToken];
        if (vaultAddress == address(0)) revert VaultNotFound();

        IAssetVault(vaultAddress).executePayout(
            user,
            amount,
            useProjectToken,
            positionId
        );
    }

    /**
     * @notice Update vault P&L
     * @param _projectToken Project token address
     * @param positionId Position ID (for tracking)
     * @param collateral Collateral amount
     * @param vaultPnL Vault P&L
     * @param fee Fee collected
     * @param positionSize Position size
     * @param excessProfit Excess profit from capped trades
     * @param direction Position direction (1=LONG, 2=SHORT)
     */
    function updateVaultPnLWithLeverage(
        address _projectToken,
        uint64 positionId,
        uint256 collateral,
        int256 vaultPnL,
        uint256 fee,
        uint256 positionSize,
        uint256 excessProfit,
        uint8 direction
    ) external onlyPositionManager {
        address vaultAddress = vaultsByProjectToken[_projectToken];
        if (vaultAddress == address(0)) revert VaultNotFound();

        IAssetVault(vaultAddress).updateVaultPnL(
            positionId,
            collateral,
            vaultPnL,
            fee,
            positionSize,
            excessProfit,
            bytes32(uint256(uint160(_projectToken))), // Use project token address as asset ID
            direction
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

    // NOTE: updateVaultPositionManager, pauseVault, unpauseVault
    // moved to VaultManagerViews.sol to reduce contract size

    // NOTE: vaultImplementation variable and updateVaultImplementation() removed
    // (BP-01 FIX) as vaults are deployed directly, not via proxy pattern

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

    /**
     * @notice Emergency: Withdraw stuck native tokens
     * @param to Recipient address
     * @param amount Amount to withdraw
     * @dev HIGH FIX: Allows recovery of stuck funds if depositFromBet fails
     */
    function emergencyWithdrawNative(
        address payable to,
        uint256 amount
    ) external onlyOwner {
        if (to == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();
        if (address(this).balance < amount) revert InvalidAmount();

        (bool success, ) = to.call{value: amount}("");
        require(success, "Transfer failed");

        emit EmergencyWithdrawNative(to, amount, block.timestamp);
    }

    /**
     * @notice Emergency: Withdraw stuck ERC20 tokens
     * @param token Token address
     * @param to Recipient address
     * @param amount Amount to withdraw
     * @dev HIGH FIX: Allows recovery of stuck ERC20 tokens
     */
    function emergencyWithdrawToken(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        if (token == address(0)) revert InvalidAddress();
        if (to == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();

        IERC20 tokenContract = IERC20(token);
        require(tokenContract.transfer(to, amount), "Transfer failed");

        emit EmergencyWithdrawToken(token, to, amount, block.timestamp);
    }

    // ========================================================================
    // VIEW FUNCTIONS (Minimal - most moved to VaultManagerViews)
    // ========================================================================

    // NOTE: Complex view and admin functions moved to VaultManagerViews.sol
    // to reduce contract size below 24KB limit. Use VaultManagerViews for:
    // - getVaultInfo(), getVaultParams(), getLPPosition()
    // - getTotalLiquidity(), getGraduatedVaults(), getTotalValueUSD()
    // - All admin forwarding functions (pauseVault, setVaultBlocksenseOracle, etc.)

    // ========================================================================
    // HIGH FIX: Emergency View Functions
    // ========================================================================

    /**
     * @notice Get balance of native tokens in VaultManager
     * @return balance Native token balance
     * @dev HIGH FIX: Allows checking if funds are stuck
     */
    function getNativeBalance() external view returns (uint256 balance) {
        return address(this).balance;
    }

    /**
     * @notice Get balance of ERC20 tokens in VaultManager
     * @param token Token address
     * @return balance Token balance
     * @dev HIGH FIX: Allows checking if ERC20 tokens are stuck
     */
    function getTokenBalance(
        address token
    ) external view returns (uint256 balance) {
        if (token == address(0)) revert InvalidAddress();
        return IERC20(token).balanceOf(address(this));
    }
}
