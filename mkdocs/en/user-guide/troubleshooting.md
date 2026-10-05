# Troubleshooting

Solutions to common issues you might encounter while using AssetFlow.

## Exchange Rates

### Exchange rates not loading

- Check your internet connection.
- Try the **Retry** button in the snapshot detail view.
- Exchange rates are fetched from cdn.jsdelivr.net — check if this domain is accessible from your network.
- If you're behind a firewall or VPN, it may block the connection.

### Exchange rates showing as stale or incorrect

- Rates are fetched for the specific snapshot date. Historical rates reflect the actual rate on that date, not today's rate.
- If a rate seems wrong, it may be because the data source uses end-of-day rates, which can differ from intraday rates you see elsewhere.

---

## CSV Import

### Import button is disabled

There are validation errors in the preview. Look for red error markers and fix the issues — common causes include missing columns, duplicate assets, or unparsable values.

### Characters appear garbled after import

Your CSV file may not be saved as UTF-8. Re-export from your spreadsheet application with UTF-8 encoding.

### "Duplicate asset" error

An asset with the same name and platform already exists in the target snapshot. Either rename the asset, change its platform, or remove the duplicate row from the CSV.

---

## Backup & Restore

### Restore seems to have lost data

Restore replaces all current data with the backup contents. If you had newer data that wasn't in the backup, it's gone. Always export a backup of your current data before restoring from an older one.

---

## App Lock

### Touch ID not available

Touch ID requires a Mac with a Touch ID sensor (MacBook Pro/Air with Touch Bar or later). On other Macs, use your system password instead.

### Can't unlock the app

- Try your Mac's system login password — it's always available as a fallback authentication method.
- If you've changed your system password recently, the new password should work.

### App keeps locking too quickly

Adjust the timeout settings in **Settings** (++cmd+comma++) **> Security**. Set "When Switching Apps" and "When Locked or Sleeping" to longer intervals or "Never".

---

## General

### App feels slow with many snapshots

This can happen with very large portfolios (hundreds of assets across many snapshots). Performance depends on your Mac's hardware.

!!! tip

    If you encounter an issue not listed here, try restarting AssetFlow. If the problem persists, you can report it on the project's GitHub page.

## Minimum balance or rebalancing unavailable

Check the latest snapshot, the minimum's original currency and stored exchange rates, and whether percentage targets total 100%. Protected holdings may leave insufficient funds even when total minimums fit. A minimum-only category keeps its surplus; add a percentage target if you want it to participate in allocation. See [Rebalancing](guide/rebalancing.md).

Currency conversion can produce very small rounding differences. These are handled automatically during rebalancing; you do not need to edit balances or goals to remove them.

## See also

- [FAQ](faq.md): Answers to frequently asked questions
- [Preferences](settings/preferences.md): Customize app settings
