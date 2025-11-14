// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "../../src/oracles/PythOracle.sol";

/**
 * @title InteractPythOracle
 * @notice Script to interact with PythOracle contract
 *
 * Functions:
 * 1. setPriceFeedId - Set price feed ID for a token
 * 2. setPriceFeedIds - Set multiple price feed IDs
 * 3. getPrice - Get current price for a token
 * 4. updatePrice - Update price for a token (pull mode)
 * 5. getPriceWithUpdate - Get price and update if stale
 *
 * Usage:
 * forge script script/interact/InteractPythOracle.s.sol:InteractPythOracle \
 *   --sig "setPriceFeedId()" \
 *   --rpc-url <RPC_URL> \
 *   --broadcast
 *
 * Required Environment Variables:
 * - DEPLOYER_PRIVATE_KEY: Deployer's private key
 * - PYTH_ORACLE: PythOracle proxy address
 * - TOKEN_ADDRESS: Token address to configure
 * - PRICE_FEED_ID: Pyth price feed ID (bytes32, with 0x prefix)
 */
contract InteractPythOracle is Script {
    function setPriceFeedId() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address pythOracleAddr = vm.envAddress("PYTH_ORACLE");
        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        bytes32 priceId = vm.envBytes32("PRICE_FEED_ID");

        console.log("=== Set Price Feed ID ===");
        console.log("PythOracle:", pythOracleAddr);
        console.log("Token:", tokenAddress);
        console.log("Price Feed ID:", vm.toString(priceId));

        vm.startBroadcast(deployerPrivateKey);

        PythOracle pythOracle = PythOracle(payable(pythOracleAddr));
        pythOracle.setPriceFeedId(tokenAddress, priceId);

        console.log("Price feed ID set successfully!");

        vm.stopBroadcast();
    }

    function setPriceFeedIds() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address pythOracleAddr = vm.envAddress("PYTH_ORACLE");

        // Example: Set multiple feed IDs
        // Modify these arrays according to your needs
        address[] memory tokens = new address[](2);
        bytes32[] memory priceIds = new bytes32[](2);

        // Example for BTC/USD and ETH/USD on Pyth
        tokens[0] = vm.envAddress("TOKEN_1");
        tokens[1] = vm.envAddress("TOKEN_2");
        priceIds[0] = vm.envBytes32("PRICE_ID_1");
        priceIds[1] = vm.envBytes32("PRICE_ID_2");

        console.log("=== Set Multiple Price Feed IDs ===");
        console.log("PythOracle:", pythOracleAddr);
        console.log("Number of tokens:", tokens.length);

        vm.startBroadcast(deployerPrivateKey);

        PythOracle pythOracle = PythOracle(payable(pythOracleAddr));
        pythOracle.setPriceFeedIds(tokens, priceIds);

        console.log("Price feed IDs set successfully!");

        vm.stopBroadcast();
    }

    function getPrice() external view {
        address pythOracleAddr = vm.envAddress("PYTH_ORACLE");
        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");

        console.log("=== Get Price ===");
        console.log("PythOracle:", pythOracleAddr);
        console.log("Token:", tokenAddress);

        PythOracle pythOracle = PythOracle(payable(pythOracleAddr));

        try pythOracle.getPrice(tokenAddress) returns (int256 price, uint256 updatedAt) {
            console.log("Price:", uint256(price));
            console.log("Updated At:", updatedAt);
            console.log("Age (seconds):", block.timestamp - updatedAt);
        } catch Error(string memory reason) {
            console.log("Failed to get price:", reason);
        } catch {
            console.log("Failed to get price: Unknown error");
        }
    }

    function checkStale() external view {
        address pythOracleAddr = vm.envAddress("PYTH_ORACLE");
        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        uint256 maxAge = vm.envOr("MAX_AGE", uint256(60));

        console.log("=== Check If Price Is Stale ===");
        console.log("PythOracle:", pythOracleAddr);
        console.log("Token:", tokenAddress);
        console.log("Max Age:", maxAge);

        PythOracle pythOracle = PythOracle(payable(pythOracleAddr));

        bool isStale = pythOracle.isPriceStale(tokenAddress, maxAge);
        console.log("Is Stale:", isStale);
    }

    function updatePrice() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address pythOracleAddr = vm.envAddress("PYTH_ORACLE");
        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");

        // UPDATE_DATA should be obtained from Pyth API
        // Example: https://hermes.pyth.network/api/latest_vaas?ids[]=<price_id>
        bytes memory updateData = vm.envBytes("UPDATE_DATA");

        console.log("=== Update Price ===");
        console.log("PythOracle:", pythOracleAddr);
        console.log("Token:", tokenAddress);

        PythOracle pythOracle = PythOracle(payable(pythOracleAddr));

        // Get update fee
        uint256 fee = pythOracle.getUpdateFee(tokenAddress, updateData);
        console.log("Update Fee:", fee);

        vm.startBroadcast(deployerPrivateKey);

        pythOracle.updatePrice{ value: fee }(tokenAddress, updateData);

        console.log("Price updated successfully!");

        vm.stopBroadcast();
    }

    function getPythContractInfo() external view {
        address pythOracleAddr = vm.envAddress("PYTH_ORACLE");

        console.log("=== Pyth Oracle Info ===");
        console.log("PythOracle:", pythOracleAddr);

        PythOracle pythOracle = PythOracle(payable(pythOracleAddr));

        console.log("Pyth Contract:", pythOracle.pythContract());
        console.log("Max Price Age:", pythOracle.maxPriceAge());
        console.log("Default Mode:", uint8(pythOracle.getCurrentMode()));
        console.log("Oracle Type:", uint8(pythOracle.getOracleType()));
        console.log("Supports Hybrid:", pythOracle.supportsHybridMode());
        console.log("Owner:", pythOracle.owner());
        console.log("Version:", pythOracle.version());
    }
}
