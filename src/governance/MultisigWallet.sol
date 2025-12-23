// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title MultisigWallet
 * @notice Multi-signature wallet requiring M-of-N signatures to execute transactions
 * @dev Simple but effective design, similar to Gnosis Safe
 *
 * Features:
 * - Requires minimum number of signatures (threshold) to execute transaction
 * - Support adding/removing owners
 * - Support batch transactions
 * - Integration with Timelock for propose operations
 */
contract MultisigWallet is ReentrancyGuard {
    // ========================================================================
    // STATE VARIABLES
    // ========================================================================

    /// @notice List of owners
    address[] public owners;

    /// @notice Mapping for quick owner check
    mapping(address => bool) public isOwner;

    /// @notice Number of required signatures
    uint256 public threshold;

    /// @notice Transaction counter
    uint256 public transactionCount;

    /// @notice Transactions mapping
    mapping(uint256 => Transaction) public transactions;

    /// @notice Confirmations mapping: txId => owner => confirmed
    mapping(uint256 => mapping(address => bool)) public confirmations;

    // ========================================================================
    // STRUCTS
    // ========================================================================

    struct Transaction {
        address to;
        uint256 value;
        bytes data;
        bool executed;
        uint256 confirmationCount;
    }

    // ========================================================================
    // EVENTS
    // ========================================================================

    event OwnerAdded(address indexed owner);
    event OwnerRemoved(address indexed owner);
    event ThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event TransactionSubmitted(uint256 indexed txId, address indexed to, uint256 value, bytes data);
    event TransactionConfirmed(uint256 indexed txId, address indexed owner);
    event TransactionRevoked(uint256 indexed txId, address indexed owner);
    event TransactionReady(uint256 indexed txId);
    event TransactionExecuted(uint256 indexed txId);
    event TransactionFailed(uint256 indexed txId);
    event Deposit(address indexed sender, uint256 amount);

    // ========================================================================
    // ERRORS
    // ========================================================================

    error NotOwner();
    error InvalidOwner();
    error InvalidThreshold();
    error TransactionNotFound();
    error TransactionAlreadyExecuted();
    error TransactionNotConfirmed();
    error AlreadyConfirmed();
    error NotConfirmed();
    error ExecutionFailed();
    error InvalidArrayLength();

    // ========================================================================
    // MODIFIERS
    // ========================================================================

    modifier onlyOwner() {
        if (!isOwner[msg.sender]) revert NotOwner();
        _;
    }

    modifier txExists(uint256 txId) {
        if (txId >= transactionCount) revert TransactionNotFound();
        _;
    }

    modifier notExecuted(uint256 txId) {
        if (transactions[txId].executed) revert TransactionAlreadyExecuted();
        _;
    }

    modifier notConfirmed(uint256 txId) {
        if (confirmations[txId][msg.sender]) revert AlreadyConfirmed();
        _;
    }

    // ========================================================================
    // CONSTRUCTOR
    // ========================================================================

    /**
     * @notice Constructor
     * @param _owners List of owner addresses
     * @param _threshold Number of required signatures (M-of-N)
     */
    constructor(address[] memory _owners, uint256 _threshold) {
        if (_owners.length == 0) revert InvalidOwner();
        if (_threshold == 0 || _threshold > _owners.length) {
            revert InvalidThreshold();
        }

        for (uint256 i = 0; i < _owners.length; i++) {
            address owner = _owners[i];
            if (owner == address(0)) revert InvalidOwner();
            if (isOwner[owner]) revert InvalidOwner();

            isOwner[owner] = true;
            owners.push(owner);
        }

        threshold = _threshold;
    }

    // ========================================================================
    // RECEIVE
    // ========================================================================

    receive() external payable {
        emit Deposit(msg.sender, msg.value);
    }

    // ========================================================================
    // TRANSACTION FUNCTIONS
    // ========================================================================

    /**
     * @notice Submit a new transaction
     * @param to Target address
     * @param value ETH value
     * @param data Call data
     * @return txId Transaction ID
     */
    function submitTransaction(address to, uint256 value, bytes memory data)
        public
        onlyOwner
        returns (uint256 txId)
    {
        txId = transactionCount;

        transactions[txId] = Transaction({
            to: to, value: value, data: data, executed: false, confirmationCount: 0
        });

        transactionCount++;

        emit TransactionSubmitted(txId, to, value, data);

        // Auto-confirm from submitter
        confirmTransaction(txId);

        return txId;
    }

    /**
     * @notice Confirm a transaction
     * @param txId Transaction ID
     * @dev Does not auto-execute, must call executeTransaction() separately (Gnosis Safe pattern)
     */
    function confirmTransaction(uint256 txId)
        public
        onlyOwner
        txExists(txId)
        notExecuted(txId)
        notConfirmed(txId)
    {
        confirmations[txId][msg.sender] = true;
        transactions[txId].confirmationCount++;

        emit TransactionConfirmed(txId, msg.sender);

        // Emit event when threshold reached to notify off-chain systems
        if (transactions[txId].confirmationCount == threshold) {
            emit TransactionReady(txId);
        }
    }

    /**
     * @notice Revoke confirmation
     * @param txId Transaction ID
     */
    function revokeConfirmation(uint256 txId) external onlyOwner txExists(txId) notExecuted(txId) {
        if (!confirmations[txId][msg.sender]) revert NotConfirmed();

        confirmations[txId][msg.sender] = false;
        transactions[txId].confirmationCount--;

        emit TransactionRevoked(txId, msg.sender);
    }

    /**
     * @notice Execute a transaction that has enough confirmations
     * @param txId Transaction ID
     * @dev Must be called separately after enough confirmations (no auto-execute)
     *      The caller pays the gas cost, can estimate beforehand using canExecute()
     */
    function executeTransaction(uint256 txId)
        public
        nonReentrant
        onlyOwner
        txExists(txId)
        notExecuted(txId)
    {
        Transaction storage txn = transactions[txId];

        if (txn.confirmationCount < threshold) revert TransactionNotConfirmed();

        txn.executed = true;

        (bool success,) = txn.to.call{ value: txn.value }(txn.data);

        if (success) {
            emit TransactionExecuted(txId);
        } else {
            emit TransactionFailed(txId);
            txn.executed = false;
            revert ExecutionFailed();
        }
    }

    // ========================================================================
    // OWNER MANAGEMENT
    // ========================================================================

    /**
     * @notice Add new owner
     * @param owner Address of new owner
     * @dev Can only be called via multisig transaction
     */
    function addOwner(address owner) external {
        if (msg.sender != address(this)) revert NotOwner();
        if (owner == address(0) || isOwner[owner]) revert InvalidOwner();

        isOwner[owner] = true;
        owners.push(owner);

        emit OwnerAdded(owner);
    }

    /**
     * @notice Remove owner
     * @param owner Address of owner to remove
     * @dev Can only be called via multisig transaction
     */
    function removeOwner(address owner) external {
        if (msg.sender != address(this)) revert NotOwner();
        if (!isOwner[owner]) revert InvalidOwner();

        isOwner[owner] = false;

        // Remove from array
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == owner) {
                owners[i] = owners[owners.length - 1];
                owners.pop();
                break;
            }
        }

        // Adjust threshold if needed
        if (threshold > owners.length) {
            threshold = owners.length;
            emit ThresholdUpdated(threshold, owners.length);
        }

        emit OwnerRemoved(owner);
    }

    /**
     * @notice Change threshold
     * @param _threshold New threshold
     * @dev Can only be called via multisig transaction
     */
    function changeThreshold(uint256 _threshold) external {
        if (msg.sender != address(this)) revert NotOwner();
        if (_threshold == 0 || _threshold > owners.length) {
            revert InvalidThreshold();
        }

        uint256 oldThreshold = threshold;
        threshold = _threshold;

        emit ThresholdUpdated(oldThreshold, _threshold);
    }

    // ========================================================================
    // BATCH OPERATIONS
    // ========================================================================

    /**
     * @notice Submit and confirm multiple transactions at once
     * @param destinations Target addresses
     * @param values ETH values
     * @param dataArray Call data array
     * @return txIds Array of transaction IDs
     */
    function submitBatchTransactions(
        address[] memory destinations,
        uint256[] memory values,
        bytes[] memory dataArray
    ) external onlyOwner returns (uint256[] memory txIds) {
        if (destinations.length != values.length || destinations.length != dataArray.length) {
            revert InvalidArrayLength();
        }

        txIds = new uint256[](destinations.length);

        for (uint256 i = 0; i < destinations.length; i++) {
            txIds[i] = submitTransaction(destinations[i], values[i], dataArray[i]);
        }

        return txIds;
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /**
     * @notice Check if transaction can be executed
     * @param txId Transaction ID
     * @return True if enough confirmations and not yet executed
     */
    function canExecute(uint256 txId) external view returns (bool) {
        if (txId >= transactionCount) return false;
        Transaction storage txn = transactions[txId];
        return txn.confirmationCount >= threshold && !txn.executed;
    }

    /**
     * @notice Get number of owners
     */
    function getOwnerCount() external view returns (uint256) {
        return owners.length;
    }

    /**
     * @notice Get list of owners
     */
    function getOwners() external view returns (address[] memory) {
        return owners;
    }

    /**
     * @notice Get confirmation count for a transaction
     * @param txId Transaction ID
     */
    function getConfirmationCount(uint256 txId) external view returns (uint256) {
        return transactions[txId].confirmationCount;
    }

    /**
     * @notice Check if transaction is confirmed by owner
     * @param txId Transaction ID
     * @param owner Owner address
     */
    function isConfirmed(uint256 txId, address owner) external view returns (bool) {
        return confirmations[txId][owner];
    }

    /**
     * @notice Get transaction info
     * @param txId Transaction ID
     */
    function getTransaction(uint256 txId)
        external
        view
        returns (
            address to,
            uint256 value,
            bytes memory data,
            bool executed,
            uint256 confirmationCount
        )
    {
        Transaction storage txn = transactions[txId];
        return (txn.to, txn.value, txn.data, txn.executed, txn.confirmationCount);
    }
}
