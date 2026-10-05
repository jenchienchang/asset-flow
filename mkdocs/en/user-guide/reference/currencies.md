# Currencies & Exchange Rates

AssetFlow supports multiple currencies and automatically fetches exchange rates to convert all values to your main display currency.

## How It Works

- Each asset can be tracked in its own currency (e.g., US stocks in USD, Taiwanese stocks in TWD).
- Exchange rates are fetched automatically for each snapshot date.
- All values are converted to your main currency for display. You can change your main currency in **Settings** (++cmd+comma++) **> Preferences**.
- **Source**: Exchange rates are fetched from cdn.jsdelivr.net, which provides open-source rate data.

## Supported Currencies

AssetFlow ships with a built-in list of common currencies. On first launch (and periodically thereafter), the app fetches an expanded currency list from the exchange rate API and caches it locally for offline use.

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

After the first successful network connection, AssetFlow fetches the complete list of available currencies from the [exchange rate API](https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies.json) and caches it locally. This includes hundreds of fiat and crypto currencies beyond the built-in list above.

You can view the full list of supported currency codes by opening the [API endpoint](https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies.json) in your browser.

## Auto-Fetch Behavior

Exchange rates are fetched automatically in several situations:

- **New snapshot** — when you create a snapshot that includes assets in multiple currencies, rates for that date are fetched immediately.
- **App launch** — any missing rates for existing snapshots are fetched in the background.
- **After restore** — when you restore from a backup, rates are re-fetched for all snapshots.

## When Rates Can't Be Fetched

If you're offline or experiencing network issues:

- The app shows a **Retry** button in the snapshot detail view so you can try again later.
- Values are shown unconverted, in their original currencies.
- Everything else in the app works fully offline — exchange rates are the only network feature.

!!! note

    AssetFlow stores fetched exchange rates locally. Once rates are fetched for a snapshot, they don't need to be re-fetched even when offline.

## Minimum balance currencies

Each category minimum retains an explicit original currency. Changing display currency preserves it. Compare category holdings and minimums using each snapshot's stored rates. A goal currency may need fetching even when no asset uses it; offline or missing goal-only rates make goal comparisons/rebalancing unavailable while valid asset statistics remain visible.

## See also

- [Preferences](../settings/preferences.md): Set your main display currency
- [Assets](../guide/assets.md): Manage assets and their currencies
- [CSV Format](csv-format.md): Specify currencies in CSV imports
