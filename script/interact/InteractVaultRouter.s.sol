// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../DeployHelper.s.sol";
import "../../src/vault-modular/VaultRouter.sol";
import "../../src/vault-modular/VaultManager.sol";
import "../../src/libraries/vault/VaultStorageLib.sol";

/**
 * @title InteractVaultRouter
 * @notice Script to interact with VaultRouter (individual vault)
 * @dev Usage: Set VAULT_ADDRESS or PROJECT_TOKEN_ADDRESS in .env
 */
contract InteractVaultRouter is DeployHelper {
    VaultRouter public vault;
    VaultManager public vmgr;

    function setUp() public override {
        super.setUp();

        vmgr = VaultManager(payable(vaultManager));

        // Get vault address from env directly or via project token
        address vaultAddr = vm.envOr("VAULT_ADDRESS", address(0));

        if (vaultAddr == address(0)) {
            address projectToken = vm.envOr("PROJECT_TOKEN_ADDRESS", address(0));
            if (projectToken != address(0)) {
                vaultAddr = vmgr.getVault(projectToken);
            }
        }

        require(
            vaultAddr != address(0),
            "Vault address not found. Set VAULT_ADDRESS or PROJECT_TOKEN_ADDRESS"
        );
        vault = VaultRouter(payable(vaultAddr));
        console.log("VaultRouter Address:", address(vault));
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    function viewInfo() public view {
        console.log("\n=== VaultRouter Info ===");
        console.log("Address:", address(vault));
        console.log("Project Token:", vault.projectToken());
        console.log("Version:", vault.version());
        console.log("VaultManager:", vault.vaultManager());
        console.log("PositionManager:", vault.positionManager());
        console.log("Paused:", vault.paused());
    }

    function viewVaultInfo() public view {
        console.log("\n=== Vault State Info ===");
        VaultStorageLib.VaultInfo memory info = vault.vaultInfo();

        console.log("Total Liquidity:", info.totalLiquidity);
        console.log("Total Shares:", info.totalShares);
        console.log("Total Leverage Exposure:", info.totalLeverageExposure);
        console.log("Total Volume:", info.totalVolume);
        console.log("Trading Enabled:", info.tradingEnabled);
        console.log("Is Graduated:", info.isGraduated);
        console.log("Created At:", info.createdAt);
        console.log("Graduated At:", info.graduatedAt);
    }

    function viewVaultParams() public view {
        console.log("\n=== Vault Parameters ===");
        VaultStorageLib.VaultParams memory params = vault.vaultParams();
        VaultStorageLib.VaultInfo memory info = vault.vaultInfo();

        console.log("Min Bet Amount:", params.minBetAmount);
        console.log("Max Bet Amount:", params.maxBetAmount);
        console.log("Min Liquidity Amount:", params.minLiquidityAmount);
        console.log("Graduation Threshold:", info.graduationThreshold);
    }

    function viewFees() public view {
        console.log("\n=== Vault Fees ===");
        VaultStorageLib.VaultInfo memory info = vault.vaultInfo();

        console.log("Total Fees Collected:", info.totalFeesCollected);
        console.log("Total Staking Fees:", info.totalStakingFees);
        console.log("Total Withdrawal Fees:", info.totalWithdrawalFees);
    }

    function viewLPPosition(address user) public view {
        console.log("\n=== LP Position ===");
        console.log("User:", user);

        VaultStorageLib.LPPosition memory lpPos = vault.getLPPosition(user);

        console.log("Shares:", lpPos.shares);
        console.log("Staked Amount:", lpPos.stakedAmount);
        console.log("Staked At:", lpPos.stakedAt);
        console.log("Last Reward Claim:", lpPos.lastRewardClaim);
        console.log("Total Rewards Claimed:", lpPos.totalRewardsClaimed);
        console.log("Pending Rewards:", lpPos.pendingRewards);
    }

    function viewAllLPs() public view {
        console.log("\n=== All LPs ===");
        uint256 lpCount = vault.getVaultLPsLength();
        console.log("Total LPs:", lpCount);

        for (uint256 i = 0; i < lpCount && i < 20; i++) {
            address lp = vault.vaultLPs(i);
            VaultStorageLib.LPPosition memory lpPos = vault.getLPPosition(lp);
            console.log("LP", i, ":", lp);
            console.log("  - Shares:", lpPos.shares);
        }

        if (lpCount > 20) {
            console.log("... and", lpCount - 20, "more LPs");
        }
    }

    function viewModules() public view {
        console.log("\n=== Vault Modules ===");

        bytes4 MODULE_CORE = bytes4(keccak256("MODULE_CORE"));
        bytes4 MODULE_FUNDING = bytes4(keccak256("MODULE_FUNDING"));
        bytes4 MODULE_REWARDS = bytes4(keccak256("MODULE_REWARDS"));

        console.log("Core Module:", vault.getModule(MODULE_CORE));
        console.log("Funding Module:", vault.getModule(MODULE_FUNDING));
        console.log("Rewards Module:", vault.getModule(MODULE_REWARDS));
    }

    // ========================================================================
    // LIQUIDITY FUNCTIONS
    // ========================================================================

    function addLiquidity(uint256 amount) public {
        vm.startBroadcast(deployer);

        // Note: User needs to approve vault before calling this
        console.log("Adding liquidity:", amount);
        vault.addLiquidity(amount);
        console.log("[SUCCESS] Liquidity added");

        vm.stopBroadcast();
    }

    function removeLiquidity() public {
        vm.startBroadcast(deployer);

        console.log("Removing liquidity...");
        vault.removeLiquidity();
        console.log("[SUCCESS] Liquidity removed");

        vm.stopBroadcast();
    }

    // ========================================================================
    // REWARDS FUNCTIONS
    // ========================================================================

    function claimRewards() public {
        vm.startBroadcast(deployer);

        console.log("Claiming rewards...");
        vault.claimRewards();
        console.log("[SUCCESS] Rewards claimed");

        vm.stopBroadcast();
    }

    // ========================================================================
    // ADMIN FUNCTIONS (via VaultManager)
    // ========================================================================

    function setTradingEnabled(bool enabled) public {
        vm.startBroadcast(deployer);

        vault.setTradingEnabled(enabled);
        console.log("Trading enabled:", enabled);

        vm.stopBroadcast();
    }

    function setFee(uint8 feeType, uint16 feeBps) public {
        vm.startBroadcast(deployer);

        vault.setFee(feeType, feeBps);
        console.log("Fee type %s set to %s bps", feeType, feeBps);

        vm.stopBroadcast();
    }

    function updateVaultParams(uint256 minBet, uint256 maxBet) public {
        vm.startBroadcast(deployer);

        vault.updateVaultParams(minBet, maxBet);
        console.log("Vault params updated");
        console.log("  Min bet:", minBet);
        console.log("  Max bet:", maxBet);

        vm.stopBroadcast();
    }

    // ========================================================================
    // PRICE IMPACT CONFIG FUNCTIONS
    // ========================================================================

    function setImpactConfig(
        uint16 tier1ImpactBps,
        uint16 tier2ImpactBps,
        uint16 tier3ImpactBps,
        uint16 tier4ImpactBps,
        uint16 tier5ImpactBps
    ) public {
        vm.startBroadcast(deployer);

        vault.setImpactConfig(
            tier1ImpactBps, tier2ImpactBps, tier3ImpactBps, tier4ImpactBps, tier5ImpactBps
        );
        console.log("Impact config updated");

        vm.stopBroadcast();
    }

    // ========================================================================
    // RISK CHECK FUNCTIONS
    // ========================================================================

    function checkPositionRisk(uint256 positionSize, uint8 leverage, uint8 direction) public view {
        console.log("\n=== Position Risk Check ===");
        console.log("Position Size:", positionSize);
        console.log("Leverage:", leverage);
        console.log("Direction:", direction == 1 ? "LONG" : "SHORT");

        // This will revert if position exceeds risk limits
        vault.checkPositionRisk(positionSize, leverage, direction);
        console.log("[OK] Position passes risk checks");
    }
}
