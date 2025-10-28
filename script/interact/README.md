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

# Add backend address
forge script script/interact/InteractPositionManager.s.sol:InteractPositionManager \
  --sig "addBackend(address)" 0xBACKEND \
  --rpc-url $RPC_URL \
  --broadcast
```

### 4. InteractVaultManager.s.sol

Interact with VaultManager contract.

**View Functions:**
```bash
# View configuration
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "viewConfig()" \
  --rpc-url $RPC_URL

# Get all vaults
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "getAllVaults()" \
  --rpc-url $RPC_URL

# Check if vault is graduated
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "isVaultGraduated(address)" 0xVAULT \
  --rpc-url $RPC_URL
```

**Admin Functions:**
```bash
# Create vault
forge script script/interact/InteractVaultManager.s.sol:InteractVaultManager \
  --sig "createVault(address,address,address,address,uint16,uint16,uint16,uint256,uint256,uint256)" \
  0xPROJECT_TOKEN 0xBASE 0xQUOTE 0xMON 500 1000 8000 1000000000000000 1000000000000000000000 10000000000000000000000 \
  --rpc-url $RPC_URL \
  --broadcast
```

### 5. InteractAssetVault.s.sol

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

# Finalize daily reward (backend bot)
forge script script/interact/InteractAssetVault.s.sol:InteractAssetVault \
  --sig "finalizeDailyReward()" \
  --rpc-url $RPC_URL \
  --broadcast
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
- `Insufficient allowance` - Approve tokens first using ERC20 approve
- `Position not found` - Check position ID is correct
- `Vault not found` - Create vault first or check project token address

## Examples

### Complete Flow Example

1. **Deploy contracts:**
```bash
forge script script/DeployAll.s.sol --rpc-url $RPC_URL --broadcast
```

2. **View oracle config:**
```bash
forge script script/interact/InteractBlocksenseOracle.s.sol:InteractBlocksenseOracle \
  --sig "viewConfig()" --rpc-url $RPC_URL
```

3. **Create vault:**
```bash
forge script script/CreateVault.s.sol --rpc-url $RPC_URL --broadcast
```

4. **Add liquidity:**
```bash
# Approve tokens first
cast send $PROJECT_TOKEN "approve(address,uint256)" $VAULT_ADDRESS 1000000000000000000000 \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# Add liquidity
forge script script/interact/InteractAssetVault.s.sol:InteractAssetVault \
  --sig "addLiquidity(uint256)" 1000000000000000000 \
  --rpc-url $RPC_URL --broadcast
```

5. **Open position:**
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
