/**
 * Script để lấy giá trực tiếp từ Chainlink Price Feed
 *
 * Sử dụng:
 * node node_scripts/get-price-from-chainlink.js
 *
 * Hoặc với các tham số tùy chỉnh:
 * node node_scripts/get-price-from-chainlink.js --feed 0x... --rpc https://...
 */

const { ethers } = require('ethers')
require('dotenv').config()

// ========================================================================
// ABI DEFINITIONS
// ========================================================================

// ABI cho Chainlink Aggregator V3
const CHAINLINK_AGGREGATOR_V3_ABI = [
  'function decimals() external view returns (uint8)',
  'function description() external view returns (string memory)',
  'function version() external view returns (uint256)',
  'function latestAnswer() external view returns (int256)',
  'function latestRound() external view returns (uint256)',
  'function latestTimestamp() external view returns (uint256)',
  'function latestRoundData() external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)',
  'function getRoundData(uint80 _roundId) external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)',
  'function phaseId() external view returns (uint16)',
  'function aggregator() external view returns (address)'
]

// ========================================================================
// POPULAR CHAINLINK FEEDS
// ========================================================================

const POPULAR_FEEDS = {
  ethereum: {
    // Ethereum Mainnet
    'ETH/USD': '0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419',
    'BTC/USD': '0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c',
    'USDC/USD': '0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6',
    'USDT/USD': '0x3E7d1eAB13ad0104d2750B8863b489D65364e32D',
    'DAI/USD': '0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9',
    'LINK/USD': '0x2c1d072e956AFFC0D435Cb7AC38EF18d24d9127c',
    'MATIC/USD': '0x7bAC85A8a13A4BcD8abb3eB7d6b4d632c5a57676'
  },
  polygon: {
    // Polygon Mainnet
    'MATIC/USD': '0xAB594600376Ec9fD91F8e885dADF0CE036862dE0',
    'ETH/USD': '0xF9680D99D6C9589e2a93a78A04A279e509205945',
    'BTC/USD': '0xc907E116054Ad103354f2D350FD2514433D57F6f',
    'USDC/USD': '0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7',
    'USDT/USD': '0x0A6513e40db6EB1b165753AD52E80663aeA50545'
  },
  arbitrum: {
    // Arbitrum One
    'ETH/USD': '0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612',
    'BTC/USD': '0x6ce185860a4963106506C203335A2910413708e9',
    'USDC/USD': '0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3',
    'USDT/USD': '0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7',
    'ARB/USD': '0xb2A824043730FE05F3DA2efaFa1CBbe83fa548D6'
  },
  base: {
    // Base Mainnet
    'ETH/USD': '0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70',
    'BTC/USD': '0x64c911996D3c6aC71f9b455B1E8E7266BcbD848F',
    'USDC/USD': '0x7e860098F58bBFC8648a4311b374B1D669a2bc6B'
  }
}

// ========================================================================
// CONFIGURATION
// ========================================================================

// Load từ environment variables hoặc command line arguments
const config = {
  rpcUrl: process.env.RPC_URL || 'https://rpc.ankr.com/eth',
  feedAddress: process.env.FEED_ADDRESS || '', // Chainlink Price Feed address
  network: process.env.NETWORK || 'ethereum'
}

// Parse command line arguments
const args = process.argv.slice(2)
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--rpc' && args[i + 1]) {
    config.rpcUrl = args[i + 1]
    i++
  } else if (args[i] === '--feed' && args[i + 1]) {
    config.feedAddress = args[i + 1]
    i++
  } else if (args[i] === '--network' && args[i + 1]) {
    config.network = args[i + 1]
    i++
  } else if (args[i] === '--list') {
    listPopularFeeds()
    process.exit(0)
  }
}

// ========================================================================
// HELPER FUNCTIONS
// ========================================================================

/**
 * Hiển thị danh sách các feed phổ biến
 */
function listPopularFeeds() {
  console.log('\n📋 DANH SÁCH CHAINLINK FEEDS PHỔ BIẾN')
  console.log('=====================================\n')

  for (const [network, feeds] of Object.entries(POPULAR_FEEDS)) {
    console.log(`\n🌐 ${network.toUpperCase()}:`)
    for (const [pair, address] of Object.entries(feeds)) {
      console.log(`   ${pair.padEnd(12)} : ${address}`)
    }
  }

  console.log('\n💡 Sử dụng:')
  console.log(
    '   node node_scripts/get-price-from-chainlink.js --feed <address> --rpc <rpc_url>\n'
  )
}

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

/**
 * Format duration (giây) thành readable string
 */
function formatDuration(seconds) {
  if (seconds < 60) return `${seconds} giây`
  if (seconds < 3600) return `${Math.floor(seconds / 60)} phút`
  if (seconds < 86400) return `${Math.floor(seconds / 3600)} giờ`
  return `${Math.floor(seconds / 86400)} ngày`
}

// ========================================================================
// MAIN FUNCTIONS
// ========================================================================

/**
 * Lấy thông tin cơ bản của feed
 */
async function getFeedInfo(provider, feedAddress) {
  console.log('\n========================================')
  console.log('📊 THÔNG TIN CHAINLINK PRICE FEED')
  console.log('========================================\n')

  try {
    const feed = new ethers.Contract(
      feedAddress,
      CHAINLINK_AGGREGATOR_V3_ABI,
      provider
    )

    console.log('🔍 Đang lấy thông tin feed...\n')

    // Lấy thông tin cơ bản
    const [decimals, description, version] = await Promise.all([
      feed.decimals().catch(() => null),
      feed.description().catch(() => null),
      feed.version().catch(() => null)
    ])

    console.log('📋 Thông tin chung:')
    console.log(`   Feed Address: ${feedAddress}`)
    if (description) console.log(`   Description: ${description}`)
    if (decimals !== null) console.log(`   Decimals: ${decimals}`)
    if (version !== null) console.log(`   Version: ${version}`)

    // Thử lấy thông tin aggregator (nếu là proxy)
    try {
      const aggregatorAddress = await feed.aggregator()
      console.log(`   Aggregator: ${aggregatorAddress}`)
      console.log(`   Type: Proxy Contract`)
    } catch {
      console.log(`   Type: Direct Aggregator`)
    }

    return { success: true, decimals, description }
  } catch (error) {
    console.error('\n❌ Lỗi khi lấy thông tin feed:', error.message)
    return { success: false, error: error.message }
  }
}

/**
 * Lấy dữ liệu giá mới nhất
 */
async function getLatestPrice(provider, feedAddress) {
  console.log('\n========================================')
  console.log('📈 DỮ LIỆU GIÁ MỚI NHẤT')
  console.log('========================================\n')

  try {
    const feed = new ethers.Contract(
      feedAddress,
      CHAINLINK_AGGREGATOR_V3_ABI,
      provider
    )

    // Lấy decimals
    const decimals = await feed.decimals()

    console.log('🔍 Đang lấy dữ liệu giá mới nhất...\n')

    // Lấy latest round data
    const [roundId, answer, startedAt, updatedAt, answeredInRound] =
      await feed.latestRoundData()

    console.log('📊 Dữ liệu Round:')
    console.log(`   Round ID: ${roundId}`)
    console.log(`   Answered In Round: ${answeredInRound}`)

    // Kiểm tra round data consistency
    if (answeredInRound < roundId) {
      console.log(
        `   ⚠️  CẢNH BÁO: answeredInRound (${answeredInRound}) < roundId (${roundId})`
      )
      console.log(`   → Dữ liệu có thể chưa được cập nhật đầy đủ`)
    } else {
      console.log(`   ✅ Round data nhất quán`)
    }

    console.log('\n💰 Giá:')
    console.log(`   Raw Value: ${answer}`)
    console.log(`   Formatted: $${formatPrice(answer, decimals)}`)

    // Kiểm tra giá hợp lệ
    if (answer <= 0) {
      console.log(`   ⚠️  CẢNH BÁO: Giá không hợp lệ (≤ 0)`)
    }

    console.log('\n⏰ Thời gian:')
    console.log(`   Started At: ${formatTimestamp(startedAt)}`)
    console.log(`   Updated At: ${formatTimestamp(updatedAt)}`)
    console.log(`   Timestamp: ${updatedAt}`)

    const age = getPriceAge(updatedAt)
    console.log(`\n⌛ Độ tươi của dữ liệu:`)
    console.log(`   Age: ${formatDuration(age)} (${age} giây)`)

    // Đánh giá freshness
    if (age > 86400) {
      // > 1 ngày
      console.log(`   🔴 RẤT CŨ: Dữ liệu quá cũ (> 1 ngày)`)
    } else if (age > 3600) {
      // > 1 giờ
      console.log(`   🟡 CŨ: Dữ liệu hơi cũ (> 1 giờ)`)
    } else if (age > 300) {
      // > 5 phút
      console.log(`   🟢 KHÁI CHẤP: Dữ liệu chấp nhận được (> 5 phút)`)
    } else {
      console.log(`   ✅ TƯƠI: Dữ liệu rất mới (< 5 phút)`)
    }

    return {
      success: true,
      decimals,
      roundId: roundId.toString(),
      answer: answer.toString(),
      answerFormatted: formatPrice(answer, decimals),
      updatedAt: updatedAt.toString(),
      age
    }
  } catch (error) {
    console.error('\n❌ Lỗi khi lấy giá:', error.message)

    // Parse error để đưa ra gợi ý
    if (error.message.includes('invalid address')) {
      console.log('💡 Gợi ý: Kiểm tra lại địa chỉ feed')
    } else if (error.message.includes('could not decode result data')) {
      console.log(
        '💡 Gợi ý: Contract có thể không phải là Chainlink Price Feed'
      )
    } else if (error.message.includes('call revert exception')) {
      console.log('💡 Gợi ý: Feed có thể đã bị deprecate hoặc không hoạt động')
    }

    return { success: false, error: error.message }
  }
}

/**
 * Lấy dữ liệu historical rounds
 */
async function getHistoricalData(provider, feedAddress, numRounds = 5) {
  console.log('\n========================================')
  console.log(`📊 ${numRounds} ROUND GẦN NHẤT`)
  console.log('========================================\n')

  try {
    const feed = new ethers.Contract(
      feedAddress,
      CHAINLINK_AGGREGATOR_V3_ABI,
      provider
    )

    const decimals = await feed.decimals()
    const latestRoundId = await feed.latestRound()

    console.log(`🔍 Đang lấy dữ liệu từ round ${latestRoundId}...\n`)

    const rounds = []
    for (let i = 0; i < numRounds; i++) {
      const roundId = latestRoundId - BigInt(i)
      if (roundId <= 0) break

      try {
        const [, answer, , updatedAt] = await feed.getRoundData(roundId)
        rounds.push({
          roundId,
          answer,
          updatedAt,
          age: getPriceAge(updatedAt)
        })
      } catch {
        // Round không tồn tại hoặc lỗi, skip
        continue
      }
    }

    if (rounds.length === 0) {
      console.log('⚠️  Không lấy được dữ liệu historical rounds')
      return { success: false, error: 'No historical data' }
    }

    console.log('📈 Lịch sử giá:\n')
    console.log(
      '   Round ID'.padEnd(20) +
        'Price'.padEnd(20) +
        'Updated At'.padEnd(25) +
        'Age'
    )
    console.log('   ' + '-'.repeat(85))

    for (const round of rounds) {
      const roundIdStr = round.roundId.toString().padEnd(20)
      const priceStr = `$${formatPrice(round.answer, decimals)}`.padEnd(20)
      const timeStr = formatTimestamp(round.updatedAt).padEnd(25)
      const ageStr = formatDuration(round.age)

      console.log(`   ${roundIdStr}${priceStr}${timeStr}${ageStr}`)
    }

    // Tính volatility
    if (rounds.length >= 2) {
      console.log('\n📊 Phân tích biến động:')

      const prices = rounds.map((r) =>
        parseFloat(ethers.formatUnits(r.answer, decimals))
      )
      const maxPrice = Math.max(...prices)
      const minPrice = Math.min(...prices)
      const avgPrice = prices.reduce((a, b) => a + b, 0) / prices.length
      const volatility = ((maxPrice - minPrice) / avgPrice) * 100

      console.log(`   Giá cao nhất: $${maxPrice.toFixed(2)}`)
      console.log(`   Giá thấp nhất: $${minPrice.toFixed(2)}`)
      console.log(`   Giá trung bình: $${avgPrice.toFixed(2)}`)
      console.log(`   Độ biến động: ${volatility.toFixed(2)}%`)
    }

    return { success: true, rounds: rounds.length }
  } catch (error) {
    console.error('\n❌ Lỗi khi lấy dữ liệu historical:', error.message)
    return { success: false, error: error.message }
  }
}

/**
 * Kiểm tra sức khỏe của feed
 */
async function checkFeedHealth(provider, feedAddress) {
  console.log('\n========================================')
  console.log('🏥 KIỂM TRA SỨC KHỎE FEED')
  console.log('========================================\n')

  const issues = []
  const warnings = []

  try {
    const feed = new ethers.Contract(
      feedAddress,
      CHAINLINK_AGGREGATOR_V3_ABI,
      provider
    )

    // Kiểm tra latest data
    const [roundId, answer, , updatedAt, answeredInRound] =
      await feed.latestRoundData()

    // Check 1: Round consistency
    if (answeredInRound < roundId) {
      issues.push(
        `Round không nhất quán: answeredInRound (${answeredInRound}) < roundId (${roundId})`
      )
    }

    // Check 2: Price validity
    if (answer <= 0) {
      issues.push(`Giá không hợp lệ: ${answer} <= 0`)
    }

    // Check 3: Staleness
    const age = getPriceAge(updatedAt)
    if (age > 86400) {
      issues.push(`Dữ liệu quá cũ: ${formatDuration(age)} (> 1 ngày)`)
    } else if (age > 3600) {
      warnings.push(`Dữ liệu hơi cũ: ${formatDuration(age)} (> 1 giờ)`)
    }

    // Check 4: Try to get previous round
    try {
      const prevRoundId = roundId - BigInt(1)
      const [, prevAnswer] = await feed.getRoundData(prevRoundId)

      // Check for suspicious price jumps (>50%)
      const priceChange =
        Math.abs(Number(answer - prevAnswer)) / Number(prevAnswer)
      if (priceChange > 0.5) {
        warnings.push(
          `Thay đổi giá lớn giữa 2 round: ${(priceChange * 100).toFixed(2)}%`
        )
      }
    } catch {
      warnings.push('Không thể lấy dữ liệu round trước đó để so sánh')
    }

    // Summary
    console.log('📋 Kết quả kiểm tra:\n')

    if (issues.length === 0 && warnings.length === 0) {
      console.log('   ✅ KHỎE MẠNH: Feed hoạt động tốt, không có vấn đề')
    } else {
      if (issues.length > 0) {
        console.log('   🔴 VẤN ĐỀ NGHIÊM TRỌNG:')
        issues.forEach((issue, i) => {
          console.log(`      ${i + 1}. ${issue}`)
        })
      }

      if (warnings.length > 0) {
        console.log(`\n   🟡 CẢNH BÁO:`)
        warnings.forEach((warning, i) => {
          console.log(`      ${i + 1}. ${warning}`)
        })
      }
    }

    return {
      success: true,
      healthy: issues.length === 0,
      issues,
      warnings
    }
  } catch (error) {
    console.error('\n❌ Lỗi khi kiểm tra sức khỏe:', error.message)
    return { success: false, error: error.message }
  }
}

/**
 * Main function
 */
async function main() {
  console.log('🚀 Script lấy giá từ Chainlink Price Feed')
  console.log('==========================================\n')

  // Validate config
  if (!config.feedAddress) {
    console.error('❌ Lỗi: Chưa cung cấp FEED_ADDRESS')
    console.log('\n💡 Cách sử dụng:')
    console.log(
      '   node node_scripts/get-price-from-chainlink.js --feed 0x... [--rpc https://...]'
    )
    console.log('\n📋 Xem danh sách feeds phổ biến:')
    console.log('   node node_scripts/get-price-from-chainlink.js --list')
    console.log('\n🔧 Hoặc set environment variables:')
    console.log('   export FEED_ADDRESS=0x...')
    console.log('   export RPC_URL=https://... (optional)')
    process.exit(1)
  }

  console.log('📋 Cấu hình:')
  console.log(`   RPC URL: ${config.rpcUrl}`)
  console.log(`   Feed Address: ${config.feedAddress}`)

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

  // Lấy thông tin feed
  const infoResult = await getFeedInfo(provider, config.feedAddress)
  if (!infoResult.success) {
    console.log('\n⚠️  Không thể lấy thông tin feed, tiếp tục thử lấy giá...')
  }

  // Lấy giá mới nhất
  const priceResult = await getLatestPrice(provider, config.feedAddress)
  if (!priceResult.success) {
    console.error('\n❌ Không thể lấy giá từ feed')
    process.exit(1)
  }

  // Lấy dữ liệu historical
  await getHistoricalData(provider, config.feedAddress, 10)

  // Kiểm tra sức khỏe
  await checkFeedHealth(provider, config.feedAddress)

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

