// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/PositionManager.sol";
import "../src/AssetVault.sol";
import "../src/VaultManager.sol";
import "../src/SettlementEngine.sol";
import "../src/BlocksenseOracle.sol";
import "../src/VaultManagerHelper.sol";
import "../src/interfaces/ICLFeedRegistryAdapter.sol";
import "../src/interfaces/ICLAggregatorAdapter.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockAdapter is ICLAggregatorAdapter {
    address public dataFeedStore;
    uint256 public id;
    uint256 public mockTimestamp;
    address public baseToken;
    address public quoteToken;

    constructor(address _dataFeedStore, uint256 _id) {
        dataFeedStore = _dataFeedStore;
        id = _id;
        mockTimestamp = block.timestamp;
    }

    function setTokens(address _baseToken, address _quoteToken) external {
        baseToken = _baseToken;
        quoteToken = _quoteToken;
    }

    function setMockTimestamp(uint256 _timestamp) external {
        mockTimestamp = _timestamp;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        if (baseToken != address(0) && quoteToken != address(0)) {
            // Get price from MockRegistry
            int256 price = MockRegistry(dataFeedStore).latestAnswer(baseToken, quoteToken);
            return (1, price, mockTimestamp, mockTimestamp, 1);
        }
        return (1, 100e18, mockTimestamp, mockTimestamp, 1);
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function description() external pure returns (string memory) {
        return "Mock Adapter";
    }

    function version() external pure returns (uint256) {
        return 1;
    }

    function getRoundData(uint80)
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (1, 100e18, block.timestamp, block.timestamp, 1);
    }

    function latestAnswer() external pure returns (int256) {
        return 100e18;
    }

    function latestRound() external pure returns (uint256) {
        return 1;
    }
}

contract MockRegistry is ICLFeedRegistryAdapter {
    mapping(address => mapping(address => int256)) public prices;
    mapping(address => mapping(address => uint256)) public timestamps;
    mapping(address => mapping(address => uint8)) public decimalsMap;

    function setPrice(address base, address quote, int256 price) external {
        prices[base][quote] = price;
        timestamps[base][quote] = block.timestamp;
    }

    function setDecimals(address base, address quote, uint8 _decimals) external {
        decimalsMap[base][quote] = _decimals;
    }

    function latestRoundData(address base, address quote)
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (1, prices[base][quote], block.timestamp, timestamps[base][quote], 1);
    }

    function getRoundData(address base, address quote, uint80)
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (1, prices[base][quote], block.timestamp, timestamps[base][quote], 1);
    }

    function latestAnswer(address base, address quote) external view returns (int256) {
        return prices[base][quote];
    }

    function latestRound(address, address) external pure returns (uint256 roundId) {
        return 1;
    }

    function decimals(address base, address quote) external view returns (uint8) {
        uint8 dec = decimalsMap[base][quote];
        return dec == 0 ? 18 : dec;
    }

    function description(address, address) external pure returns (string memory) {
        return "Mock";
    }

    function version() external pure returns (uint256) {
        return 1;
    }
}

contract MockERC20 is Test {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");

        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;

        emit Transfer(from, to, amount);
        return true;
    }
}

contract BaseTest is Test {
    // Core contracts
    PositionManager public positionManager;
    VaultManager public vaultManager;
    VaultManagerHelper public vaultManagerHelper;
    SettlementEngine public settlementEngine;
    BlocksenseOracle public blocksenseOracle;
    AssetVault public assetVault;

    // Mock contracts
    MockRegistry public mockRegistry;
    MockAdapter public mockAdapter;
    MockERC20 public projectToken;
    MockERC20 public usdc;

    // Test accounts
    address public owner;
    address public backend;
    address public user1;
    address public user2;
    address public liquidityProvider;
    address public priceUpdater;

    // Constants
    uint256 public constant INITIAL_BALANCE = 1_000_000 ether;
    uint256 public constant PRICE_DECIMALS = 18;

    // Default parameters
    uint16 public constant DEFAULT_HOUSE_EDGE_BPS = 200; // 2%
    uint16 public constant DEFAULT_WIN_MULTIPLIER_BPS = 18_000; // 1.8x
    uint256 public constant DEFAULT_MIN_BET = 0.01 ether;
    uint256 public constant DEFAULT_MAX_BET = 100 ether;

    uint16 public constant DEFAULT_MAX_PAYOUT_BPS = 500; // 5%
    uint16 public constant DEFAULT_PER_BET_UTIL_BPS = 1000; // 10%
    uint16 public constant DEFAULT_MAX_UTIL_BPS = 8000; // 80%
    uint256 public constant DEFAULT_GRADUATION_THRESHOLD = 10_000 ether;

    function setUp() public virtual {
        // Setup accounts
        owner = address(this);
        backend = makeAddr("backend");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        liquidityProvider = makeAddr("liquidityProvider");
        priceUpdater = makeAddr("priceUpdater");

        // Deploy mock tokens
        projectToken = new MockERC20("Project Token", "PROJ");
        usdc = new MockERC20("USD Coin", "USDC");

        // Mint tokens to test accounts
        projectToken.mint(user1, INITIAL_BALANCE);
        projectToken.mint(user2, INITIAL_BALANCE);
        projectToken.mint(liquidityProvider, INITIAL_BALANCE);
        projectToken.mint(address(this), INITIAL_BALANCE);

        usdc.mint(user1, INITIAL_BALANCE);
        usdc.mint(user2, INITIAL_BALANCE);

        // Fund test accounts with native tokens
        vm.deal(user1, INITIAL_BALANCE);
        vm.deal(user2, INITIAL_BALANCE);
        vm.deal(liquidityProvider, INITIAL_BALANCE);
        vm.deal(backend, 1 ether);
        vm.deal(priceUpdater, 1 ether);

        // Deploy core contracts
        _deployContracts();

        // Setup contracts
        _setupContracts();
    }

    function _deployContracts() internal {
        // Deploy mock registry
        mockRegistry = new MockRegistry();

        // Deploy mock adapter
        mockAdapter = new MockAdapter(address(mockRegistry), 1);

        // Deploy BlocksenseOracle (upgradeable via ERC1967Proxy)
        BlocksenseOracle oracleImpl = new BlocksenseOracle();
        bytes memory oracleInitData = abi.encodeWithSelector(
            BlocksenseOracle.initialize.selector,
            owner,
            address(mockRegistry),
            3600 // max price age
        );
        ERC1967Proxy oracleProxy = new ERC1967Proxy(address(oracleImpl), oracleInitData);
        blocksenseOracle = BlocksenseOracle(payable(address(oracleProxy)));

        // Deploy SettlementEngine (upgradeable via ERC1967Proxy)
        SettlementEngine settlementImpl = new SettlementEngine();
        bytes memory settlementInitData =
            abi.encodeWithSelector(SettlementEngine.initialize.selector, owner);
        ERC1967Proxy settlementProxy = new ERC1967Proxy(address(settlementImpl), settlementInitData);
        settlementEngine = SettlementEngine(payable(address(settlementProxy)));

        // Deploy PositionManager (upgradeable via ERC1967Proxy)
        PositionManager positionImpl = new PositionManager();
        bytes memory positionInitData =
            abi.encodeWithSelector(PositionManager.initialize.selector, owner, backend);
        ERC1967Proxy positionProxy = new ERC1967Proxy(address(positionImpl), positionInitData);
        positionManager = PositionManager(payable(address(positionProxy)));

        // Deploy VaultManager (upgradeable via ERC1967Proxy)
        VaultManager vaultImpl = new VaultManager();
        bytes memory vaultInitData = abi.encodeWithSelector(VaultManager.initialize.selector, owner);
        ERC1967Proxy vaultProxy = new ERC1967Proxy(address(vaultImpl), vaultInitData);
        vaultManager = VaultManager(payable(address(vaultProxy)));

        // Deploy VaultManagerHelper
        vaultManagerHelper = new VaultManagerHelper(address(vaultManager));

        // Set addresses
        positionManager.setVaultManager(address(vaultManager));
        positionManager.setSettlementEngine(address(settlementEngine));

        vaultManager.setPositionManager(address(positionManager));

        settlementEngine.setPositionManager(address(positionManager));
        settlementEngine.setVaultManager(address(vaultManager));
    }

    function _setupContracts() internal {
        // Set oracle in Settlement Engine
        settlementEngine.setBlocksenseOracle(payable(address(blocksenseOracle)));

        // Set default price decimals for mock registry
        mockRegistry.setDecimals(address(projectToken), address(usdc), 18);

        // Set BlocksenseOracle in VaultManager before creating vault
        vaultManager.setBlocksenseOracle(address(blocksenseOracle));

        // Create vault for project token (now requires oracleAdapter)
        address vaultAddr = vaultManager.createVault(
            address(projectToken),
            address(mockAdapter), // oracleAdapter parameter
            DEFAULT_MIN_BET,
            DEFAULT_MAX_BET,
            DEFAULT_GRADUATION_THRESHOLD
        );
        assetVault = AssetVault(payable(vaultAddr));

        // Transfer ownership of vault to test contract for easier testing
        // AssetVault is owned by VaultManager after creation
        vm.prank(address(vaultManager));
        assetVault.transferOwnership(owner);

        // Set tokens for mock adapter now that they're created
        mockAdapter.setTokens(address(projectToken), address(usdc));

        // Set position manager in vault so it can accept deposits
        // Note: Already set in constructor by VaultManager, but we re-set to be sure
        assetVault.setPositionManager(address(positionManager));

        console.log("AssetVault address:", address(assetVault));
        console.log("PositionManager address:", address(positionManager));
    }

    // Helper functions
    function _updatePrice(address base, address quote, int256 price) internal {
        mockRegistry.setPrice(base, quote, price);
    }

    function _addLiquidity(address provider, uint256 amount) internal returns (uint256 shares) {
        vm.startPrank(provider);
        projectToken.approve(address(assetVault), amount);
        assetVault.addLiquidity(amount);
        vm.stopPrank();

        // Get shares from LP position
        AssetVault.LPPosition memory lpPos = assetVault.getLPPosition(provider);
        shares = lpPos.shares;
    }

    function _openPosition(address user, uint256 amount, uint8 leverage, uint8 direction)
        internal
        returns (uint64 positionId)
    {
        vm.startPrank(user);
        projectToken.approve(address(positionManager), amount);
        positionId = positionManager.openPosition(
            address(projectToken),
            amount,
            leverage,
            direction,
            0, // no price limit
            block.timestamp + 3600 // deadline = 1 hour
        );
        vm.stopPrank();
    }

    function _skipTime(uint256 seconds_) internal {
        vm.warp(block.timestamp + seconds_);
    }

    function _getPosition(uint64 positionId) internal view returns (PositionLib.Position memory) {
        return positionManager.getPosition(positionId);
    }
}
