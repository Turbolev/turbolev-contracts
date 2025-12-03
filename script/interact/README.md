# Interact Scripts

Các script tương tác với hệ thống Boolean đã deploy.

## Cách sử dụng

### 1. InteractAssetVault

Tương tác với một vault cụ thể (user functions và view functions):

```bash
# Set vault address
export VAULT_ADDRESS=0x...

# View vault info
forge script script/interact/InteractAssetVault.s.sol:InteractAssetVault \
  --sig "viewVaultInfo()" \
  --rpc-url $RPC_URL

# View risk controls
forge script script/interact/InteractAssetVault.s.sol:InteractAssetVault \
  --sig "viewRiskControls()" \
  --rpc-url $RPC_URL

# Add liquidity
forge script script/interact/InteractAssetVault.s.sol:InteractAssetVault \
  --sig "addLiquidity(uint256)" 1000000000000000000 \
  --rpc-url $RPC_URL --broadcast

# Remove liquidity
forge script script/interact/InteractAssetVault.s.sol:InteractAssetVault \
  --sig "removeLiquidity()" \
  --rpc-url $RPC_URL --broadcast

# Claim rewards
forge script script/interact/InteractAssetVault.s.sol:InteractAssetVault \
  --sig "claimRewards()" \
  --rpc-url $RPC_URL --broadcast

# View LP position
forge script script/interact/InteractAssetVault.s.sol:InteractAssetVault \
  --sig "viewLPPosition(address)" 0xYourAddress \
  --rpc-url $RPC_URL

# View fee configuration
forge script script/interact/InteractAssetVault.s.sol:InteractAssetVault \
  --sig "viewFeeConfig()" \
  --rpc-url $RPC_URL

# View funding status
forge script script/interact/InteractAssetVault.s.sol:InteractAssetVault \
  --sig "viewFundingStatus()" \
  --rpc-url $RPC_URL
```

**Lưu ý:** Các admin functions (setMaxDirectionalExposure, setLeverageTierMaxValues, pauseVault, etc.) đã được chuyển sang `InteractVaultAdminConfig`. Xem phần 6 bên dưới.

### 2. InteractPositionManager

Tương tác với hệ thống trading:

```bash
# Load deployed addresses
source .env

# View position
forge script script/interact/InteractPositionManager.s.sol:InteractPositionManager \
  --sig "viewPosition(bytes32)" 0xPositionId \
  --rpc-url $RPC_URL

# View trader positions
forge script script/interact/InteractPositionManager.s.sol:InteractPositionManager \
  --sig "viewTraderPositions(address)" 0xTraderAddress \
  --rpc-url $RPC_URL

# Open position (vault, size, isLong, collateral, leverage)
forge script script/interact/InteractPositionManager.s.sol:InteractPositionManager \
  --sig "openPosition(address,uint256,bool,uint256,uint16)" \
  0xVaultAddress 1000000000000000000 true 100000000000000000 10 \
  --rpc-url $RPC_URL --broadcast

# Close position
forge script script/interact/InteractPositionManager.s.sol:InteractPositionManager \
  --sig "closePosition(bytes32)" 0xPositionId \
  --rpc-url $RPC_URL --broadcast
```

### 3. InteractVaultManager

Quản lý vaults:

```bash
# View all vaults
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "viewAllVaults()" \
  --rpc-url $RPC_URL

# View vault state
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "viewVaultState(address)" 0xVaultAddress \
  --rpc-url $RPC_URL

# Set risk parameters (admin only)
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "setVaultMaxDirectionalExposure(address,uint16)" 0xVaultAddress 5000 \
  --rpc-url $RPC_URL --broadcast

# Set leverage tiers (admin only)
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "setVaultLeverageTierMaxValues(address,uint16,uint16,uint16)" \
  0xVaultAddress 100 50 20 \
  --rpc-url $RPC_URL --broadcast
```

### 4. InteractPriceFeedManager

Quản lý oracle feeds:

```bash
# View oracle config
forge script script/interact/InteractPriceFeedManager.s.sol:InteractPriceFeedManager \
  --sig "viewOracleConfig(address)" 0xTokenAddress \
  --rpc-url $RPC_URL

# Get price
forge script script/interact/InteractPriceFeedManager.s.sol:InteractPriceFeedManager \
  --sig "viewPrice(address)" 0xTokenAddress \
  --rpc-url $RPC_URL

# Set Chainlink feed (admin only)
forge script script/interact/InteractPriceFeedManager.s.sol:InteractPriceFeedManager \
  --sig "setChainlinkFeed(address,address,uint256)" \
  0xTokenAddress 0xChainlinkFeed 3600 \
  --rpc-url $RPC_URL --broadcast
```

### 5. InteractSettlementEngine

Quản lý settlements:

```bash
# View pending payouts
forge script script/interact/InteractSettlementEngine.s.sol:InteractSettlementEngine \
  --sig "viewPendingPayouts()" \
  --rpc-url $RPC_URL

# Process payout (admin only)
forge script script/interact/InteractSettlementEngine.s.sol:InteractSettlementEngine \
  --sig "processPendingPayout(bytes32)" 0xPayoutId \
  --rpc-url $RPC_URL --broadcast
```

### 6. InteractVaultAdminConfig

Quản lý cấu hình admin cho vault (cần quyền admin, cần broadcast):

```bash
# Set vault address
export VAULT_ADDRESS=0x...

# View all configurations
forge script script/interact/InteractVaultAdminConfig.s.sol:InteractVaultAdminConfig \
  --sig "viewAllConfigs()" \
  --rpc-url $RPC_URL

# Set fees
forge script script/interact/InteractVaultAdminConfig.s.sol:InteractVaultAdminConfig \
  --sig "setStakingFeeBps(uint16)" 50 \
  --rpc-url $RPC_URL --broadcast

forge script script/interact/InteractVaultAdminConfig.s.sol:InteractVaultAdminConfig \
  --sig "setOpenPositionFeeBps(uint16)" 5 \
  --rpc-url $RPC_URL --broadcast

# Set total OI configuration
forge script script/interact/InteractVaultAdminConfig.s.sol:InteractVaultAdminConfig \
  --sig "setTotalOIRiskMultiplier(uint16)" 20000 \
  --rpc-url $RPC_URL --broadcast

# Set leverage tiers
forge script script/interact/InteractVaultAdminConfig.s.sol:InteractVaultAdminConfig \
  --sig "setLeverageTierMaxValues(uint16,uint16,uint16)" 100 200 500 \
  --rpc-url $RPC_URL --broadcast

# Setup standard leverage tiers
forge script script/interact/InteractVaultAdminConfig.s.sol:InteractVaultAdminConfig \
  --sig "setupStandardLeverageTiers()" \
  --rpc-url $RPC_URL --broadcast

# Set funding configuration
forge script script/interact/InteractVaultAdminConfig.s.sol:InteractVaultAdminConfig \
  --sig "setFundingConfig(uint16,uint16,uint16,uint16,uint16)" 1 3 5 8 10 \
  --rpc-url $RPC_URL --broadcast

# Set max directional exposure
forge script script/interact/InteractVaultAdminConfig.s.sol:InteractVaultAdminConfig \
  --sig "setMaxDirectionalExposure(uint16)" 5000 \
  --rpc-url $RPC_URL --broadcast

# Enable/disable trading
forge script script/interact/InteractVaultAdminConfig.s.sol:InteractVaultAdminConfig \
  --sig "setTradingEnabled(bool)" true \
  --rpc-url $RPC_URL --broadcast

# Enable/disable funding
forge script script/interact/InteractVaultAdminConfig.s.sol:InteractVaultAdminConfig \
  --sig "setFundingEnabled(bool)" true \
  --rpc-url $RPC_URL --broadcast

# Update hourly funding rate
forge script script/interact/InteractVaultAdminConfig.s.sol:InteractVaultAdminConfig \
  --sig "updateHourlyFunding()" \
  --rpc-url $RPC_URL --broadcast

# Pause/Unpause vault
forge script script/interact/InteractVaultAdminConfig.s.sol:InteractVaultAdminConfig \
  --sig "pauseVault()" \
  --rpc-url $RPC_URL --broadcast

forge script script/interact/InteractVaultAdminConfig.s.sol:InteractVaultAdminConfig \
  --sig "unpauseVault()" \
  --rpc-url $RPC_URL --broadcast

# View all configurations
forge script script/interact/InteractVaultAdminConfig.s.sol:InteractVaultAdminConfig \
  --sig "viewAllConfigs()" \
  --rpc-url $RPC_URL
```

### 7. InteractVaultViewer

Truy vấn thông tin vault chi tiết thông qua VaultViewer contract (view-only, không cần broadcast):

```bash
# Set vault viewer and vault addresses
export VAULT_VIEWER_ADDRESS=0x...
export VAULT_ADDRESS=0x...

# View comprehensive metrics
forge script script/interact/InteractVaultViewer.s.sol:InteractVaultViewer \
  --sig "viewAllMetrics()" \
  --rpc-url $RPC_URL

# View risk summary
forge script script/interact/InteractVaultViewer.s.sol:InteractVaultViewer \
  --sig "viewRiskSummary()" \
  --rpc-url $RPC_URL

# View total OI breakdown
forge script script/interact/InteractVaultViewer.s.sol:InteractVaultViewer \
  --sig "viewTotalOIBreakdown()" \
  --rpc-url $RPC_URL

# View effective max leverage
forge script script/interact/InteractVaultViewer.s.sol:InteractVaultViewer \
  --sig "viewEffectiveMaxLeverage()" \
  --rpc-url $RPC_URL

# Check if leverage is allowed
forge script script/interact/InteractVaultViewer.s.sol:InteractVaultViewer \
  --sig "checkLeverageAllowed(uint16)" 100 \
  --rpc-url $RPC_URL

# View directional exposure
forge script script/interact/InteractVaultViewer.s.sol:InteractVaultViewer \
  --sig "viewDirectionalExposure()" \
  --rpc-url $RPC_URL

# View funding stats
forge script script/interact/InteractVaultViewer.s.sol:InteractVaultViewer \
  --sig "viewFundingStats()" \
  --rpc-url $RPC_URL

# Check total OI cap for a position
forge script script/interact/InteractVaultViewer.s.sol:InteractVaultViewer \
  --sig "checkTotalOICap(uint256)" 1000000000000000000 \
  --rpc-url $RPC_URL

# Simulate leverage at different TVL
forge script script/interact/InteractVaultViewer.s.sol:InteractVaultViewer \
  --sig "simulateLeverageAtTVL(uint256)" 500000000000000000000 \
  --rpc-url $RPC_URL

# Calculate withdrawal amount for LP
forge script script/interact/InteractVaultViewer.s.sol:InteractVaultViewer \
  --sig "calculateWithdrawalAmount(address,uint256)" 0xUserAddress 1000000000000000000 \
  --rpc-url $RPC_URL

# Calculate pending rewards for LP
forge script script/interact/InteractVaultViewer.s.sol:InteractVaultViewer \
  --sig "calculatePendingRewards(address)" 0xUserAddress \
  --rpc-url $RPC_URL
```

## Environment Variables

Cần thiết lập trong `.env`:

```bash
# Private key
PRIVATE_KEY=0x...

# RPC URL
RPC_URL=https://...

# Deployed addresses (từ DeployAll)
POSITION_MANAGER_PROXY=0x...
VAULT_MANAGER_PROXY=0x...
SETTLEMENT_ENGINE_PROXY=0x...
PRICE_FEED_MANAGER_PROXY=0x...

# Vault specific
VAULT_ADDRESS=0x...

# VaultViewer (optional, for InteractVaultViewer)
VAULT_VIEWER_ADDRESS=0x...
```

## Lưu ý

1. **Admin Functions**: 
   - Các admin functions đã được tập trung trong `InteractVaultAdminConfig` (xem phần 6)
   - Tất cả admin functions cần quyền admin và flag `--broadcast`
   - Các functions như `setMaxDirectionalExposure`, `pauseVault`, `setLeverageTierMaxValues` đều ở trong `InteractVaultAdminConfig`

2. **User Functions**: 
   - `InteractAssetVault` chỉ chứa user functions (addLiquidity, removeLiquidity, claimRewards) và view functions
   - User functions cần `--broadcast` nhưng không cần quyền admin

3. **Gas**: Đảm bảo có đủ native token để trả gas

4. **Collateral**: Khi open position, collateral sẽ được chuyển từ ví

5. **Risk Controls**: Kiểm tra risk parameters trước khi thực hiện trade lớn
