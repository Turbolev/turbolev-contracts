// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../DeployHelper.s.sol";
import "../../src/SettlementEngine.sol";

/**
 * @title InteractSettlementEngine
 * @notice Script to interact with SettlementEngine contract
 * @dev Includes view functions and admin functions
 */
contract InteractSettlementEngine is DeployHelper {
    SettlementEngine public settlement;

    function setUp() public override {
        super.setUp();

        // Load settlement engine address from env or deployment file
        address settlementAddr = vm.envOr("SETTLEMENT_ENGINE_ADDRESS", settlementEngine);
        require(settlementAddr != address(0), "Settlement Engine address not set");
        settlement = SettlementEngine(settlementAddr);

        console.log("Settlement Engine Address:", address(settlement));
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /**
     * @notice View settlement configuration
     */
    function viewConfig() public view {
        console.log("\n=== Settlement Engine Configuration ===");

        (
            uint16 houseEdgeBps,
            uint16 winMultiplierBps,
            uint256 minBetAmount,
            uint256 maxBetAmount,
            bool isPaused
        ) = settlement.getSettlementConfig();

        console.log("House Edge BPS:", houseEdgeBps);
        console.log("Win Multiplier BPS:", winMultiplierBps);
        console.log("Min Bet Amount:", minBetAmount);
        console.log("Max Bet Amount:", maxBetAmount);
        console.log("Max Profit Cap BPS:", settlement.maxProfitCapBps());
        console.log("Paused:", isPaused);
        console.log("Owner:", settlement.owner());
        console.log("Position Manager:", settlement.positionManager());
        console.log("Vault Manager:", settlement.vaultManager());
        console.log("Blocksense Oracle:", settlement.blocksenseOracle());
        console.log("Version:", settlement.version());
    }

    /**
     * @notice Calculate potential payout for an amount
     */
    function calculatePotentialPayout(uint256 amount) public view {
        console.log("\n=== Calculate Potential Payout ===");
        console.log("Amount:", amount);

        uint256 payout = settlement.calculatePotentialPayout(amount);
        console.log("Potential Payout:", payout);
        console.log("Profit:", payout > amount ? payout - amount : 0);
    }

    /**
     * @notice Check if bet amount is valid
     */
    function isValidBetAmount(uint256 amount) public view {
        console.log("\n=== Check Bet Amount Validity ===");
        console.log("Amount:", amount);

        bool valid = settlement.isValidBetAmount(amount);
        console.log("Is Valid:", valid);
    }

    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================

    /**
     * @notice Update settlement config
     */
    function updateConfig(
        uint16 houseEdgeBps,
        uint16 winMultiplierBps,
        uint256 minBetAmount,
        uint256 maxBetAmount
    ) public {
        console.log("\n=== Update Settlement Config ===");
        console.log("House Edge BPS:", houseEdgeBps);
        console.log("Win Multiplier BPS:", winMultiplierBps);
        console.log("Min Bet Amount:", minBetAmount);
        console.log("Max Bet Amount:", maxBetAmount);

        vm.startBroadcast(deployer);
        settlement.updateConfig(houseEdgeBps, winMultiplierBps, minBetAmount, maxBetAmount);
        console.log("Config updated successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Set max profit cap in basis points
     */
    function setMaxProfitCapBps(uint16 newMaxProfitCapBps) public {
        console.log("\n=== Set Max Profit Cap BPS ===");
        console.log("New Max Profit Cap BPS:", newMaxProfitCapBps);

        vm.startBroadcast(deployer);
        settlement.setMaxProfitCapBps(newMaxProfitCapBps);
        console.log("Max profit cap BPS updated successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Set Position Manager address
     */
    function setPositionManager(address newPositionManager) public {
        console.log("\n=== Set Position Manager ===");
        console.log("New Position Manager:", newPositionManager);

        vm.startBroadcast(deployer);
        settlement.setPositionManager(newPositionManager);
        console.log("Position Manager updated successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Set Vault Manager address
     */
    function setVaultManager(address newVaultManager) public {
        console.log("\n=== Set Vault Manager ===");
        console.log("New Vault Manager:", newVaultManager);

        vm.startBroadcast(deployer);
        settlement.setVaultManager(newVaultManager);
        console.log("Vault Manager updated successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Set Blocksense Oracle address
     */
    function setBlocksenseOracle(address newOracle) public {
        console.log("\n=== Set Blocksense Oracle ===");
        console.log("New Oracle:", newOracle);

        vm.startBroadcast(deployer);
        settlement.setBlocksenseOracle(newOracle);
        console.log("Blocksense Oracle updated successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Pause settlement engine
     */
    function pauseSettlement() public {
        console.log("\n=== Pause Settlement Engine ===");

        vm.startBroadcast(deployer);
        settlement.pause();
        console.log("Settlement Engine paused successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Unpause settlement engine
     */
    function unpauseSettlement() public {
        console.log("\n=== Unpause Settlement Engine ===");

        vm.startBroadcast(deployer);
        settlement.unpause();
        console.log("Settlement Engine unpaused successfully");
        vm.stopBroadcast();
    }
}
