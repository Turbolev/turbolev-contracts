// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../DeployHelper.s.sol";
import "../../src/PriceFeedManager.sol";
import "../../src/interfaces/IPriceFeedManager.sol";

contract InteractPriceFeedManager is DeployHelper {
    PriceFeedManager public pfm;

    function setUp() public override {
        super.setUp();
        pfm = PriceFeedManager(payable(priceFeedManager));
        console.log("PriceFeedManager Address:", address(pfm));
    }

    function viewPriceFeedConfig(address token) public view {
        console.log("\n=== Price Feed Config for Token ===");
        console.log("Token:", token);
        IPriceFeedManager.PriceFeedConfig memory config = pfm.getPriceFeedConfig(token);
        console.log("Primary Provider ID:", uint256(config.primaryProviderId));
        console.log("Secondary Provider ID:", uint256(config.secondaryProviderId));
        console.log("Primary Feed:", config.primaryFeed);
        console.log("Secondary Feed:", config.secondaryFeed);
        console.log("Use Pull Mode:", config.usePullMode);
    }

    function viewOracleProvider(bytes32 providerId) public view {
        console.log("\n=== Oracle Provider ===");
        console.log("Provider ID:", uint256(providerId));
        IPriceFeedManager.OracleProvider memory provider = pfm.getOracleProvider(providerId);
        console.log("Oracle Contract:", provider.oracleContract);
        console.log("Oracle Type:", uint256(provider.oracleType));
        console.log("Enabled:", provider.enabled);
    }

    function viewResolvedConfig(address token) public view {
        console.log("\n=== Resolved Config for Token ===");
        (
            IPriceFeedManager.OracleProvider memory primary,
            IPriceFeedManager.OracleProvider memory secondary,
            bool usePullMode
        ) = pfm.getResolvedConfig(token);
        console.log("Token:", token);
        console.log("Primary Oracle Contract:", primary.oracleContract);
        console.log("Primary Oracle Type:", uint256(primary.oracleType));
        console.log("Primary Enabled:", primary.enabled);
        console.log("Secondary Oracle Contract:", secondary.oracleContract);
        console.log("Secondary Oracle Type:", uint256(secondary.oracleType));
        console.log("Secondary Enabled:", secondary.enabled);
        console.log("Use Pull Mode:", usePullMode);
    }

    function viewPrice(address token, uint256 maxAge) public view {
        console.log("\n=== Price for Token ===");
        (uint256 price, uint256 publishTime) = pfm.getPrice(token, maxAge);
        console.log("Token:", token);
        console.log("Price:", price);
        console.log("Publish Time:", publishTime);
    }

    function viewAllProviderIds() public view {
        console.log("\n=== All Provider IDs ===");
        bytes32[] memory providerIds = pfm.getAllProviderIds();
        console.log("Total providers:", providerIds.length);
        for (uint256 i = 0; i < providerIds.length; i++) {
            console.log("Provider", i, ":", uint256(providerIds[i]));
        }
    }

    function isPriceStale(address token, uint256 maxAge) public view {
        console.log("\n=== Price Staleness Check ===");
        bool isStale = pfm.isPriceStale(token, maxAge);
        console.log("Token:", token);
        console.log("Max Age:", maxAge);
        console.log("Is Stale:", isStale);
    }

    function registerOracleProvider(
        bytes32 providerId,
        address oracleContract,
        uint8 oracleType,
        bool enabled
    ) public {
        vm.startBroadcast(deployer);
        IPriceFeedManager.OracleProvider memory provider = IPriceFeedManager.OracleProvider({
            oracleContract: oracleContract,
            oracleType: IBaseOracle.OracleType(oracleType),
            enabled: enabled
        });
        pfm.registerOracleProvider(providerId, provider);
        console.log("Oracle provider registered");
        vm.stopBroadcast();
    }

    function setPriceFeedConfig(
        address token,
        bytes32 primaryProviderId,
        bytes32 secondaryProviderId,
        address primaryFeed,
        address secondaryFeed,
        bool usePullMode
    ) public {
        vm.startBroadcast(deployer);
        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: primaryProviderId,
            secondaryProviderId: secondaryProviderId,
            primaryFeed: primaryFeed,
            secondaryFeed: secondaryFeed,
            usePullMode: usePullMode
        });
        pfm.setPriceFeedConfig(token, config);
        console.log("Price feed config set for token:", token);
        vm.stopBroadcast();
    }

    function setPrimaryProvider(address token, bytes32 providerId) public {
        vm.startBroadcast(deployer);
        pfm.setPrimaryProvider(token, providerId);
        console.log("Primary provider set for token:", token);
        vm.stopBroadcast();
    }

    function setSecondaryProvider(address token, bytes32 providerId) public {
        vm.startBroadcast(deployer);
        pfm.setSecondaryProvider(token, providerId);
        console.log("Secondary provider set for token:", token);
        vm.stopBroadcast();
    }

    function setUsePullMode(address token, bool usePullMode) public {
        vm.startBroadcast(deployer);
        pfm.setUsePullMode(token, usePullMode);
        console.log("Use pull mode set for token:", token);
        vm.stopBroadcast();
    }

    function pauseManager() public {
        vm.startBroadcast(deployer);
        pfm.pause();
        console.log("PriceFeedManager paused");
        vm.stopBroadcast();
    }

    function unpauseManager() public {
        vm.startBroadcast(deployer);
        pfm.unpause();
        console.log("PriceFeedManager unpaused");
        vm.stopBroadcast();
    }
}
