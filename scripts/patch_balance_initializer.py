import os

file_path = "/opt/www/inventory-arbitrage-night/src/services/balance_initializer.py"

# Use concatenation to avoid triple quote conflict
new_method = '''
    async def get_cex_price(self, exchange_name: str, pair_symbol: str) -> Optional[float]:
        """获取 CEX 价格"""
        try:
            exchange = await self.initialize_cex_exchange(exchange_name)
            ticker = await exchange.fetch_ticker(pair_symbol)
            return ticker["last"]
        except Exception as e:
            logger.error(f"获取 CEX 价格失败: {exchange_name} {pair_symbol} - {e}")
            return None
'''

with open(file_path, "r") as f:
    content = f.read()

target = "    async def close(self):"
if "def get_cex_price" in content:
    print("Method already exists.")
else:
    # Ensure we match the indentation of the target
    if target in content:
        new_content = content.replace(target, new_method + "\n" + target)
        with open(file_path, "w") as f:
            f.write(new_content)
        print("Patched balance_initializer.py")
    else:
        print("Target not found!")