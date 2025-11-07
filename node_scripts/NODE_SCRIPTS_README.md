# Scripts Node.js cho Blocksense Oracle

Bộ scripts để tương tác với Blocksense Oracle và CL Aggregator Adapter sử dụng Node.js và ethers.js.

## 📋 Yêu Cầu

- Node.js v16+ 
- npm hoặc yarn

## 🚀 Cài Đặt

1. Di chuyển vào thư mục scripts:
```bash
cd scripts
```

2. Cài đặt dependencies:
```bash
npm install
```

3. Copy file `.env.example` thành `.env` và cấu hình:
```bash
cp .env.example .env
```

4. Chỉnh sửa file `.env`:
```bash
# Bắt buộc
ADAPTER_ADDRESS=0x... # Địa chỉ CL Aggregator Adapter

# Optional
RPC_URL=https://rpc.ankr.com/eth
ORACLE_ADDRESS=0x...  # Địa chỉ BlocksenseOracle contract
```

## 📖 Sử Dụng

### 1. Lấy giá trực tiếp từ CL Adapter (Blocksense)

```bash
# Sử dụng .env file
node get-price-from-cl-adapter.js

# Hoặc truyền tham số qua command line
node get-price-from-cl-adapter.js --adapter 0x1234... --rpc https://rpc.ankr.com/eth
```

### 2. Lấy giá từ Chainlink Price Feed

```bash
# Xem danh sách feeds phổ biến
node get-price-from-chainlink.js --list

# Lấy giá từ Chainlink feed
node get-price-from-chainlink.js --feed 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419 --rpc https://rpc.ankr.com/eth

# Hoặc dùng environment variables
export FEED_ADDRESS=0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419
export RPC_URL=https://rpc.ankr.com/eth
node get-price-from-chainlink.js
```

**Features:**
- ✅ Lấy giá mới nhất từ Chainlink
- ✅ Hiển thị lịch sử 10 rounds gần nhất
- ✅ Phân tích độ biến động giá
- ✅ Kiểm tra sức khỏe feed
- ✅ Danh sách feeds phổ biến (ETH, BTC, USDC, etc.)

### 3. Setup Vault với Chainlink Fallback

```bash
# Setup vault với cả Blocksense và Chainlink fallback
node setup-vault-with-fallback.js \
  --vault 0x... \
  --adapter 0x... \
  --chainlink 0x... \
  --oracle 0x...

# Hoặc dùng environment variables
export VAULT_ADDRESS=0x...
export ORACLE_ADAPTER=0x...
export CHAINLINK_FEED=0x...
export CHAINLINK_ORACLE=0x...
export PRIVATE_KEY=0x...
node setup-vault-with-fallback.js
```

**Script này sẽ:**
1. ✅ Set oracle adapter (Blocksense) cho vault
2. ✅ Set Chainlink feed (fallback) cho vault  
3. ✅ Configure ChainlinkOracle mapping
4. ✅ Test lấy giá với fallback mechanism
5. ✅ So sánh giá từ 2 sources
6. ✅ Hiển thị thống kê fallback usage

### 4. Test Price Fallback Mechanism

```bash
# Test fallback mechanism trong SettlementEngine
node test-price-fallback.js \
  --settlement 0x... \
  --vault-manager 0x... \
  --token 0x... \
  --max-age 300

# Hoặc dùng environment variables
export SETTLEMENT_ENGINE=0x...
export VAULT_MANAGER=0x...
export PROJECT_TOKEN=0x...
export MAX_AGE=300
node test-price-fallback.js
```

**Script này sẽ test:**
1. ✅ Configuration (oracles, vault, adapters)
2. ✅ Get settlement price với fallback
3. ✅ So sánh prices từ cả Blocksense và Chainlink
4. ✅ Listen to PriceFallbackUsed events
5. ✅ Analyze fallback usage patterns

**Output:**
```
========================================
📊 LẤY GIÁ TỪ CL AGGREGATOR ADAPTER
========================================

🔍 Thông tin Feed:
   Description: ETH/USD
   Decimals: 8

📈 Dữ liệu giá mới nhất:
   Round ID: 12345
   Price (raw): 200000000000
   Price (formatted): $2,000.00
   Updated At: 05/11/2025, 10:30:45 (1730789445)
   Age: 15 giây

✅ Giá còn fresh (15 giây < 5 phút)
```

### 2. Lấy giá qua BlocksenseOracle (với validation)

```bash
node get-price-from-cl-adapter.js \
  --adapter 0x1234... \
  --oracle 0x5678... \
  --rpc https://rpc.ankr.com/eth
```

**Output:**
```
========================================
🏛️  LẤY GIÁ QUA BLOCKSENSE ORACLE
========================================

⚙️  Cấu hình Oracle:
   Max Price Age: 300 giây
   Max Price Change: 10%
   Paused: 🟢 Không

📊 Lấy giá (với validation):
   Price (raw, 18 decimals): 2000000000000000000000
   Price (formatted): $2,000.00
   Updated At: 05/11/2025, 10:30:45 (1730789445)
   Age: 15 giây

✅ Lấy giá thành công qua oracle!
```

### 3. Sử dụng npm scripts

```bash
# Chạy script với config từ .env
npm run get-price

# Hoặc với examples có sẵn (nhớ thay địa chỉ thật)
npm run example:adapter
npm run example:oracle
```

## 🔧 Tham Số Command Line

| Tham số | Mô tả | Bắt buộc | Mặc định |
|---------|-------|----------|----------|
| `--adapter` | Địa chỉ CL Aggregator Adapter | ✅ Có | - |
| `--oracle` | Địa chỉ BlocksenseOracle contract | ❌ Không | - |
| `--rpc` | RPC URL | ❌ Không | `https://rpc.ankr.com/eth` |

## 📊 Output Formats

Script sẽ hiển thị:

### Từ CL Adapter:
- Description của price feed (vd: "ETH/USD")
- Decimals của feed
- Round ID hiện tại
- Price (raw và formatted)
- Timestamps (started at, updated at)
- Age của price data (tính bằng giây)
- Cảnh báo nếu giá quá cũ (> 5 phút)

### Từ BlocksenseOracle:
- Cấu hình oracle (max price age, max price change, paused status)
- Price với validation (đã scale lên 18 decimals)
- Price unsafe (không có staleness check)
- Age của price data
- Error messages rõ ràng nếu có lỗi

## 🔍 Features

### 1. **Lấy giá trực tiếp từ CL Adapter**
- Gọi trực tiếp contract CL Aggregator Adapter
- Lấy latest round data
- Kiểm tra freshness của price
- Không cần qua oracle contract

### 2. **Lấy giá qua BlocksenseOracle**
- Sử dụng validation từ oracle contract
- Circuit breaker protection
- Staleness check
- Price manipulation protection

### 3. **So sánh kết quả**
- Tự động so sánh giá từ adapter và oracle
- Hiển thị cả 2 kết quả khi có oracle address

### 4. **Error handling chi tiết**
- Parse và hiển thị error messages rõ ràng
- Giải thích lý do lỗi (PriceStale, InvalidPrice, PriceChangeTooLarge, etc.)

## 🛠️ Troubleshooting

### Lỗi: "Cannot find module 'ethers'"
```bash
npm install
```

### Lỗi: "Invalid adapter address"
Đảm bảo địa chỉ adapter là địa chỉ Ethereum hợp lệ (0x... với 42 ký tự)

### Lỗi: "PriceStale"
Giá từ oracle quá cũ. Options:
1. Kiểm tra xem Blocksense network có đang update giá không
2. Tăng `maxPriceAge` trong oracle config
3. Sử dụng `getPriceUnsafe()` nếu bạn chấp nhận giá cũ

### Lỗi: "PriceChangeTooLarge"
Circuit breaker triggered do giá thay đổi quá nhiều. Options:
1. Đợi giá ổn định
2. Tăng `maxPriceChangeBps` trong oracle config

## 📚 Resources

- [Blocksense Documentation](https://docs.blocksense.network/)
- [CL Aggregator Adapter Guide](https://docs.blocksense.network/docs/contracts/integration-guide/using-data-feeds/cl-aggregator-adapter)
- [Ethers.js Documentation](https://docs.ethers.org/v6/)

## 🔐 Security Notes

- **KHÔNG** commit file `.env` có chứa private keys hoặc sensitive data
- Chỉ sử dụng RPC URLs từ nguồn tin cậy
- Luôn validate prices trước khi sử dụng trong production

## 📝 License

MIT License - See [LICENSE](../LICENSE) for details.

