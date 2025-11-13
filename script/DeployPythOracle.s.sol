// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "../src/oracles/PythOracle.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployPythOracle
 * @notice Script to deploy PythOracle with UUPS proxy
 *
 * Usage:
 * forge script script/DeployPythOracle.s.sol:DeployPythOracle \
 *   --rpc-url <RPC_URL> \
 *   --broadcast \
 *   --verify
 *
 * Required Environment Variables:
 * - DEPLOYER_PRIVATE_KEY: Deployer's private key
 * - PYTH_CONTRACT: Pyth contract address on the target chain
 * - MAX_PRICE_AGE: Maximum acceptable price age in seconds (e.g., 60)
 */
contract DeployPythOracle is Script {
    function run() external {
        // Get environment variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address pythContract = vm.envAddress("PYTH_CONTRACT");
        uint256 maxPriceAge = vm.envOr("MAX_PRICE_AGE", uint256(60)); // Default: 60 seconds

        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== Deploying PythOracle ===");
        console.log("Deployer:", deployer);
        console.log("Pyth Contract:", pythContract);
        console.log("Max Price Age:", maxPriceAge, "seconds");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy implementation
        PythOracle implementation = new PythOracle();
        console.log("PythOracle Implementation deployed at:", address(implementation));

        // 2. Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            PythOracle.initialize.selector, deployer, pythContract, maxPriceAge
        );

        // 3. Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        console.log("PythOracle Proxy deployed at:", address(proxy));

        // 4. Verify initialization
        PythOracle pythOracle = PythOracle(payable(address(proxy)));
        console.log("Owner:", pythOracle.owner());
        console.log("Pyth Contract:", pythOracle.pythContract());
        console.log("Max Price Age:", pythOracle.maxPriceAge());
        console.log("Oracle Type:", uint8(pythOracle.getOracleType()));
        console.log("Supports Hybrid:", pythOracle.supportsHybridMode());

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("PythOracle Implementation:", address(implementation));
        console.log("PythOracle Proxy:", address(proxy));
        console.log("\nSave this proxy address to use in PriceFeedManager configuration!");
    }
}
