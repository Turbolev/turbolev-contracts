// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../PositionModuleBase.sol";
import "../../libraries/PositionLib.sol";
import "../../libraries/MathLib.sol";
import "../../interfaces/IVaultManager.sol";
import "../../interfaces/IAssetVault.sol";
import "../../interfaces/ISettlementEngine.sol";

/**
 * @title PositionPendingClose
 * @notice Module for processing pending close requests
 * @dev Handles:
 *      - Processing pending close positions
 *      - Cancelling pending close requests
 *      - Settlement for pending positions
 */
contract PositionPendingClose is PositionModuleBase {
    using PositionLib for PositionLib.Position;

    // ========================================================================
    // EVENTS
    // ========================================================================

    event PositionClosed(
        uint64 indexed positionId,
        address indexed user,
        address indexed projectToken,
        bool won,
        uint256 payout,
        uint256 closePrice,
        int256 pnl,
        uint256 closeTimestamp,
        uint256 pricePublishTime,
        PositionStorageLib.PositionClosedBy closedBy,
        uint256 totalFee,
        int256 fundingOwed
    );

    event BetLiquidated(
        uint64 indexed positionId,
        address indexed user,
        uint256 liquidationPrice,
        uint256 liquidationFee,
        uint256 timestamp
    );

    event PendingCloseProcessed(
        uint64 indexed positionId, bool success, PositionStorageLib.PendingCloseReason reason
    );

    event FundingSettled(
        uint64 indexed positionId,
        address indexed user,
        int256 fundingAmount,
        uint8 direction,
        uint256 timestamp
    );

    // ========================================================================
    // PENDING CLOSE FUNCTIONS
    // ========================================================================

    /**
     * @notice Process pending close positions
     * @param maxPositions Maximum number of positions to process
     */
    function processPendingClosePositions(uint256 maxPositions)
        external
        nonReentrant
        onlyPositionKeeper
    {
        PositionStorageLib.PendingCloseStorage storage pending =
            PositionStorageLib.getPendingCloseStorage();

        uint256 processed = 0;
        uint256 i = 0;

        while (i < pending.pendingClosePositionIds.length && processed < maxPositions) {
            uint64 positionId = pending.pendingClosePositionIds[i];

            bool success = _processSinglePendingClose(positionId);

            if (success) {
                processed++;
            } else {
                i++;
            }
        }
    }

    /**
     * @notice Cancel pending close request
     */
    function cancelPendingClose(uint64 positionId) external nonReentrant onlyPositionKeeper {
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();
        PositionLib.Position storage pos = core.positions[positionId];

        if (pos.user == address(0)) revert PositionNotFound();
        if (pos.state != PositionLib.POSITION_STATE_PENDING_CLOSE) {
            revert NoPendingCloseRequest();
        }

        // Revert to OPEN state
        pos.state = PositionLib.POSITION_STATE_OPEN;
        pos.lastModifiedTimestamp = block.timestamp;

        // Remove from pending queue
        _removePendingCloseRequest(positionId);

        emit PendingCloseProcessed(
            positionId, false, PositionStorageLib.PendingCloseReason.CANCELLED_BY_ADMIN
        );
    }

    // ========================================================================
    // INTERNAL FUNCTIONS
    // ========================================================================

    /**
     * @notice Process a single pending close position
     */
    function _processSinglePendingClose(uint64 positionId) internal returns (bool success) {
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();
        PositionStorageLib.PendingCloseStorage storage pending =
            PositionStorageLib.getPendingCloseStorage();

        PositionStorageLib.PendingCloseRequest memory request =
            pending.pendingCloseRequests[positionId];
        PositionLib.Position storage pos = core.positions[positionId];

        // Skip if position no longer in pending state
        if (pos.state != PositionLib.POSITION_STATE_PENDING_CLOSE) {
            _removePendingCloseRequest(positionId);
            return false;
        }

        // Check settlement engine is set
        if (core.settlementEngine == address(0)) {
            emit PendingCloseProcessed(
                positionId, false, PositionStorageLib.PendingCloseReason.SETTLEMENT_ENGINE_NOT_SET
            );
            return false;
        }

        // Close position using saved price
        (bool closed, PositionStorageLib.PendingCloseReason reason) =
            _tryClosePendingPosition(positionId, request, pos);

        emit PendingCloseProcessed(positionId, closed, reason);
        return closed;
    }

    /**
     * @notice Try to close a pending position using saved price
     */
    function _tryClosePendingPosition(
        uint64 positionId,
        PositionStorageLib.PendingCloseRequest memory request,
        PositionLib.Position storage pos
    ) internal returns (bool success, PositionStorageLib.PendingCloseReason reason) {
        // Validate saved price
        if (request.closePrice == 0) {
            return (false, PositionStorageLib.PendingCloseReason.INVALID_PRICE);
        }

        // Close position using saved price
        bool isLiquidation = PositionLib.isLiquidated(pos, request.closePrice);
        _processSettlement(
            positionId,
            request.closePrice,
            isLiquidation,
            request.pricePublishTime,
            PositionStorageLib.PositionClosedBy.PENDING_CLOSE_REQUESTED
        );
        _removePendingCloseRequest(positionId);

        return (true, PositionStorageLib.PendingCloseReason.NONE);
    }

    /**
     * @notice Remove position from pending close queue
     */
    function _removePendingCloseRequest(uint64 positionId) internal {
        PositionStorageLib.PendingCloseStorage storage pending =
            PositionStorageLib.getPendingCloseStorage();

        if (!pending.isPendingClose[positionId]) return;

        delete pending.pendingCloseRequests[positionId];
        pending.isPendingClose[positionId] = false;

        // Remove from array
        uint256 length = pending.pendingClosePositionIds.length;
        for (uint256 i = 0; i < length; i++) {
            if (pending.pendingClosePositionIds[i] == positionId) {
                pending.pendingClosePositionIds[i] = pending.pendingClosePositionIds[length - 1];
                pending.pendingClosePositionIds.pop();
                break;
            }
        }
    }

    /**
     * @notice Process settlement for pending close
     */
    function _processSettlement(
        uint64 positionId,
        uint256 closePrice,
        bool isLiquidation,
        uint256 pricePublishTime,
        PositionStorageLib.PositionClosedBy closedBy
    ) internal {
        PositionStorageLib.CoreStorage storage core = PositionStorageLib.getCoreStorage();
        PositionLib.Position storage pos = core.positions[positionId];

        if (core.settlementEngine == address(0) || core.vaultManager == address(0)) {
            revert InvalidAddress();
        }
        address vaultAddress = IVaultManager(core.vaultManager).getVault(pos.projectToken);
        if (vaultAddress == address(0)) revert InvalidAddress();

        // Process settlement
        (
            bool won,
            uint256 payout,
            uint256 settlementFee,
            int256 pnl,
            int256 vaultPnL,
            uint8 finalState,
        ) = ISettlementEngine(core.settlementEngine)
            .processSettlement(pos, closePrice, isLiquidation);

        // Calculate funding
        int256 fundingOwed = IAssetVault(vaultAddress)
            .calculatePositionFunding(
                pos.entryFundingRateLong, pos.entryFundingRateShort, pos.positionSize, pos.direction
            );

        // Adjust payout by funding
        uint256 adjustedPayout = payout;
        if (fundingOwed > 0) {
            uint256 fundingDeduction = uint256(fundingOwed);
            if (fundingDeduction >= adjustedPayout) {
                adjustedPayout = 0;
            } else {
                adjustedPayout -= fundingDeduction;
            }
            vaultPnL += fundingOwed;
        } else if (fundingOwed < 0) {
            uint256 fundingReceived = uint256(-fundingOwed);
            adjustedPayout += fundingReceived;
            vaultPnL += fundingOwed;
        }

        // Emit funding event
        if (fundingOwed != 0) {
            emit FundingSettled(positionId, pos.user, fundingOwed, pos.direction, block.timestamp);
        }

        // Update vault P&L
        uint256 closeFee = IVaultManager(core.vaultManager)
            .updateVaultPnLWithLeverage(
                pos.projectToken,
                positionId,
                pos.amount,
                vaultPnL,
                pos.positionSize,
                pos.direction,
                pos.user
            );

        // Deduct close fee
        if (closeFee > 0 && adjustedPayout > closeFee) {
            adjustedPayout -= closeFee;
        } else if (closeFee > 0) {
            adjustedPayout = 0;
        }

        // Execute payout
        if (adjustedPayout > 0) {
            IVaultManager(core.vaultManager)
                .executePayout(pos.projectToken, pos.user, adjustedPayout, positionId);
        }

        // Emit liquidation event if applicable
        if (isLiquidation) {
            uint256 effectiveLiquidationFeeBps =
                ISettlementEngine(core.settlementEngine).liquidationFeeBps();
            if (effectiveLiquidationFeeBps == 0) {
                effectiveLiquidationFeeBps = PositionLib.LIQUIDATION_FEE_BPS;
            }
            uint256 liquidationFee =
                (pos.amount * effectiveLiquidationFeeBps) / MathLib.BASIS_POINTS;

            emit BetLiquidated(positionId, pos.user, closePrice, liquidationFee, block.timestamp);
        }

        // Update position state
        pos.closePrice = closePrice;
        pos.state = finalState;
        pos.lastModifiedTimestamp = block.timestamp;

        emit PositionClosed(
            positionId,
            pos.user,
            pos.projectToken,
            won,
            adjustedPayout,
            closePrice,
            pnl,
            block.timestamp,
            pricePublishTime,
            closedBy,
            settlementFee + closeFee,
            fundingOwed
        );
    }
}

