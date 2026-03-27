// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../../src/interfaces/IVaultRouter.sol";
import "../../src/libraries/vault/VaultStorageLib.sol";
import "../../src/libraries/math/PriceImpactLib.sol";

/**
 * @title DebugImpactConfig
 * @notice Debug script to verify price impact config storage
 */
contract DebugFundingConfig is Script {
    function run() external view {
        address vaultAddress = vm.envAddress("VAULT_ADDRESS");

        console.log("=== DEBUG PRICE IMPACT CONFIG ===");
        console.log("Vault Address:", vaultAddress);

        console.log("\n--- Check getImpactConfig ---");
        try IVaultRouter(vaultAddress).getImpactConfig() returns (
            uint16 t1, uint16 t2, uint16 t3, uint16 t4, uint16 t5
        ) {
            console.log("tier1ImpactBps:", t1);
            console.log("tier2ImpactBps:", t2);
            console.log("tier3ImpactBps:", t3);
            console.log("tier4ImpactBps:", t4);
            console.log("tier5ImpactBps:", t5);
        } catch {
            console.log("ERROR: getImpactConfig() reverted");
        }

        console.log("\n--- Check isImpactEnabled ---");
        try IVaultRouter(vaultAddress).isImpactEnabled() returns (bool enabled) {
            console.log("impactEnabled:", enabled);
        } catch {
            console.log("ERROR: isImpactEnabled() reverted");
        }

        console.log("\n--- Check getImpactStats ---");
        try IVaultRouter(vaultAddress).getImpactStats() returns (
            uint256 longExp,
            uint256 shortExp,
            uint256 currentImpactBps,
            bool isLongDominant,
            uint256 imbalanceBps,
            uint256 totalFees
        ) {
            console.log("longExposure:", longExp);
            console.log("shortExposure:", shortExp);
            console.log("currentImpactBps:", currentImpactBps);
            console.log("isLongDominant:", isLongDominant);
            console.log("imbalanceBps:", imbalanceBps);
            console.log("totalFeesCollected:", totalFees);
        } catch {
            console.log("ERROR: getImpactStats() reverted");
        }

        console.log("\n--- Raw Storage Check ---");
        bytes32 fundingSlot = VaultStorageLib.calculateEIP7201Slot("boolean.vault.funding");
        console.log("FundingStorage slot:");
        console.logBytes32(fundingSlot);

        console.log("\n--- Expected Default Impact Values ---");
        console.log("DEFAULT_TIER1_IMPACT_BPS:", PriceImpactLib.DEFAULT_TIER1_IMPACT_BPS);
        console.log("DEFAULT_TIER2_IMPACT_BPS:", PriceImpactLib.DEFAULT_TIER2_IMPACT_BPS);
        console.log("DEFAULT_TIER3_IMPACT_BPS:", PriceImpactLib.DEFAULT_TIER3_IMPACT_BPS);
        console.log("DEFAULT_TIER4_IMPACT_BPS:", PriceImpactLib.DEFAULT_TIER4_IMPACT_BPS);
        console.log("DEFAULT_TIER5_IMPACT_BPS:", PriceImpactLib.DEFAULT_TIER5_IMPACT_BPS);

        console.log("\n=== END DEBUG ===");
    }
}
