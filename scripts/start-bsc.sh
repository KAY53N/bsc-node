#!/bin/bash
# 启动 BSC 节点 (Snap Sync 优化版)
# Docs: https://docs.bnbchain.org/docs/bsc-geth/
# Config: /opt/bsc-node
# Data:   /data/bsc

ROOT_DIR="/opt/bsc-node"
DATA_DIR="/data/bsc"
BINARY="$DATA_DIR/geth"
LOG_FILE="$ROOT_DIR/logs/bsc.log"

echo "🚀 BSC Node Starting (Snap Sync Mode)..."
echo "   Config: $ROOT_DIR/config/config.toml"
echo "   Data:   $DATA_DIR/data"
echo "   Logs:   $LOG_FILE"

mkdir -p "$ROOT_DIR/logs"

# 检查二进制文件
if [ ! -f "$BINARY" ]; then
    echo "❌ Binary not found at $BINARY"
    exit 1
fi

# 检查是否正在运行 (增强版)
PID_FILE="$ROOT_DIR/bsc.pid"

if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if ps -p "$OLD_PID" > /dev/null 2>&1; then
        echo "⚠️  Node is already running with PID $OLD_PID (found in $PID_FILE)."
        exit 1
    else
        echo "⚠️  Found stale PID file ($PID_FILE). Process $OLD_PID is not running. Removing stale file..."
        rm "$PID_FILE"
    fi
fi

# 兜底检查: 防止 PID 文件丢失的情况
if pgrep -f "$DATA_DIR/geth" > /dev/null; then
    echo "⚠️  Node appears to be already running (detected via process list). Check 'ps aux | grep geth'."
    exit 1
fi

# 启动命令
# --syncmode snap: 快照同步
# --gcmode full: 配合 snap
# --history.transactions 0: 不保留历史交易索引 (节省空间)
# --cache 8192: 分配 8GB 内存给缓存 (针对 15GB 内存优化)
# --db.engine pebble: 使用 PebbleDB (性能更好)
# --txlookuplimit 0: 禁用旧块交易索引 (减少 I/O)
ulimit -n 65535

nohup "$BINARY" \
  --config "$ROOT_DIR/config/config.toml" \
  --datadir "$DATA_DIR/data" \
  --syncmode snap \
  --gcmode full \
  --cache 8192 \
  --maxpeers 300 \
  --history.transactions 0 \
  --txlookuplimit 0 \
  --tries-verify-mode none \
  --pruneancient \
  --db.engine pebble \
  --state.scheme path \
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
echo "📝 Monitor logs: tail -f $LOG_FILE"
