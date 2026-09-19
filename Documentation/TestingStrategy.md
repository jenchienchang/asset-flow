# Testing Strategy

## Overview

This document outlines the testing strategy for AssetFlow, which prioritizes **unit and ViewModel testing** to ensure logical correctness and maintain a fast, reliable test suite.

The project uses the **Swift Testing** framework (`import Testing`) for all tests, with `@Suite`, `@Test`, `#expect()`, and `#require()` macros. XCTest is NOT used.

After careful consideration, the project has opted to **forgo UI testing**. A comprehensive suite of tests at the ViewModel and Service layers provides sufficient confidence in application behavior while avoiding the brittleness and maintenance overhead of UI tests.

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

- **649+ tests** across **44 test files**
- All models, services, and ViewModels have comprehensive test coverage
- Includes SPEC verification tests for end-to-end scenarios

**Test Files**:

| Category    | Files                                                                                                                                                                                                                                                                                                                              | Coverage                                                                                |
| ----------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| Models      | AssetModelTests, CategoryModelTests, SnapshotModelTests, SnapshotAssetValueModelTests, CashFlowOperationModelTests, ExchangeRateModelTests, AssetCategoryRelationshipTests, AssetUniquenessTests, CashFlowOperationUniquenessTests, CategoryUniquenessTests                                                                        | All 6 models + relationships + uniqueness constraints                                   |
| ViewModels  | DashboardViewModelTests, SnapshotListViewModelTests, SnapshotDetailViewModelTests, AssetListViewModelTests, AssetDetailViewModelTests, CategoryListViewModelTests, CategoryDetailViewModelTests, PlatformListViewModelTests, PlatformDetailViewModelTests, RebalancingViewModelTests, ImportViewModelTests, SettingsViewModelTests | All ViewModels                                                                          |
| Services    | CalculationServiceTests, CSVParsingServiceTests, BackupServiceTests, RebalancingCalculatorTests, SettingsServiceTests, ChartDataServiceTests, AuthenticationServiceTests, CurrencyConversionServiceTests, DateFormattingTests, ExchangeRateServiceTests                                                                            | All services (includes batch fetch missing rates tests)                                 |
| Currency    | BackupServiceCurrencyTests, CategoryDetailViewModelCurrencyTests, CategoryListViewModelCurrencyTests, CSVParsingCurrencyTests, PlatformDetailViewModelCurrencyTests, PlatformListViewModelCurrencyTests, SnapshotListViewModelCurrencyTests                                                                                        | Multi-currency conversion scenarios                                                     |
| Integration | NavigationIntegrationTests, SwiftDataRelationshipTests, SpecVerificationTests                                                                                                                                                                                                                                                      | End-to-end scenarios, SPEC verification, edge cases                                     |
| Root        | SnapshotTimeBucketTests                                                                                                                                                                                                                                                                                                            | Snapshot time-bucket edge cases (file at `AssetFlowTests/` root, not in a subdirectory) |

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

- **CalculationService**: Growth rate, Modified Dietz return (no cash flows, with cash flows, time-weighting), cumulative TWR (chaining returns), CAGR (multi-year, fractional year), category allocation, edge cases (zero/negative values, divide-by-zero)
- **CSVParsingService**: Valid files, malformed files, encoding, number formats, within-CSV duplicate detection (assets by name+platform, cash flows by description)
- **BackupService**: Export and version compatibility; record-aware CSV round trips; archive, scalar, identity, and relationship validation; localized diagnostics; complete-graph rollback and settings preservation; round-trip integrity
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
