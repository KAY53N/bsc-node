#!/bin/bash

# 安装必要工具
if ! command -v jq &> /dev/null;
    then
    yum install -y jq >/dev/null 2>&1
fi
if ! command -v curl &> /dev/null;
    then
    yum install -y curl >/dev/null 2>&1
fi

# 抑制时间设置 (秒) - 5分钟
SUPPRESS_SECONDS=300

# 获取 CloudWatch Metric 平均值的辅助函数
# 用法: get_metric_val NAMESPACE METRIC_NAME DIMENSIONS_ARGS
get_metric_val() {
    local NS=$1
    local NAME=$2
    local DIMS=$3
    
    # 获取过去10分钟的平均值 (period 600)
    local VAL=$(aws cloudwatch get-metric-statistics \
        --namespace "$NS" \
        --metric-name "$NAME" \
        --dimensions $DIMS \
        --start-time "$(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" \
        --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --period 600 \
        --statistics Average \
        --query 'Datapoints[0].Average' \
        --output text 2>/dev/null)

    if [ "$VAL" != "None" ] && [ -n "$VAL" ]; then
        printf "%.1f" "$VAL"
    else
        echo "N/A"
    fi
}

# 发送启动通知
curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
    -d "chat_id=$TELEGRAM_CHAT_ID" \
    -d "text=✅ AWS Monitor Started (ap-southeast-1) - Enhanced Metrics Mode" >/dev/null

echo "监控已启动 (Enhanced Metrics Mode)，正在轮询..."

# 创建临时目录存放报警时间戳
mkdir -p /tmp/alarm_timestamps

while true; do
    # 查询处于 ALARM 状态的报警
    ALARMS_JSON=$(aws cloudwatch describe-alarms --state-value ALARM --output json)
    
    # 检查是否有报警
    if [ -n "$ALARMS_JSON" ]; then
        # 使用 jq 迭代每个报警
        echo "$ALARMS_JSON" | jq -c '.MetricAlarms[]' | while read -r alarm; do
            # 提取基本信息
            NAME=$(echo "$alarm" | jq -r '.AlarmName')
            
            # --- 报警抑制逻辑开始 ---
            SAFE_NAME=$(echo -n "$NAME" | md5sum | awk '{print $1}')
            TIMESTAMP_FILE="/tmp/alarm_timestamps/${SAFE_NAME}"
            
            # 确保目录存在（防止被意外删除）
            mkdir -p /tmp/alarm_timestamps
            
            CURRENT_TIME=$(date +%s)
            SHOULD_SEND=true
            
            if [ -f "$TIMESTAMP_FILE" ]; then
                LAST_TIME=$(cat "$TIMESTAMP_FILE")
                DIFF=$((CURRENT_TIME - LAST_TIME))
                
                if [ $DIFF -lt $SUPPRESS_SECONDS ]; then
                    echo "跳过报警: '$NAME' (上次发送于 $DIFF 秒前, 限制 $SUPPRESS_SECONDS 秒)"
                    SHOULD_SEND=false
                fi
            fi
            
            if [ "$SHOULD_SEND" = true ]; then
                # 更新时间戳
                echo "$CURRENT_TIME" > "$TIMESTAMP_FILE"
                
                # --- 信息提取与处理 ---
                RAW_REASON=$(echo "$alarm" | jq -r '.StateReason')
                UPDATED_TIME=$(echo "$alarm" | jq -r '.StateUpdatedTimestamp')
                
                # 处理时间: 2025-12-19T08:20:00.000Z 或 ...+00:00 -> 2025-12-19 08:20:00
                TIME_VAL=$(echo "$UPDATED_TIME" | sed 's/T/ /;s/\..*//')
                
                # --- 中文简化逻辑 ---
                CLEAN_REASON=""
                
                # 检查是否为阈值类报警
                if [[ "$RAW_REASON" == *"Threshold Crossed"* ]]; then
                    # 提取数值 (当前值) - 匹配 [...] 内的第一个数字
                    VAL=$(echo "$RAW_REASON" | sed -n 's/.*\[\([0-9.]*\).*/\1/p' | awk '{printf("%d", $1)}' 2>/dev/null)
                    
                    # 提取阈值 - 匹配 threshold (...) 内的数字
                    THRESH=$(echo "$RAW_REASON" | sed -n 's/.*threshold (\([0-9.]*\)).*/\1/p' | awk '{printf("%d", $1)}' 2>/dev/null)
                    
                    # 确定关系符号
                    OP="超过"
                    [[ "$RAW_REASON" == *"greater than or equal to"* ]] && OP="≥"
                    [[ "$RAW_REASON" == *"greater than"* ]] && OP=">"
                    [[ "$RAW_REASON" == *"less than or equal to"* ]] && OP="≤"
                    [[ "$RAW_REASON" == *"less than"* ]] && OP="<"

                    # 判断单位后缀
                    SUFFIX=""
                    METRIC_NAME=$(echo "$alarm" | jq -r '.MetricName // ""')
                    if [[ "$METRIC_NAME" =~ (CPU|Memory|DiskSpace|Utilization|Percent) ]] || [[ "$NAME" == *"率"* ]]; then
                        SUFFIX="%"
                    fi
                    
                    if [ -n "$VAL" ] && [ -n "$THRESH" ]; then
                        CLEAN_REASON="当前值 ${VAL}${SUFFIX} ${OP} 阈值 ${THRESH}${SUFFIX}"
                    fi
                fi
                
                if [ -z "$CLEAN_REASON" ]; then
                    CLEAN_REASON=$(echo "$RAW_REASON" | sed -E 's/([0-9]+)\.[0-9]+/\1/g')
                fi

                # --- 实例信息与实时指标提取 ---
                INSTANCE_ID=$(echo "$alarm" | jq -r '.Dimensions[]? | select(.Name=="InstanceId") | .Value')
                DETAILS=""
                METRICS_BLOCK=""
                
                if [ -n "$INSTANCE_ID" ] && [ "$INSTANCE_ID" != "null" ]; then
                    INST_JSON=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --output json 2>/dev/null)
                    
                    if [ $? -eq 0 ]; then
                        TAG_NAME=$(echo "$INST_JSON" | jq -r '.Reservations[0].Instances[0].Tags[]? | select(.Key=="Name") | .Value')
                        [ -z "$TAG_NAME" ] && TAG_NAME="N/A"
                        
                        PUB_IP=$(echo "$INST_JSON" | jq -r '.Reservations[0].Instances[0].PublicIpAddress')
                        PRIV_IP=$(echo "$INST_JSON" | jq -r '.Reservations[0].Instances[0].PrivateIpAddress')
                        
                        IP_DISPLAY="N/A"
                        if [ "$PUB_IP" != "null" ]; then 
                            IP_DISPLAY="$PUB_IP"
                        elif [ "$PRIV_IP" != "null" ]; then 
                            IP_DISPLAY="$PRIV_IP"
                        fi
                        
                        DETAILS=$(printf "\n💻 <b>实例:</b> %s\n🆔 <b>ID:</b> %s\n🌐 <b>IP:</b> %s" "$TAG_NAME" "$INSTANCE_ID" "$IP_DISPLAY")

                        # --- 获取实时指标 (CPU, Memory, Disk) ---
                        # 1. CPU Utilization
                        CPU_VAL=$(get_metric_val "AWS/EC2" "CPUUtilization" "Name=InstanceId,Value=$INSTANCE_ID")
                        
                        # 2. Memory Utilization (查找正确的 Dimensions)
                        MEM_DIMS_JSON=$(aws cloudwatch list-metrics --namespace CWAgent --metric-name mem_used_percent --dimensions Name=InstanceId,Value="$INSTANCE_ID" --output json 2>/dev/null | jq -c '.Metrics[0].Dimensions')
                        MEM_VAL="N/A"
                        if [ "$MEM_DIMS_JSON" != "null" ] && [ -n "$MEM_DIMS_JSON" ]; then
                            MEM_ARGS=$(echo "$MEM_DIMS_JSON" | jq -r '.[] | "Name=\(.Name),Value=\(.Value)"' | tr '\n' ' ')
                            MEM_VAL=$(get_metric_val "CWAgent" "mem_used_percent" "$MEM_ARGS")
                        fi

                        # 2.1 Swap Utilization
                        SWAP_DIMS_JSON=$(aws cloudwatch list-metrics --namespace CWAgent --metric-name swap_used_percent --dimensions Name=InstanceId,Value="$INSTANCE_ID" --output json 2>/dev/null | jq -c '.Metrics[0].Dimensions')
                        SWAP_VAL="N/A"
                        if [ "$SWAP_DIMS_JSON" != "null" ] && [ -n "$SWAP_DIMS_JSON" ]; then
                            SWAP_ARGS=$(echo "$SWAP_DIMS_JSON" | jq -r '.[] | "Name=\(.Name),Value=\(.Value)"' | tr '\n' ' ')
                            SWAP_VAL=$(get_metric_val "CWAgent" "swap_used_percent" "$SWAP_ARGS")
                        fi

                        # 3. Disk Utilization (Root /)
                        DISK_ROOT_VAL="N/A"
                        ROOT_METRIC_INFO=$(aws cloudwatch list-metrics --namespace CWAgent --dimensions Name=InstanceId,Value="$INSTANCE_ID" Name=path,Value="/" --output json 2>/dev/null)
                        if [ -n "$ROOT_METRIC_INFO" ] && [ "$ROOT_METRIC_INFO" != "null" ]; then
                            ROOT_METRIC_NAME=$(echo "$ROOT_METRIC_INFO" | jq -r '.Metrics[0].MetricName // empty')
                            DISK_ROOT_DIMS=$(echo "$ROOT_METRIC_INFO" | jq -c '.Metrics[0].Dimensions')
                            
                            if [ -n "$ROOT_METRIC_NAME" ] && [ "$DISK_ROOT_DIMS" != "null" ] && [ -n "$DISK_ROOT_DIMS" ]; then
                                DISK_ROOT_ARGS=$(echo "$DISK_ROOT_DIMS" | jq -r '.[] | "Name=\(.Name),Value=\(.Value)"' | tr '\n' ' ')
                                DISK_ROOT_VAL=$(get_metric_val "CWAgent" "$ROOT_METRIC_NAME" "$DISK_ROOT_ARGS")
                            fi
                        fi

                        # 4. Disk Utilization (Data /data)
                        DISK_DATA_VAL="N/A"
                        DATA_METRIC_INFO=$(aws cloudwatch list-metrics --namespace CWAgent --dimensions Name=InstanceId,Value="$INSTANCE_ID" Name=path,Value="/data" --output json 2>/dev/null)
                        if [ -n "$DATA_METRIC_INFO" ] && [ "$DATA_METRIC_INFO" != "null" ]; then
                            DATA_METRIC_NAME=$(echo "$DATA_METRIC_INFO" | jq -r '.Metrics[0].MetricName // empty')
                            DISK_DATA_DIMS=$(echo "$DATA_METRIC_INFO" | jq -c '.Metrics[0].Dimensions')
                            
                            if [ -n "$DATA_METRIC_NAME" ] && [ "$DISK_DATA_DIMS" != "null" ] && [ -n "$DISK_DATA_DIMS" ]; then
                                DISK_DATA_ARGS=$(echo "$DISK_DATA_DIMS" | jq -r '.[] | "Name=\(.Name),Value=\(.Value)"' | tr '\n' ' ')
                                DISK_DATA_VAL=$(get_metric_val "CWAgent" "$DATA_METRIC_NAME" "$DISK_DATA_ARGS")
                            fi
                        fi

                        METRICS_BLOCK=$(printf "\n📊 <b>状态:</b> CPU: %s%% | Mem: %s%% | Swap: %s%% | /: %s%% | /data: %s%%" "$CPU_VAL" "$MEM_VAL" "$SWAP_VAL" "$DISK_ROOT_VAL" "$DISK_DATA_VAL")
                    fi
                fi
                
                # --- 构建消息 ---
                HEADER="🚨 <b>${NAME}</b> 🚨"
                REGION="🌏 <b>区域:</b> ap-southeast-1"
                TIME_LINE="⏰ <b>时间:</b> $TIME_VAL"
                REASON_BLOCK="📉 <b>详情:</b> $CLEAN_REASON"
                
                FULL_MSG=$(printf "%s\n\n%s\n%s%s%s\n\n%s" "$HEADER" "$REGION" "$TIME_LINE" "$DETAILS" "$METRICS_BLOCK" "$REASON_BLOCK")
                
                echo "发送报警: '$NAME' - $CLEAN_REASON"
                
                # 发送消息
                curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
                    -d "chat_id=$TELEGRAM_CHAT_ID" \
                    -d "parse_mode=HTML" \
                    --data-urlencode "text=$FULL_MSG" >/dev/null
            fi
        done
    fi
    
    sleep 60
done