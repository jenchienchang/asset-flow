# Asset Allocation & Portfolio Management App

**Product & Technical Specification (v1.3)**

______________________________________________________________________

## 1. Overview

A macOS desktop application for long-term asset allocation management.

**Target users:**

- Maintain portfolios across multiple platforms (brokerages, banks, crypto exchanges)
- Prefer local-first portfolio tracking
- Manage asset allocation manually (currently via spreadsheet)
- Want structured historical portfolio tracking

**This is NOT:**

- A trading app
- A real-time price tracker
- A brokerage integration

**Core value proposition:**

- Portfolio-level return analysis
- Snapshot-based portfolio tracking
- Deterministic rebalancing calculations
- Structured CSV import workflow

**Platform scope (v1):** macOS only (macOS 15.0+)

______________________________________________________________________

## 2. Core Concept: Snapshot-Based Portfolio Model

The system is built around **portfolio snapshots**.

A snapshot represents the best-known portfolio state at a specific date.

**Key rules:**

1. The CSV file does NOT contain a date. The user explicitly selects a date when importing.
1. Snapshots are append-only — a new import never silently overwrites an existing snapshot.
1. A snapshot contains only directly-recorded SnapshotAssetValues. There is no automatic carry-forward. Users can pre-populate values from prior snapshots via "Bulk Entry" (manual creation) or the copy-forward option during CSV import.
1. Users may delete or edit snapshots after creation (see Section 8).

______________________________________________________________________

## 3. User Interface Design

### 3.1 Navigation Structure

The app uses a **sidebar navigation** layout (standard macOS pattern):

**Sidebar items:**

1. **Dashboard** — Portfolio overview (default/home screen)
1. **Snapshots** — Chronological snapshot management
1. **Assets** — Asset registry and category assignment
1. **Categories** — Category management with target allocations
1. **Platforms** — Platform management (rename)
1. **Rebalancing** — Rebalancing calculator
1. **Import** — CSV import workflow

**Detail views:** Each sidebar section that has a list+detail pattern (Snapshots, Assets, Categories, Platforms) uses a **list-detail split** within the content area. The list appears on the leading side and the detail view appears on the trailing side. Selecting an item in the list reveals its detail. When no item is selected, the detail area shows a placeholder prompt (e.g., "Select a snapshot to view details"). Dashboard, Rebalancing, and Import occupy the full content area without a list-detail split.

**Toolbar:**

- Import button (opens the same import flow as the sidebar Import item)

______________________________________________________________________

### 3.2 Dashboard (Home Screen)

The dashboard provides a portfolio overview using the latest snapshot.

**Layout:**

1. **Summary cards row:**

   - Total Portfolio Value
   - Latest Snapshot Date
   - Number of Assets
   - Cumulative TWR (All Time) (since first snapshot)
   - CAGR (since first snapshot) — shown alongside Cumulative TWR (All Time), with a tooltip: "CAGR is the annualized rate at which the portfolio's total value has grown since inception, including the effect of deposits and withdrawals. TWR measures pure investment performance by removing cash flow effects."
   - Each metric card (TWR, CAGR, Growth, Return) includes an info icon/tooltip explaining what the metric measures and how it differs from related metrics.

1. **Period performance cards:**

   - **Growth Rate** card — simple percentage change in portfolio value (see Section 10.3). Includes a 1M / 3M / 1Y segmented control to switch between periods. Shows "N/A" if insufficient snapshot history for the selected period.
   - **Return Rate** card — Modified Dietz return, cash-flow adjusted (see Section 10.4). Includes a 1M / 3M / 1Y segmented control to switch between periods. Shows "N/A" if insufficient snapshot history for the selected period.
   - Each card includes an info icon/tooltip explaining what the metric measures and how it differs from the other.

1. **Allocation pie chart:**

   - Category allocation with a **snapshot date picker** (defaults to latest snapshot)
   - Shows percentage and value for each category
   - Clicking a category navigates to category detail

1. **Portfolio value line chart:**

   - Total portfolio value over all snapshots
   - Time axis with snapshot dates

1. **Cumulative TWR line chart:**

   - Portfolio-level cumulative time-weighted return over time (see Section 12.4)
   - Shows "Insufficient data (need at least 2 snapshots)" when fewer than 2 snapshots exist

1. **Recent snapshots list:**

   - Last 5 snapshots (newest first) with date, total value, and import summary
   - "View all" link navigates to Snapshots screen
   - Each row is clickable and navigates to the snapshot's detail view

______________________________________________________________________

### 3.3 Snapshots Screen

**List view:**

- Chronological list of all snapshots (newest first)
- Each row shows: date, total value, platforms included, number of assets
- "New Snapshot" button

**New Snapshot creation modes:**

- **Start empty**: Creates snapshot with no asset entries
- **Bulk Entry** (default): Opens a full-screen editable table with all assets from the latest snapshot grouped by platform. Users enter new market values directly. Features include:
  - Per-platform "Add Asset" button for inline asset creation (name, currency, category)
  - "Add Platform" toolbar button for creating new platform groups
  - Category picker for new assets (deferred DB creation until save)
  - Per-platform CSV import to populate values from exported brokerage data
  - Include/exclude checkbox per row to control which assets are saved
  - Previous value column for reference
  - Zero-value warning for assets saved with a market value of 0
  - Duplicate asset name validation within a platform (case-insensitive)
  - Tab/Enter keyboard navigation between value fields (assets and cash flows)
  - Self-sufficient empty state when no prior snapshots exist

**Snapshot detail view** (on selection):

- Full asset breakdown table sorted by platform (alphabetical), then by asset name (alphabetical) within each platform: Asset Name, Platform, Category, Market Value
- Zero-value warning indicator on assets with a market value of 0
- Category allocation summary for this snapshot
- Cash flow operations table: lists all CashFlowOperations for this snapshot (Description, Amount)
- Per-currency net cash flow summary lines showing the total for each currency
- Actions: Add asset, Edit values, Remove asset, Delete snapshot, Add cash flow, Edit cash flow, Remove cash flow

______________________________________________________________________

### 3.4 Assets Screen

**List view:**

- All known assets, grouped by platform (default) or category, switchable via a **segmented control** at the top of the list
- Sort order: alphabetical by asset name (within each group when grouped)
- When grouped by platform, assets without a platform appear under a "(No Platform)" group at the end of the list.
- Each row: Asset Name, Platform, Category, Latest Value

**Asset detail view:**

- Value history across snapshots (newest first in the table and chronological in the chart)
- Asset name (editable)
- Platform (editable)
- Category assignment (editable)
- Currency (editable) — ISO 4217 picker; sets the asset's native currency. Used for FX conversion display.
- **Converted value column and chart toggle:** When the asset's currency differs from the display currency (Settings), the value history table gains a "Converted Value" column showing each snapshot's market value converted to the display currency via the snapshot's stored ExchangeRate. A currency-code toggle button appears in the section header; clicking it switches the sparkline chart between the native-currency view (blue) and the converted-value view (green). The toggle is hidden when the asset currency matches the display currency or when no currency is set.
- Delete action: **only enabled when the asset has no SnapshotAssetValue records in any snapshot**. When disabled, shows explanatory text: "This asset cannot be deleted because it has values in snapshot(s). Remove the asset from all snapshots first." (See Section 6.3)

______________________________________________________________________

### 3.5 Categories Screen

**List view:**

- All categories listed alphabetically by category name
- Each row shows: name, requested pool percentage, labelled current/effective shares of the total portfolio, current value, minimum status, and asset count
- One warning indicator for any positive minimum shortfall and/or deviation of more than 5 percentage points from a feasible effective target. Minimum-only surplus is protected; no-goal categories have no effective target. Effective shares are unavailable for infeasible plans, missing conversion or zero portfolio total; independently determinable minimum shortfalls still warn.
- Add/edit/delete category actions

**Category detail view:**

- Assets in this category
- Value history over snapshots (line chart)
- Allocation percentage history over snapshots (line chart: X-axis = snapshot dates, Y-axis = allocation %, one line for this category)

Clicking a category in the dashboard pie chart (Section 3.2) selects that category in the sidebar's Categories section and shows its detail view.

______________________________________________________________________

### 3.6 Platforms Screen

**List view:**

- All platforms listed alphabetically
- Each row: Platform name, number of assets, total latest value (from latest snapshot)

**Actions:**

- **Rename** — Change the platform name. Updates all assets with that platform. The new name must not conflict with an existing platform (case-insensitive).
- **Delete** — Implicitly handled: when all assets are moved away from a platform (via rename or asset deletion), the platform no longer appears in the list.

Assets with no platform are not shown on the Platforms screen. They appear on the Assets screen under a "(No Platform)" group when grouped by platform.

______________________________________________________________________

### 3.7 Rebalancing Screen

- Column order: Category, Current balance, Current %, Effective target balance, Effective target %, Change, Action, Minimum. Both current and effective percentages use the entire portfolio; unavailable effective shares show an em dash.
- For each category: current value/share of total, minimum, effective target balance/share, difference, and action/status. Configured percentage inputs appear in category settings and relevant category calculations
- Sort order: by absolute adjustment magnitude (largest deviation first)
- Summary of suggested moves (e.g., "Move $25,000 from Equities to Bonds")
- This is read-only/preview — no data modification occurs
- Categories with a percentage target or minimum balance are included; protected holdings appear separately

______________________________________________________________________

### 3.8 Import Screen

See Section 4 (CSV Import System) for detailed flow.

______________________________________________________________________

### 3.9 Empty States

Each screen must handle the empty/first-run case:

| Screen      | Empty State                                                                                                                 |
| ----------- | --------------------------------------------------------------------------------------------------------------------------- |
| Dashboard   | Welcome message, prominent "Import your first CSV" button, brief explanation of the app's workflow                          |
| Snapshots   | "No snapshots yet. Create your first snapshot or import a CSV to get started." with "New Snapshot" and "Import CSV" buttons |
| Assets      | "No assets yet. Assets are created automatically when you import CSV data."                                                 |
| Categories  | "No categories yet. Create categories to organize your assets and set target allocations." with "Create Category" button    |
| Platforms   | "No platforms yet. Platforms are created automatically when you import CSV data or create assets."                          |
| Rebalancing | "Set target allocations on your categories to use the rebalancing calculator."                                              |

______________________________________________________________________

### 3.10 Settings

Accessible via menu bar (AssetFlow > Settings) or keyboard shortcut (Cmd+,).

**Settings options:**

1. **Display currency** — Currency code for displaying all converted portfolio values (e.g., USD, TWD, EUR). Asset values recorded in a different currency are converted to this currency using the exchange rates stored in the snapshot's ExchangeRate record (see Section 7.6).

1. **Date format** — A picker listing all date format styles natively supported by Swift's `Date.FormatStyle` (e.g., `.numeric` → "1/5/2025", `.abbreviated` → "Jan 5, 2025", `.long` → "January 5, 2025", `.complete` → "Sunday, January 5, 2025"). Default: system locale format if it maps to a supported style, otherwise `.abbreviated`.

1. **Default platform** — Pre-filled platform value during import (can be overridden per import) **Defaults:** Display currency: USD. Date format: system locale (fallback: `.abbreviated`). Default platform: empty (no pre-fill).

1. **Data Management**

   - **Export Backup** — Exports all application data to a **ZIP archive** containing:
     - One CSV file per entity: `assets.csv`, `categories.csv`, `snapshots.csv`, `snapshot_asset_values.csv`, `cash_flow_operations.csv`, `exchange_rates.csv` (optional — omitted when no exchange rate data exists), `settings.csv`
     - A `manifest.json` file containing: format version identifier (e.g., `"formatVersion": 1`), export timestamp, and app version
     - Backup CSV files use the data model field names (Section 7) as column headers. Each row represents one record. UUID fields are serialized as standard UUID strings. Decimal fields are serialized at full precision. Date fields use ISO 8601 timestamps. Optional/nullable fields use an empty string for null values. The CSV files are internal to the backup format and are not intended for direct user editing.
     - User selects save location via standard macOS save dialog. Default filename: `AssetFlow-Backup-YYYY-MM-DD.zip`.
   - **Restore from Backup** — Imports a previously exported backup archive. Confirmation required: "Restoring from backup will replace ALL existing data. This cannot be undone. Continue?" Restore validates the complete archive before replacing existing data and supports backup format versions 1 through 4. Files may be at the ZIP root or inside exactly one enclosing folder. If validation or persistence fails, the existing database and settings remain unchanged. On success, reloads all views.

1. **App Lock** — Protects portfolio data behind device authentication.

   - **Enable App Lock** toggle — when enabled, the app displays a lock screen (opaque overlay) that requires authentication before any content is visible.
   - **Authentication method:** Uses `LAPolicy.deviceOwnerAuthentication`, which provides Touch ID → Apple Watch → system password as a fallback chain. No custom biometric UI is shown; the system presents its standard authentication dialog.
   - **Lock on App Switch timeout** — configurable delay before the app re-locks after switching to another app. Options: Immediately, After 1 Minute, After 5 Minutes, After 15 Minutes, Never.
   - **Lock on Screen Lock/Sleep timeout** — configurable delay before the app re-locks after the screen locks or the Mac goes to sleep. Same options as above.
   - **Auto-disable:** When both timeouts are set to "Never", app lock is effectively disabled (the app never re-locks after the initial unlock on launch).
   - The lock screen shows the app icon and an "Unlock" button. Authentication is also triggered automatically when the app returns to the foreground, without requiring the user to press the button.
   - Tooltips (`.help()`) and hover interactions are suppressed on the lock screen to prevent financial data from leaking through the overlay.

______________________________________________________________________

### 3.11 Keyboard Shortcuts

| Shortcut | Action                                          |
| -------- | ----------------------------------------------- |
| Delete   | Remove selected item (with confirmation dialog) |
| Cmd+N    | New Snapshot                                    |
| Cmd+I    | Open Import screen                              |

______________________________________________________________________

### 3.12 Window and Appearance

- **Minimum window size:** 900 × 600 points
- **Sidebar:** Collapsible via toolbar button or drag. Default width: 220 points.
- **Appearance:** Supports system appearance (light and dark mode). All custom colors and chart colors must adapt to both modes.

**Number formatting:**

- Monetary values: ordinary asset displays use the existing currency formatter with locale grouping and Foundation currency fraction defaults (for example, $1,234.50). Entry, storage and calculation retain full Decimal precision. Rebalancing help follows asset display precision and keeps tiny nonzero amounts visible as bounds; see Shared Currency Headings in Rebalancing Help.
- Percentages: 2 decimal places (e.g., 45.23%)
- Chart axes: Abbreviated for large values (K for thousands, M for millions, B for billions)

Allocation percentage totals display the actual sum of individually rounded values (no forced normalization to 100%). Minor rounding variance (e.g., 99.99% or 100.01%) is expected and acceptable.

______________________________________________________________________

## 4. CSV Import System

### 4.1 Import Flow

1. User clicks "Import" (sidebar item or toolbar button — both open the same flow)
1. The import screen presents a unified view with:
   - **Import type selector** — Segmented control at the top: **Assets** | **Cash Flows**. Defaults to Assets. Selecting a type configures the rest of the screen for that CSV format.
   - **File selector** — Drag-and-drop zone or "Browse" button (filtered to `.csv` files)
   - Once a file is selected, the system validates columns based on the selected import type (see 4.2)
   - **For asset import:** Snapshot date picker (required, defaults to today, future dates disabled), Platform picker (optional, lists existing platforms with "None" and "New Platform..." options), Category picker (optional, lists existing categories with "None" and "New Category..." options)
   - **For cash flow import:** Snapshot date picker (required, defaults to today, future dates disabled)
   - **Preview table** showing parsed data with inline validation indicators
     - Each row in the preview table includes a **remove button** to exclude individual entries before importing
     - For asset import: if an asset already exists with a different category than the import-level category, a **warning indicator** is shown on that row (e.g., "This asset is currently assigned to [Category X]. Importing will reassign it to [Category Y].")
   - **Validation summary** at the top of the preview (errors in red, warnings in yellow)
1. **Copy-forward option (asset import only):** After selecting a file and snapshot date, if prior snapshots exist, the import screen offers a **"Copy assets from other platforms"** toggle. When enabled, the system identifies all platforms in prior snapshots that are NOT already represented in the import's resolved preview rows, and copies their most recent SnapshotAssetValues into the new snapshot as direct records. The resolved preview rows already reflect any import-level platform override, so the exclusion logic is based solely on the platforms that will actually appear in the new snapshot. This allows users to explicitly carry forward assets from platforms not included in the current import. The copied assets appear in the preview table (marked as copy-forward entries) and can be individually removed before importing.
1. User can adjust date, platform, category, and copy-forward option at any time before confirming
1. User clicks "Import" button to confirm
   - If duplicates are detected (see 4.6), an error dialog is shown and the import is rejected
   - If validation errors exist, the Import button is disabled
1. On success: snapshot is created (or updated if one exists for that date); user is navigated to the snapshot detail view
1. If the user navigates away from the import screen with a file loaded but not yet imported, a confirmation dialog is shown: "Discard import? The selected file has not been imported yet."

**Atomic replacement imports:** In Bulk Entry, asset and cash flow CSV imports replace the previous CSV-sourced values or rows for their target. Any parser or row-validation error rejects the entire replacement before existing CSV data is changed; valid rows from the same file are not applied separately. Warnings alone do not block a replacement.

______________________________________________________________________

### 4.2 CSV Schemas

The app supports two CSV formats, selected by the user via the import type selector (see 4.1).

#### 4.2.1 Asset CSV

**Required columns (exact header names):**

| Column         | Description                                                    |
| -------------- | -------------------------------------------------------------- |
| `Asset Name`   | Name of the asset (e.g., "AAPL", "Bitcoin", "Savings Account") |
| `Market Value` | Current market value as a number                               |

**Optional columns:**

| Column     | Description                                                                          |
| ---------- | ------------------------------------------------------------------------------------ |
| `Platform` | Platform/brokerage name (overridden by import-level platform if set)                 |
| `Currency` | ISO 4217 currency code (e.g., "USD", "TWD"); must be a currency supported by the app |

**Column mapping:** When the CSV headers do not match the expected column names (case-insensitive), a mapping sheet appears after file selection. The sheet displays a full preview of the CSV data with a dropdown above each column, allowing the user to assign each CSV column to a canonical field (`Asset Name`, `Market Value`, `Platform`, `Currency`) or skip it. Auto-detection: if all required columns are found by case-insensitive header matching, the mapping sheet is skipped and parsing proceeds immediately. The mapping is immutable once confirmed; re-selecting the file re-triggers the sheet. The same mapping sheet is shared between the Import screen and the Bulk Entry per-platform CSV import.

**Sample CSV:**

```csv
Asset Name,Market Value,Platform,Currency
AAPL,15000,Interactive Brokers,USD
VTI,28000,Interactive Brokers,USD
Bitcoin,5000,Coinbase,USD
Savings Account,20000,Chase Bank,TWD
```

#### 4.2.2 Cash Flow CSV

**Required columns (exact header names):**

| Column        | Description                                                                                    |
| ------------- | ---------------------------------------------------------------------------------------------- |
| `Description` | Description of the cash flow (e.g., "Salary deposit", "Rent withdrawal")                       |
| `Amount`      | Cash flow amount as a number. Positive = money added to portfolio; Negative = money withdrawn. |

**Optional columns:**

| Column     | Description                                                                          |
| ---------- | ------------------------------------------------------------------------------------ |
| `Currency` | ISO 4217 currency code (e.g., "USD", "TWD"); must be a currency supported by the app |

**Sample CSV:**

```csv
Description,Amount,Currency
Salary deposit,50000,TWD
Emergency fund transfer,-10000,TWD
Dividend reinvestment,1500,USD
```

______________________________________________________________________

### 4.3 Parsing Rules

- **Encoding:** UTF-8 (with BOM tolerance)
- **Delimiter:** Comma only
- **Number parsing:**
  - Strip leading/trailing whitespace
  - Strip currency symbols ($, etc.)
  - Strip thousand separators (commas in numbers)
  - Parse as `Decimal`
  - Negative values are allowed (for liabilities or short positions)
- **Empty rows:** Silently skipped
- **Header row:** Required as first row

______________________________________________________________________

### 4.4 Validation

The import preview screen must show validation status:

**Errors (block import) — Asset CSV:**

- Missing `Asset Name` or `Market Value` column
- `Market Value` cannot be parsed as a number for any row
- Empty `Asset Name` for any row
- File is empty or contains only headers
- Duplicate entries detected within the CSV (see 4.6)
- Duplicate entries detected between CSV and existing snapshot data (see 4.6)
- Unsupported currency code for any row (must match a currency supported by the app)

**Errors (block import) — Cash Flow CSV:**

- Missing `Description` or `Amount` column
- `Amount` cannot be parsed as a number for any row
- Empty `Description` for any row
- File is empty or contains only headers
- Duplicate entries detected within the CSV (see 4.6)
- Duplicate entries detected between CSV and existing snapshot data (see 4.6)

**Warnings (allow import with acknowledgment) — Asset CSV:**

- `Market Value` is zero for an asset
- `Market Value` is negative for an asset
- Unrecognized columns (ignored but noted)
- Asset already exists with a different category than the import-level selection (shows current vs. new category)
- Asset already exists with a different currency than the CSV-provided currency (shows current vs. new currency)

**Warnings (allow import with acknowledgment) — Cash Flow CSV:**

- `Amount` is zero
- Unrecognized columns (ignored but noted)

Each error/warning must reference the specific row number and column.

______________________________________________________________________

### 4.5 Platform Handling

Platform for each asset is determined by the import-level platform selection and the **apply mode**:

1. If no import-level platform is selected, use per-row CSV values (or empty if no `Platform` column)
1. If an import-level platform is selected:
   1. **Override All** (default): Every row receives the selected platform, overriding CSV values
   1. **Fill Empty Only**: Only rows whose CSV platform is empty receive the selected platform; rows with existing CSV platforms keep their original values

The apply mode toggle (segmented picker: "All Rows" / "Empty Only") appears only when a platform is selected AND the CSV contains a mix of empty and non-empty platform values. Otherwise, the distinction is meaningless and the toggle is hidden.

______________________________________________________________________

### 4.6 Duplicate Detection

Duplicate detection applies to both asset CSV and cash flow CSV imports. Duplicates cause the **entire import to be rejected** — no partial imports occur.

**Asset CSV duplicates:**

An asset duplicate is detected when two records share the same (Asset Name, Platform) identity (using the normalized comparison from Section 6.1):

1. **Within the CSV file:** If two rows resolve to the same (Asset Name, Platform) after applying platform handling rules (Section 4.5), the import is rejected. Error message lists the duplicate entries with row numbers.
1. **Between CSV and existing snapshot:** If an asset in the CSV matches an asset already recorded in the target snapshot (same date), the import is rejected. Error message lists the conflicting assets.

**Cash flow CSV duplicates:**

A cash flow duplicate is detected when two records share the same Description (case-insensitive comparison):

1. **Within the CSV file:** If two rows have the same Description, the import is rejected.
1. **Between CSV and existing snapshot:** If a cash flow operation in the CSV matches an existing CashFlowOperation in the target snapshot by Description, the import is rejected.

When duplicates are detected, an error dialog is shown listing all duplicates. The user must resolve duplicates in the CSV file (or remove existing records from the snapshot) before re-importing.

______________________________________________________________________

### 4.7 Category Assignment During Import

The import screen includes an optional **category picker** listing existing categories with a "New Category..." option:

- If the user selects a category, **all assets** in the import are assigned to that category
- If the user does not select a category, imported assets are uncategorized
- Selecting "New Category..." reveals a text field. If the entered name matches an existing category (case-insensitive), the existing category is selected. Otherwise, a new category is created automatically with no target allocation.

If an imported asset already exists and has a different category, the import-level category **overrides** the existing assignment. A warning is shown in the preview for each such asset. The user may remove individual entries from the preview to preserve existing category assignments.

Assets can always be re-assigned to categories individually from the Assets screen.

**Future enhancement:** Per-asset category assignment via an optional `Category` column in the CSV.

______________________________________________________________________

## 5. Category Management

### 5.1 Category Properties

- **Name** (required, unique, case-insensitive)
- **Target allocation percentage** (optional, 0-100%)

### 5.2 Operations

- **Create:** User provides name, optional percentage target, and optional minimum balance/currency. Categories can also be created implicitly: selecting "New Category..." in any category picker and entering a name that doesn't match an existing category (case-insensitive) automatically creates the category with no target allocation.
- **Edit:** Draft the name, percentage, and minimum together in Category Settings. Save Changes validates and saves all fields atomically; Revert restores saved values. Return submits only from the name, percentage, or minimum amount text field; Command-S saves within the detail view. Save/Revert are disabled without edits. Leaving the category or section with edits offers Save, Discard, or Cancel. Contextual help uses accessible information popovers; the footer assesses the saved minimum at the latest snapshot.
- **Delete:** Only allowed if no assets are assigned. If assets exist, user must reassign them first.

### 5.3 Target Allocation and Minimum Balance Rules

A category may have an optional percentage target, an optional minimum balance, both, or neither. Minimums are finite nonnegative Decimal amounts with an explicit currency; amount and currency are either both present or both absent. Explicit zero is valid. Currency defaults to the single currency shared by the category's assets, or the display currency if mixed or empty. Changing display currency preserves the saved denomination. Changing the goal currency does not convert the entered amount.

Percentage targets distribute the available allocation pool, after protecting uncategorized assets and categories without percentage targets. A minimum-only category protects `max(current balance, minimum)`. No-target categories protect their current balances. Percentage targets may be saved incrementally, but their sum must equal 100% before an actionable percentage plan is available. An explicit 0% targets its minimum, or zero; absence of a percentage protects the category instead.

All assets still contribute to total value and actual allocation percentages. Minimums take priority over percentage preferences. Infeasible requirements can be saved and produce diagnostics rather than partial buy/sell plans. Ordinary asset/cash-flow imports do not change category goals.

______________________________________________________________________

## 6. Asset Identity and Matching

### 6.1 Identity Rule

An asset is uniquely identified by the tuple: **(Asset Name, Platform)**

- During import, if an asset with the same name and platform already exists, the existing asset record is reused.
- If no match exists, a new asset record is created.
- Matching uses **normalized identity comparison**:
  1. Trim leading and trailing whitespace
  1. Collapse multiple consecutive spaces to a single space
  1. Case-insensitive comparison (Unicode-aware, using `caseInsensitiveCompare` or equivalent)

### 6.2 Implications

- Renaming an asset or changing its platform **via CSV import** creates a new asset (the old one remains with historical values)
- Renaming an asset or changing its platform **via the Asset detail view** updates the existing asset retroactively across all snapshots. The new (name, platform) combination must not conflict with an existing asset.
- Users cannot merge assets in v1 (this could be a future feature)

### 6.3 Asset Deletion

An asset record can be deleted when it has **no SnapshotAssetValue records** in any snapshot. This means:

- The asset was removed from all snapshots, or
- The asset was created but never used (e.g., created by mistake during manual snapshot editing)

When an asset still has snapshot associations, the delete action is disabled with explanatory text: "This asset cannot be deleted because it has values in [N] snapshot(s). Remove the asset from all snapshots first."

Deleting an asset is permanent and cannot be undone. A confirmation dialog is required.

______________________________________________________________________

## 7. Data Model

### 7.1 Category

| Field                      | Type     | Notes                                 |
| -------------------------- | -------- | ------------------------------------- |
| id                         | UUID     | Primary key                           |
| name                       | String   | Required, unique (case-insensitive)   |
| targetAllocationPercentage | Decimal? | Optional pool preference, 0-100       |
| minimumBalanceAmount       | Decimal? | Optional finite nonnegative amount    |
| minimumBalanceCurrency     | String?  | Explicit currency paired with minimum |
| displayOrder               | Int      | Sort order for display                |

### 7.2 Asset

| Field      | Type   | Notes                                |
| ---------- | ------ | ------------------------------------ |
| id         | UUID   | Primary key                          |
| name       | String | Required                             |
| platform   | String | Optional (may be empty)              |
| currency   | String | ISO 4217 currency code; may be empty |
| categoryID | UUID?  | FK to Category                       |

**Uniqueness constraint:** (name, platform) must be unique (case-insensitive).

Assets persist across snapshots and are created during import if they don't already exist.

### 7.3 Snapshot

| Field     | Type | Notes                                                                                                                                                                     |
| --------- | ---- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| id        | UUID | Primary key                                                                                                                                                               |
| date      | Date | Calendar date (no time component, normalized to local midnight). Must be today or earlier — future dates are not allowed. User-selected during import or manual creation. |
| createdAt | Date | Auto-set                                                                                                                                                                  |

**Uniqueness constraint:** Only one Snapshot may exist per date. Multiple imports on the same date add SnapshotAssetValues to the existing Snapshot.

**Note:** `totalPortfolioValue` is **not stored** — it is always derived by summing SnapshotAssetValues.

### 7.4 SnapshotAssetValue

| Field       | Type    | Notes          |
| ----------- | ------- | -------------- |
| snapshotID  | UUID    | FK to Snapshot |
| assetID     | UUID    | FK to Asset    |
| marketValue | Decimal | Required       |

**Uniqueness constraint:** (snapshotID, assetID) must be unique.

### 7.5 CashFlowOperation

| Field               | Type    | Notes                                            |
| ------------------- | ------- | ------------------------------------------------ |
| id                  | UUID    | Primary key                                      |
| snapshotID          | UUID    | FK to Snapshot                                   |
| cashFlowDescription | String  | Required                                         |
| amount              | Decimal | Required. Positive = inflow, negative = outflow. |
| currency            | String  | ISO 4217 currency code; may be empty             |

**Uniqueness constraint:** (snapshotID, cashFlowDescription) must be unique (case-insensitive comparison on cashFlowDescription).

The net cash flow for a snapshot is always derived: `netCashFlow = sum(CashFlowOperation.amount)` for all operations associated with that snapshot.

### 7.6 ExchangeRate

| Field        | Type   | Notes                                                                           |
| ------------ | ------ | ------------------------------------------------------------------------------- |
| baseCurrency | String | Base currency code for the stored rates (e.g., "usd")                           |
| ratesJSON    | Data   | JSON-encoded `[String: Decimal]` dictionary of currency codes to exchange rates |
| fetchDate    | Date   | When the rates were fetched from the remote source                              |
| isFallback   | Bool   | `true` if these rates are stale/cached due to a network failure                 |

**Relationship:** 1:1 with Snapshot (each snapshot has at most one ExchangeRate record).

**Computed property:** `rates: [String: Decimal]` — decoded rates dictionary from `ratesJSON`, cached in memory after first access.

Exchange rates are fetched from cdn.jsdelivr.net and stored per snapshot so that historical value conversions remain stable and reproducible. The `convert(value:from:to:)` method applies the formula `value / rates[from] * rates[to]`, where the base currency's rate is implicitly 1.0.

______________________________________________________________________

## 8. Snapshot Lifecycle

### 8.1 Manual Creation

Users can create a snapshot manually from the Snapshots screen:

1. Click "New Snapshot"
1. Select a snapshot date (required, must be today or earlier). **The selected date must not have an existing snapshot.** If the user selects a date that already has a snapshot, show a validation error: "A snapshot already exists for [date]. Go to the Snapshots screen to view and edit it." The creation flow cannot proceed until a valid date is selected.
1. Choose a creation mode:
   - **Empty snapshot** — creates a snapshot with no asset entries; user is navigated to SnapshotDetailView to add assets manually
   - **Bulk Entry** (default) — navigates to BulkEntryView with all assets from the latest snapshot (the most recent snapshot with a date before the selected date) grouped by platform. Users enter new market values directly. When no prior snapshots exist, the view displays an empty state with an "Add Platform" button, allowing users to create platforms and add assets inline. Per-platform "Add Asset" buttons and CSV import are available in each platform group header. New assets support inline category assignment via a name-based picker (categories are created in the database only on save).

### 8.2 CSV Import Creation

Snapshots are created through the CSV import flow (Section 4).

**A snapshot is uniquely identified by its date.** Multiple imports on the same date are allowed (e.g., importing Platform A and Platform B separately). Each import adds SnapshotAssetValues to the existing snapshot for that date, or creates a new snapshot if one doesn't exist.

### 8.3 Editing

Within the snapshot detail view, users can:

- **Add asset** — Add an asset entry to this snapshot.
  - *Select existing asset:* Search existing assets with autocomplete. Platform and category are displayed as read-only (pre-filled from the asset record). User enters only market value.
  - *Create new asset:* Enter asset name, platform picker (lists existing platforms with "New Platform..." option), category picker (lists existing categories with "New Category..." option), and market value. Selecting "New Category..." or "New Platform..." reveals a text field for entering the name. If the entered name matches an existing item (case-insensitive), the existing item is selected instead of creating a duplicate.
  - In both cases, if the (Asset Name, Platform) tuple matches an existing SnapshotAssetValue in this snapshot, the addition is **rejected** with an error: "This asset already exists in this snapshot. Edit its value instead." The identity matching uses the same normalized comparison from Section 6.1.
- **Edit value** — Click on a market value to edit it. Changes are saved immediately. There is no undo for inline value edits. Users should verify values before moving to the next field.
- **Remove asset** — Remove a directly-recorded asset entry from this snapshot. **Confirmation required:** "Remove [Asset Name] from this snapshot? The asset record itself will not be deleted." The Asset record itself is NOT deleted — it persists for other snapshots.

**Cash flow operations:**

- **Add cash flow** — Enter description and amount. If the description matches an existing operation in this snapshot (case-insensitive), show error and prevent creation.
- **Edit cash flow** — Edit description or amount. Same uniqueness check on description.
- **Remove cash flow** — Remove a cash flow operation from this snapshot. Confirmation required.

Derived metrics (totals, allocations) recompute automatically after any change.

### 8.4 Deletion

Users can delete an entire snapshot:

- Confirmation dialog required: "Delete snapshot from [date]? This will remove all [N] asset values and [M] cash flow operations. This action cannot be undone."
- Deletion removes the Snapshot and all its SnapshotAssetValues and CashFlowOperations
- Asset records are NOT deleted (they persist for other snapshots)

______________________________________________________________________

## 9. Net Cash Flow

Net cash flow represents external money added to or withdrawn from the portfolio between two snapshots. It is needed for accurate TWR calculation.

### 9.1 Cash Flow Operations

Each snapshot contains zero or more **CashFlowOperation** records (see Section 7.5). Each operation has:

- **Description** (required, unique within the snapshot) — identifies the cash flow (e.g., "Salary deposit", "401k contribution", "Emergency withdrawal")
- **Amount** (required) — Positive = money added to portfolio; Negative = money withdrawn

The **net cash flow** for a snapshot is computed as the sum of all its CashFlowOperation amounts. This net value is used in return calculations (Section 10.4).

### 9.2 Input Methods

Cash flow operations can be entered via:

1. **CSV import** — Using the cash flow CSV schema (Section 4.2.2). Imported operations are added to the target snapshot. Duplicate detection applies (Section 4.6).
1. **Manual entry** — On the snapshot detail screen (Section 8.3). Users can add, edit, and remove individual operations. Duplicate description check applies.

### 9.3 Scope and Limitations

- Portfolio-level only in v1
- Category-level cash flow tracking is deferred to a future version
- Cash flow operations apply to the entire portfolio, regardless of which platforms were included in the snapshot.

### 9.4 Timing Assumption

All cash flow operations within a snapshot are assumed to occur at the snapshot date for Modified Dietz time-weighting purposes.

### 9.5 Default Behavior

If a snapshot has no cash flow operations, net cash flow = 0, which assumes all value changes are due to investment returns.

______________________________________________________________________

## 10. Calculation Logic

All calculations are derived from stored structured data. No spreadsheet-style hidden formulas. All portfolio-level metrics (growth, return, TWR, CAGR) operate on stored portfolio values.

### 10.1 Portfolio Total Value

For a given snapshot, the total value is the sum of all directly-stored SnapshotAssetValues:

```
total_value(snapshot) = sum(SnapshotAssetValues in snapshot)
```

### 10.2 Category Allocation

For each snapshot:

```
category_value = sum(market_value of assets in category)
category_percentage = category_value / total_portfolio_value * 100
```

Uncategorized assets appear as a separate "Uncategorized" group.

### 10.3 Growth Rate

Growth rate measures the **simple percentage change** in portfolio value between two dates. It includes the effect of cash flows (deposits/withdrawals) and does NOT isolate investment performance.

```
growth_rate = (Ending_Value - Beginning_Value) / Beginning_Value
```

Useful for tracking how total wealth changes over time.

**Period lookback:** For 1M, 3M, and 1Y growth, compute the target lookback date (latest snapshot date minus 1/3/12 months), then find the closest snapshot to that target in either direction (before or after), with no distance limit. When two snapshots are equidistant from the target, prefer the earlier one. The actual date range is displayed below the rate value so users can see the true period covered.

### 10.4 Modified Dietz Return

The app uses the **Modified Dietz method** to calculate investment returns, isolating actual performance by adjusting for the timing and magnitude of external cash flows.

**Formula:**

```
R = (EMV - BMV - CF) / (BMV + Σ(wi * CFi))
```

Where:

- `EMV` = ending portfolio value
- `BMV` = beginning portfolio value
- `CF` = total net cash flow during the period (Σ CFi)
- `CFi` = net cash flow at each intermediate snapshot
- `wi` = time-weighting factor for each cash flow
- `wi = (CD - Di) / CD`
- `CD` = total calendar days in the period
- `Di` = number of days from period start to cash flow i

**How cash flows are time-weighted:**

Cash flows recorded on snapshot dates have known timing. For a return calculation over any period:

1. Identify all snapshots strictly after the begin date through the end date (inclusive)
1. Each snapshot's net cash flow (sum of its CashFlowOperation amounts) is a cash flow event at that snapshot's date
1. Weight each by how much of the period remained when it occurred

**Example:** 90-day period, cash flow of +100,000 at day 30:

```
w = (90 - 30) / 90 = 0.667
Weighted cash flow = 0.667 * 100,000 = 66,700 (added to denominator)
```

A cash flow at the very start (day 0) gets weight 1.0 (fully invested for the period). A cash flow at the very end (day 90) gets weight 0.0 (not invested at all during the period).

**Period lookback:** For 1M, 3M, and 1Y returns, use the same bidirectional lookback as growth rate: find the closest snapshot to the target date in either direction, with no distance limit. When equidistant, prefer the earlier snapshot. Use the resolved snapshot as the beginning and gather all cash flows from intermediate snapshots for time-weighting.

**Supported levels:**

- Portfolio-level return only

**Note:** Category-level return is not tracked in v1 because category-level cash flow data is unavailable, and approximating cash flow proportionally by category weight can produce misleading results (e.g., a large deposit invested entirely in equities would be incorrectly attributed across all categories).

### 10.5 Cumulative Time-Weighted Return (TWR)

Cumulative TWR chains Modified Dietz returns between consecutive snapshots to measure long-term **portfolio-level** performance:

For each consecutive pair of snapshots (S0→S1, S1→S2, ..., Sn-1→Sn), compute the Modified Dietz return `ri`.

```
TWR = (1 + r1) * (1 + r2) * ... * (1 + rn) - 1
```

This is the standard time-weighted return methodology that eliminates the distortion of external cash flows across the full history.

### 10.6 CAGR

```
CAGR = (Ending_Value / Beginning_Value) ^ (1 / Years) - 1
```

Where `Years` = (end date - start date) / 365.25. The implementation keeps the year interval, portfolio ratio, and fractional power in Decimal arithmetic to preserve financial precision.

Available for portfolio-level only in v1.

### 10.7 Edge Cases

| Scenario                            | Behavior                                                                                          |
| ----------------------------------- | ------------------------------------------------------------------------------------------------- |
| Only one snapshot                   | Growth/return/TWR/CAGR = N/A. Display "Insufficient data"                                         |
| Beginning value = 0                 | Return = N/A for that period. Display "Cannot calculate"                                          |
| Beginning value < 0                 | Return = N/A for that period. Display "Cannot calculate"                                          |
| Denominator (BMV + weighted CF) ≤ 0 | Return = N/A. Display "Cannot calculate"                                                          |
| Category has no assets              | Allocation = 0%, return = N/A                                                                     |
| All assets uncategorized            | Uncategorized group shows 100% allocation                                                         |
| Fewer than 2 snapshots              | All period metrics = N/A. At least 2 snapshots are required.                                      |
| Period < 1 year for CAGR            | Still calculate using fractional years (may produce large annualized numbers — display with note) |
| Negative period return > -100%      | Display normally                                                                                  |
| Net cash flow but no value change   | Return is negative (cash added but no growth). Display normally                                   |

______________________________________________________________________

## 11. Rebalancing Engine

Rebalancing is a read-only, closed-portfolio preview using the latest snapshot's directly recorded values. Missing entries do not carry forward. Convert both asset values and minimums using that snapshot's valid exchange-rate record. Missing goal rates disable the plan independently of otherwise valid asset valuations.

### Inputs and protected funds

Use category UUIDs for identity. Let `V` be total value, `c_i` current category balance, `m_i` minimum or zero, and `u` uncategorized value.

1. If `sum(m_i) > V`, report globally infeasible minimums and funding shortfall `sum(m_i) - V`.
1. For every category without a percentage, protect `q_i = max(c_i, m_i)`.
1. Define `Q = u + sum(q_i)` and the percentage pool `A = V - Q`.
1. Let `F` be minimums of percentage-target categories. If `Q + F > V`, report insufficient available funds and shortfall `Q + F - V`. Protected holdings can cause this even when total minimums fit within V.
1. Require percentage targets to sum to 100% when any exist. Save is permitted before this condition is met; actions are unavailable.

Per-category shortfalls `max(0, m_i - c_i)` are distinct from external funding shortfalls. With only minimum goals, current surpluses remain protected; unmet minimums require new funds or changed configuration, without an automatically chosen donor.

### Constrained allocation

Reserve explicit zero-percentage targets at their minimums. For positive percentages solve:

```text
target_i = max(minimum_i, lambda * percentage_i)
sum(target_i for percentage categories) = available_pool
adjustment_i = target_i - current_i
```

Repeatedly distribute remaining funds according to remaining percentage weights, fix any below-minimum category at its minimum, and redistribute. Each iteration removes a bound category, so iteration count is bounded by category count. Minimum-only targets are q_i; no-target and uncategorized balances are unchanged. A feasible plan conserves portfolio value and never violates a minimum.

For V = TWD 1,000,000, reserve 10% with a TWD 300,000 minimum, equities 60%, and bonds 30%, effective targets are approximately TWD 300,000 / 466,666.67 / 233,333.33. Flexible weights retain a 60:30 ratio after the reserve minimum binds.

Use checked Decimal arithmetic at full precision. Finite balance-arithmetic results with normal Decimal precision loss are accepted; overflow, underflow, division by zero and invalid numbers are rejected. Percentage aggregation remains exact. Minimum and protected funding sums that lose precision are usable only when their strict budget comparison is unambiguous: a conservative error bound of `max(requiredTotal, budget, 1) * componentCount * 1e-37` accounts for Decimal's 38 significant digits. If the rounded sum lies within that bound of the budget, the plan remains unavailable rather than erasing a requirement. Original components participate in the combined funding check, so rounded subtotals cannot conceal a deficit. This error bound never permits underfunding. Asset values are summed in stable asset UUID order, and allocation inputs in category UUID order. Independently summed portfolio and category totals may differ by at most `max(V, 1) * 1e-28`; larger inconsistencies are invalid. This tolerance applies only to arithmetic consistency and target reconciliation, never to genuine funding deficits or minimum compliance. A division/rounding remainder within that bound may be reconciled to a flexible positive-weight category that remains above its minimum; otherwise the calculation is unavailable. No financial value is converted through Double or rounded to currency display precision. Display and chart conversion do not feed back into the calculation.

### Result and presentation

Structured results distinguish feasible, no goals, invalid data, invalid percentage sum, globally infeasible minimums, and insufficient available funds. The assessment layer separately represents no snapshot and missing asset/goal conversion. Zero-valued snapshots can still have funding shortfalls; shares of a zero total/pool are unavailable.

Each category occupies one line with Category, Current balance, Current %, Effective target balance, Effective target %, Change, Action, and Minimum columns. Configured percentages remain in category settings and relevant calculation inputs. Category information popovers explain the selected target with lettered inputs and formula result rows. A minimum status icon identifies a shortfall or unavailable assessment. The compact header shows total and snapshot date. Calculation details reconciles portfolio total minus protected amount to the available allocation, and when applicable subtracts percentage targets fixed at minimums to show the remaining allocation. Minimum-only requirements are already included in protection and are never subtracted twice. Financial diagnostics remain visible banners. Minimum-only, protected and uncategorized rows remain visible. Sort by absolute adjustment and then stable UUID.

Mandatory minimum top-ups remain actionable below one display-currency unit. Transfer planning first funds every actual minimum shortfall, then uses remaining donor capacity for actionable percentage adjustments. Small donor reductions participate when large reductions cannot cover the total minimum shortfall; optional increases above minimums do not count toward this mandatory demand. Repeated transfers between the same pair are combined for display. Other subunit differences show “Small adjustment” with their precise value. Transfer summaries are limited by actual donor and recipient capacity. Omitted/unmatched adjustments are disclosed as a residual; invalid or infeasible plans have no actions or transfer summaries.

### Rebalancing contextual help

Calculation details combines lettered allocation-basis rows with formula result rows and compact allocation-rule bullets. Category information uses the category name as its only title, a contextual explanation, and a Target calculation table. Flexible percentage targets use remaining allocation × category percentage ÷ combined remaining percentages; minimum-bound targets equal the converted minimum; minimum-only targets use max(current balance, converted minimum); explicit 0% targets use their minimum or zero. Final effective percentages divide the target by the entire portfolio. No category lists or duplicated current/change/configuration grids are shown. Zero totals show an unavailable share without division; unavailable plans show a reason without calculation rows. Minimum warning symbols retain original/converted requirement, current balance, shortfall and date. Popovers remain lock-aware.

Historical comparisons use current goal settings and each snapshot's rates, with unavailable gaps; they do not record goal history. Value charts include the converted minimum overlay. Raw pool percentages are not plotted as whole-portfolio allocation references.

______________________________________________________________________

## 12. Visualizations

**Time range controls:** All line charts (12.2, 12.3, 12.4) include a zoom selector with the following scales:

- 1W (1 week), 1M (1 month), 3M (3 months), 6M (6 months), 1Y (1 year), 3Y (3 years), 5Y (5 years), All
- Default: All
- The chart displays only snapshots within the selected time range
- If no snapshots exist within the selected range, display "No data for selected period"
- The selected time range resets to "All" when navigating away from the chart's screen. Time range selections are not persisted across sessions.

### 12.1 Pie Chart — Category Allocation

- Shows allocation at a selected snapshot (default: latest)
- Each slice = one category
- Slices sorted by value (largest first, clockwise from 12 o'clock)
- Uncategorized shown as a distinct slice
- Labels show: category name, percentage, value
- Interactive: hover shows a tooltip with category name, percentage, and value. Clicking a slice navigates to that category's detail view in the Categories section.

### 12.2 Line Chart — Portfolio Value Over Time

- X-axis: snapshot dates
- Y-axis: portfolio total value
- Data points at each snapshot
- Tooltip on hover showing date and value
- Clicking a data point navigates to the corresponding snapshot's detail view.
- Time range zoom controls (see above)

### 12.3 Line Chart — Category Value Over Time

- Same format as portfolio chart
- Multiple lines, one per category
- Legend with category names
- Toggle individual categories on/off
- Hover shows the date and category values at that date, sorted from highest to lowest (ties alphabetically). Currency values are right-aligned in a shared column with tabular digits. No click-to-navigate behavior.
- Time range zoom controls (see above)

The category detail view also includes an allocation percentage line chart (same format as 12.3 but showing percentage instead of value, for a single category). Time range zoom controls apply.

### 12.4 Cumulative TWR Chart

- X-axis: snapshot dates
- Y-axis: cumulative TWR (%)
- Shows portfolio-level return over time
- Hover shows tooltip with date and cumulative TWR percentage. No click-to-navigate behavior.
- Time range zoom controls (see above)
- **Rebasing:** When a non-"All" time range is selected, the displayed TWR is rebased so the first visible data point starts at 0%. This shows the return earned within the selected period rather than the inception-based value. The formula is `(1 + C_i) / (1 + C_k) - 1`, where `C_k` is the cumulative TWR at the first point in the filtered range.

### 12.5 Chart Empty & Edge States

| Chart             | Condition                                    | Display                                                  |
| ----------------- | -------------------------------------------- | -------------------------------------------------------- |
| Pie chart (12.1)  | All assets uncategorized                     | Single slice labeled "Uncategorized" with 100%           |
| Pie chart (12.1)  | No assets in latest snapshot                 | "No asset data available" placeholder                    |
| Line chart (12.2) | Only one snapshot                            | Single data point with label; no connecting line         |
| Line chart (12.2) | No snapshots in selected range               | "No data for selected period" message                    |
| Line chart (12.3) | No categories defined                        | "Create categories to see allocation trends" placeholder |
| Line chart (12.3) | Category has zero value across all snapshots | Omit from chart; include in legend as "(no data)"        |
| TWR chart (12.4)  | Fewer than 2 snapshots                       | "Insufficient data (need at least 2 snapshots)"          |
| TWR chart (12.4)  | All returns N/A in selected range            | "Cannot calculate returns for selected period"           |

All charts are based strictly on stored snapshot data.

______________________________________________________________________

## 13. Error Handling

### 13.1 Import Errors

| Error                                       | Handling                                                            |
| ------------------------------------------- | ------------------------------------------------------------------- |
| File cannot be opened                       | Alert: "Could not open file. Please check the file is a valid CSV." |
| Missing required columns                    | Show which columns are missing, block import                        |
| Unparseable values                          | Highlight specific rows/columns, block import                       |
| No data rows                                | Alert: "File contains no data rows."                                |
| Missing required columns for selected type  | Show which columns are expected vs. found, block import             |
| Duplicate assets in CSV                     | Error dialog listing duplicates with row numbers, import rejected   |
| Duplicate assets with existing snapshot     | Error dialog listing conflicts, import rejected                     |
| Duplicate cash flows in CSV                 | Error dialog listing duplicates, import rejected                    |
| Duplicate cash flows with existing snapshot | Error dialog listing conflicts, import rejected                     |

### 13.2 Calculation Errors

- Division by zero: Display "N/A" or "Cannot calculate" with explanation
- Insufficient snapshots for TWR/CAGR: Display "Insufficient data (need at least 2 snapshots)"

### 13.3 Data Integrity

- Category deletion blocked if assets assigned
- Asset deletion blocked if SnapshotAssetValues exist
- Snapshot deletion requires confirmation
- Value edits are validated (must be a valid number)
- Cash flow description uniqueness enforced per snapshot

______________________________________________________________________

## 14. Architecture Requirements

### Platform

- macOS 15.0+
- SwiftUI
- Local-first storage. Network access is limited to fetching exchange rates from `cdn.jsdelivr.net` when a snapshot is created or imported. All other data is stored locally with no cloud sync.

### Data Storage

- SwiftData
- Must support efficient historical queries (fetch all snapshots, fetch asset values across snapshots)
- SwiftData lightweight migration is relied upon for schema evolution. The initial data model should be designed to minimize future breaking changes.

### Window Management

- Minimum window size: 900 × 600 points
- Sidebar collapsible
- Supports system appearance (light and dark mode)

______________________________________________________________________

## 15. Explicit Non-Goals (v1)

Do NOT implement:

- Real-time market price fetching
- Brokerage API integration
- Per-security IRR
- Tax lot tracking
- Dividend modeling
- Cloud sync
- Data export for reporting (CSV, PDF) — note: data backup/restore IS supported (see Section 3.10)
- Category-level cash flow tracking
- Category-level return tracking (TWR, CAGR)
- Asset merging/splitting
- Platform merging
- iOS / iPadOS support
- Full undo/redo system (destructive actions use confirmation dialogs instead)
- Per-asset category assignment via CSV column (import-level category selector only in v1)
- Search and filtering on list views (Assets, Snapshots, Categories, Platforms)

______________________________________________________________________

## 16. Design Principles

The application must model:

```
Raw Snapshot Data -> Derived Metrics -> Visualization
```

NOT:

```
Spreadsheet Formulas -> UI
```

All calculations must be:

- **Deterministic** — same inputs always produce same outputs
- **Recomputable** — derived values are never the source of truth
- **Transparent** — user can see what data drives each number
- **Auditable** — data sources are visible, not hidden

______________________________________________________________________

## 17. Success Criteria

The app is considered successful if:

1. Users can import CSV files from multiple platforms
1. Snapshots contain only directly-recorded values; copy-forward import option works correctly
1. Snapshots are browsable, editable, and deletable
1. Portfolio-level TWR is mathematically correct
1. Category allocation and rebalancing calculations are correct
1. Dashboard provides clear portfolio overview at a glance
1. Categories are user-manageable with target allocations
1. No hidden spreadsheet logic exists
1. All derived values can be traced back to source data
1. Cash flow operations can be imported via CSV and managed manually
1. Platform management (rename) works correctly
1. Data backup can be exported and restored without data loss

______________________________________________________________________

## Verification

After implementation, verify by:

1. Import a sample CSV and confirm snapshot is created with correct values
1. Import a partial CSV (one platform) and use copy-forward option to include other platforms
1. Create categories, assign assets, verify allocation percentages
1. Set target allocations and verify rebalancing suggestions
1. Confirm TWR and CAGR calculations with manual computation
1. Test all empty states (new app, no categories, no snapshots)
1. Test error cases (bad CSV, duplicate import, delete snapshot)
1. Import a cash flow CSV and confirm operations are created on the snapshot
1. Test duplicate rejection for both asset and cash flow CSV imports
1. Rename platforms, verify all asset associations update
1. Export a backup, delete all data, restore from backup, verify data integrity
1. Delete an asset with no snapshot associations; verify assets with associations cannot be deleted
1. Test chart zoom controls across all time ranges

## Shared Currency Headings in Rebalancing Help

Each popup table independently checks the intended currencies of its monetary rows. When they all match, the table heading shows that ISO code once and monetary values show localized numbers without a currency prefix. A previously untitled minimum assessment table uses Assessment as its heading. Mixed-currency tables retain prefixes on every available monetary value. Percentage rows are excluded from the check; unavailable monetary rows still contribute their intended currency and remain an em dash. Amounts in explanatory sentences retain their codes. The currency-heading rule does not convert values or parse formatted strings. Monetary formatting separately uses the existing asset currency formatter's fraction precision, with the same trailing decimal places, locale separators and grouping; Foundation supplies the currency defaults without an app-maintained currency list. Apply this to all popup amount rows, shortfall explanations and funding diagnostics. Nonzero values below one display unit use a bound (for example, `<0.01`), with localized Increase/Decrease text for tiny signed changes; actual zero remains a formatted zero and unavailable values remain an em dash. No Full precision section is shown. Stored Decimal values, allocation arithmetic and minimum-status comparisons remain unrounded.

### Lettered rebalancing calculations

Input rows use (A), (B), (C), etc.; result rows show their plain-language label, referenced formula, and value in the same grid. Formula text follows the label inline in caption styling. All row labels use secondary color and regular weight. All popup values use the standard system callout font with one bold weight and tabular digits (`.monospacedDigit()`), matching the dashboard category value trend tooltip approach. Result rows remain distinguished by dividers; no monospaced font design or per-result weight change is applied. Percentage symbols occupy a separate suffix column with a small gap, so percentage numbers share the right-aligned numeric column with monetary values. Tables without suffixes retain two columns. Unavailable shares have no suffix. Accessibility includes the suffix with the numeric value and hides the separate decorative symbol cell. Each data row is a single baseline-aligned GridRow; dividers are full-width table overlays positioned from result-row bounds, never extra conditional grid rows. Rebalancing popovers use their natural title/table width with explanatory paragraphs wrapping to that width. Available screen width bounds the content, allowing wrapping instead of clipping when necessary. Non-rebalancing help retains its existing sizing. Shared monetary currency headings and asset display precision remain in place. Results use ≈ when a displayed result or referenced input is rounded; arithmetic and funding decisions retain original Decimal precision. Category lists are omitted from aggregate and category explanations.

The rebalancing Keep/Protected operation includes a secondary-gray `minus.circle.fill` icon before its existing localized text.
