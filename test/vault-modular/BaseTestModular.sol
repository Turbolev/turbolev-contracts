// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../../src/SettlementEngine.sol";
import "../../src/oracles/PythOracle.sol";
import "../../src/PriceFeedManager.sol";
import "../../src/interfaces/IPriceFeedManager.sol";
import "../../src/interfaces/oracles/IPyth.sol";

// Modular Vault imports
import "../../src/vault-modular/VaultRouter.sol";
import "../../src/vault-modular/VaultAccessController.sol";
import "../../src/vault-modular/VaultManager.sol" as ModularVM;
import "../../src/vault-modular/modules/VaultCore.sol";
import "../../src/vault-modular/modules/VaultFunding.sol";
import "../../src/vault-modular/modules/VaultRewards.sol";
import "../../src/libraries/vault/VaultStorageLib.sol";
import "../../src/interfaces/IVaultRouter.sol";

// Modular Position imports
import "../../src/position-modular/PositionRouter.sol";
import "../../src/position-modular/modules/PositionCore.sol";

import "../../src/interfaces/IPriceFeedManager.sol";
import "../../src/interfaces/oracles/IBaseOracle.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// ========================================================================
// MOCK CONTRACTS
// ========================================================================

contract MockPyth is IPyth {
    mapping(bytes32 => Price) private _prices;

    function setPrice(bytes32 priceId, int64 price, int32 expo, uint256 publishTime) external {
        _prices[priceId] = Price({ price: price, conf: 0, expo: expo, publishTime: publishTime });
    }

    function getPriceUnsafe(bytes32 id) external view override returns (Price memory) {
        return _prices[id];
    }

    function getPriceNoOlderThan(bytes32 id, uint256 maxAge)
        external
        view
        override
        returns (Price memory)
    {
        Price memory p = _prices[id];
        require(p.publishTime > 0 && (block.timestamp - p.publishTime) <= maxAge, "Price too old");
        return p;
    }

    function getPrice(bytes32 id) external view override returns (Price memory) {
        return _prices[id];
    }

    function getEmaPrice(bytes32 id) external view override returns (Price memory) {
        return _prices[id];
    }

    function updatePriceFeeds(bytes[] calldata) external payable override { }

    function updatePriceFeedsIfNecessary(bytes[] calldata, bytes32[] calldata, uint64[] calldata)
        external
        payable
        override
    { }

    function getUpdateFee(bytes[] calldata) external pure override returns (uint256) {
        return 0;
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
    PythOracle public pythOracle;
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

    // Deployed vault (proxy)
    VaultRouter public vault;

    // Mock contracts
    MockPyth public mockPyth;
    MockERC20 public projectToken;
    MockERC20 public usdc;

    // Pyth price feed ID for projectToken
    bytes32 public projectTokenPriceId;

    // Test accounts
    address public owner;
    address public admin;
    address public user1;
    address public user2;
    address public liquidityProvider;
    address public priceUpdater;
    address public backend;
    address public keeper;
    address public mockTimelockController;
    address public mockEmergencyGuardian;

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
        mockEmergencyGuardian = makeAddr("mockEmergencyGuardian");

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
        // Deploy mock Pyth
        mockPyth = new MockPyth();
        projectTokenPriceId = keccak256("PROJ/USD");

        // Deploy PythOracle (upgradeable via ERC1967Proxy)
        PythOracle pythImpl = new PythOracle();
        bytes memory pythInitData = abi.encodeWithSelector(
            PythOracle.initialize.selector,
            owner,
            address(mockPyth),
            3600 // max price age
        );
        ERC1967Proxy pythProxy = new ERC1967Proxy(address(pythImpl), pythInitData);
        pythOracle = PythOracle(payable(address(pythProxy)));

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

        // Deploy PositionRouter implementation
        positionRouterImpl = new PositionRouter();

        // Deploy PositionRouter proxy with initialization
        bytes memory positionInitData = abi.encodeWithSelector(
            PositionRouter.initialize.selector,
            address(vaultAccessController), // accessController
            address(settlementEngine), // settlementEngine
            address(vaultManager), // vaultManager
            address(priceFeedManager), // priceFeedManager
            address(positionCoreModule) // coreModule
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
            address(vaultRewardsModule)
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
            address(0) // no multisig in tests
        );

        // Grant roles for testing
        vm.startPrank(mockTimelockController);
        vaultAccessController.grantRole(vaultAccessController.POSITION_KEEPER_ROLE(), admin);
        vaultAccessController.grantRole(
            vaultAccessController.EMERGENCY_ROLE(), mockEmergencyGuardian
        );
        vaultAccessController.grantRole(
            vaultAccessController.GUARDIAN_ROLE(), mockEmergencyGuardian
        );
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
        // Set initial price in mock Pyth (100 USD, expo -8)
        mockPyth.setPrice(projectTokenPriceId, 100e8, -8, block.timestamp);

        // Configure PythOracle: map projectToken -> priceId
        pythOracle.setPriceFeedId(address(projectToken), projectTokenPriceId);

        // Configure PriceFeedManager with Pyth provider
        IPriceFeedManager.OracleProvider memory pythProvider = IPriceFeedManager.OracleProvider({
            oracleContract: address(pythOracle),
            oracleType: IBaseOracle.OracleType.PULL,
            enabled: true
        });
        priceFeedManager.registerOracleProvider(priceFeedManager.PYTH_PROVIDER(), pythProvider);

        // Configure token with Pyth as primary provider
        // Use setPriceFeedConfigWithInit to initialize circuit breaker baseline price
        IPriceFeedManager.PriceFeedConfig memory config = IPriceFeedManager.PriceFeedConfig({
            primaryProviderId: priceFeedManager.PYTH_PROVIDER(),
            secondaryProviderId: bytes32(0),
            primaryFeed: address(projectToken),
            secondaryFeed: address(0),
            usePullMode: false
        });
        priceFeedManager.setPriceFeedConfigWithInit(address(projectToken), config, "", 3600);
    }

    function _createVault() internal {
        vm.startPrank(owner);
        address vaultAddress = vaultManager.createVault(
            address(projectToken),
            address(projectToken),
            DEFAULT_MIN_BET,
            DEFAULT_MAX_BET,
            DEFAULT_GRADUATION_THRESHOLD
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

    function _setHighLeverageConfig() internal {
        vm.prank(address(vaultManager));
        vault.setMaxLeverage(50);
    }

    /**
     * @notice Refresh mock price to current block.timestamp.
     * @dev Must be called after vm.warp() to satisfy PriceFeedManager circuit breaker
     *      (maxDeviationBps = 1000 = 10%, minDeviationWindow = 60s).
     *      Without this, getPriceChecked() reverts with OracleFetchFailed after any warp.
     * @param price Price to set (e.g. 100e8 for $100 with expo -8)
     */
    function _refreshPrice(int64 price) internal {
        mockPyth.setPrice(projectTokenPriceId, price, -8, block.timestamp);
    }

    /// @notice Refresh price at $100 (default price used in setUp)
    function _refreshPrice() internal {
        _refreshPrice(100e8);
    }
}
