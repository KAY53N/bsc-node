
import os

file_path = "/opt/www/inventory-arbitrage-night/run_executor.py"

with open(file_path, "r") as f:
    content = f.read()

# 1. Update get_current_price definition
# We are meticulous about whitespace here.
old_def = "async def get_current_price(settings, redis_client) -> float:"
new_def = "async def get_current_price(settings, redis_client, balance_initializer=None) -> float:"

if old_def in content:
    content = content.replace(old_def, new_def)
    print("Updated get_current_price definition.")

# 2. Add fallback logic to get_current_price
# The context is:
#             if bids and asks:
#                 best_bid = float(bids[0][0]) if bids[0] else 0
#                 best_ask = float(asks[0][0]) if asks[0] else 0
#                 if best_bid > 0 and best_ask > 0:
#                     return (best_bid + best_ask) / 2
# 
#         return None
# 
#     except Exception as e:

# Target the specific block before "return None"
old_block_end = """                if best_bid > 0 and best_ask > 0:
                    return (best_bid + best_ask) / 2

        return None"""

new_block_end = """                if best_bid > 0 and best_ask > 0:
                    return (best_bid + best_ask) / 2

        # Fallback: fetch from CEX directly
        if balance_initializer:
            try:
                price = await balance_initializer.get_cex_price(pair.cex_exchange, pair.cex_symbol)
                if price:
                    return float(price)
            except Exception:
                pass

        return None"""

if old_block_end in content:
    content = content.replace(old_block_end, new_block_end)
    print("Added fallback logic to get_current_price.")
else:
    print("Could not find old_block_end")

# 3. Update main function usage
old_main_block = """    # 📤 发送启动资产报告
    if current_assets:
        # 获取当前价格
        current_price = await get_current_price(settings, redis_client)
        await asset_reporter.send_startup_report(current_assets, current_price)"""

new_main_block = """    # 📤 发送启动资产报告
    if current_assets:
        # 获取当前价格
        price_initializer = BalanceInitializer(redis_client)
        try:
            current_price = await get_current_price(settings, redis_client, price_initializer)
            await asset_reporter.send_startup_report(current_assets, current_price)
        finally:
            await price_initializer.close()"""

if old_main_block in content:
    content = content.replace(old_main_block, new_main_block)
    print("Updated main function logic.")
else:
    print("Could not find old_main_block")

with open(file_path, "w") as f:
    f.write(content)
