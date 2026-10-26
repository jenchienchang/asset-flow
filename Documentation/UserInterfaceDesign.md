# User Interface Design

AssetFlow uses a macOS sidebar to move between dated portfolio snapshots, asset and category details, rebalancing, and CSV import. This document describes the visible controls and interaction states. [`SPEC.md`](SPEC.md) owns product requirements, [`BusinessLogic.md`](BusinessLogic.md) owns calculations and availability rules, [`APIDesign.md`](APIDesign.md) owns CSV and backup formats, and [`SecurityAndPrivacy.md`](SecurityAndPrivacy.md) owns app-lock protections and limits.

## Navigation and Windows

The sidebar shows Dashboard, Snapshots, Assets, Categories, Platforms, Rebalancing, New Snapshot, and Import CSV. Choosing New Snapshot opens the date-and-starting-point sheet; choosing Bulk Entry there then fills the content pane with its draft. Dashboard, Rebalancing, and Import fill the content pane. Snapshots, Assets, Categories, and Platforms show a list beside the selected item's detail; an unselected list shows a prompt in the detail pane. Settings opens in a separate macOS Settings scene.

The main window has a 900 × 600 point minimum size, a hidden title bar, and a unified toolbar. The sidebar's ideal width is 220 points. The list-detail screens use a list and detail pane inside the main navigation content area.

Back and Forward toolbar buttons traverse sidebar and programmatic navigation history, including chart selections and post-import navigation. A new destination clears forward history. File > New Snapshot (Command-N) opens the snapshot date sheet; File > Import CSV (Command-I) opens Import. The commands and navigation buttons are disabled while locked. Help offers the version- and locale-aware AssetFlow User Guide and Report an Issue links.

After a successful restore, selected snapshots, assets, and categories are matched to live records by their stable IDs. A removed selection clears; a replacement instance recreates its detail editor so old in-memory form state does not survive the restore. Category navigation first resolves an unsaved editor draft as described under [Categories Screen](#categories-screen).

## Dashboard

The Dashboard presents the latest snapshot and portfolio-level history.

- The prominent Total Portfolio Value card shows one converted display-currency amount when all required asset rates are available. If conversion is incomplete, it shows separate native-currency totals and explains the missing rates; it does not add unlike currencies.
- Secondary cards show the latest snapshot date, asset count, Cumulative TWR (All Time), and CAGR. The 1M, 3M, and 1Y controls on Growth Rate and Return Rate select independent periods; available rates show the actual covered dates. Insufficient history shows "N/A". Metric help explains the measures and their snapshot and cash-flow assumptions.
- The first chart row contains category allocation at a selected snapshot date and portfolio value history. The second contains cumulative TWR and category value history. Chart interactions are specified under [Charts and Historical Views](#charts-and-historical-views).
- Recent Snapshots shows up to five newest entries with date, asset count, and a converted total or separate native amounts. A row opens snapshot detail; View All opens Snapshots.

Conversion-dependent cards and charts retain their place in the layout but show an unavailable message over obscured content when their required rates are missing. Historical messages identify affected snapshot dates. A missing cash-flow rate can make return metrics unavailable while an asset-only total remains available; a missing asset rate can affect value charts independently. A failed data read shows a retryable error; a successfully loaded portfolio without snapshots shows the welcome state and an Import your first CSV action.

## Snapshots Screen

The list orders snapshots newest first in collapsible relative-date groups. Each row identifies its date, total, included platforms, and asset count. A failed list read shows Unable to load data with Retry; an empty successful read offers New Snapshot and Import CSV.

### Create and inspect

New Snapshot opens a date sheet with future dates disabled. The user chooses Bulk Entry (the default) or an empty snapshot. A date already used by a snapshot produces a validation error and does not silently replace that snapshot. Cancelling the sheet leaves the prior selection and any category editor that remained visible in place. [Bulk Entry](#bulk-entry) covers its draft.

Snapshot detail groups asset rows by platform and asset name. Each row shows the recorded market value in its asset currency; a differing currency can also show an approximate converted amount. The screen includes category allocation, cash-flow operations, per-currency net cash flow, and exchange rates used by the snapshot. A converted total or allocation is marked unavailable when required rates are missing. The total and net cash flow then appear as separate native-currency amounts where available, without a display-currency label on a mixed sum. Multi-currency snapshots identify unavailable rates; the app may fetch applicable rates after creation, restore, or display-currency changes.

Users can select an existing asset or create one when adding a value. Existing asset identity and assignments are inherited, and an asset already present in the snapshot is rejected. New assets take a name, platform, category, and currency. The row context menu's Edit Value action opens a value-edit popover; Save commits a valid amount and Cancel leaves the value unchanged. Cash-flow actions add, edit, and remove operations. The Remove from Snapshot action removes the recorded value without a separate confirmation and leaves the asset record intact. Deleting a snapshot requires confirmation and states that its asset values and cash flows will be removed. [`BusinessLogic.md`](BusinessLogic.md) defines snapshot membership and value rules.

## Assets Screen

The list groups assets by platform or category through a segmented control and sorts names within each group. "(No Platform)" and "(Uncategorized)" groups appear last. Each row shows the latest recorded value where one exists. An asset absent from the latest snapshot is **stale**; a recorded zero is present and is not stale. The Hide Stale Assets toolbar toggle is on by default and persists across sessions. It filters this list only. If records exist but all are hidden, "All Assets Are Stale" explains the filter; if there are no asset records, the ordinary No Assets state appears. A failed read instead shows Retry.

Asset detail shows name, platform, category, and native currency alongside a value-history chart and newest-first table. Name commits on Return; the currency picker saves through its selection binding; platform and category pickers commit through their own selection or inline-creation actions. Validation errors remain visible if a save fails. A rename updates the one asset record used across snapshots. Duplicate asset identity uses the normalized name and platform rules in [`BusinessLogic.md`](BusinessLogic.md).

When native and display currencies differ, the history table includes a Converted Value column independently of the chart mode; an unavailable conversion is an em dash. A currency-code control switches the chart between native and converted presentation. The chart and table show only recorded snapshot entries, so a missing entry is not drawn as zero. Deletion is blocked while the asset has values in any snapshot, with an explanation of how to remove those values first. Editing a recorded value uses the same Save/Cancel popover pattern as snapshot detail.

In converted mode, only entries with usable rates are plotted. When some converted points remain, unavailable dates break the line and have dashed markers. A compact warning shows the number of affected dates and opens a scrollable date list; the popover closes when the app locks. A selected period with no converted points shows an unavailable message. Hover shows no converted value for a missing-rate date, while native mode plots every recorded amount.

## Categories Screen

The list follows the user's saved order and supports drag reordering. Rows show the category name, configured percentage or minimum, current portfolio share and value, feasible effective share when available, asset count, and goal status. Current and effective percentages are shares of the **whole portfolio**; the configured percentage is a preference for the available allocation pool. A single warning indicator covers a significant effective-target deviation or a positive minimum shortfall. Minimum-only surplus remains protected and does not itself produce a sell warning. A no-goal category has no effective target. An infeasible plan, unavailable conversion, or zero portfolio total shows an em dash for an unavailable effective share; a separately determinable shortfall may still warn. No Categories offers Create Category; a failed read shows Retry instead.

Category detail contains an editable name, optional percentage target, and independently enabled minimum amount and currency. Minimum amount and currency have separate labeled rows. Save Changes commits the form together; Revert restores saved fields. Return from a text field and Command-S can save; Save and Revert are disabled when no edits exist. The saved-minimum assessment identifies its snapshot date and warns when unsaved edits have not entered that assessment.

Selecting another category, changing section, or opening New Snapshot while a draft exists offers Save Changes, Discard, and Cancel. Cancel keeps the editor and its draft. If the date sheet is later cancelled, the same editor remains available. A clean editor can adopt refreshed saved fields; an unsaved draft is preserved until the user resolves it. The detail is recreated when the selected SwiftData instance changes after restore.

The detail also lists assigned assets and shows value and allocation history. The value chart overlays the current minimum converted at each snapshot date; missing rates interrupt that comparison and are explained. Allocation history shows the actual whole-portfolio share without a pool-target reference line. A category with assigned assets cannot be deleted; eligible deletion requires confirmation. Selecting a slice in Dashboard's allocation chart opens the matching category detail. Goal feasibility and allocation rules belong in [`BusinessLogic.md`](BusinessLogic.md).

## Platforms Screen

Platforms are derived from nonempty asset platform names. The list follows saved user order; newly encountered names follow in name order. Dragging reorders the list. Rows show the platform name, asset count, and latest converted total when rates permit it; an unavailable total is shown as such. An asset without a platform belongs to the Assets screen's "(No Platform)" group. The No Platforms state explains how creating or importing assets creates platform names.

Platform detail shows its assets, total, value history, and an editable name. Rename commits on Return or through the row's quick-edit popover, validates case-insensitive uniqueness, and updates assets using that platform. The selection follows the new name. A platform disappears when no assets use its name; there is no independent platform record to delete. List and detail read failures show an error with Retry.

## Rebalancing Screen

Rebalancing uses the latest snapshot for a read-only preview. It displays a portfolio total, source snapshot date, calculation help, a category table, and Suggested Moves. Without a snapshot, the No Rebalancing Data state asks the user to add one. A failed read shows Retry. The preview never changes portfolio records. [`BusinessLogic.md`](BusinessLogic.md) defines protection, minimum funding, feasibility, and transfer calculations.

The table has these columns, in order: **Category**, **Current balance**, **Current %**, **Effective target balance**, **Effective target %**, **Change**, **Action**, and **Minimum**. Current and effective percentages use the whole portfolio as denominator. Configured percentages remain in category settings and contextual help. Rows are divided into Categories with Targets, No Target Set, and Uncategorized. The latter two retain protected holdings. Narrow windows can scroll the one-line columns horizontally.

Action cells use the localized Buy, Sell, Protected, Small adjustment, and No action states, as applicable. Buy and Sell use filled directional icons; Protected uses the filled minus-circle icon and a text label. Nonzero adjustments too small to round to a display unit remain distinguishable from zero. Invalid, infeasible, or conversion-unavailable plans show diagnostics and no actionable transfers. Suggested Moves funds minimum shortfalls before optional percentage adjustments and shows any unresolved residual.

### Rebalancing help and amount display

Category help shows the selected category's lettered inputs and formula result rows. Calculation details shows the aggregate portfolio total, protected funds, available allocation, and conditional minimum-fixed and remainder amounts, followed by concise rules. Minimum help shows its focused comparison, source snapshot date, and currency. Unavailable help explains the reason without presenting an invalid calculation. Popovers close or suppress help when locked.

Within each help table, a shared currency heading appears once when all monetary rows have the same intended currency, including unavailable monetary rows. The minimum comparison uses an Assessment heading. Mixed-currency rows retain each currency code; percentage rows do not determine the heading, and explanatory sentences retain their currency codes. Values align with tabular digits. A percentage suffix is read with its value by accessibility technology; its separate visual cell is decorative. Result rows are separated visually, and an approximate marker identifies a displayed formula result when its displayed inputs or result were rounded. Tables set a natural popover width; explanations wrap within the available screen width.

Amounts use the asset currency formatter's locale grouping and currency fraction precision. Actual zero displays as zero, unavailable values as an em dash, and a nonzero magnitude below one display unit as a bound such as `<0.01` with the applicable currency; tiny signed changes use localized Increase or Decrease wording. These are presentation rules: stored Decimal amounts and funding comparisons remain unrounded.

## Bulk Entry

Bulk Entry is a full-content draft for a new snapshot date. It seeds asset rows from the latest earlier snapshot and groups them by platform. Its toolbar shows the date, progress and validation information, Add Platform, and Save Snapshot. With no prior rows, an empty state offers Add Platform; a failed seed-data read shows Retry.

Each asset row has an Include control, name, category, currency, previous value, and editable new value. Existing asset identity fields are read-only; newly added rows can set them before saving. A previous value can be copied into the new field. Included rows without entered values become zero only after a pending-row confirmation; excluded rows are omitted. New names and duplicate identities are validated before saving. Add Platform starts a group with an editable asset row.

Each platform has an Import CSV action. A valid import fills matching draft rows; validation or parser failure leaves the prior CSV values intact and reports the outcome. Progress and Cancel appear in the importing platform's header if CSV preparation continues beyond a short delay. The indicator occupies the flexible gap between the filled/total count and Add Asset, so showing or hiding it does not add a row or move the header buttons. Cancel matches the neighboring buttons' control size; in a narrow gap, the status compacts to an accessible spinner and icon-only Cancel button. The Cash Flow Operations header uses the same placement for cash-flow CSV imports. Cancellation leaves rows and earlier feedback unchanged. The separate Cash Flow Operations section starts empty for each new snapshot. It supports manual rows and CSV import, inclusion controls, description, signed amount, currency, a per-currency net summary, and validation of descriptions and amounts. A valid replacement of CSV-sourced cash-flow rows occurs only after the new CSV passes validation.

Bulk Entry's asset and cash-flow CSV mapping previews leave plain data rows on the sheet surface and shade alternate rows with the system's table stripe color. Mapping controls and column headers keep their separate background.

Return moves focus through included value and amount fields; new rows focus their first editable field. Cash-flow descriptions move to their row's amount field before advancing. Asset-row accessibility labels identify the asset, platform, and updated, pending, or excluded state; cash-flow labels include description, amount, and included or excluded state. If source snapshots, assets, categories, or seed values change, a stale-data banner disables edits and Save and offers Discard Draft and Reload. Cancel remains available for a CSV load already in progress. Navigation away from an unsaved draft asks whether to discard it. No draft is silently overwritten. CSV syntax and matching rules belong in [`APIDesign.md`](APIDesign.md) and [`BusinessLogic.md`](BusinessLogic.md).

## Import Screen

Import offers an Assets/Cash Flows selector, a CSV drop zone and Browse button, and an expected-column hint for the selected type. The view does not provide a sample-download control. A selected file can be changed before commit. Progress and Cancel appear if loading continues beyond a short delay, while the prior preview remains until preparation completes; a cancelled task does not replace it.

When headers need mapping, a sheet shared with Bulk Entry shows every CSV data row and lets users map or skip each column. Headers and cells stay on one line without truncating text; columns fit their contents and mapping controls. The sheet grows with the table within available window space and adapts when the window changes size. Users can scroll in either direction when content exceeds that space, while mapping controls and headers remain visible as data rows scroll vertically. Recognized headers skip the sheet.

After file preparation, the screen shows the snapshot date, relevant asset platform and category controls, validation messages, a row preview, and Import. Asset imports can choose how selected platform or category values apply: All Rows overrides existing values; the other mode fills empty assignments. Leaving a category unselected retains existing assignments. Mixed input rows expose the applicable All Rows control.

For an asset import into a new snapshot, eligible platforms from the latest prior snapshot appear under an Enable copy-forward toggle. When enabled, per-platform selections show asset counts and source dates; selected platforms are copied into the new snapshot. Platforms already represented by included import rows are excluded.

Preview rows show effective values and row-level error or warning indicators for duplicates, reassignment, value, and currency issues; their explanations open beside the affected row. File-level errors appear in the validation summary. An error on an included row blocks Import; warnings remain visible for review. A matching nonzero value already in the selected snapshot is a conflict, while the existing zero-value placeholder exception may be filled. Successful import creates or appends to the selected-date snapshot and opens its detail. Navigating away with an uncommitted file asks for discard confirmation. [`APIDesign.md`](APIDesign.md) defines accepted columns and file parsing; [`BusinessLogic.md`](BusinessLogic.md) defines duplicate and category-application rules.

## Settings and App Lock

Settings opens with Command-Comma or AssetFlow > Settings. Preferences save when changed.

- **Display Currency** selects the currency used for converted portfolio values. Changing it recomputes affected displays using rates applicable to each snapshot; a required missing rate leaves that converted result unavailable. Recorded native amounts are unchanged.
- **Date Format** chooses numeric, abbreviated, long, or complete presentation. The default is abbreviated, formatted in the current locale.
- **Default Platform** pre-fills the import platform field and may be overridden; it starts empty.
- **Require Authentication** starts off. Enabling it first asks for system authentication. When Switching Apps and When Locked or Sleeping each offer Immediately, 1, 5, or 15 minutes, or Never. Setting both to Never turns the setting off; enabling it again resets both to Immediately. The app uses the macOS authentication dialog; available methods depend on device and system state, and no fixed fallback order is promised.
- **Data Management** exports to a user-selected ZIP file and confirms before restoring a backup that replaces existing data. It shows progress, cancellation, and a result or error. An archive creation failure shows a short final diagnostic when available and says when earlier details were omitted. A failed validation or replacement preserves existing portfolio data as described in [`APIDesign.md`](APIDesign.md). Backup protections and limits belong in [`SecurityAndPrivacy.md`](SecurityAndPrivacy.md).
- **About** presents selectable version, build, and commit metadata, developer, license, privacy text, and links to the source and User Guide. The About window presents the same identity metadata.

When locked, the main and Settings scenes place `LockScreenView` above their content, with an Unlock button and system authentication prompt when the app is active. The view uses a full-window system material background. Tooltip and hover content use lock-aware modifiers, and affected commands and controls are disabled; [`SecurityAndPrivacy.md`](SecurityAndPrivacy.md#app-lock-optional) describes the protection boundary and remaining interactive-verification needs. A failed or cancelled authentication leaves the app locked. Lock appearance should be immediate; the unlock transition may animate.

## Charts and Historical Views

The Dashboard pie chart selects a snapshot date, defaults to the latest, and shows category shares with a legend beside the pie whose columns adapt to the available width. Clicking a category or its legend entry opens that category, except Uncategorized, which has no category detail. The portfolio-value chart opens snapshot detail on click. The multi-category value chart lets users toggle categories in its legend and shows values for a hovered date, ordered by value with aligned currency numbers. The TWR chart has no click navigation. Category, platform, and asset details have their own historical charts and tooltips.

Line charts offer 1W, 1M, 3M, 6M, 1Y, 3Y, 5Y, and All. They start at All for a new view instance; a new selected detail recreates that detail's range state. Filtering is relative to the latest data point rather than the current day. A non-All TWR range rebases its first visible point to 0% unless that point's inception-based TWR is -100%; then rebasing is undefined and the filtered inception-based values remain unchanged. The all-time card remains inception-based. Chart axes abbreviate large values with K, M, and B. Hover marks should not shift the plot domain. [`ChartTimeRangeSelector.swift`](../AssetFlow/Views/Charts/ChartTimeRangeSelector.swift) and [`SingleSeriesLineChart.swift`](../AssetFlow/Views/Charts/SingleSeriesLineChart.swift) show the implemented controls and single-series interactions.

| Condition                                   | Presentation                                                                          |
| ------------------------------------------- | ------------------------------------------------------------------------------------- |
| Positive total entirely uncategorized       | One Uncategorized pie slice at 100%                                                   |
| No asset data for the selected pie snapshot | No asset data placeholder                                                             |
| One portfolio snapshot                      | One point without a connecting line                                                   |
| No points in selected range                 | No data for selected period                                                           |
| No categories or all-zero category history  | Category guidance or a no-data legend entry                                           |
| Fewer than two snapshots for TWR            | Insufficient data message                                                             |
| No calculable returns in range              | Cannot calculate returns message                                                      |
| Required historical exchange rate missing   | Explain the unavailable result or gap; do not label a mixed-currency sum as converted |

Currency-dependent charts show the unavailable overlay where their source status is incomplete. The overlay explains missing rates and replaces the chart's accessible content with its message. Hover tooltips use `.onHoverWhenUnlocked()` or `.onContinuousHoverWhenUnlocked()`; ordinary help uses `.helpWhenUnlocked()`. Chart appearance and controls should remain usable in light and dark mode and with Reduce Transparency.

## Shared States and Interaction Patterns

A successful load with no matching records is an empty state, commonly using `ContentUnavailableView` with a direct next action. A persistence read failure instead shows Unable to load data and Retry. Currency availability is separate from read failure: native amounts can remain visible while converted values, goals, or returns explain their own unavailable inputs. A stale draft is separate from an empty or failed load and requires explicit reload or resolution.

Quick value edits and platform rename use anchored popovers with Save and Cancel. Longer creation forms use sheets with a clear cancellation and commit action; the first useful field receives focus where implemented. Destructive snapshot, category, and restore actions require confirmation. The Delete key in supported lists follows the same screen-specific guard or confirmation as its visible delete action. Do not infer that every list, sheet, or popover has identical keyboard routing; verify native focus and VoiceOver behavior interactively.

## Visual Style, Localization, and Accessibility

The main window follows the system light or dark appearance. Dashboard's portfolio total uses a prominent system-adaptive surface; secondary cards use a quieter glass or material treatment that adapts to Reduce Transparency. Use system title, section, body, and caption roles to keep hierarchy clear. Align financial values with tabular digits. Monetary labels carry the relevant currency with locale grouping and currency fraction precision; percentages display two decimal places. Chart axes may abbreviate large values with K, M, and B.

Use semantic color for positive, negative, and neutral values, and distinct category colors in charts. Icons and words identify actions and warnings alongside color. The selected, empty, zero, unavailable, and invalid states need distinct text and accessible labels. English and Traditional Chinese (`zh-Hant`) UI strings use String Catalogs; dates follow the selected format and current locale.

Shared animations come from [`AnimationConstants.swift`](../AssetFlow/Utilities/AnimationConstants.swift) and respect Reduce Motion. User actions can animate list changes, chart changes, and numeric text. Avoid prescribing an empty/content transition on ViewModel initial loads; [`CodeStyle.md`](CodeStyle.md#animating-emptycontent-transitions) explains the flash this can cause. Locking exposes the covering view immediately.

Check chart labels and tooltips, popover and dialog reading order, focus after sheet presentation and dismissal, keyboard activation of list and chart actions, and visible focus indicators with VoiceOver and Full Keyboard Access. Check light and dark appearance, Reduce Transparency, Reduce Motion, and contrast interactively. Source-level labels, semantic colors, and render tests do not establish native event routing or a contrast rating by themselves.
