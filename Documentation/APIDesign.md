# API and Integration Design

## Preface

**Purpose of this Document**

This document describes the design of internal service APIs and data format specifications for AssetFlow. As a **local-only application with no external API dependencies**, this document focuses exclusively on internal service interfaces, CSV import/export formats, and the backup/restore system.

**What This Document Covers**

- **Internal Service APIs**: Service layer interfaces for CSV parsing, calculations, backup/restore, and currency conversion
- **External API Integration**: Exchange rate API for currency conversion
- **CSV Import Format**: Asset CSV and Cash Flow CSV schemas, parsing rules, and validation
- **Backup Format**: ZIP archive structure, CSV serialization, and manifest specification
- **Error Handling**: Service-level error types and handling patterns

**What This Document Does NOT Cover**

- User interface design (see [UserInterfaceDesign.md](UserInterfaceDesign.md))
- Business logic calculations (see [BusinessLogic.md](BusinessLogic.md))
- Data model structure (see [DataModel.md](DataModel.md))

**Design Philosophy**

- **Local-First**: Data stored locally; network used only for exchange rate fetching (optional, graceful degradation)
- **Standard Formats**: CSV for import/export, ZIP for backup archives
- **Deterministic**: All operations produce the same output for the same input
- **Fail-Safe**: Validation before execution; rejected operations leave no partial state

**Related Documentation**

- [Architecture.md](Architecture.md) - MVVM layers and service patterns
- [BusinessLogic.md](BusinessLogic.md) - Calculation formulas and business rules
- [DataModel.md](DataModel.md) - Data structures and relationships

______________________________________________________________________

## Internal Service APIs

### CSVParsingService

**Purpose**: Parse CSV files according to the asset and cash flow schemas defined in SPEC Section 4.2.

```swift
enum CSVParsingService {
    /// Parse asset CSV data into structured rows
    static func parseAssetCSV(
        data: Data,
        importPlatform: String?
    ) -> CSVParseResult<AssetCSVRow>

    /// Parse asset CSV using a user-provided column mapping (skips header validation)
    static func parseAssetCSV(
        data: Data,
        mapping: CSVColumnMapping,
        importPlatform: String?
    ) -> CSVParseResult<AssetCSVRow>

    /// Parse cash flow CSV data into structured rows
    static func parseCashFlowCSV(data: Data) -> CSVParseResult<CashFlowCSVRow>

    /// Parse cash flow CSV using a user-provided column mapping
    static func parseCashFlowCSV(data: Data, mapping: CSVColumnMapping) -> CSVParseResult<CashFlowCSVRow>

    /// Extract header names from the first line of CSV data
    static func extractHeaders(from data: Data) -> [String]

    /// Extract first N data rows as raw string arrays (for sample preview)
    static func extractSampleRows(from data: Data, count: Int = 3) -> [[String]]

    /// Auto-detect column mapping by case-insensitive header matching
    static func autoDetectMapping(headers: [String], schema: CSVColumnSchema) -> CSVAutoDetectResult
}

struct CSVParseResult<T> {
    let rows: [T]
    let errors: [CSVError]
    let warnings: [CSVWarning]

    var hasErrors: Bool
    var isValid: Bool
}

struct AssetCSVRow {
    let assetName: String
    let marketValue: Decimal
    let platform: String  // Resolved via platform handling rules
    let currency: String  // From optional Currency column (empty if absent)
}

struct CashFlowCSVRow {
    let description: String  // Maps to CashFlowOperation.cashFlowDescription in the model
    let amount: Decimal
    let currency: String  // From optional Currency column (empty if absent)
}

/// Canonical column identifiers for CSV mapping
enum CanonicalColumn: String, CaseIterable, Identifiable {
    case assetName = "Asset Name"
    case marketValue = "Market Value"
    case platform = "Platform"
    case currency = "Currency"
    case description = "Description"
    case amount = "Amount"
}

/// Defines required/optional columns for a CSV schema
enum CSVColumnSchema: CaseIterable {
    case asset     // required: assetName, marketValue; optional: platform, currency
    case cashFlow  // required: description, amount; optional: currency
}

/// A confirmed mapping from canonical columns to CSV column indices
struct CSVColumnMapping {
    let schema: CSVColumnSchema
    let columnMap: [CanonicalColumn: Int]
    let rawHeaders: [String]
}

/// Result of auto-detection attempt
enum CSVAutoDetectResult {
    case matched(CSVColumnMapping)
    case needsUserMapping(rawHeaders: [String], partialMap: [CanonicalColumn: Int])
}
```

**Note**: `CashFlowCSVRow.description` represents the "Description" column from the CSV file. When creating `CashFlowOperation` entities, this value is assigned to the `cashFlowDescription` property (not `description`) to avoid conflicts with Swift's built-in `CustomStringConvertible` protocol.

**Parsing Rules**:

- Encoding: UTF-8 (with BOM tolerance)
- Delimiter: comma only
- Number parsing: strip whitespace, currency symbols ($), thousand separators (commas in numbers), parse as `Decimal`
- Empty rows: silently skipped
- Header row: required as first row

**Error and Warning Types**:

```swift
struct CSVError: Error, Equatable {
    let row: Int
    let column: String?
    let message: String
}

struct CSVWarning: Equatable {
    let row: Int
    let column: String?
    let message: String
}
```

Methods do not throw — errors are embedded in the returned `CSVParseResult`. Check `result.hasErrors` or inspect `result.errors` after parsing.

______________________________________________________________________

### Duplicate Detection

**Purpose**: Detect duplicates within a CSV and between CSV data and existing snapshot records.

**Implementation**: AssetFlow handles duplicate detection in two layers:

1. **CSV-Internal Duplicates** (handled by `CSVParsingService`):

   - Detected during CSV parsing
   - Asset duplicates: Same (name, platform) within the CSV file (normalized: trim whitespace, collapse spaces, case-insensitive)
   - Cash flow duplicates: Same description within the CSV file (case-insensitive)
   - Returns parsing errors with row numbers for duplicates found

1. **CSV-vs-Snapshot Duplicates** (handled by `ImportViewModel`):

   - Detected when loading preview in import workflow
   - Compares parsed CSV rows against existing snapshot data
   - Asset conflicts: CSV row matches an asset already in the target snapshot
   - Cash flow conflicts: CSV row description matches a cash flow operation already in the target snapshot
   - Surfaces conflicts in the import preview UI for user resolution

**Asset Duplicate Detection**: Two records share the same (Asset Name, Platform) identity using normalized comparison (trim whitespace, collapse spaces, case-insensitive).

**Cash Flow Duplicate Detection**: Two records share the same Description (case-insensitive comparison).

______________________________________________________________________

### CalculationService

**Purpose**: Unified calculation engine for all financial metrics. All methods are pure functions operating on `Decimal` values.

**File**: `AssetFlow/Services/CalculationService.swift`

```swift
enum CalculationService {
    /// Calculate simple growth rate between two values (SPEC Section 10.3)
    /// Formula: (endValue - beginValue) / beginValue
    /// - Returns: Growth rate as a decimal (e.g., 0.10 for 10%), or nil if
    ///   beginning value is zero or negative
    static func growthRate(
        beginValue: Decimal,
        endValue: Decimal
    ) -> Decimal?

    /// Calculate Modified Dietz return (SPEC Section 10.4)
    /// Formula: R = (EMV - BMV - CF) / (BMV + sum(wi * CFi))
    /// Where wi = (totalDays - daysSinceStart) / totalDays
    /// - Parameters:
    ///   - beginValue: Beginning portfolio value (BMV)
    ///   - endValue: Ending portfolio value (EMV)
    ///   - cashFlows: Array of (amount, daysSinceStart) tuples for intermediate cash flows
    ///   - totalDays: Total calendar days in the period
    /// - Returns: Modified Dietz return as a decimal, or nil if denominator is <= 0
    ///   or beginning value is zero/negative
    static func modifiedDietzReturn(
        beginValue: Decimal,
        endValue: Decimal,
        cashFlows: [(amount: Decimal, daysSinceStart: Int)],
        totalDays: Int
    ) -> Decimal?

    /// Calculate cumulative time-weighted return by chaining period returns (SPEC Section 10.5)
    /// Formula: TWR = (1 + r1) * (1 + r2) * ... * (1 + rn) - 1
    /// - Parameter periodReturns: Array of Modified Dietz returns for consecutive periods
    /// - Returns: Cumulative TWR as a decimal
    static func cumulativeTWR(
        periodReturns: [Decimal]
    ) -> Decimal

    /// Calculate compound annual growth rate (SPEC Section 10.6)
    /// Formula: CAGR = (endValue / beginValue) ^ (1 / years) - 1
    /// - Parameters:
    ///   - beginValue: Beginning portfolio value
    ///   - endValue: Ending portfolio value
    ///   - years: Number of years (can be fractional)
    /// - Returns: CAGR as a decimal, or nil if beginning value is zero/negative
    ///   or years is zero/negative
    static func cagr(
        beginValue: Decimal,
        endValue: Decimal,
        years: Double
    ) -> Decimal?

    /// Calculate category allocation percentage (SPEC Section 10.2)
    /// Formula: categoryValue / totalValue * 100
    /// - Returns: Allocation percentage, or 0 if total value is zero
    static func categoryAllocation(
        categoryValue: Decimal,
        totalValue: Decimal
    ) -> Decimal
}
```

### RebalancingCalculator

**Purpose**: Computes rebalancing adjustments for portfolio allocation.

**File**: `AssetFlow/Services/RebalancingCalculator.swift`

```swift
struct CategoryAllocation {
    let name: String
    let currentValue: Decimal
    let targetPercentage: Decimal?
}

enum RebalancingActionType {
    case buy
    case sell
    case noAction
}

struct RebalancingAction {
    let categoryName: String
    let currentValue: Decimal
    let currentPercentage: Decimal
    let targetPercentage: Decimal
    let adjustmentAmount: Decimal
    let action: RebalancingActionType
}

enum RebalancingCalculator {
    /// Minimum adjustment threshold — adjustments under $1 are classified as `.noAction` (SPEC 11.4)
    static let minimumThreshold: Decimal  // = 1

    /// Calculate rebalancing adjustments for all categories with target allocations
    /// - Parameters:
    ///   - categories: Current category allocations (categories without targets are skipped)
    ///   - totalValue: Total composite portfolio value
    /// - Returns: Array of RebalancingAction sorted by absolute adjustment magnitude (largest first),
    ///   or empty array if totalValue is zero
    static func calculateAdjustments(
        categories: [CategoryAllocation],
        totalValue: Decimal
    ) -> [RebalancingAction]
}
```

**Return Value Convention**: All calculation methods return `nil` (not throwing) when the result is N/A (insufficient data, division by zero, etc.). The ViewModel maps `nil` to the appropriate display text ("N/A", "Cannot calculate", etc.).

______________________________________________________________________

### BackupService

**Purpose**: Export all application data to a ZIP archive and restore from a backup archive.

**Note**: BackupService requires `@MainActor` because it accepts `ModelContext`, which is `@MainActor`-isolated. This is an exception to the general service layer principle that services are not `@MainActor`.

```swift
@MainActor
enum BackupService {
    /// Export all data to a ZIP archive at the specified URL
    static func exportBackup(
        to url: URL,
        modelContext: ModelContext,
        settingsService: SettingsService
    ) throws

    /// Validate a backup archive without modifying data
    static func validateBackup(
        at url: URL
    ) throws -> BackupManifest

    /// Restore all data from a backup archive (replaces ALL existing data)
    static func restoreFromBackup(
        at url: URL,
        modelContext: ModelContext,
        settingsService: SettingsService
    ) throws
}

struct BackupManifest: Codable {
    let formatVersion: Int
    let exportTimestamp: String  // ISO 8601
    let appVersion: String
}
```

**File Organization**: The BackupService implementation is split across extension files: `BackupService+Export.swift` (CSV writing and export helpers), `BackupService+Parsing.swift` (typed loading and file validation), `BackupService+EntityParsing.swift` and `BackupService+SupplementalParsing.swift` (typed entity validation), `BackupService+ParsingSupport.swift` (strict scalar parsing and validation helpers), `BackupService+GraphValidation.swift` (cross-file relationship validation), `BackupCSVParser.swift` (record-aware CSV parsing), `BackupService+Restore.swift` (typed insertion and deletion), and `BackupService+Validation.swift` (validation entry point and ZIP operations).

**Export Format**: ZIP archive containing:

- `manifest.json` -- format version (currently 3), export timestamp, app version
- `categories.csv` -- all Category records (v2+ adds `displayOrder` column; v1 backups without it are supported on restore with default `displayOrder = 0`)
- `assets.csv` -- all Asset records including `currency` column (v3+; v1/v2 backups without it restore an empty currency so display-currency inheritance remains active)
- `snapshots.csv` -- all Snapshot records
- `snapshot_asset_values.csv` -- all SnapshotAssetValue records
- `cash_flow_operations.csv` -- all CashFlowOperation records including `currency` column (v3+; v1/v2 backups without it restore an empty currency so display-currency inheritance remains active)
- `exchange_rates.csv` -- all ExchangeRate records (optional; absent in v2 backups). Columns: `snapshotID`, `baseCurrency`, `fetchDate`, `isFallback`, `ratesJSON` (base64-encoded JSON)
- `settings.csv` -- user preferences with columns: `key`, `value`. Keys: `displayCurrency` (e.g., "USD"), `dateFormat` (e.g., "abbreviated"), `defaultPlatform` (e.g., "" or "Interactive Brokers")

Format versions 1 through 3 contain only those three settings. Preferences not represented by the format, such as platform ordering and stale-asset visibility, remain unchanged during restore.

**ZIP Implementation**: Uses `/usr/bin/ditto` via `Process` for ZIP creation (`-c -k --sequesterRsrc`) and extraction (`-x -k`). No external dependencies required — `ditto` is built into macOS.

**CSV Serialization Rules**:

- Column headers match data model field names (see [DataModel.md](DataModel.md))
- UUID fields: standard UUID string format
- Decimal fields: full precision (no rounding)
- Date fields: ISO 8601 timestamps
- Optional/nullable fields: empty string for null
- Records follow RFC 4180 quoting, including escaped quotes, CRLF, embedded newlines, and trailing empty fields
- Size limits: 1 MiB for `manifest.json` and 128 MiB per CSV file
- These CSV files are internal to the backup format, not intended for user editing

**Supported Restore Versions**:

| Version | Categories                                | Assets                 | Cash flows             | Exchange rates |
| ------- | ----------------------------------------- | ---------------------- | ---------------------- | -------------- |
| 1       | 3 columns; `displayOrder` defaults to `0` | 4 columns; no currency | 4 columns; no currency | Not supported  |
| 2       | 4 columns                                 | 4 columns; no currency | 4 columns; no currency | Not supported  |
| 3       | 4 columns                                 | 5 columns              | 5 columns              | Optional       |

Headers must match the manifest version. Unsupported versions and mixed-version schemas are rejected.

**Restore Validation**:

Before modifying any data, the restore operation validates:

1. All expected CSV files are present, regular files, UTF-8 encoded, and within the documented size limits
1. The manifest version is supported and all headers match that exact version
1. Every logical CSV record has the required arity and valid UUID, date, decimal, integer, Boolean, base64, and JSON values
1. Required strings are nonempty and category target allocations are between 0 and 100
1. Entity IDs, normalized category/asset identities, normalized snapshot dates, snapshot/asset pairs, per-snapshot cash-flow descriptions, and per-snapshot exchange rates are unique
1. All foreign key references are valid across files:
   - Every `assetID` in `snapshot_asset_values.csv` exists in `assets.csv`
   - Every `snapshotID` in `snapshot_asset_values.csv` exists in `snapshots.csv`
   - Every `snapshotID` in `cash_flow_operations.csv` exists in `snapshots.csv`
   - Every `categoryID` in `assets.csv` references an existing Category or is null

Validation produces immutable typed transfer records. Raw CSV fields are never indexed or parsed by the mutation phase. If validation fails, the restore is rejected with detailed file, row, and column diagnostics. Semantic row issues are aggregated across files when parsing can continue; archive, file, encoding, and header failures may stop validation immediately. No data or settings are modified.

After validation, existing pending model-context changes are saved to establish a rollback point. Autosave is suspended while deletion and typed insertion run in a single `ModelContext.transaction`. Any deletion, insertion, or save failure rolls the context back to that point. Validated `UserDefaults` settings are applied only after the SwiftData transaction succeeds.

**Error Cases**:

```swift
enum BackupError: LocalizedError {
    case invalidArchive
    case missingFile(String)
    case invalidCSVHeaders(file: String, expected: [String], got: [String])
    case invalidForeignKey(file: String, column: String, value: String)
    case unsupportedFormatVersion(Int)
    case validationFailed([BackupValidationIssue])
    case restoreFailed(String)
    case corruptedData(String)
}
```

______________________________________________________________________

### SettingsService

**Purpose**: Manage app-wide user preferences with `@Observable` reactivity.

SettingsService is an `@Observable @MainActor class` with a shared singleton and support for test isolation via `createForTesting()`. Properties use `didSet` to persist to UserDefaults immediately:

```swift
@Observable
@MainActor
class SettingsService {
    static let shared = SettingsService()

    var mainCurrency: String       // Default: "USD"
    var dateFormat: DateFormatStyle // Default: .abbreviated
    var defaultPlatform: String    // Default: ""
    var platformOrder: [String]    // Default: []

    static func createForTesting() -> SettingsService
}
```

**DateFormatStyle**: A `String`-backed `CaseIterable` enum with cases `.numeric`, `.abbreviated`, `.long`, `.complete`. Maps to `Date.FormatStyle.DateStyle` for rendering and provides `localizedName` and `preview(for:)`.

**Usage in ViewModels**:

```swift
let service = settingsService ?? SettingsService.shared
self.selectedCurrency = service.mainCurrency
```

Changes are applied immediately via `didSet` and persisted to UserDefaults.

______________________________________________________________________

### ExchangeRateService

**Purpose**: Fetch and cache date-specific exchange rates needed to convert snapshot values into the configured display currency.

`fetchRates(for:baseCurrency:)` formats dates with Gregorian calendar components, requires the API response's `date` to match the requested date, validates a non-empty set of positive finite rates, and coalesces concurrent requests for the same date/base-currency key. Coalesced waiters are tracked independently: cancelling the last waiter cancels the network task, and every caller checks cancellation before a result can be cached. `fetchMissingRates(snapshots:displayCurrency:modelContext:)` treats a cached record as usable only when its base currency, Gregorian fetch date, and all required currencies match; otherwise it refreshes or replaces the record. It returns a status for each snapshot (`cached`, `fetched`, `failed`, `cancelled`, or `notNeeded`) so callers can expose incomplete conversion to users.

______________________________________________________________________

### CurrencyService

**Purpose**: Provides currency information (codes and names).

```swift
struct Currency: Identifiable, Hashable {
    let code: String   // e.g., "USD"
    let name: String   // e.g., "US Dollar"
    var id: String     // equals code
    var displayName: String  // e.g., "USD - US Dollar"
}

@Observable
@MainActor
class CurrencyService {
    static let shared = CurrencyService()

    private(set) var currencies: [Currency]

    /// Fetch full currency list from exchange rate API
    func loadFromAPI() async

    /// Find currency by code (case-insensitive)
    func currency(for code: String) -> Currency?
}
```

Initializes with a hardcoded fallback list (~30 common fiat + top crypto currencies). `loadFromAPI()` fetches the full list (~480 currencies) via `ExchangeRateService.fetchCurrencyList()` and replaces the list on success, keeping the fallback on failure.

______________________________________________________________________

### ExchangeRateService

**Purpose**: Fetch exchange rates from the `@fawazahmed0/currency-api` CDN.

```swift
final class ExchangeRateService {
    init(session: URLSession = .shared)

    /// Fetch exchange rates for a specific date and base currency
    func fetchRates(
        for date: Date,
        baseCurrency: String
    ) async throws -> [String: Double]

    /// Fetch the full currency list (code → name)
    func fetchCurrencyList() async throws -> [String: String]

    /// Batch-fetch missing exchange rates for snapshots that need conversion
    @MainActor
    func fetchMissingRates(
        snapshots: [Snapshot],
        displayCurrency: String,
        modelContext: ModelContext
    ) async
}
```

**API Details**:

- Rates URL: `https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@{YYYY-MM-DD}/v1/currencies/{base}.min.json`
- Currency list URL: `https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies.min.json`
- Free, no API key required
- Stateless — callers cache results in SwiftData via `ExchangeRate` model
- Accepts `URLSession` parameter for dependency injection in tests

**Batch Fetch (`fetchMissingRates`)**:

- Skips snapshots that already have an `ExchangeRate` or don't need conversion (all assets/cash flows use display currency)
- Fetches sequentially to avoid API hammering
- Silently continues on per-snapshot errors (one failure doesn't block others)
- Called on app launch (`ContentView.task`) and after backup restore (`SettingsView.performRestore()`)
- `@MainActor` because it accepts `ModelContext` for inserting `ExchangeRate` objects

**Error Cases**:

```swift
enum ExchangeRateError: LocalizedError {
    case networkUnavailable
    case invalidResponse
    case ratesNotFound
}
```

______________________________________________________________________

### CurrencyConversionService

**Purpose**: Stateless currency conversion logic used by ViewModels for portfolio totals, cash flows, and category values.

```swift
enum CurrencyConversionService {
    /// Convert a single value between currencies
    static func convert(
        value: Decimal, from: String, to: String,
        using exchangeRate: ExchangeRate?,
        forSnapshotDate snapshotDate: Date
    ) -> Decimal?

    /// Sum all asset values in display currency
    static func totalValue(
        for snapshot: Snapshot, displayCurrency: String,
        exchangeRate: ExchangeRate?
    ) -> Decimal

    /// Sum all cash flows in display currency
    static func netCashFlow(
        for snapshot: Snapshot, displayCurrency: String,
        exchangeRate: ExchangeRate?
    ) -> Decimal

    /// Group converted values by category name
    static func categoryValues(
        for snapshot: Snapshot, displayCurrency: String,
        exchangeRate: ExchangeRate?
    ) -> [String: Decimal]

    /// Check if conversion is possible between currencies
    static func canConvert(
        from: String, to: String,
        using exchangeRate: ExchangeRate?,
        forSnapshotDate snapshotDate: Date
    ) -> Bool
}
```

The snapshot date is required for every conversion check so that a rate from a different date cannot be used for historical data. When `exchangeRate` is nil, the required currency is missing, or the rate date does not match the snapshot, conversion is unavailable and the caller can present the original currency values instead. This ensures the app works offline without silently applying an incorrect rate.

______________________________________________________________________

### SnapshotSummaryService

**Purpose**: Shared snapshot fetch and aggregation helper used by ViewModels that need converted totals. Fetch helpers use bounded descriptors for latest, latest-prior, and date-specific snapshot lookups.

**File**: `AssetFlow/Services/SnapshotSummaryService.swift`

```swift
struct SnapshotSummary {
    let snapshot: Snapshot
    let date: Date
    let assetCount: Int
    let totalValue: Decimal
    let categoryValues: [String: Decimal]
    let platformValues: [String: Decimal]
}

@MainActor
enum SnapshotSummaryService {
    static func fetchSnapshots(modelContext: ModelContext) -> [Snapshot]
    static func fetchLatestSnapshot(modelContext: ModelContext) -> Snapshot?
    static func fetchSnapshot(on date: Date, modelContext: ModelContext) -> Snapshot?
    static func fetchLatestSnapshot(
        before date: Date,
        modelContext: ModelContext
    ) -> Snapshot?
    static func makeSummaries(
        for snapshots: [Snapshot],
        displayCurrency: String
    ) -> [SnapshotSummary]
    static func makeSummary(
        for snapshot: Snapshot,
        displayCurrency: String
    ) -> SnapshotSummary
}
```

**Usage**: List and workflow ViewModels use `fetchLatestSnapshot` / `fetchLatestSnapshot(before:)` when only one snapshot is needed. Dashboard, category detail, and platform detail use `makeSummaries` so total, category, and platform history values are computed in one converted pass per snapshot.

______________________________________________________________________

### ChartDataService

**Purpose**: Stateless service for chart data filtering by time range and Y-axis label abbreviation.

**File**: `AssetFlow/Services/ChartDataService.swift`

```swift
enum ChartTimeRange: String, CaseIterable, Identifiable {
    case oneWeek = "1W"
    case oneMonth = "1M"
    case threeMonths = "3M"
    case sixMonths = "6M"
    case oneYear = "1Y"
    case threeYears = "3Y"
    case fiveYears = "5Y"
    case all = "All"

    /// Returns the start date for this range relative to a reference date,
    /// or nil for `.all` (no filtering)
    func startDate(from referenceDate: Date) -> Date?
}

protocol ChartFilterable {
    var chartDate: Date { get }
}

enum ChartDataService {
    /// Filters chart data points by time range
    /// Uses the latest data point's date as reference, not Date.now
    static func filter<T: ChartFilterable>(_ items: [T], range: ChartTimeRange) -> [T]

    /// Rebases cumulative TWR data points so the first point in the array starts at 0%
    /// Use after filtering by time range to show period-specific returns
    /// Formula: (1 + C_i) / (1 + C_k) - 1, where C_k is the first point's cumulative value
    static func rebasedTWR(_ points: [DashboardDataPoint]) -> [DashboardDataPoint]

    /// Returns abbreviated string for large numeric values
    /// Examples: 3,000,000,000 → "3B", 2,000,000 → "2M", 5,000 → "5K"
    static func abbreviatedLabel(for value: Double) -> String
}
```

**Usage**: Chart views use `ChartDataService.filter()` to apply time range selection before rendering. `ChartFilterable` protocol is conformed to by all chart data point types (`DashboardDataPoint`, `CategoryValueHistoryEntry`, `CategoryAllocationHistoryEntry`, `PlatformValueHistoryEntry`, `AssetValueHistoryEntry`).

**Axis Labels**: Y-axis labels use `abbreviatedLabel(for:)` to format large values (K/M/B) for readability in compact chart layouts.

______________________________________________________________________

## CSV Import Format Specification

### Asset CSV

**Required columns** (exact header names):

| Column         | Description                      |
| -------------- | -------------------------------- |
| `Asset Name`   | Name of the asset                |
| `Market Value` | Current market value as a number |

**Optional columns**:

| Column     | Description                                                          |
| ---------- | -------------------------------------------------------------------- |
| `Platform` | Platform/brokerage name (overridden by import-level platform if set) |
| `Currency` | Native currency code (e.g., "USD", "TWD"). Per-row override.         |

**Sample**:

```csv
Asset Name,Market Value,Platform,Currency
AAPL,15000,Interactive Brokers,USD
TSMC,500000,Fubon,TWD
Bitcoin,5000,Coinbase,USD
Savings Account,20000,Chase Bank,USD
```

### Cash Flow CSV

**Required columns** (exact header names):

| Column        | Description                           |
| ------------- | ------------------------------------- |
| `Description` | Description of the cash flow          |
| `Amount`      | Positive = inflow, negative = outflow |

**Optional columns**:

| Column     | Description                                                  |
| ---------- | ------------------------------------------------------------ |
| `Currency` | Native currency code (e.g., "USD", "TWD"). Per-row override. |

**Sample**:

```csv
Description,Amount,Currency
Salary deposit,50000,TWD
Emergency fund transfer,-10000,USD
Dividend reinvestment,1500,USD
```

### Column Mapping

Column mapping is deferred to a future version. For v1, CSV files must use the exact column names specified above. The app must display the expected schema and provide downloadable sample CSVs.

______________________________________________________________________

## Error Handling Patterns

### Service Error Strategy

- Services throw typed errors (enums conforming to `LocalizedError`)
- ViewModels catch errors and map to user-facing messages
- All errors include context (which file, which row, which field)

### User-Facing Error Display

- Import errors: Inline in the import preview (per-row indicators)
- Backup/restore errors: Alert dialog with detailed error description
- Calculation errors: "N/A" or "Cannot calculate" inline text

### Developer Logging

- Log errors with `os.log` (not `print()`)
- Include context (which service, which operation)
- No sensitive data in logs (no financial values)

______________________________________________________________________

## Build Phase: Commit Hash Injection

A `PBXShellScriptBuildPhase` named **"Inject Git Commit"** runs after the Resources phase on every build (not deploy-only). It writes the current git short commit hash into the built product's `Info.plist` under the `AppCommit` key:

```bash
#!/bin/bash
set -e
COMMIT=$(git -C "$SRCROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")
if [ -n "$(git -C "$SRCROOT" status --porcelain 2>/dev/null)" ]; then
  COMMIT="${COMMIT}-dev"
fi
/usr/libexec/PlistBuddy -c "Set :AppCommit $COMMIT" "$BUILT_PRODUCTS_DIR/$INFOPLIST_PATH"
```

**Key details:**

- The source `AssetFlow/Info.plist` contains `AppCommit = "unknown"` as a committed placeholder. The script only overwrites the **built** copy.
- A `-dev` suffix is appended when the working tree is dirty, making development builds visually distinguishable.
- `ENABLE_USER_SCRIPT_SANDBOXING = NO` is set in the target-level build settings (both Debug and Release) to allow the script to invoke `git` and `/usr/libexec/PlistBuddy`.
- `Constants.AppInfo.commit` reads this value at runtime via `Bundle.main.infoDictionary?["AppCommit"]`.

______________________________________________________________________

## Explicit Non-Goals (v1)

The following are NOT implemented:

- Real-time market price fetching
- Brokerage API integration
- Cloud sync / iCloud integration
- Column mapping for CSV import
- Data export for reporting (CSV, PDF) -- backup/restore IS supported
- Webhooks or push notifications

______________________________________________________________________

## References

- [Architecture.md](Architecture.md) - Service layer design
- [BusinessLogic.md](BusinessLogic.md) - Calculation formulas
- [DataModel.md](DataModel.md) - Entity definitions for CSV serialization
- Specification: `SPEC.md` Sections 3.10, 4, 7, 13, 14, 15
