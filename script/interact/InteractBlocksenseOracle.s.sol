// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../DeployHelper.s.sol";
import "../../src/BlocksenseOracle.sol";

/**
 * @title InteractBlocksenseOracle
 * @notice Script to interact with BlocksenseOracle contract
 * @dev Includes view functions and admin functions
 */
contract InteractBlocksenseOracle is DeployHelper {
    BlocksenseOracle public oracle;

    function setUp() public override {
        super.setUp();

        // Load oracle address from env or deployment file
        address oracleAddr = vm.envOr("ORACLE_ADDRESS", blocksenseOracle);
        require(oracleAddr != address(0), "Oracle address not set");
        oracle = BlocksenseOracle(oracleAddr);

        console.log("Oracle Address:", address(oracle));
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    /**
     * @notice Get price for a base/quote pair
     * @dev Usage: forge script script/interact/InteractBlocksenseOracle.s.sol:InteractBlocksenseOracle --sig "getPrice(address,address)" <base> <quote> --rpc-url $RPC
     */
    function getPrice(address base, address quote) public view {
        console.log("\n=== Get Price ===");
        console.log("Base:", base);
        console.log("Quote:", quote);

        try oracle.getPrice(base, quote) returns (int256 price, uint256 updatedAt) {
            console.log("Price:", uint256(price));
            console.log("Updated At:", updatedAt);
            console.log("Age (seconds):", block.timestamp - updatedAt);
        } catch Error(string memory reason) {
            console.log("Error:", reason);
        }
    }

    /**
     * @notice Get price unsafe (no staleness check)
     */
    function getPriceUnsafe(address base, address quote) public view {
        console.log("\n=== Get Price Unsafe ===");
        console.log("Base:", base);
        console.log("Quote:", quote);

        try oracle.getPriceUnsafe(base, quote) returns (int256 price, uint256 updatedAt) {
            console.log("Price:", uint256(price));
            console.log("Updated At:", updatedAt);
        } catch Error(string memory reason) {
            console.log("Error:", reason);
        }
    }

    /**
     * @notice Get price with custom max age
     */
    function getPriceNoOlderThan(address base, address quote, uint256 maxAge) public {
        console.log("\n=== Get Price No Older Than ===");
        console.log("Base:", base);
        console.log("Quote:", quote);
        console.log("Max Age:", maxAge);

        vm.startBroadcast(deployer);
        try oracle.getPriceNoOlderThan(base, quote, maxAge) returns (
            int256 price, uint256 updatedAt
        ) {
            console.log("Price:", uint256(price));
            console.log("Updated At:", updatedAt);
        } catch Error(string memory reason) {
            console.log("Error:", reason);
        }
        vm.stopBroadcast();
    }

    /**
     * @notice View oracle configuration
     */
    function viewConfig() public view {
        console.log("\n=== Oracle Configuration ===");
        console.log("Registry:");
        console.logAddress(address(oracle.registry()));
        console.log("Max Price Age:", oracle.maxPriceAge());
        console.log("Max Price Change BPS:", oracle.maxPriceChangeBps());
        console.log("Min Price Update Interval:", oracle.minPriceUpdateInterval());
        console.log("Owner:");
        console.logAddress(oracle.owner());
        console.log("Paused:", oracle.paused());
        console.log("Version:", oracle.version());
    }

    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================

    /**
     * @notice Set registry contract address
     */
    function setRegistryContract(address newRegistry) public {
        console.log("\n=== Set Registry Contract ===");
        console.log("New Registry:", newRegistry);

        vm.startBroadcast(deployer);
        oracle.setRegistryContract(newRegistry);
        console.log("Registry updated successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Set max price age
     */
    function setMaxPriceAge(uint256 newMaxAge) public {
        console.log("\n=== Set Max Price Age ===");
        console.log("New Max Age:", newMaxAge);

        vm.startBroadcast(deployer);
        oracle.setMaxPriceAge(newMaxAge);
        console.log("Max price age updated successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Set price validation config
     */
    function setPriceValidationConfig(
        uint256 newMaxPriceChangeBps,
        uint256 newMinPriceUpdateInterval
    ) public {
        console.log("\n=== Set Price Validation Config ===");
        console.log("Max Price Change BPS:", newMaxPriceChangeBps);
        console.log("Min Price Update Interval:", newMinPriceUpdateInterval);

        vm.startBroadcast(deployer);
        oracle.setPriceValidationConfig(newMaxPriceChangeBps, newMinPriceUpdateInterval);
        console.log("Price validation config updated successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Pause oracle
     */
    function pauseOracle() public {
        console.log("\n=== Pause Oracle ===");

        vm.startBroadcast(deployer);
        oracle.pause();
        console.log("Oracle paused successfully");
        vm.stopBroadcast();
    }

    /**
     * @notice Unpause oracle
     */
    function unpauseOracle() public {
        console.log("\n=== Unpause Oracle ===");

        vm.startBroadcast(deployer);
        oracle.unpause();
        console.log("Oracle unpaused successfully");
        vm.stopBroadcast();
    }
}
