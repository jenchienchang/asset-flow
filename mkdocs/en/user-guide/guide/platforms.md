# Platforms

Platforms represent where your assets are held — brokerage accounts, exchanges, banks, or any other custodian. They help you track which assets are on which platform, so you always know where your money lives.

Most of the time, you won't need to create platforms by hand. They're typically auto-created when you import a CSV file or assign a platform while adding an asset.

## Platform List

The left side of the Platforms view shows all your platforms in a sortable list.

- **Drag to reorder** — arrange platforms in whatever order makes sense to you.
- Each row shows the **platform name**, **total value**, and **asset count**.
- **Right-click** any platform to rename it. Renaming preserves its order and selection, and updates a matching default import platform.

Platforms with no assigned assets are hidden. Assigning their name again reuses the same platform.

![Platform list](../../assets/images/platform-list.png)

## Platform Detail

Select a platform from the list to see its detail view on the right side.

- **Name** — displayed at the top. Right-click the platform in the list to rename it.
- **Assets on Platform** — a table listing every asset held on this platform, along with each asset's name and category.
- **Value History** — a line chart showing the platform's total value over time. Use the time range selector to zoom in on a specific period, and hover over any data point to see the exact date and value.

![Platform detail](../../assets/images/platform-detail.png)

!!! note

    You don't need to create platforms manually. They are automatically created when you import CSV data or assign a platform to an asset.

## See also

- [Assets](assets.md): Manage individual assets and assign them to platforms
- [Import CSV](import-csv.md): Bulk-import assets with platform information from a spreadsheet
