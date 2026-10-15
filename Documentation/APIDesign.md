# API and Integration Design

AssetFlow is a local-first macOS app. This document defines the contracts between its Swift components and the formats crossing its CSV, backup, and exchange-rate boundaries. Portfolio records stay local; the app contacts `cdn.jsdelivr.net` for currency names and date-specific exchange rates. [`SPEC.md`](SPEC.md) defines intended behavior, [`BusinessLogic.md`](BusinessLogic.md) owns financial rules, [`DataModel.md`](DataModel.md) owns stored entities, and [`Architecture.md`](Architecture.md) owns component lifetimes and data flow.

The examples below show useful call boundaries rather than an inventory of every declaration. Source links identify the full interfaces.

## Internal Service APIs

### CSVParsingService

[`CSVParsingService.swift`](../AssetFlow/Services/CSVParsingService.swift), [`CSVParsingService+ColumnMapping.swift`](../AssetFlow/Services/CSVParsingService+ColumnMapping.swift), and [`CSVParsingTypes.swift`](../AssetFlow/Services/CSVParsingTypes.swift) define the user-import parser. It receives `Data`, not a file URL. [CSVFileReader](../AssetFlow/Services/CSVParsingService.swift) reads security-scoped URLs asynchronously; `CSVImportPreparationService` then prepares the same bytes for the Import screen and Bulk Entry.

| Boundary                                                                              | Input and result                                                                        | Failure and side effects                                                                                                                  |
| ------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `CSVParsingService.parseAssetCSV(data:importPlatform:)` and `parseCashFlowCSV(data:)` | Raw bytes → `CSVParseResult<AssetCSVRow>` or `CSVParseResult<CashFlowCSVRow>`           | Synchronous and nonthrowing. Syntax, header, and row problems are returned as `CSVError` values. No model mutation.                       |
| Mapping overloads of `parseAssetCSV` and `parseCashFlowCSV`                           | Raw bytes and a confirmed `CSVColumnMapping` → the same result types                    | The header is still read, but its names are not revalidated against canonical names. Missing required mapped fields become result errors. |
| `CSVImportPreparationService.prepare(data:schema:)` and `prepare(data:mapping:)`      | Bytes → `CSVImportPreparation.parsedAsset`, `.parsedCashFlow`, or `.needsMapping`       | Async and throwing, with cooperative cancellation. Ordinary parsing errors remain in the parsed result; cancellation throws.              |
| `CSVParsingService.resolveAssetRowsForPlatform(rows:platform:)`                       | Parsed rows and a Bulk Entry target platform → included rows and mismatched asset names | Rows for another platform are skipped; included blank or matching platforms resolve to the target.                                        |

`CSVParseResult` keeps `parsingErrors`, `duplicateErrors`, and `warnings` separate; `errors` combines the two error arrays, and `hasErrors` determines whether the result is valid. `CSVError` and `CSVWarning` carry a source row, optional column, and localized message. Parsed asset and cash-flow rows keep their source `rowNumber`, `Decimal` amount, and currency string. `CashFlowCSVRow.description` maps to the model's `cashFlowDescription` property.

[`CSVRecordReader.swift`](../AssetFlow/Services/CSVRecordReader.swift) uses TabularData for logical CSV records and quoting, including escaped quotes and embedded newlines. It reads columns as strings before the app parses monetary values as `Decimal`. The async reader checks cancellation between its TabularData passes and while materializing records; the async row parsers also check between rows and during duplicate detection.

The parser reports duplicate candidates within the raw CSV separately from structural errors. Import workflows recheck the *included, effective* rows after applying platform rules; `ImportViewModel` also checks conflicts with the target snapshot. A matching zero-valued snapshot asset can be replaced as a placeholder, while a matching nonzero asset blocks import. [`BusinessLogic.md`](BusinessLogic.md#duplicate-and-replacement-policy) owns the identity and conflict rules; the [CSV format section](#csv-import-format-specification) gives the file contract.

### CalculationService

[`CalculationService.swift`](../AssetFlow/Services/CalculationService.swift) exposes pure `Decimal` calculations. Monetary inputs and outputs are in the caller's chosen currency; return and allocation ratios have different scales.

| Call                                                            | Result contract                                                                                                                 |
| --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| `growthRate(beginValue:endValue:)`                              | `Decimal?` fraction, so `0.10` means 10%; `nil` when the beginning value is not positive.                                       |
| `modifiedDietzReturn(beginValue:endValue:cashFlows:totalDays:)` | `Decimal?` fraction; cash-flow tuples contain an amount and whole `daysSinceStart`. Invalid period or denominator yields `nil`. |
| `cumulativeTWR(periodReturns:)`                                 | `Decimal` fraction; an empty array yields zero.                                                                                 |
| `cagr(beginValue:endValue:years:)`                              | `Decimal?` fraction; `years` is a `Decimal` duration. Undefined inputs yield `nil`.                                             |
| `categoryAllocation(categoryValue:totalValue:)`                 | `Decimal` percentage on the 0–100 scale; a nonpositive total yields zero.                                                       |

The date boundaries, cash-flow signs, assumptions, and formulas belong in [`BusinessLogic.md`](BusinessLogic.md#portfolio-performance).

### RebalancingCalculator

[`RebalancingCalculator.swift`](../AssetFlow/Services/RebalancingCalculator.swift) provides `RebalancingCalculator.calculate(categories:totalValue:uncategorizedValue:) -> RebalancingPlan`. Each `CategoryGoalAllocation` carries a category UUID, name, current `Decimal` balance, optional 0–100 percentage, and optional minimum in the display currency. `totalValue` and `uncategorizedValue` use that same currency. The returned status distinguishes feasible, no-goal, invalid, and infeasible plans; only feasible plans contain actionable targets. A target retains its source allocation, target value, minimum-binding flag, difference, and current minimum shortfall.

`CategoryGoalAssessmentService` is `@MainActor` because it reads snapshot and category models. `assess(snapshot:categories:displayCurrency:)` returns optional converted totals, per-category values and minimums, independent asset and goal conversion statuses, minimum states, and an optional plan. `requiredCurrencies(categories:displayCurrency:)` includes currencies needed solely for category minimums. `convertMinimum(amount:currency:snapshot:displayCurrency:) -> Decimal?` supports historical minimum overlays without making an allocation plan; `nil` means conversion is unavailable, not a zero minimum.

`RebalancingTransferPlanner.calculate(targets:total:)` accepts feasible targets and returns typed transfers (`sourceID`, `destinationID`, `Decimal` amount), actionable category IDs, and a residual. Transfers do not mutate holdings or create cash flows. [`BusinessLogic.md`](BusinessLogic.md#rebalancing-engine) owns feasibility, funding order, precision, and residual policy.

### CurrencyConversionService

[`CurrencyConversionService.swift`](../AssetFlow/Services/CurrencyConversionService.swift) converts snapshot amounts using the selected display currency and the snapshot's exchange-rate record. Empty asset or cash-flow currency means the current display currency for conversion; it is distinct from an unavailable rate.

`totalValueReport(for:displayCurrency:exchangeRate:)` and `netCashFlowReport(for:displayCurrency:exchangeRate:)` return a `CurrencyConversionReport`:

| Field                              | Meaning                                                                                                                                                |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `convertedTotal: Decimal?`         | Complete display-currency aggregate; `nil` when a required rate is missing, wrong-base, wrong-date, or incomplete. A valid zero remains `0`.           |
| `nativeTotals: [String: Decimal]`  | Original amounts grouped by effective currency, available even when conversion is incomplete. Asset and cash-flow reports have separate native totals. |
| `status: CurrencyConversionStatus` | `.notNeeded`, `.applied`, or `.missingRates([String])`. The missing-code list is sorted.                                                               |

The convenience `totalValue` and `netCashFlow` methods return `Decimal?`; `categoryValues` returns `[String: Decimal]?`. `convert(value:from:to:using:forSnapshotDate:) -> Decimal?` and `canConvert(from:to:using:forSnapshotDate:) -> Bool` require the rate date to match the snapshot when currencies differ. Aggregate reports additionally require the rate's base currency to match the display currency and coverage for every required currency. Callers must not replace a missing converted aggregate with a partial mixed-currency sum. Asset and cash-flow availability is computed independently.

### SnapshotSummaryService

[`SnapshotSummaryService.swift`](../AssetFlow/Services/SnapshotSummaryService.swift) is `@MainActor`. Its snapshot fetch helpers accept either `ModelContext` or an injectable `ModelFetching`. Latest and latest-prior lookups use bounded fetch descriptors. Fetches throw `PersistenceError` on a SwiftData failure; an empty array or `nil` means a successful read found no matching snapshot.

`makeSummary(for:displayCurrency:)` and `makeSummaries(for:displayCurrency:)` compute shared display aggregates. The current `SnapshotSummary` type has a nonoptional `totalValue: Decimal` and nonoptional category/platform dictionaries, plus `conversionStatus` and `nativeCurrencyTotals`. When asset conversion is incomplete, this helper stores zero and empty converted dictionaries. Consumers **must check `conversionStatus`** before interpreting that zero as an available portfolio total; the underlying `CurrencyConversionReport.convertedTotal` is `nil` in that case.

### SettingsService

[`SettingsService.swift`](../AssetFlow/Services/SettingsService.swift) is an `@Observable @MainActor` singleton. Changes to `mainCurrency`, `dateFormat`, `defaultPlatform`, `platformOrder`, and `hideStaleAssets` persist immediately to `UserDefaults`. Their defaults are `USD`, `.abbreviated`, an empty platform, an empty order, and `true` respectively. `createForTesting()` creates isolated storage; `createForTesting(userDefaults:)` uses a caller-supplied store. Only the first three properties are transferred by the [backup format](#backup-interchange-format); the others remain unchanged on restore. `CurrencyService` separately caches the downloaded currency-name list in `UserDefaults`.

### Presentation and Chart Services

`RebalancingHelpPresentation` is a main-actor adapter from `CategoryGoalAssessment` and row inputs to `RebalancingHelpContent`, whose sections contain rows, bullets, and notes. `RebalancingHelpRow` keeps optional monetary currency and numeric text, formula, result flag, and suffix metadata separate from its complete display string. Optional monetary inputs preserve unavailable values. The adapter uses the assessed plan rather than recalculating allocation. [`UserInterfaceDesign.md`](UserInterfaceDesign.md) owns popover layout, currency headings, precision shown to users, and lock-aware interactions.

[`ChartDataService.swift`](../AssetFlow/Services/ChartDataService.swift) filters chart points relative to the latest point's date, rebases filtered cumulative TWR, and abbreviates axis labels. `abbreviatedLabel(for: Double)` is a display-only axis helper; monetary storage and calculations use `Decimal`. Chart presentation belongs in [`UserInterfaceDesign.md`](UserInterfaceDesign.md).

### ViewModel and Persistence Boundaries

`ImportViewModel` and `BulkEntryViewModel` are main-actor coordinators. They use async CSV preparation without changing SwiftData, then apply the confirmed mapping to the pending file's same bytes. `ImportViewModel.executeImport() -> Snapshot?` performs final validation and model changes on the main actor; it returns `nil` if import is disabled or execution fails, and reports execution errors through `importError`. Bulk Entry replaces CSV-sourced draft rows only after the replacement validates; its saved snapshot changes when the draft is saved. [`SPEC.md`](SPEC.md#41-import-flow) defines the user-facing import flow.

`ModelFetching` and `ModelContextFetcher` isolate SwiftData reads. `fetchModels(_:from:operation:)` wraps failures in `PersistenceError.fetchFailed` with the operation name. ViewModels that publish `DataLoadState` distinguish `.failed` from `.loaded` with an empty portfolio. Ordinary model edits use the shared context's autosave; restore has its own transaction boundary below. [`Architecture.md`](Architecture.md#state-observation-and-refresh) owns observation, refresh, and lifetime details.

### BackupService

[`BackupService.swift`](../AssetFlow/Services/BackupService.swift) exposes three async boundaries:

| Call                                                  | Actor and result                             | Effect                                                                                                                                 |
| ----------------------------------------------------- | -------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `exportBackup(to:modelContext:settingsService:)`      | `@MainActor async throws -> Void`            | Reads models and covered settings, serializes a v4 archive, then replaces or creates the destination after the archive is complete.    |
| `validateBackup(at:)`                                 | `nonisolated async throws -> BackupManifest` | Extracts and validates a ZIP without changing app data.                                                                                |
| `restoreFromBackup(at:modelContext:settingsService:)` | `@MainActor async throws -> Void`            | Validates first, then replaces model data and the covered settings. The source also has a defaulted checkpoint hook for restore tests. |

The main-actor façade turns SwiftData data into `Sendable` transfer records. CSV writing, extraction, parsing, and `/usr/bin/ditto` work run outside that actor. The process wrapper drains stderr while `ditto` runs and retains the last 4 KiB. Once the launched process exits, the reader stops without waiting for inherited stderr handles to close. Export failure uses the last nonempty diagnostic line, capped at 240 Unicode scalars, with an omission notice when output was shortened; extraction maps ordinary process failure to `BackupError.invalidArchive`. Cancellation terminates the launched process and completes with `CancellationError` after it exits. Errors also include `BackupError` cases for archive/layout, missing files, wrong headers, unsupported versions, validation issues, and restore failure. See [Backup Interchange Format](#backup-interchange-format) for exact bytes and compatibility.

## CSV Import Format Specification

User-import CSV is distinct from the internal CSV files in a ZIP backup. It is UTF-8 with an optional UTF-8 BOM, a comma delimiter, and a header row. Quoted fields can contain commas, doubled quotes, or newlines. Empty lines are ignored. Canonical headers are matched without regard to case or surrounding whitespace; unused columns produce warnings in the automatic header path and are skipped by a confirmed mapping. `CSVRecordReader` reports malformed structure with source row and column context.

Amounts are parsed as `Decimal` after trimming whitespace, removing the supported currency-symbol characters and comma grouping separators. A value with commas must be quoted in CSV. Invalid or absent numbers are errors; zero and negative values are accepted with the warnings below. User-import files contain no snapshot date: the importing workflow selects the date.

### Asset CSV

| Canonical column | Requirement | Value                                                                                                                                                                                                         |
| ---------------- | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Asset Name`     | Required    | Nonempty asset name.                                                                                                                                                                                          |
| `Market Value`   | Required    | `Decimal` monetary amount; zero or negative values produce warnings.                                                                                                                                          |
| `Platform`       | Optional    | Asset platform; an import-level platform and its apply mode can change the effective platform.                                                                                                                |
| `Currency`       | Optional    | Asset currency code; a blank value preserves an existing asset currency or uses the display currency for a new asset's conversion. The import workflow validates nonblank codes against supported currencies. |

`Asset Name` and `Platform` form the normalized asset identity after platform handling. See [`BusinessLogic.md`](BusinessLogic.md#duplicate-and-replacement-policy) for duplicate and zero-placeholder policy.

```csv
Asset Name,Market Value,Platform,Currency
AAPL,"15,000.25",Interactive Brokers,USD
TSMC,500000,Fubon,TWD
```

### Cash Flow CSV

| Canonical column | Requirement | Value                                                                                                                                                                                           |
| ---------------- | ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Description`    | Required    | Nonempty cash-flow description.                                                                                                                                                                 |
| `Amount`         | Required    | `Decimal` amount; positive is an external contribution, negative a withdrawal, and zero produces a warning.                                                                                     |
| `Currency`       | Optional    | Operation currency code; blank uses the display currency for conversion. The current cash-flow import does not reject a nonblank code solely because it is absent from the app's currency list. |

Descriptions are checked for duplicates within the CSV and against the target snapshot. [`BusinessLogic.md`](BusinessLogic.md#duplicate-and-replacement-policy) owns the conflict rule.

```csv
Description,Amount,Currency
External contribution,50000,TWD
External withdrawal,-10000,TWD
```

### Column Mapping

`CSVParsingService.autoDetectMapping(headers:schema:)` matches canonical columns case-insensitively after trimming surrounding whitespace. If all required columns are found, preparation parses immediately. Otherwise it returns `.needsMapping` with raw headers, sample rows, and a partial mapping. The user confirms a `CSVColumnMapping` from canonical columns to original column indices; every required field must be assigned once. The same flow is used by Import and Bulk Entry, including Bulk Entry's `.assetWithoutPlatform` schema. Confirmation reparses the pending file with that mapping. It does not change the source CSV or make arbitrary headers canonical for later files.

Raw duplicate candidates and row diagnostics survive mapping. Import and Bulk Entry then validate the effective included rows using their respective platform and snapshot context. A blocking error prevents the operation; a warning alone does not.

## Backup Interchange Format

The current export format is **v4**. Restore accepts **v1–v4**. [`BackupTypes.swift`](../AssetFlow/Services/BackupTypes.swift) defines transfer records and ordered headers; [`BackupService+Export.swift`](../AssetFlow/Services/BackupService+Export.swift) writes them; [`BackupService+Parsing.swift`](../AssetFlow/Services/BackupService+Parsing.swift) chooses headers by manifest version.

### Archive and Manifest

The canonical ZIP places `manifest.json` and CSV files at its root. Restore also accepts one immediate enclosing directory containing the manifest. It does not recursively search deeper or choose between multiple candidate backup roots.

`manifest.json` exports `formatVersion` (integer), `exportTimestamp` (ISO 8601 timestamp with timezone), and `appVersion` (nonempty string). The exporter uses `ISO8601DateFormatter`. Restore accepts valid Internet-date-time timestamps with `Z` or a numeric timezone, including fractional seconds. Missing or mistyped required JSON keys fail decoding; additional manifest keys are ignored by the decoder. An unsupported `formatVersion` is rejected.

For example, a v4 manifest can contain:

```json
{"formatVersion":4,"exportTimestamp":"2026-10-14T10:30:00Z","appVersion":"0.7.1"}
```

The six portfolio and settings CSV files below are required for every supported version. `exchange_rates.csv` is exported in v4, is optional on restore for v3/v4, and is not accepted for v1/v2. An absent optional rate file restores no stored rates; it does not invent rates.

### Exact Ordered CSV Headers

Headers are case-sensitive and ordered. A v4 export uses these exact header lines:

| File                        | v4 header                                                                                     |
| --------------------------- | --------------------------------------------------------------------------------------------- |
| `categories.csv`            | `id,name,targetAllocationPercentage,displayOrder,minimumBalanceAmount,minimumBalanceCurrency` |
| `assets.csv`                | `id,name,platform,categoryID,currency`                                                        |
| `snapshots.csv`             | `id,date,createdAt`                                                                           |
| `snapshot_asset_values.csv` | `snapshotID,assetID,marketValue`                                                              |
| `cash_flow_operations.csv`  | `id,snapshotID,description,amount,currency`                                                   |
| `settings.csv`              | `key,value`                                                                                   |
| `exchange_rates.csv`        | `snapshotID,baseCurrency,fetchDate,isFallback,ratesJSON`                                      |

For v1–v3 restore, use the v4 header above unless the file and version appear here. These are the complete replacement header lines:

| Restore version | File                       | Header instead of v4                              |
| --------------- | -------------------------- | ------------------------------------------------- |
| v1              | `categories.csv`           | `id,name,targetAllocationPercentage`              |
| v2–v3           | `categories.csv`           | `id,name,targetAllocationPercentage,displayOrder` |
| v1–v2           | `assets.csv`               | `id,name,platform,categoryID`                     |
| v1–v2           | `cash_flow_operations.csv` | `id,snapshotID,description,amount`                |

`exchange_rates.csv` is not accepted in v1/v2. In v3 it may be absent; when present, its header is the v4 header above. Thus each supported version has an exact header for every accepted file without relying on model-property names.

The cash-flow backup field is `description` even though the SwiftData model property is `cashFlowDescription`. Restoring v1 categories supplies `displayOrder = 0`. Restoring pre-v4 categories supplies no minimum amount or currency. Restoring v1/v2 assets and cash flows supplies an empty currency, which retains display-currency inheritance.

### Field Encoding and Settings

The writer uses UTF-8 CSV with LF record separators. Text containing a comma, quote, CR, or LF is quoted, with quotes doubled. The shared reader also accepts CRLF records and a trailing empty field. UUIDs use their standard string form. Snapshot and rate dates use ISO 8601 timestamps with timezone. Monetary values, target percentages, and rates remain `Decimal` values; the CSV writer emits decimal text without display rounding, while restore accepts strict numeric decimal text, including an exponent, without currency symbols or grouping separators. `targetAllocationPercentage` is on the 0–100 scale.

An empty field represents an absent optional `categoryID`, target percentage, or v4 minimum pair. Empty asset and cash-flow currency strings are meaningful inherited-currency values. The v4 minimum amount and currency must both be empty or form a valid pair. `isFallback` is the lowercase literal `true` or `false`. `ratesJSON` is base64-encoded JSON for a nonempty `[String: Decimal]` rate dictionary with positive finite values; a restored fallback flag does not itself establish an active stale-rate fallback.

`settings.csv` contains exactly one row for each key:

| Key               | Value                                           | Restore effect                          |
| ----------------- | ----------------------------------------------- | --------------------------------------- |
| `displayCurrency` | Nonempty currency string                        | Sets `SettingsService.mainCurrency`.    |
| `dateFormat`      | `numeric`, `abbreviated`, `long`, or `complete` | Sets `SettingsService.dateFormat`.      |
| `defaultPlatform` | String, which may be empty                      | Sets `SettingsService.defaultPlatform`. |

For example, a valid `settings.csv` for an empty default platform is:

```csv
key,value
displayCurrency,USD
dateFormat,abbreviated
defaultPlatform,
```

Unknown, missing, or duplicate settings keys are rejected. Other preferences, including platform order, stale-asset visibility, app-lock settings, and the cached currency list, are not exported and remain unchanged on restore. Other archive entries are not imported as model data. An exchange-rate file in v1/v2, wrong-version CSV headers, and invalid required fields are rejected; extra manifest keys do not extend the format.

### Validation and Restore Boundary

Restore extracts the ZIP with `/usr/bin/ditto` before parsing. It then requires each named file to be a regular, nonsymlink file, limits `manifest.json` to 1 MiB and each CSV to 128 MiB, and checks UTF-8, exact headers, record arity, scalar values, IDs, normalized identities, and cross-file references. These are **post-extraction per-file checks**; they do not impose a pre-extraction ZIP-size or total expansion limit. [`SecurityAndPrivacy.md`](SecurityAndPrivacy.md) owns archive threat analysis and limits.

Validation produces typed transfer records. Syntax, archive, file, and header failures can stop immediately; recoverable row issues are collected with file, row, and column context. `validateBackup(at:)` returns the manifest only after the whole backup validates. It never mutates app data.

`restoreFromBackup` validates before changing the live graph. It saves any already-pending `ModelContext` changes as a rollback point, suspends autosave, and replaces the graph in a main-actor transaction. A deletion, insertion, or save failure rolls the context back to that point; backed-up `UserDefaults` settings are applied only after the transaction succeeds. Thus a failed restore does not apply replacement records or backed-up settings, though the preexisting pending context changes may have been saved at the checkpoint. Export writes a temporary archive and moves or replaces the destination only after ZIP creation succeeds.

## Exchange Rate Integration

### ExchangeRateService

[`ExchangeRateService.swift`](../AssetFlow/Services/ExchangeRateService.swift) is a stateful `@unchecked Sendable` service with an injectable `URLSession` and shared request coordinator. It uses these provider paths:

| Request                 | URL and response                                                                                                                                                                     |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Rates for date and base | `https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@{YYYY-MM-DD}/v1/currencies/{base}.min.json` → JSON with `date` and a base-code object mapping target codes to numeric rates. |
| Currency names          | `https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies.min.json` → JSON mapping currency codes to names.                                                       |

`fetchRates(for:baseCurrency:) async throws -> [String: Decimal]` lowercases the base, formats the requested date from Gregorian calendar components in the service's current timezone, and decodes rates directly as `Decimal`. It requires a successful HTTP response, an exact response-date match, a base-code object, and nonempty positive finite rates. A 404 yields `ExchangeRateError.ratesNotFound`; other network or response failures use the service's typed errors. There is no app-specific timeout override; the injected session supplies request behavior.

Requests with the same date/base key share in-flight work. Each caller retains its own cancellation: cancelling one waiter does not cancel another, and cancelling the last waiter cancels the network task. A cancelled caller checks cancellation before accepting a result.

`fetchMissingRates(snapshots:displayCurrency:modelContext:) async -> [ExchangeRateFetchResult]` runs on the main actor because it reads categories and updates `ExchangeRate` models. It includes non-display asset, cash-flow, and configured goal-minimum currencies in each snapshot's requirements. A stored rate is reused only if its base currency, Gregorian snapshot date, and coverage of every required currency are valid. Otherwise snapshots are fetched sequentially and a valid record is inserted or refreshed. Each visited snapshot receives `.notNeeded`, `.cached`, `.fetched`, `.failed(message)`, or `.cancelled`. A category-fetch failure yields failed results for the input snapshots; cancellation during the loop stops it, so later snapshots have no result. The current app-shell and post-restore callers discard these result values; dependent conversions still expose missing-rate status through their own reports.

`fetchCurrencyList() async throws -> [String: String]` supplies [`CurrencyService.swift`](../AssetFlow/Services/CurrencyService.swift). That main-actor observable service starts with a cached list or built-in fallback and keeps the existing list if loading fails; success updates the `UserDefaults` cache. Snapshot rates remain separate SwiftData records. Failed or unavailable rate requests never justify substituting another date's rate. [`BusinessLogic.md`](BusinessLogic.md#currency-conversion) defines the resulting calculation availability.

## Error Handling Patterns

The boundary determines how an error is represented:

| Boundary                               | Failure contract                                                                                                                                                                      |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Synchronous user CSV parsing           | `CSVParseResult.errors` and `warnings`; malformed records and rows carry localized diagnostics.                                                                                       |
| Async file read and CSV preparation    | Throws for file access or cancellation; ordinary parse problems remain in `CSVParseResult`.                                                                                           |
| Model fetch                            | Throws `PersistenceError` with operation context; no-record is a successful empty result.                                                                                             |
| Calculation and conversion             | Undefined or unavailable results use `nil` or a typed status; zero remains a valid number.                                                                                            |
| Exchange-rate fetching                 | Individual requests throw; batch results carry per-snapshot statuses for visited snapshots.                                                                                           |
| Backup export, validation, and restore | Throw on persistence, I/O, validation, or cancellation; backup-format failures use `BackupError`, whose validation issues identify the affected file, row, and column when available. |

ViewModels translate these contracts into screen state. A persistence failure must not be treated as an empty portfolio, and a missing rate must not be treated as a zero amount. [`UserInterfaceDesign.md`](UserInterfaceDesign.md) owns user-facing placement and wording; [`SecurityAndPrivacy.md`](SecurityAndPrivacy.md) owns sensitive-data logging rules.

## App Version and Build Metadata

`Constants.AppInfo` reads `CFBundleShortVersionString`, `CFBundleVersion`, and custom `AppCommit` from the built app's `Info.plist`. The backup manifest records the runtime app version as `appVersion`; its separate `formatVersion` governs archive compatibility. [`DevelopmentGuide.md`](DevelopmentGuide.md#app-version-metadata) owns version synchronization, build-phase injection, and release procedures.

## References

- [`SPEC.md`](SPEC.md) — intended product behavior and acceptance criteria
- [`Architecture.md`](Architecture.md) — service lifetimes, actor boundaries, and refresh
- [`BusinessLogic.md`](BusinessLogic.md) — calculations, import policy, and rebalancing
- [`DataModel.md`](DataModel.md) — stored entity definitions
- [`UserInterfaceDesign.md`](UserInterfaceDesign.md) — import and presentation interactions
- [`SecurityAndPrivacy.md`](SecurityAndPrivacy.md) — file and network trust boundaries
