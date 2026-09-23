# User Interface Design

## Preface

**Purpose of this Document**

This document describes the user interface design for AssetFlow -- **what** users see and **how** they interact with the macOS desktop application. It is separated into two main parts:

1. **Design Specification** -- Visual design, user experience, and interaction patterns
1. **Implementation Guide** -- Technical notes for building the designs in SwiftUI

**Design Philosophy**

- **Iterate in code**: Use Xcode previews instead of separate mockup tools
- **Leverage platform defaults**: Start with native SwiftUI components
- **macOS-native**: Follow Apple's Human Interface Guidelines for macOS
- **Prioritize functionality**: Working features before visual polish

**Related Documentation**

- [BusinessLogic.md](BusinessLogic.md) - Calculations and business rules
- [DataModel.md](DataModel.md) - Data structures
- [Architecture.md](Architecture.md) - MVVM layer responsibilities

**Implementation Status (Current)**

All core screens and features are **implemented**:

- ✅ All 12 Views: Dashboard, Snapshots (list + detail), Assets (list + detail), Categories (list + detail), Platforms, Rebalancing, Import, Settings
- ✅ All 7 chart components with interactive features (hover tooltips, click-to-navigate, time range selectors, empty states)
- ✅ Empty states use `ContentUnavailableView` for consistent macOS-native appearance
- ✅ Metric card explanations via `.helpWhenUnlocked()` tooltips (SPEC 3.2)
- ✅ Keyboard shortcuts (Delete key for deletion confirmations)
- ✅ Menu bar commands: File > New Snapshot (Cmd+N), File > Import CSV (Cmd+I), Help > User Guide, Help > Report an Issue
- ✅ Sheet standardization: all sheets use `NavigationStack` + toolbar placements
- ✅ `@FocusState` auto-focus in all sheets and popovers
- ✅ `.helpWhenUnlocked()` tooltips on toolbar buttons and interactive controls
- ✅ Accessibility labels on charts, metric cards, and Bulk Entry rows (assets and cash flows)
- ✅ Glass card material adapts to Reduce Transparency accessibility setting
- ✅ Animations with Reduce Motion support via `AnimationConstants`

______________________________________________________________________

# Part 1: Design Specification

## Navigation Structure

The app uses a **sidebar navigation** layout (standard macOS pattern):

**Sidebar items**:

1. **Dashboard** -- Portfolio overview (default/home screen)
1. **Snapshots** -- Chronological snapshot management
1. **Assets** -- Asset registry and category assignment
1. **Categories** -- Category management with target allocations
1. **Platforms** -- Platform management (rename)
1. **Rebalancing** -- Rebalancing calculator
1. **Import** -- CSV import workflow

**Detail views**: Each sidebar section with a list-detail pattern (Snapshots, Assets, Categories, Platforms) uses a **list-detail split** within the content area. The list appears on the leading side and the detail view on the trailing side. When no item is selected, the detail area shows a placeholder prompt (e.g., "Select a snapshot to view details").

**Dashboard, Rebalancing, and Import** occupy the full content area without a list-detail split.

**Toolbar**:

- **Back button** (chevron.left) -- navigates to the previous sidebar section in history; disabled when no history exists or app is locked
- **Forward button** (chevron.right) -- navigates to the next sidebar section in forward history; disabled when at the latest entry or app is locked
- Navigation history is tracked for all sidebar selection changes and programmatic navigation (chart click-to-navigate, post-import redirect). Forward history is truncated when navigating to a new section from a non-tail position.

______________________________________________________________________

## Dashboard (Home Screen)

The dashboard provides a portfolio overview using the latest snapshot.

**Layout**:

1. **Summary cards row**:

   - Total Portfolio Value (one display-currency value when all required rates are available; otherwise native totals grouped by currency)
   - Latest Snapshot Date
   - Number of Assets
   - Cumulative TWR (All Time) (since first snapshot)
   - CAGR (since first snapshot) -- shown alongside Cumulative TWR (All Time), with a tooltip: "CAGR is the annualized rate at which the portfolio's total value has grown since inception, including the effect of deposits and withdrawals. TWR measures pure investment performance by removing cash flow effects."
   - Metric cards use a `helpText: LocalizedStringKey?` parameter on `MetricCard` to display a tooltip via `.helpWhenUnlocked()` (suppressed when app is locked)

1. **Period performance cards**:

   - **Growth Rate** card -- simple percentage change with 1M / 3M / 1Y segmented control. Shows "N/A" if insufficient history.
   - **Return Rate** card -- Modified Dietz return with 1M / 3M / 1Y segmented control. Shows "N/A" if insufficient history.
   - Each card displays a date range subtitle (e.g., "Jan 24 – Feb 14") below the rate value when a rate is available, showing the actual period covered.
   - Each card uses the same `helpText` parameter on `MetricCard` for its `.helpWhenUnlocked()` tooltip

1. **Allocation pie chart**:

   - Category allocation with a **snapshot date picker** (defaults to latest snapshot)
   - Shows percentage and value for each category
   - Clicking a category navigates to category detail

1. **Portfolio value line chart**:

   - Total portfolio value over all snapshots
   - Time axis with snapshot dates
   - Time range zoom controls

1. **Cumulative TWR line chart**:

   - Portfolio-level cumulative time-weighted return over time
   - Shows "Insufficient data (need at least 2 snapshots)" when fewer than 2 snapshots

1. **Recent snapshots list**:

   - Last 5 snapshots (newest first) with date, total value, and import summary
   - "View all" link navigates to Snapshots screen
   - Each row is clickable and navigates to snapshot detail

**Currency availability:** When a required exchange rate is missing, native totals remain visible by currency. Currency-dependent metric cards and charts remain visible with a blur/material overlay that says which rates are missing and, for historical metrics, which snapshots are affected.

**Implementation notes (Charts)**:

- **DashboardView** (`AssetFlow/Views/DashboardView.swift`): Replaced chart placeholders with 2x2 grid of interactive charts. Row 1: `CategoryAllocationPieChart` (with snapshot date picker, click-to-navigate to category) + `PortfolioValueLineChart` (with click-to-navigate to snapshot). Row 2: `CumulativeTWRLineChart` + `CategoryValueLineChart` (multi-line with legend toggle). Each line chart has an independent `ChartTimeRange` `@State` that defaults to `.all` and resets on navigation via `dashboardRefreshID`.
- **`CategoryAllocationPieChart`**: HStack layout with pie chart (fixed square, centered) and dynamic multi-column legend panel (right-aligned). Legend uses `LazyVGrid` with column count adapting to both category count and available width — uses the fewest columns needed to display all categories without scrolling. Column width is measured dynamically from the widest legend item (capped at 180pt). Total content width is measured via `onGeometryChange` to derive available legend space.
- **DashboardViewModel** (`AssetFlow/ViewModels/DashboardViewModel.swift`): Provides `snapshotDates`, `categoryValueHistory` (per-category `[DashboardDataPoint]`), `categoryAllocations(forSnapshotDate:)`, and `categoryAllocationConversionStatus(forSnapshotDate:)` for historical pie chart data and availability. The pie chart overlay uses the selected snapshot's status, not only the latest snapshot's status. It uses `SnapshotSummaryService` to build converted total/category caches in one pass per snapshot.
- **ChartDataService** (`AssetFlow/Services/ChartDataService.swift`): Stateless `enum` with `ChartTimeRange` (8 cases: 1W/1M/3M/6M/1Y/3Y/5Y/All), generic `filter()` for `ChartFilterable` data, `rebasedTWR()`, and `abbreviatedLabel(for:)` for K/M/B Y-axis formatting. Filtering uses latest data point's date as reference (not `Date.now`).
- **Shared chart components** in `AssetFlow/Views/Charts/`: `ChartTimeRangeSelector` (segmented picker), `ChartStyles` (constants and color palette), and 5 chart views. All charts handle empty/edge states per SPEC 12.5.
- **ContentView** (`AssetFlow/Views/ContentView.swift`): Added `navigateToCategoryByName(_:)` to wire pie chart click → sidebar Categories selection. Guards against "Uncategorized" (not a real Category).

______________________________________________________________________

## Snapshots Screen

**List view**:

- Chronological list of all snapshots (newest first), grouped into collapsible relative time buckets
- Time buckets: **This Month**, **Previous 3 Months**, **Previous 6 Months**, **Previous Year**, **Older** — boundaries based on calendar month starts relative to today; empty buckets are hidden
- Collapsible `Section(isExpanded:)` disclosure triangles; all sections expanded by default
- Each row: date, total value, platforms included, number of assets
- "New Snapshot" button

**New Snapshot creation flow**:

1. User clicks "New Snapshot"
1. Date picker appears (future dates disabled)
1. If the selected date already has a snapshot, show validation error: "A snapshot already exists for [date]. Go to the Snapshots screen to view and edit it."
1. Starting point selector:
   - **Empty Snapshot**: Creates snapshot with no asset entries
   - **Bulk Entry**: Opens `BulkEntryView` for full-screen bulk value entry. Shows an empty state with "Add Platform" action when no prior snapshots exist.
1. On creation, user is taken to the snapshot detail view for editing

**Snapshot detail view** (on selection):

- Full asset breakdown sorted by platform (alphabetical), then by asset name (alphabetical), rendered as `ForEach` rows with `HStack` layout (not a `Table`)
- Each row shows: Asset Name (with Platform and Category as secondary caption), and Market Value aligned trailing; multi-currency assets also show the currency badge and an approximate converted value below the market value
- Category allocation summary for this snapshot (marked unavailable when required rates are missing)
- Exchange rates section (only for multi-currency snapshots): shows every used currency, its "1 foreign = X base" rate when available, and an explicit unavailable state otherwise; auto-fetches when missing or when display currency changes
- When conversion is incomplete, total value and net cash flow are shown as native-currency groups rather than being labelled as the display currency
- Cash flow operations table: Description, Amount
- Per-currency net cash flow summary (one line per currency, showing the net total for included rows)
- Actions: Add asset, Edit values, Remove asset, Delete snapshot, Add cash flow, Edit cash flow, Remove cash flow

**Add asset to snapshot**: Two paths:

1. **Select existing asset**: Autocomplete search by name. When selected, platform and category are read-only (inherited from asset record). Rejected if the asset already exists in this snapshot.
1. **Create new asset**: Enter name, select platform (picker includes a "New Platform..." option), select category (picker includes a "New Category..." option). Creates the asset record and adds it to the snapshot.

**Edit value**: Right-click an asset row and select "Edit Value" to open an inline popover anchored to the row. The popover contains a single text field and Save/Cancel buttons. Changes are saved immediately on Save.

**Remove asset from snapshot**: Confirmation dialog: "Remove [Asset Name] from this snapshot? The asset record itself will not be deleted."

**Delete snapshot**: Confirmation dialog: "Delete snapshot from [date]? This will remove all [N] asset values and [M] cash flow operations. This action cannot be undone."

______________________________________________________________________

## Assets Screen

**List view**:

- All known assets, grouped by platform (default) or category, switchable via **segmented control**
- Sort order: alphabetical by asset name within each group
- When grouped by platform, assets without a platform appear under "(No Platform)" at the end
- When grouped by category, assets without a category appear under "(Uncategorized)" at the end
- Each row: Asset Name, Platform, Category, Latest Value
- Latest value comes from the most recent snapshot
- Assets with no snapshot values show "\\u{2014}" for value
- A toolbar **Hide Stale Assets** toggle button (`eye.slash` icon, rendered with `.toggleStyle(.button)`) hides assets with no value in the latest snapshot. Default ON, persisted via `SettingsService.hideStaleAssets`. The button highlights while the filter is active. When the filter hides every asset, the list shows an "All Assets Are Stale" empty state instead of the default "No Assets" message.

**Asset detail view**:

- Value history across snapshots (table and interactive 250pt line chart with hover tooltips and a `ChartTimeRangeSelector` for filtering by time range)
- Value history shows all recorded values across snapshots
- Asset name (editable)
- Platform (editable via picker with existing platforms + "New Platform..." option)
- Category assignment (editable via picker with existing categories + "None" option)
- Changes save immediately on field change
- Renaming an asset updates it retroactively across all snapshots (single record update)
- Duplicate identity validation: (name, platform) must be unique (case-insensitive, trimmed, collapsed)
- Delete action: **only enabled when asset has no SnapshotAssetValue records**. When disabled, shows: "This asset cannot be deleted because it has values in snapshot(s). Remove the asset from all snapshots first."

### Implementation Notes

- **AssetListView** (`AssetFlow/Views/AssetListView.swift`): Uses `AssetListViewModel` with `@State`. Segmented control binds to `viewModel.groupingMode`. List sections iterate over `viewModel.groups`. Context menu on rows provides delete action for eligible assets.
- **AssetDetailView** (`AssetFlow/Views/AssetDetailView.swift`): Uses `AssetDetailViewModel` with `@State`. Form with `.grouped` style. Platform picker is provided by `PlatformPickerField`. Value history section shows a `ChartTimeRangeSelector` and an interactive 250pt line chart (`ChartConstants.standardChartHeight`) with hover tooltips via `.onContinuousHoverWhenUnlocked`. When the asset currency differs from the display currency, a `showConvertedChart` toggle button appears next to the range selector; activating it switches the chart to show values converted to the display currency (in green) and adds a "Converted Value" column to the value history table. Delete confirmation dialog before deletion. Value history table supports inline editing: double-click a market value or right-click and choose "Edit Value" to open a popover for editing the value in place.
- **AssetListViewModel** (`AssetFlow/ViewModels/AssetListViewModel.swift`): Groups assets by platform or category. Computes latest values from the most recent snapshot using a bounded latest-snapshot fetch. "(No Platform)" and "(Uncategorized)" groups always sorted last. Reads `SettingsService.hideStaleAssets` inside `withObservationTracking` so toggling the filter automatically reloads. `hasHiddenStaleAssets` is true when the filter dropped at least one asset; the View uses it to swap the empty-state message. Persistence failures are represented by `DataLoadState.failed` and shown with a retry action.
- **AssetDetailViewModel** (`AssetFlow/ViewModels/AssetDetailViewModel.swift`): Editable fields (`editedName`, `editedPlatform`, `editedCategory`) initialized from asset. `save()` validates normalized identity uniqueness. `loadValueHistory()` returns direct SAVs sorted chronologically. `editAssetValue(_:newValue:)` mutates the `SnapshotAssetValue` market value and refreshes the history.

______________________________________________________________________

## Categories Screen

**List view**:

- All categories listed by user-defined display order (drag-to-reorder supported)
- Each row: name, target allocation %, current allocation %, current value, asset count
- Visual indicator when current allocation deviates significantly from target
- Add/edit/delete category actions
- Drag-and-drop reordering via `.onMove` modifier persists order via `displayOrder` property

**Category detail view**:

- Assets in this category
- Value history over snapshots (line chart)
- Allocation percentage history over snapshots (line chart)

**Cross-section navigation**: Clicking a category in the dashboard pie chart navigates to the Categories section in the sidebar and selects the clicked category, showing its detail view. This is a cross-section navigation action (Dashboard -> Categories).

**Implementation notes:**

- **CategoryListView** (`AssetFlow/Views/CategoryListView.swift`): Takes `modelContext` and `selectedCategory: Binding<Category?>`. Uses `@State private var viewModel: CategoryListViewModel`. List selection drives the binding. Toolbar "+" button opens add category sheet. Target allocation sum warning banner shown at top when allocations don't sum to 100%. Deviation indicator (orange `exclamationmark.triangle.fill`) shown when `abs(current - target) > 5`. Empty state uses folder icon.
- **CategoryListViewModel** (`AssetFlow/ViewModels/CategoryListViewModel.swift`): `CategoryRowData` struct bundles category, target/current allocation, value, and asset count. `loadCategories()` computes values from a bounded latest-snapshot fetch. `createCategory`/`editCategory`/`deleteCategory` with validation via `CategoryError`. `moveCategories(from:to:)` handles drag-to-reorder by updating `displayOrder` on each category. On first load, if all categories have the same `displayOrder` (migration scenario), they are normalized alphabetically. Failed reads use the retryable load-error state rather than the empty state.
- **CategoryDetailView** (`AssetFlow/Views/CategoryDetailView.swift`): Takes `category`, `modelContext`, `onDelete`. Parent must apply `.id(category.id)` for proper state reset. Form sections: Category Details (name + target allocation), Assets in Category (`AssetTableView` with "Platform" second column), Value History (LineMark + PointMark chart), Allocation History (LineMark + PointMark chart), Danger Zone (delete button).
- **CategoryDetailViewModel** (`AssetFlow/ViewModels/CategoryDetailViewModel.swift`): `editedName`/`editedTargetAllocation` initialized from category. `loadData()` computes the asset list with latest values plus value/allocation history across all snapshots, using `SnapshotSummaryService` for converted historical totals. Single snapshot renders as PointMark only.

**Implementation notes (Charts):**

- Value history chart now uses `ChartTimeRangeSelector` with `ChartDataService.filter()` for time range zoom. Y-axis uses abbreviated labels (K/M/B).
- Allocation history chart replaced with reusable `CategoryAllocationLineChart` component from `Views/Charts/`, which includes time range selector and hover tooltips.
- Both chart time ranges default to `.all` and reset when the selected category changes (via `.id(category.id)` on the parent).

______________________________________________________________________

## Platforms Screen

**List view**:

- All platforms listed alphabetically
- Each row: Platform name, number of assets, total latest value

**Platform detail view** (on selection):

- List of all assets on this platform with their latest market values
- Total value across all assets on this platform
- Platform name (editable)

**Actions**:

- **Rename**: Change platform name. Updates all assets. New name must not conflict (case-insensitive).
- **Delete**: Implicit -- when all assets are moved away, platform no longer appears.

Assets with no platform are NOT shown on the Platforms screen.

### Implementation Notes

**Layout**: 3-column split (sidebar | platform list | platform detail), consistent with Snapshots, Assets, and Categories. `ContentView` uses a `GeometryReader` wrapping an `HStack(spacing: 0)` with `PlatformListView` (30% width, 250pt minimum), a `Divider`, and `PlatformDetailView` (or a "Select a platform" placeholder when nothing is selected). Categories use the same 3:7 ratio; Snapshots use 4:6. `PlatformDetailView` uses `.id(platform)` for forced recreation on rename.

**Rename-propagation flow**:

1. User edits name in `PlatformDetailView` → hits Return
1. `PlatformDetailViewModel.save()` validates and renames all matching `Asset.platform` values
1. `save()` updates internal `platformName` state
1. Detail view calls `onRename(newName)` callback
1. `ContentView` sets `selectedPlatform = newName` (triggers `.id()` recreation of detail view)
1. `PlatformListView.onChange(of: selectedPlatform)` fires → `viewModel.loadPlatforms()` refreshes list

**Platforms are not SwiftData model objects** — they are derived from distinct non-empty `Asset.platform` string values. Selection binding is `String?` (not a model ID), and rename mutates all `Asset` records with the old platform name.

- **PlatformListView** (`AssetFlow/Views/PlatformListView.swift`): List-detail split with `List(selection: $selectedPlatform)`. Row context menu retains rename popover for quick renaming. `.onChange(of: selectedPlatform)` reloads platforms after rename propagation. Empty state with `building.columns` icon.
- **PlatformDetailView** (`AssetFlow/Views/PlatformDetailView.swift`): `Form(.grouped)` with three sections: Platform Details (editable name `TextField`), Assets on Platform (`AssetTableView` with "Category" second column), and Value History (line chart with `ChartTimeRangeSelector` and hover tooltip). No delete section — platforms disappear when all assets are reassigned.
- **PlatformListViewModel** (`AssetFlow/ViewModels/PlatformListViewModel.swift`): Derives platforms from `Asset.platform` values. `loadPlatforms()` computes totals from a bounded latest-snapshot fetch. `renamePlatform(from:to:)` validates uniqueness (case-insensitive), trims and normalizes whitespace, then updates all matching assets.
- **PlatformDetailViewModel** (`AssetFlow/ViewModels/PlatformDetailViewModel.swift`): Tracks `platformName` (updated after rename), `assets` (filtered to this platform, sorted alphabetically), `totalValue` (sum of latest values), and `valueHistory` (platform total per snapshot via `SnapshotSummaryService`). `save()` validates and renames all matching Asset records.

______________________________________________________________________

## Rebalancing Screen

- Current allocation vs. target allocation table
- For each category: current value, current %, target %, difference ($), action (buy/sell amount)
- Sort order: by absolute adjustment magnitude (largest deviation first)
- Summary of suggested moves
- Read-only/preview -- no data modification occurs
- Only categories with a target allocation are included
- Uncategorized assets shown as separate row with "--" for Target % and "N/A" for Action

### Implementation Notes

- **RebalancingView** (`AssetFlow/Views/RebalancingView.swift`): ScrollView with Grid-based tables. Three sections: "Categories with Targets" (main suggestions), "No Target Set", and "Uncategorized". Summary section shows suggested moves. Action text color-coded: green (Buy), red (Sell), gray (No action needed). Empty state with `chart.bar.doc.horizontal` icon.
- **RebalancingViewModel** (`AssetFlow/ViewModels/RebalancingViewModel.swift`): Loads values from a bounded latest-snapshot fetch. Groups by category, calls `RebalancingCalculator.calculateAdjustments()`, maps actions to display rows with localized action text. Adjustments under $1 display "No action needed" (SPEC 11.4).

______________________________________________________________________

## Bulk Entry View

Full-screen view for entering asset values across all platforms in a single session. Presented when the user selects "Bulk Entry" in the New Snapshot sheet.

**Layout**:

- Toolbar with snapshot date title, progress stats, validation warnings, "Add Platform" button, and "Save Snapshot" button
- Assets grouped by platform in sections (alphabetical order)
- Each section header includes an "Add Asset" button and a "CSV Import" button
- Empty state (no prior snapshots): `ContentUnavailableView` with "Add Platform" action

**Columns**:

- **Include checkbox**: Controls whether the row is saved to the snapshot
- **Asset Name**: Read-only for existing assets; editable `TextField` for new rows (`.manualNew`), with "NEW" green badge or "CSV" blue badge
- **Category**: Static text for existing assets; `CategoryNamePicker` dropdown for new assets (deferred DB creation)
- **Currency**: Static text for existing assets; `Picker` for new rows
- **Previous Value**: Value from the most recent prior snapshot with full decimal precision (or "\\u{2014}" if none). Hover reveals a fill button (`arrow.right.circle.fill`) that copies the value to the New Value field.
- **New Value**: Editable text field for the new market value

**Row states**:

- **Updated** (green accent): Value has been entered or imported
- **Pending** (normal): Included but no value entered yet (saves as 0)
- **Excluded** (dimmed): Checkbox unchecked, row is omitted from the snapshot

If the underlying snapshots, assets, categories, or prior snapshot values used to seed a Bulk Entry draft change, the view shows a stale-data banner, disables editing and saving, and offers **Discard Draft and Reload**. The app shell also marks a retained draft stale if one of its source models changes while another section is selected. Reloading creates a fresh draft from the latest snapshot; drafts are never silently overwritten.

**Inline asset creation**: Each platform header has an "Add Asset" button that appends an editable row with empty name, default currency, and a category picker. New rows have a delete (trash) button. New rows require a non-empty name to save.

**Add Platform**: Toolbar button opens a popover with a text field for the platform name. Validates against empty names and case-insensitive duplicates. Creates a new platform group with one empty asset row.

**Keyboard navigation**: Enter advances focus to the next included row's value field (assets) or amount field (cash flows). In cash flow rows, Enter on the description field moves to the same row's amount field. Adding a new asset or cash flow row auto-focuses the appropriate field (name or description).

**Per-platform CSV import**: Each platform section has an import button that opens a file picker filtered to `.csv`. Parsed values are matched to assets by name (including manually-added rows) and populate the New Value fields. Every outcome displays an import feedback alert: success, warnings for skipped rows, or errors for malformed/unreadable files. Any parser or row-validation error leaves the previous CSV values unchanged, including when the file also contains valid rows.

While a file is being read or prepared, Bulk Entry shows an indeterminate progress indicator and a Cancel action. Cancellation leaves the existing rows and CSV feedback unchanged.

**Validation warnings** (toolbar):

- Zero-value assets: "N assets have a value of 0. Exclude them or enter a non-zero value."
- Empty names: "Some new assets are missing a name."
- Duplicate asset names within a platform are validated at save time (not shown as a toolbar warning).

**Cash Flow Operations section** (below asset table, separated by a divider):

- **Section header**: "Cash Flow Operations" title with a count badge showing the number of included cash flow rows, an "Add Cash Flow" button for manual entry, and an "Import CSV" button for CSV import
- Cash flows are portfolio-level (not grouped by platform)
- The section starts empty each time (no carry-forward from previous snapshots)

**Cash flow columns**:

- **Include** (toggle): Controls whether the row is saved to the snapshot
- **Description** (text field): Required; identifies the cash flow operation
- **Amount** (text field): Monetary value; positive = inflow, negative = outflow
- **Currency** (picker): Currency for the cash flow operation
- **Delete** (trash button): Only available for manually-added rows (`.manualNew`)

**Cash flow row badges**: CSV-imported rows display a blue "CSV" source badge next to the description field.

**Cash flow keyboard navigation**: Enter on a description field advances to the same row's amount field. Enter on an amount field advances to the next included row (description field for new rows, amount field for existing/CSV rows). Adding a new cash flow row auto-focuses the description field.

**Cash flow net summary**: Below the cash flow rows, a per-currency net cash flow summary displays the total of all included rows' amounts, grouped by currency. Hidden when no cash flow rows exist.

**Cash flow accessibility**: Each row has a composite `.accessibilityLabel` including description, amount, and included/excluded status.

**Cash flow CSV import**: The "Import CSV" button opens a file picker filtered to `.csv`. Uses the `.cashFlow` schema with auto-detect column mapping (required: Description, Amount; optional: Currency). Re-importing CSV clears all previous CSV-sourced rows only after the replacement has validated successfully; any parser or row-validation error shows feedback and leaves the previous CSV rows unchanged, including when the file also contains valid rows.

**Cash flow validation warnings** (displayed in the toolbar popover alongside asset warnings):

- Empty descriptions: "Some cash flows are missing a description."
- Duplicate descriptions: Case-insensitive duplicate detection blocks save
- Invalid amount text: Unparseable amount values block save

**Confirmation alerts**:

- **Save with pending rows**: Warning that N assets will be saved with a value of 0, with options to proceed or cancel.

______________________________________________________________________

## Import Screen

See [BusinessLogic.md](BusinessLogic.md) for the detailed CSV import flow.

**Layout**:

- **Import type selector**: Segmented control (Assets | Cash Flows), defaults to Assets
- **File selector**: Drag-and-drop zone or "Browse" button (filtered to `.csv`). Dropped file URLs and raw CSV data are both supported; read and parse failures remain visible in the validation area.
- **Loading state**: While a file is being read or prepared, the screen shows an indeterminate progress indicator and keeps the existing preview state unchanged until preparation completes. Cancellation is honored by the owning task, and cancelled work does not replace the preview.
- **Column mapping sheet** (shown automatically when CSV headers don't match expected columns): A full CSV table preview with per-column dropdowns allowing the user to assign each CSV column to a canonical field (e.g., `Asset Name`, `Market Value`) or skip it. Auto-detected matches are pre-selected. Skipped entirely when headers already match (case-insensitive). Shared between Import Screen and Bulk Entry per-platform CSV import. Uses `NavigationStack` with toolbar (Cancel/Confirm) for macOS Liquid Glass integration.
- **Expected schema display**: Show the expected CSV column names for the selected import type and provide downloadable sample CSVs
- **Configuration** (after file selected or column mapping confirmed):
  - Asset import: Snapshot date picker (future dates disabled), Platform picker (with "All Rows" toggle when mixed platforms), Category picker (with "All Rows" toggle when mixed categories)
  - Cash flow import: Snapshot date picker (future dates disabled)
  - Platform and Category pickers use pill-style background (`.fill.quaternary` with rounded corners). The "All Rows" checkbox toggle appears when the CSV contains a mix of values that make the apply mode meaningful.
  - Category apply mode: "All Rows" checked (default) = override all assets with the selected category; unchecked = only assign category to assets that don't already have one.
- **Preview table**: Parsed data with validation indicators and per-row remove buttons.
  - Asset preview columns: Asset Name, Market Value, Currency, Platform, Category
  - Currency column shows the effective currency (CSV value, or existing asset currency as fallback)
  - Category column shows the effective post-import category based on apply mode
  - **Per-row error/warning popovers** (hover to reveal):
    - Within-CSV duplicate errors (red circle) — shown next to asset name
    - Snapshot duplicate errors (red circle) — shown next to asset name
    - Category reassignment warnings (yellow triangle) — shown next to asset name (only in "All Rows" mode)
    - Market value warnings (zero/negative, yellow triangle) — shown next to market value
    - Currency errors (unsupported code, red circle) — shown next to currency cell
    - Currency change warnings (yellow triangle) — shown next to currency cell
  - Cash flow preview shows duplicate/snapshot-duplicate popovers next to description
- **Validation summary**: File-level parsing errors (red) and warnings (yellow) only; row-level issues are shown as per-row popovers
- **Import button**: Disabled if validation errors or per-row errors exist on included rows
- **On successful import**: Snapshot is created (or updated if one exists for that date); user is navigated to the snapshot detail view

If user navigates away (including sidebar navigation) with file loaded but not imported, confirmation dialog: "Discard import? The selected file has not been imported yet."

______________________________________________________________________

## Empty States

All empty states use `ContentUnavailableView` (macOS 14.0+), which provides a consistent native macOS layout with `Label` (icon + title), `description` text, and optional `actions`. This replaced the custom `EmptyStateView` component for better platform consistency.

Read failures are not empty states: list and detail screens show an `Unable to load data` error with the localized persistence message and a `Retry` action. The empty state is shown only after a successful load with no matching records.

| Screen      | Icon                       | Title                | Message                                                                                          | Actions                         |
| ----------- | -------------------------- | -------------------- | ------------------------------------------------------------------------------------------------ | ------------------------------- |
| Dashboard   | `chart.bar`                | Welcome to AssetFlow | Start tracking your portfolio by importing CSV data or creating a snapshot.                      | Import your first CSV (primary) |
| Snapshots   | `calendar`                 | No Snapshots         | No snapshots yet. Create your first snapshot or import a CSV to get started.                     | New Snapshot, Import CSV        |
| Assets      | `tray`                     | No Assets            | No assets yet. Assets are created automatically when you import CSV data.                        | —                               |
| Categories  | `folder`                   | No Categories        | No categories yet. Create categories to organize your assets and set target allocations.         | Create Category                 |
| Platforms   | `building.columns`         | No Platforms         | No platforms yet. Platforms are created automatically when you import CSV data or create assets. | —                               |
| Rebalancing | `chart.bar.doc.horizontal` | No Rebalancing Data  | Set target allocations on your categories to use the rebalancing calculator.                     | —                               |

______________________________________________________________________

## Settings

Accessible via menu bar (AssetFlow > Settings) or Cmd+,.

**Settings options**:

1. **Display currency**: Currency code (e.g., USD, TWD, EUR). Display-only, no FX conversion.
1. **Date format**: Picker with Swift `Date.FormatStyle` options (`.numeric`, `.abbreviated`, `.long`, `.complete`). Default: system locale or `.abbreviated`.
1. **Default platform**: Pre-filled platform value during import (can be overridden per import). Default: empty.
1. **Security**:
   - **Require Authentication** toggle: Enables/disables app lock. Off by default. When toggling on, the system authentication dialog is presented first to verify identity (prevents accidental lockout). When toggling off, the app unlocks immediately.
   - **When Switching Apps** picker (shown only when toggle is on): Configures re-lock timeout for app switch events (Cmd+Tab, click another window, minimize) — Immediately, After 1 Minute, After 5 Minutes, After 15 Minutes, Never.
   - **When Locked or Sleeping** picker (shown only when toggle is on): Configures re-lock timeout for screen lock / sleep events — Immediately, After 1 Minute, After 5 Minutes, After 15 Minutes, Never.
   - **Auto-disable**: When both pickers are set to "Never", the Require Authentication toggle is automatically turned off.
   - **Footer text**: Three variants based on state — when disabled: explains what enabling does; when enabled with Touch ID: explains the two trigger conditions, "Never" option, and auth methods; when enabled without Touch ID: same but notes system password only.
1. **Data Management**:
   - **Export Backup**: Exports all data to ZIP archive. User selects save location. Default filename: `AssetFlow-Backup-YYYY-MM-DD.zip`.
   - **Restore from Backup**: Imports backup archive. Confirmation: "Restoring from backup will replace ALL existing data. This cannot be undone. Continue?" Validates file integrity (CSV presence, headers, foreign key references). On failure, shows detailed error. On success, SwiftData `@Query` invalidation and model query fingerprints reload active screens; retained selections are rebound by stable model ID, while deleted selections are cleared. Query-backed caches also refresh after relevant edits to existing records, not only after restore.
1. **About**: App identity and legal information at the bottom of Settings.
   - **App identity row**: App icon (48×48), app name (headline), version + build number (subheadline), commit hash (caption). The commit hash includes a `-dev` suffix when built from a dirty working tree.
   - **Developer**: Static field showing the developer name.
   - **License**: Static field showing the license (GNU General Public License v3.0).
   - **Privacy**: "All data is stored locally. No data is collected or transmitted."
   - **GitHub link**: Tappable `Link` that opens the source repository in the browser.
   - **User Guide link**: Tappable `Link` that opens the documentation site, version- and locale-aware (see Help menu below).

**Lock screen overlay**: When app lock is enabled and the app is locked (on launch or after returning from background beyond the timeout), a full-window opaque overlay (`LockScreenView`) is displayed in a `ZStack` above `ContentView`. It shows the app icon (128×128), "AssetFlow is Locked" title, and an "Unlock" button. The system authentication dialog is triggered automatically on appear. The overlay uses `.regularMaterial` background to fully obscure content. No custom biometric UI — the system `LAContext.evaluatePolicy` dialog handles Touch ID, Apple Watch, and password fallback. Background-date recording is suppressed while authentication is in progress (`isAuthenticating`) to prevent the system auth dialog from triggering a re-lock loop.

**Consistent lock overlays**: Both the main `WindowGroup` and the `Settings` scene use the same `ZStack` + `LockScreenView` pattern. When `authService.isLocked` is `true`, each window independently shows a full opaque material overlay with an Unlock button. No windows are closed when locking — this avoids bugs caused by `NSApplication.shared.mainWindow` returning the wrong window.

**Native About panel** (App menu → About AssetFlow): Replaced via `CommandGroup(replacing: .appInfo)` in `AssetFlowApp.swift`. Shows version + build number as the version string, with a rich-text credits block containing the commit hash, license, copyright, a clickable "Source Code" hyperlink, and the privacy statement.

**File menu commands**: Replaced via `CommandGroup(replacing: .newItem)`. Includes "New Snapshot..." (Cmd+N) and "Import CSV..." (Cmd+I). Uses `@FocusedValue` to bridge actions from the menu bar to `ContentView`. Both commands are disabled when `authService.isLocked` is `true`.

**Help menu** (Help → AssetFlow User Guide / Report an Issue): Replaced via `CommandGroup(replacing: .help)` in `AssetFlowApp.swift`. Two items:

- **AssetFlow User Guide** -- opens the documentation site at the correct version and locale. Dev builds (version contains `-dev`) link to `/dev/`; release builds link to `/v{version}/`. Locale is auto-detected: Chinese → `/zh-TW/`, otherwise root (English is the default, no locale prefix).
- **Report an Issue** -- opens the GitHub Issues page.

The macOS Help menu's built-in search field (which searches menu items) is preserved -- `CommandGroup(replacing:)` only replaces the menu items, not the search field.

______________________________________________________________________

## Keyboard Shortcuts

| Shortcut | Context                       | Action                                                           |
| -------- | ----------------------------- | ---------------------------------------------------------------- |
| Delete   | Snapshot list (item selected) | Delete selected snapshot (confirmation dialog)                   |
| Delete   | Asset list (item selected)    | Delete selected asset (error alert if it has snapshot values)    |
| Delete   | Category list (item selected) | Delete selected category (error alert if it has assigned assets) |
| Cmd+,    | Global                        | Open Settings window (standard macOS `Settings` scene)           |

**Implementation**: Delete key uses `.onDeleteCommand` on each List view, delegating to the same ViewModel delete methods as the context menu. The Settings shortcut is provided automatically by the SwiftUI `Settings` scene in `AssetFlowApp.swift`.

______________________________________________________________________

## Localization

AssetFlow uses Apple String Catalogs (`.xcstrings`) with **English** as the development language and **Traditional Chinese (zh-Hant)** as the additional supported language.

**String catalog organization by feature:**

| Catalog                 | Scope                                           |
| ----------------------- | ----------------------------------------------- |
| `Localizable.xcstrings` | All SwiftUI view-level strings (auto-extracted) |
| `Asset.xcstrings`       | Asset validation and error messages             |
| `Category.xcstrings`    | Category validation and error messages          |
| `Platform.xcstrings`    | Platform operation messages                     |
| `Snapshot.xcstrings`    | Snapshot validation and error messages          |
| `Import.xcstrings`      | Import workflow messages                        |
| `Rebalancing.xcstrings` | Rebalancing action text                         |
| `Services.xcstrings`    | Backup/restore messages                         |
| `Settings.xcstrings`    | Settings display strings                        |

**Conventions:**

- SwiftUI view strings (in `Text()`, `Label()`, etc.) are auto-extracted into `Localizable.xcstrings`
- ViewModel and Service strings use `String(localized:table:)` with the appropriate feature table
- Enum display names use `localizedName` computed properties — never display `rawValue` directly
- Translation style: idiomatic Traditional Chinese matching Taiwan usage (e.g., 資產, 快照, 類別, 平台, 再平衡, 儀表板, 匯入, 備份)

______________________________________________________________________

## Window and Appearance

- **Window style**: `.windowStyle(.hiddenTitleBar)` with `.windowToolbarStyle(.unified)` for modern macOS Tahoe Liquid Glass integration
- **Minimum window size**: 900 x 600 points
- **Sidebar**: Collapsible via toolbar button or drag. Default width: 220 points.
- **Appearance**: Supports system appearance (light and dark mode). All custom colors and chart colors adapt to both modes.

**Number formatting**:

- Monetary values: Full stored precision with thousand separators (e.g., $1,234.5, $28,000). No minimum or maximum decimal places are enforced -- values display exactly as entered or computed.
- Percentages: 2 decimal places (e.g., 45.23%)
- Chart axes: Abbreviated for large values (K, M, B)

Allocation percentage totals display actual sum (no forced normalization to 100%).

______________________________________________________________________

## Visualizations

### Time Range Controls

All line charts include a zoom selector:

- 1W, 1M, 3M, 6M, 1Y, 3Y, 5Y, All
- Default: All
- Shows only snapshots within selected range
- "No data for selected period" if empty
- Range resets to "All" when navigating away (not persisted)

### Pie Chart -- Category Allocation (Section 12.1)

- Shows allocation at a selected snapshot (default: latest)
- Each slice = one category
- Slices sorted by value (largest first, clockwise from 12 o'clock)
- Uncategorized shown as distinct slice (uses a neutral/gray tone to indicate it is not a user-defined category)
- Labels: category name, percentage, value
- Legend is displayed as a dynamic multi-column grid to the right of the pie chart, showing color swatch, category name, and percentage for each category. The number of columns adapts to both the category count and the available width — using the fewest columns needed to fit all categories without scrolling. Column width is measured from the widest item content (capped at 180pt). The pie chart is fixed to a square aspect ratio and centered in the remaining space, with the legend right-aligned. Legend items are interactive: hovering highlights the corresponding slice, and clicking navigates to category detail.
- Hover: tooltip with details. Click: navigates to category detail.

### Line Chart -- Portfolio Value Over Time (Section 12.2)

- X-axis: snapshot dates. Y-axis: portfolio total value.
- Data points at each snapshot
- Hover: tooltip with date and value. Click: navigates to snapshot detail.
- Time range zoom controls

### Line Chart -- Category Value Over Time (Section 12.3)

- Multiple lines, one per category
- Legend with category names
- Toggle individual categories on/off
- Hover: tooltip with date, category name, value. No click-to-navigate.
- Time range zoom controls

Category detail also includes allocation percentage line chart (same format, single category).

### Cumulative TWR Chart (Section 12.4)

- X-axis: snapshot dates. Y-axis: cumulative TWR (%)
- Portfolio-level return over time
- Hover: tooltip with date and TWR percentage. No click-to-navigate.
- Time range zoom controls
- **Rebasing:** When a non-"All" time range is selected, TWR values are rebased so the first visible point starts at 0%, showing period-specific returns. The "All" range shows inception-based values unchanged.
- The metric card is labeled "Cumulative TWR (All Time)" to distinguish it from the chart's period-rebased values.

### Chart Axis Stability

All interactive charts (those with hover tooltips or click-to-navigate) must pin both X and Y axis domains explicitly using `.chartXScale(domain:)` and `.chartYScale(domain:)`. This prevents axis recalculation and visual shifts when conditional marks (e.g., `RuleMark` annotations) are added or removed during hover/tap interactions.

### Chart Empty and Edge States

| Chart                  | Condition                                | Display                                         |
| ---------------------- | ---------------------------------------- | ----------------------------------------------- |
| Pie chart              | All assets uncategorized                 | Single slice "Uncategorized" 100%               |
| Pie chart              | No assets in latest snapshot             | "No asset data available"                       |
| Line chart (portfolio) | Only one snapshot                        | Single data point with label, no line           |
| Line chart (portfolio) | No snapshots in range                    | "No data for selected period"                   |
| Line chart (category)  | No categories defined                    | "Create categories to see allocation trends"    |
| Line chart (category)  | Category has zero value in all snapshots | Omit from chart, show "(no data)" in legend     |
| TWR chart              | Fewer than 2 snapshots                   | "Insufficient data (need at least 2 snapshots)" |
| TWR chart              | All returns N/A in range                 | "Cannot calculate returns for selected period"  |

______________________________________________________________________

## Visual Style

### Color Usage

**Semantic Colors** (leverage system defaults):

- **Accent**: Primary actions and highlights (system blue)
- **Positive**: Value increases (green)
- **Negative**: Value decreases (red)
- **Neutral**: Informational (gray)

**Automatic Dark Mode**: Use semantic color names, test all screens in both modes.

### Typography

- **Screen Titles**: `.title` or `.largeTitle`
- **Section Headers**: `.title2` or `.title3`
- **Primary Content**: `.body`
- **Secondary Info**: `.subheadline` or `.caption`
- **Financial Values**: Monospaced digits for alignment

**Formatting**:

- Currency: Use `Decimal` with `.formatted(currency:)` extension
- Percentages: Use `.formattedPercentage()` extension
- Large numbers: K, M, B suffixes in chart axes

### Iconography

**SF Symbols**:

- Add: `plus.circle.fill`
- Edit: `pencil`
- Delete: `trash`
- Import: `square.and.arrow.down`
- Export: `square.and.arrow.up`
- Info: `info.circle`
- Chart: `chart.pie.fill`, `chart.xyaxis.line`

### Spacing and Layout

- 8pt base unit (small: 8pt, medium: 16pt, large: 24pt)
- Cards: Secondary background, 16pt padding, 10-12pt corner radius
- Lists: Full width within safe areas

### Component Patterns

- **Empty States**: Centered icon, brief message, call-to-action button
- **Loading States**: Progress spinner with text
- **Error States**: Error icon, clear message, suggested action
- **Confirmation Dialogs**: For all destructive actions (delete snapshot, delete asset from snapshot, restore from backup)

______________________________________________________________________

## Accessibility Considerations

### Visual Accessibility

- Use semantic colors (WCAG AA contrast)
- Support Dynamic Type
- Respect Reduce Motion via `AnimationConstants` (near-instant fallback durations)

### Screen Reader (VoiceOver)

- All interactive elements have clear labels
- Logical reading order
- Actionable items clearly identified

### Keyboard Navigation

- Full keyboard navigation on macOS
- Logical tab order
- Visible focus indicators

______________________________________________________________________

# Part 2: Implementation Guide

## SwiftUI Implementation Patterns

### Navigation Structure

```swift
NavigationSplitView {
    // Sidebar
    List(selection: $selectedSection) {
        NavigationLink(value: Section.dashboard) {
            Label("Dashboard", systemImage: "chart.bar")
        }
        NavigationLink(value: Section.snapshots) {
            Label("Snapshots", systemImage: "calendar")
        }
        // ... other items
    }
    .navigationSplitViewColumnWidth(min: 180, ideal: 220)
} detail: {
    switch selectedSection {
    case .dashboard:
        DashboardView()
    case .snapshots:
        SnapshotsSplitView()
    // ... other sections
    }
}
.frame(minWidth: 900, minHeight: 600)
```

### List-Detail Split Pattern

For sections with list-detail (Snapshots, Assets, Categories, Platforms), the outer `NavigationSplitView` provides the sidebar+detail layout, and each inner split view provides the list+detail layout within the detail column. This creates a 3-column layout on macOS (sidebar | list | detail). Use `NavigationSplitView(columnVisibility:)` with `.all` to ensure the 3-column mode is available:

```swift
struct SnapshotsSplitView: View {
    @State private var viewModel: SnapshotListViewModel
    @State private var selectedSnapshot: Snapshot?

    init(modelContext: ModelContext) {
        _viewModel = State(
            initialValue: SnapshotListViewModel(modelContext: modelContext))
    }

    var body: some View {
        NavigationSplitView {
            Group {
                if case .failed(let message) = viewModel.loadState {
                    DataLoadErrorView(message: message) {
                        viewModel.loadRowData()
                    }
                } else {
                    List(viewModel.snapshots, selection: $selectedSnapshot) { snapshot in
                        SnapshotRowView(snapshot: snapshot)
                    }
                }
            }
            .toolbar {
                Button("New Snapshot", systemImage: "plus") { /* ... */ }
            }
        } detail: {
            if let snapshot = selectedSnapshot {
                SnapshotDetailView(snapshot: snapshot)
            } else {
                ContentUnavailableView(
                    "Select a Snapshot",
                    systemImage: "calendar",
                    description: Text("Select a snapshot to view details")
                )
            }
        }
    }
}
```

`SnapshotListView` may retain an `@Query` as an invalidation signal for collection membership changes, but it must not render that query directly or pass its results into row loading. Snapshot display and creation both use the throwing `SnapshotListViewModel`, so a failed fetch cannot become “No Snapshots” and a failed date check cannot insert a duplicate.

### Popover Pattern for Quick Edits

Lightweight edit interactions (1-2 fields) use `.popover()` anchored to their trigger row instead of modal sheets. This provides faster, less disruptive editing:

```swift
.popover(
    isPresented: Binding(
        get: { editingItem?.id == item.id },
        set: { if !$0 { editingItem = nil } }
    ),
    arrowEdge: .trailing
) {
    VStack(alignment: .leading, spacing: 12) {
        Text("Edit Value").font(.headline)
        TextField("Value", text: $valueText).textFieldStyle(.roundedBorder)
        HStack {
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Spacer()
            Button("Save") { save() }.keyboardShortcut(.defaultAction)
        }
    }
    .frame(width: 280)
    .padding()
}
```

Popovers are used for: Edit Asset Value, Edit Cash Flow, Rename Platform. Complex multi-field forms (Add Asset, Add Cash Flow, Add Category) remain as modal sheets.

### Sheet Pattern (Standard macOS)

All modal sheets use the standard macOS sheet pattern with `NavigationStack` + toolbar placements. `@FocusState` is used to auto-focus the first field on appear:

```swift
NavigationStack {
  Form { ... }
  .formStyle(.grouped)
  .navigationTitle("Sheet Title")
  .toolbar {
    ToolbarItem(placement: .cancellationAction) {
      Button("Cancel") { dismiss() }
    }
    ToolbarItem(placement: .confirmationAction) {
      Button("Create") { ... }
        .disabled(...)
    }
  }
}

// Auto-focus first field:
@FocusState private var focusedField: Field?
.onAppear { focusedField = .name }
```

### Menu Bar Commands

The File menu includes custom commands via `CommandGroup(replacing: .newItem)`:

- **New Snapshot...** (Cmd+N) -- navigates to Snapshots section and opens the New Snapshot sheet
- **Import CSV...** (Cmd+I) -- navigates to the Import CSV section

These use `@FocusedValue` to bridge between menu commands and `ContentView` state. `FocusedValueKey` types (`NewSnapshotActionKey`, `ImportCSVActionKey`) are defined in `ContentView.swift`.

The Help menu includes custom commands via `CommandGroup(replacing: .help)`:

- **AssetFlow User Guide** -- opens the version- and locale-aware documentation URL (`Constants.AppInfo.documentationURL`)
- **Report an Issue** -- opens the GitHub Issues page (`Constants.AppInfo.issuesURL`)

### Chart Implementation

Use Swift Charts framework:

```swift
import Charts

// Pie chart for category allocation
Chart(categoryData) { item in
    SectorMark(
        angle: .value("Value", item.value),
        innerRadius: .ratio(0.5)
    )
    .foregroundStyle(by: .value("Category", item.name))
}

// Line chart for portfolio value
Chart(snapshotData) { point in
    LineMark(
        x: .value("Date", point.date),
        y: .value("Value", point.totalValue)
    )
    PointMark(
        x: .value("Date", point.date),
        y: .value("Value", point.totalValue)
    )
}
```

### Import Screen Implementation

```swift
struct ImportView: View {
    @State private var viewModel = ImportViewModel()

    var body: some View {
        VStack {
            // Import type selector
            Picker("Import Type", selection: $viewModel.importType) {
                Text("Assets").tag(ImportType.assets)
                Text("Cash Flows").tag(ImportType.cashFlows)
            }
            .pickerStyle(.segmented)

            // File drop zone
            FileDropZone(url: $viewModel.selectedFile)

            // Configuration (date, platform, category)
            if viewModel.selectedFile != nil {
                ImportConfigurationView(viewModel: viewModel)
                ImportPreviewTable(viewModel: viewModel)
                ImportValidationSummary(viewModel: viewModel)
            }

            // Import button
            Button("Import") { viewModel.executeImport() }
                .disabled(viewModel.isImportDisabled)
        }
    }
}
```

### Reusable Components

**CurrencyText**: Use `Decimal.formatted(currency:)` extension

```swift
Text(value.formatted(currency: settings.displayCurrency))
    .font(.title2)
    .fontWeight(.semibold)
```

**PercentageText**: Color-coded percentage display

```swift
Text(percentage.formattedPercentage())
    .foregroundColor(percentage >= 0 ? .green : .red)
```

**MetricCard**: Card container for dashboard metrics

```swift
VStack(alignment: .leading, spacing: 8) {
    HStack {
        Text("Total Portfolio Value")
            .font(.subheadline)
            .foregroundColor(.secondary)
        Button(action: { showTooltip.toggle() }) {
            Image(systemName: "info.circle")
        }
    }
    Text(value.formatted(currency: "USD"))
        .font(.title)
        .fontWeight(.bold)
}
.padding()
.background(.regularMaterial)
.cornerRadius(10)
```

**AssetTableView** (`Views/Components/AssetTableView.swift`): Generic `AssetTableView<SecondColumn>` for displaying asset rows with Name, a configurable second column (e.g., "Category" or "Platform"), Original Value, and an optional Converted Value column. The Converted Value column is automatically hidden when no rows have converted values. Uses `DetailAssetRowData` as the shared row data type. Used by `PlatformDetailView` and `CategoryDetailView`.

**PlatformPickerField** (`Views/Components/PlatformPickerField.swift`): Reusable `Picker` for selecting an existing platform or creating a new one inline. Uses a `Binding<String>` for the selected platform. Selecting the sentinel value `"__new__"` (tagged as "New Platform...") toggles to an inline `TextField` for entering a new platform name. Commit logic performs case-insensitive deduplication against the cached platform list.

**CategoryPickerField** (`Views/Components/CategoryPickerField.swift`): Reusable picker for selecting an existing `Category` or entering a new category name inline. Similar inline-creation pattern to `PlatformPickerField`; uses a `resolveCategory` closure to look up or create the `Category` model object.

**EditValuePopover** (`Views/Components/EditValuePopover.swift`): Small popover for editing a `Decimal` market value in place. Triggered by double-click or context menu on market value cells in `AssetDetailView` and `SnapshotDetailView`.

### Animation and Transitions

All animations use shared constants from `AnimationConstants` (`Utilities/AnimationConstants.swift`), which automatically respect the Reduce Motion accessibility setting by falling back to near-instant durations.

**Available animations:**

| Constant       | Duration | Curve     | Usage                                                  |
| -------------- | -------- | --------- | ------------------------------------------------------ |
| `.standard`    | 0.25s    | easeOut   | Empty↔content transitions, conditional field show/hide |
| `.list`        | 0.2s     | easeOut   | List row reordering (`.onMove`)                        |
| `.chart`       | 0.25s    | easeInOut | Chart time range changes, pie chart cross-fade         |
| `.numericText` | 0.2s     | easeInOut | Dashboard period picker value changes                  |

**Animation patterns:**

- **Empty state transitions**: Views using ViewModel-based loading (`.onAppear`) must NOT use `.animation(_:value:)` — it animates the initial data load, causing a flash of the empty state. Do NOT add `.transition(.opacity)` to empty/content branches either — the transition is unnecessary and may cause jitter on navigation. The `withAnimation` in user-action code paths (e.g., `onChange`, delete handlers) smoothly updates list content; the empty↔content switch itself should be instant. A view may use `@Query` to invalidate a throwing ViewModel load, but it must render the ViewModel's loaded collection so query failures cannot display a false empty state.
- **Chart data cross-fade**: When switching between datasets (e.g., pie chart snapshot picker), use `.id(selectedValue)` + `.transition(.opacity)` on the chart content with `.animation()` on the parent container. This produces a clean dissolve instead of morphing artifacts.
- **Lock screen**: Only the unlock transition animates (security constraint — lock must appear instantly).
- **Numeric text**: Use `.contentTransition(.numericText())` for metric values that change in place.

______________________________________________________________________

## Development Workflow

### Before Building a Screen

1. Define the screen's purpose in one sentence
1. Identify which models/queries are needed
1. Choose container (List, Form, ScrollView, or custom layout)
1. Plan navigation (how users arrive and leave)

### While Building

1. Use Xcode Previews for rapid iteration
1. Test with realistic data and edge cases
1. Check light and dark mode
1. Verify Dynamic Type scaling

### After Implementation

1. Add empty states
1. Add loading states (if async)
1. Add error handling UI
1. Verify keyboard navigation
1. Test VoiceOver (basic navigation)

______________________________________________________________________

## Resources

### Apple Documentation

- [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- [SF Symbols App](https://developer.apple.com/sf-symbols/)
- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui/)
- [Swift Charts](https://developer.apple.com/documentation/charts)
- [Accessibility Guidelines](https://developer.apple.com/accessibility/)

### Specification Reference

- `SPEC.md` Sections 3, 4, 12 for detailed UI requirements

______________________________________________________________________

## Implementation Status

| View                           | Status      | Notes                                                                                                                                                                                                                                                     |
| ------------------------------ | ----------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ContentView (Navigation Shell) | Implemented | Full 7-section sidebar with SidebarSection enum, list-detail splits, discard confirmation, post-import navigation                                                                                                                                         |
| DashboardView                  | Implemented | Summary cards with `.helpWhenUnlocked()` tooltips, period performance (1M/3M/1Y), interactive charts, ContentUnavailableView, recent snapshots                                                                                                            |
| SnapshotListView               | Implemented | Throwing ViewModel-backed list with query invalidation, relative time bucket grouping (collapsible sections), New Snapshot sheet (NavigationStack), retryable persistence error state, ContentUnavailableView, Delete key shortcut                        |
| SnapshotDetailView             | Implemented | Asset breakdown, category allocation, cash flow CRUD, edit popovers, delete confirmation                                                                                                                                                                  |
| AssetListView                  | Implemented | Platform/category grouping, selection binding, ContentUnavailableView, Delete key shortcut                                                                                                                                                                |
| AssetDetailView                | Implemented | Edit fields, interactive 250pt value history chart with time range selector and hover tooltips, converted value chart toggle, inline editing, delete validation                                                                                           |
| CategoryListView               | Implemented | Add sheet (NavigationStack), target allocation warning, delete validation, ContentUnavailableView, Delete key shortcut                                                                                                                                    |
| CategoryDetailView             | Implemented | Edit fields, value/allocation history charts with time range controls, delete validation                                                                                                                                                                  |
| PlatformListView               | Implemented | List-detail split with selection binding, rename popover, ContentUnavailableView, onChange reload after rename                                                                                                                                            |
| PlatformDetailView             | Implemented | Editable name, assets table (Name/Category/Original Value), value history chart with time range controls and hover tooltip                                                                                                                                |
| RebalancingView                | Implemented | Suggestions table, no-target section, uncategorized section, summary, ContentUnavailableView                                                                                                                                                              |
| ImportView                     | Implemented | Accepts ViewModel from ContentView for shared state observation                                                                                                                                                                                           |
| BulkEntryView                  | Implemented | Full-screen bulk value entry with platform-grouped table, per-platform CSV import, inline asset/platform creation, category picker for new assets, keyboard navigation, zero-value warnings, observation boundaries for asset/cash-flow/toolbar isolation |
| SettingsView                   | Implemented | Currency, date format, default platform; accessible via Cmd+, (Settings scene)                                                                                                                                                                            |
