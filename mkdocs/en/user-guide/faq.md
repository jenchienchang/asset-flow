# Frequently Asked Questions

## What is a "snapshot"?

A snapshot is a point-in-time record of your entire portfolio. Think of it like a photograph of your finances on a specific date. Each snapshot stores the market value of every asset you own at that moment.

## How often should I create snapshots?

Monthly is a good starting point for most users. Some prefer weekly or even daily. The more frequently you create snapshots, the more detailed your historical data and performance charts will be.

## What's the difference between Growth Rate and Return Rate?

**Growth Rate** is the simple percentage change in total portfolio value, including the effect of deposits and withdrawals. **Return Rate** uses the Modified Dietz method to separate actual investment performance from cash flows, giving you a more accurate picture of how your investments are doing. See [Performance Metrics](guide/performance-metrics.md) for a detailed explanation.

## Where is my data stored?

All data is stored locally on your Mac using Apple's SwiftData framework. No data is sent to external servers. The only network activity is fetching exchange rates from cdn.jsdelivr.net.

## Can I use AssetFlow offline?

Yes. The only feature that requires internet is exchange rate fetching. Everything else works fully offline.

## How do I track assets in different currencies?

Set each asset's currency in its detail view. AssetFlow automatically fetches exchange rates and converts values to your main currency for display. See [Currencies & Exchange Rates](reference/currencies.md) for details.

## Can I import data from my brokerage?

If your brokerage exports CSV files, yes. Export your holdings as CSV, make sure it has "Asset Name" and "Market Value" columns, and use the Import CSV tool. See [CSV Format](reference/csv-format.md) for the expected format.

## What happens if I delete a snapshot?

The snapshot and all its recorded values and cash flows are permanently deleted. The assets themselves remain — they just won't have values for that date anymore.

## Why can't I delete an asset?

Assets can only be deleted when they have no values in any snapshot. First remove the asset from all snapshots, then you can delete it.

## Is my data backed up?

Not automatically. Open **Settings** (++cmd+comma++) and use **Data Management > Export Backup** to create a backup ZIP file. See [Backup & Restore](settings/backup-restore.md) for details.

## Why can minimums and percentages disagree?

Minimums take priority. The calculator reserves protected holdings and adjusts flexible percentage targets proportionally. If funds cannot satisfy all requirements, it shows a shortfall and no trade plan. See [Rebalancing](guide/rebalancing.md) for examples.

## See also

- [Troubleshooting](troubleshooting.md): Solutions to common issues
- [Getting Started](getting-started/quick-start.md): Set up AssetFlow for the first time
