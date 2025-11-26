// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IVaultBeacon.sol";

interface IVault {
    function totalShares() external view returns (uint256);
    function lpPositions(address user)
        external
        view
        returns (
            address,
            uint256 shares,
            uint256 stakedAmount,
            uint256 stakedAt,
            uint256 lastRewardClaim,
            uint256 totalRewardsClaimed,
            uint256 lastProcessedDay,
            uint256 pendingRewards
        );
}

/**
 * @title OptInUpgradeManager
 * @notice Quản lý upgrades cho vaults theo mô hình GMX/Hyperliquid
 * @dev LP-friendly upgrade system: LP không rút = tự động opt-in
 *
 * Flow (đơn giản, không có threshold):
 * 1. Admin propose upgrade (qua Timelock + Multisig)
 * 2. Grace period bắt đầu (24-48h)
 * 3. LPs muốn rút → rút trong grace period
 * 4. Sau grace period → AUTO EXECUTE upgrade
 * 5. LPs không rút = coi như đồng ý upgrade
 *
 * No TVL threshold - tránh governance deadlock
 * Simple opt-in: withdraw = opt-out, stay = opt-in
 */
contract OptInUpgradeManager is Ownable {
    // ========================================================================
    // STATE VARIABLES
    // ========================================================================

    /// @notice Beacon contract address
    address public beacon;

    /// @notice Timelock controller address
    address public timelockController;

    /// @notice Upgrade proposals per vault
    mapping(address => UpgradeProposal) public upgradeProposals;

    /// @notice Emergency upgrade override (bypass grace period)
    bool public emergencyOverride;

    /// @notice Emergency override timestamp
    uint256 public emergencyOverrideTimestamp;

    /// @notice Default grace period (24-48h)
    uint256 public defaultGracePeriod = 48 hours;

    /// @notice Minimum grace period (24h)
    uint256 public constant MIN_GRACE_PERIOD = 24 hours;

    /// @notice Maximum grace period (7 days)
    uint256 public constant MAX_GRACE_PERIOD = 7 days;

    /// @notice Emergency override duration
    uint256 public constant EMERGENCY_OVERRIDE_DURATION = 7 days;

    // ========================================================================
    // STRUCTS
    // ========================================================================

    struct UpgradeProposal {
        address newImplementation;
        uint256 proposedAt;
        uint256 gracePeriodEnd;
        bool executed;
        bool cancelled;
    }

    // ========================================================================
    // EVENTS
    // ========================================================================

    event UpgradeProposed(
        address indexed vault,
        address indexed newImplementation,
        uint256 proposedAt,
        uint256 gracePeriodEnd
    );

    event UpgradeExecuted(
        address indexed vault, address indexed newImplementation, uint256 timestamp
    );

    event UpgradeCancelled(address indexed vault, uint256 timestamp);

    event EmergencyOverrideEnabled(uint256 timestamp, uint256 expiresAt);
    event EmergencyOverrideDisabled(uint256 timestamp);
    event BeaconUpdated(address indexed oldBeacon, address indexed newBeacon);
    event TimelockUpdated(address indexed oldTimelock, address indexed newTimelock);
    event GracePeriodUpdated(uint256 oldPeriod, uint256 newPeriod);

    // ========================================================================
    // ERRORS
    // ========================================================================

    error NotAuthorized();
    error InvalidAddress();
    error NoActiveProposal();
    error ProposalAlreadyExists();
    error ProposalAlreadyExecuted();
    error ProposalCancelled();
    error GracePeriodNotEnded();
    error InvalidGracePeriod();
    error OnlyTimelock();

    // ========================================================================
    // MODIFIERS
    // ========================================================================

    modifier onlyTimelock() {
        if (msg.sender != timelockController) revert OnlyTimelock();
        _;
    }

    // ========================================================================
    // CONSTRUCTOR
    // ========================================================================

    constructor(address _beacon, address _timelockController, address _owner) Ownable(_owner) {
        if (_beacon == address(0) || _timelockController == address(0)) {
            revert InvalidAddress();
        }

        beacon = _beacon;
        timelockController = _timelockController;
    }

    // ========================================================================
    // PROPOSAL FUNCTIONS
    // ========================================================================

    /**
     * @notice Propose upgrade cho vault (only timelock/governance)
     * @param vault Vault address
     * @param newImplementation New implementation address
     * @param customGracePeriod Custom grace period (0 = use default 48h)
     */
    function proposeUpgrade(address vault, address newImplementation, uint256 customGracePeriod)
        external
        onlyTimelock
    {
        if (vault == address(0) || newImplementation == address(0)) {
            revert InvalidAddress();
        }

        UpgradeProposal storage proposal = upgradeProposals[vault];

        // Check if there's an active proposal
        if (proposal.proposedAt > 0 && !proposal.executed && !proposal.cancelled) {
            revert ProposalAlreadyExists();
        }

        // Use custom or default grace period
        uint256 gracePeriod = customGracePeriod > 0 ? customGracePeriod : defaultGracePeriod;

        // Validate grace period
        if (gracePeriod < MIN_GRACE_PERIOD || gracePeriod > MAX_GRACE_PERIOD) {
            revert InvalidGracePeriod();
        }

        // Create proposal (no threshold check)
        upgradeProposals[vault] = UpgradeProposal({
            newImplementation: newImplementation,
            proposedAt: block.timestamp,
            gracePeriodEnd: block.timestamp + gracePeriod,
            executed: false,
            cancelled: false
        });

        emit UpgradeProposed(
            vault, newImplementation, block.timestamp, block.timestamp + gracePeriod
        );
    }

    /**
     * @notice Cancel upgrade proposal
     * @param vault Vault address
     */
    function cancelUpgrade(address vault) external onlyOwner {
        UpgradeProposal storage proposal = upgradeProposals[vault];

        if (proposal.proposedAt == 0) revert NoActiveProposal();
        if (proposal.executed) revert ProposalAlreadyExecuted();
        if (proposal.cancelled) revert ProposalCancelled();

        proposal.cancelled = true;

        emit UpgradeCancelled(vault, block.timestamp);
    }

    // ========================================================================
    // EXECUTE UPGRADE
    // ========================================================================

    /**
     * @notice Execute upgrade after grace period
     * @param vault Vault address
     * @dev No threshold check - auto execute after grace period
     */
    function executeUpgrade(address vault) external {
        UpgradeProposal storage proposal = upgradeProposals[vault];

        // Check proposal exists and is active
        if (proposal.proposedAt == 0) revert NoActiveProposal();
        if (proposal.executed) revert ProposalAlreadyExecuted();
        if (proposal.cancelled) revert ProposalCancelled();

        // Check grace period has ended
        if (block.timestamp < proposal.gracePeriodEnd) {
            revert GracePeriodNotEnded();
        }

        // Mark as executed
        proposal.executed = true;

        // Call beacon to upgrade vault
        IVaultBeacon(beacon).setVaultImplementation(vault, proposal.newImplementation);

        emit UpgradeExecuted(vault, proposal.newImplementation, block.timestamp);
    }

    // ========================================================================
    // EMERGENCY OVERRIDE
    // ========================================================================

    /**
     * @notice Enable emergency override (bypass opt-in)
     */
    function enableEmergencyOverride() external onlyTimelock {
        emergencyOverride = true;
        emergencyOverrideTimestamp = block.timestamp;

        emit EmergencyOverrideEnabled(
            block.timestamp, block.timestamp + EMERGENCY_OVERRIDE_DURATION
        );
    }

    /**
     * @notice Disable emergency override
     */
    function disableEmergencyOverride() external onlyOwner {
        emergencyOverride = false;
        emit EmergencyOverrideDisabled(block.timestamp);
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /**
     * @notice Check if vault can upgrade
     * @param vault Vault address
     * @return canUpgrade True if can upgrade
     */
    function canVaultUpgrade(address vault) external view returns (bool) {
        // Check emergency override first
        if (emergencyOverride) {
            if (block.timestamp <= emergencyOverrideTimestamp + EMERGENCY_OVERRIDE_DURATION) {
                return true;
            }
        }

        UpgradeProposal storage proposal = upgradeProposals[vault];

        // No proposal or not executed yet
        if (proposal.proposedAt == 0 || !proposal.executed) {
            return false;
        }

        return true;
    }

    /**
     * @notice Get upgrade proposal details
     * @param vault Vault address
     * @return proposal Upgrade proposal
     */
    function getUpgradeProposal(address vault) external view returns (UpgradeProposal memory) {
        return upgradeProposals[vault];
    }

    /**
     * @notice Check if upgrade is ready to execute
     * @param vault Vault address
     * @return ready True if ready
     * @return reason Reason if not ready
     */
    function isUpgradeReady(address vault)
        external
        view
        returns (bool ready, string memory reason)
    {
        UpgradeProposal storage proposal = upgradeProposals[vault];

        if (proposal.proposedAt == 0) {
            return (false, "No active proposal");
        }

        if (proposal.executed) {
            return (false, "Already executed");
        }

        if (proposal.cancelled) {
            return (false, "Proposal cancelled");
        }

        if (block.timestamp < proposal.gracePeriodEnd) {
            return (false, "Grace period not ended");
        }

        return (true, "");
    }

    /**
     * @notice Get time remaining in grace period
     * @param vault Vault address
     * @return remaining Time remaining in seconds (0 if ended)
     */
    function getGracePeriodRemaining(address vault) external view returns (uint256) {
        UpgradeProposal storage proposal = upgradeProposals[vault];

        if (proposal.proposedAt == 0 || proposal.executed || proposal.cancelled) {
            return 0;
        }

        if (block.timestamp >= proposal.gracePeriodEnd) {
            return 0;
        }

        return proposal.gracePeriodEnd - block.timestamp;
    }

    /**
     * @notice Check if emergency override is active
     * @return active True if active
     */
    function isEmergencyOverrideActive() external view returns (bool) {
        if (!emergencyOverride) return false;
        return block.timestamp <= emergencyOverrideTimestamp + EMERGENCY_OVERRIDE_DURATION;
    }

    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================

    /**
     * @notice Update beacon address
     * @param _beacon New beacon address
     */
    function updateBeacon(address _beacon) external onlyOwner {
        if (_beacon == address(0)) revert InvalidAddress();
        address oldBeacon = beacon;
        beacon = _beacon;
        emit BeaconUpdated(oldBeacon, _beacon);
    }

    /**
     * @notice Update timelock address
     * @param _timelockController New timelock address
     */
    function updateTimelock(address _timelockController) external onlyOwner {
        if (_timelockController == address(0)) revert InvalidAddress();
        address oldTimelock = timelockController;
        timelockController = _timelockController;
        emit TimelockUpdated(oldTimelock, _timelockController);
    }

    /**
     * @notice Update default grace period
     * @param _gracePeriod New grace period
     */
    function updateDefaultGracePeriod(uint256 _gracePeriod) external onlyOwner {
        if (_gracePeriod < MIN_GRACE_PERIOD || _gracePeriod > MAX_GRACE_PERIOD) {
            revert InvalidGracePeriod();
        }
        uint256 oldPeriod = defaultGracePeriod;
        defaultGracePeriod = _gracePeriod;
        emit GracePeriodUpdated(oldPeriod, _gracePeriod);
    }
}
