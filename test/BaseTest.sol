// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/PositionManager.sol";
import "../src/AssetVault.sol";
import "../src/AssetVaultUpgradeable.sol";
import "../src/VaultManager.sol";
import "../src/SettlementEngine.sol";
import "../src/oracles/BlocksenseOracle.sol";
import "../src/oracles/ChainlinkOracle.sol";
import "../src/PriceFeedManager.sol";
import "../src/VaultManagerHelper.sol";
import "../src/governance/VaultBeacon.sol";
import "../src/interfaces/ICLFeedRegistryAdapter.sol";
import "../src/interfaces/ICLAggregatorAdapter.sol";
import "../src/interfaces/IChainlinkAggregatorV3.sol";
import "../src/interfaces/chainlink/IChainlinkAggregator.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockAdapter is ICLAggregatorAdapter, IChainlinkAggregatorV3 {
    // Implement both interfaces - functions are shared
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

    // Shared functions for both interfaces
    function latestRoundData()
        external
        view
        override(IChainlinkAggregator, IChainlinkAggregatorV3)
        returns (uint80, int256, uint256, uint256, uint80)
    {
        if (baseToken != address(0) && quoteToken != address(0)) {
            // Get price from MockRegistry
            int256 price = MockRegistry(dataFeedStore).latestAnswer(baseToken, quoteToken);
            return (1, price, mockTimestamp, mockTimestamp, 1);
        }
        return (1, 100e18, mockTimestamp, mockTimestamp, 1);
    }

    function decimals()
        external
        pure
        override(IChainlinkAggregator, IChainlinkAggregatorV3)
        returns (uint8)
    {
        return 18;
    }

    function description()
        external
        pure
        override(IChainlinkAggregator, IChainlinkAggregatorV3)
        returns (string memory)
    {
        return "Mock Adapter";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function getRoundData(uint80)
        external
        view
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        if (baseToken != address(0) && quoteToken != address(0)) {
            // Get price from MockRegistry
            int256 price = MockRegistry(dataFeedStore).latestAnswer(baseToken, quoteToken);
            return (1, price, mockTimestamp, mockTimestamp, 1);
        }
        return (1, 100e18, mockTimestamp, mockTimestamp, 1);
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
    ChainlinkOracle public chainlinkOracle;
    PriceFeedManager public priceFeedManager;
    AssetVaultUpgradeable public assetVault;

    // Mock contracts
    MockRegistry public mockRegistry;
    MockAdapter public mockAdapter;
    MockERC20 public projectToken;
    MockERC20 public usdc;

    // Test accounts
    address public owner;
    address public admin;
    address public user1;
    address public user2;
    address public liquidityProvider;
    address public priceUpdater;
    address public backend;

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
        admin = makeAddr("admin");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        liquidityProvider = makeAddr("liquidityProvider");
        priceUpdater = makeAddr("priceUpdater");
        backend = makeAddr("backend");
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
        vm.deal(admin, 1 ether);
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
            3600 // max price age
        );
        ERC1967Proxy oracleProxy = new ERC1967Proxy(address(oracleImpl), oracleInitData);
        blocksenseOracle = BlocksenseOracle(payable(address(oracleProxy)));

        // Deploy ChainlinkOracle (upgradeable via ERC1967Proxy)
        ChainlinkOracle chainlinkImpl = new ChainlinkOracle();
        bytes memory chainlinkInitData =
            abi.encodeWithSelector(ChainlinkOracle.initialize.selector, 3600); // max price age
        ERC1967Proxy chainlinkProxy = new ERC1967Proxy(address(chainlinkImpl), chainlinkInitData);
        chainlinkOracle = ChainlinkOracle(address(chainlinkProxy));

        // Deploy PriceFeedManager (upgradeable via ERC1967Proxy) - V2.1
        PriceFeedManager priceFeedImpl = new PriceFeedManager();
        bytes memory priceFeedInitData =
            abi.encodeWithSelector(PriceFeedManager.initialize.selector, owner);
        ERC1967Proxy priceFeedProxy = new ERC1967Proxy(address(priceFeedImpl), priceFeedInitData);
        priceFeedManager = PriceFeedManager(payable(address(priceFeedProxy)));

        // Deploy SettlementEngine (upgradeable via ERC1967Proxy)
        SettlementEngine settlementImpl = new SettlementEngine();
        bytes memory settlementInitData =
            abi.encodeWithSelector(SettlementEngine.initialize.selector, owner);
        ERC1967Proxy settlementProxy = new ERC1967Proxy(address(settlementImpl), settlementInitData);
        settlementEngine = SettlementEngine(payable(address(settlementProxy)));

        // Deploy PositionManager (upgradeable via ERC1967Proxy)
        PositionManager positionImpl = new PositionManager();
        bytes memory positionInitData =
            abi.encodeWithSelector(PositionManager.initialize.selector, owner, admin);
        ERC1967Proxy positionProxy = new ERC1967Proxy(address(positionImpl), positionInitData);
        positionManager = PositionManager(payable(address(positionProxy)));

        // Deploy VaultManager (upgradeable via ERC1967Proxy)
        VaultManager vaultImpl = new VaultManager();

        // Create mock governance addresses for testing
        address mockOptInUpgradeManager = makeAddr("mockOptInUpgradeManager");

        // Deploy VaultBeacon for AssetVault (needed for createVaultWithBeacon)
        AssetVaultUpgradeable vaultImplementation = new AssetVaultUpgradeable();
        VaultBeacon vaultBeaconContract =
            new VaultBeacon(address(vaultImplementation), owner, mockOptInUpgradeManager);
        address mockTimelockController = makeAddr("mockTimelockController");
        address mockMultisigWallet = makeAddr("mockMultisigWallet");
        address mockVaultGovernor = makeAddr("mockVaultGovernor");

        bytes memory vaultInitData = abi.encodeWithSelector(
            VaultManager.initializeV2.selector,
            owner,
            address(vaultBeaconContract),
            mockOptInUpgradeManager,
            mockTimelockController,
            mockMultisigWallet,
            mockVaultGovernor
        );
        ERC1967Proxy vaultProxy = new ERC1967Proxy(address(vaultImpl), vaultInitData);
        vaultManager = VaultManager(payable(address(vaultProxy)));

        // Deploy VaultManagerHelper
        vaultManagerHelper = new VaultManagerHelper(address(vaultManager));

        // Set addresses (all these contracts are owned by 'owner')
        vm.startPrank(owner);

        positionManager.setVaultManager(address(vaultManager));
        positionManager.setSettlementEngine(address(settlementEngine));
        positionManager.setPriceFeedManager(address(priceFeedManager));

        vaultManager.setPositionManager(address(positionManager));
        vaultManager.setVaultManagerHelper(address(vaultManagerHelper));

        settlementEngine.setPositionManager(address(positionManager));
        settlementEngine.setVaultManager(address(vaultManager));
        settlementEngine.setPriceFeedManager(address(priceFeedManager));
        // Note: Oracle logic moved to PriceFeedManager

        vaultManagerHelper.setPriceFeedManager(address(priceFeedManager));

        vm.stopPrank();
    }

    function _setupContracts() internal {
        // Set default price decimals for mock registry
        mockRegistry.setDecimals(address(projectToken), address(usdc), 18);

        // Set tokens for mock adapter now that they're created
        mockAdapter.setTokens(address(projectToken), address(usdc));

        // Configure PriceFeedManager V2.1 with Oracle Registry
        // 1. Register providers (without feed - feed is per-token in config)
        IPriceFeedManager.OracleProvider memory chainlinkProvider = IPriceFeedManager.OracleProvider({
            oracleContract: address(chainlinkOracle),
            oracleType: IBaseOracle.OracleType.PUSH,
            enabled: true
        });
        priceFeedManager.registerOracleProvider(
            priceFeedManager.CHAINLINK_PROVIDER(), chainlinkProvider
        );

        IPriceFeedManager.OracleProvider memory blocksenseProvider = IPriceFeedManager
            .OracleProvider({
            oracleContract: address(blocksenseOracle),
            oracleType: IBaseOracle.OracleType.PUSH,
            enabled: true
        });
        priceFeedManager.registerOracleProvider(
            priceFeedManager.BLOCKSENSE_PROVIDER(), blocksenseProvider
        );

        // 2. Configure token with feed addresses
        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: priceFeedManager.CHAINLINK_PROVIDER(),
            secondaryProviderId: priceFeedManager.BLOCKSENSE_PROVIDER(),
            primaryFeed: address(mockAdapter), // Feed for Chainlink
            secondaryFeed: address(mockAdapter), // Feed for Blocksense
            usePullMode: false
        });
        priceFeedManager.setPriceFeedConfig(address(projectToken), config);

        // Create vault using BeaconProxy (proper way)
        address vaultAddr = vaultManager.createVaultWithBeacon(
            address(projectToken), DEFAULT_MIN_BET, DEFAULT_MAX_BET, DEFAULT_GRADUATION_THRESHOLD
        );
        assetVault = AssetVaultUpgradeable(payable(vaultAddr));

        // Transfer ownership to test contract for easier testing
        address currentOwner = assetVault.owner();
        if (currentOwner != owner) {
            vm.prank(currentOwner);
            assetVault.transferOwnership(owner);
        }

        console.log("AssetVault address:", address(assetVault));
        console.log("PositionManager address:", address(positionManager));
        console.log("PriceFeedManager address:", address(priceFeedManager));
        console.log("Vault owner after transfer:", assetVault.owner());
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
        AssetVaultUpgradeable.LPPosition memory lpPos = assetVault.getLPPosition(provider);
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
            block.timestamp + 3600, // deadline = 1 hour
            "" // No price update data
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
