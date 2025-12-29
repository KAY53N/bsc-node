import yaml

config_path = "/opt/www/cash-carry-arbitrage/config.yaml"

with open(config_path, "r") as f:
    config = yaml.safe_load(f)

# 1. Add futures symbol
for exchange in config['cex']['exchanges']:
    if exchange['name'] == 'bybit':
        if "CARV/USDT:USDT" not in exchange['symbols']:
            exchange['symbols'].append("CARV/USDT:USDT")

# 2. Add spot_futures config
config['spot_futures'] = {
    'enabled': True,
    'check_interval': 1.0,
    'pairs': [
        {
            'exchange': 'bybit',
            'spot_symbol': 'CARV/USDT',
            'futures_symbol': 'CARV/USDT:USDT',
            'open_threshold_percent': 0.5,
            'close_threshold_percent': 0.1,
            'min_trade_amount': 10.0,
            'max_trade_amount': 1000.0,
            'leverage': 1
        }
    ]
}

with open(config_path, "w") as f:
    yaml.dump(config, f, sort_keys=False, allow_unicode=True)

print("Updated config.yaml")
