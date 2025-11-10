# Interact Scripts

Collection of scripts to interact with deployed Boolean Contracts.

## Setup

1. Deploy contracts first using deployment scripts in `script/` folder
2. Update `.env` file with deployed contract addresses:
   ```bash
   ORACLE_ADDRESS=0x...
   SETTLEMENT_ENGINE_ADDRESS=0x...
   POSITION_MANAGER_ADDRESS=0x...
   VAULT_MANAGER_ADDRESS=0x...
   VAULT_MANAGER_HELPER_ADDRESS=0x...  # For InteractVaultManagerHelper
   VAULT_ADDRESS=0x...  # For InteractAssetVault
   ```

## Usage

All scripts follow the same pattern:

```bash
forge script script/interact/<ScriptName>.s.sol:<ContractName> \
  --sig "<functionName>(<params>)" <args> \
  --rpc-url $RPC_URL \
  --broadcast \
  -vvvv
```

### View Functions (No Broadcast Needed)

View functions don't modify state, so you can omit `--broadcast`:

```bash
forge script script/interact/<ScriptName>.s.sol:<ContractName> \
  --sig "<functionName>(<params>)" <args> \
  --rpc-url $RPC_URL \
  -vvvv
```

## Scripts Overview

1. **InteractBlocksenseOracle.s.sol** - Oracle management and price queries
2. **InteractSettlementEngine.s.sol** - Settlement configuration and payout calculations
3. **InteractPositionManager.s.sol** - Position management (open/close/add margin)
4. **InteractVaultManager.s.sol** - VaultManager and individual vault operations (LP + Admin)
5. **InteractVaultManagerHelper.s.sol** - VaultManagerHelper view functions and admin proxies
6. **InteractAssetVault.s.sol** - Direct interaction with specific AssetVault
7. **InteractPendingClose.s.sol** - Pending close position management (Admin cron tasks)

---

### 1. InteractBlocksenseOracle.s.sol

Interact with BlocksenseOracle contract.

**View Functions:**
```bash
# View oracle configuration
forge script script/interact/InteractBlocksenseOracle.s.sol:InteractBlocksenseOracle \
  --sig "viewConfig()" \
  --rpc-url $RPC_URL

# Get price for base/quote pair
forge script script/interact/InteractBlocksenseOracle.s.sol:InteractBlocksenseOracle \
  --sig "getPrice(address,address)" 0xBASE 0xQUOTE \
  --rpc-url $RPC_URL
```

**Admin Functions:**
```bash
# Set max price age
forge script script/interact/InteractBlocksenseOracle.s.sol:InteractBlocksenseOracle \
  --sig "setMaxPriceAge(uint256)" 7200 \
  --rpc-url $RPC_URL \
  --broadcast

# Pause oracle
forge script script/interact/InteractBlocksenseOracle.s.sol:InteractBlocksenseOracle \
  --sig "pauseOracle()" \
  --rpc-url $RPC_URL \
  --broadcast
```

### 2. InteractSettlementEngine.s.sol

Interact with SettlementEngine contract.

**View Functions:**
```bash
# View settlement configuration
forge script script/interact/InteractSettlementEngine.s.sol:InteractSettlementEngine \
  --sig "viewConfig()" \
  --rpc-url $RPC_URL

# Calculate potential payout
forge script script/interact/InteractSettlementEngine.s.sol:InteractSettlementEngine \
  --sig "calculatePotentialPayout(uint256)" 1000000000000000000 \
  --rpc-url $RPC_URL
```

**Admin Functions:**
```bash
# Update config
forge script script/interact/InteractSettlementEngine.s.sol:InteractSettlementEngine \
  --sig "updateConfig(uint16,uint16,uint256,uint256)" 200 30000 1000000000000000 1000000000000000000000 \
  --rpc-url $RPC_URL \
  --broadcast

# Set max profit cap BPS
forge script script/interact/InteractSettlementEngine.s.sol:InteractSettlementEngine \
  --sig "setMaxProfitCapBps(uint16)" 200 \
  --rpc-url $RPC_URL \
  --broadcast
```

### 3. InteractPositionManager.s.sol

Interact with PositionManager contract.

**View Functions:**
```bash
# View configuration
forge script script/interact/InteractPositionManager.s.sol:InteractPositionManager \
  --sig "viewConfig()" \
  --rpc-url $RPC_URL

# Get position details
forge script script/interact/InteractPositionManager.s.sol:InteractPositionManager \
  --sig "getPosition(uint64)" 1 \
  --rpc-url $RPC_URL

# Check if position can be closed
forge script script/interact/InteractPositionManager.s.sol:InteractPositionManager \
  --sig "canClosePosition(uint64)" 1 \
  --rpc-url $RPC_URL
```

**User Functions:**
```bash
# Open position (LONG = 1, SHORT = 2)
# Make sure to approve tokens first!
forge script script/interact/InteractPositionManager.s.sol:InteractPositionManager \
  --sig "openPosition(address,uint256,uint8,uint8,uint256)" \
  0xPROJECT_TOKEN 1000000000000000000 10 1 0 \
  --rpc-url $RPC_URL \
  --broadcast

# Close position
forge script script/interact/InteractPositionManager.s.sol:InteractPositionManager \
  --sig "closePosition(uint64,uint256)" 1 1234567890 \
  --rpc-url $RPC_URL \
  --broadcast

# Add margin to position
forge script script/interact/InteractPositionManager.s.sol:InteractPositionManager \
  --sig "addMargin(uint64,uint256)" 1 500000000000000000 \
  --rpc-url $RPC_URL \
  --broadcast
```

**Admin Functions:**
```bash
# Set leverage limits
forge script script/interact/InteractPositionManager.s.sol:InteractPositionManager \
  --sig "setLeverageLimits(uint8,uint8)" 1 100 \
  --rpc-url $RPC_URL \
  --broadcast

# Add admin address
forge script script/interact/InteractPositionManager.s.sol:InteractPositionManager \
  --sig "addAdmin(address)" 0xADMIN \
  --rpc-url $RPC_URL \
  --broadcast
```

### 4. InteractVaultManager.s.sol

Interact with VaultManager contract and individual vaults. 


#### VaultManager View Functions:
```bash
# View configuration
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "viewConfig()" \
  --rpc-url $RPC_URL

# Get all vaults
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "getAllVaults()" \
  --rpc-url $RPC_URL

# Get vault for project token
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "getVault(address)" 0xPROJECT_TOKEN \
  --rpc-url $RPC_URL

# Check if vault is supported
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "isVaultSupported(address)" 0xPROJECT_TOKEN \
  --rpc-url $RPC_URL

# Check if vault is graduated
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "isVaultGraduated(address)" 0xVAULT \
  --rpc-url $RPC_URL

# Check position risk
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "checkPositionRisk(address,uint256,uint8)" 0xPROJECT_TOKEN 1000000000000000000 10 \
  --rpc-url $RPC_URL
```

#### Vault LP Functions (Liquidity Provider):
```bash
# Get LP position for user
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "getLPPosition(address,address)" 0xPROJECT_TOKEN 0xUSER \
  --rpc-url $RPC_URL

# Add liquidity to vault (approve tokens first!)
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "addLiquidity(address,uint256)" 0xPROJECT_TOKEN 1000000000000000000 \
  --rpc-url $RPC_URL \
  --broadcast

# Remove liquidity from vault
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "removeLiquidity(address,uint256)" 0xPROJECT_TOKEN 1000000000000000000 \
  --rpc-url $RPC_URL \
  --broadcast

# Claim rewards
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "claimRewards(address)" 0xPROJECT_TOKEN \
  --rpc-url $RPC_URL \
  --broadcast

# Calculate withdrawal amount (with fee)
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "calculateWithdrawalAmount(address,address,uint256)" 0xPROJECT_TOKEN 0xUSER 1000000000000000000 \
  --rpc-url $RPC_URL

# Get remaining lock time
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "getRemainingLockTime(address,address)" 0xPROJECT_TOKEN 0xUSER \
  --rpc-url $RPC_URL
```

#### Vault Info View Functions:
```bash
# Get complete vault info
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "getVaultInfo(address)" 0xPROJECT_TOKEN \
  --rpc-url $RPC_URL

# Get vault parameters (risk settings)
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "getVaultParams(address)" 0xPROJECT_TOKEN \
  --rpc-url $RPC_URL

# Get fee configuration
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "getFeeConfig(address)" 0xPROJECT_TOKEN \
  --rpc-url $RPC_URL

# Get all LPs in vault
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "getAllLPs(address)" 0xPROJECT_TOKEN \
  --rpc-url $RPC_URL

# Get pending payout queue
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "getPendingPayoutQueue(address)" 0xPROJECT_TOKEN \
  --rpc-url $RPC_URL

# Get daily snapshot
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "getDailySnapshot(address,uint256)" 0xPROJECT_TOKEN 19800 \
  --rpc-url $RPC_URL
```

#### Vault Maintenance Functions:
```bash
# Process pending payouts manually
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "processPendingPayouts(address)" 0xPROJECT_TOKEN \
  --rpc-url $RPC_URL \
  --broadcast

# Check graduation status
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "checkGraduation(address)" 0xPROJECT_TOKEN \
  --rpc-url $RPC_URL \
  --broadcast
```

#### VaultManager Admin Functions:
```bash
# Create vault
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "createVault(address,address,address,uint256,uint256,uint256)" \
  0xPROJECT_TOKEN 0xBASE 1000000000000000 1000000000000000000000 10000000000000000000000 \
  --rpc-url $RPC_URL \
  --broadcast

# Set position manager
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "setPositionManager(address)" 0xNEW_POSITION_MANAGER \
  --rpc-url $RPC_URL \
  --broadcast

# Set settlement engine
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "setSettlementEngine(address)" 0xNEW_SETTLEMENT_ENGINE \
  --rpc-url $RPC_URL \
  --broadcast

# Pause/unpause vault manager
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "pauseVaultManager()" \
  --rpc-url $RPC_URL \
  --broadcast
```

#### Vault-Specific Admin Functions:
```bash
# Pause specific vault
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "pauseVault(address)" 0xPROJECT_TOKEN \
  --rpc-url $RPC_URL \
  --broadcast

# Unpause specific vault
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "unpauseVault(address)" 0xPROJECT_TOKEN \
  --rpc-url $RPC_URL \
  --broadcast

# Enable/disable trading
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "setTradingEnabled(address,bool)" 0xPROJECT_TOKEN true \
  --rpc-url $RPC_URL \
  --broadcast

# Update vault parameters
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "updateVaultParams(address,uint16,uint16,uint16,uint256,uint256,uint16,uint16)" \
  0xPROJECT_TOKEN 500 1000 8000 1000000000000000 1000000000000000000000 10000 200 \
  --rpc-url $RPC_URL \
  --broadcast

# Set graduation threshold
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "setGraduationThreshold(address,uint256)" 0xPROJECT_TOKEN 10000000000000000000000 \
  --rpc-url $RPC_URL \
  --broadcast

# Add admin bot
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "addAdmin(address,address)" 0xPROJECT_TOKEN 0xADMIN \
  --rpc-url $RPC_URL \
  --broadcast

# Set Blocksense Oracle
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "setBlocksenseOracle(address,address)" 0xPROJECT_TOKEN 0xORACLE \
  --rpc-url $RPC_URL \
  --broadcast
```

### 5. InteractVaultManagerHelper.s.sol

Interact with VaultManagerHelper contract for view and admin proxy functions.

**Important:** Set `VAULT_MANAGER_HELPER_ADDRESS` in `.env` before using this script.

#### View Functions:
```bash
# Get vault address for a project token
forge script script/interact/InteractVaultManagerHelper.s.sol:InteractVaultManagerHelper \
  --sig "getVault(address)" 0xPROJECT_TOKEN \
  --rpc-url $RPC_URL

# Get all vaults
forge script script/interact/InteractVaultManagerHelper.s.sol:InteractVaultManagerHelper \
  --sig "getAllVaults()" \
  --rpc-url $RPC_URL

# Get vault info
forge script script/interact/InteractVaultManagerHelper.s.sol:InteractVaultManagerHelper \
  --sig "getVaultInfo(address)" 0xTOKEN_ADDRESS \
  --rpc-url $RPC_URL

# Get vault parameters
forge script script/interact/InteractVaultManagerHelper.s.sol:InteractVaultManagerHelper \
  --sig "getVaultParams(address)" 0xTOKEN_ADDRESS \
  --rpc-url $RPC_URL

# Check if vault is supported
forge script script/interact/InteractVaultManagerHelper.s.sol:InteractVaultManagerHelper \
  --sig "isVaultSupported(address)" 0xPROJECT_TOKEN \
  --rpc-url $RPC_URL

# Get LP position for user
forge script script/interact/InteractVaultManagerHelper.s.sol:InteractVaultManagerHelper \
  --sig "getLPPosition(address,address)" 0xTOKEN_ADDRESS 0xUSER \
  --rpc-url $RPC_URL

# Get total liquidity across all vaults
forge script script/interact/InteractVaultManagerHelper.s.sol:InteractVaultManagerHelper \
  --sig "getTotalLiquidity()" \
  --rpc-url $RPC_URL

# Get total USD value across all vaults
forge script script/interact/InteractVaultManagerHelper.s.sol:InteractVaultManagerHelper \
  --sig "getTotalValueUSD()" \
  --rpc-url $RPC_URL

# Get comprehensive vaults summary
forge script script/interact/InteractVaultManagerHelper.s.sol:InteractVaultManagerHelper \
  --sig "getVaultsSummary()" \
  --rpc-url $RPC_URL

# Get native balance
forge script script/interact/InteractVaultManagerHelper.s.sol:InteractVaultManagerHelper \
  --sig "getNativeBalance()" \
  --rpc-url $RPC_URL

# Get token balance
forge script script/interact/InteractVaultManagerHelper.s.sol:InteractVaultManagerHelper \
  --sig "getTokenBalance(address)" 0xTOKEN \
  --rpc-url $RPC_URL
```

#### Admin Proxy Functions:
```bash
# Pause a vault
forge script script/interact/InteractVaultManagerHelper.s.sol:InteractVaultManagerHelper \
  --sig "pauseVault(address)" 0xTOKEN_ADDRESS \
  --rpc-url $RPC_URL \
  --broadcast

# Unpause a vault
forge script script/interact/InteractVaultManagerHelper.s.sol:InteractVaultManagerHelper \
  --sig "unpauseVault(address)" 0xTOKEN_ADDRESS \
  --rpc-url $RPC_URL \
  --broadcast

# Add vault admin
forge script script/interact/InteractVaultManagerHelper.s.sol:InteractVaultManagerHelper \
  --sig "addVaultAdmin(address,address)" 0xTOKEN_ADDRESS 0xADMIN \
  --rpc-url $RPC_URL \
  --broadcast

# Remove vault admin
forge script script/interact/InteractVaultManagerHelper.s.sol:InteractVaultManagerHelper \
  --sig "removeVaultAdmin(address,address)" 0xTOKEN_ADDRESS 0xADMIN \
  --rpc-url $RPC_URL \
  --broadcast

# Update vault parameters
forge script script/interact/InteractVaultManagerHelper.s.sol:InteractVaultManagerHelper \
  --sig "updateVaultParams(address,uint256,uint256,uint16)" \
  0xTOKEN_ADDRESS 1000000000000000 1000000000000000000000 8000 \
  --rpc-url $RPC_URL \
  --broadcast

# Set staking fee BPS
forge script script/interact/InteractVaultManagerHelper.s.sol:InteractVaultManagerHelper \
  --sig "setVaultStakingFeeBps(address,uint16)" 0xTOKEN_ADDRESS 200 \
  --rpc-url $RPC_URL \
  --broadcast

# Set early withdrawal fee BPS
forge script script/interact/InteractVaultManagerHelper.s.sol:InteractVaultManagerHelper \
  --sig "setVaultEarlyWithdrawalFeeBps(address,uint16)" 0xTOKEN_ADDRESS 1000 \
  --rpc-url $RPC_URL \
  --broadcast

# Set graduation threshold
forge script script/interact/InteractVaultManagerHelper.s.sol:InteractVaultManagerHelper \
  --sig "setVaultGraduationThreshold(address,uint256)" 0xTOKEN_ADDRESS 10000000000000000000000 \
  --rpc-url $RPC_URL \
  --broadcast

# Set trading enabled
forge script script/interact/InteractVaultManagerHelper.s.sol:InteractVaultManagerHelper \
  --sig "setVaultTradingEnabled(address,bool)" 0xTOKEN_ADDRESS true \
  --rpc-url $RPC_URL \
  --broadcast

# Set oracle adapter
forge script script/interact/InteractVaultManagerHelper.s.sol:InteractVaultManagerHelper \
  --sig "setVaultOracleAdapter(address,address)" 0xTOKEN_ADDRESS 0xORACLE_ADAPTER \
  --rpc-url $RPC_URL \
  --broadcast

# Set Blocksense Oracle
forge script script/interact/InteractVaultManagerHelper.s.sol:InteractVaultManagerHelper \
  --sig "setVaultBlocksenseOracle(address,address)" 0xTOKEN_ADDRESS 0xBLOCKSENSE_ORACLE \
  --rpc-url $RPC_URL \
  --broadcast
```

#### Batch Operations:
```bash
# Pause multiple vaults at once
forge script script/interact/InteractVaultManagerHelper.s.sol:InteractVaultManagerHelper \
  --sig "pauseVaultsBatch(address[])" "[0xTOKEN1,0xTOKEN2,0xTOKEN3]" \
  --rpc-url $RPC_URL \
  --broadcast

# Unpause multiple vaults at once
forge script script/interact/InteractVaultManagerHelper.s.sol:InteractVaultManagerHelper \
  --sig "unpauseVaultsBatch(address[])" "[0xTOKEN1,0xTOKEN2,0xTOKEN3]" \
  --rpc-url $RPC_URL \
  --broadcast

# Set staking fee for multiple vaults
forge script script/interact/InteractVaultManagerHelper.s.sol:InteractVaultManagerHelper \
  --sig "setStakingFeeBatch(address[],uint16)" "[0xTOKEN1,0xTOKEN2]" 200 \
  --rpc-url $RPC_URL \
  --broadcast
```

### 6. InteractAssetVault.s.sol

Interact with a specific AssetVault contract.

**Important:** Set `VAULT_ADDRESS` in `.env` before using this script.

**View Functions:**
```bash
# View vault info
forge script script/interact/InteractAssetVault.s.sol:InteractAssetVault \
  --sig "viewVaultInfo()" \
  --rpc-url $RPC_URL

# View user LP position
forge script script/interact/InteractAssetVault.s.sol:InteractAssetVault \
  --sig "viewLPPosition(address)" 0xUSER \
  --rpc-url $RPC_URL

# Calculate pending rewards
forge script script/interact/InteractAssetVault.s.sol:InteractAssetVault \
  --sig "calculatePendingRewards(address)" 0xUSER \
  --rpc-url $RPC_URL
```

**User Functions:**
```bash
# Add liquidity (approve tokens first!)
forge script script/interact/InteractAssetVault.s.sol:InteractAssetVault \
  --sig "addLiquidity(uint256)" 1000000000000000000 \
  --rpc-url $RPC_URL \
  --broadcast

# Remove liquidity
forge script script/interact/InteractAssetVault.s.sol:InteractAssetVault \
  --sig "removeLiquidity(uint256)" 1000000000000000000 \
  --rpc-url $RPC_URL \
  --broadcast

# Claim rewards
forge script script/interact/InteractAssetVault.s.sol:InteractAssetVault \
  --sig "claimRewards()" \
  --rpc-url $RPC_URL \
  --broadcast
```

**Admin Functions:**
```bash
# Set staking fee BPS
forge script script/interact/InteractAssetVault.s.sol:InteractAssetVault \
  --sig "setStakingFeeBps(uint16)" 200 \
  --rpc-url $RPC_URL \
  --broadcast

# Finalize daily reward (admin bot)
forge script script/interact/InteractAssetVault.s.sol:InteractAssetVault \
  --sig "finalizeDailyReward()" \
  --rpc-url $RPC_URL \
  --broadcast
```

### 7. InteractPendingClose.s.sol

Interact with pending close positions management for admin/backend cron tasks.

**Important:** This script is designed for backend automation to handle positions that couldn't be closed immediately due to stale oracle prices.

#### View Functions:
```bash
# View all pending positions with details (no broadcast needed)
forge script script/interact/InteractPendingClose.s.sol:InteractPendingClose \
  --sig "getPendingPositionDetails()" \
  --rpc-url $RPC_URL
```

#### Admin Functions:
```bash
# Process pending closes (default: max 10 positions)
forge script script/interact/InteractPendingClose.s.sol:InteractPendingClose \
  --sig "run()" \
  --rpc-url $RPC_URL \
  --broadcast

# Process specific batch size
forge script script/interact/InteractPendingClose.s.sol:InteractPendingClose \
  --sig "processPendingClosesBatch(uint256)" 20 \
  --rpc-url $RPC_URL \
  --broadcast

# Process single pending close
forge script script/interact/InteractPendingClose.s.sol:InteractPendingClose \
  --sig "processSinglePendingClose(uint64)" 123 \
  --rpc-url $RPC_URL \
  --broadcast

# Cancel pending close (revert to OPEN state)
forge script script/interact/InteractPendingClose.s.sol:InteractPendingClose \
  --sig "cancelPendingClose(uint64)" 123 \
  --rpc-url $RPC_URL \
  --broadcast
```

**Backend Cron Task Setup:**

This script should be run periodically (e.g., every 2-5 minutes) by backend automation:

```bash
#!/bin/bash
# cron-pending-close.sh
# Run every 2 minutes: */2 * * * * /path/to/cron-pending-close.sh

BATCH_SIZE=20
RPC_URL="https://your-rpc-url"
PRIVATE_KEY="your-admin-private-key"

forge script script/interact/InteractPendingClose.s.sol:InteractPendingClose \
  --sig "processPendingClosesBatch(uint256)" $BATCH_SIZE \
  --rpc-url $RPC_URL \
  --broadcast \
  --private-key $PRIVATE_KEY \
  >> /var/log/pending-close-cron.log 2>&1
```

See [PENDING_CLOSE_FEATURE.md](../../docs/PENDING_CLOSE_FEATURE.md) for detailed documentation on the pending close system.

### Advanced Pending Close Management

InteractPositionManager script cung cấp các advanced functions để quản lý và monitor pending close positions hiệu quả hơn:

**1. Health Check:**
```bash
# Kiểm tra toàn diện sức khỏe hệ thống
forge script script/interact/InteractPositionManager.s.sol:InteractPositionManager \
  --sig "healthCheckPendingClose()" \
  --rpc-url $RPC_URL
```

**2. Statistics & Analytics:**
```bash
# Xem thống kê chi tiết (LONG/SHORT, collateral, age, v.v.)
forge script script/interact/InteractPositionManager.s.sol:InteractPositionManager \
  --sig "getPendingCloseStats()" \
  --rpc-url $RPC_URL

# Group by user
forge script script/interact/InteractPositionManager.s.sol:InteractPositionManager \
  --sig "getPendingByUser()" \
  --rpc-url $RPC_URL
```

**3. Filter & Query:**
```bash
# Lọc positions cũ hơn 1 giờ (3600 seconds)
forge script script/interact/InteractPositionManager.s.sol:InteractPositionManager \
  --sig "getPendingOlderThan(uint256)" 3600 \
  --rpc-url $RPC_URL

# Lọc positions cũ hơn 24 giờ
forge script script/interact/InteractPositionManager.s.sol:InteractPositionManager \
  --sig "getPendingOlderThan(uint256)" 86400 \
  --rpc-url $RPC_URL
```

**4. Advanced Processing:**
```bash
# Process với detailed logging
forge script script/interact/InteractPositionManager.s.sol:InteractPositionManager \
  --sig "processPendingClosePositions(uint256, uint256)" 10 \
  --rpc-url $RPC_URL --broadcast

# Auto-retry processing (batchSize=10, maxIterations=5)
forge script script/interact/InteractPositionManager.s.sol:InteractPositionManager \
  --sig "processAllPendingWithRetry(uint256,uint256)" 10 5 \
  --rpc-url $RPC_URL --broadcast
```

**5. Batch Operations:**
```bash
# Batch cancel multiple positions
forge script script/interact/InteractPositionManager.s.sol:InteractPositionManager \
  --sig "batchCancelPendingClose(uint64[])" "[123,124,125]" \
  --rpc-url $RPC_URL --broadcast
```

**6. Export & Monitoring:**
```bash
# Export JSON cho monitoring systems
forge script script/interact/InteractPositionManager.s.sol:InteractPositionManager \
  --sig "exportPendingPositionsJSON()" \
  --rpc-url $RPC_URL

# Save to file
forge script script/interact/InteractPositionManager.s.sol:InteractPositionManager \
  --sig "exportPendingPositionsJSON()" \
  --rpc-url $RPC_URL > pending_$(date +%Y%m%d_%H%M%S).json
```

**Enhanced Cron Setup với Health Monitoring:**

```bash
#!/bin/bash
# advanced-cron-pending-close.sh
# Crontab: */5 * * * * /path/to/advanced-cron-pending-close.sh

SCRIPT_DIR="/path/to/boolean-contracts-evm"
RPC_URL="https://your-rpc-url"
LOG_DIR="/var/log/pending-close"

cd $SCRIPT_DIR

# 1. Health check
echo "[$(date)] Running health check..." >> $LOG_DIR/health.log
forge script script/interact/InteractPositionManager.s.sol:InteractPositionManager \
  --sig "healthCheckPendingClose()" \
  --rpc-url $RPC_URL >> $LOG_DIR/health.log 2>&1

# 2. Process với retry
echo "[$(date)] Processing pending positions..." >> $LOG_DIR/process.log
forge script script/interact/InteractPositionManager.s.sol:InteractPositionManager \
  --sig "processAllPendingWithRetry(uint256,uint256)" 10 3 \
  --rpc-url $RPC_URL --broadcast >> $LOG_DIR/process.log 2>&1

# 3. Export stats (mỗi 30 phút)
MINUTE=$(date +%M)
if [ $((10#$MINUTE % 30)) -eq 0 ]; then
  forge script script/interact/InteractPositionManager.s.sol:InteractPositionManager \
    --sig "exportPendingPositionsJSON()" \
    --rpc-url $RPC_URL > $LOG_DIR/stats_$(date +%Y%m%d_%H%M).json
fi

# 4. Alert nếu unhealthy
if grep -q "UNHEALTHY" $LOG_DIR/health.log; then
  # Send alert (Slack, Discord, Email, etc.)
  echo "ALERT: Pending Close System is UNHEALTHY!" | mail -s "System Alert" admin@example.com
fi
```

## Tips

1. **Always set addresses in `.env`** before running interact scripts
2. **Use view functions first** to check state before making transactions
3. **Test on local network first** before deploying to testnet/mainnet
4. **Approve tokens** before adding liquidity or opening positions
5. **Use `-vvvv` flag** for detailed output and debugging
6. **Check gas estimates** with `--gas-estimate` flag before broadcasting

## Common Errors

- `Oracle address not set` - Set `ORACLE_ADDRESS` in `.env`
- `Vault address not set` - Set `VAULT_ADDRESS` in `.env`
- `Vault Manager Helper address not set` - Set `VAULT_MANAGER_HELPER_ADDRESS` in `.env`
- `Insufficient allowance` - Approve tokens first using ERC20 approve
- `Position not found` - Check position ID is correct
- `Vault not found` - Create vault first or check project token address
- `NotAuthorized` - Make sure you're using the owner/admin account

## Examples

### Complete Flow Example (New Improved Flow)

1. **Deploy contracts:**
```bash
forge script script/DeployAll.s.sol --rpc-url $RPC_URL --broadcast
```

2. **View oracle config:**
```bash
forge script script/interact/InteractBlocksenseOracle.s.sol:InteractBlocksenseOracle \
  --sig "viewConfig()" --rpc-url $RPC_URL
```

3. **Create vault using VaultManager:**
```bash
forge script script/CreateVault.s.sol --rpc-url $RPC_URL --broadcast
```

4. **Check vault info:**
```bash
# View vault info using project token address
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "getVaultInfo(address)" $PROJECT_TOKEN \
  --rpc-url $RPC_URL
```

5. **Add liquidity (Stake tokens):**
```bash
# Approve tokens first
cast send $PROJECT_TOKEN "approve(address,uint256)" $VAULT_ADDRESS 1000000000000000000000 \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# Add liquidity using project token address (NOT vault address!)
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "addLiquidity(address,uint256)" $PROJECT_TOKEN 1000000000000000000 \
  --rpc-url $RPC_URL --broadcast
```

6. **Check LP position:**
```bash
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "getLPPosition(address,address)" $PROJECT_TOKEN $YOUR_ADDRESS \
  --rpc-url $RPC_URL
```

7. **Open position (Trade):**
```bash
# Approve tokens
cast send $PROJECT_TOKEN "approve(address,uint256)" $POSITION_MANAGER 1000000000000000000 \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# Open LONG position with 10x leverage
forge script script/interact/InteractPositionManager.s.sol:InteractPositionManager \
  --sig "openPosition(address,uint256,uint8,uint8,uint256)" \
  $PROJECT_TOKEN 1000000000000000000 10 1 0 \
  --rpc-url $RPC_URL --broadcast
```

8. **Check position:**
```bash
forge script script/interact/InteractPositionManager.s.sol:InteractPositionManager \
  --sig "getPosition(uint64)" 1 \
  --rpc-url $RPC_URL
```

9. **Close position:**
```bash
forge script script/interact/InteractPositionManager.s.sol:InteractPositionManager \
  --sig "closePosition(uint64,uint256)" 1 1234567890 \
  --rpc-url $RPC_URL --broadcast
```

10. **Claim LP rewards:**
```bash
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "claimRewards(address)" $PROJECT_TOKEN \
  --rpc-url $RPC_URL --broadcast
```

11. **Remove liquidity (Unstake):**
```bash
# Calculate withdrawal amount first
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "calculateWithdrawalAmount(address,address,uint256)" \
  $PROJECT_TOKEN $YOUR_ADDRESS 1000000000000000000 \
  --rpc-url $RPC_URL

# Remove liquidity
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "removeLiquidity(address,uint256)" $PROJECT_TOKEN 1000000000000000000 \
  --rpc-url $RPC_URL --broadcast
```

### VaultManagerHelper Usage Example

The VaultManagerHelper provides convenient view functions and admin proxy features:

**View all vaults summary:**
```bash
forge script script/interact/InteractVaultManagerHelper.s.sol:InteractVaultManagerHelper \
  --sig "getVaultsSummary()" \
  --rpc-url $RPC_URL
```

**Get total liquidity and USD value:**
```bash
# Total liquidity across all vaults
forge script script/interact/InteractVaultManagerHelper.s.sol:InteractVaultManagerHelper \
  --sig "getTotalLiquidity()" \
  --rpc-url $RPC_URL

# Total USD value across all vaults
forge script script/interact/InteractVaultManagerHelper.s.sol:InteractVaultManagerHelper \
  --sig "getTotalValueUSD()" \
  --rpc-url $RPC_URL
```

**Admin operations:**
```bash
# Pause a specific vault
forge script script/interact/InteractVaultManagerHelper.s.sol:InteractVaultManagerHelper \
  --sig "pauseVault(address)" $PROJECT_TOKEN \
  --rpc-url $RPC_URL --broadcast

# Update vault parameters
forge script script/interact/InteractVaultManagerHelper.s.sol:InteractVaultManagerHelper \
  --sig "updateVaultParams(address,uint256,uint256,uint16)" \
  $PROJECT_TOKEN 1000000000000000 1000000000000000000000 8000 \
  --rpc-url $RPC_URL --broadcast
```

**Batch operations (admin only):**
```bash
# Pause multiple vaults at once
forge script script/interact/InteractVaultManagerHelper.s.sol:InteractVaultManagerHelper \
  --sig "pauseVaultsBatch(address[])" "[$TOKEN1,$TOKEN2,$TOKEN3]" \
  --rpc-url $RPC_URL --broadcast

# Set staking fee for multiple vaults
forge script script/interact/InteractVaultManagerHelper.s.sol:InteractVaultManagerHelper \
  --sig "setStakingFeeBatch(address[],uint16)" "[$TOKEN1,$TOKEN2]" 200 \
  --rpc-url $RPC_URL --broadcast
```
