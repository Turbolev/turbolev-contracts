// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../src/PositionManager.sol";
import "../../src/SettlementEngine.sol";
import "../../src/libraries/PositionLib.sol";
import "../../src/interfaces/IVaultAccessController.sol";
import "../../src/interfaces/IPriceFeedManager.sol";
import "../../src/interfaces/IVaultManager.sol";
import "../../src/interfaces/IAssetVault.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title MockVaultAccessControllerForPending
 * @notice Mock access controller for testing
 */
contract MockVaultAccessControllerForPending is IVaultAccessController {
    mapping(address => bool) public positionKeepers;

    bytes32 public constant VAULT_ADMIN_ROLE = keccak256("VAULT_ADMIN_ROLE");
    bytes32 public constant POSITION_MANAGER_ROLE = keccak256("POSITION_MANAGER_ROLE");
    bytes32 public constant VAULT_KEEPER_ROLE = keccak256("VAULT_KEEPER_ROLE");
    bytes32 public constant POSITION_KEEPER_ROLE = keccak256("POSITION_KEEPER_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    function setPositionKeeper(address keeper, bool status) external {
        positionKeepers[keeper] = status;
    }

    function hasVaultRole(address, bytes32, address) external pure returns (bool) {
        return false;
    }

    function isVaultAdmin(address, address) external pure returns (bool) {
        return false;
    }

    function isPositionManager(address) external pure returns (bool) {
        return false;
    }

    function isVaultKeeper(address) external pure returns (bool) {
        return false;
    }

    function isPositionKeeper(address account) external view returns (bool) {
        return positionKeepers[account];
    }

    function hasEmergencyRole(address) external pure returns (bool) {
        return false;
    }

    function isVaultRegistered(address) external pure returns (bool) {
        return false;
    }

    function hasRole(bytes32, address) external pure returns (bool) {
        return false;
    }

    function isGuardian(address) external pure returns (bool) {
        return false;
    }

    function getGuardianCount() external pure returns (uint256) {
        return 0;
    }

    function getGuardianConfig() external pure returns (uint256, uint256, uint256) {
        return (2, 10, 0);
    }

    function getConfirmationWindowConfig() external pure returns (uint256, uint256, uint256) {
        return (30 minutes, 24 hours, 1 hours);
    }
}

/**
 * @title MockPriceFeedManagerForPending
 * @notice Mock PriceFeedManager that supports both getPrice and getPriceWithUpdate
 */
contract MockPriceFeedManagerForPending {
    mapping(address => uint256) public prices;
    mapping(address => uint256) public publishTimes;

    bool public shouldRevertOnGetPrice;
    bool public shouldRevertOnGetPriceWithUpdate;
    uint256 public updateFee;

    // Track calls
    uint256 public getPriceCallCount;
    uint256 public getPriceWithUpdateCallCount;
    bytes public lastPriceUpdateData;

    function setPrice(address token, uint256 price, uint256 publishTime) external {
        prices[token] = price;
        publishTimes[token] = publishTime;
    }

    function setShouldRevertOnGetPrice(bool shouldRevert) external {
        shouldRevertOnGetPrice = shouldRevert;
    }

    function setShouldRevertOnGetPriceWithUpdate(bool shouldRevert) external {
        shouldRevertOnGetPriceWithUpdate = shouldRevert;
    }

    function setUpdateFee(uint256 fee) external {
        updateFee = fee;
    }

    function getPrice(
        address token,
        uint256 /* maxAge */
    )
        external
        view
        returns (uint256 price, uint256 publishTime)
    {
        if (shouldRevertOnGetPrice) {
            revert("Price stale");
        }
        return (prices[token], publishTimes[token]);
    }

    function getPriceWithUpdate(
        address token,
        uint256,
        /* maxAge */
        bytes calldata updateData
    )
        external
        payable
        returns (uint256 price, uint256 publishTime)
    {
        if (shouldRevertOnGetPriceWithUpdate) {
            revert("Price update failed");
        }

        // Track the call
        getPriceWithUpdateCallCount++;
        lastPriceUpdateData = updateData;

        // Optionally require fee
        if (updateFee > 0) {
            require(msg.value >= updateFee, "Insufficient fee");
        }

        return (prices[token], publishTimes[token]);
    }
}

/**
 * @title MockSettlementEngineForPending
 * @notice Mock SettlementEngine for testing pending close
 */
contract MockSettlementEngineForPending {
    uint256 public liquidationFeeBps = 100; // 1%

    function processSettlement(
        PositionLib.Position memory pos,
        uint256,
        /* closePrice */
        bool /* isLiquidation */
    )
        external
        pure
        returns (
            bool won,
            uint256 payout,
            uint256 fee,
            int256 pnl,
            int256 vaultPnL,
            uint8 finalState,
            uint256 /* empty */
        )
    {
        // Simple mock: always return some payout
        won = true;
        payout = pos.amount;
        fee = 0;
        pnl = 0;
        vaultPnL = 0;
        finalState = PositionLib.POSITION_STATE_CLOSED;
    }
}

/**
 * @title MockVaultManagerForPending
 * @notice Mock VaultManager for testing
 */
contract MockVaultManagerForPending {
    address public mockVault;

    function setMockVault(address vault) external {
        mockVault = vault;
    }

    function getVault(
        address /* projectToken */
    )
        external
        view
        returns (address)
    {
        return mockVault;
    }
}

/**
 * @title MockAssetVaultForPending
 * @notice Mock AssetVault for testing
 */
contract MockAssetVaultForPending {
    function calculatePositionFunding(int256, int256, uint256, uint8)
        external
        pure
        returns (int256)
    {
        return 0;
    }

    function getCumulativeFundingRates() external pure returns (int256, int256) {
        return (0, 0);
    }

    function getMaxProfitCapMultiplier() external pure returns (uint8) {
        return 10;
    }

    function recordPnL(int256, uint256) external { }
}

/**
 * @title MockERC20ForPending
 * @notice Simple mock ERC20 for testing
 */
contract MockERC20ForPending {
    string public name = "Mock Token";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }
}

/**
 * @title PendingCloseWithPriceDataTest
 * @notice Integration tests for processPendingClosePositions with priceUpdateData
 */
contract PendingCloseWithPriceDataTest is Test {
    PositionManager public positionManager;
    MockVaultAccessControllerForPending public accessController;
    MockPriceFeedManagerForPending public priceFeedManager;
    MockSettlementEngineForPending public settlementEngine;
    MockVaultManagerForPending public vaultManager;
    MockAssetVaultForPending public assetVault;
    MockERC20ForPending public projectToken;

    address public owner;
    address public keeper;
    address public user1;

    uint256 public constant INITIAL_BALANCE = 1000 ether;
    uint256 public constant MOCK_PRICE = 100e18;

    event PendingCloseProcessed(
        uint64 indexed positionId, bool success, PositionManager.PendingCloseReason reason
    );

    event PositionClosed(
        uint64 indexed positionId,
        address indexed user,
        address indexed projectToken,
        bool won,
        uint256 payout,
        uint256 closePrice,
        int256 pnl,
        uint256 closeTimestamp,
        uint256 pricePublishTime,
        PositionManager.PositionClosedBy closedBy
    );

    function setUp() public {
        owner = address(this);
        keeper = makeAddr("keeper");
        user1 = makeAddr("user1");

        // Deploy mocks
        accessController = new MockVaultAccessControllerForPending();
        accessController.setPositionKeeper(keeper, true);

        priceFeedManager = new MockPriceFeedManagerForPending();
        settlementEngine = new MockSettlementEngineForPending();
        vaultManager = new MockVaultManagerForPending();
        assetVault = new MockAssetVaultForPending();
        projectToken = new MockERC20ForPending();

        // Setup vault manager
        vaultManager.setMockVault(address(assetVault));

        // Setup price
        priceFeedManager.setPrice(address(projectToken), MOCK_PRICE, block.timestamp);

        // Deploy PositionManager
        PositionManager impl = new PositionManager();
        bytes memory initData = abi.encodeWithSelector(
            PositionManager.initialize.selector, owner, address(accessController)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        positionManager = PositionManager(payable(address(proxy)));

        // Configure PositionManager
        positionManager.setSettlementEngine(address(settlementEngine));
        positionManager.setVaultManager(address(vaultManager));
        positionManager.setPriceFeedManager(address(priceFeedManager));

        // Mint tokens
        projectToken.mint(user1, INITIAL_BALANCE);
        projectToken.mint(address(positionManager), INITIAL_BALANCE); // For payouts

        // Fund accounts
        vm.deal(keeper, 10 ether);
    }

    // ========================================================================
    // HELPER FUNCTIONS
    // ========================================================================

    function _createPendingPosition() internal returns (uint64 positionId) {
        // We need to manually create a position in pending state
        // Since we can't easily trigger pending through normal flow without full integration,
        // we'll test the processPendingClosePositions behavior with empty queue first
        return 0;
    }

    // ========================================================================
    // TEST: processPendingClosePositions with priceUpdateData
    // ========================================================================

    function test_ProcessPendingClose_WithEmptyPriceUpdateData() public {
        // Should work with empty priceUpdateData (uses getPrice)
        vm.prank(keeper);
        positionManager.processPendingClosePositions(10, 3600, "");

        // No positions to process, but should not revert
    }

    function test_ProcessPendingClose_WithPriceUpdateData() public {
        bytes memory priceUpdateData = abi.encode("mock_price_update");

        vm.prank(keeper);
        positionManager.processPendingClosePositions{ value: 0 }(10, 3600, priceUpdateData);

        // No positions to process, but should not revert
    }

    function test_ProcessPendingClose_IsPayable() public {
        bytes memory priceUpdateData = abi.encode("mock_price_update");

        // Should accept ETH for oracle fee
        vm.prank(keeper);
        positionManager.processPendingClosePositions{ value: 0.1 ether }(10, 3600, priceUpdateData);
    }

    function test_ProcessPendingClose_NonKeeperCannotCall() public {
        bytes memory priceUpdateData = abi.encode("mock_price_update");

        vm.prank(user1);
        vm.expectRevert(PositionManager.NotPositionKeeper.selector);
        positionManager.processPendingClosePositions(10, 3600, priceUpdateData);
    }

    function test_ProcessPendingClose_GasEstimate_EmptyQueue() public {
        bytes memory priceUpdateData = abi.encode("mock_price_update");

        vm.prank(keeper);
        uint256 gasBefore = gasleft();
        positionManager.processPendingClosePositions(10, 3600, priceUpdateData);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used for empty queue with priceUpdateData:", gasUsed);
        assertTrue(gasUsed < 50_000, "Processing empty queue should use minimal gas");
    }

    function test_ProcessPendingClose_WithDifferentMaxAge() public {
        // Test with various maxAge values
        vm.startPrank(keeper);

        positionManager.processPendingClosePositions(10, 60, ""); // 1 minute
        positionManager.processPendingClosePositions(10, 3600, ""); // 1 hour
        positionManager.processPendingClosePositions(10, 86_400, ""); // 1 day

        vm.stopPrank();
    }

    function test_ProcessPendingClose_WithDifferentMaxPositions() public {
        vm.startPrank(keeper);

        positionManager.processPendingClosePositions(1, 3600, "");
        positionManager.processPendingClosePositions(10, 3600, "");
        positionManager.processPendingClosePositions(100, 3600, "");

        vm.stopPrank();
    }

    // ========================================================================
    // TEST: Signature verification
    // ========================================================================

    function test_FunctionSignature_HasThreeParameters() public view {
        // Verify the function exists with new signature
        bytes4 selector = positionManager.processPendingClosePositions.selector;

        // The selector should be for (uint256, uint256, bytes)
        bytes4 expectedSelector =
            bytes4(keccak256("processPendingClosePositions(uint256,uint256,bytes)"));
        assertEq(selector, expectedSelector, "Function signature should match");
    }
}

