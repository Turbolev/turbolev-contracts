// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title MultisigWallet
 * @notice Multi-signature wallet yêu cầu M-of-N signatures để thực thi transactions
 * @dev Thiết kế đơn giản nhưng hiệu quả, tương tự Gnosis Safe
 *
 * Chức năng:
 * - Yêu cầu số lượng chữ ký tối thiểu (threshold) để execute transaction
 * - Hỗ trợ thêm/xóa owners
 * - Hỗ trợ batch transactions
 * - Tích hợp với Timelock để tạo propose operations
 */
contract MultisigWallet {
    // ========================================================================
    // STATE VARIABLES
    // ========================================================================

    /// @notice Danh sách owners
    address[] public owners;

    /// @notice Mapping để check owner nhanh
    mapping(address => bool) public isOwner;

    /// @notice Số lượng signatures cần thiết
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
     * @param _owners Danh sách owner addresses
     * @param _threshold Số lượng signatures cần thiết (M-of-N)
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
     * @notice Submit một transaction mới
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

        transactions[txId] =
            Transaction({ to: to, value: value, data: data, executed: false, confirmationCount: 0 });

        transactionCount++;

        emit TransactionSubmitted(txId, to, value, data);

        // Auto-confirm from submitter
        confirmTransaction(txId);

        return txId;
    }

    /**
     * @notice Confirm một transaction
     * @param txId Transaction ID
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

        // Auto-execute if threshold reached
        if (transactions[txId].confirmationCount >= threshold) {
            executeTransaction(txId);
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
     * @notice Execute một transaction đã được confirm đủ
     * @param txId Transaction ID
     */
    function executeTransaction(uint256 txId) public onlyOwner txExists(txId) notExecuted(txId) {
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
     * @notice Thêm owner mới
     * @param owner Address của owner mới
     * @dev Chỉ có thể gọi qua multisig transaction
     */
    function addOwner(address owner) external {
        if (msg.sender != address(this)) revert NotOwner();
        if (owner == address(0) || isOwner[owner]) revert InvalidOwner();

        isOwner[owner] = true;
        owners.push(owner);

        emit OwnerAdded(owner);
    }

    /**
     * @notice Xóa owner
     * @param owner Address của owner cần xóa
     * @dev Chỉ có thể gọi qua multisig transaction
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
     * @notice Thay đổi threshold
     * @param _threshold Threshold mới
     * @dev Chỉ có thể gọi qua multisig transaction
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
     * @notice Submit và confirm nhiều transactions cùng lúc
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
     * @notice Lấy số lượng owners
     */
    function getOwnerCount() external view returns (uint256) {
        return owners.length;
    }

    /**
     * @notice Lấy danh sách owners
     */
    function getOwners() external view returns (address[] memory) {
        return owners;
    }

    /**
     * @notice Lấy số lượng confirmations của một transaction
     * @param txId Transaction ID
     */
    function getConfirmationCount(uint256 txId) external view returns (uint256) {
        return transactions[txId].confirmationCount;
    }

    /**
     * @notice Kiểm tra xem transaction đã được confirm bởi owner chưa
     * @param txId Transaction ID
     * @param owner Owner address
     */
    function isConfirmed(uint256 txId, address owner) external view returns (bool) {
        return confirmations[txId][owner];
    }

    /**
     * @notice Lấy thông tin transaction
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
