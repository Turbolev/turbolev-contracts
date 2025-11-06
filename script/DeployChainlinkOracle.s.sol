// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./DeployHelper.s.sol";
import "../src/ChainlinkOracle.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployChainlinkOracle
 * @notice Deployment script for ChainlinkOracle (Upgradeable UUPS)
 *
 * Usage:
 * forge script script/DeployChainlinkOracle.s.sol:DeployChainlinkOracle \
 *   --rpc-url $RPC_URL \
 *   --private-key $PRIVATE_KEY \
 *   --broadcast \
 *   --verify \
 *   --etherscan-api-key $ETHERSCAN_API_KEY \
 *   -vvvv
 */
contract DeployChainlinkOracle is DeployHelper {
    function run() external {
        // Load environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 maxPriceAge = vm.envOr("MAX_PRICE_AGE", uint256(300)); // Default: 5 minutes

        // Use blocksenseOracle from DeployHelper if available
        if (blocksenseOracle == address(0)) {
            blocksenseOracle = payable(vm.envAddress("BLOCKSENSE_ORACLE_ADDRESS"));
        }

        console.log("\n=== Deploying ChainlinkOracle (UUPS Upgradeable) ===");
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("BlocksenseOracle:", blocksenseOracle);
        console.log("Max Price Age:", maxPriceAge);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy implementation
        console.log("\n1. Deploying implementation...");
        ChainlinkOracle implementation = new ChainlinkOracle();
        console.log("Implementation deployed at:", address(implementation));

        // 2. Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            ChainlinkOracle.initialize.selector, blocksenseOracle, maxPriceAge
        );

        // 3. Deploy proxy
        console.log("\n2. Deploying proxy...");
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        console.log("Proxy deployed at:", address(proxy));

        ChainlinkOracle chainlinkOracleContract = ChainlinkOracle(address(proxy));

        // Update chainlinkOracle address in DeployHelper
        chainlinkOracle = payable(address(proxy));

        // 4. Verify deployment
        console.log("\n3. Verifying deployment...");
        console.log("BlocksenseOracle:", chainlinkOracleContract.blocksenseOracle());
        console.log("Max Price Age:", chainlinkOracleContract.maxPriceAge());
        console.log("Owner:", chainlinkOracleContract.owner());

        vm.stopBroadcast();

        // Log deployment
        _logDeployment("ChainlinkOracle", address(proxy));

        console.log("\n=== Deployment Complete ===");
        console.log("\nIMPORTANT: Save these addresses!");
        console.log("Implementation:", address(implementation));
        console.log("Proxy (ChainlinkOracle):", address(proxy));
        console.log("\nTo interact with the contract, use the PROXY address:");
        console.log(address(proxy));
    }
}
