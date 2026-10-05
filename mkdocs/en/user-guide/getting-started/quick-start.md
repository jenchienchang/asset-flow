# Quick Start

This guide walks you through two ways to start tracking your portfolio in AssetFlow. Pick the path that fits your situation best.

---

## Option A: Import from CSV (Recommended for Existing Portfolios)

If you already have your holdings in a spreadsheet, CSV import is the fastest way to get started.

1. Open AssetFlow.

1. Navigate to **Tools > Import CSV** in the sidebar, or press ++cmd+i++.

1. Select **Assets** as the import type.

1. Drag and drop your CSV file onto the import area, or click **Browse** to select it from Finder.

    !!! info "Expected CSV columns"

        Your file should include at least an **Asset Name** and **Market Value** column. **Platform** and **Currency** columns are optional — if omitted, you can set defaults during import.

1. Configure the import settings: pick a **snapshot date**, and optionally assign a default **platform** and **category** for the imported assets.

1. Review the preview table. AssetFlow will highlight any validation errors so you can fix them before importing.

1. Click **Import** to bring everything in.

![Import CSV](../../../assets/images/import-csv-file.png)

!!! tip

    You can always edit imported assets after the fact. Don't worry about getting everything perfect on the first try.

---

## Option B: Create a Snapshot Manually

Prefer to enter things by hand? You can build your portfolio directly in the app.

1. Navigate to **Portfolio > Snapshots** in the sidebar.
1. Click the **+** button in the toolbar, or press ++cmd+n++.
1. Choose a **date** for the snapshot.
1. Choose a **creation mode**:
    - **Bulk Entry** (default) — a full-screen view where you enter values for all assets at once, grouped by platform. You can create new assets and platforms inline, and import CSV files per platform.
    - **Empty Snapshot** — a blank snapshot where you add assets one by one in the detail view.
1. Click **Create**.

![Create snapshot](../../../assets/images/snapshot-create.png)

!!! tip

    **Bulk Entry** is the fastest way to build a snapshot from scratch — you can add platforms and assets inline without switching between screens. See [Bulk Entry](../guide/bulk-entry.md) for a full walkthrough.

!!! note

    Each snapshot captures your portfolio at a single point in time. You'll create new snapshots whenever you want to record an update — for example, at the end of each month.

---

## Set Up Categories

Categories help you organize your assets and define your target allocation. Setting them up early makes the rebalancing tool much more useful.

1. Navigate to **Portfolio > Categories** in the sidebar.
1. Click **+** to create a new category (for example: Equities, Bonds, Cash, Real Estate).
1. For each category, set a **target allocation percentage** — these should add up to 100%.
1. Navigate to **Portfolio > Assets** and assign each asset to the appropriate category.

!!! example "Sample categories"

    | Category | Target Allocation |
    | -------- | ----------------- |
    | Equities | 60%               |
    | Bonds    | 30%               |
    | Cash     | 10%               |

---

## Explore the Dashboard

Once you have at least one snapshot with assets, the dashboard comes to life.

1. Navigate to **Overview** in the sidebar to see your portfolio summary.
1. Browse the **allocation charts** to see how your current holdings compare to your targets.
1. Check the **performance metrics** to track growth over time.

![Dashboard](../../../assets/images/app-overview.png)

!!! tip

    The more snapshots you create over time, the richer your performance charts and metrics become. Try to record a snapshot regularly — monthly is a good cadence for most people.

---

## Add an optional minimum balance

Alongside percentage targets, a category can have a minimum balance with its own currency. Percentage targets must total 100% for an actionable plan. Minimums take priority and categories without percentages retain their balances. See [Categories](../guide/categories.md).

## See also

- [Dashboard](../guide/dashboard.md): Deep dive into the overview screen
- [Import CSV](../guide/import-csv.md): Detailed CSV import guide and format reference
- [Categories](../guide/categories.md): Managing categories and target allocations
- [Snapshots](../guide/snapshots.md): Working with portfolio snapshots
