# AssetFlow Architecture

## Overview

AssetFlow is a macOS desktop application (macOS 15.0+) for snapshot-based portfolio management and asset allocation tracking. It is built with SwiftUI, SwiftData, and Swift Charts, following a local-first architecture with optional network access limited to exchange rate fetching.

The project uses the Swift 6 language mode and the Swift 6.4 compiler supplied by Xcode 27. The app target uses default MainActor isolation with approachable concurrency enabled. Pure value-only helpers that are used from nonisolated contexts are explicitly marked `nonisolated`; SwiftData models and model contexts remain on the main actor.

## Architecture Pattern

### MVVM (Model-View-ViewModel)

The application follows the MVVM architectural pattern to separate concerns and improve testability:

```
+--------------+
|     View     | <- SwiftUI Views (UI Layer)
+------+-------+
       | observes
       v
+--------------+
|  ViewModel   | <- Business Logic & State
+------+-------+
       | uses
       v
+--------------+
|    Model     | <- SwiftData Models (Data Layer)
+------+-------+
       |
       v
+--------------+
|   Services   | <- Stateless Calculations & Utilities
+--------------+
```

### Layer Responsibilities

#### View Layer (SwiftUI)

- **Purpose**: Presentation and user interaction
- **Location**: `AssetFlow/Views/`
- **Characteristics**:
  - Declarative UI with SwiftUI
  - Observes ViewModel state changes
  - Minimal business logic
  - macOS-optimized layouts (sidebar navigation, list-detail split)
  - Shared animation constants (`AnimationConstants`) with Reduce Motion support
  - Reusable components

**Example Structure**:

```swift
struct DashboardView: View {
    @State private var viewModel: DashboardViewModel

    var body: some View {
        // UI declaration
    }
}
```

#### ViewModel Layer

- **Purpose**: Business logic and state management
- **Location**: `AssetFlow/ViewModels/`
- **Characteristics**:
  - Uses `@Observable` macro for automatic change tracking
  - `@MainActor` isolation for UI thread safety
  - Coordinates between Views and Models/Services
  - Handles data transformation and validation
  - Form validation with real-time feedback

**ViewModels** (all 12 implemented and tested):

1. **DashboardViewModel**: Portfolio overview metrics, summary cards, chart data
1. **SnapshotListViewModel**: Snapshot listing, creation, deletion
1. **SnapshotDetailViewModel**: Snapshot detail, asset breakdown, cash flow management
1. **AssetListViewModel**: Asset listing, grouping (by platform or category)
1. **AssetDetailViewModel**: Asset value history, editing, deletion validation
1. **CategoryListViewModel**: Category listing, creation, deletion
1. **CategoryDetailViewModel**: Category detail, value and allocation history
1. **PlatformListViewModel**: Platform listing, rename operations
1. **PlatformDetailViewModel**: Platform detail and rename, assets on platform with latest values, platform value history across snapshots
1. **RebalancingViewModel**: Rebalancing calculations, current vs. target allocation
1. **ImportViewModel**: CSV parsing, validation, preview, import execution
1. **SettingsViewModel**: Display currency, date format, default platform

**Views** (all 14 implemented — navigation shell, all sections, all detail views):

1. **ContentView**: Full sidebar navigation with `SidebarSection` enum, list-detail splits, discard confirmation, post-import navigation
1. **DashboardView**: Summary cards, period performance (1M/3M/1Y), chart placeholders, recent snapshots
1. **SnapshotListView**: `@Query` live list, New Snapshot sheet
1. **SnapshotDetailView**: Asset breakdown, category allocation, cash flow CRUD
1. **AssetListView**: Platform/category grouping, selection binding
1. **AssetDetailView**: Edit fields, sparkline chart, value history, delete validation
1. **CategoryListView**: Add sheet, target allocation warning, delete validation
1. **CategoryDetailView**: Value/allocation history charts, delete validation
1. **PlatformListView**: Rename sheet, empty state
1. **PlatformDetailView**: Editable platform name field, asset table with latest values, value history chart across snapshots
1. **RebalancingView**: Suggestions table, no-target section, summary
1. **ImportView**: CSV import (accepts shared ViewModel from ContentView)
1. **SettingsView**: Currency, date format, default platform
1. **LockScreenView**: Full-window opaque overlay displayed when the app is locked; triggers `AuthenticationService` authentication via system `LAContext` dialog

**Example Structure**:

```swift
@Observable
@MainActor
class ImportViewModel {
    var importType: ImportType = .assets
    var selectedFile: URL?
    var snapshotDate: Date = .now
    var selectedPlatform: String?
    var selectedCategory: Category?
    var previewRows: [PreviewRow] = []
    var validationErrors: [ValidationError] = []
    var validationWarnings: [ValidationWarning] = []

    var isImportDisabled: Bool {
        !validationErrors.isEmpty || previewRows.isEmpty
    }

    func parseCSV(_ url: URL) { /* Parse and validate */ }
    func executeImport() { /* Create/update snapshot */ }
}
```

##### Automatic Data Reload

ViewModels that compute aggregate or currency-converted values use `withObservationTracking` to automatically re-trigger their load method when any `@Observable`/`@Model` property read during computation changes. This provides reactive updates for property mutations (e.g., display currency change, asset value edit, exchange rate update).

**Two complementary mechanisms:**

1. `withObservationTracking` — detects property changes on existing objects (currency change, value edit, exchange rate update)
1. `@Query` + `.onChange(of:)` in views — detects collection membership changes (new/deleted objects), which `modelContext.fetch()` inside `withObservationTracking` cannot track

**Applied to:** `DashboardViewModel`, `SnapshotDetailViewModel`, `SnapshotListViewModel`, `CategoryListViewModel`, `CategoryDetailViewModel`, `PlatformListViewModel`, `PlatformDetailViewModel`, `AssetListViewModel`, `AssetDetailViewModel`, `RebalancingViewModel`.

**Not applied to:** `ImportViewModel`, `BulkEntryViewModel`, `SettingsViewModel` (do not display converted aggregate values). `BulkEntryViewModel` uses `private(set)` rows with centralized mutation methods and a stored `toolbarStats` property maintained via O(1) delta updates instead.

##### Operation-Scoped Persistence Lookups

Multi-row CSV work uses short-lived lookup indexes in `Utilities/ModelResolutionLookup.swift`. `ImportViewModel` builds asset and snapshot-value indexes once per preview rebuild, validation pass, or import execution. `BulkEntryViewModel` builds asset and category indexes once per save only when new records require them. The indexes are updated immediately after inserting records, preserve first-match behavior for unexpected duplicate normalized identities, and are discarded when the operation finishes. The shared `ModelContext` resolution helpers remain available for isolated single-record operations and do not retain process-wide caches.

#### Model Layer (SwiftData)

- **Purpose**: Data structure and persistence
- **Location**: `AssetFlow/Models/`
- **Characteristics**:
  - SwiftData `@Model` classes
  - Business entities with relationships
  - Type-safe data structures
  - Computed properties for derived values
  - Schema versioning support

**Core Models**:

- `Category` - Asset categorization with target allocation
- `Asset` - Individual investments identified by (name, platform) with native currency
- `Snapshot` - Portfolio state at a specific date
- `SnapshotAssetValue` - Market value of an asset within a snapshot
- `CashFlowOperation` - External cash flow event associated with a snapshot
- `ExchangeRate` - Exchange rate data for currency conversion (1:1 with Snapshot)

See [DataModel.md](DataModel.md) for detailed model documentation.

#### Service Layer

- **Purpose**: Stateless calculations, data operations, and utility functions
- **Location**: `AssetFlow/Services/`
- **Characteristics**:
  - Business logic separated from models and ViewModels
  - NOT marked as `@MainActor` (pure functions where possible)
  - Minimal external network access (exchange rate fetching only)
  - Stateless calculations
  - Error handling and validation

**Services**:

1. **CalculationService** (`enum`): Unified calculation engine providing growth rate, Modified Dietz return, cumulative time-weighted return (TWR), compound annual growth rate (CAGR), and category allocation percentage calculations. All methods are pure functions operating on `Decimal` values.

1. **CSVParsingService** (`enum`): Parses asset CSV and cash flow CSV files according to the schemas defined in SPEC Section 4.2. Handles encoding (UTF-8 with BOM tolerance), number parsing (strip currency symbols, thousand separators), validation, and **within-CSV duplicate detection**. Returns structured results with error reporting.

1. **RebalancingCalculator** (`enum`): Computes target vs. current allocation differences and suggested buy/sell adjustment amounts for each category. Returns signed `Decimal` values (positive = buy, negative = sell).

1. **BackupService** (`@MainActor enum`): Exports all application data to a ZIP archive (via `/usr/bin/ditto`) containing CSV files and a manifest.json. Restore uses a two-phase pipeline: the complete archive is parsed into typed transfer records and validated without side effects, then the live SwiftData graph is replaced in one transaction. Settings are applied only after the database transaction succeeds. **Note**: BackupService requires `@MainActor` annotation because it accepts `ModelContext`, which is `@MainActor`-isolated. This is an exception to the general "services are not `@MainActor`" principle. BackupService is organized across focused extension files for export, typed parsing, scalar and graph validation, record-aware CSV parsing, transactional restore, and ZIP operations.

1. **SettingsService** (`@Observable @MainActor class`): Manages app-wide user preferences (display currency, date format, default platform) via UserDefaults. Observable for reactive UI updates when settings change.

1. **AuthenticationService** (`@Observable @MainActor class`): Manages optional app lock using macOS LocalAuthentication framework. Persists lock settings (enabled, re-lock timeout) via UserDefaults. Handles authentication via `LAContext.evaluatePolicy(.deviceOwnerAuthentication)` supporting Touch ID, Apple Watch, and system password fallback. Injectable `LAContext` factory for test isolation.

1. **CurrencyService** (`@Observable @MainActor class` with `static let shared` singleton): Provides currency information (codes, names, flag emojis). Loads from a hardcoded fallback list (~30 common currencies) on init, then can fetch the full list (~480 currencies) from the exchange rate API via `loadFromAPI()`.

1. **ExchangeRateService** (`final class`): Fetches exchange rates from the `@fawazahmed0/currency-api` CDN. Provides `fetchRates(for:baseCurrency:)`, `fetchCurrencyList()`, and `fetchMissingRates(snapshots:displayCurrency:modelContext:)` for batch-fetching missing rates across all snapshots. Date-specific requests are coalesced by date/base currency, with caller-aware cancellation and validation before cache mutation. Accepts a `URLSession` for testability. Throws `ExchangeRateError` on failure.

1. **CurrencyConversionService** (`enum`): Stateless conversion logic used by ViewModels. Provides date-validated `convert(value:from:to:using:forSnapshotDate:)` and `canConvert(from:to:using:forSnapshotDate:)`, plus `totalValue(for:displayCurrency:exchangeRate:)`, `netCashFlow(for:displayCurrency:exchangeRate:)`, and `categoryValues(for:displayCurrency:exchangeRate:)`. Conversion is unavailable when the exchange rate is missing, incomplete, or does not match the snapshot date; callers can then present native-currency values.

1. **SnapshotSummaryService** (`@MainActor enum`): Provides bounded snapshot fetch helpers (latest, latest prior, date lookup, sorted history) and one-pass converted snapshot summaries containing total value, asset count, category totals, and platform totals. ViewModels use this to avoid repeated full-table fetches and duplicate aggregate traversal logic.

**Duplicate Detection**: AssetFlow handles duplicate detection in two layers:

- **CSV-internal duplicates**: Detected by `CSVParsingService` during parsing (same name+platform within file, or same description within cash flow CSV)
- **CSV-vs-snapshot duplicates**: Detected by `ImportViewModel` when loading preview (checks CSV rows against existing snapshot data)

**Supporting Types**: `DateFormatStyle`, `BackupTypes`, `CSVParsingTypes` (result types), `SnapshotSummary` (converted snapshot aggregates), `ChartDataService` (chart data filtering and axis formatting). Domain error enums (`AssetError`, `CategoryError`, `PlatformError`) are in `Models/`.

**Design Principles**:

- Services perform pure calculations without requiring MainActor where possible
- Services that accept `ModelContext` are `@MainActor` and use bounded fetch descriptors when the caller only needs the latest, latest-prior, or date-specific snapshot
- Models remain simple data containers
- ViewModels coordinate between services and UI
- Testability: mock data can be passed to services without side effects
- All service data types (structs used as inputs/outputs, such as `CSVParseResult`, `RebalancingAction`) should conform to `Sendable` for Swift 6 strict concurrency compatibility
- Using `enum` for stateless services naturally avoids actor isolation issues

## Localization

AssetFlow uses Apple's **String Catalogs** (`.xcstrings`) with feature-scoped tables for organization:

- **View Layer**: String literals in SwiftUI (`Text()`, `Label()`, etc.) are auto-extracted into `Localizable.xcstrings` at build time. No manual wrapping needed.
- **ViewModel/Service Layer**: All user-facing strings use `String(localized:table:)` with feature-specific tables (e.g., `Snapshot`, `Asset`, `Category`, `Import`, `Services`).
- **Enum Display Names**: Enums with user-facing values have a `localizedName` computed property for UI display. The `rawValue` is reserved for SwiftData persistence and must never be shown to users.

## Data Flow

### Unidirectional Data Flow

```
User Action -> View -> ViewModel -> Service/Model -> SwiftData
                ^                                      |
                +-------- State Update <---------------+
```

1. **User Interaction**: User interacts with View
1. **Action Dispatch**: View calls ViewModel method
1. **Business Logic**: ViewModel processes request (may use Services)
1. **Data Operation**: Model updates SwiftData
1. **State Update**: Changes propagate back to ViewModel
1. **UI Refresh**: View automatically re-renders

### SwiftData Integration

- **Single ModelContainer**: Shared container injected at app root in `AssetFlowApp.swift`
- **Automatic Persistence**: No manual `save()` calls required
- **SwiftUI Integration**: `@Query` property wrapper for reactive data binding
- **Schema Registration**: All models registered in `SchemaV1` (`Models/SchemaVersioning.swift`)

```swift
@main
struct AssetFlowApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema(versionedSchema: SchemaV1.self)
        // Container configuration
    }()
}
```

## Platform Support

### macOS Only (v1)

**Platform**: macOS 15.0+

- Full-featured desktop application
- Sidebar navigation with list-detail split views
- Minimum window size: 900 x 600 points
- Collapsible sidebar (default width: 220 points)
- Supports system appearance (light and dark mode)
- Menu bar integration (Settings via Cmd+,)
- Keyboard shortcuts for common actions

**No iOS or iPadOS support** in v1. No platform-specific compiler directives are needed.

## Dependency Management

### Current Dependencies

- **SwiftData**: First-party persistence framework
- **SwiftUI**: UI framework
- **Swift Charts**: Data visualization (pie charts, line charts)
- **Foundation**: Core utilities (including CSV parsing, ZIP handling)

### Minimal External Dependencies

AssetFlow is primarily a local application with one optional network dependency:

- **Exchange Rate API**: Fetches currency rates from `cdn.jsdelivr.net/npm/@fawazahmed0/currency-api` (free, no API key required)
- Network access is optional — the app works offline with graceful degradation (no currency conversion, raw sums displayed)
- `com.apple.security.network.client` entitlement is required for exchange rate fetching
- No third-party packages

### Dependency Injection

ViewModels and Services use dependency injection for testability:

```swift
@Observable
@MainActor
class SnapshotDetailViewModel {
    init(
        snapshot: Snapshot,
        modelContext: ModelContext
    ) {
        // ...
    }
}
```

## State Management

### View State

- `@State`: Local view state
- `@Binding`: Two-way bindings
- `@Environment(\.modelContext)`: Access to persistence context

### Data State

- `@Query`: SwiftData reactive queries
- `@Observable` ViewModels: Business logic state

### App State

- `@AppStorage`: User preferences (display currency, date format)
- Custom environment values for configuration

## Error Handling

### Strategy

- Typed errors with custom `Error` conformances
- Error propagation via `throws`
- User-facing error messages (localized)
- Logging for debugging via `os.log` (no `print()` statements)

```swift
enum ImportError: LocalizedError {
    case missingRequiredColumns([String])
    case duplicateAssetsInCSV([(row1: Int, row2: Int, name: String)])
    case duplicateAssetsInSnapshot([(name: String, platform: String)])
    case emptyFile

    var errorDescription: String? {
        // Localized descriptions
    }
}
```

### Calculation Error Handling

- Division by zero: Display "N/A" or "Cannot calculate" with explanation
- Insufficient snapshots for TWR/CAGR: Display "Insufficient data (need at least 2 snapshots)"
- Beginning value \<= 0: Display "Cannot calculate"
- Denominator (BMV + weighted CF) \<= 0: Display "Cannot calculate"
- No snapshot within lookback window: Period metric = N/A

## Performance and Scalability

### General Optimization Strategies

- **Lazy Loading**: SwiftData automatically lazy loads relationships
- **Efficient Queries**: Use specific, filtered predicates in `@Query`
- **Batch Operations**: Use batch processing for CSV imports (insert all SnapshotAssetValues at once)
- **Background Processing**: Consider background tasks for large CSV imports

### Memory Management

- **ARC**: Swift's Automatic Reference Counting is the primary mechanism
- **SwiftUI**: SwiftUI's struct-based views minimize memory footprint
- **Chart Data**: Compute chart data points lazily as needed for the visible time range

## Security Considerations

### Data Protection

- SwiftData encrypted storage (via file system encryption)
- All data stored locally (no network transmission)
- Backup files are unencrypted ZIP archives (user responsibility to store securely)

### Privacy

- No data collection or telemetry
- Network access limited to fetching exchange rates from a public CDN (no authentication, no user data sent)
- User owns 100% of their data
- Local-first architecture

See [SecurityAndPrivacy.md](SecurityAndPrivacy.md) for comprehensive security documentation.

## Testing Strategy

See [TestingStrategy.md](TestingStrategy.md) for comprehensive testing approach.

## Build Configuration

### Targets

- **AssetFlow (macOS)**: Desktop application (macOS 15.0+)

### Build Schemes

- **Debug**: Development builds with logging
- **Release**: Optimized production builds

### Configuration Files

- `.swift-format`: Code formatting rules
- `.swiftlint.yml`: Linting configuration
- `.editorconfig`: Editor settings
- `.pre-commit-config.yaml`: Git hooks

## Future Architecture Considerations

### Potential Enhancements

1. **Modular Architecture**: Extract features into Swift Packages
1. **Repository Pattern**: Abstract data persistence layer
1. **iOS/iPadOS Support**: Platform expansion in future versions
1. **Column Mapping**: Configurable CSV column mapping (future version)
1. **Category-Level Cash Flows**: Per-category cash flow tracking (future version)
