/**
 * Script để setup vault với Chainlink fallback
 *
 * Script này demo cách:
 * 1. Set oracle adapter (Blocksense) cho vault
 * 2. Set Chainlink feed (fallback) cho vault
 * 3. Configure ChainlinkOracle để map adapter -> Chainlink feed
 * 4. Test lấy giá với fallback mechanism
 *
 * Sử dụng:
 * node node_scripts/setup-vault-with-fallback.js
 */

const { ethers } = require('ethers')
require('dotenv').config()

// ========================================================================
// ABI DEFINITIONS
// ========================================================================

const ASSET_VAULT_ABI = [
  'function setOracleAdapter(address _oracleAdapter) external',
  'function setChainlinkFeed(address _chainlinkFeed) external',
  'function oracleAdapter() external view returns (address)',
  'function chainlinkFeed() external view returns (address)'
]

const CHAINLINK_ORACLE_ABI = [
  'function setChainlinkFeed(address adapter, address chainlinkFeed) external',
  'function hasFallback(address adapter) external view returns (bool hasFallback, address chainlinkFeed)',
  'function getPrice(address adapter) external view returns (int256 price, uint256 updatedAt, bool usedFallback)',
  'function getPriceBothSources(address adapter) external view returns (int256 blocksensePrice, uint256 blocksenseUpdatedAt, bool blocksenseSuccess, int256 chainlinkPrice, uint256 chainlinkUpdatedAt, bool chainlinkSuccess)',
  'function fallbackCount(address adapter) external view returns (uint256 count)'
]

// ========================================================================
// CONFIGURATION
// ========================================================================

const config = {
  rpcUrl: process.env.RPC_URL || 'https://rpc.ankr.com/eth',
  privateKey: process.env.PRIVATE_KEY || '',
  vaultAddress: process.env.VAULT_ADDRESS || '',
  oracleAdapter: process.env.ORACLE_ADAPTER || '', // Blocksense adapter
  chainlinkFeed: process.env.CHAINLINK_FEED || '', // Chainlink feed (fallback)
  chainlinkOracle: process.env.CHAINLINK_ORACLE || '' // ChainlinkOracle contract
}

// Parse command line arguments
const args = process.argv.slice(2)
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--rpc' && args[i + 1]) {
    config.rpcUrl = args[i + 1]
    i++
  } else if (args[i] === '--vault' && args[i + 1]) {
    config.vaultAddress = args[i + 1]
    i++
  } else if (args[i] === '--adapter' && args[i + 1]) {
    config.oracleAdapter = args[i + 1]
    i++
  } else if (args[i] === '--chainlink' && args[i + 1]) {
    config.chainlinkFeed = args[i + 1]
    i++
  } else if (args[i] === '--oracle' && args[i + 1]) {
    config.chainlinkOracle = args[i + 1]
    i++
  }
}

// ========================================================================
// HELPER FUNCTIONS
// ========================================================================

function formatPrice(price, decimals = 18) {
  const priceStr = ethers.formatUnits(price, decimals)
  return parseFloat(priceStr).toLocaleString('en-US', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 8
  })
}

function formatTimestamp(timestamp) {
  const date = new Date(Number(timestamp) * 1000)
  return date.toLocaleString('vi-VN', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    timeZone: 'Asia/Ho_Chi_Minh'
  })
}

// ========================================================================
// MAIN FUNCTIONS
// ========================================================================

/**
 * Setup vault với oracle adapter và Chainlink fallback
 */
async function setupVault(provider, wallet) {
  console.log('\n========================================')
  console.log('📦 SETUP VAULT WITH FALLBACK')
  console.log('========================================\n')

  try {
    const vault = new ethers.Contract(config.vaultAddress, ASSET_VAULT_ABI, wallet)

    console.log('🔧 Cấu hình vault:')
    console.log(`   Vault Address: ${config.vaultAddress}`)
    console.log(`   Oracle Adapter (Blocksense): ${config.oracleAdapter}`)
    console.log(`   Chainlink Feed (Fallback): ${config.chainlinkFeed}`)

    // Step 1: Set oracle adapter
    console.log('\n1️⃣ Setting Oracle Adapter...')
    const tx1 = await vault.setOracleAdapter(config.oracleAdapter)
    await tx1.wait()
    console.log('   ✅ Oracle Adapter set successfully')
    console.log(`   Transaction: ${tx1.hash}`)

    // Step 2: Set Chainlink feed
    console.log('\n2️⃣ Setting Chainlink Feed...')
    const tx2 = await vault.setChainlinkFeed(config.chainlinkFeed)
    await tx2.wait()
    console.log('   ✅ Chainlink Feed set successfully')
    console.log(`   Transaction: ${tx2.hash}`)

    // Verify
    console.log('\n3️⃣ Verifying vault configuration...')
    const currentAdapter = await vault.oracleAdapter()
    const currentFeed = await vault.chainlinkFeed()

    console.log(`   Oracle Adapter: ${currentAdapter}`)
    console.log(`   Chainlink Feed: ${currentFeed}`)

    if (
      currentAdapter.toLowerCase() === config.oracleAdapter.toLowerCase() &&
      currentFeed.toLowerCase() === config.chainlinkFeed.toLowerCase()
    ) {
      console.log('   ✅ Vault configuration verified!')
      return true
    } else {
      console.log('   ❌ Vault configuration mismatch!')
      return false
    }
  } catch (error) {
    console.error('\n❌ Lỗi khi setup vault:', error.message)
    return false
  }
}

/**
 * Configure ChainlinkOracle mapping
 */
async function configureOracle(provider, wallet) {
  console.log('\n========================================')
  console.log('🔗 CONFIGURE CHAINLINK ORACLE')
  console.log('========================================\n')

  try {
    const oracle = new ethers.Contract(
      config.chainlinkOracle,
      CHAINLINK_ORACLE_ABI,
      wallet
    )

    console.log('🔧 Cấu hình ChainlinkOracle:')
    console.log(`   Oracle Address: ${config.chainlinkOracle}`)
    console.log(`   Adapter: ${config.oracleAdapter}`)
    console.log(`   Chainlink Feed: ${config.chainlinkFeed}`)

    // Set mapping
    console.log('\n1️⃣ Setting Chainlink Feed mapping...')
    const tx = await oracle.setChainlinkFeed(
      config.oracleAdapter,
      config.chainlinkFeed
    )
    await tx.wait()
    console.log('   ✅ Mapping set successfully')
    console.log(`   Transaction: ${tx.hash}`)

    // Verify
    console.log('\n2️⃣ Verifying mapping...')
    const [hasFallback, feed] = await oracle.hasFallback(config.oracleAdapter)

    console.log(`   Has Fallback: ${hasFallback}`)
    console.log(`   Chainlink Feed: ${feed}`)

    if (hasFallback && feed.toLowerCase() === config.chainlinkFeed.toLowerCase()) {
      console.log('   ✅ Oracle configuration verified!')
      return true
    } else {
      console.log('   ❌ Oracle configuration mismatch!')
      return false
    }
  } catch (error) {
    console.error('\n❌ Lỗi khi configure oracle:', error.message)
    return false
  }
}

/**
 * Test lấy giá với fallback mechanism
 */
async function testGetPrice(provider) {
  console.log('\n========================================')
  console.log('🧪 TEST PRICE RETRIEVAL')
  console.log('========================================\n')

  try {
    const oracle = new ethers.Contract(
      config.chainlinkOracle,
      CHAINLINK_ORACLE_ABI,
      provider
    )

    // Test 1: Get price với fallback
    console.log('1️⃣ Testing getPrice (với fallback)...\n')

    const [price, updatedAt, usedFallback] = await oracle.getPrice(
      config.oracleAdapter
    )

    console.log('📊 Kết quả:')
    console.log(`   Price: $${formatPrice(price, 18)}`)
    console.log(`   Updated At: ${formatTimestamp(updatedAt)}`)
    console.log(`   Timestamp: ${updatedAt}`)
    console.log(
      `   Age: ${Number((Date.now() / 1000).toFixed(0)) - Number(updatedAt)} giây`
    )
    console.log(`   Used Fallback: ${usedFallback ? '🟡 YES (Chainlink)' : '🟢 NO (Blocksense)'}`)

    // Test 2: Get price từ cả 2 sources
    console.log('\n2️⃣ Testing getPriceBothSources (comparison)...\n')

    const [
      blocksensePrice,
      blocksenseUpdatedAt,
      blocksenseSuccess,
      chainlinkPrice,
      chainlinkUpdatedAt,
      chainlinkSuccess
    ] = await oracle.getPriceBothSources(config.oracleAdapter)

    console.log('📊 Blocksense Oracle:')
    if (blocksenseSuccess) {
      console.log(`   Status: ✅ SUCCESS`)
      console.log(`   Price: $${formatPrice(blocksensePrice, 18)}`)
      console.log(`   Updated At: ${formatTimestamp(blocksenseUpdatedAt)}`)
    } else {
      console.log(`   Status: ❌ FAILED`)
    }

    console.log('\n📊 Chainlink Oracle:')
    if (chainlinkSuccess) {
      console.log(`   Status: ✅ SUCCESS`)
      console.log(`   Price: $${formatPrice(chainlinkPrice, 18)}`)
      console.log(`   Updated At: ${formatTimestamp(chainlinkUpdatedAt)}`)
    } else {
      console.log(`   Status: ❌ FAILED`)
    }

    // Compare prices
    if (blocksenseSuccess && chainlinkSuccess) {
      console.log('\n📈 So sánh giá:')
      const diff = Number(blocksensePrice) - Number(chainlinkPrice)
      const diffPercent = (Math.abs(diff) / Number(blocksensePrice)) * 100

      console.log(`   Blocksense: $${formatPrice(blocksensePrice, 18)}`)
      console.log(`   Chainlink:  $${formatPrice(chainlinkPrice, 18)}`)
      console.log(
        `   Difference: $${formatPrice(Math.abs(diff), 18)} (${diffPercent.toFixed(4)}%)`
      )

      if (diffPercent > 1) {
        console.log(`   ⚠️  CẢNH BÁO: Chênh lệch giá > 1%`)
      } else {
        console.log(`   ✅ Giá khớp tốt (< 1%)`)
      }
    }

    // Get fallback count
    console.log('\n3️⃣ Checking fallback usage statistics...\n')
    const fallbackCount = await oracle.fallbackCount(config.oracleAdapter)
    console.log(`📊 Fallback Count: ${fallbackCount}`)

    if (fallbackCount > 0) {
      console.log(
        `   ⚠️  Fallback đã được sử dụng ${fallbackCount} lần cho adapter này`
      )
    } else {
      console.log(`   ✅ Blocksense Oracle đang hoạt động ổn định`)
    }

    return true
  } catch (error) {
    console.error('\n❌ Lỗi khi test get price:', error.message)
    return false
  }
}

/**
 * Main function
 */
async function main() {
  console.log('🚀 Setup Vault với Chainlink Fallback')
  console.log('======================================\n')

  // Validate config
  if (
    !config.vaultAddress ||
    !config.oracleAdapter ||
    !config.chainlinkFeed ||
    !config.chainlinkOracle
  ) {
    console.error('❌ Lỗi: Thiếu thông tin cấu hình')
    console.log('\n💡 Cách sử dụng:')
    console.log(
      '  node node_scripts/setup-vault-with-fallback.js --vault 0x... --adapter 0x... --chainlink 0x... --oracle 0x...'
    )
    console.log('\n🔧 Hoặc set environment variables:')
    console.log('  export VAULT_ADDRESS=0x...')
    console.log('  export ORACLE_ADAPTER=0x...')
    console.log('  export CHAINLINK_FEED=0x...')
    console.log('  export CHAINLINK_ORACLE=0x...')
    console.log('  export PRIVATE_KEY=0x...')
    process.exit(1)
  }

  console.log('📋 Cấu hình:')
  console.log(`   RPC URL: ${config.rpcUrl}`)
  console.log(`   Vault: ${config.vaultAddress}`)
  console.log(`   Oracle Adapter: ${config.oracleAdapter}`)
  console.log(`   Chainlink Feed: ${config.chainlinkFeed}`)
  console.log(`   ChainlinkOracle: ${config.chainlinkOracle}`)

  // Setup provider
  const provider = new ethers.JsonRpcProvider(config.rpcUrl)

  // Test connection
  try {
    const network = await provider.getNetwork()
    console.log(
      `\n✅ Đã kết nối đến network: ${network.name} (Chain ID: ${network.chainId})`
    )
  } catch (error) {
    console.error('\n❌ Không thể kết nối đến RPC:', error.message)
    process.exit(1)
  }

  // Check if private key provided
  const isReadOnly = !config.privateKey

  if (isReadOnly) {
    console.log('\n⚠️  Chế độ READ-ONLY (không có private key)')
    console.log('   Chỉ có thể test đọc giá, không thể setup vault\n')

    // Only test price
    await testGetPrice(provider)
  } else {
    // Setup wallet
    const wallet = new ethers.Wallet(config.privateKey, provider)
    console.log(`\n👛 Wallet: ${wallet.address}\n`)

    // Step 1: Setup vault
    const setupSuccess = await setupVault(provider, wallet)
    if (!setupSuccess) {
      console.error('\n❌ Setup vault failed!')
      process.exit(1)
    }

    // Step 2: Configure oracle
    const configSuccess = await configureOracle(provider, wallet)
    if (!configSuccess) {
      console.error('\n❌ Configure oracle failed!')
      process.exit(1)
    }

    // Step 3: Test price
    await testGetPrice(provider)
  }

  console.log('\n========================================')
  console.log('✅ HOÀN THÀNH')
  console.log('========================================\n')
}

// ========================================================================
// EXECUTION
// ========================================================================

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('\n❌ Lỗi không xử lý được:', error)
    process.exit(1)
  })

