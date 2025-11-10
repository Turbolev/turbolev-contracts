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

### 1. Lấy giá trực tiếp từ CL Adapter

```bash
# Sử dụng .env file
node get-price-from-cl-adapter.js

# Hoặc truyền tham số qua command line
node get-price-from-cl-adapter.js --adapter 0x1234... --rpc https://rpc.ankr.com/eth
```

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

