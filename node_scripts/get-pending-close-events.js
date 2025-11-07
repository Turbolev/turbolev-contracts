/**
 * Script để lấy tất cả các events PositionPendingClose từ PositionManager
 *
 * Sử dụng:
 * node node_scripts/get-pending-close-events.js
 *
 * Hoặc với các tham số tùy chỉnh:
 * node node_scripts/get-pending-close-events.js --contract 0x... --rpc https://... --from-block 0
 */

const { ethers } = require('ethers')
require('dotenv').config()

// ========================================================================
// ABI DEFINITIONS
// ========================================================================

// ABI cho PositionManager - chỉ cần event và các enum
const POSITION_MANAGER_ABI = [
  'event PositionPendingClose(uint64 indexed positionId, address indexed user, uint256 requestTime, uint256 deadline, uint256 maxAcceptablePrice, uint8 reason, uint8 closedBy)'
]

// Enum mappings
const PendingCloseReason = {
  0: 'NONE',
  1: 'PRICE_STALE',
  2: 'PRICE_NOT_ACCEPTABLE',
  3: 'INVALID_PRICE',
  4: 'SETTLEMENT_ENGINE_NOT_SET'
}

const PositionClosedBy = {
  0: 'USER_REQUESTED',
  1: 'LIQUIDATION',
  2: 'TAKE_PROFIT',
  3: 'STOP_LOSS',
  4: 'MAX_PROFIT_REACHED'
}

// ========================================================================
// CONFIGURATION
// ========================================================================

const config = {
  rpcUrl: process.env.RPC_URL || 'https://rpc.ankr.com/eth',
  contractAddress: process.env.POSITION_MANAGER_ADDRESS || '',
  fromBlock: 0, // Block để bắt đầu query (0 = từ đầu)
  toBlock: 'latest', // Block để kết thúc query
  batchSize: 10 // Số blocks mỗi lần query (tránh quá tải)
}

// Parse command line arguments
const args = process.argv.slice(2)
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--rpc' && args[i + 1]) {
    config.rpcUrl = args[i + 1]
    i++
  } else if (args[i] === '--contract' && args[i + 1]) {
    config.contractAddress = args[i + 1]
    i++
  } else if (args[i] === '--from-block' && args[i + 1]) {
    config.fromBlock = parseInt(args[i + 1])
    i++
  } else if (args[i] === '--to-block' && args[i + 1]) {
    config.toBlock = args[i + 1] === 'latest' ? 'latest' : parseInt(args[i + 1])
    i++
  } else if (args[i] === '--batch-size' && args[i + 1]) {
    config.batchSize = parseInt(args[i + 1])
    i++
  }
}

// ========================================================================
// HELPER FUNCTIONS
// ========================================================================

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
 * Format địa chỉ để hiển thị ngắn gọn
 */
function formatAddress(address) {
  return `${address.slice(0, 6)}...${address.slice(-4)}`
}

/**
 * Format giá với 18 decimals
 */
function formatPrice(price) {
  const priceStr = ethers.formatUnits(price, 18)
  return parseFloat(priceStr).toLocaleString('en-US', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 8
  })
}

/**
 * Lấy enum name từ value
 */
function getPendingCloseReasonName(value) {
  return PendingCloseReason[value] || `UNKNOWN(${value})`
}

function getPositionClosedByName(value) {
  return PositionClosedBy[value] || `UNKNOWN(${value})`
}

/**
 * Query events theo batch để tránh quá tải
 */
async function queryEventsByBatch(contract, fromBlock, toBlock, batchSize) {
  const allEvents = []
  let currentFrom = fromBlock
  let currentTo =
    toBlock === 'latest'
      ? await contract.runner.provider.getBlockNumber()
      : toBlock

  console.log(
    `\n🔍 Bắt đầu query events từ block ${currentFrom} đến ${currentTo}...`
  )
  console.log(`   Batch size: ${batchSize} blocks\n`)

  while (currentFrom <= currentTo) {
    const batchTo = Math.min(currentFrom + batchSize - 1, currentTo)

    try {
      console.log(`   📦 Query batch: blocks ${currentFrom} - ${batchTo}`)

      const filter = contract.filters.PositionPendingClose()
      const events = await contract.queryFilter(filter, currentFrom, batchTo)

      if (events.length > 0) {
        console.log(`      ✅ Tìm thấy ${events.length} events`)
        allEvents.push(...events)
      } else {
        console.log(`      ⚪ Không có events`)
      }
    } catch (error) {
      console.error(`      ❌ Lỗi khi query batch: ${error.message}`)

      // Nếu bị lỗi, thử giảm batch size
      if (batchSize > 1000) {
        console.log(`      🔄 Thử lại với batch size nhỏ hơn...`)
        const smallerBatchSize = Math.floor(batchSize / 2)
        const partialEvents = await queryEventsByBatch(
          contract,
          currentFrom,
          batchTo,
          smallerBatchSize
        )
        allEvents.push(...partialEvents)
      } else {
        throw error
      }
    }

    currentFrom = batchTo + 1
  }

  return allEvents
}

/**
 * Lấy và hiển thị block timestamp
 */
async function getBlockTimestamp(provider, blockNumber) {
  try {
    const block = await provider.getBlock(blockNumber)
    return block ? block.timestamp : null
  } catch (error) {
    console.error(`Lỗi khi lấy block ${blockNumber}:`, error.message)
    return null
  }
}

// ========================================================================
// MAIN FUNCTIONS
// ========================================================================

/**
 * Lấy tất cả events PositionPendingClose
 */
async function getPendingCloseEvents(
  provider,
  contractAddress,
  fromBlock,
  toBlock,
  batchSize
) {
  console.log('\n========================================')
  console.log('📋 LẤY EVENTS POSITIONPENDINGCLOSE')
  console.log('========================================\n')

  try {
    const contract = new ethers.Contract(
      contractAddress,
      POSITION_MANAGER_ABI,
      provider
    )

    // Query events
    const events = await queryEventsByBatch(
      contract,
      fromBlock,
      toBlock,
      batchSize
    )

    console.log(`\n✅ Tổng cộng tìm thấy ${events.length} events\n`)

    if (events.length === 0) {
      console.log('⚪ Không có events nào được emit từ contract này.')
      return []
    }

    // Parse và hiển thị events
    console.log('========================================')
    console.log('📊 CHI TIẾT CÁC EVENTS')
    console.log('========================================\n')

    const parsedEvents = []

    for (let i = 0; i < events.length; i++) {
      const event = events[i]
      const args = event.args

      // Lấy block timestamp
      const blockTimestamp = await getBlockTimestamp(
        provider,
        event.blockNumber
      )

      const eventData = {
        eventIndex: i + 1,
        transactionHash: event.transactionHash,
        blockNumber: event.blockNumber,
        blockTimestamp: blockTimestamp,
        logIndex: event.index,
        positionId: args.positionId.toString(),
        user: args.user,
        requestTime: args.requestTime.toString(),
        deadline: args.deadline.toString(),
        maxAcceptablePrice: args.maxAcceptablePrice.toString(),
        reason: Number(args.reason),
        reasonName: getPendingCloseReasonName(Number(args.reason)),
        closedBy: Number(args.closedBy),
        closedByName: getPositionClosedByName(Number(args.closedBy))
      }

      parsedEvents.push(eventData)

      // Hiển thị event
      console.log(`Event #${i + 1}:`)
      console.log(`   Transaction: ${event.transactionHash}`)
      console.log(
        `   Block: ${event.blockNumber} (${
          blockTimestamp ? formatTimestamp(blockTimestamp) : 'N/A'
        })`
      )
      console.log(`   Position ID: ${eventData.positionId}`)
      console.log(
        `   User: ${eventData.user} (${formatAddress(eventData.user)})`
      )
      console.log(
        `   Request Time: ${formatTimestamp(eventData.requestTime)} (${
          eventData.requestTime
        })`
      )
      console.log(
        `   Deadline: ${formatTimestamp(eventData.deadline)} (${
          eventData.deadline
        })`
      )
      console.log(
        `   Max Acceptable Price: $${formatPrice(eventData.maxAcceptablePrice)}`
      )
      console.log(`   Reason: ${eventData.reasonName} (${eventData.reason})`)
      console.log(
        `   Closed By: ${eventData.closedByName} (${eventData.closedBy})`
      )
      console.log('')
    }

    return parsedEvents
  } catch (error) {
    console.error('\n❌ Lỗi khi lấy events:', error.message)
    throw error
  }
}

/**
 * Tạo summary statistics
 */
function generateSummary(events) {
  if (events.length === 0) return

  console.log('========================================')
  console.log('📈 THỐNG KÊ TỔNG HỢP')
  console.log('========================================\n')

  // Đếm theo reason
  const reasonCounts = {}
  events.forEach((event) => {
    const reason = event.reasonName
    reasonCounts[reason] = (reasonCounts[reason] || 0) + 1
  })

  console.log('📊 Phân bố theo Reason:')
  Object.entries(reasonCounts).forEach(([reason, count]) => {
    const percentage = ((count / events.length) * 100).toFixed(2)
    console.log(`   ${reason}: ${count} (${percentage}%)`)
  })

  // Đếm theo closedBy
  const closedByCounts = {}
  events.forEach((event) => {
    const closedBy = event.closedByName
    closedByCounts[closedBy] = (closedByCounts[closedBy] || 0) + 1
  })

  console.log('\n📊 Phân bố theo Closed By:')
  Object.entries(closedByCounts).forEach(([closedBy, count]) => {
    const percentage = ((count / events.length) * 100).toFixed(2)
    console.log(`   ${closedBy}: ${count} (${percentage}%)`)
  })

  // Unique users
  const uniqueUsers = new Set(events.map((e) => e.user))
  console.log(`\n👥 Số lượng users độc nhất: ${uniqueUsers.size}`)

  // Unique positions
  const uniquePositions = new Set(events.map((e) => e.positionId))
  console.log(`📍 Số lượng positions độc nhất: ${uniquePositions.size}`)

  // Time range
  if (events.length > 0) {
    const firstEvent = events[0]
    const lastEvent = events[events.length - 1]
    console.log(`\n⏰ Khoảng thời gian:`)
    console.log(
      `   Đầu tiên: ${formatTimestamp(firstEvent.blockTimestamp)} (Block ${
        firstEvent.blockNumber
      })`
    )
    console.log(
      `   Cuối cùng: ${formatTimestamp(lastEvent.blockTimestamp)} (Block ${
        lastEvent.blockNumber
      })`
    )
  }
}

/**
 * Export events ra file JSON
 */
async function exportToJson(events, filename) {
  const fs = require('fs')
  const path = require('path')

  const outputPath = path.join(__dirname, filename)

  try {
    fs.writeFileSync(outputPath, JSON.stringify(events, null, 2))
    console.log(`\n💾 Đã export ${events.length} events ra file: ${outputPath}`)
  } catch (error) {
    console.error(`\n❌ Lỗi khi export file: ${error.message}`)
  }
}

/**
 * Main function
 */
async function main() {
  console.log('🚀 Script lấy PositionPendingClose Events')
  console.log('==========================================\n')

  // Validate config
  if (!config.contractAddress) {
    console.error('❌ Lỗi: Chưa cung cấp POSITION_MANAGER_ADDRESS')
    console.log('\n📝 Cách sử dụng:')
    console.log(
      '  node node_scripts/get-pending-close-events.js --contract 0x... [options]'
    )
    console.log('\n⚙️  Options:')
    console.log(
      '  --contract <address>    Địa chỉ contract PositionManager (bắt buộc)'
    )
    console.log(
      '  --rpc <url>            RPC URL (mặc định: https://rpc.ankr.com/eth)'
    )
    console.log('  --from-block <number>  Block bắt đầu (mặc định: 0)')
    console.log('  --to-block <number>    Block kết thúc (mặc định: latest)')
    console.log('  --batch-size <number>  Số blocks mỗi batch (mặc định: 5000)')
    console.log('\n💡 Hoặc set environment variables:')
    console.log('  export POSITION_MANAGER_ADDRESS=0x...')
    console.log('  export RPC_URL=https://...')
    console.log('\n📋 Ví dụ:')
    console.log(
      '  node node_scripts/get-pending-close-events.js --contract 0x1234... --from-block 1000000'
    )
    process.exit(1)
  }

  console.log('📋 Cấu hình:')
  console.log(`   RPC URL: ${config.rpcUrl}`)
  console.log(`   Contract Address: ${config.contractAddress}`)
  console.log(`   From Block: ${config.fromBlock}`)
  console.log(`   To Block: ${config.toBlock}`)
  console.log(`   Batch Size: ${config.batchSize}`)

  // Setup provider
  const provider = new ethers.JsonRpcProvider(config.rpcUrl)

  // Test connection
  try {
    const network = await provider.getNetwork()
    const currentBlock = await provider.getBlockNumber()
    console.log(
      `\n✅ Đã kết nối đến network: ${network.name} (Chain ID: ${network.chainId})`
    )
    console.log(`   Current Block: ${currentBlock}`)
  } catch (error) {
    console.error('\n❌ Không thể kết nối đến RPC:', error.message)
    process.exit(1)
  }

  // Lấy events
  const events = await getPendingCloseEvents(
    provider,
    config.contractAddress,
    config.fromBlock,
    config.toBlock,
    config.batchSize
  )

  // Tạo summary
  if (events.length > 0) {
    generateSummary(events)

    // Export ra file JSON
    await exportToJson(events, 'pending-close-events.json')
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
    console.error(error.stack)
    process.exit(1)
  })
