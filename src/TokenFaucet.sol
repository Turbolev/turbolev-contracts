// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title TokenFaucet
 * @dev Token faucet contract with the following features:
 * - Upgradeable: Can be upgraded in the future
 * - Ownable: Only owner has management rights
 * - ReentrancyGuard: Protected from reentrancy attacks
 * - Pausable: Can be paused when necessary
 * - One claim per user
 * - Admin can deposit tokens
 * - Adjustable claim amount
 */
contract TokenFaucet is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    // ============ State Variables ============

    /// @notice Token distributed by the faucet
    IERC20 public token;

    /// @notice Amount of tokens each user can claim
    uint256 public claimAmount;

    /// @notice Mapping to track whether a user has claimed
    mapping(address => bool) public hasClaimed;

    /// @notice Total number of users who have claimed
    uint256 public totalClaimers;

    /// @notice Total amount of tokens claimed
    uint256 public totalClaimed;

    // ============ Storage Gap ============

    /// @dev Storage gap to allow for new variables in future versions
    /// @notice Currently using 5 storage slots (token, claimAmount, hasClaimed, totalClaimers, totalClaimed)
    /// @notice Reserving 45 slots for future use (total 50 slots)
    uint256[45] private __gap;

    // ============ Events ============

    event TokensClaimed(address indexed user, uint256 amount);
    event TokensDeposited(address indexed admin, uint256 amount);
    event TokensWithdrawn(address indexed admin, uint256 amount);
    event ClaimAmountUpdated(uint256 oldAmount, uint256 newAmount);

    // ============ Errors ============

    error AlreadyClaimed();
    error InsufficientFaucetBalance();
    error InvalidClaimAmount();
    error InvalidTokenAddress();

    // ============ Initializer ============

    /**
     * @dev Initialize contract (replaces constructor for upgradeable contracts)
     * @param _token Address of the token contract
     * @param _claimAmount Amount of tokens each user can claim
     */
    function initialize(
        address _token,
        uint256 _claimAmount
    ) public initializer {
        if (_token == address(0)) revert InvalidTokenAddress();
        if (_claimAmount == 0) revert InvalidClaimAmount();

        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __Pausable_init();

        token = IERC20(_token);
        claimAmount = _claimAmount;
    }

    // ============ External Functions ============

    /**
     * @notice User claims tokens from faucet
     * @dev Each user can only claim once
     */
    function claim() external nonReentrant whenNotPaused {
        if (hasClaimed[msg.sender]) revert AlreadyClaimed();

        uint256 balance = token.balanceOf(address(this));
        if (balance < claimAmount) revert InsufficientFaucetBalance();

        // Mark user as claimed (Checks-Effects-Interactions pattern)
        hasClaimed[msg.sender] = true;
        totalClaimers++;
        totalClaimed += claimAmount;

        // Transfer tokens to user
        token.safeTransfer(msg.sender, claimAmount);

        emit TokensClaimed(msg.sender, claimAmount);
    }

    /**
     * @notice Admin deposits tokens into faucet
     * @param amount Amount of tokens to deposit
     */
    function deposit(uint256 amount) external onlyOwner {
        token.transferFrom(msg.sender, address(this), amount);
        emit TokensDeposited(msg.sender, amount);
    }

    /**
     * @notice Admin withdraws tokens from faucet (emergency)
     * @param amount Amount of tokens to withdraw
     */
    function withdraw(uint256 amount) external onlyOwner {
        token.safeTransfer(msg.sender, amount);
        emit TokensWithdrawn(msg.sender, amount);
    }

    /**
     * @notice Admin updates claim amount
     * @param newAmount New token amount per claim
     */
    function setClaimAmount(uint256 newAmount) external onlyOwner {
        if (newAmount == 0) revert InvalidClaimAmount();

        uint256 oldAmount = claimAmount;
        claimAmount = newAmount;

        emit ClaimAmountUpdated(oldAmount, newAmount);
    }

    /**
     * @notice Pause the faucet
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Resume faucet operations
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Reset claim status for a user (owner only, for special cases)
     * @param user Address of user to reset
     */
    function resetClaimStatus(address user) external onlyOwner {
        if (hasClaimed[user]) {
            hasClaimed[user] = false;
            totalClaimers--;
        }
    }

    /**
     * @notice Reset claim status for multiple users
     * @param users Array of user addresses to reset
     */
    function resetClaimStatusBatch(
        address[] calldata users
    ) external onlyOwner {
        for (uint256 i = 0; i < users.length; i++) {
            if (hasClaimed[users[i]]) {
                hasClaimed[users[i]] = false;
                totalClaimers--;
            }
        }
    }

    // ============ View Functions ============

    /**
     * @notice Check token balance in faucet
     * @return Amount of tokens remaining
     */
    function getFaucetBalance() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    /**
     * @notice Check if faucet has enough tokens to claim
     * @return true if there are enough tokens
     */
    function hasEnoughTokens() external view returns (bool) {
        return token.balanceOf(address(this)) >= claimAmount;
    }

    /**
     * @notice Check how many more claims can be made
     * @return Number of remaining claims
     */
    function getRemainingClaims() external view returns (uint256) {
        uint256 balance = token.balanceOf(address(this));
        if (balance < claimAmount) return 0;
        return balance / claimAmount;
    }

    /**
     * @notice Check if user has claimed
     * @param user Address of user to check
     * @return true if already claimed
     */
    function hasUserClaimed(address user) external view returns (bool) {
        return hasClaimed[user];
    }

    /**
     * @notice Check if user can claim
     * @param user Address of user to check
     * @return canClaim true if can claim
     * @return reason Reason why cannot claim (if applicable)
     */
    function canUserClaim(
        address user
    ) external view returns (bool canClaim, string memory reason) {
        if (paused()) {
            return (false, "Faucet is paused");
        }

        if (hasClaimed[user]) {
            return (false, "Already claimed");
        }

        if (token.balanceOf(address(this)) < claimAmount) {
            return (false, "Insufficient faucet balance");
        }

        return (true, "");
    }

    /**
     * @notice Get faucet overview information
     * @return faucetBalance Token balance in faucet
     * @return _claimAmount Amount of tokens per claim
     * @return _totalClaimers Total number of users who have claimed
     * @return _totalClaimed Total amount of tokens claimed
     * @return remainingClaims Number of remaining claims
     * @return isPaused Whether the faucet is paused
     */
    function getFaucetInfo()
        external
        view
        returns (
            uint256 faucetBalance,
            uint256 _claimAmount,
            uint256 _totalClaimers,
            uint256 _totalClaimed,
            uint256 remainingClaims,
            bool isPaused
        )
    {
        faucetBalance = token.balanceOf(address(this));
        _claimAmount = claimAmount;
        _totalClaimers = totalClaimers;
        _totalClaimed = totalClaimed;
        remainingClaims = faucetBalance >= claimAmount
            ? faucetBalance / claimAmount
            : 0;
        isPaused = paused();
    }
}
