# BSC 节点部署与维护指南

本文档记录了在 Linux 服务器上部署高性能 BSC (Binance Smart Chain) 节点的完整流程。本方案采用 **Snap Sync** 模式配合 **PebbleDB** 引擎，旨在以最快速度完成同步并最小化资源占用。

## 1. 硬件要求 (推荐)

*   **CPU**: 16核+ (高频优先)
*   **RAM**: 64GB+ (分配给 Geth 的缓存越多越好)
*   **Disk**: 2TB+ NVMe SSD (必须是 NVMe，SATA SSD 极可能跟不上节点读写速度)
*   **OS**: Linux (Ubuntu 20.04/22.04 推荐)

## 2. 目录结构

我们将程序逻辑与数据分离，以便于管理。

*   **程序/配置目录**: `/opt/bsc-node`
*   **大数据目录**: `/data/bsc` (挂载在 NVMe 硬盘上)

```text
/opt/bsc-node/
├── bsc.pid                 # 运行时的进程ID
├── config/
│   ├── config.toml         # Geth 配置文件
│   ├── genesis.json        # 创世块配置
│   └── mainnet.zip         # (可选) 官方配置包
├── logs/
│   └── bsc.log             # 运行日志
└── scripts/
    ├── start-bsc.sh        # 启动脚本 (含优化参数)
    ├── stop-bsc.sh         # 优雅停止脚本
    ├── check_bsc_sync.py   # 同步状态检查工具
    └── get_token_price.py  # 辅助工具
```

## 3. 环境准备

确保数据目录权限正确：

```bash
mkdir -p /opt/bsc-node/{config,logs,scripts}
mkdir -p /data/bsc/data
```

下载 BSC Geth 二进制文件 (建议使用官方最新版) 并放置于 `/data/bsc/geth`，添加执行权限：

```bash
chmod +x /data/bsc/geth
```

## 4. 关键配置文件

### 4.1 config.toml

从官方仓库获取 `config.toml` 和 `genesis.json`。重点修改 `[Node]` 部分以适配本地环境，根据机器内存调整 `Cache` 设置 (在启动命令中覆盖)。

### 4.2 启动脚本 (`scripts/start-bsc.sh`)

这是核心部分，包含了针对同步速度的优化参数。

```bash
#!/bin/bash
# 启动 BSC 节点 (Snap Sync 优化版)

ROOT_DIR="/opt/bsc-node"
DATA_DIR="/data/bsc"
BINARY="$DATA_DIR/geth"
LOG_FILE="$ROOT_DIR/logs/bsc.log"

echo "🚀 BSC Node Starting (Snap Sync Mode)..."

mkdir -p "$ROOT_DIR/logs"

# 启动参数详解：
# --syncmode snap: 快照同步，最快的同步方式。
# --gcmode full: 配合 snap 使用。
# --cache 32000: 分配 32GB 内存用于缓存 (根据实际内存调整，越大越好)。
# --tries-verify-mode none: 关键优化！跳过状态树验证，大幅加速同步。
# --history.transactions 0: 不保留历史交易索引，节省约 30-40% 磁盘空间。
# --db.engine pebble: 使用 PebbleDB，写入性能优于默认的 LevelDB。
# --maxpeers 200: 增加连接节点数，提高下载并发度。

nohup "$BINARY" \
  --config "$ROOT_DIR/config/config.toml" \
  --datadir "$DATA_DIR/data" \
  --syncmode snap \
  --gcmode full \
  --cache 32000 \
  --tries-verify-mode none \
  --maxpeers 200 \
  --history.transactions 0 \
  --db.engine pebble \
  --http \
  --http.addr 0.0.0.0 \
  --http.port 8545 \
  --http.corsdomain "*" \
  --http.vhosts "*" \
  --http.api "eth,net,web3,txpool" \
  --ws \
  --ws.addr 0.0.0.0 \
  --ws.port 8546 \
  --ws.api "eth,net,web3,txpool" \
  --metrics \
  >> "$LOG_FILE" 2>&1 &

PID=$!
echo "✅ BSC Node started. PID: $PID"
echo $PID > "$ROOT_DIR/bsc.pid"
```

### 4.3 停止脚本 (`scripts/stop-bsc.sh`)

防止强制杀进程导致数据库损坏。

```bash
#!/bin/bash
ROOT_DIR="/opt/bsc-node"
PID_FILE="$ROOT_DIR/bsc.pid"

# 读取 PID 并发送 SIGINT (Ctrl+C 信号)
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    kill -SIGINT $PID
    # 脚本中包含循环等待逻辑，确保进程完全退出
fi
```

## 5. 常用操作命令

### 启动节点
```bash
cd /opt/bsc-node
bash scripts/start-bsc.sh
```

### 停止节点
```bash
cd /opt/bsc-node
bash scripts/stop-bsc.sh
```

### 查看实时日志
```bash
tail -f /opt/bsc-node/logs/bsc.log
```

### 检查同步进度
使用 Python 脚本计算百分比：
```bash
python3 scripts/check_bsc_sync.py
```
或者在控制台直接查询：
```bash
/data/bsc/geth attach /data/bsc/data/geth.ipc --exec eth.syncing
```

## 6. 性能优化与故障排查

1.  **同步速度慢**:
    *   **检查 Peers**: 如果 peers 数量少于 20，检查防火墙是否开放 30311 端口 (TCP/UDP)。
    *   **IO 瓶颈**: 使用 `iostat -x 1` 查看磁盘使用率。如果 `%util` 长期接近 100%，说明硬盘是瓶颈，必须更换 NVMe。
    *   **参数调整**: 确保开启了 `--tries-verify-mode none` 和 `--db.engine pebble`。

2.  **Snap Sync 阶段**:
    *   节点会先下载区块头 (Block Headers)。
    *   然后下载状态数据 (State / Snap Sync)，这是最慢的阶段（可能持续数天）。
    *   **极速方案**: 如果无法忍受 P2P 同步速度，建议下载官方或社区提供的**离线快照包 (Snapshot)**，解压到 `data` 目录替换数据，可将时间缩短至数小时。

3.  **磁盘空间**:
    *   Pruned 节点目前约需 1.8TB+ 空间。务必监控磁盘余量，空间不足会导致数据库损坏。
