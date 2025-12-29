
import sys
import os

# Add project root to path
sys.path.append("/opt/www/inventory-arbitrage-night")

from src.services.arbitrage_executor import ArbitrageExecutor
import inspect

print("Checking ArbitrageExecutor for monitor_redis_client...")
if hasattr(ArbitrageExecutor, 'monitor_redis_client'):
    print("Found as class attribute")
else:
    print("Not a class attribute")

# Check __init__ source code
init_source = inspect.getsource(ArbitrageExecutor.__init__)
if "self.monitor_redis_client =" in init_source:
    print("Found assignment in __init__")
    for line in init_source.split('\n'):
        if "self.monitor_redis_client =" in line:
            print(f"Assignment line: {line.strip()}")
else:
    print("Not assigned in __init__")

# Check properties
for name, member in inspect.getmembers(ArbitrageExecutor):
    if name == 'monitor_redis_client':
        print(f"Found member: {member}")
