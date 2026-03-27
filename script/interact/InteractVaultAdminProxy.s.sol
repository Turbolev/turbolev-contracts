// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../../src/vault-modular/VaultAdminProxy.sol";
import "../../src/vault-modular/VaultAccessController.sol";
import "../../src/interfaces/IVaultRouter.sol";
import "../../src/interfaces/IVaultManager.sol";

/**
 * @title InteractVaultAdminProxy
 * @notice Script to interact with VaultAdminProxy contract
 * @dev Example usage:
 *
 * # View operations
 * forge script script/interact/InteractVaultAdminProxy.s.sol:InteractVaultAdminProxy \
 *     --rpc-url $RPC_URL \
 *     --sig "viewStatus()"
 *
 * # Batch update funding (as keeper)
 * forge script script/interact/InteractVaultAdminProxy.s.sol:InteractVaultAdminProxy \
 *     --rpc-url $RPC_URL \
 *     --broadcast \
 *     --sig "batchUpdateFunding()"
 *
 * # Pause vault (as admin)
 * forge script script/interact/InteractVaultAdminProxy.s.sol:InteractVaultAdminProxy \
 *     --rpc-url $RPC_URL \
 *     --broadcast \
 *     --sig "pauseVault(address)" $PROJECT_TOKEN
 */
contract InteractVaultAdminProxy is Script {
    VaultAdminProxy public adminProxy;
    address public deployer;

    function setUp() public {
        adminProxy = VaultAdminProxy(vm.envAddress("VAULT_ADMIN_PROXY"));
        deployer = vm.envAddress("DEPLOYER_ADDRESS");
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    function viewStatus() public view {
        console.log("\n=== VaultAdminProxy Status ===");
        console.log("Address:", address(adminProxy));
        console.log("Version:", adminProxy.version());
        console.log("VaultManager:", adminProxy.vaultManager());
        console.log("AccessController:", adminProxy.accessController());
        console.log("PriceFeedManager:", adminProxy.priceFeedManager());

        address[] memory vaults = adminProxy.getAllVaults();
        console.log("\n--- Registered Vaults ---");
        console.log("Total count:", vaults.length);

        for (uint256 i = 0; i < vaults.length; i++) {
            console.log("Vault", i, ":", vaults[i]);
        }
    }

    function checkVault(address projectToken) public view {
        address vault = adminProxy.getVault(projectToken);
        console.log("\n=== Vault Info ===");
        console.log("Project Token:", projectToken);
        console.log("Vault Address:", vault);
        console.log("Is Supported:", adminProxy.isVaultSupported(projectToken));

        if (vault != address(0)) {
            IVaultRouter v = IVaultRouter(vault);
            IVaultRouter.VaultInfo memory info = v.getVaultInfo();

            console.log("\n--- Vault Details ---");
            console.log("Total Liquidity:", info.totalLiquidity);
            console.log("Total Shares:", info.totalShares);
            console.log("Is Graduated:", info.isGraduated);
            console.log("Trading Enabled:", info.tradingEnabled);
            console.log("Is Paused:", v.paused());
            console.log("Impact Enabled:", v.isImpactEnabled());
        }
    }

    // ========================================================================
    // BATCH OPERATIONS (KEEPER)
    // ========================================================================

    function batchUpdateFunding() public {
        console.log("\n=== Batch Update Funding ===");

        vm.startBroadcast(deployer);
        uint256 updated = adminProxy.batchUpdateHourlyFunding();
        vm.stopBroadcast();

        console.log("Vaults updated:", updated);
    }

    function batchUpdateFundingForVaults(address[] calldata vaults) public {
        console.log("\n=== Batch Update Funding for Vaults ===");

        vm.startBroadcast(deployer);
        uint256 updated = adminProxy.batchUpdateHourlyFundingForVaults(vaults);
        vm.stopBroadcast();

        console.log("Vaults updated:", updated);
    }

    // ========================================================================
    // VAULT ADMIN OPERATIONS
    // ========================================================================

    function pauseVault(address projectToken) public {
        console.log("\n=== Pause Vault ===");
        console.log("Project Token:", projectToken);

        vm.startBroadcast(deployer);
        adminProxy.pauseVault(projectToken);
        vm.stopBroadcast();

        console.log("[SUCCESS] Vault paused");
    }

    function unpauseVault(address projectToken) public {
        console.log("\n=== Unpause Vault ===");
        console.log("Project Token:", projectToken);

        vm.startBroadcast(deployer);
        adminProxy.unpauseVault(projectToken);
        vm.stopBroadcast();

        console.log("[SUCCESS] Vault unpaused");
    }

    function updateVaultParams(address projectToken, uint256 minBet, uint256 maxBet) public {
        console.log("\n=== Update Vault Params ===");
        console.log("Project Token:", projectToken);
        console.log("Min Bet:", minBet);
        console.log("Max Bet:", maxBet);

        vm.startBroadcast(deployer);
        adminProxy.updateVaultParams(projectToken, minBet, maxBet);
        vm.stopBroadcast();

        console.log("[SUCCESS] Vault params updated");
    }

    function setVaultStakingFee(address projectToken, uint16 feeBps) public {
        console.log("\n=== Set Staking Fee ===");
        console.log("Project Token:", projectToken);
        console.log("Fee (bps):", feeBps);

        vm.startBroadcast(deployer);
        adminProxy.setVaultStakingFeeBps(projectToken, feeBps);
        vm.stopBroadcast();

        console.log("[SUCCESS] Staking fee updated");
    }

    function setVaultEarlyWithdrawalFee(address projectToken, uint16 feeBps) public {
        console.log("\n=== Set Early Withdrawal Fee ===");
        console.log("Project Token:", projectToken);
        console.log("Fee (bps):", feeBps);

        vm.startBroadcast(deployer);
        adminProxy.setVaultEarlyWithdrawalFeeBps(projectToken, feeBps);
        vm.stopBroadcast();

        console.log("[SUCCESS] Early withdrawal fee updated");
    }

    function setVaultTradingEnabled(address projectToken, bool enabled) public {
        console.log("\n=== Set Trading Enabled ===");
        console.log("Project Token:", projectToken);
        console.log("Enabled:", enabled);

        vm.startBroadcast(deployer);
        adminProxy.setVaultTradingEnabled(projectToken, enabled);
        vm.stopBroadcast();

        console.log("[SUCCESS] Trading enabled updated");
    }

    function setVaultGraduationThreshold(address projectToken, uint256 threshold) public {
        console.log("\n=== Set Graduation Threshold ===");
        console.log("Project Token:", projectToken);
        console.log("Threshold:", threshold);

        vm.startBroadcast(deployer);
        adminProxy.setVaultGraduationThreshold(projectToken, threshold);
        vm.stopBroadcast();

        console.log("[SUCCESS] Graduation threshold updated");
    }

    function setVaultTreasury(address projectToken, address treasury) public {
        console.log("\n=== Set Treasury ===");
        console.log("Project Token:", projectToken);
        console.log("Treasury:", treasury);

        vm.startBroadcast(deployer);
        adminProxy.setVaultTreasury(projectToken, treasury);
        vm.stopBroadcast();

        console.log("[SUCCESS] Treasury updated");
    }

    function setTreasuryForAllVaults(address treasury) public {
        console.log("\n=== Set Treasury for All Vaults ===");
        console.log("Treasury:", treasury);

        vm.startBroadcast(deployer);
        adminProxy.setTreasuryForAllVaults(treasury);
        vm.stopBroadcast();

        console.log("[SUCCESS] Treasury updated for all vaults");
    }

    function setVaultImpactEnabled(address projectToken, bool enabled) public {
        console.log("\n=== Set Impact Enabled ===");
        console.log("Project Token:", projectToken);
        console.log("Enabled:", enabled);

        vm.startBroadcast(deployer);
        adminProxy.setVaultImpactEnabled(projectToken, enabled);
        vm.stopBroadcast();

        console.log("[SUCCESS] Impact enabled updated");
    }

    function setImpactEnabledForAllVaults(bool enabled) public {
        console.log("\n=== Set Impact Enabled for All Vaults ===");
        console.log("Enabled:", enabled);

        vm.startBroadcast(deployer);
        adminProxy.setImpactEnabledForAllVaults(enabled);
        vm.stopBroadcast();

        console.log("[SUCCESS] Impact enabled updated for all vaults");
    }

    function setVaultImpactConfig(
        address projectToken,
        uint16 tier1,
        uint16 tier2,
        uint16 tier3,
        uint16 tier4,
        uint16 tier5
    ) public {
        console.log("\n=== Set Impact Config ===");
        console.log("Project Token:", projectToken);
        console.log("Tier 1:", tier1);
        console.log("Tier 2:", tier2);
        console.log("Tier 3:", tier3);
        console.log("Tier 4:", tier4);
        console.log("Tier 5:", tier5);

        vm.startBroadcast(deployer);
        adminProxy.setVaultImpactConfig(projectToken, tier1, tier2, tier3, tier4, tier5);
        vm.stopBroadcast();

        console.log("[SUCCESS] Impact config updated");
    }

    function withdrawFees(address projectToken, uint256 amount) public {
        console.log("\n=== Withdraw Fees ===");
        console.log("Project Token:", projectToken);
        console.log("Amount:", amount);

        vm.startBroadcast(deployer);
        adminProxy.withdrawFees(projectToken, amount);
        vm.stopBroadcast();

        console.log("[SUCCESS] Fees withdrawn");
    }

    // ========================================================================
    // ADMIN CONFIG
    // ========================================================================

    function setPriceFeedManager(address pfm) public {
        console.log("\n=== Set PriceFeedManager ===");
        console.log("New PriceFeedManager:", pfm);

        vm.startBroadcast(deployer);
        adminProxy.setPriceFeedManager(pfm);
        vm.stopBroadcast();

        console.log("[SUCCESS] PriceFeedManager updated");
    }
}
