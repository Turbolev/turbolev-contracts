// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../../src/interfaces/IVaultRouter.sol";
import "../../src/vault-modular/libraries/VaultStorageLib.sol";
import "../../src/libraries/FundingRateLib.sol";

/**
 * @title DebugFundingConfig
 * @notice Debug script to verify funding config storage
 */
contract DebugFundingConfig is Script {
    function run() external view {
        // Replace with actual vault address
        address vaultAddress = vm.envAddress("VAULT_ADDRESS");

        console.log("=== DEBUG FUNDING CONFIG ===");
        console.log("Vault Address:", vaultAddress);

        // Hypothesis A: Check via staticcall (current implementation)
        console.log("\n--- Hypothesis A: getFundingConfig via staticcall ---");
        try IVaultRouter(vaultAddress).getFundingConfig() returns (
            uint16 t1, uint16 t2, uint16 t3, uint16 t4, uint16 t5
        ) {
            console.log("tier1RateBps:", t1);
            console.log("tier2RateBps:", t2);
            console.log("tier3RateBps:", t3);
            console.log("tier4RateBps:", t4);
            console.log("tier5RateBps:", t5);

            if (t1 == 0 && t2 == 0 && t3 == 0 && t4 == 0 && t5 == 0) {
                console.log("CONFIRMED: All values are 0 - staticcall reads from wrong storage!");
            }
        } catch {
            console.log("ERROR: getFundingConfig() reverted");
        }

        // Hypothesis A2: Check funding enabled
        console.log("\n--- Check isFundingEnabled ---");
        try IVaultRouter(vaultAddress).fundingEnabled() returns (bool enabled) {
            console.log("fundingEnabled:", enabled);
            if (!enabled) {
                console.log("WARNING: Funding is disabled!");
            }
        } catch {
            console.log("ERROR: isFundingEnabled() reverted");
        }

        // Hypothesis B: Check if vault was initialized properly
        console.log("\n--- Check Vault Initialization ---");
        try IVaultRouter(vaultAddress).projectToken() returns (address projectToken) {
            console.log("projectToken:", projectToken);
            if (projectToken != address(0)) {
                console.log("CONFIRMED: Vault was initialized (projectToken is set)");
            } else {
                console.log("ERROR: Vault may not be initialized!");
            }
        } catch {
            console.log("ERROR: projectToken() reverted");
        }

        // Additional check: getFundingStats
        console.log("\n--- Check getFundingStats ---");
        try IVaultRouter(vaultAddress).getCumulativeFundingRates() returns (
            int256 cumulativeLongRate, int256 cumulativeShortRate
        ) {
            console.log("cumulativeLong:", cumulativeLongRate);
            console.log("cumulativeShort:", cumulativeShortRate);
        } catch {
            console.log("ERROR: getCumulativeFundingRates() reverted");
        }

        try IVaultRouter(vaultAddress).getCurrentHourlyFundingRate() returns (
            uint256 rateBps, bool longsPayShorts, uint256 imbalanceBps, bool hasCounterparty
        ) {
            console.log("rateBps:", rateBps);
            console.log("longsPayShorts:", longsPayShorts);
            console.log("imbalanceBps:", imbalanceBps);
            console.log("hasCounterparty:", hasCounterparty);
        } catch {
            console.log("ERROR: getCurrentHourlyFundingRate() reverted");
        }

        try IVaultRouter(vaultAddress).getFundingConfig() returns (
            uint16 t1, uint16 t2, uint16 t3, uint16 t4, uint16 t5
        ) {
            console.log("t1:", t1);
            console.log("t2:", t2);
            console.log("t3:", t3);
            console.log("t4:", t4);
            console.log("t5:", t5);
        } catch {
            console.log("ERROR: getFundingConfig() reverted");
        }
        // Check raw storage slot for funding config
        console.log("\n--- Raw Storage Check ---");
        bytes32 fundingSlot = VaultStorageLib.calculateEIP7201Slot("boolean.vault.funding");
        console.log("FundingStorage slot:");
        console.logBytes32(fundingSlot);

        // Expected default values
        console.log("\n--- Expected Default Values ---");
        console.log("DEFAULT_TIER1_RATE_BPS:", FundingRateLib.DEFAULT_TIER1_RATE_BPS);
        console.log("DEFAULT_TIER2_RATE_BPS:", FundingRateLib.DEFAULT_TIER2_RATE_BPS);
        console.log("DEFAULT_TIER3_RATE_BPS:", FundingRateLib.DEFAULT_TIER3_RATE_BPS);
        console.log("DEFAULT_TIER4_RATE_BPS:", FundingRateLib.DEFAULT_TIER4_RATE_BPS);
        console.log("DEFAULT_TIER5_RATE_BPS:", FundingRateLib.DEFAULT_TIER5_RATE_BPS);

        console.log("\n=== END DEBUG ===");
    }
}

