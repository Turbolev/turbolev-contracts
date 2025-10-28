// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "./DeployHelper.s.sol";

import "../src/SettlementEngine.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeploySettlementEngine
 * @notice Deploy only SettlementEngine contract
 */
contract DeploySettlementEngine is DeployHelper {
    function run() public {
        vm.startBroadcast(deployer);

        console.log("\nDeploying SettlementEngine...");
        console.log("Owner:", owner);

        // Deploy implementation
        address impl = address(new SettlementEngine());
        console.log("Implementation deployed:", impl);

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(SettlementEngine.initialize.selector, owner);

        // Deploy proxy
        address proxy = address(new ERC1967Proxy(impl, initData));

        settlementEngine = proxy;

        // Apply config
        SettlementEngine(settlementEngine).updateConfig(
            HOUSE_EDGE_BPS, WIN_MULTIPLIER_BPS, MIN_BET_AMOUNT, MAX_BET_AMOUNT
        );
        SettlementEngine(settlementEngine).setMaxProfitCapBps(MAX_PROFIT_CAP_BPS);

        _logDeployment("SettlementEngine", settlementEngine);

        vm.stopBroadcast();
    }
}
