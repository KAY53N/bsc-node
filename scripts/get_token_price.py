import json
import urllib.request
import urllib.error
import sys
import math
import time

# BSC JSON-RPC URL
URL = "http://localhost:8545"
RPC_URL = "https://bsc-mainnet.infura.io/v3/0e95b61f8c324420afb73d5aaf8f5f00"
# Constants for BSC Mainnet
PANCAKESWAP_FACTORY = "0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73"
WBNB_ADDRESS = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c"
USDT_ADDRESS = "0x55d398326f99059fF775485246999027B3197955" # BSC-USD

# Function Selectors
FUNC_GET_PAIR = "0xe6a43905"      # getPair(address,address)
FUNC_GET_RESERVES = "0x0902f1ac"  # getReserves()
FUNC_TOKEN0 = "0x0dfe1681"        # token0()
FUNC_TOKEN1 = "0xd21220a7"        # token1()
FUNC_DECIMALS = "0x313ce567"      # decimals()
FUNC_SLOT0 = "0x3850c7bd"         # slot0()
FUNC_SYMBOL = "0x95d89b41"        # symbol()

def rpc_call(method, params=[]):
    payload = json.dumps({
        "jsonrpc": "2.0",
        "method": method,
        "params": params,
        "id": 1
    }).encode('utf-8')
    
    req = urllib.request.Request(URL, data=payload, headers={'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req) as response:
            res = json.load(response)
            if 'error' in res:
                return None
            return res.get('result')
    except Exception as e:
        print(f"Connection Error: {e}")
        return None

def pad_address(addr):
    """Pads address to 32 bytes for ABI encoding"""
    return "000000000000000000000000" + addr.replace("0x", "").lower()

def decode_address(hex_str):
    """Decodes 32-byte hex string to address"""
    if not hex_str or len(hex_str) < 26: return None
    return "0x" + hex_str[-40:]

def decode_uint(hex_str):
    """Decodes hex string to int"""
    if not hex_str or hex_str == "0x": return 0
    return int(hex_str, 16)

def decode_string(hex_str):
    """Decodes ABI encoded string (simplified)"""
    if not hex_str or hex_str == "0x": return "?"
    try:
        raw = hex_str.replace("0x", "")
        # Check if it's likely a pointer (first word is 32)
        if len(raw) >= 64:
            first_word = int(raw[0:64], 16)
            if first_word == 32:
                length = int(raw[64:128], 16)
                data_hex = raw[128 : 128 + length * 2]
                return bytes.fromhex(data_hex).decode('utf-8')
        
        # Fallback: Try decoding generic bytes if it looks like ASCII
        try:
            return bytes.fromhex(raw).decode('utf-8').rstrip('\x00')
        except:
            return "?"
    except:
        return "?"

def format_block(block):
    """Formats block number to hex if it's an integer string, or returns as is (e.g. 'latest')"""
    if block == "latest": return block
    if block.startswith("0x"): return block
    try:
        return hex(int(block))
    except:
        return block

def eth_call(to_addr, data, block="latest"):
    return rpc_call("eth_call", [{"to": to_addr, "data": data}, block])

def get_decimals(token_addr, block="latest"):
    data = FUNC_DECIMALS
    res = eth_call(token_addr, data, block)
    if not res or res == "0x": return 18
    return decode_uint(res)

def get_symbol(token_addr, block="latest"):
    res = eth_call(token_addr, FUNC_SYMBOL, block)
    if not res: return "?"
    return decode_string(res)

def get_pair(token_a, token_b, block="latest"):
    data = FUNC_GET_PAIR + pad_address(token_a) + pad_address(token_b)
    res = eth_call(PANCAKESWAP_FACTORY, data, block)
    if not res or res == "0x": return None
    return decode_address(res)

def get_reserves(pair_addr, block="latest"):
    data = FUNC_GET_RESERVES
    res = eth_call(pair_addr, data, block)
    if not res or len(res) < 130: return None
    raw = res.replace("0x", "")
    reserve0 = int(raw[0:64], 16)
    reserve1 = int(raw[64:128], 16)
    return reserve0, reserve1

def get_token0(pair_addr, block="latest"):
    res = eth_call(pair_addr, FUNC_TOKEN0, block)
    if not res: return None
    return decode_address(res)

def get_v3_pool_price(pool_address, block="latest"):
    print(f"🔍 Fetching V3 Pool Data for {pool_address} at block {block}...")
    
    t0_addr = get_token0(pool_address, block)
    res_t1 = eth_call(pool_address, FUNC_TOKEN1, block)
    t1_addr = decode_address(res_t1) if res_t1 else None

    if not t0_addr or not t1_addr:
        print("❌ Failed to fetch token addresses from pool.")
        print("   Possible reasons:")
        print("   1. Node is not fully synced (State missing).")
        print("   2. Invalid V3 pool address.")
        print("   3. Pool did not exist at the specified block.")
        return

    sym0 = get_symbol(t0_addr, block)
    sym1 = get_symbol(t1_addr, block)
    dec0 = get_decimals(t0_addr, block)
    dec1 = get_decimals(t1_addr, block)
    
    print(f"   Token0: {sym0} ({t0_addr}) Dec: {dec0}")
    print(f"   Token1: {sym1} ({t1_addr}) Dec: {dec1}")

    # slot0 -> sqrtPriceX96 (uint160)
    res = eth_call(pool_address, FUNC_SLOT0, block)
    if not res or len(res) < 66:
        print("❌ Failed to fetch slot0 (Price data). Node might not be synced or pool unavailable.")
        return
        
    raw = res.replace("0x", "")
    sqrtPriceX96 = int(raw[0:64], 16)
    
    if sqrtPriceX96 == 0:
        print("❌ Pool price is zero.")
        return

    # Calculate Price
    # P = (sqrtPriceX96 / 2^96) ^ 2
    raw_price = (sqrtPriceX96 / (2**96)) ** 2
    
    # Adjust for decimals
    # Price of Token1 per Token0 = raw_price * 10^(d0 - d1)
    price_t1_per_t0 = raw_price * (10**(dec0 - dec1))
    
    # Price of Token0 per Token1
    if price_t1_per_t0 > 0:
        price_t0_per_t1 = 1 / price_t1_per_t0
    else:
        price_t0_per_t1 = 0

    print("-" * 40)
    print(f"💰 Price: 1 {sym0} = {price_t1_per_t0:.8f} {sym1}")
    print(f"💰 Price: 1 {sym1} = {price_t0_per_t1:.8f} {sym0}")
    print("-" * 40)

def run():
    args = sys.argv[1:]
    block = "latest"

    # Parse --block argument
    if "--block" in args:
        try:
            idx = args.index("--block")
            if idx + 1 < len(args):
                block = format_block(args[idx+1])
                # Remove --block and value from args
                args.pop(idx)
                args.pop(idx)
            else:
                print("Error: --block requires a value (e.g. --block 123456)")
                sys.exit(1)
        except ValueError:
            pass

    if len(args) < 1:
        print("Usage:")
        print("  V2: python get_token_price.py <TOKEN_ADDRESS> [BASE_TOKEN_ADDRESS] [--block BLOCK_NUM]")
        print("  V3: python get_token_price.py --v3 <POOL_ADDRESS> [--block BLOCK_NUM]")
        print(f"Default Base Token (V2): WBNB ({WBNB_ADDRESS})")
        sys.exit(1)

    arg1 = args[0]
    
    if arg1 == "--v3":
        if len(args) < 2:
            print("Usage: python get_token_price.py --v3 <POOL_ADDRESS> [--block BLOCK_NUM]")
            sys.exit(1)
        get_v3_pool_price(args[1], block)
        return

    target_token = args[0].lower()
    base_token = args[1].lower() if len(args) > 1 else WBNB_ADDRESS.lower()
    
    print(f"🔍 Looking up V2 pair for {target_token} / {base_token} at block {block}...")
    
    # 1. Get Pair Address
    pair_address = get_pair(target_token, base_token, block)
    
    if not pair_address or pair_address == "0x0000000000000000000000000000000000000000":
        print("❌ Liquidity Pair not found on PancakeSwap V2.")
        sys.exit(0)
        
    print(f"✅ Found Pair: {pair_address}")
    
    # 2. Get Reserves
    reserves = get_reserves(pair_address, block)
    if not reserves:
        print("❌ Could not fetch reserves.")
        sys.exit(1)
        
    reserve0, reserve1 = reserves
    
    # 3. Determine which reserve is which
    token0_addr = get_token0(pair_address, block)
    
    if token0_addr.lower() == target_token:
        target_reserve = reserve0
        base_reserve = reserve1
    else:
        target_reserve = reserve1
        base_reserve = reserve0

    # 4. Get Decimals
    target_decimals = get_decimals(target_token, block)
    base_decimals = get_decimals(base_token, block)
    
    # 5. Calculate Price
    if target_reserve == 0:
        print("❌ Liquidity is zero.")
        sys.exit(0)

    price = (base_reserve / (10**base_decimals)) / (target_reserve / (10**target_decimals))
    
    base_symbol = "BNB" if base_token == WBNB_ADDRESS.lower() else "BaseToken"
    if base_token == USDT_ADDRESS.lower(): base_symbol = "USDT"

    print("-" * 40)
    print(f"💰 Price: {price:.8f} {base_symbol}")
    print(f"📊 Reserves: {target_reserve / 10**target_decimals:,.2f} Target / {base_reserve / 10**base_decimals:,.2f} {base_symbol}")
    print("-" * 40)
    
def main():
    start_time = time.perf_counter()
    run()
    print("执行免费PRC业务代码...")
    end_time = time.perf_counter()
    elapsed_time = end_time - start_time
    print(f"\n代码执行耗时：{elapsed_time:.4f} 秒")
    
    start_time = time.perf_counter()

    # -------------------- 你的业务代码（替换成自己的） --------------------
    # 示例：模拟耗时操作（你删除这行，替换成自己的代码）
    print("执行本地业务代码...")
    URL = RPC_URL
    run()
    # 2. 记录结束时间
    end_time = time.perf_counter()

    # 3. 计算并输出耗时（保留4位小数，可调整）
    elapsed_time = end_time - start_time
    print(f"\n代码执行耗时：{elapsed_time:.4f} 秒")


if __name__ == "__main__":
    main()




