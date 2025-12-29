
file_path = "/opt/www/inventory-arbitrage-night/src/services/arbitrage_executor.py"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# Step 1: Add wall clock time capture
old_str_1 = """        # ⏱️ 记录开始时间（使用 perf_counter 获得更高精度）
        execute_start_time = time.perf_counter()

        if not self.config.enabled:"""

new_str_1 = """        # ⏱️ 记录开始时间（使用 perf_counter 获得更高精度）
        execute_start_time = time.perf_counter()
        execute_start_wall_time = time.time()

        if not self.config.enabled:"""

if old_str_1 in content:
    content = content.replace(old_str_1, new_str_1)
    print("Step 1 replacement success")
else:
    print("Step 1 replacement failed: pattern not found (Check whitespace/indentation)")

# Step 2: Use wall clock time for latency calculation
old_str_2 = """            # ⏱️ 计算从发现机会到开始执行的延迟
            discovery_to_execute_delay = (execute_start_time - opportunity.timestamp.timestamp()) * 1000  # 毫秒"""

new_str_2 = """            # ⏱️ 计算从发现机会到开始执行的延迟
            discovery_to_execute_delay = (execute_start_wall_time - opportunity.timestamp.timestamp()) * 1000  # 毫秒"""

if old_str_2 in content:
    content = content.replace(old_str_2, new_str_2)
    print("Step 2 replacement success")
else:
    print("Step 2 replacement failed: pattern not found (Check whitespace/indentation)")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
