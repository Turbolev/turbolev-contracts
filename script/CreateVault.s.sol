// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "./DeployHelper.s.sol";

import "../src/VaultManager.sol";

/**
 * @title CreateVault
 * @notice Create new vault for a project token
 * @dev Set env variables: PROJECT_TOKEN, PROJECT_TOKEN_BASE, PROJECT_TOKEN_QUOTE
 */
contract CreateVault is DeployHelper {
    function run() public {
        vm.startBroadcast(deployer);

        require(vaultManager != address(0), "VaultManager not set in helper");

        address projectToken = vm.envAddress("PROJECT_TOKEN");
        address projectTokenBase = vm.envAddress("PROJECT_TOKEN_BASE");
        address projectTokenQuote = vm.envAddress("PROJECT_TOKEN_QUOTE");

        // Params can be overridden via ENV, otherwise use defaults from helper
        uint16 maxPayoutBps = uint16(vm.envOr("MAX_PAYOUT_BPS", uint256(MAX_PAYOUT_BPS)));
        uint16 perBetUtilBps = uint16(vm.envOr("PER_BET_UTIL_BPS", uint256(PER_BET_UTIL_BPS)));
        uint16 maxUtilBps = uint16(vm.envOr("MAX_UTIL_BPS", uint256(MAX_UTIL_BPS)));
        uint256 minBet = vm.envOr("MIN_BET_AMOUNT", MIN_BET_AMOUNT);
        uint256 maxBet = vm.envOr("MAX_BET_AMOUNT", MAX_BET_AMOUNT);
        uint256 graduationThreshold = vm.envOr("GRADUATION_THRESHOLD", GRADUATION_THRESHOLD);

        console.log("\nCreating vault for token:", projectToken);
        console.log("Project Token Base:", projectTokenBase);
        console.log("Project Token Quote:", projectTokenQuote);
        console.log("Max Payout BPS:", maxPayoutBps);
        console.log("Per Bet Util BPS:", perBetUtilBps);
        console.log("Max Util BPS:", maxUtilBps);
        console.log("Min Bet Amount:", minBet);
        console.log("Max Bet Amount:", maxBet);
        console.log("Graduation Threshold:", graduationThreshold);

        address vaultAddr = VaultManager(vaultManager).createVault(
            projectToken,
            projectTokenBase,
            projectTokenQuote,
            maxPayoutBps,
            perBetUtilBps,
            maxUtilBps,
            minBet,
            maxBet,
            graduationThreshold
        );

        console.log("\n===================================");
        console.log("Vault created successfully!");
        console.log("Vault Address:", vaultAddr);
        console.log("===================================");

        vm.stopBroadcast();
    }
}
