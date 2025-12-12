// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "../../src/governance/MultisigWallet.sol";

contract MultisigWalletTest is Test {
    MultisigWallet public multisig;

    // Test accounts
    address public owner1;
    address public owner2;
    address public owner3;
    address public nonOwner;

    // Test target contract for transactions
    MockTarget public target;

    // Constants
    uint256 public constant THRESHOLD = 2;

    function setUp() public {
        owner1 = makeAddr("owner1");
        owner2 = makeAddr("owner2");
        owner3 = makeAddr("owner3");
        nonOwner = makeAddr("nonOwner");

        // Fund accounts
        vm.deal(owner1, 10 ether);
        vm.deal(owner2, 10 ether);
        vm.deal(owner3, 10 ether);

        // Create owners array
        address[] memory owners = new address[](3);
        owners[0] = owner1;
        owners[1] = owner2;
        owners[2] = owner3;

        // Deploy multisig with 2-of-3 threshold
        multisig = new MultisigWallet(owners, THRESHOLD);

        // Deploy mock target
        target = new MockTarget();
    }

    // ========================================================================
    // CONSTRUCTOR TESTS
    // ========================================================================

    function test_Constructor_Success() public view {
        assertEq(multisig.threshold(), THRESHOLD);
        assertEq(multisig.getOwnerCount(), 3);
        assertTrue(multisig.isOwner(owner1));
        assertTrue(multisig.isOwner(owner2));
        assertTrue(multisig.isOwner(owner3));
        assertFalse(multisig.isOwner(nonOwner));
    }

    function test_Constructor_RevertEmptyOwners() public {
        address[] memory emptyOwners = new address[](0);
        vm.expectRevert(MultisigWallet.InvalidOwner.selector);
        new MultisigWallet(emptyOwners, 1);
    }

    function test_Constructor_RevertZeroThreshold() public {
        address[] memory owners = new address[](2);
        owners[0] = owner1;
        owners[1] = owner2;
        vm.expectRevert(MultisigWallet.InvalidThreshold.selector);
        new MultisigWallet(owners, 0);
    }

    function test_Constructor_RevertThresholdTooHigh() public {
        address[] memory owners = new address[](2);
        owners[0] = owner1;
        owners[1] = owner2;
        vm.expectRevert(MultisigWallet.InvalidThreshold.selector);
        new MultisigWallet(owners, 3); // threshold > owners.length
    }

    function test_Constructor_RevertZeroAddressOwner() public {
        address[] memory owners = new address[](2);
        owners[0] = owner1;
        owners[1] = address(0);
        vm.expectRevert(MultisigWallet.InvalidOwner.selector);
        new MultisigWallet(owners, 1);
    }

    function test_Constructor_RevertDuplicateOwner() public {
        address[] memory owners = new address[](2);
        owners[0] = owner1;
        owners[1] = owner1;
        vm.expectRevert(MultisigWallet.InvalidOwner.selector);
        new MultisigWallet(owners, 1);
    }

    // ========================================================================
    // SUBMIT TRANSACTION TESTS
    // ========================================================================

    function test_SubmitTransaction_Success() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.prank(owner1);
        uint256 txId = multisig.submitTransaction(address(target), 0, data);

        assertEq(txId, 0);
        assertEq(multisig.transactionCount(), 1);

        (address to, uint256 value, bytes memory txData, bool executed, uint256 confirmationCount) =
            multisig.getTransaction(0);

        assertEq(to, address(target));
        assertEq(value, 0);
        assertEq(txData, data);
        assertFalse(executed);
        assertEq(confirmationCount, 1); // Auto-confirmed by submitter
    }

    function test_SubmitTransaction_RevertNotOwner() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.prank(nonOwner);
        vm.expectRevert(MultisigWallet.NotOwner.selector);
        multisig.submitTransaction(address(target), 0, data);
    }

    function test_SubmitTransaction_WithValue() public {
        // Fund multisig
        vm.deal(address(multisig), 1 ether);

        bytes memory data = "";

        vm.prank(owner1);
        uint256 txId = multisig.submitTransaction(address(target), 0.5 ether, data);

        (address to, uint256 value,,,) = multisig.getTransaction(txId);
        assertEq(to, address(target));
        assertEq(value, 0.5 ether);
    }

    // ========================================================================
    // CONFIRM TRANSACTION TESTS
    // ========================================================================

    function test_ConfirmTransaction_Success() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.prank(owner1);
        uint256 txId = multisig.submitTransaction(address(target), 0, data);

        // owner2 confirms
        vm.prank(owner2);
        multisig.confirmTransaction(txId);

        (,,,, uint256 confirmationCount) = multisig.getTransaction(txId);
        assertEq(confirmationCount, 2);
        assertTrue(multisig.isConfirmed(txId, owner1));
        assertTrue(multisig.isConfirmed(txId, owner2));
        assertFalse(multisig.isConfirmed(txId, owner3));
    }

    function test_ConfirmTransaction_RevertNotOwner() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.prank(owner1);
        uint256 txId = multisig.submitTransaction(address(target), 0, data);

        vm.prank(nonOwner);
        vm.expectRevert(MultisigWallet.NotOwner.selector);
        multisig.confirmTransaction(txId);
    }

    function test_ConfirmTransaction_RevertAlreadyConfirmed() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.prank(owner1);
        uint256 txId = multisig.submitTransaction(address(target), 0, data);

        // owner1 already confirmed via submit, try to confirm again
        vm.prank(owner1);
        vm.expectRevert(MultisigWallet.AlreadyConfirmed.selector);
        multisig.confirmTransaction(txId);
    }

    function test_ConfirmTransaction_RevertTxNotFound() public {
        vm.prank(owner1);
        vm.expectRevert(MultisigWallet.TransactionNotFound.selector);
        multisig.confirmTransaction(999);
    }

    function test_ConfirmTransaction_RevertAlreadyExecuted() public {
        vm.deal(address(multisig), 1 ether);
        bytes memory data = "";

        vm.prank(owner1);
        uint256 txId = multisig.submitTransaction(address(target), 0.1 ether, data);

        vm.prank(owner2);
        multisig.confirmTransaction(txId);

        vm.prank(owner1);
        multisig.executeTransaction(txId);

        // Try to confirm executed transaction
        vm.prank(owner3);
        vm.expectRevert(MultisigWallet.TransactionAlreadyExecuted.selector);
        multisig.confirmTransaction(txId);
    }

    // ========================================================================
    // REVOKE CONFIRMATION TESTS
    // ========================================================================

    function test_RevokeConfirmation_Success() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.prank(owner1);
        uint256 txId = multisig.submitTransaction(address(target), 0, data);

        vm.prank(owner2);
        multisig.confirmTransaction(txId);

        // owner2 revokes
        vm.prank(owner2);
        multisig.revokeConfirmation(txId);

        (,,,, uint256 confirmationCount) = multisig.getTransaction(txId);
        assertEq(confirmationCount, 1);
        assertFalse(multisig.isConfirmed(txId, owner2));
    }

    function test_RevokeConfirmation_RevertNotConfirmed() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.prank(owner1);
        uint256 txId = multisig.submitTransaction(address(target), 0, data);

        // owner2 hasn't confirmed, try to revoke
        vm.prank(owner2);
        vm.expectRevert(MultisigWallet.NotConfirmed.selector);
        multisig.revokeConfirmation(txId);
    }

    function test_RevokeConfirmation_RevertNotOwner() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.prank(owner1);
        uint256 txId = multisig.submitTransaction(address(target), 0, data);

        vm.prank(nonOwner);
        vm.expectRevert(MultisigWallet.NotOwner.selector);
        multisig.revokeConfirmation(txId);
    }

    // ========================================================================
    // EXECUTE TRANSACTION TESTS
    // ========================================================================

    function test_ExecuteTransaction_Success() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.prank(owner1);
        uint256 txId = multisig.submitTransaction(address(target), 0, data);

        vm.prank(owner2);
        multisig.confirmTransaction(txId);

        assertTrue(multisig.canExecute(txId));

        vm.prank(owner1);
        multisig.executeTransaction(txId);

        (,,, bool executed,) = multisig.getTransaction(txId);
        assertTrue(executed);
        assertEq(target.value(), 42);
    }

    function test_ExecuteTransaction_WithETH() public {
        vm.deal(address(multisig), 1 ether);
        bytes memory data = "";

        uint256 targetBalanceBefore = address(target).balance;

        vm.prank(owner1);
        uint256 txId = multisig.submitTransaction(address(target), 0.5 ether, data);

        vm.prank(owner2);
        multisig.confirmTransaction(txId);

        vm.prank(owner1);
        multisig.executeTransaction(txId);

        assertEq(address(target).balance, targetBalanceBefore + 0.5 ether);
    }

    function test_ExecuteTransaction_RevertNotEnoughConfirmations() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.prank(owner1);
        uint256 txId = multisig.submitTransaction(address(target), 0, data);

        // Only 1 confirmation (from submit), need 2
        assertFalse(multisig.canExecute(txId));

        vm.prank(owner1);
        vm.expectRevert(MultisigWallet.TransactionNotConfirmed.selector);
        multisig.executeTransaction(txId);
    }

    function test_ExecuteTransaction_RevertAlreadyExecuted() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.prank(owner1);
        uint256 txId = multisig.submitTransaction(address(target), 0, data);

        vm.prank(owner2);
        multisig.confirmTransaction(txId);

        vm.prank(owner1);
        multisig.executeTransaction(txId);

        // Try to execute again
        vm.prank(owner1);
        vm.expectRevert(MultisigWallet.TransactionAlreadyExecuted.selector);
        multisig.executeTransaction(txId);
    }

    function test_ExecuteTransaction_RevertExecutionFailed() public {
        // Create a transaction that will fail
        bytes memory data = abi.encodeWithSelector(MockTarget.revertingFunction.selector);

        vm.prank(owner1);
        uint256 txId = multisig.submitTransaction(address(target), 0, data);

        vm.prank(owner2);
        multisig.confirmTransaction(txId);

        vm.prank(owner1);
        vm.expectRevert(MultisigWallet.ExecutionFailed.selector);
        multisig.executeTransaction(txId);
    }

    // ========================================================================
    // OWNER MANAGEMENT TESTS
    // ========================================================================

    function test_AddOwner_Success() public {
        address newOwner = makeAddr("newOwner");

        // Create transaction to add owner
        bytes memory data = abi.encodeWithSelector(MultisigWallet.addOwner.selector, newOwner);

        vm.prank(owner1);
        uint256 txId = multisig.submitTransaction(address(multisig), 0, data);

        vm.prank(owner2);
        multisig.confirmTransaction(txId);

        vm.prank(owner1);
        multisig.executeTransaction(txId);

        assertTrue(multisig.isOwner(newOwner));
        assertEq(multisig.getOwnerCount(), 4);
    }

    function test_AddOwner_RevertNotFromMultisig() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(owner1);
        vm.expectRevert(MultisigWallet.NotOwner.selector);
        multisig.addOwner(newOwner);
    }

    function test_AddOwner_RevertZeroAddress() public {
        bytes memory data = abi.encodeWithSelector(MultisigWallet.addOwner.selector, address(0));

        vm.prank(owner1);
        uint256 txId = multisig.submitTransaction(address(multisig), 0, data);

        vm.prank(owner2);
        multisig.confirmTransaction(txId);

        vm.prank(owner1);
        vm.expectRevert(MultisigWallet.ExecutionFailed.selector);
        multisig.executeTransaction(txId);
    }

    function test_AddOwner_RevertDuplicateOwner() public {
        bytes memory data = abi.encodeWithSelector(MultisigWallet.addOwner.selector, owner1);

        vm.prank(owner1);
        uint256 txId = multisig.submitTransaction(address(multisig), 0, data);

        vm.prank(owner2);
        multisig.confirmTransaction(txId);

        vm.prank(owner1);
        vm.expectRevert(MultisigWallet.ExecutionFailed.selector);
        multisig.executeTransaction(txId);
    }

    function test_RemoveOwner_Success() public {
        // Create transaction to remove owner3
        bytes memory data = abi.encodeWithSelector(MultisigWallet.removeOwner.selector, owner3);

        vm.prank(owner1);
        uint256 txId = multisig.submitTransaction(address(multisig), 0, data);

        vm.prank(owner2);
        multisig.confirmTransaction(txId);

        vm.prank(owner1);
        multisig.executeTransaction(txId);

        assertFalse(multisig.isOwner(owner3));
        assertEq(multisig.getOwnerCount(), 2);
    }

    function test_RemoveOwner_AdjustsThreshold() public {
        // Create 2-of-2 multisig
        address[] memory owners = new address[](2);
        owners[0] = owner1;
        owners[1] = owner2;
        MultisigWallet multisig2 = new MultisigWallet(owners, 2);

        // Remove owner2 - threshold should be adjusted to 1
        bytes memory data = abi.encodeWithSelector(MultisigWallet.removeOwner.selector, owner2);

        vm.prank(owner1);
        uint256 txId = multisig2.submitTransaction(address(multisig2), 0, data);

        vm.prank(owner2);
        multisig2.confirmTransaction(txId);

        vm.prank(owner1);
        multisig2.executeTransaction(txId);

        assertEq(multisig2.threshold(), 1);
        assertEq(multisig2.getOwnerCount(), 1);
    }

    // ========================================================================
    // CHANGE THRESHOLD TESTS
    // ========================================================================

    function test_ChangeThreshold_Success() public {
        bytes memory data = abi.encodeWithSelector(MultisigWallet.changeThreshold.selector, 3);

        vm.prank(owner1);
        uint256 txId = multisig.submitTransaction(address(multisig), 0, data);

        vm.prank(owner2);
        multisig.confirmTransaction(txId);

        vm.prank(owner1);
        multisig.executeTransaction(txId);

        assertEq(multisig.threshold(), 3);
    }

    function test_ChangeThreshold_RevertZero() public {
        bytes memory data = abi.encodeWithSelector(MultisigWallet.changeThreshold.selector, 0);

        vm.prank(owner1);
        uint256 txId = multisig.submitTransaction(address(multisig), 0, data);

        vm.prank(owner2);
        multisig.confirmTransaction(txId);

        vm.prank(owner1);
        vm.expectRevert(MultisigWallet.ExecutionFailed.selector);
        multisig.executeTransaction(txId);
    }

    function test_ChangeThreshold_RevertTooHigh() public {
        bytes memory data = abi.encodeWithSelector(MultisigWallet.changeThreshold.selector, 5);

        vm.prank(owner1);
        uint256 txId = multisig.submitTransaction(address(multisig), 0, data);

        vm.prank(owner2);
        multisig.confirmTransaction(txId);

        vm.prank(owner1);
        vm.expectRevert(MultisigWallet.ExecutionFailed.selector);
        multisig.executeTransaction(txId);
    }

    // ========================================================================
    // BATCH TRANSACTION TESTS
    // ========================================================================

    function test_SubmitBatchTransactions_Success() public {
        address[] memory destinations = new address[](2);
        destinations[0] = address(target);
        destinations[1] = address(target);

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory dataArray = new bytes[](2);
        dataArray[0] = abi.encodeWithSelector(MockTarget.setValue.selector, 10);
        dataArray[1] = abi.encodeWithSelector(MockTarget.setValue.selector, 20);

        vm.prank(owner1);
        uint256[] memory txIds = multisig.submitBatchTransactions(destinations, values, dataArray);

        assertEq(txIds.length, 2);
        assertEq(txIds[0], 0);
        assertEq(txIds[1], 1);
        assertEq(multisig.transactionCount(), 2);
    }

    function test_SubmitBatchTransactions_RevertLengthMismatch() public {
        address[] memory destinations = new address[](2);
        destinations[0] = address(target);
        destinations[1] = address(target);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory dataArray = new bytes[](2);
        dataArray[0] = abi.encodeWithSelector(MockTarget.setValue.selector, 10);
        dataArray[1] = abi.encodeWithSelector(MockTarget.setValue.selector, 20);

        vm.prank(owner1);
        vm.expectRevert(MultisigWallet.InvalidArrayLength.selector);
        multisig.submitBatchTransactions(destinations, values, dataArray);
    }

    // ========================================================================
    // VIEW FUNCTION TESTS
    // ========================================================================

    function test_GetOwners() public view {
        address[] memory owners = multisig.getOwners();
        assertEq(owners.length, 3);
        assertEq(owners[0], owner1);
        assertEq(owners[1], owner2);
        assertEq(owners[2], owner3);
    }

    function test_CanExecute_True() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.prank(owner1);
        uint256 txId = multisig.submitTransaction(address(target), 0, data);

        vm.prank(owner2);
        multisig.confirmTransaction(txId);

        assertTrue(multisig.canExecute(txId));
    }

    function test_CanExecute_False_NotEnoughConfirmations() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.prank(owner1);
        uint256 txId = multisig.submitTransaction(address(target), 0, data);

        assertFalse(multisig.canExecute(txId));
    }

    function test_CanExecute_False_InvalidTxId() public view {
        assertFalse(multisig.canExecute(999));
    }

    function test_GetConfirmationCount() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        vm.prank(owner1);
        uint256 txId = multisig.submitTransaction(address(target), 0, data);

        assertEq(multisig.getConfirmationCount(txId), 1);

        vm.prank(owner2);
        multisig.confirmTransaction(txId);

        assertEq(multisig.getConfirmationCount(txId), 2);
    }

    // ========================================================================
    // RECEIVE ETH TESTS
    // ========================================================================

    function test_ReceiveETH() public {
        uint256 balanceBefore = address(multisig).balance;

        vm.deal(nonOwner, 1 ether);
        vm.prank(nonOwner);
        (bool success,) = address(multisig).call{ value: 0.5 ether }("");

        assertTrue(success);
        assertEq(address(multisig).balance, balanceBefore + 0.5 ether);
    }

    // ========================================================================
    // FUZZ TESTS
    // ========================================================================

    function testFuzz_Constructor(uint8 ownerCount, uint8 threshold) public {
        // Bound inputs to reasonable values
        ownerCount = uint8(bound(ownerCount, 1, 10));
        threshold = uint8(bound(threshold, 1, ownerCount));

        address[] memory owners = new address[](ownerCount);
        for (uint8 i = 0; i < ownerCount; i++) {
            owners[i] = address(uint160(i + 1));
        }

        MultisigWallet wallet = new MultisigWallet(owners, threshold);

        assertEq(wallet.threshold(), threshold);
        assertEq(wallet.getOwnerCount(), ownerCount);
    }

    function testFuzz_SubmitAndConfirm(uint256 value) public {
        vm.assume(value <= 1 ether);
        vm.deal(address(multisig), 10 ether);

        bytes memory data = "";

        vm.prank(owner1);
        uint256 txId = multisig.submitTransaction(address(target), value, data);

        assertEq(multisig.getConfirmationCount(txId), 1);

        vm.prank(owner2);
        multisig.confirmTransaction(txId);

        assertEq(multisig.getConfirmationCount(txId), 2);
        assertTrue(multisig.canExecute(txId));
    }
}

// ========================================================================
// MOCK TARGET CONTRACT
// ========================================================================

contract MockTarget {
    uint256 public value;

    receive() external payable { }

    function setValue(uint256 _value) external {
        value = _value;
    }

    function revertingFunction() external pure {
        revert("Always reverts");
    }
}

