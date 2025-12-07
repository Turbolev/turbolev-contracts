# Interact Scripts

Các script tương tác với hệ thống Boolean đã deploy.

## Cách sử dụng

### 1. InteractAssetVault

Tương tác với một vault cụ thể (user functions, admin functions và view functions):

```bash
# Set vault address
export VAULT_ADDRESS=0x...

# ========== VIEW FUNCTIONS ==========

# View all configurations
forge script script/interact/InteractAssetVault.s.sol:InteractAssetVault \
  --sig "viewAllConfigs()" \
  --rpc-url $RPC_URL

# View vault info
forge script script/interact/InteractAssetVault.s.sol:InteractAssetVault \
  --sig "viewVaultInfo()" \
  --rpc-url $RPC_URL

# View risk controls
forge script script/interact/InteractAssetVault.s.sol:InteractAssetVault \
  --sig "viewRiskControls()" \
  --rpc-url $RPC_URL

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

# View leverage configuration
forge script script/interact/InteractAssetVault.s.sol:InteractAssetVault \
  --sig "viewLeverageConfig()" \
  --rpc-url $RPC_URL

# View total OI configuration
forge script script/interact/InteractAssetVault.s.sol:InteractAssetVault \
  --sig "viewTotalOIConfig()" \
  --rpc-url $RPC_URL

# ========== USER FUNCTIONS (LP) ==========

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

# ========== ADMIN FUNCTIONS (require admin rights) ==========

# Set fees (feeType: 0=staking, 1=earlyWithdrawal, 2=openPosition, 3=closePosition)
forge script script/interact/InteractAssetVault.s.sol:InteractAssetVault \
  --sig "setFee(uint8,uint16)" 0 50 \
  --rpc-url $RPC_URL --broadcast

# Set leverage tier config (thresholds in wei, max leverage values)
forge script script/interact/InteractAssetVault.s.sol:InteractAssetVault \
  --sig "setLeverageTierConfig(uint256,uint256,uint16,uint16,uint16)" \
  100000000000000000000000 500000000000000000000000 100 200 500 \
  --rpc-url $RPC_URL --broadcast

# Setup standard leverage tiers (100K/500K thresholds, 100x/200x/500x)
forge script script/interact/InteractAssetVault.s.sol:InteractAssetVault \
  --sig "setupStandardLeverageTiers()" \
  --rpc-url $RPC_URL --broadcast

# Set funding config (5 tier rates in bps)
forge script script/interact/InteractAssetVault.s.sol:InteractAssetVault \
  --sig "setFundingConfig(uint16,uint16,uint16,uint16,uint16)" 1 3 5 8 10 \
  --rpc-url $RPC_URL --broadcast

# Set funding enabled/disabled
forge script script/interact/InteractAssetVault.s.sol:InteractAssetVault \
  --sig "setFundingEnabled(bool)" true \
  --rpc-url $RPC_URL --broadcast

# Update hourly funding (permissionless)
forge script script/interact/InteractAssetVault.s.sol:InteractAssetVault \
  --sig "updateHourlyFunding()" \
  --rpc-url $RPC_URL --broadcast

# Set max directional exposure
forge script script/interact/InteractAssetVault.s.sol:InteractAssetVault \
  --sig "setMaxDirectionalExposure(uint16)" 5000 \
  --rpc-url $RPC_URL --broadcast

# Set trading enabled/disabled
forge script script/interact/InteractAssetVault.s.sol:InteractAssetVault \
  --sig "setTradingEnabled(bool)" true \
  --rpc-url $RPC_URL --broadcast

# Set graduation threshold
forge script script/interact/InteractAssetVault.s.sol:InteractAssetVault \
  --sig "setGraduationThreshold(uint256)" 1000000000000000000000 \
  --rpc-url $RPC_URL --broadcast

# Pause/Unpause vault
forge script script/interact/InteractAssetVault.s.sol:InteractAssetVault \
  --sig "pauseVault()" \
  --rpc-url $RPC_URL --broadcast

forge script script/interact/InteractAssetVault.s.sol:InteractAssetVault \
  --sig "unpauseVault()" \
  --rpc-url $RPC_URL --broadcast

# Add/Remove admin
forge script script/interact/InteractAssetVault.s.sol:InteractAssetVault \
  --sig "addAdmin(address)" 0xAdminAddress \
  --rpc-url $RPC_URL --broadcast

# Set treasury
forge script script/interact/InteractAssetVault.s.sol:InteractAssetVault \
  --sig "setTreasury(address)" 0xTreasuryAddress \
  --rpc-url $RPC_URL --broadcast

# Withdraw fees
forge script script/interact/InteractAssetVault.s.sol:InteractAssetVault \
  --sig "withdrawFees(uint256)" 0 \
  --rpc-url $RPC_URL --broadcast
```

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

### 6. InteractVaultViewer

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

### 7. InteractMultisigWallet

Quản lý MultisigWallet (M-of-N multisig):

```bash
export MULTISIG_WALLET_ADDRESS=0x...

# View multisig info
forge script script/interact/InteractMultisigWallet.s.sol:InteractMultisigWallet \
  --sig "viewInfo()" \
  --rpc-url $RPC_URL

# View owners
forge script script/interact/InteractMultisigWallet.s.sol:InteractMultisigWallet \
  --sig "viewOwners()" \
  --rpc-url $RPC_URL

# View transaction
forge script script/interact/InteractMultisigWallet.s.sol:InteractMultisigWallet \
  --sig "viewTransaction(uint256)" 0 \
  --rpc-url $RPC_URL

# View pending transactions
forge script script/interact/InteractMultisigWallet.s.sol:InteractMultisigWallet \
  --sig "viewPendingTransactions()" \
  --rpc-url $RPC_URL

# Submit transaction
forge script script/interact/InteractMultisigWallet.s.sol:InteractMultisigWallet \
  --sig "submitTransaction(address,uint256,bytes)" 0xTarget 0 0x \
  --rpc-url $RPC_URL --broadcast

# Confirm transaction
forge script script/interact/InteractMultisigWallet.s.sol:InteractMultisigWallet \
  --sig "confirmTransaction(uint256)" 0 \
  --rpc-url $RPC_URL --broadcast

# Execute transaction
forge script script/interact/InteractMultisigWallet.s.sol:InteractMultisigWallet \
  --sig "executeTransaction(uint256)" 0 \
  --rpc-url $RPC_URL --broadcast

# Propose add owner (requires multisig approval)
forge script script/interact/InteractMultisigWallet.s.sol:InteractMultisigWallet \
  --sig "proposeAddOwner(address)" 0xNewOwner \
  --rpc-url $RPC_URL --broadcast
```

### 8. InteractVersionedBeacon

Quản lý VersionedBeacon (vault upgrade management):

```bash
export VAULT_BEACON_ADDRESS=0x...

# View beacon info
forge script script/interact/InteractVersionedBeacon.s.sol:InteractVersionedBeacon \
  --sig "viewInfo()" \
  --rpc-url $RPC_URL

# View current version details
forge script script/interact/InteractVersionedBeacon.s.sol:InteractVersionedBeacon \
  --sig "viewCurrentVersionInfo()" \
  --rpc-url $RPC_URL

# View all versions
forge script script/interact/InteractVersionedBeacon.s.sol:InteractVersionedBeacon \
  --sig "viewAllVersions()" \
  --rpc-url $RPC_URL

# View version history (from version 1 to 5)
forge script script/interact/InteractVersionedBeacon.s.sol:InteractVersionedBeacon \
  --sig "viewVersionHistory(uint256,uint256)" 1 5 \
  --rpc-url $RPC_URL

# Check specific version
forge script script/interact/InteractVersionedBeacon.s.sol:InteractVersionedBeacon \
  --sig "checkVersion(uint256)" 1 \
  --rpc-url $RPC_URL

# Upgrade to new version (owner only - should be Timelock)
forge script script/interact/InteractVersionedBeacon.s.sol:InteractVersionedBeacon \
  --sig "upgradeToVersion(address,bytes32)" 0xNewImpl 0x0 \
  --rpc-url $RPC_URL --broadcast

# Rollback to previous version (owner only)
forge script script/interact/InteractVersionedBeacon.s.sol:InteractVersionedBeacon \
  --sig "rollbackTo(uint256)" 1 \
  --rpc-url $RPC_URL --broadcast
```

### 9. InteractVaultGovernor

Quản lý VaultGovernor (vault-specific governance):

```bash
export VAULT_GOVERNOR_ADDRESS=0x...

# View governor info
forge script script/interact/InteractVaultGovernor.s.sol:InteractVaultGovernor \
  --sig "viewInfo()" \
  --rpc-url $RPC_URL

# View roles
forge script script/interact/InteractVaultGovernor.s.sol:InteractVaultGovernor \
  --sig "viewRoles()" \
  --rpc-url $RPC_URL

# Check roles for address
forge script script/interact/InteractVaultGovernor.s.sol:InteractVaultGovernor \
  --sig "checkRole(address)" 0xYourAddress \
  --rpc-url $RPC_URL

# Propose pause vault via governance
forge script script/interact/InteractVaultGovernor.s.sol:InteractVaultGovernor \
  --sig "proposePauseVault(address,bytes32)" 0xProjectToken 0x0 \
  --rpc-url $RPC_URL --broadcast

# Emergency pause by vault address (Guardian only, no timelock)
forge script script/interact/InteractVaultGovernor.s.sol:InteractVaultGovernor \
  --sig "emergencyPauseVaultByAddress(address)" 0xVaultAddress \
  --rpc-url $RPC_URL --broadcast

# Emergency pause by project token (Guardian only, no timelock)
forge script script/interact/InteractVaultGovernor.s.sol:InteractVaultGovernor \
  --sig "emergencyPauseVault(address)" 0xProjectToken \
  --rpc-url $RPC_URL --broadcast

# Propose beacon upgrade
forge script script/interact/InteractVaultGovernor.s.sol:InteractVaultGovernor \
  --sig "proposeBeaconUpgrade(address,bytes32,bytes32)" 0xNewImpl 0x0 0x0 \
  --rpc-url $RPC_URL --broadcast

# Add guardian
forge script script/interact/InteractVaultGovernor.s.sol:InteractVaultGovernor \
  --sig "addGuardian(address)" 0xGuardianAddress \
  --rpc-url $RPC_URL --broadcast
```

## Environment Variables

Cần thiết lập trong `.env`:

```bash
# Private key
PRIVATE_KEY=0x...

# RPC URL
RPC_URL=https://...

# Deployed addresses (từ DeployAll)
POSITION_MANAGER_ADDRESS=0x...
VAULT_MANAGER_ADDRESS=0x...
SETTLEMENT_ENGINE_ADDRESS=0x...
PRICE_FEED_MANAGER_ADDRESS=0x...

# Vault specific
VAULT_ADDRESS=0x...

# Helper contracts
VAULT_VIEWER_ADDRESS=0x...

# Governance contracts
MULTISIG_WALLET_ADDRESS=0x...
TIMELOCK_ADDRESS=0x...
VAULT_BEACON_ADDRESS=0x...
VAULT_GOVERNOR_ADDRESS=0x...
```

## Lưu ý

1. **Admin Functions**: 
   - Admin functions được gọi trực tiếp qua `InteractAssetVault` (xem phần 1)
   - Tất cả admin functions cần quyền admin/owner và flag `--broadcast`
   - Các functions như `setMaxDirectionalExposure`, `pauseVault`, `setLeverageTierConfig` đều ở trong `InteractAssetVault`

2. **User Functions**: 
   - User functions: `addLiquidity`, `removeLiquidity`, `claimRewards`
   - User functions cần `--broadcast` nhưng không cần quyền admin

3. **Gas**: Đảm bảo có đủ native token để trả gas

4. **Collateral**: Khi open position, collateral sẽ được chuyển từ ví

5. **Risk Controls**: Kiểm tra risk parameters trước khi thực hiện trade lớn
