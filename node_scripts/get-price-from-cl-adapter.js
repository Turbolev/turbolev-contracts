/**
 * Script để lấy giá từ Blocksense Oracle sử dụng CL Adapter
 *
 * Sử dụng:
 * node scripts/get-price-from-cl-adapter.js
 *
 * Hoặc với các tham số tùy chỉnh:
 * node scripts/get-price-from-cl-adapter.js --adapter 0x... --rpc https://...
 */

const { ethers } = require('ethers')
require('dotenv').config()

// ========================================================================
// ABI DEFINITIONS
// ========================================================================

// ABI cho CL Aggregator Adapter (Chainlink-compatible interface)
const CL_AGGREGATOR_ABI = [
  'function decimals() external view returns (uint8)',
  'function description() external view returns (string memory)',
  'function latestAnswer() external view returns (int256)',
  'function latestRound() external view returns (uint256)',
  'function latestRoundData() external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)',
  'function getRoundData(uint80 _roundId) external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)'
]

// ABI cho BlocksenseOracle
const BLOCKSENSE_ORACLE_ABI = [
  'function getPrice(address adapter) external view returns (int256 price, uint256 updatedAt)',
  'function getPriceUnsafe(address adapter) external view returns (int256 price, uint256 updatedAt)',
  'function getPriceNoOlderThan(address adapter, uint256 maxAge) external returns (int256 price, uint256 updatedAt)',
  'function maxPriceAge() external view returns (uint256)',
  'function maxPriceChangeBps() external view returns (uint256)',
  'function paused() external view returns (bool)'
]

// ========================================================================
// CONFIGURATION
// ========================================================================

// Load từ environment variables hoặc command line arguments
const config = {
  rpcUrl: process.env.RPC_URL || 'https://rpc.ankr.com/eth',
  oracleAddress: process.env.ORACLE_ADDRESS || '', // BlocksenseOracle contract address
  adapterAddress: process.env.ADAPTER_ADDRESS || '' // CL Aggregator Adapter address
}

// Parse command line arguments
const args = process.argv.slice(2)
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--rpc' && args[i + 1]) {
    config.rpcUrl = args[i + 1]
    i++
  } else if (args[i] === '--oracle' && args[i + 1]) {
    config.oracleAddress = args[i + 1]
    i++
  } else if (args[i] === '--adapter' && args[i + 1]) {
    config.adapterAddress = args[i + 1]
    i++
  }
}

// ========================================================================
// HELPER FUNCTIONS
// ========================================================================

/**
 * Format giá với decimals
 */
function formatPrice(price, decimals) {
  const priceStr = ethers.formatUnits(price, decimals)
  return parseFloat(priceStr).toLocaleString('en-US', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 8
  })
}

/**
 * Format timestamp thành readable date
 */
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

/**
 * Tính tuổi của price data (seconds)
 */
function getPriceAge(timestamp) {
  const now = Math.floor(Date.now() / 1000)
  return now - Number(timestamp)
}

// ========================================================================
// MAIN FUNCTIONS
// ========================================================================

/**
 * Lấy giá trực tiếp từ CL Aggregator Adapter
 */
async function getPriceFromAdapter(provider, adapterAddress) {
  console.log('\n========================================')
  console.log('📊 LẤY GIÁ TỪ CL AGGREGATOR ADAPTER')
  console.log('========================================\n')

  try {
    const adapter = new ethers.Contract(
      adapterAddress,
      CL_AGGREGATOR_ABI,
      provider
    )

    // Lấy thông tin feed
    console.log('🔍 Thông tin Feed:')
    const [decimals, description] = await Promise.all([
      adapter.decimals(),
      adapter.description()
    ])
    console.log(`   Description: ${description}`)
    console.log(`   Decimals: ${decimals}`)

    // Lấy latest round data
    console.log('\n📈 Dữ liệu giá mới nhất:')
    const roundData = await adapter.latestRoundData()

    const [roundId, answer, startedAt, updatedAt, answeredInRound] = roundData

    console.log(`   Round ID: ${roundId}`)
    console.log(`   Price (raw): ${answer}`)
    console.log(`   Price (formatted): $${formatPrice(answer, decimals)}`)
    console.log(`   Started At: ${formatTimestamp(startedAt)} (${startedAt})`)
    console.log(`   Updated At: ${formatTimestamp(updatedAt)} (${updatedAt})`)
    console.log(`   Answered In Round: ${answeredInRound}`)
    console.log(`   Age: ${getPriceAge(updatedAt)} giây`)

    // Kiểm tra freshness
    const age = getPriceAge(updatedAt)
    if (age > 300) {
      console.log(
        `\n⚠️  CẢNH BÁO: Giá có tuổi ${age} giây (> 5 phút), có thể đã cũ!`
      )
    } else {
      console.log(`\n✅ Giá còn fresh (${age} giây < 5 phút)`)
    }

    return {
      success: true,
      decimals,
      description,
      roundId: roundId.toString(),
      price: answer.toString(),
      priceFormatted: formatPrice(answer, decimals),
      updatedAt: updatedAt.toString(),
      age
    }
  } catch (error) {
    console.error('\n❌ Lỗi khi lấy giá từ adapter:', error.message)
    return { success: false, error: error.message }
  }
}

/**
 * Lấy giá qua BlocksenseOracle (với validation)
 */
async function getPriceFromOracle(provider, oracleAddress, adapterAddress) {
  console.log('\n========================================')
  console.log('🏛️  LẤY GIÁ QUA BLOCKSENSE ORACLE')
  console.log('========================================\n')

  try {
    const oracle = new ethers.Contract(
      oracleAddress,
      BLOCKSENSE_ORACLE_ABI,
      provider
    )

    // Lấy config của oracle
    console.log('⚙️  Cấu hình Oracle:')
    const [maxPriceAge, maxPriceChangeBps, paused] = await Promise.all([
      oracle.maxPriceAge(),
      oracle.maxPriceChangeBps(),
      oracle.paused()
    ])
    console.log(`   Max Price Age: ${maxPriceAge} giây`)
    console.log(`   Max Price Change: ${Number(maxPriceChangeBps) / 100}%`)
    console.log(`   Paused: ${paused ? '🔴 Có' : '🟢 Không'}`)

    if (paused) {
      console.log('\n⚠️  CẢNH BÁO: Oracle đang bị tạm dừng!')
      return { success: false, error: 'Oracle is paused' }
    }

    // Lấy giá với validation
    console.log('\n📊 Lấy giá (với validation):')
    const [price, updatedAt] = await oracle.getPrice(adapterAddress)

    console.log(`   Price (raw, 18 decimals): ${price}`)
    console.log(`   Price (formatted): $${formatPrice(price, 18)}`)
    console.log(`   Updated At: ${formatTimestamp(updatedAt)} (${updatedAt})`)
    console.log(`   Age: ${getPriceAge(updatedAt)} giây`)

    // Thử lấy giá unsafe (không có staleness check)
    console.log('\n📊 Lấy giá (unsafe, không có staleness check):')
    const [priceUnsafe, updatedAtUnsafe] = await oracle.getPriceUnsafe(
      adapterAddress
    )
    console.log(`   Price (formatted): $${formatPrice(priceUnsafe, 18)}`)
    console.log(`   Updated At: ${formatTimestamp(updatedAtUnsafe)}`)

    console.log('\n✅ Lấy giá thành công qua oracle!')

    return {
      success: true,
      price: price.toString(),
      priceFormatted: formatPrice(price, 18),
      updatedAt: updatedAt.toString(),
      age: getPriceAge(updatedAt),
      config: {
        maxPriceAge: maxPriceAge.toString(),
        maxPriceChangeBps: maxPriceChangeBps.toString(),
        paused
      }
    }
  } catch (error) {
    console.error('\n❌ Lỗi khi lấy giá từ oracle:', error.message)

    // Parse error message để hiện thông báo rõ ràng hơn
    if (error.message.includes('PriceStale')) {
      console.log('💡 Lý do: Giá quá cũ (vượt quá maxPriceAge)')
    } else if (error.message.includes('InvalidPrice')) {
      console.log('💡 Lý do: Giá không hợp lệ (≤ 0)')
    } else if (error.message.includes('PriceChangeTooLarge')) {
      console.log('💡 Lý do: Circuit breaker triggered - thay đổi giá quá lớn')
    }

    return { success: false, error: error.message }
  }
}

/**
 * Main function
 */
async function main() {
  console.log('🚀 Script lấy giá từ Blocksense Oracle')
  console.log('=====================================\n')

  // Validate config
  if (!config.adapterAddress) {
    console.error('❌ Lỗi: Chưa cung cấp ADAPTER_ADDRESS')
    console.log('\nCách sử dụng:')
    console.log(
      '  node scripts/get-price-from-cl-adapter.js --adapter 0x... [--oracle 0x...] [--rpc https://...]'
    )
    console.log('\nHoặc set environment variables:')
    console.log('  export ADAPTER_ADDRESS=0x...')
    console.log('  export ORACLE_ADDRESS=0x... (optional)')
    console.log('  export RPC_URL=https://... (optional)')
    process.exit(1)
  }

  console.log('📋 Cấu hình:')
  console.log(`   RPC URL: ${config.rpcUrl}`)
  console.log(`   Adapter Address: ${config.adapterAddress}`)
  if (config.oracleAddress) {
    console.log(`   Oracle Address: ${config.oracleAddress}`)
  }

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

  // Lấy giá trực tiếp từ adapter
  const adapterResult = await getPriceFromAdapter(
    provider,
    config.adapterAddress
  )

  // Nếu có oracle address, lấy giá qua oracle
  if (config.oracleAddress) {
    const oracleResult = await getPriceFromOracle(
      provider,
      config.oracleAddress,
      config.adapterAddress
    )

    // So sánh kết quả
    if (adapterResult.success && oracleResult.success) {
      console.log('\n========================================')
      console.log('📊 SO SÁNH KẾT QUẢ')
      console.log('========================================\n')
      console.log(`   Adapter Price: $${adapterResult.priceFormatted}`)
      console.log(`   Oracle Price:  $${oracleResult.priceFormatted}`)
      console.log(`   Cả 2 đều cho giá sau khi scale lên 18 decimals`)
    }
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
