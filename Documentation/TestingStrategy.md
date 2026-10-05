# Testing Strategy

## Overview

This document outlines the testing strategy for AssetFlow, which prioritizes **unit and ViewModel testing** to ensure logical correctness and maintain a fast, reliable test suite.

The project uses the **Swift Testing** framework (`import Testing`) for all tests, with `@Suite`, `@Test`, `#expect()`, and `#require()` macros. XCTest is NOT used.

The app and test targets use the Swift 6 language mode with complete concurrency checking. A successful test run requires both compilation without Swift concurrency diagnostics and passing Swift Testing assertions; tests are run on macOS because SwiftData and the application target are macOS-only.

GitHub Actions runs the unit test suite on every pull request through `.github/workflows/unit-tests.yml`. The workflow uses the shared Xcode build workflow and runs `xcodebuild test -project AssetFlow.xcodeproj -scheme AssetFlow -destination 'platform=macOS'`.

Currency conversion tests cover both numeric correctness and availability semantics. Exchange-rate fetch tests use a mock `URLSession` to verify fixed Gregorian API dates, rejection of empty, invalid, and wrong-date responses, complete currency coverage before caching, replacement of malformed and wrong-date cached data, request coalescing, prompt cancellation of an individual coalesced waiter while another continues, and protection against cache mutation after cancellation. Conversion tests also verify that wrong-date records and missing rates produce native-currency totals plus an explicit unavailable status rather than a mixed-currency display total. Dashboard ViewModel tests verify that a historical pie-chart selection reports the selected snapshot's availability even when the latest snapshot is complete. Persistence failure tests inject a `ModelFetching` double and verify that fetch errors propagate, list ViewModels expose `DataLoadState.failed`, the snapshot list does not trust an empty query result, and snapshot creation performs no mutation after a required read fails.

After careful consideration, the project has opted to **forgo UI testing**. A comprehensive suite of tests at the ViewModel and Service layers provides sufficient confidence in application behavior while avoiding the brittleness and maintenance overhead of UI tests.

### Query-Driven Data Refresh

Unit tests cover query revision changes for both membership and edits to each persisted model type, stable-ID selection rebinding, Import preview revalidation and picker refresh after store replacement, Platform detail reload behavior, and Bulk Entry stale-draft save protection. SwiftUI `@Query` callback wiring is verified manually because the project has no UI test target:

1. Restore a different backup while Dashboard, Rebalancing, Snapshots, Assets, Categories, or Platforms is active; confirm visible data refreshes without navigating away and returning.
1. Keep the Assets, Categories, and Platforms lists open while adding a newer snapshot with changed values; confirm latest values, allocations, and platform totals refresh without navigating away.
1. Keep a snapshot, asset, or category detail selected across restore; confirm a matching stable ID shows the restored values and a missing ID clears the detail selection.
1. Keep the New Snapshot or Add Asset sheet open through restore; confirm date conflicts, picker options, and selected model references reflect the restored store.
1. Keep Category or Platform detail open while adding and deleting snapshots (including snapshots without asset values); confirm histories incorporate each date.
1. Keep Import open with a loaded CSV while changing existing asset/category fields and snapshot child values; confirm picker options and duplicate validation update. Navigate away and return to confirm a fresh validation pass.
1. Keep Bulk Entry open while editing a value in the prior snapshot or changing an asset/category; confirm the stale banner appears, editing and saving are disabled, and **Discard Draft and Reload** creates a fresh draft.
1. Keep a platform detail selected across restore; confirm its asset/history data reloads, its rename draft resets, and a platform absent from the restored assets is deselected.
1. Keep Bulk Entry open while restoring; confirm the stale banner appears, editing and saving are disabled, and **Discard Draft and Reload** creates a fresh draft. Also verify a retained Bulk Entry draft becomes stale when restore occurs while another section is selected.

Async file, import, and backup tests use `Sendable` transfer values and deterministic task boundaries. They verify that CSV preparation and backup validation can be called from detached tasks, that cancellation is honored during CSV record and row processing, and that main-actor ViewModels apply only completed worker results. Bulk Entry direct-import tests also verify that cancellation returns a no-op result without changing existing rows or feedback, including deterministic gates that cancel after preparation is ready but before main-actor application. These tests do not inspect thread identities or assert elapsed time; executor threads are an implementation detail and timing thresholds are unstable across machines.

______________________________________________________________________

## Testing Philosophy

### Core Principles

1. **Test-Driven Development (TDD)**: Write tests before or alongside implementation when practical
1. **Focused Testing**: Concentrate on ViewModel and Service layers (the logic-heavy parts)
1. **Fast Feedback**: Tests must run quickly and provide clear failure messages
1. **Isolation**: Each test runs in a completely isolated environment (in-memory SwiftData container)
1. **Maintainability**: Tests are code and must be kept clean and well-organized

### The Testing Pyramid

```
        +------------------+
        |    UI Layer      |  <- Not tested automatically
        |     (Views)      |
        +------------------+
        |   ViewModel &    |  <- Primary focus: Test app
        | Integration Tests|    logic and state here
        +------------------+
        |    Unit Tests    |  <- Foundation: Test models,
        | (Models, Utils)  |    services, and calculations
        +------------------+
```

______________________________________________________________________

## Testing Frameworks

This project uses **Swift Testing** for all tests:

```swift
import Testing
import SwiftData

@Suite("Category Model Tests")
@MainActor
struct CategoryModelTests {
    @Test("name must not be empty")
    func nameValidation() throws {
        // test implementation
    }
}
```

**NOT XCTest**: Do not use `XCTestCase`, `XCTAssert*`, or other XCTest APIs.

______________________________________________________________________

## Unit and ViewModel Testing with SwiftData

Every test function that requires a database creates its own dedicated, in-memory `ModelContainer` for perfect isolation.

### Import Lookup Coverage

Import and Bulk Entry tests verify operation-scoped lookup behavior through functional correctness rather than timing thresholds. Coverage includes normalized identity reuse, first-match behavior, zero-value snapshot placeholders, duplicate validation, category reuse and display-order assignment, excluded rows, and representative larger synthetic imports that assert final entity/value counts and selected relationships. Unit tests do not assert elapsed time because SwiftData faulting, in-memory containers, build configuration, and CI machine load make timing thresholds noisy; collection-size scalability is validated by the indexed implementation structure and these correctness fixtures.

### Background Work Validation

No execution-time/performance test target and no UI test target is used for main-actor responsiveness. Swift 6 compilation verifies that non-Sendable SwiftData objects do not cross the worker boundary. Service and ViewModel tests verify async handoff, cancellation during CSV record/row processing, failure state, and restore data preservation with task cancellation and state assertions rather than sleeps. Large-file responsiveness is checked manually with Instruments by inspecting main-thread call stacks for file, parser, serialization, and archive work.

### Test Data Manager

```swift
// In AssetFlowTests/TestDataManager.swift
@MainActor
class TestDataManager {
    static func createInMemoryContainer() -> ModelContainer {
        let schema = Schema([
            Category.self,
            Asset.self,
            Snapshot.self,
            SnapshotAssetValue.self,
            CashFlowOperation.self,
            ExchangeRate.self,
        ])
        // Use a unique name per container to ensure true isolation.
        // Without a unique name, ModelConfiguration(isStoredInMemoryOnly: true) may
        // share the same backing store across calls, causing test interference.
        let configuration = ModelConfiguration(
            UUID().uuidString,
            schema: schema,
            isStoredInMemoryOnly: true
        )
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            return container
        } catch {
            fatalError("Failed to create in-memory model container: \(error)")
        }
    }
}
```

### Example: Model Test

```swift
@Suite("Asset Model Tests")
@MainActor
struct AssetModelTests {
    @Test("asset identity uses normalized name and platform")
    func assetIdentity() throws {
        let container = TestDataManager.createInMemoryContainer()
        let context = container.mainContext

        let asset1 = Asset(name: "AAPL", platform: "Interactive Brokers")
        let asset2 = Asset(name: "  aapl  ", platform: "interactive brokers")
        context.insert(asset1)
        context.insert(asset2)

        // Verify normalized identity matching
        #expect(asset1.normalizedIdentity == asset2.normalizedIdentity)
    }
}
```

### Example: ViewModel Test

ViewModels accept a `ModelContext` in their initializer for test injection:

```swift
@Suite("CategoryListViewModel Tests")
@MainActor
struct CategoryListViewModelTests {
    @Test("deleteCategory blocked when assets assigned")
    func deleteCategoryWithAssets() throws {
        let container = TestDataManager.createInMemoryContainer()
        let context = container.mainContext

        let category = Category(name: "Equities")
        let asset = Asset(name: "AAPL", platform: "IB")
        asset.category = category
        context.insert(category)
        context.insert(asset)

        let viewModel = CategoryListViewModel(modelContext: context)

        #expect(throws: CategoryError.cannotDeleteWithAssignedAssets) {
            try viewModel.deleteCategory(category)
        }
    }

    @Test("deleteCategory succeeds when no assets assigned")
    func deleteCategoryEmpty() throws {
        let container = TestDataManager.createInMemoryContainer()
        let context = container.mainContext

        let category = Category(name: "Equities")
        context.insert(category)

        let viewModel = CategoryListViewModel(modelContext: context)
        try viewModel.deleteCategory(category)

        let descriptor = FetchDescriptor<Category>()
        let remaining = try context.fetch(descriptor)
        #expect(remaining.isEmpty)
    }
}
```

### Example: Service Test

Services are stateless and operate on pre-fetched data. Tests use real SwiftData models in an in-memory container (same pattern as ViewModel tests):

### Example: Calculation Test

```swift
@Suite("ModifiedDietzCalculator Tests")
struct ModifiedDietzCalculatorTests {
    @Test("basic return with no cash flows")
    func basicReturn() {
        let result = ModifiedDietzCalculator.calculate(
            beginningValue: 100000,
            endingValue: 110000,
            cashFlows: [],
            periodStart: date("2025-01-01"),
            periodEnd: date("2025-03-31")
        )

        #expect(result != nil)
        #expect(result! == Decimal(string: "0.1")!)  // 10% return
    }

    @Test("return with mid-period cash flow")
    func returnWithCashFlow() {
        let result = ModifiedDietzCalculator.calculate(
            beginningValue: 100000,
            endingValue: 160000,
            cashFlows: [(date: date("2025-01-31"), amount: 50000)],
            periodStart: date("2025-01-01"),
            periodEnd: date("2025-03-31")
        )

        #expect(result != nil)
        // EMV=160000, BMV=100000, CF=50000
        // w = (89-30)/89 = 0.663
        // R = (160000-100000-50000) / (100000 + 0.663*50000)
        // R = 10000 / 133150 = 0.0751 (approx)
    }

    @Test("returns nil when beginning value is zero")
    func zeroBMV() {
        let result = ModifiedDietzCalculator.calculate(
            beginningValue: 0,
            endingValue: 10000,
            cashFlows: [],
            periodStart: date("2025-01-01"),
            periodEnd: date("2025-03-31")
        )

        #expect(result == nil)
    }
}
```

### Example: Parameterized Test

Swift Testing supports parameterized tests, which are ideal for testing edge cases in calculation logic:

```swift
@Suite("GrowthRateCalculator Edge Cases")
struct GrowthRateEdgeCaseTests {
    @Test("returns nil for invalid beginning values", arguments: [
        Decimal(0), Decimal(-100), Decimal(-1),
    ])
    func invalidBeginningValues(bmv: Decimal) {
        let result = GrowthRateCalculator.calculate(
            beginningValue: bmv,
            endingValue: 100
        )
        #expect(result == nil)
    }
}
```

______________________________________________________________________

### Example: CSV Parsing Test

```swift
@Suite("CSVParsingService Tests")
struct CSVParsingServiceTests {
    @Test("parses valid asset CSV")
    func parseValidAssetCSV() throws {
        let csv = """
        Asset Name,Market Value,Platform
        AAPL,15000,Interactive Brokers
        Bitcoin,5000,Coinbase
        """
        let url = createTempFile(content: csv)

        let result = try CSVParsingService.parseAssetCSV(
            url: url,
            importPlatform: nil,
            importCategory: nil
        )

        #expect(result.rows.count == 2)
        #expect(result.rows[0].assetName == "AAPL")
        #expect(result.rows[0].marketValue == 15000)
        #expect(result.rows[0].platform == "Interactive Brokers")
    }

    @Test("strips currency symbols and thousand separators")
    func numberParsing() throws {
        let csv = """
        Asset Name,Market Value
        Stock A,$15,000.50
        Stock B, $1,234
        """
        let url = createTempFile(content: csv)

        let result = try CSVParsingService.parseAssetCSV(
            url: url,
            importPlatform: nil,
            importCategory: nil
        )

        #expect(result.rows[0].marketValue == Decimal(string: "15000.50"))
        #expect(result.rows[1].marketValue == 1234)
    }

    @Test("throws error for missing required columns")
    func missingColumns() {
        let csv = """
        Name,Value
        AAPL,15000
        """
        let result = CSVParsingService.parseAssetCSV(
            data: Data(csv.utf8),
            importPlatform: nil
        )

        #expect(result.hasErrors)
        #expect(result.errors.first?.message.contains("Platform") == true)
    }
}
```

### Example: Duplicate Detection Test

```swift
@Suite("DuplicateDetectionService Tests")
struct DuplicateDetectionTests {
    @Test("detects duplicate assets within CSV")
    func duplicatesInCSV() {
        let rows = [
            AssetCSVRow(rowNumber: 1, assetName: "AAPL", marketValue: 15000, platform: "IB"),
            AssetCSVRow(rowNumber: 2, assetName: "VTI", marketValue: 28000, platform: "IB"),
            AssetCSVRow(rowNumber: 3, assetName: "aapl", marketValue: 16000, platform: "IB"),
        ]

        let duplicates = DuplicateDetectionService.findAssetDuplicatesInCSV(rows)

        #expect(duplicates.count == 1)
        #expect(duplicates[0].row1 == 1)
        #expect(duplicates[0].row2 == 3)
    }

    @Test("detects duplicate cash flows within CSV")
    func cashFlowDuplicatesInCSV() {
        let rows = [
            CashFlowCSVRow(rowNumber: 1, description: "Salary deposit", amount: 50000),
            CashFlowCSVRow(rowNumber: 2, description: "salary deposit", amount: 30000),
        ]

        let duplicates = DuplicateDetectionService.findCashFlowDuplicatesInCSV(rows)

        #expect(duplicates.count == 1)
    }
}
```

______________________________________________________________________

## Test Data and Previews

### Test Utilities

- **Unit/ViewModel Tests**: Use `TestDataManager.createInMemoryContainer()` for clean database per test
- **SwiftUI Previews**: Use `PreviewContainer` utility for dedicated in-memory container

### Test Fixtures

For creating complex model instances:

```swift
extension Snapshot {
    static func withAssets(
        date: Date,
        assets: [(Asset, Decimal)],
        in context: ModelContext
    ) -> Snapshot {
        let snapshot = Snapshot(date: date)
        context.insert(snapshot)
        for (asset, value) in assets {
            let sav = SnapshotAssetValue(marketValue: value)
            sav.snapshot = snapshot
            sav.asset = asset
            context.insert(sav)
        }
        return snapshot
    }
}
```

______________________________________________________________________

## Test Coverage

### Coverage Goals

| Layer       | Target Coverage |
| ----------- | --------------- |
| Models      | 90%+            |
| ViewModels  | 85%+            |
| Services    | 90%+            |
| Calculators | 95%+            |
| Overall     | 85%+            |

### Enabling Coverage

1. Edit Scheme > Test
1. Options > Code Coverage > Gather coverage for `AssetFlow` target
1. Run tests and view results in Report Navigator (Cmd+9)

______________________________________________________________________

## Test Inventory

**Current Status:**

- **901 tests** across **57 test files**
- All models, services, and ViewModels have comprehensive test coverage
- Includes SPEC verification tests for end-to-end scenarios

**Test Files**:

| Category       | Files                                                                                                                                                                                                                                                                                                                                                       | Coverage                                                                                                    |
| -------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| Models         | AssetModelTests, CategoryModelTests, SnapshotModelTests, SnapshotAssetValueModelTests, CashFlowOperationModelTests, ExchangeRateModelTests, AssetCategoryRelationshipTests, AssetUniquenessTests, CashFlowOperationUniquenessTests, CategoryUniquenessTests                                                                                                 | All 6 models + relationships + uniqueness constraints                                                       |
| ViewModels     | DashboardViewModelTests, SnapshotListViewModelTests, SnapshotDetailViewModelTests, AssetListViewModelTests, AssetDetailViewModelTests, CategoryListViewModelTests, CategoryDetailViewModelTests, PlatformListViewModelTests, PlatformDetailViewModelTests, RebalancingViewModelTests, BulkEntryViewModelTests, ImportViewModelTests, SettingsViewModelTests | All ViewModels                                                                                              |
| Services       | CalculationServiceTests, CSVParsingServiceTests, BackupServiceTests, RebalancingCalculatorTests, SettingsServiceTests, ChartDataServiceTests, AuthenticationServiceTests, CurrencyConversionServiceTests, DateFormattingTests, ExchangeRateServiceTests, SnapshotSummaryFetchFailureTests                                                                   | All services (includes persistence failure and batch fetch missing rates tests)                             |
| Currency       | BackupServiceCurrencyTests, CategoryDetailViewModelCurrencyTests, CategoryListViewModelCurrencyTests, CSVParsingCurrencyTests, PlatformDetailViewModelCurrencyTests, PlatformListViewModelCurrencyTests, SnapshotListViewModelCurrencyTests                                                                                                                 | Multi-currency conversion scenarios                                                                         |
| Integration    | NavigationIntegrationTests, SwiftDataRelationshipTests, SpecVerificationTests                                                                                                                                                                                                                                                                               | End-to-end scenarios, SPEC verification, edge cases                                                         |
| Root           | SnapshotTimeBucketTests                                                                                                                                                                                                                                                                                                                                     | Snapshot time-bucket edge cases (file at `AssetFlowTests/` root, not in a subdirectory)                     |
| Utilities      | ModelResolutionLookupTests                                                                                                                                                                                                                                                                                                                                  | Operation-scoped persistence lookup indexes                                                                 |
| Category goals | CategoryGoalValidatorTests, CategoryGoalAssessmentTests, CategoryGoalBackupTests, CategoryGoalViewModelTests, CategoryGoalMigrationTests, CategoryGoalLocalizationTests, CategoryGoalPreviewTests, RebalancingHelpPresentationTests                                                                                                                         | Goal validation, constrained allocation integration, migration, backup, locales and sample screen rendering |

**TestContext Pattern**: All ViewModel tests use the `TestContext` struct pattern to retain `ModelContainer` for the test scope, preventing premature deallocation and "model instance destroyed" crashes.

______________________________________________________________________

## What to Test

### Models

- Computed properties (normalized identity, relationship helpers)
- Validation rules (uniqueness, required fields)
- Deletion constraints (asset with values, category with assets)

### ViewModels

- Form state management and validation
- CRUD operations (create, update, delete with proper constraints)
- Error state handling
- Empty state handling
- Import preview and validation

### Services

- **CalculationService**: Growth rate, Modified Dietz return (no cash flows, with cash flows, time-weighting), cumulative TWR (chaining returns), CAGR (multi-year, fractional year, large-magnitude Decimal values), category allocation, edge cases (zero/negative values, divide-by-zero), and Decimal precision bounds
- **CSVParsingService**: Valid files, RFC-style quoted commas, escaped quotes, CRLF, embedded newlines, empty/trailing fields, malformed records, encoding, number formats, column mapping, localized parser/validation diagnostics, source-row-preserving duplicate diagnostics (including invalid rows before cash-flow duplicates), and within-CSV duplicate detection (assets by name+platform, cash flows by description)
- **BulkEntryViewModel**: Effective target-platform resolution, duplicate rejection after resolution, skipped-platform warnings, malformed and mixed-validity CSV errors, and atomic replacement preservation
- **BackupService**: Export and version compatibility; record-aware CSV round trips; archive, scalar, identity, and relationship validation; localized diagnostics from app-owned parser reasons (including Traditional Chinese catalog coverage); complete-graph rollback and settings preservation; round-trip integrity
- **RebalancingCalculator**: Balanced portfolio, unbalanced, no target, uncategorized assets, adjustment calculations
- **ChartDataService**: Time range filtering, abbreviated axis labels (K/M/B)

______________________________________________________________________

## Best Practices

- **Test Behavior, Not Implementation**: Focus on what the code *does*, not how it does it
- **One Assertion Per Test**: Ideal for clarity, but group related assertions when necessary
- **Arrange-Act-Assert**: Structure tests clearly
- **Independence**: Tests must not rely on each other
- **Avoid Testing Frameworks**: Don't test SwiftData or SwiftUI internals
- **Write Regression Tests**: When fixing a bug, write a test that fails before the fix and passes after
- **Test Edge Cases**: Zero values, nil values, empty collections, boundary conditions (14-day threshold, 0 denominator)

______________________________________________________________________

## References

- [Swift Testing Documentation](https://developer.apple.com/documentation/testing)
- [AssetFlowTests/CLAUDE.md](../AssetFlowTests/CLAUDE.md) - Detailed test patterns
- [Architecture.md](Architecture.md) - Layer responsibilities
- [BusinessLogic.md](BusinessLogic.md) - Calculation formulas for test verification

## Category Goal Coverage

Swift Testing goal suites cover shared validation and complete locale parsing, all four goal combinations, currency defaults, Decimal precision, iterative minimum binding, conservation/permutation invariants, zero weights/totals, global versus available-funds shortfalls, protected balances, tiny mandatory transfers, and stale-plan clearing. RED uses compiling stubs and assertion failures before implementation; targeted GREEN logs precede full-suite regression verification.

Category editing regression tests cover draft detection, atomic validation, Revert, saved baselines, guarded navigation, Cancel, failed Save retention, and successful Save/Discard continuation. Offscreen render samples cover compact table rows and wide/narrow form layouts in both languages. Verify field-focused Return, Command-S, information-button keyboard access, and locked popover dismissal interactively; model tests and render samples do not verify actual keyboard event routing.

Disposable disk fixtures verify V1-to-V2 migration of all six model types and persistence after reopen. Backup v4 tests cover currency/rate preservation, full-precision goals, legacy default nil fields, invalid pairs and restore rollback. Goal-only rate tests use a mocked URLSession; missing historical rates break goal comparisons without hiding valid values. Catalog tests require Traditional Chinese translations and matching placeholders. Manual macOS review covers narrow windows, accessibility, both languages, and lock interactions; automated tests do not establish visual accessibility by themselves.

## Structured Rebalancing Help

RebalancingHelpPresentationTests cover section grouping, omitted goals, protected categories, minimum-binding explanations, infeasible plans without totals, original versus converted denominations, missing values as em dashes, and genuine zero shortfalls. Render fixtures include all three popup bodies in both languages. Actual mouse/keyboard activation and lock transitions still require interactive macOS verification.

Currency-heading regression coverage checks per-table scope, mixed currencies, unavailable row currencies, case-insensitive ISO codes, percentage-only and mixed percentage/monetary tables, signs, asset display precision, tiny nonzero bounds, and preservation of currency codes in explanatory sentences.

### Rebalancing conversion precision regressions

Synthetic full-precision converted balances reproduce the legacy portfolio precision failure without including private backup data. Calculator tests separately cover addition precision loss with identical totals, regrouping differences, both signs of consistency residuals, rejection outside the existing arithmetic tolerance, input permutation invariance, strict minimum funding boundaries, percentage/funding sums whose precision loss could conceal an excess, converted protected holdings and binding minimums, and invalid/overflow/underflow arithmetic. Assessment tests reverse SwiftData relationship and category ordering across multi-currency historical snapshots and require identical totals, category balances and plans. A disposable V1 disk graph with converted history migrates to V2 with nil minimum fields and remains rebalancable. Each regression was run to assertion-based RED before production changes, followed by GREEN and full-suite verification.

### Rebalancing popup display precision

Assertion-based RED/GREEN regressions verify shared and mixed-currency popup rows, allocation totals, shortfall explanations and blocked-plan diagnostics. Numeric formatting is compared with Foundation's existing asset currency fraction defaults for fiat, crypto and unknown codes in English, Traditional Chinese and a comma-decimal locale. Coverage includes positive/negative changes, actual zero, unavailable values, thresholds with zero/two/three fraction digits, values just below and at one display unit, localized Increase/Decrease labels and preservation of raw minimum assessment inputs. Currency code compaction remains independent of numeric formatting. No Full precision disclosure or per-asset precision metadata is introduced.

### Aggregate refresh and category-list regressions

Use assertion-based RED before replacing loaders. Counting fetchers stop runaway refreshes safely and assert that repeated loads and Save settle, then that later source mutations still refresh. `ObservedRefreshTests` cover request coalescing, generation supersession, publication exclusion and mutations during publication. Dashboard cache-reader tests check UI observation independently of scalar output equality. Category-list tests cover minimum-only shares, protected surplus, no-goal rows, combined reasons, the exact five-point boundary, zero/infeasible portfolios and missing goal conversion. Existing history/rate, query-revision and store-replacement tests remain part of the full suite. English/Traditional Chinese catalog tests require translated labels/help and matching placeholders.

Clean category editors adopt externally updated saved fields after a data refresh; editors with unsaved changes retain every draft field. Saved-field source reads are tracked even for empty categories.

Rebalancing column regressions verify the SwiftUI declaration order and percentage binding as a source contract, alongside runtime ViewModel checks for minimum-only effective shares including protected holdings and unavailable/zero-total cases. String catalog tests require Traditional Chinese translations for both effective-target headings.

### Lettered allocation explanation regressions

Assertion-based RED/GREEN covers the eight-column order, letter/formula references, portfolio/protected/available reconciliation, final remaining weights after multiple minimum passes, minimum-bound equality, minimum-only top-ups and surplus retention, uncategorized protection, explicit zero percentages, zero totals, missing rates and infeasible plans. Rounded inputs/results use approximation markers without altering Decimal targets. Existing currency compaction and precision regressions remain. Every new presentation string has English and Traditional Chinese coverage; render fixtures cover both locales and wide/narrow tables.

### Intrinsic rebalancing popup layout

Assertion-based RED/GREEN measures NSHostingView fitting sizes: inline formulas increase width without adding a line; long paragraphs do not widen tables; screen-constrained labels and very long values wrap; text-only diagnostics remain bounded; input row spacing is one text line plus four points. Source integration checks cover all three content-sizing opt-ins, consistent secondary labels and first-baseline rows without conditional separator views. Render previews measure natural dimensions and also capture 320-point constrained layouts for both locales. Offscreen renders verify layout, not native popover event routing.

Numeric-width regression tests compare popup fitting widths for identical values in input/result rows and for different digits of equal length. Cases include grouped amounts, ISO prefixes, approximation markers and percentage suffixes. Source integration checks require the standard system callout font, one bold value weight and `.monospacedDigit()`, matching the dashboard tooltip approach; they reject monospaced font design and conditional result font weights. Assertion-based RED/GREEN verifies the styling switch while preserving natural/constrained layout and numeric widths.

Percentage suffix regressions reach assertion-based RED/GREEN for English, Traditional Chinese, German and French number separators and percent symbols, actual zero and unavailable shares. Category tests check configured/remaining/effective percentage metadata and its preservation through currency compaction; render previews cover a separate suffix column under natural and constrained widths. Accessibility joins the symbol to the value rather than exposing a disconnected symbol cell.

Keep-operation icon regressions require a secondary-gray Label with `minus.circle.fill`, retain the existing localized key and verify that AppKit resolves the SF Symbol. Both-language rebalancing render previews cover the action column.

### Reviewer regression coverage: funding, sheets, localization

`RebalancingTransferPlannerTests` exercises the reported 100-unit portfolio, multiple minimum-bearing recipients with above-minimum demand, supporting small donors, optional subunit suppression, zero changes, recipient order, capacity limits and minimum preservation. `CategoryGoalViewModelTests` verifies the actual localized Suggested Moves and residual, editor retention through Save/Discard and sheet cancellation, subsequent navigation guards, actual editor replacement and ContentView lifecycle wiring. Existing invalid-save and infeasible-plan tests remain required. `CategoryGoalLocalizationTests` checks active rebalancing catalog keys and renders the real percentage-sum diagnostic from the compiled Traditional Chinese bundle, including interpolation and a single literal percent sign. RED must fail by assertions before implementation.
