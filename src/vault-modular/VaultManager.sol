// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./VaultRouter.sol";
import "./VaultAccessController.sol";
import "../interfaces/IVaultManager.sol";
import "../interfaces/IVaultRouter.sol";

/**
 * @title VaultManager
 * @notice Vault factory + manager for modular vault architecture
 * @dev Factory creates modular vaults with VaultRouter + modules
 *
 * Key Features:
 * - Deploy modular vaults (VaultRouter with delegatecall modules)
 * - Integrate VaultAccessController for centralized access control
 * - Governance integration (Timelock + Multisig)
 * - UUPS upgradeable
 * - Backward compatible with legacy vault calls
 */
contract VaultManager is
    IVaultManager,
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;
    // ========================================================================
    // STATE VARIABLES
    // ========================================================================

    /// @notice PositionManager contract address
    address public positionManager;

    /// @notice VaultAccessController address
    address public accessController;

    /// @notice VaultRouter implementation address
    address public vaultRouterImpl;

    /// @notice VaultCore module address
    address public coreModule;

    /// @notice VaultFunding module address
    address public fundingModule;

    /// @notice VaultRewards module address
    address public rewardsModule;

    /// @notice Mapping: keccak256(abi.encode(collateralToken, priceToken)) => vault address
    mapping(bytes32 => address) public vaultsByPair;

    /// @notice Array of all vault addresses
    address[] public allVaults;

    /// @notice Mapping: vault address => vault info
    mapping(address => IVaultManager.VaultInfo) public vaultInfos;

    // ========================================================================
    // STORAGE GAP
    // ========================================================================

    uint256[30] private __gap;

    // ========================================================================
    // CONSTANTS
    // ========================================================================

    uint256 public constant MAX_BATCH_SIZE = 10;

    // ========================================================================
    // EVENTS
    // ========================================================================

    event VaultCreated(
        address indexed priceToken,
        address indexed collateralToken,
        address indexed vaultAddress,
        bool isBeaconProxy,
        uint256 timestamp
    );
    event ModularVaultCreated(
        address indexed priceToken,
        address collateralToken,
        address indexed vaultAddress,
        address indexed coreModule,
        uint256 timestamp
    );
    event CollateralDepositedFromBet(
        address indexed vault,
        address indexed priceToken,
        address collateralToken,
        uint256 amount,
        uint256 positionSize,
        uint256 timestamp
    );
    event VaultDeactivated(address indexed vaultAddress, uint256 timestamp);
    event VaultReactivated(address indexed vaultAddress, uint256 timestamp);
    event EmergencyPauseAllTriggered(address indexed caller, uint256 timestamp);
    event EmergencyPauseBatchTriggered(
        address indexed caller, uint256 startIndex, uint256 count, uint256 timestamp
    );
    event EmergencyUnpauseAllTriggered(address indexed caller, uint256 timestamp);
    event EmergencyUnpauseBatchTriggered(
        address indexed caller, uint256 startIndex, uint256 count, uint256 timestamp
    );
    event AccessControllerUpdated(address indexed oldController, address indexed newController);
    event VaultRouterImplUpdated(address indexed oldImpl, address indexed newImpl);
    event ModulesUpdated(address coreModule, address fundingModule, address rewardsModule);
    event PositionManagerUpdated(
        address indexed oldPositionManager, address indexed newPositionManager
    );

    // Emergency events
    event EmergencyPauseVault(address indexed vault, address indexed caller, uint256 timestamp);
    event EmergencyUnpauseVault(address indexed vault, address indexed caller, uint256 timestamp);
    event EmergencyBatchPauseVaults(address[] vaults, address indexed caller, uint256 timestamp);
    event EmergencyBatchUnpauseVaults(address[] vaults, address indexed caller, uint256 timestamp);
    event EmergencyUpgrade(
        address indexed newImplementation, address indexed caller, uint256 timestamp
    );

    // ========================================================================
    // ERRORS
    // ========================================================================

    error InvalidAddress();
    error VaultNotFound();
    error VaultNotActive();
    error NotPositionManager();
    error DuplicateVaultPair();
    error DirectTransferNotAllowed();
    error DeploymentFailed();
    error NotAuthorized();
    error LengthMismatch();
    error BatchTooLarge();
    error InvalidBatchRange();
    error MustPauseBeforeEmergencyUpgrade();
    error NotAContract(address addr);

    // ========================================================================
    // MODIFIERS
    // ========================================================================

    modifier onlyPositionManager() {
        if (msg.sender != positionManager) revert NotPositionManager();
        _;
    }

    modifier onlyEmergencyRole() {
        if (!VaultAccessController(accessController).hasEmergencyRole(msg.sender)) {
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
     * @notice Initialize contract
     * @param initialOwner Owner address
     * @param _accessController VaultAccessController address
     * @param _vaultRouterImpl VaultRouter implementation address
     * @param _coreModule VaultCore module address
     * @param _fundingModule VaultFunding module address
     * @param _rewardsModule VaultRewards module address
     */
    function initialize(
        address initialOwner,
        address _accessController,
        address _vaultRouterImpl,
        address _coreModule,
        address _fundingModule,
        address _rewardsModule
    ) public initializer {
        if (initialOwner == address(0)) revert InvalidAddress();
        if (_accessController == address(0)) revert InvalidAddress();
        if (_vaultRouterImpl == address(0)) revert InvalidAddress();
        if (_coreModule == address(0)) revert InvalidAddress();
        if (_fundingModule == address(0)) revert InvalidAddress();
        if (_rewardsModule == address(0)) revert InvalidAddress();

        __Ownable_init(initialOwner);
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        accessController = _accessController;
        vaultRouterImpl = _vaultRouterImpl;
        coreModule = _coreModule;
        fundingModule = _fundingModule;
        rewardsModule = _rewardsModule;
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
    // VAULT CREATION
    // ========================================================================

    /**
     * @notice Create modular vault for a (collateralToken, priceToken) pair
     * @param _priceToken Token whose price is tracked by the oracle (e.g. SEI, ETH)
     * @param _collateralToken Token used for LP liquidity and user collateral (e.g. USDC, USDT)
     * @param _minBetAmount Min bet amount
     * @param _maxBetAmount Max bet amount
     * @param _graduationThreshold Graduation threshold
     * @return vaultAddress Address of the newly created vault
     */
    function createVault(
        address _priceToken,
        address _collateralToken,
        uint256 _minBetAmount,
        uint256 _maxBetAmount,
        uint256 _graduationThreshold
    ) public onlyOwner whenNotPaused returns (address vaultAddress) {
        if (_priceToken == address(0)) revert InvalidAddress();
        if (_collateralToken == address(0)) revert InvalidAddress();
        if (positionManager == address(0)) revert InvalidAddress();

        bytes32 pairKey = _vaultPairKey(_collateralToken, _priceToken);
        if (vaultsByPair[pairKey] != address(0)) revert DuplicateVaultPair();

        // Create ERC1967 Proxy for VaultRouter
        bytes memory initData = abi.encodeWithSelector(
            VaultRouter.initialize.selector,
            _priceToken,
            _collateralToken,
            address(this),
            positionManager,
            accessController,
            coreModule,
            fundingModule,
            rewardsModule,
            _minBetAmount,
            _maxBetAmount,
            _graduationThreshold
        );

        ERC1967Proxy proxy = new ERC1967Proxy(vaultRouterImpl, initData);
        vaultAddress = address(proxy);

        if (vaultAddress == address(0)) revert DeploymentFailed();

        // Register with access controller
        VaultAccessController(accessController).registerVault(vaultAddress);

        // Store vault info
        vaultsByPair[pairKey] = vaultAddress;
        allVaults.push(vaultAddress);

        vaultInfos[vaultAddress] = IVaultManager.VaultInfo({
            priceToken: _priceToken,
            collateralToken: _collateralToken,
            vaultAddress: vaultAddress,
            deployedAt: block.timestamp,
            isActive: true,
            isBeaconProxy: false
        });

        emit ModularVaultCreated(
            _priceToken, _collateralToken, vaultAddress, coreModule, block.timestamp
        );
        emit VaultCreated(_priceToken, _collateralToken, vaultAddress, false, block.timestamp);

        return vaultAddress;
    }

    /**
     * @notice Batch create vaults
     */
    function batchCreateVaults(
        address[] calldata priceTokens,
        address[] calldata collateralTokens,
        uint256[] calldata minBetAmounts,
        uint256[] calldata maxBetAmounts,
        uint256[] calldata graduationThresholds
    ) external onlyOwner whenNotPaused returns (address[] memory vaultAddresses) {
        if (
            priceTokens.length != collateralTokens.length
                || priceTokens.length != minBetAmounts.length
                || priceTokens.length != maxBetAmounts.length
                || priceTokens.length != graduationThresholds.length
        ) revert LengthMismatch();

        if (priceTokens.length > MAX_BATCH_SIZE) revert BatchTooLarge();

        vaultAddresses = new address[](priceTokens.length);

        for (uint256 i = 0; i < priceTokens.length; i++) {
            vaultAddresses[i] = createVault(
                priceTokens[i],
                collateralTokens[i],
                minBetAmounts[i],
                maxBetAmounts[i],
                graduationThresholds[i]
            );
        }

        return vaultAddresses;
    }

    // ========================================================================
    // PROXY FUNCTIONS (Route to specific vaults)
    // ========================================================================

    /**
     * @notice Deposit collateral from bet
     */
    function depositFromBet(
        address _priceToken,
        address _collateralToken,
        uint64 positionId,
        uint256 amount,
        uint256 positionSize,
        bool isMarginAdd,
        uint8 direction
    ) external onlyPositionManager {
        // R3-I-04: not payable — collateral is ERC-20 only; ETH would be stuck with no withdrawal path
        address vaultAddress = _getVault(_collateralToken, _priceToken);
        IERC20(_collateralToken).safeTransferFrom(positionManager, vaultAddress, amount);
        IVaultRouter(vaultAddress)
            .depositFromBet(positionId, amount, positionSize, isMarginAdd, direction);
        emit CollateralDepositedFromBet(
            vaultAddress, _priceToken, _collateralToken, amount, positionSize, block.timestamp
        );
    }

    /**
     * @notice Execute payout to user
     */
    function executePayout(
        address _priceToken,
        address _collateralToken,
        address user,
        uint256 amount,
        uint64 positionId
    ) external onlyPositionManager {
        IVaultRouter(_getVault(_collateralToken, _priceToken))
            .executePayout(user, amount, positionId);
    }

    /**
     * @notice Update vault P&L
     */
    function updateVaultPnLWithLeverage(
        address _priceToken,
        address _collateralToken,
        uint64 positionId,
        uint256 collateral,
        int256 vaultPnL,
        uint256 positionSize,
        uint8 direction,
        address user,
        uint256 payout
    ) external onlyPositionManager returns (uint256 closeFee) {
        return IVaultRouter(_getVault(_collateralToken, _priceToken))
            .updateVaultPnL(positionId, collateral, vaultPnL, positionSize, direction, user, payout);
    }

    // ========================================================================
    // GOVERNANCE PROTECTED FUNCTIONS
    // ========================================================================

    /**
     * @notice Pause vault by (collateralToken, priceToken) pair
     */
    function pauseVault(address collateralToken, address priceToken) external onlyEmergencyRole {
        IVaultRouter(_getVault(collateralToken, priceToken)).pause();
    }

    /**
     * @notice Unpause vault by (collateralToken, priceToken) pair
     * @dev R3-M-01 fix: restricted to onlyOwner (Timelock) to prevent EMERGENCY_ROLE from
     *      bypassing the EMERGENCY_UNPAUSE_DELAY enforced in VaultCore.unpause().
     *      When VaultManager calls IVaultRouter.unpause(), msg.sender inside VaultCore is
     *      VaultManager (not the original caller), so the per-role delay check in VaultCore
     *      would be skipped. Restricting to onlyOwner closes this bypass path.
     */
    function unpauseVault(address collateralToken, address priceToken) external onlyOwner {
        IVaultRouter(_getVault(collateralToken, priceToken)).unpause();
    }

    /**
     * @notice Pause vault by address
     */
    function pauseVaultByAddress(address vault) public onlyEmergencyRole {
        IVaultRouter(vault).pause();
    }

    /**
     * @notice Unpause vault by address
     * @dev R3-M-01 fix: restricted to onlyOwner (Timelock) — see unpauseVault() for rationale.
     */
    function unpauseVaultByAddress(address vault) public onlyOwner {
        IVaultRouter(vault).unpause();
    }

    /**
     * @notice Batch pause vaults
     */
    function batchPauseVaults(address[] calldata vaults) external onlyEmergencyRole {
        for (uint256 i = 0; i < vaults.length; i++) {
            pauseVaultByAddress(vaults[i]);
        }
    }

    /**
     * @notice Batch unpause vaults
     * @dev R3-M-01 fix: restricted to onlyOwner (Timelock) — see unpauseVault() for rationale.
     */
    function batchUnpauseVaults(address[] calldata vaults) external onlyOwner {
        for (uint256 i = 0; i < vaults.length; i++) {
            unpauseVaultByAddress(vaults[i]);
        }
    }

    /**
     * @notice Emergency pause all vaults in a single batch (safe only when vault count is small)
     * @dev Reverts if allVaults.length > MAX_BATCH_SIZE to prevent OOG.
     *      Use emergencyPauseBatch() for paginated execution when vault count is large.
     */
    function emergencyPauseAll() external onlyEmergencyRole {
        if (allVaults.length > MAX_BATCH_SIZE) revert BatchTooLarge();
        _pause();
        _pauseVaultRange(0, allVaults.length);
        emit EmergencyPauseAllTriggered(msg.sender, block.timestamp);
    }

    /**
     * @notice Emergency pause vaults in a paginated range
     * @param startIndex First index in allVaults to process (inclusive)
     * @param count Number of vaults to process (capped at MAX_BATCH_SIZE)
     * @dev Call repeatedly with increasing startIndex until all vaults are covered.
     *      VaultManager itself is paused on the first call (startIndex == 0).
     */
    function emergencyPauseBatch(uint256 startIndex, uint256 count) external onlyEmergencyRole {
        if (count == 0 || count > MAX_BATCH_SIZE) revert BatchTooLarge();
        if (startIndex >= allVaults.length) revert InvalidBatchRange();

        if (startIndex == 0) _pause();

        uint256 end = startIndex + count;
        if (end > allVaults.length) end = allVaults.length;

        _pauseVaultRange(startIndex, end);
        emit EmergencyPauseBatchTriggered(msg.sender, startIndex, end - startIndex, block.timestamp);
    }

    /**
     * @notice Emergency unpause all vaults in a single batch (safe only when vault count is small)
     * @dev Reverts if allVaults.length > MAX_BATCH_SIZE to prevent OOG.
     *      Use emergencyUnpauseBatch() for paginated execution when vault count is large.
     *      R3-M-01 fix: restricted to onlyOwner (Timelock) to prevent EMERGENCY_ROLE from
     *      bypassing EMERGENCY_UNPAUSE_DELAY via this batch path.
     */
    function emergencyUnpauseAll() external onlyOwner {
        if (allVaults.length > MAX_BATCH_SIZE) revert BatchTooLarge();
        _unpause();
        _unpauseVaultRange(0, allVaults.length);
        emit EmergencyUnpauseAllTriggered(msg.sender, block.timestamp);
    }

    /**
     * @notice Emergency unpause vaults in a paginated range
     * @param startIndex First index in allVaults to process (inclusive)
     * @param count Number of vaults to process (capped at MAX_BATCH_SIZE)
     * @dev Call repeatedly with increasing startIndex until all vaults are covered.
     *      VaultManager itself is unpaused on the first call (startIndex == 0).
     *      R3-M-01 fix: restricted to onlyOwner (Timelock) — see emergencyUnpauseAll() for rationale.
     */
    function emergencyUnpauseBatch(uint256 startIndex, uint256 count) external onlyOwner {
        if (count == 0 || count > MAX_BATCH_SIZE) revert BatchTooLarge();
        if (startIndex >= allVaults.length) revert InvalidBatchRange();

        if (startIndex == 0) _unpause();

        uint256 end = startIndex + count;
        if (end > allVaults.length) end = allVaults.length;

        _unpauseVaultRange(startIndex, end);
        emit EmergencyUnpauseBatchTriggered(
            msg.sender, startIndex, end - startIndex, block.timestamp
        );
    }

    // ========================================================================
    // INTERNAL HELPERS
    // ========================================================================

    function _pauseVaultRange(uint256 start, uint256 end) internal {
        for (uint256 i = start; i < end; i++) {
            address vault = allVaults[i];
            if (vaultInfos[vault].isActive) {
                try IVaultRouter(vault).paused() returns (bool isPaused) {
                    if (!isPaused) {
                        try IVaultRouter(vault).pause() { } catch { }
                    }
                } catch { }
            }
        }
    }

    function _unpauseVaultRange(uint256 start, uint256 end) internal {
        for (uint256 i = start; i < end; i++) {
            address vault = allVaults[i];
            if (vaultInfos[vault].isActive) {
                try IVaultRouter(vault).paused() returns (bool isPaused) {
                    if (isPaused) {
                        try IVaultRouter(vault).unpause() { } catch { }
                    }
                } catch { }
            }
        }
    }

    // ========================================================================
    // EMERGENCY FUNCTIONS (NO TIMELOCK DELAY)
    // Uses EMERGENCY_ROLE from VaultAccessController
    // ========================================================================

    /**
     * @notice Emergency pause vault by (collateralToken, priceToken) pair (NO TIMELOCK DELAY)
     * @dev Only addresses with EMERGENCY_ROLE can call this
     */
    function emergencyPauseVault(address collateralToken, address priceToken)
        external
        onlyEmergencyRole
    {
        address vault = _getVault(collateralToken, priceToken);
        IVaultRouter(vault).pause();
        emit EmergencyPauseVault(vault, msg.sender, block.timestamp);
    }

    /**
     * @notice Emergency pause vault by address (NO TIMELOCK DELAY)
     * @param vault Vault address
     * @dev Only addresses with EMERGENCY_ROLE can call this
     */
    function emergencyPauseVaultByAddress(address vault) public onlyEmergencyRole {
        if (vaultInfos[vault].vaultAddress == address(0)) revert VaultNotFound();
        IVaultRouter(vault).pause();
        emit EmergencyPauseVault(vault, msg.sender, block.timestamp);
    }

    /**
     * @notice Emergency batch pause vaults (NO TIMELOCK DELAY)
     * @param vaults Array of vault addresses
     * @dev Only addresses with EMERGENCY_ROLE can call this
     */
    function emergencyBatchPauseVaults(address[] calldata vaults) external onlyEmergencyRole {
        for (uint256 i = 0; i < vaults.length; i++) {
            if (vaultInfos[vaults[i]].vaultAddress != address(0)) {
                try IVaultRouter(vaults[i]).pause() { } catch { }
            }
        }
        emit EmergencyBatchPauseVaults(vaults, msg.sender, block.timestamp);
    }

    /**
     * @notice Emergency unpause vault by (collateralToken, priceToken) pair (NO TIMELOCK DELAY)
     * @dev Only owner can unpause to prevent guardian abuse
     */
    function emergencyUnpauseVault(address collateralToken, address priceToken) external onlyOwner {
        address vault = _getVault(collateralToken, priceToken);
        IVaultRouter(vault).unpause();
        emit EmergencyUnpauseVault(vault, msg.sender, block.timestamp);
    }

    /**
     * @notice Emergency unpause vault by address (NO TIMELOCK DELAY)
     * @param vault Vault address
     * @dev Only owner can unpause to prevent guardian abuse
     */
    function emergencyUnpauseVaultByAddress(address vault) public onlyOwner {
        if (vaultInfos[vault].vaultAddress == address(0)) revert VaultNotFound();
        IVaultRouter(vault).unpause();
        emit EmergencyUnpauseVault(vault, msg.sender, block.timestamp);
    }

    /**
     * @notice Emergency batch unpause vaults (NO TIMELOCK DELAY)
     * @param vaults Array of vault addresses
     * @dev Only owner can unpause to prevent guardian abuse
     */
    function emergencyBatchUnpauseVaults(address[] calldata vaults) external onlyOwner {
        for (uint256 i = 0; i < vaults.length; i++) {
            if (vaultInfos[vaults[i]].vaultAddress != address(0)) {
                try IVaultRouter(vaults[i]).unpause() { } catch { }
            }
        }
        emit EmergencyBatchUnpauseVaults(vaults, msg.sender, block.timestamp);
    }

    // ========================================================================
    // VAULT MANAGEMENT
    // ========================================================================

    function deactivateVault(address vault) external onlyOwner whenNotPaused {
        IVaultManager.VaultInfo storage info = vaultInfos[vault];
        if (info.vaultAddress == address(0)) revert VaultNotFound();
        info.isActive = false;
        emit VaultDeactivated(vault, block.timestamp);
    }

    function reactivateVault(address vault) external onlyOwner whenNotPaused {
        IVaultManager.VaultInfo storage info = vaultInfos[vault];
        if (info.vaultAddress == address(0)) revert VaultNotFound();
        info.isActive = true;
        emit VaultReactivated(vault, block.timestamp);
    }

    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================

    function setPositionManager(address _positionManager) external onlyOwner whenNotPaused {
        if (_positionManager == address(0)) revert InvalidAddress();
        address oldPositionManager = positionManager;
        VaultAccessController(accessController)
            .updatePositionManagerRole(oldPositionManager, _positionManager);
        positionManager = _positionManager;
        emit PositionManagerUpdated(oldPositionManager, _positionManager);
    }

    function setAccessController(address _accessController) external onlyOwner whenNotPaused {
        if (_accessController == address(0)) revert InvalidAddress();
        address oldController = accessController;
        accessController = _accessController;
        emit AccessControllerUpdated(oldController, _accessController);
    }

    function setVaultRouterImpl(address _vaultRouterImpl) external onlyOwner whenNotPaused {
        if (_vaultRouterImpl == address(0)) revert InvalidAddress();
        address oldImpl = vaultRouterImpl;
        vaultRouterImpl = _vaultRouterImpl;
        emit VaultRouterImplUpdated(oldImpl, _vaultRouterImpl);
    }

    function setModules(address _coreModule, address _fundingModule, address _rewardsModule)
        external
        onlyOwner
        whenNotPaused
    {
        if (
            _coreModule == address(0) || _fundingModule == address(0)
                || _rewardsModule == address(0)
        ) {
            revert InvalidAddress();
        }
        // Contract existence checks
        if (_coreModule.code.length == 0) revert NotAContract(_coreModule);
        if (_fundingModule.code.length == 0) revert NotAContract(_fundingModule);
        if (_rewardsModule.code.length == 0) revert NotAContract(_rewardsModule);

        coreModule = _coreModule;
        fundingModule = _fundingModule;
        rewardsModule = _rewardsModule;
        emit ModulesUpdated(_coreModule, _fundingModule, _rewardsModule);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Authorize upgrade with Timelock + Emergency Guardian pattern
     * @dev Two paths for upgrade:
     *      1. Normal path: UPGRADER_ROLE (Timelock) - no restrictions
     *      2. Emergency path: EMERGENCY_ROLE (Multisig) - requires contract to be paused first
     *      This ensures users have opportunity to withdraw before emergency upgrades
     */
    function _authorizeUpgrade(address newImplementation) internal override {
        if (newImplementation.code.length == 0) revert NotAContract(newImplementation);

        VaultAccessController ac = VaultAccessController(accessController);

        // Path 1: Normal upgrade via Timelock (UPGRADER_ROLE)
        if (ac.hasRole(ac.UPGRADER_ROLE(), msg.sender)) {
            return; // Authorized
        }

        // Path 2: Emergency upgrade via Multisig (EMERGENCY_ROLE) - only if paused
        if (ac.hasRole(ac.EMERGENCY_ROLE(), msg.sender)) {
            if (!paused()) {
                revert MustPauseBeforeEmergencyUpgrade();
            }
            emit EmergencyUpgrade(newImplementation, msg.sender, block.timestamp);
            return; // Authorized
        }

        // No valid role - revert
        revert NotAuthorized();
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    function getVault(address collateralToken, address priceToken) external view returns (address) {
        return vaultsByPair[_vaultPairKey(collateralToken, priceToken)];
    }

    function isVaultSupported(address collateralToken, address priceToken)
        external
        view
        returns (bool)
    {
        return vaultsByPair[_vaultPairKey(collateralToken, priceToken)] != address(0);
    }

    function getAllVaults() external view returns (address[] memory) {
        return allVaults;
    }

    /// @notice Total number of vaults (use with MAX_BATCH_SIZE to calculate batch count for emergencyPauseBatch)
    function vaultCount() external view returns (uint256) {
        return allVaults.length;
    }

    function vaultPriceToken(address vaultAddress) external view returns (address priceToken) {
        return vaultInfos[vaultAddress].priceToken;
    }

    function vaultCollateralToken(address vaultAddress)
        external
        view
        returns (address collateralToken)
    {
        return vaultInfos[vaultAddress].collateralToken;
    }

    function getActiveVaults() external view returns (address[] memory active) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < allVaults.length; i++) {
            if (vaultInfos[allVaults[i]].isActive) {
                activeCount++;
            }
        }

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

    function getVaultInfo(address vault)
        external
        view
        returns (IVaultManager.VaultInfo memory info)
    {
        return vaultInfos[vault];
    }

    /**
     * @notice Get beacon proxy vaults (returns empty for modular vaults)
     * @dev Kept for backward compatibility with IVaultManager interface
     */
    function getBeaconProxyVaults() external pure returns (address[] memory beaconVaults) {
        // Modular vaults don't use BeaconProxy, return empty array
        return new address[](0);
    }

    function _vaultPairKey(address collateralToken, address priceToken)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(collateralToken, priceToken));
    }

    function _getVault(address collateralToken, address priceToken)
        internal
        view
        returns (address)
    {
        address vault = vaultsByPair[_vaultPairKey(collateralToken, priceToken)];
        if (vault == address(0) || vault.code.length == 0) {
            revert VaultNotFound();
        }
        if (!vaultInfos[vault].isActive) {
            revert VaultNotActive();
        }
        return vault;
    }

    function version() external pure returns (string memory) {
        return "3.1.0-modular";
    }
}

