#!/bin/bash
# bsc-sync-monitor-full.sh

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
ORANGE='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 公共RPC端点列表（故障转移）
PUBLIC_RPCS=(
    "https://bnb-mainnet.g.alchemy.com/v2/EEKfy_ESSyEHR5N7xXXZk"
    "https://bsc-dataseed1.binance.org"
    "https://bsc-dataseed2.binance.org"
    "https://bsc-dataseed3.binance.org"
    "https://bsc-dataseed4.binance.org"
    "https://bsc-dataseed.binance.org"
)

while true; do
    clear
    echo -e "${BLUE}================ BSC 节点同步监控 ================${NC}"
    echo "监控时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "${BLUE}--------------------------------------------------${NC}"
    
    # 获取本地节点信息
    LOCAL_DATA=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        http://localhost:8545 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$LOCAL_DATA" ]; then
        echo -e "本地节点: ${RED}无法连接${NC}"
        sleep 10
        continue
    fi
    
    LOCAL_HEX=$(echo $LOCAL_DATA | grep -o '"result":"[^"]*"' | cut -d'"' -f4)
    LOCAL_DEC=$((LOCAL_HEX))
    
    # 获取本地最新区块的时间戳和详情
    LOCAL_BLOCK=$(curl -s -X POST -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"latest\", true],\"id\":1}" \
        http://localhost:8545 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$LOCAL_BLOCK" ]; then
        LOCAL_TIMESTAMP_HEX=$(echo $LOCAL_BLOCK | grep -o '"timestamp":"[^"]*"' | cut -d'"' -f4)
        LOCAL_TIMESTAMP=$((LOCAL_TIMESTAMP_HEX))
        LOCAL_TIME_STR=$(date -d @$LOCAL_TIMESTAMP '+%H:%M:%S')
        
        # 获取交易数量
        TX_COUNT=$(echo $LOCAL_BLOCK | grep -o '"transactions":\[[^]]*\]' | tr -cd ',' | wc -c)
        TX_COUNT=$((TX_COUNT + 1))
    else
        LOCAL_TIME_STR="N/A"
        TX_COUNT="N/A"
    fi
    
    # 尝试从多个公共RPC获取最新高度
    PUBLIC_DEC=""
    PUBLIC_RPC_USED=""
    for rpc in "${PUBLIC_RPCS[@]}"; do
        PUBLIC_DATA=$(curl -s -m 5 -X POST -H "Content-Type: application/json" \
            --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
            $rpc 2>/dev/null)
        
        if [ $? -eq 0 ] && [ -n "$PUBLIC_DATA" ]; then
            PUBLIC_HEX=$(echo $PUBLIC_DATA | grep -o '"result":"[^"]*"' | cut -d'"' -f4)
            PUBLIC_DEC=$((PUBLIC_HEX))
            PUBLIC_RPC_USED=$(echo $rpc | awk -F'/' '{print $3}')
            break
        fi
    done
    
    if [ -z "$PUBLIC_DEC" ]; then
        echo -e "公共节点: ${RED}无法获取${NC}"
        LAG="N/A"
        TIME_LAG="N/A"
    else
        LAG=$((PUBLIC_DEC - LOCAL_DEC))
        
        # 计算时间延迟（使用实际时间差）
        if [ "$LOCAL_TIMESTAMP" != "" ] && [ "$LOCAL_TIMESTAMP" != "0" ]; then
            CURRENT_TIMESTAMP=$(date +%s)
            TIME_DIFF=$((CURRENT_TIMESTAMP - LOCAL_TIMESTAMP))
            TIME_LAG="${TIME_DIFF}秒"
        else
            TIME_LAG="$((LAG * 3))秒(估算)"
        fi
        
        echo -e "本地节点高度: ${GREEN}$LOCAL_DEC${NC}"
        echo -e "公共节点高度: ${BLUE}$PUBLIC_DEC${NC} (来源: $PUBLIC_RPC_USED)"
        echo -e "最新区块时间: ${YELLOW}$LOCAL_TIME_STR${NC}"
        echo -e "区块交易数量: ${TX_COUNT}"
        echo ""
        echo -e "区块延迟: ${YELLOW}$LAG 个区块${NC}"
        echo -e "时间延迟: ${YELLOW}$TIME_LAG${NC}"
        echo ""
        
        # 显示延迟状态（使用您的判断逻辑）
        if [ $LAG -eq 0 ]; then
            echo -e "同步状态: ${GREEN}✅ 完全同步${NC}"
        elif [ $LAG -le 3 ]; then
            echo -e "同步状态: ${GREEN}🟢 良好 ($LAG blocks)${NC}"
        elif [ $LAG -le 10 ]; then
            echo -e "同步状态: ${YELLOW}🟡 轻微延迟 ($LAG blocks)${NC}"
        elif [ $LAG -le 50 ]; then
            echo -e "同步状态: ${ORANGE}🟠 中等延迟 ($LAG blocks)${NC}"
        else
            echo -e "同步状态: ${RED}🔴 严重延迟 ($LAG blocks)${NC}"
        fi
        
        # 显示进度条
        if [ $PUBLIC_DEC -gt 0 ]; then
            PERCENTAGE=$((LOCAL_DEC * 100 / PUBLIC_DEC))
            BAR_LENGTH=30
            FILLED=$((PERCENTAGE * BAR_LENGTH / 100))
            EMPTY=$((BAR_LENGTH - FILLED))
            
            echo ""
            echo -n "同步进度: ["
            for ((i=0; i<FILLED; i++)); do 
                if [ $PERCENTAGE -ge 99 ]; then
                    echo -ne "${GREEN}█${NC}"
                elif [ $PERCENTAGE -ge 90 ]; then
                    echo -ne "${YELLOW}█${NC}"
                else
                    echo -ne "${RED}█${NC}"
                fi
            done
            for ((i=0; i<EMPTY; i++)); do echo -n "░"; done
            echo -e "] ${PERCENTAGE}%"
        fi
    fi
    
    # 显示节点基本信息
    echo -e "${BLUE}--------------------------------------------------${NC}"
    
    # 获取 peer 数量
    PEER_DATA=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
        http://localhost:8545 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$PEER_DATA" ]; then
        PEER_HEX=$(echo $PEER_DATA | grep -o '"result":"[^"]*"' | cut -d'"' -f4)
        PEER_COUNT=$((PEER_HEX))
        
        # Peer 数量状态
        if [ $PEER_COUNT -ge 100 ]; then
            PEER_COLOR=$GREEN
            PEER_STATUS="优秀"
        elif [ $PEER_COUNT -ge 50 ]; then
            PEER_COLOR=$YELLOW
            PEER_STATUS="良好"
        elif [ $PEER_COUNT -ge 10 ]; then
            PEER_COLOR=$ORANGE
            PEER_STATUS="一般"
        else
            PEER_COLOR=$RED
            PEER_STATUS="较差"
        fi
        
        echo -e "Peer连接数: ${PEER_COLOR}$PEER_COUNT${NC} (${PEER_STATUS})"
    else
        echo -e "Peer连接数: ${RED}无法获取${NC}"
    fi
    
    echo -e "${BLUE}--------------------------------------------------${NC}"
    echo -e "刷新间隔: 0.5秒 | 按 Ctrl+C 退出"
    echo -e "${BLUE}==================================================${NC}"
    
    sleep 0.5
done
