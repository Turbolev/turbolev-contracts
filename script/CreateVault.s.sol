// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "./DeployHelper.s.sol";

import "../src/VaultManager.sol";

/**
 * @title CreateVault
 * @notice Create new vault for a project token
 * @dev Required env variables: PROJECT_TOKEN
 * @dev Optional env variables: MIN_BET_AMOUNT, MAX_BET_AMOUNT, GRADUATION_THRESHOLD
 */
contract CreateVault is DeployHelper {
    function run() public {
        vm.startBroadcast(deployer);

        require(vaultManager != address(0), "VaultManager not set in helper");

        address projectToken = vm.envAddress("PROJECT_TOKEN");

        // Params can be overridden via ENV, otherwise use defaults from helper
        uint256 minBet = vm.envOr("MIN_BET_AMOUNT", MIN_BET_AMOUNT);
        uint256 maxBet = vm.envOr("MAX_BET_AMOUNT", MAX_BET_AMOUNT);
        uint256 graduationThreshold = vm.envOr("GRADUATION_THRESHOLD", GRADUATION_THRESHOLD);

        console.log("\nCreating vault for token:", projectToken);
        console.log("Min Bet Amount:", minBet);
        console.log("Max Bet Amount:", maxBet);
        console.log("Graduation Threshold:", graduationThreshold);

        address vaultAddr = VaultManager(vaultManager).createVaultWithBeacon(
            projectToken, minBet, maxBet, graduationThreshold
        );

        console.log("\n===================================");
        console.log("Vault created successfully!");
        console.log("Vault Address:", vaultAddr);
        console.log("===================================");

        vm.stopBroadcast();
    }
}
