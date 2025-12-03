# Boolean Contracts Deployment Scripts

This directory contains Foundry scripts for deploying and interacting with the Boolean Contracts system.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Environment Setup](#environment-setup)
- [Deployment Scripts](#deployment-scripts)
- [Interaction Scripts](#interaction-scripts)
- [Common Issues](#common-issues)

## Overview

The Boolean Contracts system consists of the following upgradeable core contracts:

### Core Contracts
1. **PositionManager** - Position lifecycle management (open/close/liquidate)
2. **SettlementEngine** - Position settlement and P&L calculation
3. **VaultManager** - Vault factory and management
4. **VaultManagerHelper** - Helper functions for vault operations
5. **PriceFeedManager** - Oracle registry and price feed management

### Oracle Contracts
6. **BlocksenseOracle** - Blocksense oracle integration
7. **ChainlinkOracle** - Chainlink oracle integration
8. **PythOracle** - Pyth oracle integration (pull mode)

### Vault Contract
9. **AssetVaultUpgradeable** - Per-token vault with:
   - LP liquidity management
   - Risk controls (directional exposure, OI caps, leverage tiers)
   - Funding rates
   - Position fees

## Prerequisites

1. **Foundry installed**
   ```bash
   curl -L https://foundry.paradigm.xyz | bash
   foundryup
   ```

2. **Environment variables configured** (see [Environment Setup](#environment-setup))

3. **Private key with sufficient ETH** for deployment

4. **Blocksense Registry address** (if deploying to mainnet/testnet)

## Environment Setup

### 1. Copy the example environment file

```bash
cp .env.example .env
```

### 2. Configure the environment variables

Edit `.env` with your values:

```bash
# Network Configuration
CHAIN_ID=31337                          # 1 for mainnet, 31337 for local testnet
RPC_URL=http://localhost:8545           # Your RPC endpoint

# Account Configuration
OWNER_ADDRESS=0x...                     # Contract owner address
ADMIN_ADDRESS=0x...                      # Admin/oracle role address
DEPLOYER_PRIVATE_KEY=0x...             # Private key for deployment

# Blocksense Registry (REQUIRED for mainnet/testnet)
BLOCKSENSE_REGISTRY_ADDRESS=0x...      # Set to empty for local dev

# Optional: Override default parameters
ORACLE_MAX_PRICE_AGE=3600
MAINTENANCE_MARGIN_RATIO=5000
MIN_LEVERAGE=10000
MAX_LEVERAGE=1000000
```

### 3. Important Notes

- **NEVER commit `.env` file** - it contains sensitive private keys
- For **local development**, you can omit `BLOCKSENSE_REGISTRY_ADDRESS`
- For **mainnet/testnet**, `BLOCKSENSE_REGISTRY_ADDRESS` is **REQUIRED**
- Use `cast wallet` to generate new private keys if needed

## Deployment Scripts

### Smart Deployment (Recommended)

All deployment scripts now support **smart deployment** - they will check if contracts are already deployed before deploying new ones.

**How it works:**
1. Scripts read contract addresses from environment variables first
2. If addresses are set (not zero), they skip deployment and use existing contracts
3. If addresses are not set, they deploy new contracts
4. After deployment, addresses are saved to `deployments/{chainId}.json`

**To use smart deployment:**
Add already deployed contract addresses to your `.env` file:
```bash
BLOCKSENSE_ORACLE_ADDRESS=0x...
SETTLEMENT_ENGINE_ADDRESS=0x...
POSITION_MANAGER_ADDRESS=0x...
VAULT_MANAGER_ADDRESS=0x...
```

This allows you to:
- Deploy only missing contracts
- Redeploy specific contracts while keeping others
- Skip deployment of contracts that are already on-chain

### Deploy Full System

Deploy all contracts in the correct order with automatic configuration:

```bash
forge script script/DeployAll.s.sol:DeployAll --rpc-url $RPC_URL --broadcast -vvv
```

**What it does:**
1. Checks each contract - if address in `.env`, uses existing contract
2. Deploys only missing contracts (upgradeable via UUPS proxy)
3. Connects all contracts together
4. Verifies the deployment
5. Saves deployment addresses to `deployments/{chainId}.json`

**Output:**
- Deployment addresses saved to `deployments/{chainId}.json`
- Full deployment summary printed to console

### Deploy Individual Contracts

If you need to deploy or redeploy specific contracts:

#### BlocksenseOracle

```bash
forge script script/DeployBlocksenseOracle.s.sol:DeployBlocksenseOracle \
  --rpc-url $RPC_URL --broadcast -vvv
```

#### SettlementEngine

```bash
forge script script/DeploySettlementEngine.s.sol:DeploySettlementEngine \
  --rpc-url $RPC_URL --broadcast -vvv
```

**Note:** Requires `BLOCKSENSE_ORACLE_ADDRESS` in `.env`

#### PositionManager

```bash
forge script script/DeployPositionManager.s.sol:DeployPositionManager\
  --rpc-url $RPC_URL --broadcast -vvv
```

**Note:** Requires `SETTLEMENT_ENGINE_ADDRESS` in `.env`

#### VaultManager

```bash
forge script script/DeployVaultManager.s.sol:DeployVaultManager \
  --rpc-url $RPC_URL --broadcast -vvv
```

### Create a New Vault

After deploying VaultManager, create vaults for specific project tokens:

```bash
# Basic vault creation
PROJECT_TOKEN=0x... forge script script/CreateVault.s.sol --sig "run()" \
  --rpc-url $RPC_URL --broadcast -vvv

# Vault with full configuration (risk controls)
PROJECT_TOKEN=0x... forge script script/CreateVault.s.sol --sig "createVaultWithConfig()" \
  --rpc-url $RPC_URL --broadcast -vvv

# Vault with funding rate enabled
PROJECT_TOKEN=0x... forge script script/CreateVault.s.sol --sig "createVaultWithFunding()" \
  --rpc-url $RPC_URL --broadcast -vvv
```

**Required environment variables:**
```bash
VAULT_MANAGER_ADDRESS=0x...
VAULT_MANAGER_HELPER_ADDRESS=0x...
PROJECT_TOKEN=0x...           # Project token address
```

**Optional parameters** (will use defaults from DeployHelper if not set):
```bash
# Basic params
MIN_BET_AMOUNT=1000000000000000       # 0.001 token
MAX_BET_AMOUNT=1000000000000000000000 # 1000 tokens
GRADUATION_THRESHOLD=10000000000000000000000  # 10,000 tokens

# Risk controls
MAX_DIRECTIONAL_EXPOSURE_BPS=5000     # 50% of TVL
TIER1_MAX_LEVERAGE=100                # Launch phase
TIER2_MAX_LEVERAGE=200                # Growth phase
TIER3_MAX_LEVERAGE=500                # Mature phase

# Funding rate
FUNDING_ENABLED=true
```

## Risk Control System

The vault system implements multiple layers of risk controls:

### Control Lever 1: Maximum Leverage Tiers

Leverage limits scale with vault TVL:

| TVL Range | Phase | Default Max Leverage |
|-----------|-------|---------------------|
| < 100K | Launch | 100x |
| 100K - 500K | Growth | 200x |
| >= 500K | Mature | 500x |

### Control Lever 2: Directional Exposure Cap

Net exposure (|Long - Short|) cannot exceed a percentage of TVL:
- Default: 50% (5000 bps)
- Example: TVL = 100K → Max net exposure = 50K

### Control Lever 3: Total OI Cap

Total Open Interest (Long + Short) is capped based on TVL tier:

| TVL Tier | Multiplier |
|----------|------------|
| Tier 1 (Small) | 1.5x TVL |
| Tier 2 (Medium) | 2.0x TVL |
| Tier 3 (Large) | 2.5x TVL |
| Tier 4 (Very Large) | 3.0x TVL |

### Funding Rate System

- Updates hourly based on OI imbalance
- Majority side (longs/shorts) pays minority side
- Rate scales with imbalance level:
  - < 20% imbalance: 0.01%/hour
  - 20-40%: 0.03%/hour
  - 40-60%: 0.05%/hour
  - 60-80%: 0.08%/hour
  - > 80%: 0.10%/hour

## Interaction Scripts

The `interact/` directory contains scripts for interacting with deployed contracts. These are useful for:
- Testing deployed contracts
- Performing admin operations
- Querying contract state

See [interact/README.md](./interact/README.md) for detailed documentation.

### Quick Examples

#### View Oracle Price

```bash
forge script script/interact/InteractBlocksenseOracle.s.sol:InteractBlocksenseOracle \
  --sig "getPrice(address)" 0xBTC_FEED_ADDRESS \
  --rpc-url $RPC_URL
```

#### Create Position

```bash
forge script script/interact/InteractPositionManager.s.sol:InteractPositionManager \
  --sig "openPosition()" \
  --rpc-url $RPC_URL --broadcast
```

#### View Vault Info

```bash
forge script script/interact/InteractAssetVault.s.sol:InteractAssetVault \
  --sig "getVaultInfo()" \
  --rpc-url $RPC_URL
```

## Deployment Addresses

After deployment, contract addresses are saved to:
```
deployments/{chainId}.json
```

Example structure:
```json
{
  "blocksenseOracle": "0x...",
  "blocksenseOracleImpl": "0x...",
  "settlementEngine": "0x...",
  "settlementEngineImpl": "0x...",
  "positionManager": "0x...",
  "positionManagerImpl": "0x...",
  "vaultManager": "0x...",
  "vaultManagerImpl": "0x...",
  "chainId": 31337,
  "timestamp": 1234567890
}
```

## Common Issues

### 1. "Invalid private key" Error

**Problem:** Private key format is incorrect.

**Solution:** 
```bash
# Private keys should start with 0x
DEPLOYER_PRIVATE_KEY=0x1234567890abcdef...
```

### 2. "Blocksense Registry address required" Error

**Problem:** Deploying to mainnet/testnet without setting `BLOCKSENSE_REGISTRY_ADDRESS`.

**Solution:**
```bash
# Add to .env
BLOCKSENSE_REGISTRY_ADDRESS=0x...
```

### 3. "Insufficient funds" Error

**Problem:** Deployer account has insufficient ETH for gas fees.

**Solution:**
- Check balance: `cast balance $DEPLOYER_ADDRESS --rpc-url $RPC_URL`
- Send ETH to deployer account

### 4. "Nonce too low" Error / Transaction Failures When Deploying Onchain

**Problem:** 
- Một số transaction fail khi deploy onchain nhưng simulate thành công
- Nonce conflicts khi nhiều transaction được gửi cùng lúc
- Transaction ordering issues

**Nguyên nhân:**
- Khi simulate, tất cả transaction được thực thi trong môi trường giả lập
- Khi deploy onchain, nhiều transaction được gửi cùng lúc trong một `vm.startBroadcast()` block
- Có thể có vấn đề về RPC rate limiting hoặc gas estimation

**Giải pháp:**

#### Option 1: Sử dụng UpdateConnections sau khi deploy
Nếu deployment thành công nhưng một số connection fail:

```bash
# 1. Deploy contracts (có thể một số connection fail)
forge script script/DeployAll.s.sol:DeployAll \
  --rpc-url $RPC_URL \
  --broadcast \
  --account monadDeployer \
  --sender 0xc54840D80bc1eF1A8902C0F1A1db54287335DBe1 \
  --gas-limit 50000000 \
  --slow \
  -vvv

# 2. Fix connections riêng biệt (nếu cần)
forge script script/UpdateConnections.s.sol:UpdateConnections \
  --rpc-url $RPC_URL \
  --broadcast \
  --account monadDeployer \
  --sender 0xc54840D80bc1eF1A8902C0F1A1db54287335DBe1 \
  --gas-limit 50000000 \
  --slow \
  -vvv
```

#### Option 2: Deploy từng contract riêng biệt
Nếu DeployAll fail, có thể deploy từng contract:

```bash
# Deploy từng contract một
forge script script/DeployBlocksenseOracle.s.sol:DeployBlocksenseOracle \
  --rpc-url $RPC_URL --broadcast --account monadDeployer --slow -vvv

forge script script/DeployChainlinkOracle.s.sol:DeployChainlinkOracle \
  --rpc-url $RPC_URL --broadcast --account monadDeployer --slow -vvv

# ... tiếp tục với các contract khác

# Sau đó chạy UpdateConnections để connect tất cả
forge script script/UpdateConnections.s.sol:UpdateConnections \
  --rpc-url $RPC_URL --broadcast --account monadDeployer --slow -vvv
```

#### Option 3: Clear cache và thử lại
```bash
# Clear foundry cache
rm -rf cache/
forge clean

# Kiểm tra nonce hiện tại
cast nonce $DEPLOYER_ADDRESS --rpc-url $RPC_URL

# Thử lại với --slow flag
forge script script/DeployAll.s.sol:DeployAll \
  --rpc-url $RPC_URL \
  --broadcast \
  --account monadDeployer \
  --sender 0xc54840D80bc1eF1A8902C0F1A1db54287335DBe1 \
  --gas-limit 50000000 \
  --slow \
  -vvv
```

**Best Practices:**
1. **Luôn simulate trước**: `forge script script/DeployAll.s.sol:DeployAll --rpc-url $RPC_URL` (không có --broadcast)
2. **Sử dụng `--slow` flag** để đảm bảo transaction được gửi tuần tự
3. **Kiểm tra balance** trước khi deploy: `cast balance $DEPLOYER_ADDRESS --rpc-url $RPC_URL`
4. **Monitor transactions** trên block explorer
5. **Nếu một số transaction fail**, sử dụng `UpdateConnections.s.sol` để fix riêng
6. **Script sẽ tự động skip** các contract đã deploy nếu chạy lại

### 5. Contract Not Verified

**Problem:** Contracts are deployed but not verified on block explorer.

**Solution:**
```bash
# Verify on Etherscan (requires ETHERSCAN_API_KEY)
forge verify-contract \
  --chain-id $CHAIN_ID \
  --constructor-args $(cast abi-encode "constructor()" ) \
  $CONTRACT_ADDRESS \
  src/ContractName.sol:ContractName \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

### 6. "ERC1967: new implementation is not UUPS" Error

**Problem:** Trying to upgrade to an incompatible implementation.

**Solution:**
- Ensure new implementation inherits from `UUPSUpgradeable`
- Ensure `_authorizeUpgrade()` function is implemented

## Advanced Usage

### Dry Run (Simulation)

Test deployment without broadcasting transactions:

```bash
forge script script/DeployAll.s.sol:DeployAll --rpc-url $RPC_URL
```

### Custom Gas Settings

```bash
forge script script/DeployAll.s.sol:DeployAll \
  --rpc-url $RPC_URL \
  --broadcast \
  --gas-price 50000000000 \
  --priority-gas-price 2000000000
```

### Deploy to Specific Network

```bash
# Mainnet
forge script script/DeployAll.s.sol:DeployAll \
  --rpc-url https://eth-mainnet.alchemyapi.io/v2/YOUR_KEY \
  --broadcast \
  --verify

# Sepolia testnet
forge script script/DeployAll.s.sol:DeployAll \
  --rpc-url https://eth-sepolia.alchemyapi.io/v2/YOUR_KEY \
  --broadcast \
  --verify
```

### Upgrade Contracts

To upgrade an existing contract:

1. Deploy new implementation:
```bash
forge create src/PositionManager.sol:PositionManager \
  --rpc-url $RPC_URL \
  --private-key $DEPLOYER_PRIVATE_KEY
```

2. Call `upgradeToAndCall` on the proxy:
```bash
cast send $PROXY_ADDRESS \
  "upgradeToAndCall(address,bytes)" \
  $NEW_IMPLEMENTATION_ADDRESS \
  0x \
  --rpc-url $RPC_URL \
  --private-key $OWNER_PRIVATE_KEY
```

## Security Best Practices

1. **Use hardware wallet** for mainnet deployments
2. **Test on testnet first** before mainnet deployment
3. **Verify contracts** on block explorer after deployment
4. **Use multi-sig** for owner/admin roles in production
5. **Keep private keys secure** - never commit to git
6. **Audit contracts** before mainnet deployment
7. **Test upgrades** on testnet before applying to mainnet

## Support

For issues or questions:
- Check [Common Issues](#common-issues)
- Review [Foundry Book](https://book.getfoundry.sh/)
- Open an issue on GitHub

## License

MIT

