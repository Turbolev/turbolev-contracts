// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../DeployHelper.s.sol";
import "../../src/SettlementEngine.sol";

contract InteractSettlementEngine is DeployHelper {
    SettlementEngine public se;

    function setUp() public override {
        super.setUp();
        se = SettlementEngine(payable(settlementEngine));
        console.log("SettlementEngine Address:", address(se));
    }

    function viewConfig() public view {
        console.log("\n=== Settlement Engine Config ===");
        console.log("Win Multiplier BPS:", se.winMultiplierBps());
        console.log("Min Bet Amount:", se.minBetAmount());
        console.log("Max Bet Amount:", se.maxBetAmount());
        console.log("Max Profit Cap BPS:", se.maxProfitCapBps());
    }

    function viewConnectedContracts() public view {
        console.log("\n=== Connected Contracts ===");
        console.log("Position Manager:", se.positionManager());
        console.log("Vault Manager:", se.vaultManager());
        console.log("Price Feed Manager:", se.priceFeedManager());
    }

    function isValidBetAmount(uint256 amount) public view {
        console.log("\n=== Bet Amount Validation ===");
        console.log("Amount:", amount);
        console.log("Is Valid:", se.isValidBetAmount(amount));
    }

    function setPositionManager(address _positionManager) public {
        vm.startBroadcast(deployer);
        se.setPositionManager(_positionManager);
        console.log("Position Manager set:", _positionManager);
        vm.stopBroadcast();
    }

    function setVaultManager(address _vaultManager) public {
        vm.startBroadcast(deployer);
        se.setVaultManager(_vaultManager);
        console.log("Vault Manager set:", _vaultManager);
        vm.stopBroadcast();
    }

    function setPriceFeedManager(address _priceFeedManager) public {
        vm.startBroadcast(deployer);
        se.setPriceFeedManager(_priceFeedManager);
        console.log("Price Feed Manager set:", _priceFeedManager);
        vm.stopBroadcast();
    }

    function setMaxProfitCapBps(uint16 _maxProfitCapBps) public {
        vm.startBroadcast(deployer);
        se.setMaxProfitCapBps(_maxProfitCapBps);
        console.log("Max Profit Cap BPS set:", _maxProfitCapBps);
        vm.stopBroadcast();
    }

    function pauseEngine() public {
        vm.startBroadcast(deployer);
        se.pause();
        console.log("SettlementEngine paused");
        vm.stopBroadcast();
    }

    function unpauseEngine() public {
        vm.startBroadcast(deployer);
        se.unpause();
        console.log("SettlementEngine unpaused");
        vm.stopBroadcast();
    }
}
