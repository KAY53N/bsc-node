#!/bin/bash

# 检查必要的环境变量
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$TELEGRAM_BOT_TOKEN" ]; then
    echo "错误: 请确保您已在当前 Shell 中导出 (export) 了 AWS_ACCESS_KEY_ID, TELEGRAM_BOT_TOKEN 等环境变量。"
    exit 1
fi

echo "正在启动 AWS CloudWatch 监控 (区域: ap-southeast-1)..."

# 停止并删除旧容器（如果存在）
docker rm -f aws-cloudwatch-monitor 2>/dev/null

# 获取当前脚本所在目录的绝对路径，用于挂载
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

docker run -d \
    --name aws-cloudwatch-monitor \
    --restart always \
    -e AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
    -e AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
    -e AWS_DEFAULT_REGION="ap-southeast-1" \
    -e TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN" \
    -e TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID" \
    -v "$SCRIPT_DIR/aws-monitor-task.sh:/aws-monitor-task.sh" \
    --entrypoint /bin/bash \
    amazon/aws-cli:latest \
    /aws-monitor-task.sh

echo "容器启动成功！使用 docker logs aws-cloudwatch-monitor 查看日志。"
