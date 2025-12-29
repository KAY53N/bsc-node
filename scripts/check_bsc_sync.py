import json
import urllib.request
import sys
import time
import os
import datetime

URL = "http://localhost:8545"
# 估算值 (基于 2025 BscScan 数据 & 经验调整)
EST_TOTAL_ACCOUNTS = 500_000_000   # 预估活跃账户 (BscScan 总量为 7.1亿，但节点仅需同步活跃部分)
EST_TOTAL_SLOTS = 4_000_000_000    # 预估存储槽
EST_TOTAL_BYTECODES = 3_200_000    # 预估合约代码数量 (根据 Sync 行为调整)

def clear_screen():
    print("\033[H\033[J", end="")

def rpc_call(method, params=[]):
    payload = json.dumps({
        "jsonrpc": "2.0",
        "method": method,
        "params": params,
        "id": 1
    }).encode('utf-8')
    
    try:
        req = urllib.request.Request(URL, data=payload, headers={'Content-Type': 'application/json'})
        with urllib.request.urlopen(req, timeout=5) as response:
            return json.load(response).get('result')
    except Exception:
        return None

def format_bytes(size):
    return f"{size / (1024**3):.2f} GB"

def format_speed(bytes_diff, time_diff):
    if time_diff == 0: return "0 MB/s"
    mb_s = (bytes_diff / (1024**2)) / time_diff
    return f"{mb_s:.2f} MB/s"

def calc_eta(current, total, speed):
    if speed <= 0 or current >= total:
        return "未知 / 计算中..."
    remaining = total - current
    seconds_left = remaining / speed
    return str(datetime.timedelta(seconds=int(seconds_left)))

def main():
    print("正在初始化监控面板，请稍候...")
    
    last_time = time.time()
    last_stats = {}
    
    try:
        while True:
            current_time = time.time()
            time_diff = current_time - last_time
            
            syncing = rpc_call("eth_syncing")
            peer_count_hex = rpc_call("net_peerCount")
            
            clear_screen()
            print(f"🕒 更新时间: {datetime.datetime.now().strftime('%H:%M:%S')}")
            print("==================================================")
            
            if syncing is None:
                print("❌ 无法连接到 Geth (端口 8545)")
                time.sleep(5)
                continue

            if syncing is False:
                print("✅ 节点已完全同步 (Synced)！")
                print("==================================================")
                time.sleep(10)
                continue

            peer_count = int(peer_count_hex, 16) if peer_count_hex else 0
            current_block = int(syncing.get('currentBlock', '0x0'), 16)
            highest_block = int(syncing.get('highestBlock', '0x0'), 16)
            
            load_1, load_5, load_15 = os.getloadavg()
            print(f"💻 系统负载: {load_1:.2f}, {load_5:.2f}, {load_15:.2f}")
            print(f"🔗 连接节点: {peer_count}")
            print("==================================================")

            header_pct = (current_block / highest_block * 100) if highest_block > 0 else 0
            print(f"1️⃣  阶段 1: 区块头 (Headers)")
            print(f"   进度: {header_pct:.2f}% ({current_block:,} / {highest_block:,})")
            
            if 'syncedAccounts' in syncing:
                accs = int(syncing.get('syncedAccounts', '0x0'), 16)
                accs_bytes = int(syncing.get('syncedAccountBytes', '0x0'), 16)
                
                slots = int(syncing.get('syncedStorage', '0x0'), 16)
                slots_bytes = int(syncing.get('syncedStorageBytes', '0x0'), 16)
                
                codes = int(syncing.get('syncedBytecodes', '0x0'), 16)
                codes_bytes = int(syncing.get('syncedBytecodeBytes', '0x0'), 16)
                
                # 计算速度
                prev_accs = last_stats.get('accs', accs)
                acc_speed = (accs - prev_accs) / time_diff if time_diff > 0 else 0
                
                prev_slots = last_stats.get('slots', slots)
                slot_speed = (slots - prev_slots) / time_diff if time_diff > 0 else 0

                prev_codes = last_stats.get('codes', codes)
                code_speed = (codes - prev_codes) / time_diff if time_diff > 0 else 0

                last_stats['accs'] = accs
                last_stats['slots'] = slots
                last_stats['codes'] = codes
                
                print("-" * 50)
                print(f"2️⃣  阶段 2: 状态下载 (Snap Sync) - 实时监控")
                
                # 账户
                acc_pct_est = (accs / EST_TOTAL_ACCOUNTS * 100)
                acc_eta = calc_eta(accs, EST_TOTAL_ACCOUNTS, acc_speed)
                print(f"   👤 账户 (Accounts):")
                print(f"      进度: {acc_pct_est:.2f}% ({accs:,} / ~{EST_TOTAL_ACCOUNTS:,})")
                print(f"      速度: 🚀 {int(acc_speed):,}/s | 剩余: ⏳ {acc_eta}")
                
                # 存储槽
                slot_pct_est = (slots / EST_TOTAL_SLOTS * 100)
                slot_eta = calc_eta(slots, EST_TOTAL_SLOTS, slot_speed)
                print(f"   💾 存储槽 (Storage):")
                print(f"      进度: {slot_pct_est:.2f}% ({slots:,} / ~{EST_TOTAL_SLOTS:,})")
                print(f"      速度: 🚀 {int(slot_speed):,}/s | 剩余: ⏳ {slot_eta}")
                
                # 代码
                code_pct_est = (codes / EST_TOTAL_BYTECODES * 100)
                code_eta = calc_eta(codes, EST_TOTAL_BYTECODES, code_speed)
                print(f"   📜 代码 (Bytecodes):")
                print(f"      进度: {code_pct_est:.2f}% ({codes:,} / ~{EST_TOTAL_BYTECODES:,})")
                print(f"      速度: 🚀 {int(code_speed):,}/s | 剩余: ⏳ {code_eta}")
                print(f"      大小: {format_bytes(codes_bytes)}")

            healed = int(syncing.get('healedTrienodes', '0x0'), 16)
            if healed > 0:
                print("-" * 50)
                print(f"3️⃣  阶段 3: 状态修复 (Healing)")
                print(f"   已修复: {healed:,} 个节点")

            print("==================================================")
            print("按 Ctrl+C 退出监控")
            
            last_time = current_time
            time.sleep(0.5)

    except KeyboardInterrupt:
        print("\n👋 监控已停止。")

if __name__ == "__main__":
    main()