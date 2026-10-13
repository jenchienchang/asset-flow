# Data Model

AssetFlow stores portfolio state as dated snapshots, not as a transaction ledger. This document defines the six SwiftData entities, their relationships, and the integrity and migration rules for the stored graph. [SPEC.md](SPEC.md) defines intended product behavior, [BusinessLogic.md](BusinessLogic.md) owns calculations and allocation policy, and [APIDesign.md](APIDesign.md) owns backup and CSV formats.

## Persistence Boundaries

| Data                                                                           | Storage                                                              | Boundary                                                                                             |
| ------------------------------------------------------------------------------ | -------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| Categories, assets, snapshots, recorded values, cash flows, exchange rates     | SwiftData, using `CurrentSchema.schema`                              | The six versioned models below form the persistent portfolio graph.                                  |
| Display preferences, platform order, stale-asset visibility, app-lock settings | `UserDefaults` through `SettingsService` and `AuthenticationService` | These are not SwiftData models. The backup format includes only some preferences.                    |
| Downloaded currency list                                                       | `UserDefaults` through `CurrencyService`                             | A reusable currency-list cache, separate from snapshot exchange-rate records.                        |
| Decoded exchange-rate dictionary                                               | `ExchangeRate._cachedRates`, marked `@Transient`                     | An in-memory cache rebuilt from persisted `ratesJSON` and cleared on rate updates.                   |
| Backup manifest and records                                                    | ZIP transfer data produced by `BackupService`                        | A serialized copy of selected data, not a second live model store; see [APIDesign.md](APIDesign.md). |

Money amounts, percentage targets, and exchange rates use `Decimal`; no model stores monetary values as `Float` or `Double`. A target percentage is stored on the 0–100 scale, while a minimum amount is denominated in its paired currency. Asset and cash-flow currencies are strings; an empty string means that conversion uses the current display currency. This inherited currency is distinct from a missing exchange rate. See [BusinessLogic.md](BusinessLogic.md) for conversion and result-availability rules.

`UUID` properties identify Category, Asset, Snapshot, and CashFlowOperation records in application and backup data. `SnapshotAssetValue` and `ExchangeRate` use relationships for their identity in the graph. SwiftData also gives persistent models its own `persistentModelID`; the `#Unique` declarations below identify the actual model-level uniqueness keys. Portfolio totals, converted values, net cash flow, category assessments, and rebalancing targets are derived rather than stored.

## Entities

### Category

A Category groups assets and retains the user's display order. A category may have a percentage target, a currency-denominated minimum, both, or neither. See [Category.swift](../AssetFlow/Models/Category.swift).

| Property                     | Type       | Stored meaning                             | Initial value                       |
| ---------------------------- | ---------- | ------------------------------------------ | ----------------------------------- |
| `id`                         | `UUID`     | Application identifier                     | New UUID                            |
| `name`                       | `String`   | Display name                               | Required initializer argument       |
| `targetAllocationPercentage` | `Decimal?` | Percentage target, 0–100 when present      | `nil`                               |
| `minimumBalanceAmount`       | `Decimal?` | Minimum amount in `minimumBalanceCurrency` | `nil`                               |
| `minimumBalanceCurrency`     | `String?`  | Original currency of the minimum           | `nil`                               |
| `displayOrder`               | `Int`      | User-defined category order                | `0`                                 |
| `assets`                     | `[Asset]?` | Inverse of `Asset.category`                | Empty collection in the initializer |

Application validation requires a nonempty name, checks name conflicts without case, and validates a present percentage as finite and within 0–100. Minimum amount and currency must be present together or both absent. A present minimum must be finite and nonnegative; zero is valid. The category editing path stores the selected currency in uppercase and preserves that denomination when display currency changes. These are application-enforced invariants, not guarantees implied by the optional Swift properties alone. See [CategoryGoalValidator.swift](../AssetFlow/Services/CategoryGoalValidator.swift).

A category with a minimum and no percentage still participates in goal assessment. An absent percentage protects its current balance or minimum during allocation; it does not simply remove the category from the calculation. No goal mode, effective target, or goal history is stored. [BusinessLogic.md](BusinessLogic.md#rebalancing-engine) owns the allocation rules.

### Asset

An Asset persists across snapshots and is identified for import matching by its name and platform. See [Asset.swift](../AssetFlow/Models/Asset.swift).

| Property              | Type                    | Stored meaning                                                  | Initial value                       |
| --------------------- | ----------------------- | --------------------------------------------------------------- | ----------------------------------- |
| `id`                  | `UUID`                  | Application identifier                                          | New UUID                            |
| `name`                | `String`                | Asset name                                                      | Required initializer argument       |
| `platform`            | `String`                | Platform or brokerage; empty means none                         | `""`                                |
| `currency`            | `String`                | Native currency; empty inherits display currency for conversion | `""`                                |
| `category`            | `Category?`             | Optional category assignment                                    | `nil`                               |
| `snapshotAssetValues` | `[SnapshotAssetValue]?` | Recorded values across snapshots                                | Empty collection in the initializer |

Application matching uses `normalizedForIdentity` on both name and platform: it trims outer whitespace, collapses internal whitespace, and lowercases the result. The model's `#Unique` key uses the stored name and platform properties; it does not itself express this normalization. [BusinessLogic.md](BusinessLogic.md#asset-identity-and-matching) owns matching and rename behavior.

The initializer accepts `name` and `platform`; currency can be assigned afterward in a main-actor model operation:

```swift
@MainActor
func makeAsset() -> Asset {
  let asset = Asset(name: "AAPL", platform: "Brokerage")
  asset.currency = "USD"
  return asset
}
```

### Snapshot

A Snapshot represents the portfolio state recorded for one calendar date. See [Snapshot.swift](../AssetFlow/Models/Snapshot.swift).

| Property             | Type                    | Stored meaning                                                                      | Initial value                       |
| -------------------- | ----------------------- | ----------------------------------------------------------------------------------- | ----------------------------------- |
| `id`                 | `UUID`                  | Application identifier                                                              | New UUID                            |
| `date`               | `Date`                  | Snapshot date, normalized by the initializer to `Calendar.current.startOfDay(for:)` | Required initializer argument       |
| `createdAt`          | `Date`                  | Creation timestamp                                                                  | `Date()`                            |
| `assetValues`        | `[SnapshotAssetValue]?` | Direct asset records at this date                                                   | Empty collection in the initializer |
| `cashFlowOperations` | `[CashFlowOperation]?`  | External flows assigned to this date                                                | Empty collection in the initializer |
| `exchangeRate`       | `ExchangeRate?`         | Optional rate record for this date                                                  | `nil`                               |

`date` remains a `Date` value representing local start of day, not a date-only storage type. `#Unique<Snapshot>([\.date])` allows at most one snapshot for that stored date. The creation and import flows reject future dates; that restriction is application validation, not a property type constraint. Multiple permitted imports can add records to an existing date. A snapshot can omit an asset altogether or contain an explicit zero-valued `SnapshotAssetValue`; those states differ. See [SPEC.md](SPEC.md#8-snapshot-lifecycle) for lifecycle behavior.

### SnapshotAssetValue

A SnapshotAssetValue records one asset's market value in one snapshot, forming the join between Asset and Snapshot. See [SnapshotAssetValue.swift](../AssetFlow/Models/SnapshotAssetValue.swift).

| Property      | Type        | Stored meaning                                                                    | Initial value                 |
| ------------- | ----------- | --------------------------------------------------------------------------------- | ----------------------------- |
| `marketValue` | `Decimal`   | Value in the linked asset's currency, or display currency when that code is empty | Required initializer argument |
| `snapshot`    | `Snapshot?` | Parent snapshot                                                                   | `nil` until linked            |
| `asset`       | `Asset?`    | Valued asset                                                                      | `nil` until linked            |

The model declares `#Unique<SnapshotAssetValue>([\.snapshot, \.asset])`: a valid saved graph has at most one value for an asset in a snapshot. The Swift properties are optional so an object may be unlinked while it is being constructed; application flows and backup graph validation require both links for a meaningful recorded value. Zero is a stored value, not absence. Negative values are allowed for liabilities or short positions. Import handling of zero placeholders is defined in [SPEC.md](SPEC.md#46-duplicate-detection).

### CashFlowOperation

A CashFlowOperation records an external contribution or withdrawal at a snapshot date. See [CashFlowOperation.swift](../AssetFlow/Models/CashFlowOperation.swift).

| Property              | Type        | Stored meaning                                                  | Initial value                 |
| --------------------- | ----------- | --------------------------------------------------------------- | ----------------------------- |
| `id`                  | `UUID`      | Application identifier                                          | New UUID                      |
| `cashFlowDescription` | `String`    | Description within its snapshot                                 | Required initializer argument |
| `amount`              | `Decimal`   | Positive contribution; negative withdrawal                      | Required initializer argument |
| `currency`            | `String`    | Native currency; empty inherits display currency for conversion | `""`                          |
| `snapshot`            | `Snapshot?` | Parent snapshot                                                 | `nil` until linked            |

The property is named `cashFlowDescription` in Swift; backup transfer data uses `description`. `#Unique<CashFlowOperation>([\.snapshot, \.cashFlowDescription])` declares the stored-property key. Application paths also check duplicate descriptions without case; the macro alone does not specify that comparison. A valid saved operation is linked to one snapshot, although its Swift property is optional during construction. Net cash flow is derived from operations with currency conversion where needed; [BusinessLogic.md](BusinessLogic.md#net-cash-flow) defines its timing and calculation.

### ExchangeRate

An ExchangeRate stores rates applicable to a snapshot date. See [ExchangeRate.swift](../AssetFlow/Models/ExchangeRate.swift).

| Property       | Type        | Stored meaning                                                 | Initial value                 |
| -------------- | ----------- | -------------------------------------------------------------- | ----------------------------- |
| `baseCurrency` | `String`    | Base currency code, stored lowercase by the current fetch path | Required initializer argument |
| `ratesJSON`    | `Data`      | JSON-encoded `[String: Decimal]` rates                         | Required initializer argument |
| `fetchDate`    | `Date`      | Date to which the rates apply                                  | Required initializer argument |
| `isFallback`   | `Bool`      | Stored fallback flag retained in model and backup data         | `false`                       |
| `snapshot`     | `Snapshot?` | Parent snapshot                                                | `nil` until linked            |

Each rate represents units of that currency per one base-currency unit; the base currency has an implicit rate of one. `rates` decodes `ratesJSON` into a lowercased dictionary and caches it in the `@Transient` `_cachedRates` property; a decode failure yields an empty dictionary.

`updateRates(baseCurrency:ratesJSON:fetchDate:)` updates the stored fields, clears that cache, and sets `isFallback` to `false`. The current fetch path creates or refreshes records with the flag false; a restored backup can retain its stored value. The flag does not establish an active stale-rate fallback path.

The model's `convert(value:from:to:)` uses positive finite cross-rates and returns `nil` when a required rate is unusable. `matchesDate(_:timeZone:)` compares Gregorian calendar days, and `supportsAll(_:)` checks currency coverage. The service additionally requires the appropriate base currency, snapshot date, and coverage before reusing a record or presenting a converted aggregate. A wrong-date or incomplete record is unavailable for that purpose; see [CurrencyConversionService.swift](../AssetFlow/Services/CurrencyConversionService.swift) and [ExchangeRateService.swift](../AssetFlow/Services/ExchangeRateService.swift).

## Relationships and Integrity

### Entity Relationship Diagram

```text
Category ←── optional category ── Asset
Asset ←── one asset ── SnapshotAssetValue ── one snapshot ──→ Snapshot
Snapshot ── zero or more ──→ CashFlowOperation
Snapshot ── zero or one ───→ ExchangeRate
```

Each SnapshotAssetValue connects one Asset to one Snapshot in a valid saved graph, so Asset and Snapshot have a many-to-many relationship through that entity. The parent links on SnapshotAssetValue, CashFlowOperation, and ExchangeRate are declared optional to allow construction before linking; the cardinalities above describe valid application data, not nonoptional Swift types.

| Declared relationship                                        | Cardinality in valid application data        | Configured delete rule                                       |
| ------------------------------------------------------------ | -------------------------------------------- | ------------------------------------------------------------ |
| `Category.assets` ↔ `Asset.category`                         | Category: 0–many assets; Asset: 0–1 category | `.deny` on `Category.assets`; `.nullify` on `Asset.category` |
| `Asset.snapshotAssetValues` ↔ `SnapshotAssetValue.asset`     | Asset: 0–many values; value: one asset       | `.deny` on `Asset.snapshotAssetValues`                       |
| `Snapshot.assetValues` ↔ `SnapshotAssetValue.snapshot`       | Snapshot: 0–many values; value: one snapshot | `.cascade` on `Snapshot.assetValues`                         |
| `Snapshot.cashFlowOperations` ↔ `CashFlowOperation.snapshot` | Snapshot: 0–many flows; flow: one snapshot   | `.cascade` on `Snapshot.cashFlowOperations`                  |
| `Snapshot.exchangeRate` ↔ `ExchangeRate.snapshot`            | Snapshot: 0–1 rate; rate: one snapshot       | `.cascade` on `Snapshot.exchangeRate`                        |

The rule is configured on a particular relationship; it applies when deleting a model that contains references through that relationship. Inverse-side rules cannot be dismissed as universally meaningless. [Apple's SwiftData delete-rule reference](https://developer.apple.com/documentation/swiftdata/schema/relationship/deleterule-swift.enum) defines the rule directions. Snapshot declares `.cascade` for its values, cash flows, and rate record. [SwiftDataRelationshipTests.swift](../AssetFlowTests/Integration/SwiftDataRelationshipTests.swift) asserts value and cash-flow cascades and that deleting one snapshot preserves its Assets and other snapshots' values.

Application deletion paths also guard `.deny` relationships: [CategoryListViewModel.swift](../AssetFlow/ViewModels/CategoryListViewModel.swift) refuses to delete a category with assigned assets, and [AssetListViewModel.swift](../AssetFlow/ViewModels/AssetListViewModel.swift) refuses to delete an asset with snapshot values. Those guards enforce the app's deletion rules and provide user-facing errors. Restore deletes related records in dependency order; see [BackupService+Restore.swift](../AssetFlow/Services/BackupService+Restore.swift).

### Uniqueness and Valid-Graph Rules

| Model              | Declared `#Unique` key            | Additional application rule                                                    |
| ------------------ | --------------------------------- | ------------------------------------------------------------------------------ |
| Category           | `name`                            | Nonempty; case-insensitive name conflict check                                 |
| Asset              | `name`, `platform`                | Match and reject conflicts using normalized identity                           |
| Snapshot           | `date`                            | Normalize to local start of day; reject future creation dates                  |
| SnapshotAssetValue | `snapshot`, `asset`               | Link both parents; one direct value per asset and snapshot                     |
| CashFlowOperation  | `snapshot`, `cashFlowDescription` | Link a snapshot; check descriptions without case                               |
| ExchangeRate       | No `#Unique` declaration          | At most one rate through the snapshot's to-one relationship; link its snapshot |

These declared keys are not substitutes for validation before mutation. In particular, a `#Unique` declaration does not encode the application's text normalization. The graph rules describe app-created and validated backup data; the optional relationship properties do not alone prohibit an unlinked object from existing during construction. See [BackupService+GraphValidation.swift](../AssetFlow/Services/BackupService+GraphValidation.swift) for restore-time reference checks.

## Schema, Migration, and Preservation

[SchemaVersioning.swift](../AssetFlow/Models/SchemaVersioning.swift) defines `SchemaV1` (1.0.0), `SchemaV2` (2.0.0), `CurrentSchema`, and `AssetFlowMigrationPlan`. V1's six historical model definitions live in the frozen [SchemaV1Models.swift](../AssetFlow/Models/SchemaV1Models.swift). V2 registers the six current models and adds optional Category minimum amount and currency fields. The plan contains a lightweight V1→V2 stage; migrated categories have no minimum until one is set.

[AssetFlowApp.swift](../AssetFlow/AssetFlowApp.swift) creates the normal disk-backed `ModelContainer` with `CurrentSchema.schema` and `AssetFlowMigrationPlan.self`. A Debug `--preview-data` launch uses an in-memory configuration for disposable sample data. Tests likewise use isolated memory containers or disposable disk stores; these are separate from the user's persistent store. If the app cannot open its database, it shows a database error and exits after dismissal. It does not delete or recreate that store as a compatibility fallback.

[CategoryGoalMigrationTests.swift](../AssetFlowTests/Integration/CategoryGoalMigrationTests.swift) creates disposable V1 disk graphs, opens them through the migration plan, checks identities and relationships, and reopens a V2 graph after adding a minimum. This supports the documented V1→V2 path; it does not prove that every possible future schema change will migrate automatically. Future released-schema changes require an explicit versioning and migration assessment while preserving historical definitions. [DevelopmentGuide.md](DevelopmentGuide.md#working-with-swiftdata) owns the contributor procedure for model changes.

Current queries fetch snapshots by normalized date and read value history through `Asset.snapshotAssetValues`; the models declare no indexes. See [SnapshotListViewModel.swift](../AssetFlow/ViewModels/SnapshotListViewModel.swift) and [AssetDetailViewModel.swift](../AssetFlow/ViewModels/AssetDetailViewModel.swift). Query and context usage procedures belong in [DevelopmentGuide.md](DevelopmentGuide.md#working-with-swiftdata).

## Backup Mapping

Backup transfer records carry entity UUIDs and relationship references rather than persisting duplicate foreign-key properties on the SwiftData models. For example, `Asset.category` maps to a category UUID, and a cash flow's Swift `cashFlowDescription` maps to a transfer field named `description`. Snapshot and rate dates serialize as ISO 8601 timestamps, not date-only strings. The current backup format is v4, distinct from SwiftData SchemaV2; it includes Category minimum amount and currency. Restore of v1–v3 backups leaves those minimums absent, while v4 retains the currency and exchange-rate data introduced in v3.

The format transfers only the documented settings subset; other UserDefaults preferences and the currency-list cache are outside the model graph. [APIDesign.md](APIDesign.md#backupservice) owns exact headers, field order, null representation, archive layout, and restore compatibility. [BackupTypes.swift](../AssetFlow/Services/BackupTypes.swift) and [BackupService+Export.swift](../AssetFlow/Services/BackupService+Export.swift) define the current transfer records and writer.
