# Currencies & Exchange Rates

AssetFlow supports multiple currencies and requests exchange rates for converted portfolio values. A converted result is unavailable when a required rate is missing.

## How It Works

- Each asset can be tracked in its own currency (e.g., US stocks in USD, Taiwanese stocks in TWD).
- Exchange rates are fetched automatically for each snapshot date.
- Converted values use your selected display currency when the required rates are available. You can change that currency in **Settings** (++cmd+comma++) **> Preferences**.
- **Source**: Exchange rates are fetched from cdn.jsdelivr.net, which provides open-source rate data.

## Supported Currencies

AssetFlow ships with a built-in list of common currencies. When the app loads, it requests an expanded currency list from the exchange rate API and caches successful results for offline use.

### Built-in Currencies

These currencies are always available, even without an internet connection:

| Code | Currency          |     | Code | Currency           |
| ---- | ----------------- | --- | ---- | ------------------ |
| AED  | UAE Dirham        |     | KRW  | South Korean Won   |
| AUD  | Australian Dollar |     | MXN  | Mexican Peso       |
| BRL  | Brazilian Real    |     | MYR  | Malaysian Ringgit  |
| BTC  | Bitcoin           |     | NOK  | Norwegian Krone    |
| CAD  | Canadian Dollar   |     | NZD  | New Zealand Dollar |
| CHF  | Swiss Franc       |     | PHP  | Philippine Peso    |
| CNY  | Chinese Yuan      |     | PLN  | Polish Zloty       |
| DKK  | Danish Krone      |     | SAR  | Saudi Riyal        |
| ETH  | Ethereum          |     | SEK  | Swedish Krona      |
| EUR  | Euro              |     | SGD  | Singapore Dollar   |
| GBP  | British Pound     |     | THB  | Thai Baht          |
| HKD  | Hong Kong Dollar  |     | TRY  | Turkish Lira       |
| IDR  | Indonesian Rupiah |     | TWD  | New Taiwan Dollar  |
| ILS  | Israeli Shekel    |     | USD  | US Dollar          |
| INR  | Indian Rupee      |     | VND  | Vietnamese Dong    |
| JPY  | Japanese Yen      |     | ZAR  | South African Rand |

### Full Currency List

After a successful currency-list request, AssetFlow caches the provider's list of available currencies from the [exchange rate API](https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies.json). This includes hundreds of fiat and crypto currencies beyond the built-in list above.

You can view the full list of supported currency codes by opening the [API endpoint](https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies.json) in your browser.

## Auto-Fetch Behavior

Exchange rates are fetched automatically in several situations:

- **New or imported snapshot** — the app requests rates needed for its asset, cash-flow, and goal currencies.
- **App launch and restore** — the app checks existing snapshots and requests rates that are missing or no longer cover the required currencies.
- **Currency changes** — changing the display currency or a recorded or goal currency can require new rates.

## When Rates Can't Be Fetched

If you're offline or experiencing network issues:

- The app shows a **Retry** button in the snapshot detail view so you can try again later.
- Native amounts remain available where the screen shows them; converted totals and rate-dependent calculations are marked unavailable.
- You can keep recording and reviewing portfolio data offline. Fetching the expanded currency list or missing rates requires a connection.

!!! note

    AssetFlow stores fetched rates locally. It can reuse them offline when they match the snapshot date and display currency and cover every currency needed for the result.

## Minimum balance currencies

Each category minimum retains an explicit original currency. Changing display currency preserves it. Compare category holdings and minimums using each snapshot's stored rates. A goal currency may need fetching even when no asset uses it; offline or missing goal-only rates make goal comparisons/rebalancing unavailable while valid asset statistics remain visible.

## See also

- [Preferences](../settings/preferences.md): Set your main display currency
- [Assets](../guide/assets.md): Manage assets and their currencies
- [CSV Format](csv-format.md): Specify currencies in CSV imports
