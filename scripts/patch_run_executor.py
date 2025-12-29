# Fallback: fetch from CEX directly
        if balance_initializer:
            try:
                price = await balance_initializer.get_cex_price(pair.cex_exchange, pair.cex_symbol)
                if price:
                    return float(price)
            except Exception:
                pass

        return None

    except Exception as e: