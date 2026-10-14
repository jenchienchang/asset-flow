# Assets

Assets represent individual investments in your portfolio — stocks, bonds, ETFs, crypto, cash accounts, or anything else you want to track. Each asset belongs to a category, is associated with a platform, and has a currency.

## Asset List

The left side of the Assets view shows all your assets. You can toggle between two grouping modes using the button in the toolbar:

- **By Platform** — groups assets under the broker or service where they're held.
- **By Category** — groups assets by their investment category.

Each row shows:

- Asset name
- Platform
- Category
- Latest value (with a currency badge if the asset isn't in your main currency)

Right-click an asset for a context menu. The **Delete** option is only available if the asset has no values recorded in any snapshot.

![Asset list](../../assets/images/asset-list.png)

### Hiding stale assets

The toolbar includes a **Hide Stale Assets** toggle button (eye-with-slash icon). When it's active (the default), assets that are missing from your most recent snapshot are hidden, keeping the list focused on your current portfolio. Click the button to bring closed positions and assets you no longer hold back into view. Your choice is remembered across app launches and when you switch to other views.

!!! note

    A "stale" asset is one with no value in the latest snapshot. Its row would otherwise show an em dash (—) where the value normally appears.

## Asset Detail

Select an asset to see its full detail on the right side.

### Properties

All properties are editable directly in the detail view:

- **Name** — the display name for the asset.
- **Platform** — choose from existing platforms or create a new one inline.
- **Category** — choose from existing categories or create a new one inline.
- **Currency** — select from the list of supported currencies.

### Value History

The value history section shows how the asset's value has changed over time.

- **Time range selector** — choose from **All**, **1Y**, **3M**, or **1M** to zoom in on a specific period.
- **Line chart** — a visual plot of the asset's value over time. Hover over any point to see a tooltip with the exact date and value.
- **Show Converted Value** toggle — this only appears for assets in a currency different from your main currency. When enabled, the chart shows values converted using each snapshot's exchange rate. If a rate is unavailable, that date has no converted point; a dashed marker identifies it, and the line stops across the gap. A compact warning shows the number of days with unavailable exchange rates; click it to see their dates. If no values can be converted in the selected period, the chart shows an unavailable message. Switch back to see the complete history in the asset's original currency.
- **Value history table** — below the chart, a table lists every recorded value with columns for Date, Market Value, and Converted Value when applicable. A dash (—) in Converted Value means the historical rate is unavailable. Double-click or right-click any row to edit the value for that snapshot.

![Asset detail](../../assets/images/asset-detail.png)

## Deleting Assets

Assets can only be deleted when they have **no values in any snapshot**. If the asset still has recorded values, the delete button will be disabled with an explanation.

To fully remove an asset:

1. Remove it from every snapshot where it appears (right-click the asset in each snapshot's breakdown and select **Remove**).
1. Once the asset has no snapshot values, you can delete it from the asset list.

!!! note

    Assets are typically created through CSV import or by adding them to a snapshot. You don't need to create assets separately — they're created on the fly when you first add them to a snapshot.

## See also

- [Snapshots](snapshots.md): Manage snapshots and edit asset values
- [Categories](categories.md): Organize assets into groups
- [Platforms](platforms.md): Manage the platforms where your assets are held
- [Import CSV](import-csv.md): Bulk-import assets and values from a spreadsheet
