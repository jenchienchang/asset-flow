# Testing Strategy

Tests should establish AssetFlow's behavior against the [product requirements](SPEC.md), with calculation examples from [`BusinessLogic.md`](BusinessLogic.md) and file and service contracts from [`APIDesign.md`](APIDesign.md). Prioritize financial correctness, unavailable results, failed operations, and preservation of existing data. Describe each check by what it asserts; a passing suite does not establish behavior it never exercises.

Swift application tests use Swift Testing on macOS. Python repository-tooling tests use pytest and have separate fixtures and CI execution. [`DevelopmentGuide.md`](DevelopmentGuide.md) owns setup and contributor commands; the [test skill](../.codex/skills/test/SKILL.md) owns agent execution of Swift tests. [`AssetFlowTests/AGENTS.md`](../AssetFlowTests/AGENTS.md) and [`CodeStyle.md`](CodeStyle.md) own test structure and naming conventions.

## Swift Application Tests

Use pure service and model tests for calculations and validation, ViewModel tests for state transitions, and integration tests with isolated SwiftData containers for persistence and cross-component behavior. Source-contract tests inspect specific view declarations. Offscreen render tests create samples and can assert fitting sizes or that images were produced. The project has no native UI automation target, so interaction, visual quality, and accessibility still need interactive macOS review.

### Risk and verification map

#### Portfolio values and returns

- **Automated evidence:** [CalculationServiceTests](../AssetFlowTests/Services/CalculationServiceTests.swift), [CurrencyConversionServiceTests](../AssetFlowTests/Services/CurrencyConversionServiceTests.swift), [ExchangeRateServiceTests](../AssetFlowTests/Services/ExchangeRateServiceTests.swift), [DashboardViewModelTests](../AssetFlowTests/ViewModels/DashboardViewModelTests.swift), and [AssetDetailViewModelTests](../AssetFlowTests/ViewModels/AssetDetailViewModelTests.swift) cover [returns and conversion](SPEC.md#10-calculation-logic), rate validity, cancellation, and unavailable display state. Asset-history fixtures check converted-only points, line gaps at missing rates, unavailable rates at either end, empty converted periods, and hover suppression near unavailable dates.
- **Manual checks and limits:** Check chart selection, hover, gap markers, affected-date popovers, date labels, and unavailable messages in the running app. ViewModel assertions do not exercise chart or popover interactions.

#### Category goals and rebalancing

- **Automated evidence:** [CategoryGoalValidatorTests](../AssetFlowTests/Services/CategoryGoalValidatorTests.swift), [RebalancingCalculatorTests](../AssetFlowTests/Services/RebalancingCalculatorTests.swift), [RebalancingTransferPlannerTests](../AssetFlowTests/Services/RebalancingTransferPlannerTests.swift), and [CategoryGoalViewModelTests](../AssetFlowTests/ViewModels/CategoryGoalViewModelTests.swift) cover [goal rules](SPEC.md#11-rebalancing-engine), funding, precision, and editor state.
- **Manual checks and limits:** Verify the real sheet, table, help popovers, and Save/Discard/Cancel routing with mouse and keyboard.

#### CSV import and Bulk Entry

- **Automated evidence:** [CSVParsingServiceTests](../AssetFlowTests/Services/CSVParsingServiceTests.swift), [CSVColumnMappingTests](../AssetFlowTests/Services/CSVColumnMappingTests.swift), [ImportViewModelTests](../AssetFlowTests/ViewModels/ImportViewModelTests.swift), and [BulkEntryViewModelTests](../AssetFlowTests/ViewModels/BulkEntryViewModelTests.swift) cover [import behavior](SPEC.md#4-csv-import-system): row errors, mapping, duplicates, and atomic replacement. [DelayedCSVLoadingIndicatorTests](../AssetFlowTests/Views/DelayedCSVLoadingIndicatorTests.swift) check visibility state with a controlled delay and cancellation; [ColumnMappingPreviewLayoutTests](../AssetFlowTests/Views/ColumnMappingPreviewLayoutTests.swift) check column measurement and relative sheet sizing.
- **Manual checks and limits:** Check file picking, mapping-sheet focus, preview feedback, and stale-draft controls in the app. Verify that progress stays hidden for quick CSV loads, appears and clears for longer loads, and that the mapping sheet fits narrow windows without excess blank space or clipping. State and size assertions do not establish the rendered result.

#### Persistence, migration, and backup

- **Automated evidence:** [CategoryGoalMigrationTests](../AssetFlowTests/Integration/CategoryGoalMigrationTests.swift), [BackupServiceTests](../AssetFlowTests/Services/BackupServiceTests.swift), and [CategoryGoalBackupTests](../AssetFlowTests/Services/CategoryGoalBackupTests.swift) check [migration](DataModel.md#schema-migration-and-preservation), [backup compatibility](APIDesign.md#backup-interchange-format), and failure preservation with isolated stores and archives. Process fixtures check success and failure after large stderr, bounded final diagnostics with invalid UTF-8, and prompt cancellation while a child retains the stderr handle.
- **Manual checks and limits:** Restore only disposable synthetic portfolios. Backup validation tests do not establish pre-extraction resource or path guarantees.

#### Refresh, drafts, and fetch failures

- **Automated evidence:** [ObservedRefreshTests](../AssetFlowTests/Utilities/ObservedRefreshTests.swift), [ObservedRefreshRegressionTests](../AssetFlowTests/ViewModels/ObservedRefreshRegressionTests.swift), and [SnapshotSummaryFetchFailureTests](../AssetFlowTests/Services/SnapshotSummaryFetchFailureTests.swift) check refresh coalescing, draft retention, and injected read failures.
- **Manual checks and limits:** Verify SwiftUI `@Query` wiring, visible refresh, retained drafts, and stale Bulk Entry controls in the running app.

#### Presentation, localization, and app lock

- **Automated evidence:** [CategoryGoalLocalizationTests](../AssetFlowTests/Integration/CategoryGoalLocalizationTests.swift), [RebalancingColumnTests](../AssetFlowTests/Integration/RebalancingColumnTests.swift), [CategoryGoalPreviewTests](../AssetFlowTests/Integration/CategoryGoalPreviewTests.swift), and [AuthenticationServiceTests](../AssetFlowTests/Services/AuthenticationServiceTests.swift) check catalogs, source contracts, render samples, and authentication state.
- **Manual checks and limits:** Follow the [interaction design](UserInterfaceDesign.md) in English and Traditional Chinese at wide and narrow widths. Use VoiceOver and native mouse and keyboard events through lock transitions; render files and source checks do not prove interaction or visual accessibility. On supported Macs with and without enrolled Touch ID or a paired Apple Watch, verify the macOS authentication dialog and Settings wording. Mock-based service tests establish the selected policy and failure state, not hardware-specific method availability.

The [SPEC success criteria](SPEC.md#17-success-criteria) identify expected outcomes. Use the corresponding [BusinessLogic worked examples](BusinessLogic.md#portfolio-performance) and [rebalancing rules](BusinessLogic.md#rebalancing-engine) to derive expected values and invariants; do not infer an expected result from the implementation under test.

### Fixtures and failure boundaries

- For ordinary model and ViewModel tests, [TestDataManager](../AssetFlowTests/TestDataManager.swift) creates a uniquely named in-memory container with `CurrentSchema.schema`. Retain the `ModelContainer` for the whole test, including relationship reads; a helper result that discards it can invalidate the backing store. The `TestContext` pattern in [`AssetFlowTests/AGENTS.md`](../AssetFlowTests/AGENTS.md#swiftdata-lifetime-critical) keeps it alive.
- Migration and reopen behavior require disposable disk stores. [CategoryGoalMigrationTests](../AssetFlowTests/Integration/CategoryGoalMigrationTests.swift) opens V1 fixtures through `AssetFlowMigrationPlan` and reopens migrated data. Backup tests use temporary archives and separate model graphs to check supported versions, invalid records, transaction rollback, and preservation of settings when restore fails.
- Settings tests use `SettingsService.createForTesting()` or an isolated `UserDefaults` suite. Exchange-rate tests inject a `URLSession` with mock `URLProtocol`; persistence-failure tests inject `ModelFetching` doubles. These fixtures avoid changing user settings, relying on a live network, or treating a failed fetch as an empty portfolio.
- Async import and backup checks use `Sendable` transfer values, cancellation points, and state assertions. Bulk Entry tests use a gate between preparation and main-actor application, then assert that cancellation leaves rows and feedback unchanged. Swift 6 concurrency compilation checks actor transfers, but does not establish responsiveness. Avoid elapsed-time thresholds and thread-identity assertions.

For each risk, cover valid, invalid, absent, zero, and unavailable inputs where they produce different outcomes. Financial regressions should check full-precision Decimal values, both signs of residuals, strict funding boundaries, conservation and permutation invariants, protected funds, and tiny mandatory transfers. Import regressions should check quoted CSV records, source row diagnostics, normalized duplicates, zero-placeholder replacement, and no partial mutation after invalid input. Refresh regressions should check both settling after repeated loads and later source mutations still publishing new state.

Presentation regressions should distinguish genuine zero, unavailable values, and tiny nonzero amounts rounded for display. Check currency codes and signs, percentage suffixes, and English and Traditional Chinese interpolation without rounding the underlying Decimal targets.

### Representative assertions

The following small Swift Testing suite uses current service interfaces. A Modified Dietz return is a fraction, so `0.09` means 9%; the 90-day example and its expected result are explained in [`BusinessLogic.md`](BusinessLogic.md#modified-dietz-return). The tolerance accounts for Decimal division, while the CSV assertions check both quoted numeric input and a genuinely required header.

```swift
import Foundation
import Testing

@testable import AssetFlow

@Suite("Service examples")
@MainActor
struct ServiceExampleTests {
  @Test("Mid-period contribution produces a nine percent return")
  func midPeriodContribution() throws {
    let result = try #require(
      CalculationService.modifiedDietzReturn(
        beginValue: Decimal(100_000),
        endValue: Decimal(215_000),
        cashFlows: [(amount: Decimal(100_000), daysSinceStart: 30)],
        totalDays: 90
      ))
    let expected = Decimal(string: "0.09")!
    let tolerance = Decimal(string: "0.0001")!
    #expect(abs(result - expected) < tolerance)
  }

  @Test("Quoted amounts parse and missing required headers are reported")
  func assetCSV() throws {
    let csv = """
      Asset Name,Market Value
      AAPL,"15,000.50"
      """
    let parsed = CSVParsingService.parseAssetCSV(
      data: Data(csv.utf8), importPlatform: nil)
    #expect(parsed.isValid)
    let row = try #require(parsed.rows.first)
    #expect(row.marketValue == Decimal(string: "15000.50")!)
    #expect(row.platform == "")

    let missing = CSVParsingService.parseAssetCSV(
      data: Data("Asset Name\nAAPL\n".utf8), importPlatform: nil)
    #expect(missing.errors.contains(where: {
      $0.row == 1 && $0.column == "Market Value"
    }))
  }
}
```

For model and ViewModel fixture examples, use [AssetModelTests](../AssetFlowTests/Models/AssetModelTests.swift) and [CategoryListViewModelTests](../AssetFlowTests/ViewModels/CategoryListViewModelTests.swift). Test normalized identity through its public behavior; use separate persistence tests when checking uniqueness constraints or relationships. The current source files and [`APIDesign.md`](APIDesign.md#internal-service-apis) own API signatures rather than copied skeletons here.

### Interaction checks on macOS

The following are recommended manual checks. They are not established by the Swift Testing suites:

1. Restore a disposable synthetic backup while Dashboard, Rebalancing, Snapshots, Assets, Categories, or Platforms is open. Confirm that visible data refreshes, matching stable IDs rebind to restored records, missing selections clear, and open pickers or import previews use the new store. Never use a personal portfolio or delete a personal store for this check.
1. Add or change snapshots, asset values, categories, and goal settings while their lists or detail views remain open. Confirm histories and totals refresh without navigation, clean editors adopt saved changes, unsaved category drafts remain, and a stale Bulk Entry draft blocks editing and saving until reloaded.
1. In both supported languages and at narrow widths, inspect rebalancing explanations, currency headings, zero and unavailable values, chart interactions, and clipping. Check field-focused Return, Command-S, information-button keyboard access, popover dismissal, VoiceOver labels, and focus order.
1. With App Lock enabled, exercise mouse, keyboard, hover, and tooltip behavior through lock and unlock transitions. Service tests cover authentication state; they do not prove that the lock overlay prevents visual or interaction disclosure.
1. For large synthetic imports and backups, use Instruments to inspect main-thread file, parsing, serialization, and archive work. Compilation and cancellation assertions do not measure interface responsiveness.

### Regression workflow and coverage expectations

When using red-green-refactor, first write a compiling test and minimal stubs, then confirm RED is an assertion failure. Implement the behavior, confirm GREEN, and run the relevant regressions before refactoring. Use `#expect` for assertions and `#require` when the remainder of a test needs a value. Keep fixtures deterministic and independent.

Judge coverage by the behaviors and failure boundaries asserted, not by an unmeasured percentage or a fixed file count. A service result, a ViewModel state assertion, a source-contract check, an offscreen render, and an interactive observation are different kinds of evidence. Record any unverified behavior as a gap rather than describing the suite as complete.

When diagnosing a Swift test failure, separate compilation or actor-isolation errors from assertion failures. A suite-wide SIGTRAP immediately after relationship access can indicate a prematurely released `ModelContainer`; inspect the retained fixture and captured test log before rerunning. The [test skill](../.codex/skills/test/SKILL.md) owns runner and log details.

## Python Script Tests

Python tests verify repository tooling independently of the Swift application. The root [`pyproject.toml`](../pyproject.toml) discovers [`scripts/tests/`](../scripts/tests/); pytest is in the project-local uv development dependency group. [`DevelopmentGuide.md`](DevelopmentGuide.md#python-script-tests) owns local commands and environment setup. The current [release-version suite](../scripts/tests/test_release_version.py) requires macOS because the script uses `/usr/bin/plutil`; it skips on other platforms.

The release-version tests run the [CLI](../scripts/release_version.py) through `sys.executable` against pytest temporary project and archive fixtures. They check that synchronization changes only app marketing versions, no-op runs preserve bytes, invalid or missing versions and configurations fail without changing the project, and archive checks accept XML or binary plists while rejecting missing, malformed, or mismatched metadata. Parameterized cases cover related invalid inputs. These assertions establish script behavior on disposable fixtures, not signing or a hosted release.

The [Unit Tests workflow](../.github/workflows/unit-tests.yml) runs Swift tests and pytest in separate macOS jobs. The [shared Xcode workflow](../.github/workflows/xcode-build.yml) also checks the real project's version before builds and checks the finished archive's version for archive jobs. Fixture tests, real-project checks, and archive checks answer different questions; none establish that a distributed app was signed or notarized. For new tooling, test CLI exit status, diagnostics, and file side effects against isolated fixtures, including preservation on failure.
