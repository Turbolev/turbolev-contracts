// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./BaseTest.sol";

/**
 * @title SettlementEngineTest
 * @notice Comprehensive tests for SettlementEngine
 * @dev Tests settlement logic, profit capping, fees, and admin functions
 */
contract SettlementEngineTest is BaseTest {
    // Test constants
    uint256 constant COLLATERAL = 1 ether;
    uint8 constant LEVERAGE_10X = 10;

    function test_Initialize_Success() public {
        assertEq(settlementEngine.houseEdgeBps(), 200, "House edge should be 200");
        assertEq(settlementEngine.winMultiplierBps(), 30_000, "Win multiplier should be 30000");
        assertEq(settlementEngine.minBetAmount(), 0.001 ether, "Min bet should be 0.001");
        assertEq(settlementEngine.maxBetAmount(), 1000 ether, "Max bet should be 1000");
        assertEq(settlementEngine.maxProfitCapBps(), 200, "Max profit cap should be 200");
    }

    function test_CalculatePotentialPayout_Success() public {
        uint256 amount = 1 ether;
        uint256 payout = settlementEngine.calculatePotentialPayout(amount);

        // Expected: 1 * 3 = 3 ether (gross)
        // House edge: 3 * 0.02 = 0.06 ether
        // Net: 3 - 0.06 = 2.94 ether
        assertEq(payout, 2.94 ether, "Potential payout should be 2.94");
    }

    function test_IsValidBetAmount_Success() public {
        assertTrue(settlementEngine.isValidBetAmount(0.001 ether), "0.001 should be valid");
        assertTrue(settlementEngine.isValidBetAmount(1 ether), "1 should be valid");
        assertTrue(settlementEngine.isValidBetAmount(1000 ether), "1000 should be valid");
    }

    function test_IsValidBetAmount_Invalid() public {
        assertFalse(settlementEngine.isValidBetAmount(0.0001 ether), "Below min should be invalid");
        assertFalse(settlementEngine.isValidBetAmount(1001 ether), "Above max should be invalid");
    }

    function test_GetSettlementConfig_Success() public {
        (uint16 houseEdge, uint16 winMultiplier, uint256 minBet, uint256 maxBet, bool isPaused) =
            settlementEngine.getSettlementConfig();

        assertEq(houseEdge, 200, "House edge should match");
        assertEq(winMultiplier, 30_000, "Win multiplier should match");
        assertEq(minBet, 0.001 ether, "Min bet should match");
        assertEq(maxBet, 1000 ether, "Max bet should match");
        assertFalse(isPaused, "Should not be paused");
    }

    function test_UpdateConfig_Success() public {
        settlementEngine.updateConfig(
            300, // 3% house edge
            20_000, // 2x multiplier
            0.01 ether, // New min
            500 ether // New max
        );

        assertEq(settlementEngine.houseEdgeBps(), 300, "House edge should be updated");
        assertEq(settlementEngine.winMultiplierBps(), 20_000, "Win multiplier should be updated");
        assertEq(settlementEngine.minBetAmount(), 0.01 ether, "Min bet should be updated");
        assertEq(settlementEngine.maxBetAmount(), 500 ether, "Max bet should be updated");
    }

    function test_UpdateConfig_RevertsOnInvalidHouseEdge() public {
        vm.expectRevert(abi.encodeWithSelector(SettlementEngine.InvalidConfig.selector));
        settlementEngine.updateConfig(
            1001, // > 10%
            20_000,
            0.001 ether,
            1000 ether
        );
    }

    function test_UpdateConfig_RevertsOnInvalidMultiplier() public {
        vm.expectRevert(abi.encodeWithSelector(SettlementEngine.InvalidConfig.selector));
        settlementEngine.updateConfig(
            200,
            9999, // < 1x
            0.001 ether,
            1000 ether
        );
    }

    function test_UpdateConfig_RevertsOnZeroMinBet() public {
        vm.expectRevert(abi.encodeWithSelector(SettlementEngine.InvalidConfig.selector));
        settlementEngine.updateConfig(200, 20_000, 0, 1000 ether);
    }

    function test_UpdateConfig_RevertsOnMaxLessThanMin() public {
        vm.expectRevert(abi.encodeWithSelector(SettlementEngine.InvalidConfig.selector));
        settlementEngine.updateConfig(200, 20_000, 10 ether, 5 ether);
    }

    function test_UpdateConfig_RevertsWhenNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        settlementEngine.updateConfig(200, 20_000, 0.001 ether, 1000 ether);
    }

    function test_SetPositionManager_Success() public {
        address newPM = makeAddr("newPositionManager");

        settlementEngine.setPositionManager(newPM);

        assertEq(settlementEngine.positionManager(), newPM, "Position manager should be updated");
    }

    function test_SetPositionManager_RevertsOnZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(SettlementEngine.InvalidAddress.selector));
        settlementEngine.setPositionManager(address(0));
    }

    function test_SetVaultManager_Success() public {
        address newVM = makeAddr("newVaultManager");

        settlementEngine.setVaultManager(newVM);

        assertEq(settlementEngine.vaultManager(), newVM, "Vault manager should be updated");
    }

    function test_SetVaultManager_RevertsOnZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(SettlementEngine.InvalidAddress.selector));
        settlementEngine.setVaultManager(address(0));
    }

    function test_SetBlocksenseOracle_Success() public {
        BlocksenseOracle newOracle = new BlocksenseOracle();
        bytes memory initData = abi.encodeWithSelector(
            BlocksenseOracle.initialize.selector, owner, address(mockRegistry), 3600
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(newOracle), initData);

        settlementEngine.setBlocksenseOracle(address(proxy));

        assertEq(settlementEngine.blocksenseOracle(), address(proxy), "Oracle should be updated");
    }

    function test_SetBlocksenseOracle_RevertsOnZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(SettlementEngine.InvalidAddress.selector));
        settlementEngine.setBlocksenseOracle(address(0));
    }

    function test_Pause_Success() public {
        settlementEngine.pause();

        (,,,, bool isPaused) = settlementEngine.getSettlementConfig();
        assertTrue(isPaused, "Should be paused");
    }

    function test_Unpause_Success() public {
        settlementEngine.pause();
        settlementEngine.unpause();

        (,,,, bool isPaused) = settlementEngine.getSettlementConfig();
        assertFalse(isPaused, "Should be unpaused");
    }

    function test_SetMaxProfitCapBps_Success() public {
        settlementEngine.setMaxProfitCapBps(500);

        assertEq(settlementEngine.maxProfitCapBps(), 500, "Max profit cap should be updated");
    }

    function test_SetMaxProfitCapBps_RevertsOnTooHigh() public {
        vm.expectRevert(abi.encodeWithSelector(SettlementEngine.InvalidConfig.selector));
        settlementEngine.setMaxProfitCapBps(1001);
    }

    function test_Version_ReturnsCorrectVersion() public {
        string memory ver = settlementEngine.version();
        assertEq(ver, "1.0.0-settlement-engine", "Version should match");
    }

    // ========================================================================
    // INTEGRATION TESTS (require full setup)
    // ========================================================================

    function test_GetSettlementPrice_Success() public {
        _updatePrice(address(projectToken), address(usdc), 100e18);

        (uint256 price, uint256 publishTime) =
            settlementEngine.getSettlementPrice(address(projectToken), 3600);

        assertEq(price, 100e18, "Price should be 100");
        assertEq(publishTime, block.timestamp, "Publish time should match");
    }

    function test_GetSettlementPrice_RevertsWhenPaused() public {
        _updatePrice(address(projectToken), address(usdc), 100e18);
        settlementEngine.pause();

        vm.expectRevert();
        settlementEngine.getSettlementPrice(address(projectToken), 3600);
    }

    function test_GetSettlementPrice_RevertsOnStalePrice() public {
        _updatePrice(address(projectToken), address(usdc), 100e18);

        // Set old timestamp in mock adapter (1 hour ago)
        mockAdapter.setMockTimestamp(1);

        // Warp to make sure current time is much later
        vm.warp(block.timestamp + 7200); // 2 hours later

        // Oracle throws InvalidOraclePrice for stale price
        vm.expectRevert(abi.encodeWithSelector(SettlementEngine.InvalidOraclePrice.selector));
        settlementEngine.getSettlementPrice(address(projectToken), 3600);
    }
}
