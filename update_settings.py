import os

file_path = "/opt/www/cash-carry-arbitrage/src/config/settings.py"

with open(file_path, "r") as f:
    lines = f.readlines()

# Check if already updated
if any("class SpotFuturesConfig" in line for line in lines):
    print("Already updated")
    exit(0)

# Define new content
new_classes = '''
# ============== 现货合约套利配置 ============== 

class SpotFuturesPairConfig(BaseModel):
    """现货合约套利对配置"""
    exchange: str
    spot_symbol: str
    futures_symbol: str
    open_threshold_percent: float = 1.0  # 开仓阈值 (价差百分比)
    close_threshold_percent: float = 0.0  # 平仓阈值 (价差百分比)
    min_trade_amount: float = 1.0
    max_trade_amount: float = 1000.0
    leverage: int = 1  # 合约杠杆倍数

class SpotFuturesConfig(BaseModel):
    """现货合约套利全局配置"""
    enabled: bool = False
    check_interval: float = 1.0
    pairs: list[SpotFuturesPairConfig] = []
'''

# Find insertion point for classes (before class Settings)
insert_idx = -1
for i, line in enumerate(lines):
    if line.strip().startswith("class Settings(BaseModel):"):
        insert_idx = i
        break

if insert_idx != -1:
    lines.insert(insert_idx, new_classes + "\n\n")
else:
    print("Could not find class Settings")
    exit(1)

# Find insertion point for field in Settings
settings_start = -1
for i, line in enumerate(lines):
    if line.strip().startswith("class Settings(BaseModel):"):
        settings_start = i
        break

field_insert_idx = -1
for i in range(settings_start, len(lines)):
    if lines[i].strip().startswith("logging: LoggingConfig"):
        field_insert_idx = i
        break

if field_insert_idx != -1:
    lines.insert(field_insert_idx, "    spot_futures: SpotFuturesConfig = SpotFuturesConfig()\n")
else:
    print("Could not find logging field")
    exit(1)

with open(file_path, "w") as f:
    f.writelines(lines)

print("Updated settings.py")