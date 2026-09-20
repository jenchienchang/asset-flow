# Backup & Restore

Protect your portfolio data by regularly creating backups. AssetFlow exports all your data to a single ZIP file that can be restored at any time.

## Creating a Backup

1. Open **Settings** (++cmd+comma++) and go to the **Data Management** section.
1. Click **Export Backup**.
1. Choose a location and filename in the save dialog.
1. A ZIP file is created containing all your portfolio data.

AssetFlow normally stores the backup files at the ZIP root. Restore also accepts a ZIP with the files inside one enclosing folder, as can happen when a folder is compressed using Finder or another archive tool.

## What's Included

A backup file contains everything in your portfolio:

- All snapshots and their asset values
- All assets, categories, and platforms
- All cash flow operations
- Exchange rate data
- App settings

## Restoring from Backup

1. Open **Settings** (++cmd+comma++) and go to the **Data Management** section.
1. Click **Restore from Backup**.
1. Select a backup ZIP file.
1. Confirm the restore — this replaces all current data.
1. After restore, exchange rates are automatically re-fetched for all snapshots.

![Data Management in Settings](../../assets/images/settings-security.png)

!!! warning

    Restoring from a backup replaces **ALL** current data. This action cannot be undone. Make sure to export a backup of your current data first if you want to keep it.

!!! tip

    Create regular backups, especially before major changes to your portfolio data. Store backups in a safe location like an external drive or cloud storage.

## See also

- [Preferences](preferences.md): Customize display and import settings
- [Security](security.md): Protect your data with app lock and authentication
