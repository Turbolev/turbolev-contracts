// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../../src/SettlementEngine.sol";
import "../../src/oracles/BlocksenseOracle.sol";
import "../../src/oracles/ChainlinkOracle.sol";
import "../../src/PriceFeedManager.sol";
import "../../src/interfaces/IPriceFeedManager.sol";

// Modular Vault imports
import "../../src/vault-modular/VaultRouter.sol";
import "../../src/vault-modular/VaultAccessController.sol";
import "../../src/vault-modular/VaultManager.sol" as ModularVM;
import "../../src/vault-modular/modules/VaultCore.sol";
import "../../src/vault-modular/modules/VaultFunding.sol";
import "../../src/vault-modular/modules/VaultRewards.sol";
import "../../src/vault-modular/libraries/VaultStorageLib.sol";
import "../../src/interfaces/IVaultRouter.sol";

// Modular Position imports
import "../../src/position-modular/PositionRouter.sol";
import "../../src/position-modular/modules/PositionCore.sol";
import "../../src/position-modular/modules/PositionPendingClose.sol";

import "../../src/interfaces/ICLFeedRegistryAdapter.sol";
import "../../src/interfaces/ICLAggregatorAdapter.sol";
import "../../src/interfaces/IChainlinkAggregatorV3.sol";
import "../../src/interfaces/chainlink/IChainlinkAggregator.sol";
import "../../src/interfaces/IPriceFeedManager.sol";
import "../../src/interfaces/oracles/IBaseOracle.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// ========================================================================
// MOCK CONTRACTS
// ========================================================================

contract MockRegistry is ICLFeedRegistryAdapter {
    mapping(address => mapping(address => int256)) private prices;
    mapping(address => mapping(address => uint8)) private decimalsMapping;
    mapping(address => mapping(address => uint256)) private timestamps;

    function setPrice(address base, address quote, int256 price) external {
        prices[base][quote] = price;
        timestamps[base][quote] = block.timestamp;
    }

    function setDecimals(address base, address quote, uint8 _decimals) external {
        decimalsMapping[base][quote] = _decimals;
    }

    function decimals(address base, address quote) external view override returns (uint8) {
        uint8 d = decimalsMapping[base][quote];
        return d == 0 ? 18 : d;
    }

    function latestRoundData(address base, address quote)
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        int256 price = prices[base][quote];
        uint256 ts = timestamps[base][quote];
        if (ts == 0) ts = block.timestamp;
        return (1, price == 0 ? int256(100e18) : price, ts, ts, 1);
    }

    function latestAnswer(address base, address quote) external view returns (int256) {
        int256 price = prices[base][quote];
        return price == 0 ? int256(100e18) : price;
    }

    function description(address, address) external pure override returns (string memory) {
        return "Mock Registry";
    }

    function version(address, address) external pure returns (uint256) {
        return 1;
    }

    function getRoundData(address, address, uint80)
        external
        view
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (1, int256(100e18), block.timestamp, block.timestamp, 1);
    }

    function latestRound(address, address) external pure override returns (uint256) {
        return 1;
    }

    function getAnswer(address, address, uint256) external pure returns (int256) {
        return int256(100e18);
    }

    function getTimestamp(address, address, uint256) external view returns (uint256) {
        return block.timestamp;
    }

    function getFeed(address, address) external pure returns (address) {
        return address(0);
    }

    function isFeedEnabled(address) external pure returns (bool) {
        return true;
    }

    function getPhaseRange(address, address, uint16) external pure returns (uint80, uint80) {
        return (1, 1);
    }

    function getCurrentPhaseId(address, address) external pure returns (uint16) {
        return 1;
    }

    function getPhaseId(address, address, uint80) external pure returns (uint16) {
        return 1;
    }

    function getPreviousRoundId(address, address, uint80) external pure returns (uint80) {
        return 0;
    }

    function getNextRoundId(address, address, uint80) external pure returns (uint80) {
        return 2;
    }
}

contract MockAdapter is ICLAggregatorAdapter, IChainlinkAggregatorV3 {
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

    function latestRoundData()
        external
        view
        override(IChainlinkAggregator, IChainlinkAggregatorV3)
        returns (uint80, int256, uint256, uint256, uint80)
    {
        if (baseToken != address(0) && quoteToken != address(0)) {
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

contract MockERC20 {
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

    function burn(address from, uint256 amount) external {
        require(balanceOf[from] >= amount, "Insufficient balance");
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
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

// ========================================================================
// BASE TEST CONTRACT FOR MODULAR VAULT
// ========================================================================

contract BaseTestModular is Test {
    // Core contracts
    PositionRouter public positionManager;
    ModularVM.VaultManager public vaultManager;
    SettlementEngine public settlementEngine;
    BlocksenseOracle public blocksenseOracle;
    ChainlinkOracle public chainlinkOracle;
    PriceFeedManager public priceFeedManager;

    // Modular Vault contracts
    VaultAccessController public vaultAccessController;
    VaultRouter public vaultRouterImpl;
    VaultCore public vaultCoreModule;
    VaultFunding public vaultFundingModule;
    VaultRewards public vaultRewardsModule;

    // Modular Position contracts
    PositionRouter public positionRouterImpl;
    PositionCore public positionCoreModule;
    PositionPendingClose public positionPendingCloseModule;

    // Deployed vault (proxy)
    VaultRouter public vault;

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
    address public keeper;
    address public mockMultisigWallet;
    address public mockTimelockController;

    // Test vault address (for convenience)
    address public testVault;

    // Constants
    uint256 public constant INITIAL_BALANCE = 1_000_000 ether;
    uint256 public constant PRICE_DECIMALS = 18;

    // Default parameters
    uint16 public constant DEFAULT_HOUSE_EDGE_BPS = 200; // 2%
    uint16 public constant DEFAULT_WIN_MULTIPLIER_BPS = 18_000; // 1.8x
    uint256 public constant DEFAULT_MIN_BET = 0.01 ether;
    uint256 public constant DEFAULT_MAX_BET = 100 ether;
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
        keeper = makeAddr("keeper");
        mockTimelockController = makeAddr("mockTimelockController");
        mockMultisigWallet = makeAddr("mockMultisigWallet");

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

        // Create vault
        _createVault();
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
            abi.encodeWithSelector(ChainlinkOracle.initialize.selector, 3600);
        ERC1967Proxy chainlinkProxy = new ERC1967Proxy(address(chainlinkImpl), chainlinkInitData);
        chainlinkOracle = ChainlinkOracle(address(chainlinkProxy));

        // Deploy PriceFeedManager (upgradeable via ERC1967Proxy)
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

        // Deploy Modular Vault components first (to get vaultAccessController)
        _deployModularVault();

        // Deploy Modular Position components
        _deployModularPosition();

        // Now setup all addresses after PositionManager is deployed
        _setupModularVaultAddresses();
    }

    function _deployModularPosition() internal {
        // Deploy modules (logic contracts)
        positionCoreModule = new PositionCore();
        positionPendingCloseModule = new PositionPendingClose();

        // Deploy PositionRouter implementation
        positionRouterImpl = new PositionRouter();

        // Deploy PositionRouter proxy with initialization
        bytes memory positionInitData = abi.encodeWithSelector(
            PositionRouter.initialize.selector,
            address(vaultAccessController), // accessController
            address(settlementEngine), // settlementEngine
            address(vaultManager), // vaultManager
            address(priceFeedManager), // priceFeedManager
            address(positionCoreModule), // coreModule
            address(positionPendingCloseModule) // pendingCloseModule
        );
        ERC1967Proxy positionProxy = new ERC1967Proxy(address(positionRouterImpl), positionInitData);
        positionManager = PositionRouter(payable(address(positionProxy)));
    }

    function _deployModularVault() internal {
        // Deploy modules (these are logic contracts, not proxies)
        vaultCoreModule = new VaultCore();
        vaultFundingModule = new VaultFunding();
        vaultRewardsModule = new VaultRewards();

        // Deploy VaultRouter implementation
        vaultRouterImpl = new VaultRouter();

        // Deploy VaultAccessController (without initialize - will initialize after VaultManager)
        VaultAccessController accessControllerImpl = new VaultAccessController();
        ERC1967Proxy accessControllerProxy = new ERC1967Proxy(
            address(accessControllerImpl),
            "" // Initialize later
        );
        vaultAccessController = VaultAccessController(address(accessControllerProxy));

        // Deploy VaultManager (modular)
        ModularVM.VaultManager vaultManagerImpl = new ModularVM.VaultManager();
        bytes memory vaultManagerInitData = abi.encodeWithSelector(
            ModularVM.VaultManager.initialize.selector,
            owner,
            address(vaultAccessController),
            address(vaultRouterImpl),
            address(vaultCoreModule),
            address(vaultFundingModule),
            address(vaultRewardsModule),
            mockTimelockController,
            mockMultisigWallet
        );
        ERC1967Proxy vaultManagerProxy =
            new ERC1967Proxy(address(vaultManagerImpl), vaultManagerInitData);
        vaultManager = ModularVM.VaultManager(payable(address(vaultManagerProxy)));
    }

    function _setupModularVaultAddresses() internal {
        // This is called after PositionRouter is deployed
        // Initialize VaultAccessController with all addresses
        vaultAccessController.initialize(
            mockTimelockController, // admin
            address(vaultManager),
            address(positionManager),
            mockMultisigWallet
        );

        // Grant POSITION_KEEPER_ROLE to admin for testing
        vm.startPrank(mockTimelockController);
        vaultAccessController.grantRole(vaultAccessController.POSITION_KEEPER_ROLE(), admin);
        vm.stopPrank();

        // Set addresses
        vm.startPrank(owner);

        // PositionRouter is already configured via initialize
        // Update VaultManager with PositionRouter address
        vaultManager.setPositionManager(address(positionManager));

        settlementEngine.setPositionManager(address(positionManager));
        settlementEngine.setVaultManager(address(vaultManager));
        settlementEngine.setPriceFeedManager(address(priceFeedManager));
        settlementEngine.setAccessController(address(vaultAccessController));

        // Set accessController for PriceFeedManager
        priceFeedManager.setAccessController(address(vaultAccessController));

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

        IPriceFeedManager.OracleProvider memory blocksenseProvider = IPriceFeedManager.OracleProvider({
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
            primaryFeed: address(mockAdapter),
            secondaryFeed: address(mockAdapter),
            usePullMode: false
        });
        priceFeedManager.setPriceFeedConfig(address(projectToken), config);

        // Set default price
        mockRegistry.setPrice(address(projectToken), address(usdc), 100e18);
    }

    function _createVault() internal {
        vm.startPrank(owner);
        address vaultAddress = vaultManager.createVault(
            address(projectToken), DEFAULT_MIN_BET, DEFAULT_MAX_BET, DEFAULT_GRADUATION_THRESHOLD
        );
        vault = VaultRouter(payable(vaultAddress));
        testVault = vaultAddress;
        vm.stopPrank();
    }

    // ========================================================================
    // HELPER FUNCTIONS
    // ========================================================================

    function _addLiquidity(address user, uint256 amount) internal {
        vm.startPrank(user);
        projectToken.approve(address(vault), amount);
        vault.addLiquidity(amount);
        vm.stopPrank();
    }

    function _enableTrading() internal {
        vm.prank(address(vaultManager));
        vault.setTradingEnabled(true);
    }

    function _graduateVault() internal {
        // Add enough liquidity to graduate
        _addLiquidity(liquidityProvider, DEFAULT_GRADUATION_THRESHOLD);
    }
}
