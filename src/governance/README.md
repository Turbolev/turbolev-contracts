# 🏛️ Governance Contracts

Hệ thống governance cho Boolean Protocol theo mô hình **GMX/Hyperliquid**: Timelock + Multisig + LP Opt-in Upgrades.

---

## 📦 Contracts Overview

### 1. TimelockController.sol ⏱️
**Timelock với multisig approval system**

```solidity
// Delay: 24-48 hours (recommended: 48h)
// Purpose: Thời gian cho community phản ứng trước khi execute operations
```

**Key Features:**
- ✅ Schedule operations với delay
- ✅ Require M-of-N approvals trước khi execute
- ✅ Cancel operations nếu cần
- ✅ Multiple roles: Proposer, Approver, Executor

**Main Functions:**
```solidity
// Propose operation (only proposers)
schedule(target, value, data, predecessor, salt, delay)

// Approve operation (only approvers)
approve(operationId)

// Execute after delay + approvals (only executors)
execute(target, value, data, predecessor, salt)

// Cancel operation (only admin)
cancel(operationId)
```

**Use Cases:**
- Pause/unpause vaults
- Update critical parameters
- Upgrade contracts
- Emergency responses

---

### 2. MultisigWallet.sol 🔐
**M-of-N multisignature wallet**

```solidity
// Recommended: 3-of-5 or 4-of-7
// Purpose: Require consensus từ nhiều parties
```

**Key Features:**
- ✅ Submit transactions
- ✅ Confirm/revoke confirmations
- ✅ Execute khi đủ threshold
- ✅ Add/remove owners
- ✅ Change threshold

**Main Functions:**
```solidity
// Submit new transaction
submitTransaction(destination, value, data)

// Confirm transaction
confirmTransaction(transactionId)

// Execute after reaching threshold
executeTransaction(transactionId)

// Revoke confirmation
revokeConfirmation(transactionId)
```

**Use Cases:**
- Approve timelock operations
- Emergency multisig decisions
- Treasury management

---

### 3. VaultGovernor.sol 🎭
**Governance wrapper cho vault operations**

```solidity
// Purpose: Wrapper giữa governance và vaults
// Integrates: Timelock + Multisig + Emergency pause
```

**Key Features:**
- ✅ Propose pause/unpause vaults
- ✅ Emergency pause (guardians only, no delay)
- ✅ Batch operations
- ✅ Integration với VaultManager

**Main Functions:**
```solidity
// Propose pause (via timelock)
proposePauseVault(vault)

// Emergency pause (guardians only, NO DELAY)
emergencyPause(vault)

// Propose unpause
proposeUnpauseVault(vault)

// Batch operations
proposeBatchPause(vaults[])
```

**Use Cases:**
- Routine maintenance
- Emergency response
- Batch vault management

---

### 4. VaultBeacon.sol 🔄
**Upgradeable beacon cho tất cả vaults**

```solidity
// Pattern: Beacon Proxy
// Purpose: Upgrade all vaults cùng lúc
```

**Key Features:**
- ✅ Hold implementation address
- ✅ Upgrade toàn bộ vaults
- ✅ Per-vault custom implementation
- ✅ Opt-in enforcement

**Main Functions:**
```solidity
// Get implementation for vault
implementation() → address

// Upgrade global implementation (all vaults)
upgradeTo(newImplementation)

// Set custom implementation for specific vault
setVaultImplementation(vault, implementation)

// Clear custom implementation
clearVaultImplementation(vault)
```

**Use Cases:**
- Bug fixes
- Feature upgrades
- Emergency patches

---

### 5. OptInUpgradeManager.sol ✅
**LP opt-in upgrade system (GMX/Hyperliquid style)**

```solidity
// Grace Period: 48 hours (default)
// Opt-in Logic: LPs không rút = auto opt-in
// NO TVL Threshold: Avoid governance deadlock
```

**Key Features:**
- ✅ Propose upgrade với grace period
- ✅ LPs có thể withdraw trong grace period
- ✅ Auto execute sau grace period
- ✅ No threshold requirement
- ✅ Emergency override

**Main Functions:**
```solidity
// Propose upgrade (only timelock)
proposeUpgrade(vault, newImplementation, customGracePeriod)

// Execute upgrade after grace period (anyone)
executeUpgrade(vault)

// Cancel upgrade (only timelock)
cancelUpgrade(vault)

// Emergency override (only timelock)
enableEmergencyOverride()
```

**Upgrade Flow:**
```
Hour 0:  Propose upgrade
         └─> Grace period starts (48h)

Hour 0-48: LPs decide
           ├─> Want to stay: Do nothing (auto opt-in)
           └─> Want to leave: removeLiquidity()

Hour 48:   Execute upgrade
           └─> All remaining LPs upgraded ✅
```

**Use Cases:**
- Planned upgrades
- Bug fixes
- Feature additions

---

## 🔄 Integration Flow

### Normal Operation (Pause Vault)

```
Step 1: Propose
  VaultGovernor.proposePauseVault(vault)
    └─> TimelockController.schedule(operation, 48h)

Step 2: Approve (Day 0-2)
  MultisigWallet approvers confirm
    └─> 3 of 5 signatures required

Step 3: Execute (Day 2+)
  TimelockController.execute(operation)
    └─> VaultManager.pauseVault(vault)
        └─> Vault.pause() ✅

Timeline: 48 hours
```

### Emergency Operation (Critical Issue)

```
VaultGovernor.emergencyPause(vault)
  └─> VaultManager.pauseVault(vault)
      └─> Vault.pause() ✅

Timeline: < 1 minute (NO DELAY)
```

### Upgrade Operation (LP Opt-in)

```
Step 1: Propose
  OptInUpgradeManager.proposeUpgrade(vault, implV2, 48h)
    └─> Grace period starts

Step 2: Grace Period (48h)
  LPs can:
    ├─> removeLiquidity() → Opt-out
    └─> Stay → Auto opt-in

Step 3: Execute
  OptInUpgradeManager.executeUpgrade(vault)
    └─> VaultBeacon.setVaultImplementation(vault, implV2)
        └─> All vaults upgraded ✅

Timeline: 48 hours (fixed)
```

---

## 🔐 Access Control

| Contract | Role | Permissions |
|----------|------|-------------|
| **TimelockController** | Admin | Update settings, cancel ops |
| | Proposer | Schedule operations |
| | Approver | Approve operations (M-of-N) |
| | Executor | Execute approved operations |
| **MultisigWallet** | Owner | Submit, confirm, execute txs |
| **VaultGovernor** | Owner | Propose operations |
| | Guardian | Emergency pause only |
| **VaultBeacon** | Owner | Upgrade implementation |
| **OptInUpgradeManager** | Timelock | Propose/cancel upgrades |
| | Anyone | Execute after grace period |

---

## ⚙️ Configuration Examples

### Testnet (Fast)
```javascript
const testnetConfig = {
  // Timelock
  delay: 1 * 3600,              // 1 hour
  approvalThreshold: 2,         // 2-of-3
  
  // Multisig
  owners: 3,
  threshold: 2,
  
  // Upgrade
  gracePeriod: 2 * 3600,        // 2 hours
};
```

### Production (Secure)
```javascript
const productionConfig = {
  // Timelock
  delay: 48 * 3600,             // 48 hours
  approvalThreshold: 3,         // 3-of-5
  
  // Multisig
  owners: 5,
  threshold: 3,
  
  // Upgrade
  gracePeriod: 48 * 3600,       // 48 hours
  
  // Guardians
  pauseGuardians: [addr1, addr2],
};
```

---

## 📊 Security Model

### Defense Layers

```
Layer 1: Access Control
  └─> Only authorized roles can propose

Layer 2: Timelock Delay (48h)
  └─> Community has time to react

Layer 3: Multisig Approval (3/5)
  └─> Require consensus

Layer 4: LP Opt-in (48h grace)
  └─> LPs can withdraw before upgrade

Layer 5: Emergency Response
  └─> Guardians can pause immediately
```

### Attack Vectors & Mitigations

| Attack | Mitigation |
|--------|-----------|
| **Admin key compromise** | Multisig (3/5) + Timelock (48h) |
| **Malicious upgrade** | LP opt-in (48h to withdraw) |
| **Fast exploit** | Emergency pause (guardians) |
| **Governance deadlock** | No TVL threshold required |
| **Single point of failure** | Distributed signers |

---

## 🎯 Design Principles

### 1. LP Protection First
- ✅ Always have time to withdraw (48h)
- ✅ No forced upgrades
- ✅ Transparent on-chain

### 2. No Deadlock
- ✅ No TVL threshold
- ✅ No quorum requirement
- ✅ Fixed timeline (48h)

### 3. Emergency Ready
- ✅ Pause guardians (no delay)
- ✅ Cannot unpause (governance only)
- ✅ Emergency override (7 days limit)

### 4. Battle-Tested
- ✅ GMX model ($400M+ TVL)
- ✅ Hyperliquid proven
- ✅ Simple & effective

---

## 🚀 Quick Start

### Deploy Governance System

```solidity
// 1. Deploy Timelock
TimelockController timelock = new TimelockController(
    48 * 3600,                    // 48h delay
    [proposer1, proposer2],       // proposers
    [executor1, executor2],       // executors
    [approver1, approver2, approver3, approver4, approver5],  // 5 approvers
    3,                            // 3-of-5 threshold
    admin
);

// 2. Deploy Multisig
MultisigWallet multisig = new MultisigWallet(
    [owner1, owner2, owner3, owner4, owner5],  // 5 owners
    3                                          // 3-of-5
);

// 3. Deploy VaultGovernor
VaultGovernor governor = new VaultGovernor(
    address(timelock),
    address(multisig),
    vaultManager,
    [guardian1, guardian2]  // pause guardians
);

// 4. Deploy Beacon
VaultBeacon beacon = new VaultBeacon(
    assetVaultImplementation,
    admin
);

// 5. Deploy OptInUpgradeManager
OptInUpgradeManager upgradeManager = new OptInUpgradeManager(
    address(beacon),
    address(timelock)
);

// 6. Connect everything
beacon.setOptInUpgradeManager(address(upgradeManager));
upgradeManager.updateDefaultGracePeriod(48 * 3600);

// ✅ Done!
```

### Example Operations

**Pause Vault:**
```solidity
// 1. Propose via governor
governor.proposePauseVault(vault);

// 2. Multisig approves (3/5)
multisig.confirmTransaction(txId);  // x3

// 3. Execute after 48h
timelock.execute(operationId);
```

**Upgrade Vault:**
```solidity
// 1. Deploy new implementation
AssetVaultUpgradeable implV2 = new AssetVaultUpgradeable();

// 2. Propose upgrade
upgradeManager.proposeUpgrade(vault, address(implV2), 48 * 3600);

// 3. Wait 48h (LPs can withdraw)

// 4. Execute
upgradeManager.executeUpgrade(vault);
```

**Emergency Pause:**
```solidity
// Guardian calls directly (NO DELAY)
governor.emergencyPause(vault);
```

---

## 📚 Further Reading

- **../GOVERNANCE_ARCHITECTURE.md** - Chi tiết architecture
- **../SYSTEM_OVERVIEW.md** - Tổng quan hệ thống
- **../VaultManager.sol** - Main factory contract

---

## 🔍 Testing

```bash
# Run governance tests
forge test --match-contract Governance

# Run specific test
forge test --match-test testTimelockDelay

# Coverage
forge coverage
```

---

## ⚠️ Important Notes

1. **Timelock Delay**: Minimum 24h, recommended 48h
2. **Multisig**: Minimum 3-of-5, recommended 4-of-7 for large teams
3. **Grace Period**: Minimum 24h, recommended 48h
4. **Guardians**: 2-3 trusted addresses, cannot unpause
5. **Emergency Override**: Max 7 days, use carefully

---

## 📝 Changelog

### V2.0 (Current)
- ✅ TimelockController with multisig approval
- ✅ VaultGovernor wrapper
- ✅ VaultBeacon for upgrades
- ✅ OptInUpgradeManager (GMX style)
- ✅ Emergency pause guardians

### V1.0
- Basic Ownable pattern
- No timelock
- No opt-in upgrades

---

## 🤝 Contributing

Khi modify governance contracts:
1. Test thoroughly (mainnet fork recommended)
2. Update docs
3. Review with team
4. Audit if critical changes

---

## 📞 Support

- GitHub Issues: [boolean-contracts-evm](https://github.com/capylabs/boolean-contracts-evm)
- Docs: See root README.md

---

Made with ❤️ by Capylabs


