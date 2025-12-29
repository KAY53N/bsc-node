#!/bin/bash
# 停止 BSC 节点

ROOT_DIR="/opt/bsc-node"
PID_FILE="$ROOT_DIR/bsc.pid"

echo "🛑 Stopping BSC Node..."

# 1. 尝试通过 PID 文件停止
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if ps -p $PID > /dev/null; then
        echo "Found PID file: $PID"
    else
        echo "PID file exists but process is gone. Removing file."
        rm "$PID_FILE"
        PID=""
    fi
fi

# 2. 如果 PID 文件没找到或进程不在，尝试通过进程名查找
if [ -z "$PID" ]; then
    PID=$(pgrep -f "/data/bsc/geth")
fi

if [ -z "$PID" ]; then
    echo "❌ No BSC Node process found running."
    exit 0
fi

echo "Sending SIGINT to PID $PID (Graceful shutdown)..."
kill -SIGINT $PID

# 等待循环
count=0
while kill -0 $PID 2>/dev/null; do
    sleep 1
    count=$((count+1))
    echo -ne "Waiting for shutdown... ${count}s\r"
    
    # 超过 300秒 (5分钟) 强制杀死，因为写入数据可能很慢
    if [ $count -gt 300 ]; then
        echo ""
        echo "⚠️  Timeout! Force killing (SIGKILL)..."
        kill -SIGKILL $PID
        break
    fi
done

echo ""
echo "✅ BSC Node stopped."
[ -f "$PID_FILE" ] && rm "$PID_FILE"
