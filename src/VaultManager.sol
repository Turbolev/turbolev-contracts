// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IVaultManager.sol";
import "./interfaces/IAssetVault.sol";
import "./governance/VersionedBeacon.sol";

/**
 * @title VaultManager
 * @notice Vault factory + manager với governance support (Timelock + Multisig)
 * @dev Factory tạo vaults qua BeaconProxy pattern, tích hợp governance system
 *
 * Tính năng chính:
 * - Deploy vaults qua BeaconProxy (upgradeable)
 * - Tích hợp Timelock (24-48h) + Multisig (3/5 or 4/7)
 * - Opt-in upgrade cho LPs (GMX/Hyperliquid style)
 * - Pause/unpause vaults qua Multisig (không cần timelock delay)
 * - UUPS upgradeable
 */
contract VaultManager is
    IVaultManager,
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

    /// @notice VaultManagerHelper contract address
    address public vaultManagerHelper;

    /// @notice VersionedBeacon address (replaces VaultBeacon in V2)
    address public vaultBeacon;

    /// @dev DEPRECATED: optInUpgradeManager removed in V2
    address private __deprecated_optInUpgradeManager;

    /// @notice TimelockController address
    address public timelockController;

    /// @notice MultisigWallet address
    address public multisigWallet;

    /// @notice VaultGovernor address
    address public vaultGovernor;

    /// @notice Mapping: projectToken => vault address
    mapping(address => address) public vaultsByProjectToken;

    /// @notice Array of all vault addresses
    address[] public allVaults;

    /// @notice Mapping: vault address => vault info
    mapping(address => IVaultManager.VaultInfo) public vaultInfos;

    // ========================================================================
    // STORAGE GAP (for future upgrades)
    // ========================================================================

    uint256[35] private __gap;

    // ========================================================================
    // EVENTS
    // ========================================================================

    event VaultCreated(
        address indexed projectToken,
        address indexed vaultAddress,
        bool isBeaconProxy,
        uint256 timestamp
    );

    event CollateralDepositedFromBet(
        address indexed vault,
        address indexed projectToken,
        uint256 amount,
        uint256 positionSize,
        uint256 timestamp
    );

    event VaultBeaconUpdated(address indexed oldBeacon, address indexed newBeacon);
    // DEPRECATED: OptInUpgradeManagerUpdated removed in V2
    event TimelockControllerUpdated(address indexed oldController, address indexed newController);
    event MultisigWalletUpdated(address indexed oldWallet, address indexed newWallet);
    event VaultGovernorUpdated(address indexed oldGovernor, address indexed newGovernor);
    event VaultDeactivated(address indexed vaultAddress, uint256 timestamp);
    event VaultReactivated(address indexed vaultAddress, uint256 timestamp);

    // ========================================================================
    // ERRORS
    // ========================================================================

    error InvalidAddress();
    error VaultNotFound();
    error NotPositionManager();
    error DuplicateProjectToken();
    error DirectTransferNotAllowed();
    error DeploymentFailed();
    error NotAuthorized();

    // ========================================================================
    // MODIFIERS
    // ========================================================================

    modifier onlyPositionManager() {
        if (msg.sender != positionManager) revert NotPositionManager();
        _;
    }

    modifier onlyTimelockOrGovernor() {
        if (msg.sender != timelockController && msg.sender != vaultGovernor) {
            revert NotAuthorized();
        }
        _;
    }

    modifier onlyMultisig() {
        if (msg.sender != multisigWallet) {
            revert NotAuthorized();
        }
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
     * @notice Initialize contract V2
     * @param initialOwner Owner address
     * @param _vaultBeacon VersionedBeacon address
     * @param _timelockController TimelockController address
     * @param _multisigWallet MultisigWallet address
     * @param _vaultGovernor VaultGovernor address
     * @dev V2: Removed optInUpgradeManager parameter
     */
    function initializeV2(
        address initialOwner,
        address _vaultBeacon,
        address _timelockController,
        address _multisigWallet,
        address _vaultGovernor
    ) public reinitializer(2) {
        if (initialOwner == address(0)) revert InvalidAddress();
        if (_vaultBeacon == address(0)) revert InvalidAddress();

        // Initialize base contracts (for first-time deploy)
        __Ownable_init(initialOwner);
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        vaultBeacon = _vaultBeacon;
        timelockController = _timelockController;
        multisigWallet = _multisigWallet;
        vaultGovernor = _vaultGovernor;
    }

    // ========================================================================
    // RECEIVE / FALLBACK
    // ========================================================================

    receive() external payable {
        revert DirectTransferNotAllowed();
    }

    fallback() external payable {
        revert DirectTransferNotAllowed();
    }

    // ========================================================================
    // VAULT CREATION (V2 - Beacon Proxy)
    // ========================================================================

    /**
     * @notice Tạo vault mới sử dụng BeaconProxy
     * @param _projectToken Project token address
     * @param _minBetAmount Min bet amount
     * @param _maxBetAmount Max bet amount
     * @param _graduationThreshold Graduation threshold
     * @return vaultAddress Address of the newly created vault
     */
    function createVaultWithBeacon(
        address _projectToken,
        uint256 _minBetAmount,
        uint256 _maxBetAmount,
        uint256 _graduationThreshold
    ) public onlyOwner returns (address vaultAddress) {
        if (_projectToken == address(0) || vaultManagerHelper == address(0)) {
            revert InvalidAddress();
        }
        if (vaultsByProjectToken[_projectToken] != address(0)) {
            revert DuplicateProjectToken();
        }
        if (vaultBeacon == address(0)) revert InvalidAddress();

        // Create BeaconProxy
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address,address,address,uint256,uint256,uint256)",
            _projectToken,
            address(this),
            vaultManagerHelper,
            positionManager,
            _minBetAmount,
            _maxBetAmount,
            _graduationThreshold
        );

        BeaconProxy proxy = new BeaconProxy(vaultBeacon, initData);
        vaultAddress = address(proxy);

        if (vaultAddress == address(0)) revert DeploymentFailed();

        // Store vault info
        vaultsByProjectToken[_projectToken] = vaultAddress;
        allVaults.push(vaultAddress);

        vaultInfos[vaultAddress] = IVaultManager.VaultInfo({
            projectToken: _projectToken,
            vaultAddress: vaultAddress,
            deployedAt: block.timestamp,
            isActive: true,
            isBeaconProxy: true
        });

        // V2: Removed setUpgradeManager call (opt-in mechanism removed)
        emit VaultCreated(_projectToken, vaultAddress, true, block.timestamp);

        return vaultAddress;
    }

    /**
     * @notice Batch create nhiều vaults cùng lúc
     * @param projectTokens Array of project tokens
     * @param minBetAmounts Array of min bet amounts
     * @param maxBetAmounts Array of max bet amounts
     * @param graduationThresholds Array of graduation thresholds
     * @return vaultAddresses Array of created vault addresses
     */
    function batchCreateVaults(
        address[] calldata projectTokens,
        uint256[] calldata minBetAmounts,
        uint256[] calldata maxBetAmounts,
        uint256[] calldata graduationThresholds
    ) external onlyOwner returns (address[] memory vaultAddresses) {
        require(
            projectTokens.length == minBetAmounts.length
                && projectTokens.length == maxBetAmounts.length
                && projectTokens.length == graduationThresholds.length,
            "Length mismatch"
        );

        vaultAddresses = new address[](projectTokens.length);

        for (uint256 i = 0; i < projectTokens.length; i++) {
            vaultAddresses[i] = createVaultWithBeacon(
                projectTokens[i], minBetAmounts[i], maxBetAmounts[i], graduationThresholds[i]
            );
        }

        return vaultAddresses;
    }

    // ========================================================================
    // PROXY FUNCTIONS (Route to specific vaults)
    // ========================================================================

    /**
     * @notice Deposit collateral from bet
     * @param _projectToken Project token address
     * @param positionId Position ID
     * @param amount Collateral amount
     * @param positionSize Position size
     * @param isMarginAdd Is margin add
     * @param direction Position direction (1 = LONG, 2 = SHORT)
     */
    function depositFromBet(
        address _projectToken,
        uint64 positionId,
        uint256 amount,
        uint256 positionSize,
        bool isMarginAdd,
        uint8 direction
    ) external payable onlyPositionManager {
        address vaultAddress = _getVault(_projectToken);
        IERC20(_projectToken).transferFrom(positionManager, vaultAddress, amount);
        IAssetVault(vaultAddress).depositFromBet(
            positionId, amount, positionSize, isMarginAdd, direction
        );
        emit CollateralDepositedFromBet(
            vaultAddress, _projectToken, amount, positionSize, block.timestamp
        );
    }

    /**
     * @notice Execute payout to user
     */
    function executePayout(address _projectToken, address user, uint256 amount, uint64 positionId)
        external
        onlyPositionManager
    {
        IAssetVault(_getVault(_projectToken)).executePayout(user, amount, positionId);
    }

    /**
     * @notice Update vault P&L
     * @param direction Position direction (1 = LONG, 2 = SHORT)
     */
    function updateVaultPnLWithLeverage(
        address _projectToken,
        uint64 positionId,
        uint256 collateral,
        int256 vaultPnL,
        uint256 fee,
        uint256 positionSize,
        uint8 direction
    ) external onlyPositionManager {
        IAssetVault(_getVault(_projectToken)).updateVaultPnL(
            positionId, collateral, vaultPnL, fee, positionSize, direction
        );
    }

    // ========================================================================
    // GOVERNANCE PROTECTED FUNCTIONS (Timelock + Multisig)
    // ========================================================================

    /**
     * @notice Pause vault by project token (IVaultManager interface)
     * @param _projectToken Project token address
     * @dev Chỉ MultisigWallet có thể gọi
     */
    function pauseVault(address _projectToken) external onlyMultisig {
        address vault = _getVault(_projectToken);
        IAssetVault(vault).pause();
    }

    /**
     * @notice Unpause vault by project token (IVaultManager interface)
     * @param _projectToken Project token address
     * @dev Chỉ MultisigWallet có thể gọi
     */
    function unpauseVault(address _projectToken) external onlyMultisig {
        address vault = _getVault(_projectToken);
        IAssetVault(vault).unpause();
    }

    /**
     * @notice Pause vault by vault address directly
     * @param vault Vault address
     * @dev Chỉ MultisigWallet có thể gọi
     */
    function pauseVaultByAddress(address vault) public onlyMultisig {
        IAssetVault(vault).pause();
    }

    /**
     * @notice Unpause vault by vault address directly
     * @param vault Vault address
     * @dev Chỉ MultisigWallet có thể gọi
     */
    function unpauseVaultByAddress(address vault) public onlyMultisig {
        IAssetVault(vault).unpause();
    }

    /**
     * @notice Batch pause nhiều vaults
     * @param vaults Array of vault addresses
     * @dev Chỉ MultisigWallet có thể gọi
     */
    function batchPauseVaults(address[] calldata vaults) external onlyMultisig {
        for (uint256 i = 0; i < vaults.length; i++) {
            pauseVaultByAddress(vaults[i]);
        }
    }

    /**
     * @notice Batch unpause nhiều vaults
     * @param vaults Array of vault addresses
     * @dev Chỉ MultisigWallet có thể gọi
     */
    function batchUnpauseVaults(address[] calldata vaults) external onlyMultisig {
        for (uint256 i = 0; i < vaults.length; i++) {
            unpauseVaultByAddress(vaults[i]);
        }
    }

    // ========================================================================
    // VAULT MANAGEMENT
    // ========================================================================

    /**
     * @notice Deactivate vault
     * @param vault Vault address
     */
    function deactivateVault(address vault) external onlyOwner {
        IVaultManager.VaultInfo storage info = vaultInfos[vault];
        if (info.vaultAddress == address(0)) revert VaultNotFound();

        info.isActive = false;

        emit VaultDeactivated(vault, block.timestamp);
    }

    /**
     * @notice Reactivate vault
     * @param vault Vault address
     */
    function reactivateVault(address vault) external onlyOwner {
        IVaultManager.VaultInfo storage info = vaultInfos[vault];
        if (info.vaultAddress == address(0)) revert VaultNotFound();

        info.isActive = true;

        emit VaultReactivated(vault, block.timestamp);
    }

    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================

    /**
     * @notice Set PositionManager contract address
     */
    function setPositionManager(address _positionManager) external onlyOwner {
        if (_positionManager == address(0)) revert InvalidAddress();
        positionManager = _positionManager;
    }

    /**
     * @notice Set VaultManagerHelper contract address
     */
    function setVaultManagerHelper(address _vaultManagerHelper) external onlyOwner {
        if (_vaultManagerHelper == address(0)) revert InvalidAddress();
        vaultManagerHelper = _vaultManagerHelper;
    }

    /**
     * @notice Set Vault Beacon address
     * @param _vaultBeacon New beacon address
     */
    function setVaultBeacon(address _vaultBeacon) external onlyOwner {
        if (_vaultBeacon == address(0)) revert InvalidAddress();

        address oldBeacon = vaultBeacon;
        vaultBeacon = _vaultBeacon;

        emit VaultBeaconUpdated(oldBeacon, _vaultBeacon);
    }

    // DEPRECATED: setOptInUpgradeManager removed in V2

    /**
     * @notice Set TimelockController address
     * @param _timelockController New timelock controller address
     */
    function setTimelockController(address _timelockController) external onlyOwner {
        if (_timelockController == address(0)) revert InvalidAddress();

        address oldController = timelockController;
        timelockController = _timelockController;

        emit TimelockControllerUpdated(oldController, _timelockController);
    }

    /**
     * @notice Set MultisigWallet address
     * @param _multisigWallet New multisig wallet address
     */
    function setMultisigWallet(address _multisigWallet) external onlyOwner {
        if (_multisigWallet == address(0)) revert InvalidAddress();

        address oldWallet = multisigWallet;
        multisigWallet = _multisigWallet;

        emit MultisigWalletUpdated(oldWallet, _multisigWallet);
    }

    /**
     * @notice Set VaultGovernor address
     * @param _vaultGovernor New vault governor address
     */
    function setVaultGovernor(address _vaultGovernor) external onlyOwner {
        if (_vaultGovernor == address(0)) revert InvalidAddress();

        address oldGovernor = vaultGovernor;
        vaultGovernor = _vaultGovernor;

        emit VaultGovernorUpdated(oldGovernor, _vaultGovernor);
    }

    /**
     * @notice Pause factory
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
     * @notice Authorize upgrade (UUPS pattern)
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    function getVault(address _projectToken) external view returns (address) {
        return vaultsByProjectToken[_projectToken];
    }

    function isVaultSupported(address _projectToken) external view returns (bool) {
        return vaultsByProjectToken[_projectToken] != address(0);
    }

    function getAllVaults() external view returns (address[] memory) {
        return allVaults;
    }

    function vaultProjectToken(address vaultAddress) external view returns (address projectToken) {
        return vaultInfos[vaultAddress].projectToken;
    }

    /**
     * @notice Get beacon proxy vaults only
     */
    function getBeaconProxyVaults() external view returns (address[] memory) {
        uint256 count = 0;

        // Count first
        for (uint256 i = 0; i < allVaults.length; i++) {
            if (vaultInfos[allVaults[i]].isBeaconProxy) {
                count++;
            }
        }

        // Create array
        address[] memory beaconVaults = new address[](count);
        uint256 index = 0;

        for (uint256 i = 0; i < allVaults.length; i++) {
            if (vaultInfos[allVaults[i]].isBeaconProxy) {
                beaconVaults[index] = allVaults[i];
                index++;
            }
        }

        return beaconVaults;
    }

    /**
     * @notice Get active vaults only
     * @return active Array of active vault addresses
     */
    function getActiveVaults() external view returns (address[] memory active) {
        uint256 activeCount = 0;

        // Count active vaults
        for (uint256 i = 0; i < allVaults.length; i++) {
            if (vaultInfos[allVaults[i]].isActive) {
                activeCount++;
            }
        }

        // Populate array
        active = new address[](activeCount);
        uint256 index = 0;

        for (uint256 i = 0; i < allVaults.length; i++) {
            if (vaultInfos[allVaults[i]].isActive) {
                active[index] = allVaults[i];
                index++;
            }
        }

        return active;
    }

    /**
     * @notice Get vault info
     * @param vault Vault address
     * @return info VaultInfo struct
     */
    function getVaultInfo(address vault)
        external
        view
        returns (IVaultManager.VaultInfo memory info)
    {
        return vaultInfos[vault];
    }

    function _getVault(address _projectToken) internal view returns (address) {
        address vault = vaultsByProjectToken[_projectToken];
        if (vault == address(0) || vault.code.length == 0) {
            revert VaultNotFound();
        }
        return vault;
    }

    function version() external pure returns (string memory) {
        return "2.0.0-with-governance";
    }
}
