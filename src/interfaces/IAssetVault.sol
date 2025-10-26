// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IAssetVault
 * @notice Interface for AssetVault contract
 */
interface IAssetVault {
    struct VaultInfo {
        address tokenAddress;
        uint256 totalLiquidity;
        uint256 activeLiquidity;
        uint256 reservedLiquidity;
        uint256 totalShares;
        uint256 lifetimePnL;
        bool isNegativePnL;
        uint256 totalVolume;
        uint256 totalPositionsSettled;
        uint256 totalLeverageExposure;
        uint256 maxLeverageExposure;
        bool isPaused;
        bool isInitialized;
        uint256 createdAt;
    }

    struct VaultParams {
        uint16 maxPayoutBps;
        uint16 perBetUtilBps;
        uint16 maxUtilizationBps;
        uint256 minBetAmount;
        uint256 maxBetAmount;
        uint16 maxLeverageExposureBps;
    }

    struct LPPosition {
        address user;
        uint256 shares;
        uint256 stakedAmount;
        uint256 stakedAt;
        uint256 lastRewardClaim;
        uint256 totalRewardsClaimed;
    }

    /**
     * @notice Add liquidity to vault
     * @param amount Amount of tokens
     */
    function addLiquidity(uint256 amount) external payable;

    /**
     * @notice Remove liquidity from vault
     * @param shares Amount of shares to burn
     */
    function removeLiquidity(uint256 shares) external;

    /**
     * @notice Deposit collateral from bet
     * @param amount Collateral amount
     * @param positionSize Position size
     */
    function depositFromBet(
        uint256 amount,
        uint256 positionSize
    ) external payable;

    /**
     * @notice Execute payout to user
     * @param user User address
     * @param amount Payout amount
     */
    function executePayout(address user, uint256 amount) external;

    /**
     * @notice Update vault P&L
     * @param collateral Collateral amount
     * @param vaultPnL Vault P&L
     * @param fee Fee collected
     * @param positionSize Position size
     */
    function updateVaultPnL(
        uint256 collateral,
        int256 vaultPnL,
        uint256 fee,
        uint256 positionSize
    ) external;

    /**
     * @notice Check position risk
     * @param positionSize Position size
     * @param leverage Leverage multiplier
     * @return canOpen Whether position can be opened
     * @return reason Reason if cannot open
     */
    function checkPositionRisk(
        uint256 positionSize,
        uint8 leverage
    ) external view returns (bool canOpen, string memory reason);

    /**
     * @notice Get vault info
     */
    function getVaultInfo() external view returns (VaultInfo memory);

    /**
     * @notice Get vault parameters
     */
    function getVaultParams() external view returns (VaultParams memory);

    /**
     * @notice Get LP position
     * @param user User address
     */
    function getLPPosition(
        address user
    ) external view returns (LPPosition memory);

    /**
     * @notice Set PositionManager contract address
     * @param _positionManager PositionManager address
     */
    function setPositionManager(address _positionManager) external;

    /**
     * @notice Pause vault
     */
    function pause() external;

    /**
     * @notice Unpause vault
     */
    function unpause() external;
}
