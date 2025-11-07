/**
 * Script để test price fallback mechanism
 *
 * Test scenarios:
 * 1. Blocksense working → Should use Blocksense
 * 2. Blocksense stale → Should fallback to Chainlink
 * 3. Both sources available → Compare prices
 * 4. Monitor fallback events
 *
 * Usage:
 * node node_scripts/test-price-fallback.js
 */

const { ethers } = require('ethers')
require('dotenv').config()

// ========================================================================
// ABI DEFINITIONS
// ========================================================================

const SETTLEMENT_ENGINE_ABI = [
  'function getSettlementPrice(address projectToken, uint256 maxAge) external view returns (uint256 closePrice, uint256 publishTime)',
  'function chainlinkOracle() external view returns (address)',
  'function blocksenseOracle() external view returns (address)',
  'event PriceFallbackUsed(address indexed projectToken, address indexed adapter, address indexed chainlinkFeed, string reason)'
]

const VAULT_MANAGER_ABI = [
  'function getVault(address projectToken) external view returns (address)'
]

const ASSET_VAULT_ABI = [
  'function oracleAdapter() external view returns (address)',
  'function chainlinkFeed() external view returns (address)'
]

const BLOCKSENSE_ORACLE_ABI = [
  'function getPrice(address adapter) external view returns (int256 price, uint256 updatedAt)'
]

const CHAINLINK_ORACLE_ABI = [
  'function getPrice(address adapter) external view returns (int256 price, uint256 updatedAt, bool usedFallback)',
  'function getPriceBothSources(address adapter) external view returns (int256 blocksensePrice, uint256 blocksenseUpdatedAt, bool blocksenseSuccess, int256 chainlinkPrice, uint256 chainlinkUpdatedAt, bool chainlinkSuccess)',
  'function hasFallback(address adapter) external view returns (bool, address)'
]

// ========================================================================
// CONFIGURATION
// ========================================================================

const config = {
  rpcUrl: process.env.RPC_URL || 'https://rpc.ankr.com/eth',
  settlementEngine: process.env.SETTLEMENT_ENGINE || '',
  vaultManager: process.env.VAULT_MANAGER || '',
  projectToken: process.env.PROJECT_TOKEN || '',
  maxAge: parseInt(process.env.MAX_AGE || '300')
}

// Parse command line arguments
const args = process.argv.slice(2)
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--rpc' && args[i + 1]) {
    config.rpcUrl = args[i + 1]
    i++
  } else if (args[i] === '--settlement' && args[i + 1]) {
    config.settlementEngine = args[i + 1]
    i++
  } else if (args[i] === '--vault-manager' && args[i + 1]) {
    config.vaultManager = args[i + 1]
    i++
  } else if (args[i] === '--token' && args[i + 1]) {
    config.projectToken = args[i + 1]
    i++
  } else if (args[i] === '--max-age' && args[i + 1]) {
    config.maxAge = parseInt(args[i + 1])
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

function getPriceAge(timestamp) {
  const now = Math.floor(Date.now() / 1000)
  return now - Number(timestamp)
}

// ========================================================================
// TEST FUNCTIONS
// ========================================================================

/**
 * Test 1: Get configuration
 */
async function testConfiguration(provider) {
  console.log('\n========================================')
  console.log('📋 TEST 1: CONFIGURATION')
  console.log('========================================\n')

  try {
    const settlementEngine = new ethers.Contract(
      config.settlementEngine,
      SETTLEMENT_ENGINE_ABI,
      provider
    )

    const vaultManager = new ethers.Contract(
      config.vaultManager,
      VAULT_MANAGER_ABI,
      provider
    )

    // Get oracle addresses
    console.log('🔍 Oracle Configuration:')
    const blocksenseOracle = await settlementEngine.blocksenseOracle()
    const chainlinkOracle = await settlementEngine.chainlinkOracle()

    console.log(`   Blocksense Oracle: ${blocksenseOracle}`)
    console.log(`   Chainlink Oracle:  ${chainlinkOracle}`)

    if (chainlinkOracle === ethers.ZeroAddress) {
      console.log('   ⚠️  WARNING: No ChainlinkOracle configured!')
    } else {
      console.log('   ✅ ChainlinkOracle configured')
    }

    // Get vault info
    console.log('\n🏦 Vault Configuration:')
    const vaultAddr = await vaultManager.getVault(config.projectToken)
    console.log(`   Vault Address: ${vaultAddr}`)

    if (vaultAddr === ethers.ZeroAddress) {
      console.log('   ❌ No vault found for project token!')
      return false
    }

    const vault = new ethers.Contract(vaultAddr, ASSET_VAULT_ABI, provider)
    const adapter = await vault.oracleAdapter()
    const chainlinkFeed = await vault.chainlinkFeed()

    console.log(`   Oracle Adapter: ${adapter}`)
    console.log(`   Chainlink Feed: ${chainlinkFeed}`)

    if (adapter === ethers.ZeroAddress) {
      console.log('   ⚠️  WARNING: No oracle adapter configured!')
    }

    if (chainlinkFeed === ethers.ZeroAddress) {
      console.log('   ⚠️  WARNING: No Chainlink feed configured!')
    } else {
      console.log('   ✅ Chainlink feed configured (fallback available)')
    }

    return {
      blocksenseOracle,
      chainlinkOracle,
      vaultAddr,
      adapter,
      chainlinkFeed
    }
  } catch (error) {
    console.error('\n❌ Error:', error.message)
    return null
  }
}

/**
 * Test 2: Get price from SettlementEngine
 */
async function testGetSettlementPrice(provider) {
  console.log('\n========================================')
  console.log('📊 TEST 2: GET SETTLEMENT PRICE')
  console.log('========================================\n')

  try {
    const settlementEngine = new ethers.Contract(
      config.settlementEngine,
      SETTLEMENT_ENGINE_ABI,
      provider
    )

    console.log(`🔍 Getting price for: ${config.projectToken}`)
    console.log(`   Max Age: ${config.maxAge} seconds\n`)

    const [closePrice, publishTime] = await settlementEngine.getSettlementPrice(
      config.projectToken,
      config.maxAge
    )

    console.log('✅ Price Retrieved:')
    console.log(`   Price: $${formatPrice(closePrice, 18)}`)
    console.log(`   Raw Value: ${closePrice}`)
    console.log(`   Publish Time: ${formatTimestamp(publishTime)}`)
    console.log(`   Timestamp: ${publishTime}`)
    console.log(`   Age: ${getPriceAge(publishTime)} seconds`)

    const age = getPriceAge(publishTime)
    if (age > config.maxAge) {
      console.log(`   ⚠️  WARNING: Price age (${age}s) > maxAge (${config.maxAge}s)`)
    } else {
      console.log(`   ✅ Price is fresh (${age}s < ${config.maxAge}s)`)
    }

    return { closePrice, publishTime }
  } catch (error) {
    console.error('\n❌ Failed to get price:', error.message)
    
    if (error.message.includes('InvalidOraclePrice')) {
      console.log('   💡 Reason: Both Blocksense and Chainlink failed')
    }
    
    return null
  }
}

/**
 * Test 3: Compare both sources
 */
async function testCompareSources(provider, configData) {
  console.log('\n========================================')
  console.log('🔄 TEST 3: COMPARE PRICE SOURCES')
  console.log('========================================\n')

  if (!configData || !configData.chainlinkOracle || !configData.adapter) {
    console.log('⚠️  Skipping: Configuration not available')
    return
  }

  try {
    const chainlinkOracle = new ethers.Contract(
      configData.chainlinkOracle,
      CHAINLINK_ORACLE_ABI,
      provider
    )

    const [
      blocksensePrice,
      blocksenseUpdatedAt,
      blocksenseSuccess,
      chainlinkPrice,
      chainlinkUpdatedAt,
      chainlinkSuccess
    ] = await chainlinkOracle.getPriceBothSources(configData.adapter)

    console.log('📊 Blocksense Oracle:')
    if (blocksenseSuccess) {
      console.log(`   Status: ✅ SUCCESS`)
      console.log(`   Price: $${formatPrice(blocksensePrice, 18)}`)
      console.log(`   Updated: ${formatTimestamp(blocksenseUpdatedAt)}`)
      console.log(`   Age: ${getPriceAge(blocksenseUpdatedAt)} seconds`)
    } else {
      console.log(`   Status: ❌ FAILED`)
    }

    console.log('\n📊 Chainlink Oracle:')
    if (chainlinkSuccess) {
      console.log(`   Status: ✅ SUCCESS`)
      console.log(`   Price: $${formatPrice(chainlinkPrice, 18)}`)
      console.log(`   Updated: ${formatTimestamp(chainlinkUpdatedAt)}`)
      console.log(`   Age: ${getPriceAge(chainlinkUpdatedAt)} seconds`)
    } else {
      console.log(`   Status: ❌ FAILED or NOT CONFIGURED`)
    }

    if (blocksenseSuccess && chainlinkSuccess) {
      console.log('\n📈 Price Comparison:')
      const diff = Number(blocksensePrice) - Number(chainlinkPrice)
      const diffPercent =
        (Math.abs(diff) / Number(blocksensePrice)) * 100

      console.log(`   Blocksense: $${formatPrice(blocksensePrice, 18)}`)
      console.log(`   Chainlink:  $${formatPrice(chainlinkPrice, 18)}`)
      console.log(`   Difference: $${formatPrice(Math.abs(diff), 18)} (${diffPercent.toFixed(4)}%)`)

      if (diffPercent > 1) {
        console.log(`   ⚠️  WARNING: Large price divergence (> 1%)!`)
      } else {
        console.log(`   ✅ Prices are well aligned (< 1%)`)
      }
    }
  } catch (error) {
    console.error('\n❌ Error comparing sources:', error.message)
  }
}

/**
 * Test 4: Listen to fallback events
 */
async function testListenFallbackEvents(provider) {
  console.log('\n========================================')
  console.log('👂 TEST 4: LISTEN TO FALLBACK EVENTS')
  console.log('========================================\n')

  try {
    const settlementEngine = new ethers.Contract(
      config.settlementEngine,
      SETTLEMENT_ENGINE_ABI,
      provider
    )

    console.log('🔍 Listening for PriceFallbackUsed events...')
    console.log('   (Checking last 1000 blocks)\n')

    const currentBlock = await provider.getBlockNumber()
    const fromBlock = currentBlock - 1000

    const filter = settlementEngine.filters.PriceFallbackUsed()
    const events = await settlementEngine.queryFilter(filter, fromBlock, currentBlock)

    if (events.length === 0) {
      console.log('✅ No fallback events found in last 1000 blocks')
      console.log('   → Blocksense Oracle working normally')
    } else {
      console.log(`⚠️  Found ${events.length} fallback event(s):\n`)

      events.forEach((event, i) => {
        console.log(`   Event ${i + 1}:`)
        console.log(`   Project Token: ${event.args.projectToken}`)
        console.log(`   Adapter: ${event.args.adapter}`)
        console.log(`   Chainlink Feed: ${event.args.chainlinkFeed}`)
        console.log(`   Reason: ${event.args.reason}`)
        console.log(`   Block: ${event.blockNumber}`)
        console.log()
      })

      console.log('   💡 Consider investigating Blocksense Oracle health')
    }

    return events
  } catch (error) {
    console.error('\n❌ Error listening to events:', error.message)
    return []
  }
}

/**
 * Main function
 */
async function main() {
  console.log('🚀 Test Price Fallback Mechanism')
  console.log('==================================\n')

  // Validate config
  if (!config.settlementEngine || !config.vaultManager || !config.projectToken) {
    console.error('❌ Error: Missing configuration')
    console.log('\n💡 Usage:')
    console.log(
      '  node node_scripts/test-price-fallback.js --settlement 0x... --vault-manager 0x... --token 0x...'
    )
    console.log('\n🔧 Or set environment variables:')
    console.log('  export SETTLEMENT_ENGINE=0x...')
    console.log('  export VAULT_MANAGER=0x...')
    console.log('  export PROJECT_TOKEN=0x...')
    console.log('  export MAX_AGE=300')
    process.exit(1)
  }

  console.log('📋 Configuration:')
  console.log(`   RPC URL: ${config.rpcUrl}`)
  console.log(`   Settlement Engine: ${config.settlementEngine}`)
  console.log(`   Vault Manager: ${config.vaultManager}`)
  console.log(`   Project Token: ${config.projectToken}`)
  console.log(`   Max Age: ${config.maxAge} seconds`)

  // Setup provider
  const provider = new ethers.JsonRpcProvider(config.rpcUrl)

  // Test connection
  try {
    const network = await provider.getNetwork()
    console.log(
      `\n✅ Connected to: ${network.name} (Chain ID: ${network.chainId})`
    )
  } catch (error) {
    console.error('\n❌ Cannot connect to RPC:', error.message)
    process.exit(1)
  }

  // Run tests
  const configData = await testConfiguration(provider)
  await testGetSettlementPrice(provider)
  
  if (configData) {
    await testCompareSources(provider, configData)
  }
  
  await testListenFallbackEvents(provider)

  console.log('\n========================================')
  console.log('✅ ALL TESTS COMPLETED')
  console.log('========================================\n')
}

// ========================================================================
// EXECUTION
// ========================================================================

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('\n❌ Unhandled error:', error)
    process.exit(1)
  })

