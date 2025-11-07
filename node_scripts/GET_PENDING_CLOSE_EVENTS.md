# Script Lấy Events PositionPendingClose

Script này được sử dụng để query và phân tích tất cả các events `PositionPendingClose` đã được emit từ contract `PositionManager`.

## Cài đặt

```bash
cd node_scripts
npm install
```

## Sử dụng

### 1. Sử dụng với Environment Variables

Tạo file `.env` trong thư mục `node_scripts`:

```env
POSITION_MANAGER_ADDRESS=0x1234567890123456789012345678901234567890
RPC_URL=https://rpc.ankr.com/eth
```

Sau đó chạy:

```bash
npm run get-pending-close
```

### 2. Sử dụng với Command Line Arguments

```bash
node get-pending-close-events.js --contract 0x... --rpc https://... [options]
```

### 3. Các Options

| Option | Mô tả | Mặc định |
|--------|-------|----------|
| `--contract` | Địa chỉ contract PositionManager (bắt buộc) | - |
| `--rpc` | RPC URL | `https://rpc.ankr.com/eth` |
| `--from-block` | Block bắt đầu query | `0` |
| `--to-block` | Block kết thúc query | `latest` |
| `--batch-size` | Số blocks mỗi lần query | `5000` |

## Ví dụ

### Lấy tất cả events từ đầu đến hiện tại

```bash
node get-pending-close-events.js \
  --contract 0x1234567890123456789012345678901234567890 \
  --rpc https://rpc.ankr.com/eth
```

### Lấy events từ block cụ thể

```bash
node get-pending-close-events.js \
  --contract 0x1234567890123456789012345678901234567890 \
  --from-block 1000000 \
  --rpc https://rpc.ankr.com/eth
```

### Lấy events trong khoảng block nhất định

```bash
node get-pending-close-events.js \
  --contract 0x1234567890123456789012345678901234567890 \
  --from-block 1000000 \
  --to-block 2000000 \
  --rpc https://rpc.ankr.com/eth
```

### Sử dụng batch size nhỏ hơn cho RPC có rate limit

```bash
node get-pending-close-events.js \
  --contract 0x1234567890123456789012345678901234567890 \
  --batch-size 1000 \
  --rpc https://rpc.ankr.com/eth
```

## Output

Script sẽ hiển thị:

### 1. Thông tin kết nối
- Network name và Chain ID
- Current block number

### 2. Chi tiết từng event
Mỗi event sẽ hiển thị:
- Transaction hash
- Block number và timestamp
- Position ID
- User address
- Request time và deadline
- Max acceptable price
- Reason (lý do pending)
- Closed by (ai yêu cầu đóng)

### 3. Thống kê tổng hợp
- Phân bố theo Reason
- Phân bố theo Closed By
- Số lượng users độc nhất
- Số lượng positions độc nhất
- Khoảng thời gian của events

### 4. File JSON Export
Tất cả events sẽ được export ra file `pending-close-events.json` trong cùng thư mục.

## Event Structure

Event `PositionPendingClose` có cấu trúc như sau:

```solidity
event PositionPendingClose(
    uint64 indexed positionId,
    address indexed user,
    uint256 requestTime,
    uint256 deadline,
    uint256 maxAcceptablePrice,
    PendingCloseReason reason,
    PositionClosedBy closedBy
);
```

### PendingCloseReason

| Value | Name | Mô tả |
|-------|------|-------|
| 0 | NONE | Default/not set |
| 1 | PRICE_STALE | Oracle price is stale |
| 2 | PRICE_NOT_ACCEPTABLE | Price doesn't meet maxAcceptablePrice |
| 3 | INVALID_PRICE | Price is invalid (zero or negative) |
| 4 | SETTLEMENT_ENGINE_NOT_SET | Settlement engine address not set |

### PositionClosedBy

| Value | Name | Mô tả |
|-------|------|-------|
| 0 | USER_REQUESTED | User requested close |
| 1 | LIQUIDATION | Position liquidated |
| 2 | TAKE_PROFIT | Take profit requested |
| 3 | STOP_LOSS | Stop loss requested |
| 4 | MAX_PROFIT_REACHED | Max profit reached |

## Lưu ý

### 1. Rate Limiting
- Nếu RPC endpoint của bạn có rate limit, hãy giảm `--batch-size`
- Mặc định là 5000 blocks mỗi batch
- Nếu gặp lỗi, script sẽ tự động thử lại với batch size nhỏ hơn

### 2. Large Block Ranges
- Query từ block 0 có thể mất thời gian lâu trên mainnet
- Nên sử dụng `--from-block` với giá trị gần hơn nếu biết contract được deploy gần đây
- Có thể chia nhỏ queries bằng cách sử dụng `--from-block` và `--to-block`

### 3. Memory
- Nếu có quá nhiều events, có thể gặp vấn đề về memory
- Trong trường hợp này, hãy chia nhỏ queries theo block range

## Troubleshooting

### Lỗi: "Cannot connect to RPC"
- Kiểm tra RPC URL có đúng không
- Kiểm tra kết nối internet
- Thử RPC endpoint khác

### Lỗi: "Response too large" hoặc timeout
- Giảm `--batch-size` xuống 1000 hoặc 500
- Chia nhỏ query bằng cách sử dụng `--to-block`

### Không tìm thấy events
- Kiểm tra địa chỉ contract có đúng không
- Kiểm tra `--from-block` có đúng không
- Có thể contract chưa emit event nào

## Ví dụ Output

```
🚀 Script lấy PositionPendingClose Events
==========================================

📋 Cấu hình:
   RPC URL: https://rpc.ankr.com/eth
   Contract Address: 0x1234567890123456789012345678901234567890
   From Block: 1000000
   To Block: latest
   Batch Size: 5000

✅ Đã kết nối đến network: mainnet (Chain ID: 1)
   Current Block: 18500000

========================================
📋 LẤY EVENTS POSITIONPENDINGCLOSE
========================================

🔍 Bắt đầu query events từ block 1000000 đến 18500000...
   Batch size: 5000 blocks

   📦 Query batch: blocks 1000000 - 1004999
      ✅ Tìm thấy 5 events
   📦 Query batch: blocks 1005000 - 1009999
      ⚪ Không có events
   ...

✅ Tổng cộng tìm thấy 42 events

========================================
📊 CHI TIẾT CÁC EVENTS
========================================

Event #1:
   Transaction: 0xabc...def
   Block: 1002345 (15/10/2023, 14:30:25)
   Position ID: 1
   User: 0x1234...5678 (0x1234...5678)
   Request Time: 15/10/2023, 14:30:20 (1697373020)
   Deadline: 15/10/2023, 14:35:20 (1697373320)
   Max Acceptable Price: $2,500.00000000
   Reason: PRICE_STALE (1)
   Closed By: USER_REQUESTED (0)

...

========================================
📈 THỐNG KÊ TỔNG HỢP
========================================

📊 Phân bố theo Reason:
   PRICE_STALE: 25 (59.52%)
   PRICE_NOT_ACCEPTABLE: 15 (35.71%)
   INVALID_PRICE: 2 (4.76%)

📊 Phân bố theo Closed By:
   USER_REQUESTED: 30 (71.43%)
   LIQUIDATION: 8 (19.05%)
   TAKE_PROFIT: 4 (9.52%)

👥 Số lượng users độc nhất: 15
📍 Số lượng positions độc nhất: 38

⏰ Khoảng thời gian:
   Đầu tiên: 15/10/2023, 14:30:25 (Block 1002345)
   Cuối cùng: 20/10/2023, 10:15:42 (Block 1098765)

💾 Đã export 42 events ra file: /path/to/node_scripts/pending-close-events.json

========================================
✅ HOÀN THÀNH
========================================
```

## File JSON Output Format

File `pending-close-events.json` sẽ có dạng:

```json
[
  {
    "eventIndex": 1,
    "transactionHash": "0xabc...def",
    "blockNumber": 1002345,
    "blockTimestamp": 1697373025,
    "logIndex": 5,
    "positionId": "1",
    "user": "0x1234567890123456789012345678901234567890",
    "requestTime": "1697373020",
    "deadline": "1697373320",
    "maxAcceptablePrice": "2500000000000000000000",
    "reason": 1,
    "reasonName": "PRICE_STALE",
    "closedBy": 0,
    "closedByName": "USER_REQUESTED"
  },
  ...
]
```

## License

MIT

