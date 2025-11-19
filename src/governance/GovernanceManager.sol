// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @title GovernanceManager
 * @notice Base governance contract using OpenZeppelin TimelockController + AccessControl
 * @dev Generic governance logic, có thể extend cho specific contracts (Vault, Position, Settlement, etc.)
 *
 * Architecture:
 * - GovernanceManager (base) - Generic governance using OZ
 *   ├─> VaultGovernor - Vault-specific governance
 *   ├─> PositionGovernor - PositionManager governance
 *   └─> SettlementGovernor - SettlementEngine governance
 *
 * Uses OpenZeppelin (Battle-tested):
 * - TimelockController for delay mechanism
 * - AccessControl for role-based permissions
 * 
 * Workflow:
 * 1. Proposer calls scheduleOperation()
 * 2. TimelockController queues with delay (24-48h)
 * 3. After delay, Executor calls executeOperation()
 * 4. Canceller can cancel before execution
 *
 * Roles (AccessControl):
 * - DEFAULT_ADMIN_ROLE: Can manage all roles
 * - PROPOSER_ROLE: Can schedule operations
 * - EXECUTOR_ROLE: Can execute after delay
 * - CANCELLER_ROLE: Can cancel operations
 */
contract GovernanceManager is AccessControl {
    // ========================================================================
    // ROLES (OpenZeppelin AccessControl)
    // ========================================================================

    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 public constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");

    // ========================================================================
    // STATE VARIABLES
    // ========================================================================
    
    /// @notice OpenZeppelin TimelockController
    TimelockController public immutable timelockController;

    /// @notice Primary multisig wallet (optional tracking)
    /// @dev Can have multiple proposers via AccessControl, this tracks the primary one
    address public multisigWallet;
    
    // ========================================================================
    // EVENTS
    // ========================================================================
    
    event OperationScheduled(
        bytes32 indexed id,
        address indexed target,
        uint256 value,
        bytes data,
        bytes32 salt,
        uint256 delay
    );

    event OperationExecuted(bytes32 indexed id, address indexed target);

    event OperationCancelled(bytes32 indexed id);

    event MultisigWalletUpdated(
        address indexed oldMultisig,
        address indexed newMultisig
    );
    
    // ========================================================================
    // ERRORS
    // ========================================================================
    
    error InvalidAddress();
    error ExecutionFailed();
    error NotProposer();
    error NotExecutor();
    error NotCanceller();
    
    // ========================================================================
    // MODIFIERS
    // ========================================================================
    
    modifier onlyProposer() {
        if (!hasRole(PROPOSER_ROLE, msg.sender)) revert NotProposer();
        _;
    }

    modifier onlyExecutor() {
        if (!hasRole(EXECUTOR_ROLE, msg.sender)) revert NotExecutor();
        _;
    }

    modifier onlyCanceller() {
        if (!hasRole(CANCELLER_ROLE, msg.sender)) revert NotCanceller();
        _;
    }
    
    // ========================================================================
    // CONSTRUCTOR
    // ========================================================================
    
    /**
     * @notice Constructor
     * @param _timelockController OpenZeppelin TimelockController address
     * @param _admin Admin address (will have all roles initially)
     * @param _multisigWallet Primary multisig wallet address (optional, can be address(0))
     */
    constructor(
        address _timelockController,
        address _admin,
        address _multisigWallet
    ) {
        if (_timelockController == address(0) || _admin == address(0)) {
            revert InvalidAddress();
        }
        
        timelockController = TimelockController(payable(_timelockController));
        multisigWallet = _multisigWallet;

        // Setup roles for admin
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(PROPOSER_ROLE, _admin);
        _grantRole(EXECUTOR_ROLE, _admin);
        _grantRole(CANCELLER_ROLE, _admin);

        // Grant PROPOSER_ROLE to multisig if provided
        if (_multisigWallet != address(0)) {
            _grantRole(PROPOSER_ROLE, _multisigWallet);
        }
    }
    
    // ========================================================================
    // SCHEDULE OPERATIONS (via TimelockController)
    // ========================================================================
    
    /**
     * @notice Schedule operation via OpenZeppelin TimelockController
     * @param target Target contract
     * @param value ETH value
     * @param data Call data
     * @param predecessor Predecessor operation (0 if none)
     * @param salt Salt for uniqueness
     * @param delay Custom delay (0 = use minimum delay)
     * @return id Operation ID (hash)
     */
    function scheduleOperation(
        address target,
        uint256 value,
        bytes memory data,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) public onlyProposer returns (bytes32 id) {
        if (target == address(0)) revert InvalidAddress();
        
        // Use minimum delay if not specified
        uint256 actualDelay = delay == 0
            ? timelockController.getMinDelay()
            : delay;

        // Schedule via TimelockController (low-level call to handle bytes memory -> calldata)
        (bool success, ) = address(timelockController).call(
            abi.encodeWithSignature(
                "schedule(address,uint256,bytes,bytes32,bytes32,uint256)",
            target,
            value,
            data,
                predecessor,
                salt,
                actualDelay
            )
        );

        if (!success) revert ExecutionFailed();

        // Calculate operation ID (same as TimelockController hashOperation)
        id = keccak256(abi.encode(target, value, data, predecessor, salt));

        emit OperationScheduled(id, target, value, data, salt, actualDelay);

        return id;
    }

    /**
     * @notice Schedule batch operations
     * @param targets Array of target contracts
     * @param values Array of ETH values
     * @param payloads Array of call data
     * @param predecessor Predecessor operation
     * @param salt Salt
     * @param delay Custom delay
     * @return id Batch operation ID
     */
    function scheduleBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata payloads,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) public onlyProposer returns (bytes32 id) {
        // Use minimum delay if not specified
        uint256 actualDelay = delay == 0
            ? timelockController.getMinDelay()
            : delay;

        // Schedule batch via TimelockController
        timelockController.scheduleBatch(
            targets,
            values,
            payloads,
            predecessor,
            salt,
            actualDelay
        );

        // Calculate operation ID
        id = timelockController.hashOperationBatch(
            targets,
            values,
            payloads,
            predecessor,
            salt
        );

        emit OperationScheduled(id, address(0), 0, "", salt, actualDelay);

        return id;
    }

    // ========================================================================
    // EXECUTE OPERATIONS (via TimelockController)
    // ========================================================================

    /**
     * @notice Execute operation after delay
     * @param target Target contract
     * @param value ETH value
     * @param data Call data
     * @param predecessor Predecessor operation
     * @param salt Salt (must match schedule)
     */
    function executeOperation(
        address target,
        uint256 value,
        bytes memory data,
        bytes32 predecessor,
        bytes32 salt
    ) public onlyExecutor {
        // Execute via TimelockController (low-level call to handle bytes memory -> calldata)
        (bool success, ) = address(timelockController).call(
            abi.encodeWithSignature(
                "execute(address,uint256,bytes,bytes32,bytes32)",
            target,
            value,
            data,
                predecessor,
                salt
            )
        );

        if (!success) revert ExecutionFailed();

        bytes32 id = keccak256(abi.encode(target, value, data, predecessor, salt));

        emit OperationExecuted(id, target);
    }

    /**
     * @notice Execute batch operations
     * @param targets Array of target contracts
     * @param values Array of ETH values
     * @param payloads Array of call data
     * @param predecessor Predecessor operation
     * @param salt Salt (must match schedule)
     */
    function executeBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata payloads,
        bytes32 predecessor,
        bytes32 salt
    ) public onlyExecutor {
        // Execute batch via TimelockController
        timelockController.executeBatch(
            targets,
            values,
            payloads,
            predecessor,
            salt
        );

        bytes32 id = timelockController.hashOperationBatch(
            targets,
            values,
            payloads,
            predecessor,
            salt
        );

        emit OperationExecuted(id, address(0));
    }

    // ========================================================================
    // CANCEL OPERATIONS
    // ========================================================================

    /**
     * @notice Cancel operation before execution
     * @param id Operation ID
     */
    function cancelOperation(bytes32 id) public onlyCanceller {
        timelockController.cancel(id);

        emit OperationCancelled(id);
    }
    
    // ========================================================================
    // VIEW FUNCTIONS (TimelockController queries)
    // ========================================================================
    
    /**
     * @notice Check if operation is pending
     * @param id Operation ID
     */
    function isOperationPending(bytes32 id) public view returns (bool) {
        return timelockController.isOperationPending(id);
    }

    /**
     * @notice Check if operation is ready to execute
     * @param id Operation ID
     */
    function isOperationReady(bytes32 id) public view returns (bool) {
        return timelockController.isOperationReady(id);
    }

    /**
     * @notice Check if operation is done
     * @param id Operation ID
     */
    function isOperationDone(bytes32 id) public view returns (bool) {
        return timelockController.isOperationDone(id);
    }

    /**
     * @notice Get operation timestamp (when it can be executed)
     * @param id Operation ID
     */
    function getTimestamp(bytes32 id) public view returns (uint256) {
        return timelockController.getTimestamp(id);
    }

    /**
     * @notice Get minimum delay
     */
    function getMinDelay() public view returns (uint256) {
        return timelockController.getMinDelay();
    }

    /**
     * @notice Hash operation (for ID calculation)
     */
    function hashOperation(
        address target,
        uint256 value,
        bytes memory data,
        bytes32 predecessor,
        bytes32 salt
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(target, value, data, predecessor, salt));
    }
    
    // ========================================================================
    // ROLE MANAGEMENT (via AccessControl)
    // ========================================================================
    
    /**
     * @notice Grant proposer role
     * @param account Account address
     */
    function grantProposer(
        address account
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(PROPOSER_ROLE, account);
    }

    /**
     * @notice Grant executor role
     * @param account Account address
     */
    function grantExecutor(
        address account
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(EXECUTOR_ROLE, account);
    }

    /**
     * @notice Grant canceller role
     * @param account Account address
     */
    function grantCanceller(
        address account
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(CANCELLER_ROLE, account);
    }

    /**
     * @notice Revoke proposer role
     * @param account Account address
     */
    function revokeProposer(
        address account
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(PROPOSER_ROLE, account);
    }

    /**
     * @notice Revoke executor role
     * @param account Account address
     */
    function revokeExecutor(
        address account
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(EXECUTOR_ROLE, account);
    }

    /**
     * @notice Revoke canceller role
     * @param account Account address
     */
    function revokeCanceller(
        address account
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(CANCELLER_ROLE, account);
    }
    
    // ========================================================================
    // MULTISIG MANAGEMENT
    // ========================================================================
    
    /**
     * @notice Update primary multisig wallet
     * @dev This only updates tracking variable, roles must be managed separately
     * @param _newMultisig New multisig wallet address
     */
    function updateMultisigWallet(
        address _newMultisig
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address oldMultisig = multisigWallet;
        multisigWallet = _newMultisig;

        emit MultisigWalletUpdated(oldMultisig, _newMultisig);
    }

    /**
     * @notice Check if address is a proposer
     * @param account Address to check
     * @return bool True if account has PROPOSER_ROLE
     */
    function isProposer(address account) external view returns (bool) {
        return hasRole(PROPOSER_ROLE, account);
    }

    /**
     * @notice Check if address is an executor
     * @param account Address to check
     * @return bool True if account has EXECUTOR_ROLE
     */
    function isExecutor(address account) external view returns (bool) {
        return hasRole(EXECUTOR_ROLE, account);
    }

    /**
     * @notice Check if address is a canceller
     * @param account Address to check
     * @return bool True if account has CANCELLER_ROLE
     */
    function isCanceller(address account) external view returns (bool) {
        return hasRole(CANCELLER_ROLE, account);
    }
}

