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
 * @dev Manages vaults for different tokens (native + ERC20) - Non-upgradeable
 *
 * Features:
 * - Create vaults for different tokens
 * - Track all vaults and their addresses
 * - Route requests to appropriate vaults
 * - Global risk management across all vaults
 * - Centralized configuration
 */
contract VaultManager is Ownable, ReentrancyGuard, Pausable {
    // ========================================================================
    // STATE VARIABLES
    // ========================================================================

    /// @notice PositionManager contract address
    address public positionManager;

    /// @notice SettlementEngine contract address
    address public settlementEngine;

    /// @notice AssetVault implementation address (deprecated - vaults are now deployed directly)
    address public vaultImplementation;

    /// @notice Mapping: token address => vault address
    mapping(address => address) public vaults;

    /// @notice Mapping: price feed ID => vault address (to prevent duplicates)
    mapping(bytes32 => address) public vaultsByPriceFeed;

    /// @notice Array of all vault token addresses
    address[] public supportedTokens;

    /// @notice Mapping: vault address => is valid vault
    mapping(address => bool) public isValidVault;

    // ========================================================================
    // EVENTS
    // ========================================================================

    event VaultCreated(
        address indexed tokenAddress,
        address indexed vaultAddress,
        uint256 timestamp
    );

    event VaultImplementationUpdated(
        address indexed oldImplementation,
        address indexed newImplementation
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
    error InvalidAmount(); // HIGH FIX: For validation checks

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
     * @notice Create new vault for a token
     * @param tokenAddress Token address (address(0) for native token)
     * @param tokenPriceFeedId Pyth price feed ID for token (for USD conversion)
     * @param maxPayoutBps Max payout in bps
     * @param perBetUtilBps Per bet utilization in bps
     * @param maxUtilizationBps Max utilization in bps
     * @param minBetAmount Min bet amount
     * @param maxBetAmount Max bet amount
     * @return vaultAddress Address of created vault
     */
    function createVault(
        address tokenAddress,
        bytes32 tokenPriceFeedId,
        uint16 maxPayoutBps,
        uint16 perBetUtilBps,
        uint16 maxUtilizationBps,
        uint256 minBetAmount,
        uint256 maxBetAmount
    ) external onlyOwner returns (address vaultAddress) {
        if (vaults[tokenAddress] != address(0)) revert VaultAlreadyExists();

        // Validate that price feed ID is not already used by another vault
        if (vaultsByPriceFeed[tokenPriceFeedId] != address(0)) {
            revert DuplicatePriceFeedId();
        }

        // Deploy new vault directly (non-upgradeable)
        AssetVault vault = new AssetVault(
            tokenAddress,
            address(this),
            positionManager,
            tokenPriceFeedId,
            maxPayoutBps,
            perBetUtilBps,
            maxUtilizationBps,
            minBetAmount,
            maxBetAmount
        );

        vaultAddress = address(vault);

        // Register vault
        vaults[tokenAddress] = vaultAddress;
        vaultsByPriceFeed[tokenPriceFeedId] = vaultAddress;
        supportedTokens.push(tokenAddress);
        isValidVault[vaultAddress] = true;

        emit VaultCreated(tokenAddress, vaultAddress, block.timestamp);

        return vaultAddress;
    }

    // ========================================================================
    // VAULT MANAGEMENT
    // ========================================================================

    /**
     * @notice Get vault address for token
     * @param tokenAddress Token address
     * @return vaultAddress Vault address
     */
    function getVault(
        address tokenAddress
    ) external view returns (address vaultAddress) {
        vaultAddress = vaults[tokenAddress];
        if (vaultAddress == address(0)) revert VaultNotFound();
        return vaultAddress;
    }

    /**
     * @notice Get vault address by price feed ID
     * @param priceFeedId Pyth price feed ID
     * @return vaultAddress Vault address (address(0) if not found)
     */
    function getVaultByPriceFeed(
        bytes32 priceFeedId
    ) external view returns (address vaultAddress) {
        return vaultsByPriceFeed[priceFeedId];
    }

    /**
     * @notice Check if vault exists for token
     * @param tokenAddress Token address
     * @return exists Whether vault exists
     */
    function isVaultSupported(
        address tokenAddress
    ) external view returns (bool exists) {
        return vaults[tokenAddress] != address(0);
    }

    /**
     * @notice Get all supported tokens
     * @return tokens Array of token addresses
     */
    function getSupportedTokens()
        external
        view
        returns (address[] memory tokens)
    {
        return supportedTokens;
    }

    /**
     * @notice Get vault count
     * @return count Number of vaults
     */
    function getVaultCount() external view returns (uint256 count) {
        return supportedTokens.length;
    }

    // ========================================================================
    // PROXY FUNCTIONS (Route to specific vaults)
    // ========================================================================

    /**
     * @notice Check position risk for a token
     * @param tokenAddress Token address
     * @param positionSize Position size
     * @param leverage Leverage multiplier
     * @param priceFeedId Pyth price feed ID of asset being bet on
     * @return canOpen Whether position can be opened
     * @return reason Reason if cannot open
     */
    function checkPositionRisk(
        address tokenAddress,
        uint256 positionSize,
        uint8 leverage,
        bytes32 priceFeedId
    ) external view returns (bool canOpen, string memory reason) {
        address vaultAddress = vaults[tokenAddress];
        if (vaultAddress == address(0)) {
            return (false, "Vault not found");
        }

        return
            IAssetVault(vaultAddress).checkPositionRisk(
                positionSize,
                leverage,
                priceFeedId
            );
    }

    /**
     * @notice Deposit collateral from bet
     * @param tokenAddress Token address
     * @param amount Collateral amount
     * @param positionSize Position size
     * @param priceFeedId Pyth price feed ID of asset being bet on
     * @param direction Position direction (1=LONG, 2=SHORT)
     * @dev HIGH FIX: Check vault existence BEFORE accepting payment to prevent stuck funds
     */
    function depositFromBet(
        address tokenAddress,
        uint256 amount,
        uint256 positionSize,
        bytes32 priceFeedId,
        uint8 direction
    ) external payable onlyPositionManager {
        // HIGH FIX: Validate vault exists BEFORE accepting any payment
        address vaultAddress = vaults[tokenAddress];
        if (vaultAddress == address(0)) revert VaultNotFound();

        // HIGH FIX: Additional validation - ensure vault is actually a contract
        if (vaultAddress.code.length == 0) revert VaultNotFound();

        // Forward call to vault
        if (tokenAddress == address(0)) {
            // Native token - msg.value should match amount
            if (msg.value != amount) revert InvalidAmount();

            IAssetVault(vaultAddress).depositFromBet{value: msg.value}(
                amount,
                positionSize,
                priceFeedId,
                direction
            );
        } else {
            // ERC20 - no native token should be sent
            if (msg.value != 0) revert InvalidAmount();

            // Vault will handle transfer from PositionManager
            IAssetVault(vaultAddress).depositFromBet(
                amount,
                positionSize,
                priceFeedId,
                direction
            );
        }
    }

    /**
     * @notice Execute payout to user
     * @param tokenAddress Token address
     * @param user User address
     * @param amount Payout amount
     */
    function executePayout(
        address tokenAddress,
        address user,
        uint256 amount
    ) external onlyPositionManager {
        address vaultAddress = vaults[tokenAddress];
        if (vaultAddress == address(0)) revert VaultNotFound();

        IAssetVault(vaultAddress).executePayout(user, amount);
    }

    /**
     * @notice Update vault P&L
     * @param tokenAddress Token address
     * @param positionId Position ID (for tracking)
     * @param collateral Collateral amount
     * @param vaultPnL Vault P&L
     * @param fee Fee collected
     * @param positionSize Position size
     * @param excessProfit Excess profit from capped trades
     * @param priceFeedId Pyth price feed ID of the asset
     * @param direction Position direction (1=LONG, 2=SHORT)
     */
    function updateVaultPnLWithLeverage(
        address tokenAddress,
        uint64 positionId,
        uint256 collateral,
        int256 vaultPnL,
        uint256 fee,
        uint256 positionSize,
        uint256 excessProfit,
        bytes32 priceFeedId,
        uint8 direction
    ) external onlyPositionManager {
        address vaultAddress = vaults[tokenAddress];
        if (vaultAddress == address(0)) revert VaultNotFound();

        IAssetVault(vaultAddress).updateVaultPnL(
            positionId,
            collateral,
            vaultPnL,
            fee,
            positionSize,
            excessProfit,
            priceFeedId,
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

    /**
     * @notice Update vault implementation (for future vaults)
     */
    function updateVaultImplementation(
        address _newImplementation
    ) external onlyOwner {
        if (_newImplementation == address(0)) revert InvalidAddress();
        address oldImplementation = vaultImplementation;
        vaultImplementation = _newImplementation;
        emit VaultImplementationUpdated(oldImplementation, _newImplementation);
    }

    /**
     * @notice Update PositionManager contract for a specific vault
     */
    function updateVaultPositionManager(
        address tokenAddress,
        address _positionManager
    ) external onlyOwner {
        address vaultAddress = vaults[tokenAddress];
        if (vaultAddress == address(0)) revert VaultNotFound();

        IAssetVault(vaultAddress).setPositionManager(_positionManager);
    }

    /**
     * @notice Pause a specific vault
     */
    function pauseVault(address tokenAddress) external onlyOwner {
        address vaultAddress = vaults[tokenAddress];
        if (vaultAddress == address(0)) revert VaultNotFound();

        IAssetVault(vaultAddress).pause();
    }

    /**
     * @notice Unpause a specific vault
     */
    function unpauseVault(address tokenAddress) external onlyOwner {
        address vaultAddress = vaults[tokenAddress];
        if (vaultAddress == address(0)) revert VaultNotFound();

        IAssetVault(vaultAddress).unpause();
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
    // VIEW FUNCTIONS
    // ========================================================================

    /**
     * @notice Get vault info for a token
     */
    function getVaultInfo(
        address tokenAddress
    ) external view returns (IAssetVault.VaultInfo memory) {
        address vaultAddress = vaults[tokenAddress];
        if (vaultAddress == address(0)) revert VaultNotFound();

        return IAssetVault(vaultAddress).getVaultInfo();
    }

    /**
     * @notice Get vault parameters for a token
     */
    function getVaultParams(
        address tokenAddress
    ) external view returns (IAssetVault.VaultParams memory) {
        address vaultAddress = vaults[tokenAddress];
        if (vaultAddress == address(0)) revert VaultNotFound();

        return IAssetVault(vaultAddress).getVaultParams();
    }

    /**
     * @notice Get LP position for a user in a specific vault
     */
    function getLPPosition(
        address tokenAddress,
        address user
    ) external view returns (IAssetVault.LPPosition memory) {
        address vaultAddress = vaults[tokenAddress];
        if (vaultAddress == address(0)) revert VaultNotFound();

        return IAssetVault(vaultAddress).getLPPosition(user);
    }

    /**
     * @notice Get total liquidity across all vaults (in native token equivalent)
     * @dev This is a simplified view - actual implementation would need price oracle
     */
    function getTotalLiquidity() external view returns (uint256 total) {
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            address vaultAddress = vaults[supportedTokens[i]];
            IAssetVault.VaultInfo memory info = IAssetVault(vaultAddress)
                .getVaultInfo();
            total += info.totalLiquidity;
        }
        return total;
    }

    // ========================================================================
    // GRADUATION FUNCTIONS (Phase 2)
    // ========================================================================

    /**
     * @notice Get all graduated vaults
     * @return graduated Array of graduated vault addresses
     */
    function getGraduatedVaults()
        external
        view
        returns (address[] memory graduated)
    {
        uint256 count = 0;

        // Count graduated vaults
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            address vaultAddr = vaults[supportedTokens[i]];
            IAssetVault.VaultInfo memory info = IAssetVault(vaultAddr)
                .getVaultInfo();
            if (info.isGraduated) {
                count++;
            }
        }

        // Collect graduated vaults
        graduated = new address[](count);
        uint256 index = 0;

        for (uint256 i = 0; i < supportedTokens.length; i++) {
            address vaultAddr = vaults[supportedTokens[i]];
            IAssetVault.VaultInfo memory info = IAssetVault(vaultAddr)
                .getVaultInfo();
            if (info.isGraduated) {
                graduated[index] = vaultAddr;
                index++;
            }
        }

        return graduated;
    }

    /**
     * @notice Get total USD value across all vaults
     * @return totalUSD Total value in USD (18 decimals)
     */
    function getTotalValueUSD() external view returns (uint256 totalUSD) {
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            address vaultAddr = vaults[supportedTokens[i]];
            totalUSD += IAssetVault(vaultAddr).getVaultValueUSD();
        }
        return totalUSD;
    }

    /**
     * @notice Set Pyth Oracle for a vault
     * @param tokenAddress Token address
     * @param pythOracle PythOracle contract address
     */
    function setVaultPythOracle(
        address tokenAddress,
        address pythOracle
    ) external onlyOwner {
        address vaultAddress = vaults[tokenAddress];
        if (vaultAddress == address(0)) revert VaultNotFound();

        IAssetVault(vaultAddress).setPythOracle(pythOracle);
    }

    /**
     * @notice Set graduation threshold for a vault
     * @param tokenAddress Token address
     * @param threshold New threshold in token amount (same decimals as token)
     */
    function setVaultGraduationThreshold(
        address tokenAddress,
        uint256 threshold
    ) external onlyOwner {
        address vaultAddress = vaults[tokenAddress];
        if (vaultAddress == address(0)) revert VaultNotFound();

        IAssetVault(vaultAddress).setGraduationThreshold(threshold);
    }

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
