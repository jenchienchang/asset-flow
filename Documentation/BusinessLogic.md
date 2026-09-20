# Business Logic and Calculation Design

## Preface

**Purpose of this Document**

This document describes the **business rules, calculations, workflows, and execution logic** that power AssetFlow's functionality. It focuses on the "what" and "how" of the application's behavior -- what the system does with user data and how financial calculations, validations, and business processes are executed.

**What This Document Covers**

- **Core Concept**: Snapshot-based portfolio model
- **Calculation Logic**: Portfolio value, category allocation, growth rate, Modified Dietz return, TWR, CAGR
- **Rebalancing Engine**: Target vs. current allocation with suggested adjustments
- **CSV Import**: Parsing, validation, duplicate detection, and import execution
- **Data Management**: Category, asset, snapshot, and cash flow lifecycle
- **Edge Cases**: Boundary conditions, error scenarios, and N/A handling

**What This Document Does NOT Cover**

- User interface design (see [UserInterfaceDesign.md](UserInterfaceDesign.md))
- Data model structure (see [DataModel.md](DataModel.md))
- System architecture (see [Architecture.md](Architecture.md))
- Testing strategies (see [TestingStrategy.md](TestingStrategy.md))

**Related Documentation**

- [DataModel.md](DataModel.md) - Data structures and relationships
- [Architecture.md](Architecture.md) - MVVM layer responsibilities
- [APIDesign.md](APIDesign.md) - CSV parsing and backup/restore service interfaces

______________________________________________________________________

## Core Concept: Snapshot-Based Portfolio Model

### Overview

AssetFlow tracks portfolio state through **snapshots** -- discrete records of portfolio holdings at specific dates. This differs from transaction-based systems that derive state from a history of buy/sell operations.

**Key Rules**:

1. Snapshots are append-only -- a new import never silently overwrites an existing snapshot
1. A snapshot contains only directly-recorded SnapshotAssetValues. There is no automatic carry-forward. Users can reference prior snapshot values in Bulk Entry mode (manual creation) or use the copy-forward option during CSV import.
1. The CSV file does NOT contain a date -- the user explicitly selects a date when importing
1. Users may delete or edit snapshots after creation

______________________________________________________________________

## Calculation Logic

All calculations are derived from stored structured data. No spreadsheet-style hidden formulas. All portfolio-level metrics operate on stored portfolio values.

### Portfolio Total Value

For a given snapshot, the total value is the sum of all directly-stored SnapshotAssetValues, **converted to the display currency** using the snapshot's exchange rate:

```
total_value(snapshot) = sum(convert(sav.marketValue, from: asset.currency, to: displayCurrency) for each sav)
```

If any required exchange rate is unavailable, the converted total is unavailable rather than a mixed-currency sum. Native totals remain available grouped by currency so the user can inspect the underlying values. This value is always derived, never stored on the Snapshot model.

### Currency Conversion

Each asset and cash flow has a native currency. When computing cross-asset totals, values are converted to the global display currency using the snapshot's `ExchangeRate`:

```
converted_value = value / rates[from_currency] * rates[to_currency]
```

Where `rates[baseCurrency]` is implicitly 1.0. Cross-rate conversion is used when neither currency is the base currency.

**Conversion status**: A conversion is complete only when every non-display currency used by the snapshot has a positive, finite rate in an exchange-rate record whose base currency and Gregorian `fetchDate` match the display currency and snapshot date. Missing, invalid, or wrong-date rates produce an explicit unavailable status; they never silently pass through native values as if they were display-currency values.

When conversion is incomplete, the UI shows native asset and cash-flow totals grouped by currency. Statistics that require a single display-currency series (category allocations, platform totals, growth and return rates, TWR/CAGR, and related graphs) remain in place with an unavailable overlay identifying the missing currencies and affected snapshots.

**Auto-Fetch Missing Rates**: On app launch and after backup restore, `ExchangeRateService.fetchMissingRates()` scans all snapshots and fetches exchange rates for any that need currency conversion but lack a complete usable `ExchangeRate`. This covers snapshots created offline, failed fetches, malformed, incomplete, or wrong-date cached data, and restored backups (especially v2 backups which lack `exchange_rates.csv`). Requests for the same date/base-currency pair are coalesced with caller-aware cancellation, API response dates and currency coverage are validated before caching, and failures are returned to callers instead of being silently treated as successful conversion data.

### Category Allocation

For each snapshot with complete conversion, asset values are converted to the display currency before computing allocation:

```
category_value = sum(convert(market_value, asset.currency, displayCurrency) for assets in category)
category_percentage = category_value / total_portfolio_value * 100
```

- Uncategorized assets appear as a separate "Uncategorized" group
- A category with no assets has allocation = 0%
- If all assets are uncategorized, the "Uncategorized" group shows 100% allocation
- If any required exchange rate is missing, allocation is unavailable rather than calculated from mixed currencies

### Growth Rate

Growth rate measures the **simple percentage change** in portfolio value between two dates. It includes the effect of cash flows (deposits/withdrawals) and does NOT isolate investment performance.

```
growth_rate = (Ending_Value - Beginning_Value) / Beginning_Value
```

**Period Lookback**: For 1M, 3M, and 1Y growth:

1. Calculate the target lookback date (latest snapshot date minus 1/3/12 months)
1. Find the closest snapshot to the target date in either direction (before or after), with no distance limit
1. When two snapshots are equidistant from the target, prefer the earlier one
1. If fewer than 2 snapshots exist, return N/A

### Modified Dietz Return

The Modified Dietz method calculates investment returns, isolating actual performance by adjusting for the timing and magnitude of external cash flows.

**Formula**:

```
R = (EMV - BMV - CF) / (BMV + sum(wi * CFi))
```

Where:

- `EMV` = ending portfolio value
- `BMV` = beginning portfolio value
- `CF` = total net cash flow during the period (sum of CFi)
- `CFi` = net cash flow at each intermediate snapshot
- `wi` = time-weighting factor for each cash flow
- `wi = (CD - Di) / CD`
- `CD` = total calendar days in the period (code: `totalDays`)
- `Di` = number of days from period start to cash flow i (code: `daysSinceStart`)

**Cash Flow Time-Weighting**:

Cash flows recorded on snapshot dates have known timing. For a return calculation over any period:

1. Identify all snapshots strictly after the begin date through the end date (inclusive)
1. Each snapshot's net cash flow (sum of its CashFlowOperation amounts) is a cash flow event at that snapshot's date
1. Weight each by how much of the period remained when it occurred

**Example**: 90-day period, cash flow of +100,000 at day 30:

```
w = (90 - 30) / 90 = 0.667
Weighted cash flow = 0.667 * 100,000 = 66,700 (added to denominator)
```

A cash flow at the very start (day 0) gets weight 1.0 (fully invested). A cash flow at the very end (day 90) gets weight 0.0 (not invested during the period).

**Period Lookback**: Same bidirectional closest-snapshot lookback as growth rate (no distance limit, prefer earlier on tie).

**Supported Levels**: Portfolio-level return only in v1. Category-level return is not tracked because category-level cash flow data is unavailable.

### Cumulative Time-Weighted Return (TWR)

Cumulative TWR chains Modified Dietz returns between consecutive snapshots to measure long-term portfolio performance:

For each consecutive pair of snapshots (S0->S1, S1->S2, ..., Sn-1->Sn), compute the Modified Dietz return `ri`:

```
TWR = (1 + r1) * (1 + r2) * ... * (1 + rn) - 1
```

This is the standard time-weighted return methodology that eliminates the distortion of external cash flows across the full history.

### CAGR

```
CAGR = (Ending_Value / Beginning_Value) ^ (1 / Years) - 1
```

Where `Years` = (end date - start date) / 365.25

Available for portfolio-level only in v1.

### Edge Cases

| Scenario                              | Behavior                                                                                     |
| ------------------------------------- | -------------------------------------------------------------------------------------------- |
| Only one snapshot                     | Growth/return/TWR/CAGR = N/A. Display "Insufficient data"                                    |
| Beginning value = 0                   | Return = N/A. Display "Cannot calculate"                                                     |
| Beginning value < 0                   | Return = N/A. Display "Cannot calculate"                                                     |
| Ending value \<= 0 (CAGR)             | CAGR = N/A. Display "Cannot calculate"                                                       |
| Denominator (BMV + weighted CF) \<= 0 | Return = N/A. Display "Cannot calculate"                                                     |
| Category has no assets                | Allocation = 0%, return = N/A                                                                |
| All assets uncategorized              | Uncategorized group shows 100% allocation                                                    |
| Fewer than 2 snapshots                | All period metrics = N/A                                                                     |
| Period < 1 year for CAGR              | Calculate using fractional years (may produce large annualized numbers -- display with note) |
| Negative period return > -100%        | Display normally                                                                             |
| Net cash flow but no value change     | Return is negative (cash added but no growth). Display normally                              |

______________________________________________________________________

## Rebalancing Engine

The rebalancing calculator is **read-only** -- it computes suggested adjustments but does NOT modify stored data.

### Inputs

- Current category allocation (from latest snapshot)
- Target allocation (from category settings)

### Calculation

For each category with a target allocation:

```
target_value = total_portfolio_value * target_percentage / 100
adjustment_amount = target_value - current_category_value
```

### Output

A table showing:

| Category | Current Value | Current % | Target % | Difference ($) | Action       |
| -------- | ------------- | --------- | -------- | -------------- | ------------ |
| Equities | $75,000       | 60%       | 50%      | -$12,500       | Sell $12,500 |
| Bonds    | $25,000       | 20%       | 30%      | +$12,500       | Buy $12,500  |
| Cash     | $25,000       | 20%       | 20%      | $0             | No action    |

### Rules

- Only categories with target allocations are included in the main table
- Categories without targets are shown separately as "No target set"
- Uncategorized assets shown as a separate row with current value and current %, with "--" in Target % and "N/A" in Difference and Action
- Sort order: by absolute adjustment magnitude (largest deviation first)
- Minimum threshold: adjustments under $1 are displayed as "No action needed"

______________________________________________________________________

## CSV Import System

### Import Flow

1. User selects import type (Assets or Cash Flows) via segmented control
1. User selects a CSV file (drag-and-drop or browse)
1. System auto-detects column mapping by case-insensitive header matching:
   - If all required columns match: parsing proceeds immediately (no sheet)
   - If required columns are missing: a column mapping sheet appears with a full CSV table preview, per-column dropdowns, and sample data rows; the user maps each CSV column to a canonical field or skips it; matched optional columns are pre-selected
1. User configures import parameters:
   - **Asset import**: Snapshot date (required, defaults to today), Platform (optional), Category (optional)
   - **Cash flow import**: Snapshot date (required, defaults to today)
1. Preview table shows parsed data with inline validation indicators
1. User may remove individual rows from the preview
1. User clicks "Import" to confirm
1. On success: snapshot created or updated; user navigated to snapshot detail

### CSV Schemas

**Asset CSV** (required columns: `Asset Name`, `Market Value`; optional: `Platform`):

```csv
Asset Name,Market Value,Platform
AAPL,15000,Interactive Brokers
VTI,28000,Interactive Brokers
Bitcoin,5000,Coinbase
Savings Account,20000,Chase Bank
```

**Cash Flow CSV** (required columns: `Description`, `Amount`):

```csv
Description,Amount
Salary deposit,50000
Emergency fund transfer,-10000
```

### Parsing Rules

- **Encoding**: UTF-8 (with BOM tolerance)
- **Delimiter**: Comma only
- **Number parsing**: Strip whitespace, currency symbols ($), thousand separators (commas in numbers). Parse as `Decimal`. Negative values allowed.
- **Empty rows**: Silently skipped
- **Header row**: Required as first row
- **Malformed files**: Invalid encoding, quoting, field counts, or CSV structure produce a user-visible import error; no rows are imported

### Validation

**Errors (block import) -- Asset CSV**:

- Missing `Asset Name` or `Market Value` column
- `Market Value` cannot be parsed as a number for any row
- Empty `Asset Name` for any row
- File is empty or contains only headers
- Duplicate entries detected (within CSV or against existing snapshot)
- Unsupported currency code for any row (must match a currency supported by the app)

**Errors (block import) -- Cash Flow CSV**:

- Missing `Description` or `Amount` column
- `Amount` cannot be parsed as a number for any row
- Empty `Description` for any row
- File is empty or contains only headers
- Duplicate entries detected (within CSV or against existing snapshot)

**Warnings (allow import) -- Asset CSV**:

- `Market Value` is zero for an asset
- `Market Value` is negative for an asset
- Unrecognized columns (ignored but noted)
- Asset already exists with a different category than import-level selection
- Asset already exists with a different currency than the CSV-provided currency

**Warnings (allow import) -- Cash Flow CSV**:

- `Amount` is zero
- Unrecognized columns (ignored but noted)

Each error/warning references the specific row number and column.

### Platform Handling

Platform for each asset is determined by the import-level platform selection and apply mode:

1. If no import-level platform is selected, use per-row CSV values (or empty if no `Platform` column)
1. If an import-level platform is selected:
   1. **Override All** (default): Every row receives the selected platform, overriding CSV values
   1. **Fill Empty Only**: Only rows whose CSV platform is empty receive the selected platform; rows with existing CSV platforms keep their original values

The apply mode toggle appears only when a platform is selected AND the CSV has a mix of empty and non-empty platform values.

### Currency Handling

Currency for each asset is determined by the CSV data and existing asset state:

1. If the CSV provides a `Currency` column value for a row, that currency is assigned to the asset on import (takes precedence over any existing currency)
1. If the CSV has no currency for a row (no `Currency` column or empty value), the existing asset's currency is preserved unchanged
1. Unsupported currency codes (not recognized by `CurrencyService`) produce a validation error that blocks import
1. When an unsupported currency error exists for a row, it takes precedence over the currency change warning (both are not shown simultaneously)

Cash flow CSV currency handling follows the same pattern: CSV currency is assigned if provided, otherwise no currency is set on the new cash flow operation.

### Duplicate Detection

Duplicates are shown as per-row error popovers on the affected preview rows. Rows with duplicate errors block import.

**Asset CSV duplicates**:

- **Within CSV**: Two rows with the same (Asset Name, Platform) after applying platform handling rules and normalized identity comparison. The second occurrence gets the error.
- **Between CSV and existing snapshot**: An asset in the CSV matches an asset already recorded in the target snapshot (same date)

**Cash flow CSV duplicates**:

- **Within CSV**: Two rows with the same Description (case-insensitive). The second occurrence gets the error.
- **Between CSV and existing snapshot**: A Description matches an existing CashFlowOperation in the target snapshot

Excluding (removing) a row with a duplicate error triggers revalidation; if the remaining rows have no duplicates, the errors are cleared.

### Category Assignment During Import

Category for each asset is determined by the import-level category selection and apply mode:

1. If no category is selected, imported assets are uncategorized (existing assets retain their current category)
1. If a category is selected:
   1. **Override All** (default): Every asset receives the selected category, overriding existing categories
   1. **Fill Empty Only**: Only assets that have no existing category receive the selected category; assets with existing categories keep their original category

The apply mode toggle ("All Rows" checkbox) appears only when a category is selected AND the import contains a mix of categorized and uncategorized existing assets (`hasMixedCategories`).

- In **Override All** mode, a category reassignment warning is shown on rows where the existing asset has a different category
- In **Fill Empty Only** mode, no category reassignment warning is shown (existing categories won't change)
- The preview table's Category column shows the effective post-import category reflecting the apply mode
- "New Category..." option: if entered name matches existing category (case-insensitive), the existing one is used; otherwise a new category is created with no target allocation

______________________________________________________________________

## Category Management

### Operations

- **Create**: User provides name and optional target allocation. Also created implicitly via "New Category..." picker option. New categories receive the next sequential `displayOrder` value.
- **Edit**: Rename or change target allocation
- **Delete**: Only allowed if no assets are assigned. If assets exist, user must reassign them first. After deletion, `displayOrder` values are compacted to remove gaps.
- **Reorder**: Categories can be reordered via drag-and-drop. The `displayOrder` property persists the user-defined order. All category lists sort by `displayOrder` first, then alphabetically by name as a tiebreaker.

### Target Allocation Rules

- Target allocations across all categories should sum to 100% (app warns if not, but does not block)
- Categories without a target allocation are excluded from rebalancing calculations
- An "Uncategorized" virtual group appears in allocation views for assets without a category

______________________________________________________________________

## Asset Identity and Matching

### Identity Rule

An asset is uniquely identified by the tuple: **(Asset Name, Platform)**

- During import, if an asset with the same name and platform already exists, the existing asset record is reused
- If no match exists, a new asset record is created
- Matching uses normalized identity comparison (trim whitespace, collapse spaces, case-insensitive)

### Renaming Behavior

- Renaming an asset or changing its platform **via CSV import** creates a new asset (old one remains with historical values)
- Renaming an asset or changing its platform **via the Asset detail view** updates the existing asset retroactively across all snapshots. The new (name, platform) must not conflict with an existing asset.

### Asset Deletion

An asset can be deleted when it has **no SnapshotAssetValue records** in any snapshot:

- The asset was removed from all snapshots, or
- The asset was created but never used

When an asset has snapshot associations, the delete action is disabled with explanatory text. Deletion is permanent and requires confirmation.

### Stale Assets and the Hide Filter

An asset is considered **stale** when it has **no value in the latest snapshot** (its `latestValue` lookup is `nil`). Assets typically become stale after the user closes a position: the asset still has SnapshotAssetValue records in older snapshots, but the most recent snapshot no longer references it.

The Asset list provides a **Hide Stale Assets** filter (toolbar Filter menu) to remove these rows from the list. The filter is **enabled by default** so the list focuses on the user's current portfolio. The user's choice is persisted in `UserDefaults` under `Constants.UserDefaultsKeys.hideStaleAssets` via `SettingsService.hideStaleAssets`, so it survives view switches and app relaunches. The filter is purely presentational — it does not delete data and does not affect any other view (Dashboard, Snapshots, Categories, Platforms, Rebalancing).

______________________________________________________________________

## Snapshot Lifecycle

### Manual Creation

1. User clicks "New Snapshot" on the Snapshots screen
1. Selects a date (must be today or earlier, future dates disabled)
1. If the selected date already has a snapshot, show validation error: "A snapshot already exists for [date]. Go to the Snapshots screen to view and edit it."
1. Chooses starting point:
   - **Empty snapshot**: Creates snapshot with no asset entries
   - **Bulk Entry** (default): Opens BulkEntryView with all assets from the latest prior snapshot grouped by platform. When no prior snapshots exist, the view shows an empty state with an "Add Platform" action. Users can add platforms and assets inline without needing prior data.
1. User is taken to snapshot detail for editing

#### Bulk Entry Validation Rules

- New asset rows (`.manualNew`) must have a non-empty name before saving
- Duplicate asset names within the same platform (case-insensitive) are validated at save time (same pattern as cash flow duplicate descriptions)
- Same asset name in different platforms is allowed
- Categories for new assets are stored as name strings and resolved on save via `resolveCategory(name:)` (case-insensitive find-or-create)
- New categories typed by the user are immediately available in the picker for other new asset rows but are not created in the database until save

### CSV Import Creation

Snapshots created through the CSV import flow. If a snapshot already exists for the selected date, SnapshotAssetValues are added to the existing snapshot.

### Editing

Within the snapshot detail view:

- **Add asset**: Select existing asset or create new one. Rejected if (Asset Name, Platform) already exists in this snapshot.
- **Edit value**: Click on market value to edit. Changes saved immediately. There is no undo for inline value edits. Users should verify values before moving to the next field.
- **Remove asset**: Remove a directly-recorded asset from this snapshot (asset record itself is NOT deleted)
- **Add/Edit/Remove cash flow**: Manage CashFlowOperations with description uniqueness check

### Deletion

- Confirmation required showing date, asset count, and cash flow count
- Removes the Snapshot and all its SnapshotAssetValues and CashFlowOperations
- Asset records are NOT deleted

______________________________________________________________________

## Net Cash Flow

### Purpose

Net cash flow represents external money added to or withdrawn from the portfolio between snapshots. It is needed for accurate Modified Dietz return calculation.

### Cash Flow Operations

Each snapshot contains zero or more CashFlowOperation records:

- **Description** (required, unique within snapshot) -- identifies the cash flow
- **Amount** (required) -- Positive = inflow, negative = outflow

Net cash flow = sum of all CashFlowOperation amounts for a snapshot.

### Input Methods

1. **CSV import**: Using the cash flow CSV schema. Duplicate detection applies.
1. **Manual entry**: On the snapshot detail screen. Description uniqueness enforced.

### Scope and Limitations

- Portfolio-level only in v1
- Category-level cash flow tracking deferred to future version
- Cash flow operations apply to entire portfolio regardless of which platforms were included
- All operations within a snapshot assumed to occur at the snapshot date for time-weighting

### Default Behavior

If a snapshot has no cash flow operations, net cash flow = 0, which assumes all value changes are due to investment returns.

______________________________________________________________________

## Bulk Entry

### Overview

Bulk entry provides a full-screen workflow for entering asset values across all platforms in a single session. It presents all known assets grouped by platform, allowing users to enter new market values directly or import them from per-platform CSV files.

### Save Semantics

- **Included rows with values**: A SnapshotAssetValue is created with the entered market value
- **Included rows without values (pending)**: A SnapshotAssetValue is created with market value 0
- **Excluded rows**: No SnapshotAssetValue is created; the asset is omitted from the snapshot

### Zero-Value Design Invariant

A `SnapshotAssetValue` with `marketValue == 0` is treated as a placeholder — an asset that has not yet been recorded for the snapshot. If a snapshot should not track an asset, the `SnapshotAssetValue` should be removed rather than kept with value 0. This invariant enables:

- **CSV import overwrite**: When importing into an existing snapshot, zero-value SAVs are overwritten in-place rather than flagged as duplicates. This allows users to create a snapshot via bulk entry (which saves pending rows as 0) and later fill in values via CSV import.
- **Bulk entry validation**: Explicitly entering 0 is blocked (`hasZeroValueError`); users must exclude the asset instead.

### Zero-Value Warning Rules

Assets with a market value of 0 trigger warnings in multiple contexts:

- **Bulk entry save**: A confirmation alert lists all assets that will be saved with value 0, giving the user a chance to review before proceeding
- **Snapshot detail view**: A yellow warning icon appears next to assets with value 0, with a tooltip explaining that the value may need updating or the asset should be removed
- **Asset list view**: Assets whose latest snapshot value is 0 display a warning indicator

### Cash Flow Operations in Bulk Entry

Cash flow rows are portfolio-level and do not carry forward from previous snapshots. The cash flow section starts empty each time a new bulk entry session begins.

**Input methods**:

1. **Manual entry**: The "Add Cash Flow" button appends an inline row with editable description, amount, and currency fields. Manually-added rows (`.manualNew`) can be deleted via a trash button.
1. **CSV import**: The "Import CSV" button uses the `.cashFlow` schema with auto-detect column mapping (required: Description, Amount; optional: Currency). A valid replacement clears all previous CSV-sourced rows globally (cash flows are portfolio-level, not per-platform) before applying the new import. Any parser or row-validation error rejects the replacement without changing the previous CSV-sourced rows. CSV rows are matched to existing rows by normalized description (`normalizedForIdentity`).

**Validation rules**:

1. Non-empty description is required for all included rows
1. Case-insensitive duplicate description detection via `normalizedForIdentity` blocks save
1. Invalid (unparseable) amount text blocks save
1. All cash flow validation errors prevent saving (reflected in `canSave`)

**Bulk Entry CSV failure handling**:

- Asset and cash-flow CSV parse results are always surfaced in an import feedback alert, including row-level parser errors and file-read failures.
- Any parser or row-validation error rejects the replacement before existing CSV values or rows are changed; valid rows from a mixed-validity file are not imported separately.

**Save semantics**:

- **Included rows**: Create `CashFlowOperation` objects on the snapshot. All included rows must have a non-empty, parseable amount (enforced by `canSave`). Explicit zero amounts are allowed. Currency is preserved from the row.
- **Excluded rows**: Omitted entirely; no `CashFlowOperation` is created.

**`canSave` integration**: The bulk entry `canSave` check includes cash flow validation alongside asset validation: no cash flow validation errors, no empty amounts, no empty descriptions on included rows. Duplicate cash flow descriptions are validated at save time (not in `canSave`) to avoid expensive `normalizedForIdentity` computation on every keystroke.

______________________________________________________________________

## Data Validation Rules

### Category Validation

- `name` must not be empty
- `name` must be unique (case-insensitive)
- `targetAllocationPercentage`, if provided, must be 0-100

### Asset Validation

- `name` must not be empty
- `(name, platform)` must be unique (case-insensitive, normalized)

### Snapshot Validation

- `date` must be today or earlier
- `date` must be unique (one snapshot per date)

### SnapshotAssetValue Validation

- `(snapshot, asset)` must be unique (one value per asset per snapshot)
- `marketValue` must be a valid `Decimal`

### CashFlowOperation Validation

- `description` must not be empty
- `(snapshot, description)` must be unique (case-insensitive)
- `amount` must be a valid `Decimal`

______________________________________________________________________

## Error Handling

### Import Errors

| Error                                       | Handling                                                             |
| ------------------------------------------- | -------------------------------------------------------------------- |
| File cannot be opened                       | Alert: "Could not open file. Please check the file is a valid CSV."  |
| Malformed CSV syntax or encoding            | Error feedback with the parser diagnostic; no replacement is applied |
| Missing required columns for selected type  | Show which columns are expected vs. found, block import              |
| Unparseable values                          | Highlight specific rows/columns, block import                        |
| No data rows                                | Alert: "File contains no data rows."                                 |
| Duplicate assets in CSV                     | Error dialog listing duplicates with row numbers, import rejected    |
| Duplicate assets with existing snapshot     | Error dialog listing conflicts, import rejected                      |
| Duplicate cash flows in CSV                 | Error dialog listing duplicates, import rejected                     |
| Duplicate cash flows with existing snapshot | Error dialog listing conflicts, import rejected                      |

### Calculation Errors

- Division by zero: Display "N/A" or "Cannot calculate" with explanation
- Insufficient snapshots for TWR/CAGR: Display "Insufficient data (need at least 2 snapshots)"

### Data Integrity

- Category deletion blocked if assets assigned
- Asset deletion blocked if SnapshotAssetValues exist
- Snapshot deletion requires confirmation
- Value edits validated (must be a valid number)
- Cash flow description uniqueness enforced per snapshot

______________________________________________________________________

## Design Principles

All calculations must be:

- **Deterministic** -- same inputs always produce same outputs
- **Recomputable** -- derived values are never the source of truth
- **Transparent** -- user can see what data drives each number
- **Auditable** -- data sources are visible, not hidden

```
Raw Snapshot Data -> Derived Metrics -> Visualization
```

NOT:

```
Spreadsheet Formulas -> UI
```

______________________________________________________________________

## App Lock (Authentication)

### Overview

Optional app-level authentication to protect against casual physical access. Uses macOS `LocalAuthentication` framework with `LAPolicy.deviceOwnerAuthentication`.

### Rules

1. **Off by default** — user enables in Settings → Security
1. **Enable gate** — toggling app lock on triggers a system authentication prompt first; if auth fails, the toggle reverts to off (prevents accidental lockout)
1. **Lock on launch** — if app lock is enabled, the app starts locked and requires authentication
1. **Per-condition re-lock (three-step protocol)** — all lock state is centralized in `AuthenticationService`:
   - **Step 1: `recordBackground(trigger:)`** — called by notification handlers. Two independent triggers:
     - **App switch** (`NSApplication.didResignActiveNotification`) — fires when Cmd+Tab, clicking another window, or minimizing
     - **Screen lock / sleep** — detected via two notifications: `com.apple.screenIsLocked` distributed notification (fires immediately on Ctrl+Cmd+Q and screen lock) and `NSWorkspace.screensDidSleepNotification` (fires on display sleep from lid close or idle timeout). Both are needed because screen lock does not trigger display sleep, and display sleep on external monitors may not trigger screen lock
   - `screenSleep` always overrides a pending `appSwitch` (higher priority). Recording is suppressed while `isAuthenticating` is true to prevent re-lock loops. If the relevant timeout is `.immediately`, `isLocked` is set eagerly (lock overlay appears immediately, auth dialog deferred)
   - **Step 2: `evaluateOnBecomeActive()`** — called on `didBecomeActiveNotification`. Evaluates the pending background event against its timeout and locks if elapsed time exceeds the threshold. Always clears background state afterward
   - **Step 3: `authenticateIfActive()`** — auth dialog is ONLY shown when `isAppActive == true`. This prevents the system authentication dialog from appearing while the user is in another app. `LockScreenView` calls this via `.task(id:)` (for lock-on-launch) and `.onReceive(didBecomeActiveNotification)` (for deferred auth when returning to a locked app)
   - Note: `ScenePhase` is not used because it is unreliable on macOS (only fires for Cmd+H hide)
1. **Window protection** — both the main `WindowGroup` and `Settings` scene use the same `ZStack` + `LockScreenView` overlay pattern. No windows are closed when locking — each window independently shows/hides its own lock overlay based on `authService.isLocked`. This eliminates bugs caused by `NSApplication.shared.mainWindow` returning the wrong window
1. **Menu command gating** — keyboard shortcuts (Cmd+N, Cmd+I) are disabled when `authService.isLocked` is true
1. **Re-lock timeouts** — Immediately (0s), After 1 Minute (60s), After 5 Minutes (300s), After 15 Minutes (900s), Never (skip locking for that trigger). Default: Immediately for both triggers
1. **Auto-disable / auto-reset** — when both `appSwitchTimeout` and `screenLockTimeout` are set to `.never`, `isAppLockEnabled` is automatically set to `false` (the user has effectively disabled all lock triggers). Conversely, when re-enabling app lock while both timeouts are still `.never`, both are reset to `.immediately` (the default) so the lock is immediately functional
1. **Authentication method** — not user-configurable. The system dialog handles fallback: Touch ID → Apple Watch → system password
1. **Disabling** — toggling app lock off immediately unlocks the app and disables future locking

### State

- `isAppLockEnabled` — persisted in UserDefaults
- `appSwitchTimeout` — persisted in UserDefaults (raw value of `ReLockTimeout` enum). Timeout for app switch trigger
- `screenLockTimeout` — persisted in UserDefaults (raw value of `ReLockTimeout` enum). Timeout for screen lock / sleep trigger
- `isLocked` — runtime only, not persisted. Set to `true` on launch if app lock is enabled
- `isAppActive` — runtime only, tracks whether the app is the frontmost application. Initialized to `true` (app starts active). Maintained by `didResignActiveNotification` / `didBecomeActiveNotification` handlers in `AssetFlowApp`. Used as a gate for `authenticateIfActive()` to prevent auth dialogs from appearing while the user is in another app
- `backgroundDate` — runtime only, the timestamp when the app entered the background. Set by `recordBackground()`, cleared by `evaluateOnBecomeActive()`
- `backgroundTrigger` — runtime only, which trigger (`.appSwitch` or `.screenSleep`) caused the background event
- `isAuthenticating` — runtime only, `true` while the system authentication dialog is being presented. Used to suppress `recordBackground()` calls
- `authWasCancelled` — runtime only, set to `true` when the user cancels or fails authentication; suppresses auto-auth retries in `authenticateIfActive()` until the next background event resets it
- `lastUnlockDate` — runtime only, set after each successful authentication

______________________________________________________________________

## References

### Financial Concepts

- [Investopedia - Modified Dietz Method](https://www.investopedia.com/terms/m/modifieddietz.asp)
- [Investopedia - Time-Weighted Return](https://www.investopedia.com/terms/t/time-weightedror.asp)
- [Investopedia - CAGR](https://www.investopedia.com/terms/c/cagr.asp)
- [Investopedia - Asset Allocation](https://www.investopedia.com/terms/a/assetallocation.asp)

### Implementation

- Swift `Decimal` type for precision
- Swift Charts for visualization
- Specification: `SPEC.md` Sections 2, 4, 5, 6, 7, 8, 9, 10, 11
