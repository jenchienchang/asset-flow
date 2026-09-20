# Snapshots

Snapshots are the core concept in AssetFlow. Each snapshot captures your entire portfolio's state at a specific point in time — like a photograph of your finances. By comparing snapshots over time, AssetFlow can calculate your performance, track allocation changes, and show you how your portfolio evolves.

## Snapshot List

The left side of the Snapshots view shows all your snapshots, grouped by time period: **This Month**, **Previous 3 Months**, **Previous 6 Months**, **Previous Year**, and **Older**.

Each row displays:

- Snapshot date
- Platform badges (up to 3 visible, with a **+N** overflow indicator if you have more)
- Total portfolio value
- Asset count

Right-click any snapshot for a context menu with the option to **Delete** it.

![Snapshot list](../../assets/images/snapshot-list.png)

## Creating a New Snapshot

Click the **+** button in the toolbar or press ++cmd+n++ to create a new snapshot.

You'll be asked to:

1. **Choose a date** — the snapshot date cannot be in the future, and you can't have two snapshots on the same date. If the selected date already has a snapshot, a warning appears and the Create button is disabled.
1. **Choose a creation mode**:
    - **Bulk Entry** (default) — opens a full-screen view where you can enter values for all your assets at once, grouped by platform. Previous values are carried forward for reference. This is the recommended workflow for monthly updates.
    - **Empty Snapshot** — creates a blank snapshot and takes you to the snapshot detail view, where you can add assets one by one.

![Create snapshot](../../assets/images/snapshot-create.png)

!!! tip

    Use **Bulk Entry** for monthly updates — all your assets are pre-loaded from the latest snapshot, so you just update the values that changed. See [Bulk Entry](bulk-entry.md) for a full walkthrough.

## Snapshot Detail

The right side shows the detail view for the selected snapshot.

### Summary

At the top, you'll see:

- **Total Value** — one value in the display currency when every required exchange rate is available. If a rate is missing, totals are shown grouped by their original currencies instead.
- **Net Cash Flow** — the converted total when rates are complete, or native-currency totals when conversion is unavailable
- **Exchange Rate Status** — whether all rates required by this snapshot are valid and available

### Asset Breakdown

A table listing every asset in the snapshot with its market value. For multi-currency assets, both the original currency value and the converted value are shown.

- **Right-click** an asset to edit its value or remove it from the snapshot.
- **Add Asset** — click to add an existing asset to this snapshot, or create a new asset on the spot.

### Category Allocation

Shows all categories represented in this snapshot, with their values and percentage of the total portfolio. If required rates are missing, this section remains visible but is marked unavailable.

### Exchange Rates

Displays every exchange rate needed for currency conversions. Rates are auto-fetched when you create a snapshot or open a snapshot with incomplete cached data. Missing or invalid rates are shown explicitly, and **Retry** fetches fresh data. The app never labels native values as the display currency when conversion has not succeeded.

### Cash Flow Operations

Lists all deposits and withdrawals recorded for this snapshot. Right-click any entry to edit or remove it. Use the **Add Cash Flow** button to record a new deposit or withdrawal.

![Snapshot detail](../../assets/images/snapshot-detail.png)

## Editing Asset Values

There are two ways to edit an asset's value within a snapshot:

1. **Right-click** the asset in the breakdown and select **Edit Value**.
1. **Double-click** the value directly.

A popover will appear where you can enter the new market value.

![Edit value](../../assets/images/snapshot-edit-value.png)

## Deleting a Snapshot

To delete a snapshot, scroll to the **Danger Zone** at the bottom of the snapshot detail view and click **Delete Snapshot**. A confirmation dialog will appear showing the snapshot date, asset count, and cash flow count so you know exactly what will be removed.

!!! warning

    Deleting a snapshot permanently removes all recorded values and cash flows for that date. The assets themselves are **not** deleted — they will still exist and appear in other snapshots.

## See also

- [Bulk Entry](bulk-entry.md): Enter values for all assets in a single session
- [Cash Flows](cash-flows.md): Record deposits and withdrawals for each snapshot
- [Assets](assets.md): Manage your individual investments
- [Import CSV](import-csv.md): Bulk-import snapshot data from a spreadsheet
