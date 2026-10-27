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
1. An import may add records to the snapshot for its selected date, but it must not silently replace a recorded nonzero asset value or an existing cash flow. An existing zero-value asset entry is a placeholder that an asset CSV import may replace (Section 4.6). Users may also edit or delete snapshots explicitly (Section 8).
1. A snapshot contains only directly-recorded SnapshotAssetValues. There is no automatic carry-forward. Users can pre-populate values from prior snapshots via "Bulk Entry" (manual creation) or the copy-forward option during CSV import.
1. Bulk Entry CSV imports replace their own draft rows atomically, without changing the saved snapshot until the user saves the draft (Section 4.1).

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
1. **New Snapshot** — Opens snapshot creation
1. **Import CSV** — CSV import workflow

**Detail views:** Snapshots, Assets, Categories, and Platforms use a list beside the selected item's detail. When no item is selected, the detail area shows a prompt. Dashboard, Rebalancing, Import CSV, and an active Bulk Entry draft occupy the full content area.

The File menu also opens New Snapshot and Import CSV. [`UserInterfaceDesign.md`](UserInterfaceDesign.md) owns navigation history, draft protection, and command details.

______________________________________________________________________

### 3.2 Dashboard (Home Screen)

The dashboard provides a portfolio overview using the latest snapshot.

**Layout:**

1. **Summary cards row:**

   - Total Portfolio Value
   - Latest Snapshot Date
   - Number of Assets
   - Cumulative TWR (All Time) (since first snapshot)
   - CAGR (since first snapshot) — shown alongside Cumulative TWR (All Time). Help distinguishes wealth growth, which includes deposits and withdrawals, from the app's estimated cash-flow-adjusted return.
   - Metric help explains each measure and the snapshot and cash-flow assumptions behind it.

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

1. **Category value history chart:**

   - Shows category values across snapshots with a legend that can hide individual categories

1. **Recent snapshots list:**

   - Last 5 snapshots (newest first) with date, converted total when available or separate native-currency amounts, and asset count
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
- **Bulk Entry** (default): Opens a full-screen editable table seeded from the latest snapshot before the selected date, grouped by platform. Users enter new market values directly. Features include:
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
- **Hide Stale Assets** toolbar toggle is on by default and persists across sessions. A stale asset has no entry in the latest snapshot; an entry explicitly valued at zero is not stale. Hiding stale assets affects this list only. If all rows are hidden, explain how to show them again.
- When grouped by platform, assets without a platform appear under a "(No Platform)" group at the end of the list.
- Each row: Asset Name, Platform, Category, Latest Value

**Asset detail view:**

- Value history across snapshots (newest first in the table and chronological in the chart)
- Asset name (editable)
- Platform (editable)
- Category assignment (editable)
- Currency (editable) — Supported currency picker; sets the asset's native currency. Used for FX conversion display.
- **Converted value column and chart toggle:** When the asset's currency differs from the display currency (Settings), the value history table gains a "Converted Value" column showing each snapshot's market value converted to the display currency via the snapshot's stored ExchangeRate. A currency-code toggle button appears in the section header; clicking it switches the sparkline chart between the native-currency view (blue) and the converted-value view (green). The toggle is hidden when the asset currency matches the display currency or when no currency is set.
- Delete action: **only enabled when the asset has no SnapshotAssetValue records in any snapshot**. When disabled, shows explanatory text: "This asset cannot be deleted because it has values in snapshot(s). Remove the asset from all snapshots first." (See Section 6.3)

______________________________________________________________________

### 3.5 Categories Screen

**List view:**

- Categories follow the user's saved order, with names breaking any order ties. Users can reorder them.
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

- Platforms follow the user's saved order. Previously unseen platforms appear afterward in name order; users can reorder them.
- Each row: platform name, asset count, and latest converted value when the required rates are available

**Actions:**

- **Rename** — Change the platform name. Updates all assets with that platform. The new name must not conflict with an existing platform (case-insensitive).
- **Delete** — Implicitly handled: when all assets are moved away from a platform (via rename or asset deletion), the platform no longer appears in the list.

Assets with no platform are not shown on the Platforms screen. They appear on the Assets screen under a "(No Platform)" group when grouped by platform.

______________________________________________________________________

### 3.7 Rebalancing Screen

Show each category's current balance and whole-portfolio share, minimum status, effective target and share, and any suggested change. Include percentage-goal, minimum-only, and protected holdings; explain unavailable or infeasible plans. Suggested moves are a read-only preview and never modify portfolio records. Section 11 defines the required outcomes; [`UserInterfaceDesign.md`](UserInterfaceDesign.md) owns columns and help presentation.

______________________________________________________________________

### 3.8 Import Screen

See Section 4 (CSV Import System) for detailed flow.

______________________________________________________________________

### 3.9 Empty States

Each screen must handle the empty/first-run case:

| Screen      | Empty State                                                                                                                          |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| Dashboard   | Welcome message, prominent "Import your first CSV" button, brief explanation of the app's workflow                                   |
| Snapshots   | "No snapshots yet. Create your first snapshot or import a CSV to get started." with "New Snapshot" and "Import CSV" buttons          |
| Assets      | Explain how to create or import assets when none exist; if the Hide Stale Assets toggle hides every row, explain how to reveal them. |
| Categories  | "No categories yet. Create categories to organize your assets and set target allocations." with "Create Category" button             |
| Platforms   | "No platforms yet. Platforms are created automatically when you import CSV data or create assets."                                   |
| Rebalancing | "Add a snapshot to calculate rebalancing from your category goals."                                                                  |

______________________________________________________________________

### 3.10 Settings

Accessible via menu bar (AssetFlow > Settings) or keyboard shortcut (Cmd+,).

**Settings options:**

1. **Display currency** — Currency code for displaying all converted portfolio values (e.g., USD, TWD, EUR). Asset values recorded in a different currency are converted to this currency using the exchange rates stored in the snapshot's ExchangeRate record (see Section 7.6).

1. **Date format** — The user can select a supported date presentation style. The default is abbreviated; the current locale determines the resulting text.

1. **Default platform** — Pre-filled platform value during import, which the user can override. Defaults: display currency USD, abbreviated date format, and no default platform.

1. **Data Management**

   - **Export Backup** — Saves application data and the settings covered by the backup format in a user-selected ZIP archive. The current archive format is version 4; its manifest and CSV contracts belong in [`APIDesign.md`](APIDesign.md). App-lock settings and other device preferences are outside the backed-up settings set.
   - **Restore from Backup** — Requires confirmation before replacing application data and the backed-up settings. Formats 1 through 4 are accepted. Validate the archive before replacement; if validation or persistence fails, preserve the existing database and settings. On success, refresh views. See [`APIDesign.md`](APIDesign.md) for file layout and [`SecurityAndPrivacy.md`](SecurityAndPrivacy.md) for backup protections and limits.

1. **App Lock** — Protects portfolio data behind device authentication.

   - **Enable App Lock** toggle — when enabled, the app covers portfolio content with a lock screen until authentication succeeds.
   - **Authentication method:** Uses the macOS system dialog with `LAPolicy.deviceOwnerAuthentication`. Touch ID, a paired Apple Watch, or the system password may be available according to device and system state; the app does not choose a fixed sequence. [Apple describes the policy's macOS behavior](https://developer.apple.com/documentation/localauthentication/lapolicy/deviceownerauthentication).
   - **Lock on App Switch timeout** — configurable delay before the app re-locks after switching to another app. Options: Immediately, After 1 Minute, After 5 Minutes, After 15 Minutes, Never.
   - **Lock on Screen Lock/Sleep timeout** — configurable delay before the app re-locks after the screen locks or the Mac goes to sleep. Same options as above.
   - **Auto-disable:** Setting both timeouts to "Never" turns the Enable App Lock setting off and unlocks the app. Re-enabling app lock after that resets both timeouts to "Immediately" and requires successful authentication.
   - The lock screen offers an Unlock button. After an applicable timeout, returning to the foreground can trigger system authentication.
   - Portfolio tooltips and hover interactions must stay hidden while the app is locked; see [`SecurityAndPrivacy.md`](SecurityAndPrivacy.md) for disclosure limits.

______________________________________________________________________

### 3.11 Keyboard Shortcuts

| Shortcut | Action                                                                              |
| -------- | ----------------------------------------------------------------------------------- |
| Delete   | Remove the selected item where supported, following that screen's confirmation rule |
| Cmd+N    | New Snapshot                                                                        |
| Cmd+I    | Open Import CSV                                                                     |

______________________________________________________________________

### 3.12 Window and Appearance

- **Minimum window size:** 900 × 600 points
- **Appearance:** Supports system appearance (light and dark mode). All custom colors and chart colors must adapt to both modes.

**Number formatting:**

- Monetary values: display in the relevant currency with locale-aware grouping and currency precision. Entry, storage, and calculation retain Decimal precision. Tiny nonzero rebalancing adjustments remain distinguishable from zero; presentation rules belong in [`UserInterfaceDesign.md`](UserInterfaceDesign.md).
- Percentages: 2 decimal places (e.g., 45.23%)
- Chart axes: Abbreviated for large values (K for thousands, M for millions, B for billions)

Allocation percentage totals display the actual sum of individually rounded values (no forced normalization to 100%). Minor rounding variance (e.g., 99.99% or 100.01%) is expected and acceptable.

______________________________________________________________________

## 4. CSV Import System

### 4.1 Import Flow

1. User opens Import CSV from the sidebar or File menu
1. The import screen presents a unified view with:
   - **Import type selector** — Segmented control at the top: **Assets** | **Cash Flows**. Defaults to Assets. Selecting a type configures the rest of the screen for that CSV format.
   - **File selector** — Drag-and-drop zone or "Browse" button (filtered to `.csv` files)
   - Once a file is selected, the system validates columns based on the selected import type (see 4.2)
   - **For asset import:** Snapshot date picker (required, defaults to today, future dates disabled), Platform picker (optional, lists existing platforms with "None" and "New Platform..." options), Category picker (optional, lists existing categories with "None" and "New Category..." options)
   - **For cash flow import:** Snapshot date picker (required, defaults to today, future dates disabled)
   - **Preview table** showing parsed data with inline validation indicators
     - Each CSV row in the preview table includes a **remove button** to exclude that entry before importing
     - For asset import: show a category-reassignment warning only when the selected category and apply mode would change an existing assignment.
   - **Validation summary** distinguishes blocking errors from warnings
1. **Copy-forward option (asset import only):** When creating a new snapshot with a prior snapshot available, the user can copy the latest values from other platforms as direct records. Platforms already represented by the resolved import rows are excluded. The copy-forward controls list eligible platforms with their asset counts and source dates; users include or exclude whole platforms before importing. Copy-forward is unavailable when importing into an existing snapshot.
1. User can adjust date, platform, category, and copy-forward option at any time before confirming
1. User clicks "Import" button to confirm
   - Blocking duplicates and other validation errors are shown in the preview and disable Import (see Sections 4.4 and 4.6)
1. On success: snapshot is created (or updated if one exists for that date); user is navigated to the snapshot detail view
1. If the user navigates away from the import screen with a file loaded but not yet imported, a confirmation dialog is shown: "Discard import? The selected file has not been imported yet."

**Bulk Entry draft imports:** Within Bulk Entry, asset and cash-flow CSV imports replace the previous CSV-sourced draft rows for their target. Parser or row-validation errors reject the entire draft replacement; valid rows from the same file are not applied separately. Warnings alone do not block replacement. Canceling the system file picker leaves the draft unchanged and allows another import attempt. A new asset without a prior user-selected currency enters the draft blank when its CSV currency is unmapped, empty, or unrecognized; the user selects one before saving. A recognized CSV currency is preselected but remains editable. On reimport, a user-selected currency survives for the same new asset when the new CSV has no recognized currency. A recognized currency in the new CSV takes precedence, with feedback if it changes the user's choice. The saved snapshot changes only when the user saves the draft. This differs from importing records into a snapshot for an existing date.

When CSV headers require manual mapping, Import and Bulk Entry show every data row before users confirm the column assignments. [Import Screen](UserInterfaceDesign.md#import-screen) defines the shared preview's presentation.

______________________________________________________________________

### 4.2 CSV Schemas

The app supports two CSV formats selected in the import screen. The following fields describe what a user must provide; [`APIDesign.md`](APIDesign.md) owns the exact interchange contract.

#### 4.2.1 Asset CSV

An asset import requires **Asset Name** and **Market Value**. **Platform** and **Currency** are optional. A supplied asset currency must be supported by the app; a blank one preserves an existing asset's currency or uses the display currency for a new asset's conversion. A selected import-level platform or category may affect the resulting row according to its apply mode (Sections 4.5 and 4.7).

Required headers are detected without regard to case or surrounding whitespace. When they cannot be detected, the user can map CSV columns to the required and optional fields before import. The same mapping flow is available in Bulk Entry.

#### 4.2.2 Cash Flow CSV

Cash-flow import requires **Description** and **Amount**. Positive amounts add external money to the portfolio; negative amounts withdraw it. **Currency** is optional. An empty currency uses the display currency for conversion; a supplied code becomes the operation currency. If its exchange rate is unavailable, converted cash-flow results are unavailable. Unlike asset import, cash-flow import does not currently reject a code solely because it is absent from the app's currency list.

For example, this valid CSV records an external contribution and withdrawal:

```csv
Description,Amount,Currency
External contribution,50000,TWD
External withdrawal,-10000,TWD
```

______________________________________________________________________

### 4.3 Parsing Rules

CSV files use UTF-8 (with an optional BOM) and a comma delimiter. A header row is required; empty rows are skipped. Financial numbers are parsed as Decimal values, with supported currency symbols and quoted thousands separators accepted. Negative values are allowed. See [`APIDesign.md`](APIDesign.md) for quoting, mapping, and parsing details.

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
- Unsupported currency code in an included asset row (must match a currency supported by the app)

**Errors (block import) — Cash Flow CSV:**

- Missing `Description` or `Amount` column
- `Amount` cannot be parsed as a number for any row
- Empty `Description` for any row
- File is empty or contains only headers
- Duplicate entries detected within the CSV (see 4.6)
- Duplicate entries detected between CSV and existing snapshot data (see 4.6)

**Warnings (do not block import) — Asset CSV:**

- `Market Value` is zero for an asset
- `Market Value` is negative for an asset
- Unrecognized columns (ignored but noted)
- An existing asset would change category under All Rows (shows current vs. selected category)
- Asset already exists with a different currency than the CSV-provided currency (shows current vs. new currency)

**Warnings (do not block import) — Cash Flow CSV:**

- `Amount` is zero
- Unrecognized columns (ignored but noted)

Row-level diagnostics identify the affected row and field; file-level diagnostics identify missing headers or file errors.

______________________________________________________________________

### 4.5 Platform Handling

Platform for each asset is determined by the import-level platform selection and the **apply mode**:

1. If no import-level platform is selected, use per-row CSV values (or empty if no `Platform` column)
1. If an import-level platform is selected:
   1. **Override All** (default): Every row receives the selected platform, overriding CSV values
   1. **Fill Empty Only**: Only rows whose CSV platform is empty receive the selected platform; rows with existing CSV platforms keep their original values

The apply-mode choice is relevant when a platform is selected and CSV rows contain both empty and non-empty platform values. [`UserInterfaceDesign.md`](UserInterfaceDesign.md#import-screen) owns its control.

______________________________________________________________________

### 4.6 Duplicate Detection

Duplicate detection applies to included asset and cash-flow CSV rows. A blocking duplicate prevents the import; the user may remove a conflicting preview row before confirming.

**Asset CSV duplicates:**

An asset duplicate is detected when two records share the same (Asset Name, Platform) identity (using the normalized comparison from Section 6.1):

1. **Within the CSV file:** If two rows resolve to the same (Asset Name, Platform) after applying platform handling rules (Section 4.5), the import is rejected. Error message lists the duplicate entries with row numbers.
1. **Between CSV and existing snapshot:** A matching nonzero asset entry on the target date blocks import. A matching zero-value entry is treated as a placeholder and may be replaced in place by the imported value; this exception does not permit replacement of nonzero records.

**Cash flow CSV duplicates:**

A cash flow duplicate is detected when two records share the same Description (case-insensitive comparison):

1. **Within the CSV file:** If two rows have the same Description, the import is rejected.
1. **Between CSV and existing snapshot:** If a cash flow operation in the CSV matches an existing CashFlowOperation in the target snapshot by Description, the import is rejected.

Blocking duplicate diagnostics identify the conflicting rows or records. The user can remove rows from the preview, resolve the CSV, or edit existing records before trying again. See [`BusinessLogic.md`](BusinessLogic.md) for normalized identity rules.

______________________________________________________________________

### 4.7 Category Assignment During Import

The import screen offers an optional category picker, including a way to create a category. Without a selection, existing assets keep their assignments and new assets remain uncategorized. A newly named category is reused when its name matches an existing category under the app's case-insensitive identity rule; otherwise it is created without a goal.

With a selected category, **All Rows** (the default) assigns it to every included asset, while **Empty Only** assigns it only to assets without a category. A preview warning identifies an existing assignment that All Rows would change. The user may remove a row or change the apply mode before importing.

Assets can always be re-assigned to categories individually from the Assets screen.

**Future enhancement:** Per-asset category assignment via an optional `Category` column in the CSV.

______________________________________________________________________

## 5. Category Management

### 5.1 Category Properties

- **Name** (required, unique, case-insensitive)
- **Target allocation percentage** (optional, 0-100%)
- **Minimum balance amount and currency** (optional paired fields; a minimum-only goal is valid)

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
  1. Lowercase the normalized strings for case-insensitive comparison

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

These entities support the product behavior above. [`DataModel.md`](DataModel.md) owns field types, relationships, constraints, and migration; [`APIDesign.md`](APIDesign.md) owns their backup representation.

### 7.1 Category

A category groups assets, may set a percentage target and/or a currency-denominated minimum, and retains the user's display order (Sections 3.5 and 5).

### 7.2 Asset

An asset has a name and optional platform, currency, and category. Its normalized name and platform identify it for import matching (Section 6). The asset record persists across snapshots.

### 7.3 Snapshot

A snapshot represents a user-selected calendar date, with at most one snapshot per date. Dates in the future are unavailable. Imports on an existing date add permitted records to that snapshot. Portfolio totals are derived, not stored.

### 7.4 SnapshotAssetValue

A SnapshotAssetValue directly records one asset's Decimal market value in one snapshot. There is at most one entry for an asset in a snapshot; a zero entry remains a stored record and may serve as the import placeholder described in Section 4.6.

### 7.5 CashFlowOperation

A CashFlowOperation records an external contribution or withdrawal at its snapshot date. Descriptions are unique within a snapshot under the application's case-insensitive check. Amounts are Decimal; positive means contribution and negative means withdrawal. A blank currency uses the display currency for conversion. Net cash flow is derived from the operations, with conversion required before combining different currencies.

### 7.6 ExchangeRate

A snapshot may store rates for its date and a display-currency base. A usable record must match the snapshot's date and cover the currencies needed for the calculation. If rates are missing, incomplete, or for another date, the affected converted result is unavailable; a failed fetch does not substitute another date's rates. The stored rate date describes applicability to the snapshot, not the time a network request finished. See [`DataModel.md`](DataModel.md) and [`APIDesign.md`](APIDesign.md) for storage and fetching contracts.

______________________________________________________________________

## 8. Snapshot Lifecycle

### 8.1 Manual Creation

The New Snapshot actions in Sections 3.1 and 3.3 open the same date and creation-mode sheet:

1. Select a snapshot date (required, must be today or earlier). **The selected date must not have an existing snapshot.** If the user selects a date that already has a snapshot, show a validation error: "A snapshot already exists for [date]. Go to the Snapshots screen to view and edit it." The creation flow cannot proceed until a valid date is selected.
1. Choose a creation mode:
   - **Empty snapshot** — creates a snapshot with no asset entries; user is navigated to SnapshotDetailView to add assets manually
   - **Bulk Entry** (default) — seeds an editable draft with direct asset entries from the most recent snapshot before the selected date, grouped by platform. Users enter new values and may include, exclude, or add rows. When no prior snapshot exists, the user can add platforms and assets. New categories are created only when the draft is saved.

### 8.2 CSV Import Creation

Snapshots are created through the CSV import flow (Section 4).

**A snapshot is uniquely identified by its date.** Multiple imports on the same date are allowed (e.g., importing Platform A and Platform B separately). Each import adds permitted values to the existing snapshot or creates a new one. A matching zero-value entry can be filled; a nonzero one is protected from import replacement (Section 4.6).

### 8.3 Editing

Within the snapshot detail view, users can:

- **Add asset** — Add an asset entry to this snapshot.
  - *Select existing asset:* Search existing assets with autocomplete. Platform and category are displayed as read-only (pre-filled from the asset record). User enters only market value.
  - *Create new asset:* Enter asset name, platform picker (lists existing platforms with "New Platform..." option), category picker (lists existing categories with "New Category..." option), and market value. Selecting "New Category..." or "New Platform..." reveals a text field for entering the name. If the entered name matches an existing item (case-insensitive), the existing item is selected instead of creating a duplicate.
  - In both cases, if the (Asset Name, Platform) tuple matches an existing SnapshotAssetValue in this snapshot, the addition is **rejected** with an error: "This asset already exists in this snapshot. Edit its value instead." The identity matching uses the same normalized comparison from Section 6.1.
- **Edit value** — Use the value's Edit Value action, then submit a valid replacement in its editor. The changed value updates the snapshot; there is no separate undo flow.
- **Remove asset** — The row's Remove from Snapshot action deletes that direct value entry without a separate confirmation. The Asset record remains for other snapshots.

**Cash flow operations:**

- **Add cash flow** — Enter description and amount. If the description matches an existing operation in this snapshot (case-insensitive), show error and prevent creation.
- **Edit cash flow** — Edit description or amount. Same uniqueness check on description.
- **Remove cash flow** — The operation's Remove action deletes it without a separate confirmation.

Derived metrics (totals, allocations) recompute automatically after any change.

### 8.4 Deletion

Users can delete an entire snapshot:

- Confirmation dialog required: "Delete snapshot from [date]? This will remove all [N] asset values and [M] cash flow operations. This action cannot be undone."
- Deletion removes the Snapshot and all its SnapshotAssetValues and CashFlowOperations
- Asset records are NOT deleted (they persist for other snapshots)

______________________________________________________________________

## 9. Net Cash Flow

Net cash flow represents external money added to or withdrawn from the portfolio between two snapshots. It supports the app's cash-flow-adjusted return estimate.

### 9.1 Cash Flow Operations

Each snapshot contains zero or more **CashFlowOperation** records (see Section 7.5). Each operation has:

- **Description** (required, unique within the snapshot) — identifies the cash flow (e.g., "Salary deposit", "401k contribution", "Emergency withdrawal")
- **Amount** (required) — Positive = money added to portfolio; Negative = money withdrawn

The **net cash flow** for a snapshot is the sum of its external cash-flow operations after any required currency conversion. When a needed rate is unavailable, a single converted net amount and affected returns are unavailable; amounts in different native currencies are not added together.

### 9.2 Input Methods

Cash flow operations can be entered via:

1. **CSV import** — Using the cash flow CSV schema (Section 4.2.2). Imported operations are added to the target snapshot. Duplicate detection applies (Section 4.6).
1. **Manual entry** — On the snapshot detail screen (Section 8.3). Users can add, edit, and remove individual operations. Duplicate description check applies.

### 9.3 Scope and Limitations

- Portfolio-level only in v1
- Category-level cash flow tracking is deferred to a future version
- Cash flow operations apply to the entire portfolio, regardless of which platforms were included in the snapshot.

### 9.4 Timing Assumption

All cash-flow operations within a snapshot are assumed to occur at that snapshot's date. A return for a period includes operations on dates after its beginning snapshot through its ending snapshot, inclusive: `(begin, end]`.

### 9.5 Default Behavior

If a snapshot has no cash flow operations, net cash flow = 0, which assumes all value changes are due to investment returns.

______________________________________________________________________

## 10. Calculation Logic

All metrics derive from directly recorded snapshot values and cash flows, with currency conversion into the selected display currency where needed. They are portfolio-level in v1. [`BusinessLogic.md`](BusinessLogic.md) owns formulas, units, precision, and calculation edge cases.

### 10.1 Portfolio Total Value

For a snapshot, convert each directly recorded asset value to the display currency using rates applicable to that snapshot date, then sum the converted values. An asset with no currency uses the display currency. If any required asset rate is unavailable, the single-currency total is unavailable; show the reason and, where useful, separate native-currency totals. Never present a sum of mixed native amounts as one currency.

### 10.2 Category Allocation

At each snapshot, allocation compares each category's converted value with the converted portfolio total. Uncategorized assets form a separate group. When conversion is incomplete or the total does not permit a meaningful share, category shares are unavailable rather than inferred from partial amounts.

### 10.3 Growth Rate

Growth rate measures the **simple percentage change** in converted portfolio value between two dates. It includes the effect of deposits and withdrawals and does not isolate investment performance. Both endpoint totals must be available, and the beginning value must be positive.

```
growth_rate = (Ending_Value - Beginning_Value) / Beginning_Value
```

Useful for tracking how total wealth changes over time.

**Period lookback:** For 1M, 3M, and 1Y, find the snapshot other than the latest that is closest to the target date in either direction; there is no distance cutoff. Prefer the earlier snapshot on a tie, and display the actual begin and end dates. The resolved interval may differ from the named lookback period.

### 10.4 Modified Dietz Return

The app uses **Modified Dietz** to estimate portfolio investment return while accounting for the amount and timing of external contributions and withdrawals. It is an estimate under the available snapshot valuations and the assumption that each cash flow occurred on its snapshot date; it does not reconstruct values at every actual transaction time. [The GIPS methodology handbook describes Modified Dietz as a day-weighted estimate](https://www.gipsstandards.org/wp-content/uploads/2021/04/gips-standards-handbook-firms.pdf). This describes the calculation method, not GIPS compliance.

For a selected period, use the converted beginning and ending portfolio values and converted cash flows from `(begin, end]`. A flow on the ending date has zero time weight; a flow on the beginning date is excluded by the aggregation rule. Required rates must be available for both endpoint values and the included cash flows. Apply the same lookback and actual-date display as Section 10.3. [`BusinessLogic.md`](BusinessLogic.md) owns the full calculation rule.

Only portfolio-level return is supported: category-level external flows are not recorded, so a category return would require unsupported assumptions about where contributions and withdrawals went.

### 10.5 Cumulative Time-Weighted Return (TWR)

Cumulative TWR chains the app's Modified Dietz estimates for consecutive snapshot intervals. It is a portfolio-level approximation of cash-flow-adjusted performance, subject to those period estimates and their snapshot-date assumptions. If any required interval return is undefined, the all-time cumulative result is unavailable. See [`BusinessLogic.md`](BusinessLogic.md) for the chaining formula.

### 10.6 CAGR

CAGR annualizes the change between the first and latest converted portfolio totals. It includes the effect of external cash flows and is available only when both totals and the date interval permit the calculation. It is portfolio-level only in v1; [`BusinessLogic.md`](BusinessLogic.md) defines the formula and Decimal precision policy.

### 10.7 Edge Cases

| Scenario                                                   | Product behavior                                                                                                                                        |
| ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Fewer than two snapshots                                   | Growth, period return, cumulative TWR, and CAGR are unavailable.                                                                                        |
| Nonpositive beginning value                                | Growth and Modified Dietz return are unavailable; CAGR also requires a positive ending value.                                                           |
| Nonpositive Modified Dietz denominator or invalid interval | That period return is unavailable, as is any cumulative TWR that needs it.                                                                              |
| Required asset, cash-flow, or goal rate missing            | Show the affected converted aggregate, performance metric, or rebalancing plan as unavailable, with a reason; unaffected measures may remain available. |
| Zero or nonpositive converted portfolio total              | Do not show a meaningful category share or effective target percentage.                                                                                 |
| No category assets, with a positive total                  | Show zero category value and share; uncategorized assets remain a separate group.                                                                       |
| CAGR interval shorter than one year                        | Annualize over the actual fractional year when its inputs are valid.                                                                                    |

______________________________________________________________________

## 11. Rebalancing Engine

Rebalancing is a read-only, closed-portfolio preview using the latest snapshot's directly recorded values. Missing entries do not carry forward. Convert both asset values and minimums using that snapshot's valid exchange-rate record. Missing goal rates disable the plan independently of otherwise valid asset valuations.

### Inputs and protected funds

Uncategorized assets and categories without a percentage target remain protected. A category without a percentage keeps at least its current balance and any configured minimum. Percentage targets apply only to the remaining allocation pool, after protection. Percentage goals can be saved incrementally, but must sum to 100% before percentage-based actions are available.

If all minimums exceed the portfolio total, or protected funds plus percentage-category minimums exceed the available total, show the relevant infeasibility and funding shortfall instead of suggesting transfers. A category's own shortfall is distinct from the external funds needed by the entire plan. With only minimum goals, existing surpluses are protected; the app does not invent a donor for an unmet minimum.

### Constrained allocation

Minimums take priority. An explicit 0% target receives its minimum or zero; positive percentage targets share the remaining pool, with any minimum-bound category fixed at its minimum and the rest redistributed. Minimum-only, no-goal, and uncategorized protected balances are not treated as freely available. A feasible plan conserves the portfolio total and meets every minimum.

Use Decimal values without rounding to display precision for funding decisions. If arithmetic cannot establish whether a strict funding requirement is met, make the plan unavailable rather than treating a possible deficit as zero. [`BusinessLogic.md`](BusinessLogic.md) owns the allocation algorithm, precision policy, and worked cases.

### Result and presentation

Distinguish a feasible plan from no goals, invalid data, an invalid percentage sum, globally infeasible minimums, insufficient available funds, no snapshot, and missing asset or goal conversion. Zero-valued snapshots can still have funding shortfalls; their percentage shares are unavailable. Show current balances and whole-portfolio shares, effective targets and shares, changes, actions, and minimum status, including protected, minimum-only, and uncategorized holdings. Configured percentages remain visible in category settings.

Suggestions first fund actual minimum shortfalls, including amounts below one display-currency unit, then use remaining donor capacity for optional percentage adjustments. Suggestions must not exceed available donor or recipient capacity. Show any unresolved adjustment as a residual; invalid, infeasible, or conversion-unavailable plans have no transfer suggestions. The preview never modifies portfolio records.

### Rebalancing contextual help

Users can inspect how protected balances, available allocation, minimums, and percentage preferences produced a target. Effective shares use the entire portfolio as their denominator. Explanations distinguish tiny nonzero amounts, zero, and unavailable values; identify monetary currencies; and show the source snapshot date and currency for minimum assessments. An unavailable plan explains why without presenting a calculation or transfer as valid. [`UserInterfaceDesign.md`](UserInterfaceDesign.md) owns help presentation, currency headings, accessibility, and lock-aware interaction.

Historical comparisons use current goal settings and each snapshot's rates, with unavailable gaps; they do not record goal history. Value charts include the converted minimum overlay. Raw pool percentages are not plotted as whole-portfolio allocation references.

______________________________________________________________________

## 12. Visualizations

**Time range controls:** All line charts (12.2, 12.3, 12.4) include a zoom selector with the following scales:

- 1W (1 week), 1M (1 month), 3M (3 months), 6M (6 months), 1Y (1 year), 3Y (3 years), 5Y (5 years), All
- A newly opened chart defaults to All; its range selection is not persisted across sessions
- The chart displays only snapshots within the selected time range
- If no snapshots exist within the selected range, display "No data for selected period"

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
- Hover identifies the date and available category values at that date. No click-to-navigate behavior.
- Time range zoom controls (see above)

The category detail view also includes an allocation percentage line chart (same format as 12.3 but showing percentage instead of value, for a single category). Time range zoom controls apply.

### 12.4 Cumulative TWR Chart

- X-axis: snapshot dates
- Y-axis: cumulative TWR (%)
- Shows portfolio-level return over time
- Hover shows tooltip with date and cumulative TWR percentage. No click-to-navigate behavior.
- Time range zoom controls (see above)
- **Rebasing:** For a selected non-"All" range, the first visible point starts at 0% and later points show the chained estimated return within that range, unless the first point's inception-based TWR is -100%. In that case, rebasing is undefined and the filtered inception-based values remain unchanged. See [`BusinessLogic.md`](BusinessLogic.md) for the calculation.

### 12.5 Chart Empty & Edge States

| Chart             | Condition                                            | Display                                                                    |
| ----------------- | ---------------------------------------------------- | -------------------------------------------------------------------------- |
| Pie chart (12.1)  | All value is uncategorized and the total is positive | Single "Uncategorized" slice with 100%                                     |
| Pie chart (12.1)  | No assets in latest snapshot                         | "No asset data available" placeholder                                      |
| Line chart (12.2) | Only one snapshot                                    | Single data point with label; no connecting line                           |
| Line chart (12.2) | No snapshots in selected range                       | "No data for selected period" message                                      |
| Line chart (12.3) | No categories defined                                | "Create categories to see allocation trends" placeholder                   |
| Line chart (12.3) | Category has zero value across all snapshots         | Omit from chart; include in legend as "(no data)"                          |
| TWR chart (12.4)  | Fewer than 2 snapshots                               | "Insufficient data (need at least 2 snapshots)"                            |
| TWR chart (12.4)  | All returns N/A in selected range                    | "Cannot calculate returns for selected period"                             |
| Converted charts  | Required rates missing for a snapshot                | Identify the unavailable value or gap; do not plot a mixed-currency total. |

Chart values derive from stored snapshot data using the current display currency and applicable rates. Chart interaction and presentation details belong in [`UserInterfaceDesign.md`](UserInterfaceDesign.md).

______________________________________________________________________

## 13. Error Handling

### 13.1 Import Errors

| Condition                                                | Required outcome                                                                                         |
| -------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| File cannot be opened or has no usable data rows         | Explain the file problem and do not import.                                                              |
| Required header missing or value unparseable             | Identify the field or row, show a blocking error, and disable Import.                                    |
| Included rows resolve to one asset or cash-flow identity | Identify the conflicting rows and disable Import until resolved or excluded.                             |
| Asset row matches a nonzero entry on the selected date   | Identify the conflict and disable Import; a matching zero-value placeholder may be filled (Section 4.6). |
| Cash-flow row matches an operation on the selected date  | Identify the conflict and disable Import.                                                                |

### 13.2 Calculation Errors

- Division by zero: Display "N/A" or "Cannot calculate" with explanation
- Insufficient snapshots for TWR/CAGR: Display "Insufficient data (need at least 2 snapshots)"
- Missing required exchange rates: Identify affected converted totals, returns, or goals as unavailable. Retain separate native-currency amounts where the screen provides them.

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
- Local-first storage with no cloud sync. Network requests to `cdn.jsdelivr.net` load the supported currency list and required exchange rates. Missing rates may be fetched when snapshots are created or imported, and when the app loads, a backup is restored, the display currency changes, or goal/recorded currencies change. A failed fetch leaves affected converted results unavailable until usable rates exist.

### Data Storage

- SwiftData
- Must support efficient historical queries (fetch all snapshots, fetch asset values across snapshots)
- SwiftData stores portfolio records using the current versioned schema and migration plan. Opening or migrating a store must preserve existing user data on failure rather than deleting it. [`DataModel.md`](DataModel.md) owns schema and migration details.

### Window Management

- Minimum window size: 900 × 600 points
- Supports system appearance (light and dark mode)

### Localization, Accessibility, and Privacy

- Provide English and Traditional Chinese (`zh-Hant`) text for user-facing controls, validation, and unavailable states. Format dates, currencies, and percentages for the selected locale and settings.
- Keep essential actions, state, and explanations available through accessible labels and keyboard operation. Do not rely on color alone to convey a financial warning or missing value. [`UserInterfaceDesign.md`](UserInterfaceDesign.md) owns interaction details.
- Keep portfolio data local except for the currency-service requests described above. App lock must prevent portfolio tooltips and hover content from appearing over the lock screen; [`SecurityAndPrivacy.md`](SecurityAndPrivacy.md) owns protections and limits.

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
- Full undo/redo system
- Per-asset category assignment via CSV column (import-level category selector only in v1)
- General search and filtering across list views. The Assets list does include the Hide Stale Assets toggle described in Section 3.4.

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

The following outcomes are acceptance criteria for the product behavior described above:

1. A user can create, browse, edit, and delete dated snapshots. Values are carried forward only by an explicit action. Import into an existing date adds permitted records, replaces a matching zero-value placeholder, and blocks a matching nonzero asset or cash-flow duplicate without silently changing it.
1. A user can import assets and external cash flows from more than one platform. File-level parsing errors block import; a preview-row conflict stops blocking when that row is excluded. A failed Bulk Entry CSV replacement leaves prior draft data intact. Category edits offer Save, Discard, or Cancel on navigation; Bulk Entry and import drafts warn before discard.
1. Category creation, editing, saved ordering, percentage goals, minimums, and import apply modes produce the outcomes in Sections 3–5. The Assets list can hide stale assets without hiding explicit zero-value entries or changing stored data.
1. Converted totals and category shares use the selected display currency and date-applicable rates. Missing asset rates leave the affected single-currency total unavailable; missing cash-flow rates leave affected returns unavailable; missing goal rates leave affected rebalancing unavailable. Available native-currency amounts remain separate.
1. Growth, Modified Dietz period return, cumulative TWR, and CAGR use the relevant snapshots and cash flows as described in Section 10. Insufficient history, invalid denominators, or missing required rates produce an unavailable result rather than a misleading number.
1. Rebalancing preserves protected holdings, funds minimum requirements before optional percentage changes, and reports infeasible or unavailable plans without suggested transfers. The preview never writes asset values or executes trades.
1. Export and restore preserve the records and settings covered by the backup format. A malformed archive or failed restore leaves the existing database and settings intact; successful restore refreshes the displayed data.
1. App lock blocks portfolio content and lock-screen hover or help disclosure until authentication succeeds. Setting both timeouts to Never disables the lock; re-enabling it restores immediate timeouts. User-facing flows provide English and Traditional Chinese text and accessible state explanations.

______________________________________________________________________

## Verification

Use disposable synthetic data for these checks; do not delete a personal store to test restore.

1. Import separate platform files into one date. Confirm nonzero duplicates fail, a zero placeholder can be filled, and a partial new snapshot copies only explicitly selected prior-platform values.
1. Switch category import between All Rows and Empty Only, then confirm existing assignments change only in the selected mode. Verify a malformed Bulk Entry CSV leaves existing draft rows unchanged and navigation protects unsaved category, Bulk Entry, and import drafts.
1. Remove a needed rate for an asset, cash flow, or goal in separate fixtures. Confirm each affects only the relevant converted result or plan, native amounts remain distinct, and a later valid rate restores availability.
1. Compare a synthetic return period with the worked rules in [`BusinessLogic.md`](BusinessLogic.md), including a dated external contribution, an excluded begin-date flow, and an undefined interval that prevents cumulative TWR.
1. Try a feasible minimum-plus-percentage goal, a minimum-only shortfall, and an infeasible funding case. Confirm tiny mandatory top-ups remain visible and no transfer is offered for an infeasible plan.
1. Restore a valid synthetic backup, then try malformed and interrupted restore cases. Confirm the covered data and settings round-trip, failed attempts preserve the pre-restore state, and refreshed views show the restored records.
1. Check locked and unlocked hover/help, both-Never auto-disable and re-enable, keyboard paths, empty/error/unavailable states, and English and Traditional Chinese labels with appropriate interactive verification.
