// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/TokenFaucet.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title MockToken
 * @dev Mock ERC20 token để test faucet
 */
contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1_000_000 * 10 ** 18); // Mint 1 triệu token
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title TokenFaucetTest
 * @dev Test suite cho TokenFaucet contract
 */
contract TokenFaucetTest is Test {
    TokenFaucet public faucet;
    TokenFaucet public implementation;
    MockToken public token;
    ERC1967Proxy public proxy;

    address public owner;
    address public user1;
    address public user2;

    uint256 public constant CLAIM_AMOUNT = 100 * 10 ** 18; // 100 tokens
    uint256 public constant INITIAL_DEPOSIT = 10_000 * 10 ** 18; // 10,000 tokens

    event TokensClaimed(address indexed user, uint256 amount);
    event TokensDeposited(address indexed admin, uint256 amount);
    event TokensWithdrawn(address indexed admin, uint256 amount);
    event ClaimAmountUpdated(uint256 oldAmount, uint256 newAmount);

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy mock token
        token = new MockToken();

        // Deploy implementation
        implementation = new TokenFaucet();

        // Deploy proxy và initialize
        bytes memory initData =
            abi.encodeWithSelector(TokenFaucet.initialize.selector, address(token), CLAIM_AMOUNT);
        proxy = new ERC1967Proxy(address(implementation), initData);
        faucet = TokenFaucet(address(proxy));

        // Approve và deposit token vào faucet
        token.approve(address(faucet), INITIAL_DEPOSIT);
        faucet.deposit(INITIAL_DEPOSIT);
    }

    // ============ Initialize Tests ============

    function test_Initialize() public view {
        assertEq(address(faucet.token()), address(token));
        assertEq(faucet.claimAmount(), CLAIM_AMOUNT);
        assertEq(faucet.owner(), owner);
    }

    function test_CannotInitializeTwice() public {
        vm.expectRevert();
        faucet.initialize(address(token), CLAIM_AMOUNT);
    }

    function test_CannotInitializeWithZeroAddress() public {
        TokenFaucet newImplementation = new TokenFaucet();
        bytes memory initData =
            abi.encodeWithSelector(TokenFaucet.initialize.selector, address(0), CLAIM_AMOUNT);
        vm.expectRevert(TokenFaucet.InvalidTokenAddress.selector);
        new ERC1967Proxy(address(newImplementation), initData);
    }

    function test_CannotInitializeWithZeroAmount() public {
        TokenFaucet newImplementation = new TokenFaucet();
        bytes memory initData =
            abi.encodeWithSelector(TokenFaucet.initialize.selector, address(token), 0);
        vm.expectRevert(TokenFaucet.InvalidClaimAmount.selector);
        new ERC1967Proxy(address(newImplementation), initData);
    }

    // ============ Claim Tests ============

    function test_Claim() public {
        uint256 balanceBefore = token.balanceOf(user1);

        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit TokensClaimed(user1, CLAIM_AMOUNT);
        faucet.claim();

        uint256 balanceAfter = token.balanceOf(user1);
        assertEq(balanceAfter - balanceBefore, CLAIM_AMOUNT);
        assertTrue(faucet.hasClaimed(user1));
        assertEq(faucet.totalClaimers(), 1);
        assertEq(faucet.totalClaimed(), CLAIM_AMOUNT);
    }

    function test_CannotClaimTwice() public {
        vm.startPrank(user1);
        faucet.claim();

        vm.expectRevert(TokenFaucet.AlreadyClaimed.selector);
        faucet.claim();
        vm.stopPrank();
    }

    function test_MultipleUsersClaim() public {
        vm.prank(user1);
        faucet.claim();

        vm.prank(user2);
        faucet.claim();

        assertTrue(faucet.hasClaimed(user1));
        assertTrue(faucet.hasClaimed(user2));
        assertEq(faucet.totalClaimers(), 2);
        assertEq(faucet.totalClaimed(), CLAIM_AMOUNT * 2);
    }

    function test_CannotClaimWhenPaused() public {
        faucet.pause();

        vm.prank(user1);
        vm.expectRevert();
        faucet.claim();
    }

    function test_CannotClaimWhenInsufficientBalance() public {
        // Withdraw hết token
        faucet.withdraw(token.balanceOf(address(faucet)));

        vm.prank(user1);
        vm.expectRevert(TokenFaucet.InsufficientFaucetBalance.selector);
        faucet.claim();
    }

    // ============ Deposit Tests ============

    function test_Deposit() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        uint256 balanceBefore = token.balanceOf(address(faucet));

        token.approve(address(faucet), depositAmount);

        vm.expectEmit(true, false, false, true);
        emit TokensDeposited(owner, depositAmount);
        faucet.deposit(depositAmount);

        uint256 balanceAfter = token.balanceOf(address(faucet));
        assertEq(balanceAfter - balanceBefore, depositAmount);
    }

    function test_OnlyOwnerCanDeposit() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        token.transfer(user1, depositAmount);

        vm.startPrank(user1);
        token.approve(address(faucet), depositAmount);

        vm.expectRevert();
        faucet.deposit(depositAmount);
        vm.stopPrank();
    }

    // ============ Withdraw Tests ============

    function test_Withdraw() public {
        uint256 withdrawAmount = 1000 * 10 ** 18;
        uint256 balanceBefore = token.balanceOf(owner);

        vm.expectEmit(true, false, false, true);
        emit TokensWithdrawn(owner, withdrawAmount);
        faucet.withdraw(withdrawAmount);

        uint256 balanceAfter = token.balanceOf(owner);
        assertEq(balanceAfter - balanceBefore, withdrawAmount);
    }

    function test_OnlyOwnerCanWithdraw() public {
        vm.prank(user1);
        vm.expectRevert();
        faucet.withdraw(1000 * 10 ** 18);
    }

    // ============ SetClaimAmount Tests ============

    function test_SetClaimAmount() public {
        uint256 newAmount = 200 * 10 ** 18;

        vm.expectEmit(false, false, false, true);
        emit ClaimAmountUpdated(CLAIM_AMOUNT, newAmount);
        faucet.setClaimAmount(newAmount);

        assertEq(faucet.claimAmount(), newAmount);
    }

    function test_CannotSetClaimAmountToZero() public {
        vm.expectRevert(TokenFaucet.InvalidClaimAmount.selector);
        faucet.setClaimAmount(0);
    }

    function test_OnlyOwnerCanSetClaimAmount() public {
        vm.prank(user1);
        vm.expectRevert();
        faucet.setClaimAmount(200 * 10 ** 18);
    }

    function test_ClaimWithNewAmount() public {
        uint256 newAmount = 200 * 10 ** 18;
        faucet.setClaimAmount(newAmount);

        uint256 balanceBefore = token.balanceOf(user1);
        vm.prank(user1);
        faucet.claim();

        uint256 balanceAfter = token.balanceOf(user1);
        assertEq(balanceAfter - balanceBefore, newAmount);
    }

    // ============ Pause/Unpause Tests ============

    function test_Pause() public {
        faucet.pause();
        assertTrue(faucet.paused());
    }

    function test_Unpause() public {
        faucet.pause();
        faucet.unpause();
        assertFalse(faucet.paused());
    }

    function test_OnlyOwnerCanPause() public {
        vm.prank(user1);
        vm.expectRevert();
        faucet.pause();
    }

    function test_OnlyOwnerCanUnpause() public {
        faucet.pause();
        vm.prank(user1);
        vm.expectRevert();
        faucet.unpause();
    }

    // ============ Reset Claim Status Tests ============

    function test_ResetClaimStatus() public {
        vm.prank(user1);
        faucet.claim();
        assertTrue(faucet.hasClaimed(user1));

        faucet.resetClaimStatus(user1);
        assertFalse(faucet.hasClaimed(user1));
        assertEq(faucet.totalClaimers(), 0);
    }

    function test_ResetClaimStatusBatch() public {
        vm.prank(user1);
        faucet.claim();
        vm.prank(user2);
        faucet.claim();

        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        faucet.resetClaimStatusBatch(users);
        assertFalse(faucet.hasClaimed(user1));
        assertFalse(faucet.hasClaimed(user2));
        assertEq(faucet.totalClaimers(), 0);
    }

    function test_OnlyOwnerCanResetClaimStatus() public {
        vm.prank(user1);
        vm.expectRevert();
        faucet.resetClaimStatus(user2);
    }

    function test_CanClaimAgainAfterReset() public {
        // Claim lần đầu
        vm.prank(user1);
        faucet.claim();

        // Reset
        faucet.resetClaimStatus(user1);

        // Claim lại
        vm.prank(user1);
        faucet.claim();

        assertTrue(faucet.hasClaimed(user1));
    }

    // ============ View Functions Tests ============

    function test_GetFaucetBalance() public view {
        assertEq(faucet.getFaucetBalance(), INITIAL_DEPOSIT);
    }

    function test_HasEnoughTokens() public view {
        assertTrue(faucet.hasEnoughTokens());
    }

    function test_HasEnoughTokens_False() public {
        // Withdraw hầu hết token
        faucet.withdraw(INITIAL_DEPOSIT - CLAIM_AMOUNT + 1);
        assertFalse(faucet.hasEnoughTokens());
    }

    function test_GetRemainingClaims() public view {
        uint256 expected = INITIAL_DEPOSIT / CLAIM_AMOUNT;
        assertEq(faucet.getRemainingClaims(), expected);
    }

    function test_HasUserClaimed() public {
        assertFalse(faucet.hasUserClaimed(user1));

        vm.prank(user1);
        faucet.claim();

        assertTrue(faucet.hasUserClaimed(user1));
    }

    function test_CanUserClaim() public view {
        (bool canClaim, string memory reason) = faucet.canUserClaim(user1);
        assertTrue(canClaim);
        assertEq(reason, "");
    }

    function test_CanUserClaim_AlreadyClaimed() public {
        vm.prank(user1);
        faucet.claim();

        (bool canClaim, string memory reason) = faucet.canUserClaim(user1);
        assertFalse(canClaim);
        assertEq(reason, "Already claimed");
    }

    function test_CanUserClaim_Paused() public {
        faucet.pause();

        (bool canClaim, string memory reason) = faucet.canUserClaim(user1);
        assertFalse(canClaim);
        assertEq(reason, "Faucet is paused");
    }

    function test_CanUserClaim_InsufficientBalance() public {
        faucet.withdraw(token.balanceOf(address(faucet)));

        (bool canClaim, string memory reason) = faucet.canUserClaim(user1);
        assertFalse(canClaim);
        assertEq(reason, "Insufficient faucet balance");
    }

    function test_GetFaucetInfo() public view {
        (
            uint256 faucetBalance,
            uint256 _claimAmount,
            uint256 _totalClaimers,
            uint256 _totalClaimed,
            uint256 remainingClaims,
            bool isPaused
        ) = faucet.getFaucetInfo();

        assertEq(faucetBalance, INITIAL_DEPOSIT);
        assertEq(_claimAmount, CLAIM_AMOUNT);
        assertEq(_totalClaimers, 0);
        assertEq(_totalClaimed, 0);
        assertEq(remainingClaims, INITIAL_DEPOSIT / CLAIM_AMOUNT);
        assertFalse(isPaused);
    }

    // ============ Fuzzing Tests ============

    function testFuzz_Claim(address user) public {
        vm.assume(user != address(0));
        vm.assume(user.code.length == 0); // Not a contract

        uint256 balanceBefore = token.balanceOf(user);

        vm.prank(user);
        faucet.claim();

        uint256 balanceAfter = token.balanceOf(user);
        assertEq(balanceAfter - balanceBefore, CLAIM_AMOUNT);
        assertTrue(faucet.hasClaimed(user));
    }

    function testFuzz_SetClaimAmount(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount <= INITIAL_DEPOSIT);

        faucet.setClaimAmount(amount);
        assertEq(faucet.claimAmount(), amount);
    }

    // ============ Integration Tests ============

    function test_FullWorkflow() public {
        // 1. User1 claim
        vm.prank(user1);
        faucet.claim();
        assertEq(token.balanceOf(user1), CLAIM_AMOUNT);

        // 2. Update claim amount
        uint256 newAmount = 150 * 10 ** 18;
        faucet.setClaimAmount(newAmount);

        // 3. User2 claim với amount mới
        vm.prank(user2);
        faucet.claim();
        assertEq(token.balanceOf(user2), newAmount);

        // 4. Pause faucet
        faucet.pause();

        // 5. User không thể claim khi paused
        vm.prank(makeAddr("user3"));
        vm.expectRevert();
        faucet.claim();

        // 6. Unpause
        faucet.unpause();

        // 7. User3 có thể claim
        address user3 = makeAddr("user3");
        vm.prank(user3);
        faucet.claim();
        assertEq(token.balanceOf(user3), newAmount);

        // 8. Check statistics
        assertEq(faucet.totalClaimers(), 3);
        assertEq(faucet.totalClaimed(), CLAIM_AMOUNT + newAmount + newAmount);
    }
}
