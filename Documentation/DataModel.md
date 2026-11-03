# Data Model

AssetFlow stores portfolio state as dated snapshots, not as a transaction ledger. This document defines the seven SwiftData entities, their relationships, and the integrity and migration rules for the stored graph. [`SPEC.md`](SPEC.md) defines intended product behavior, [`BusinessLogic.md`](BusinessLogic.md) owns calculations and allocation policy, and [`APIDesign.md`](APIDesign.md) owns backup and CSV formats.

## Persistence Boundaries

| Data                                                                                  | Storage                                                              | Boundary                                                                                               |
| ------------------------------------------------------------------------------------- | -------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| Platforms, categories, assets, snapshots, recorded values, cash flows, exchange rates | SwiftData, using `CurrentSchema.schema`                              | The seven versioned models below form the persistent portfolio graph.                                  |
| Display preferences, stale-asset visibility, app-lock settings                        | `UserDefaults` through `SettingsService` and `AuthenticationService` | These are not SwiftData models. The backup format includes only some preferences.                      |
| Downloaded currency list                                                              | `UserDefaults` through `CurrencyService`                             | A reusable currency-list cache, separate from snapshot exchange-rate records.                          |
| Decoded exchange-rate dictionary                                                      | `ExchangeRate._cachedRates`, marked `@Transient`                     | An in-memory cache rebuilt from persisted `ratesJSON` and cleared on rate updates.                     |
| Backup manifest and records                                                           | ZIP transfer data produced by `BackupService`                        | A serialized copy of selected data, not a second live model store; see [`APIDesign.md`](APIDesign.md). |

Money amounts, percentage targets, and exchange rates use `Decimal`; no model stores monetary values as `Float` or `Double`. A target percentage is stored on the 0–100 scale, while a minimum amount is denominated in its paired currency. Asset and cash-flow currencies are strings; an empty string means that conversion uses the current display currency. This inherited currency is distinct from a missing exchange rate. See [`BusinessLogic.md`](BusinessLogic.md) for conversion and result-availability rules.

`UUID` properties identify Platform, Category, Asset, Snapshot, and CashFlowOperation records in application and backup data. `SnapshotAssetValue` and `ExchangeRate` use relationships for their identity in the graph. SwiftData also gives persistent models its own `persistentModelID`; the `#Unique` declarations below identify the actual model-level uniqueness keys. Portfolio totals, converted values, net cash flow, category assessments, and rebalancing targets are derived rather than stored.

## Entities

### Category

A Category groups assets and retains the user's display order. A category may have a percentage target, a currency-denominated minimum, both, or neither. See [`Category.swift`](../AssetFlow/Models/Category.swift).

| Property                     | Type       | Stored meaning                             | Initial value                       |
| ---------------------------- | ---------- | ------------------------------------------ | ----------------------------------- |
| `id`                         | `UUID`     | Application identifier                     | New UUID                            |
| `name`                       | `String`   | Display name                               | Required initializer argument       |
| `targetAllocationPercentage` | `Decimal?` | Percentage target, 0–100 when present      | `nil`                               |
| `minimumBalanceAmount`       | `Decimal?` | Minimum amount in `minimumBalanceCurrency` | `nil`                               |
| `minimumBalanceCurrency`     | `String?`  | Original currency of the minimum           | `nil`                               |
| `displayOrder`               | `Int`      | User-defined category order                | `0`                                 |
| `assets`                     | `[Asset]?` | Inverse of `Asset.category`                | Empty collection in the initializer |

Application validation requires a nonempty name, checks name conflicts without case, and validates a present percentage as finite and within 0–100. Minimum amount and currency must be present together or both absent. A present minimum must be finite and nonnegative; zero is valid. The category editing path stores the selected currency in uppercase and preserves that denomination when display currency changes. These are application-enforced invariants, not guarantees implied by the optional Swift properties alone. See [`CategoryGoalValidator.swift`](../AssetFlow/Services/CategoryGoalValidator.swift).

A category with a minimum and no percentage still participates in goal assessment. An absent percentage protects its current balance or minimum during allocation; it does not simply remove the category from the calculation. No goal mode, effective target, or goal history is stored. [`BusinessLogic.md`](BusinessLogic.md#rebalancing-engine) owns the allocation rules.

### Platform

A Platform identifies a brokerage, bank, exchange, or other custodian independently of its display name. See [`Platform.swift`](../AssetFlow/Models/Platform.swift).

| Property         | Type       | Stored meaning                                                    | Initial value                     |
| ---------------- | ---------- | ----------------------------------------------------------------- | --------------------------------- |
| `id`             | `UUID`     | Stable application and backup identifier                          | New UUID                          |
| `name`           | `String`   | Display name with collapsed whitespace                            | Required initializer argument     |
| `normalizedName` | `String`   | Unique trimmed, collapsed, lowercased name                        | Derived from name                 |
| `displayOrder`   | `Int`      | User ordering; unseen platforms sort afterward by normalized name | `0`; resolution assigns `Int.max` |
| `assets`         | `[Asset]?` | Inverse of `Asset.platformRecord`                                 | Empty collection                  |

`PlatformService` resolves names and validates renames before mutation. Display and normalized names change together; neither has a public setter. A rename preserves UUID, asset assignments, and order. See [`APIDesign.md`](APIDesign.md#platform-operations) for the rename mutation contract. Empty records remain stored but are hidden from platform lists and pickers; resolving their names reuses them. Deletion is denied while assets reference the platform. Totals and history are calculated, not stored on Platform.

### Asset

An Asset persists across snapshots and is identified for import matching by its name and platform. See [`Asset.swift`](../AssetFlow/Models/Asset.swift).

| Property              | Type                    | Stored meaning                                                        | Initial value                       |
| --------------------- | ----------------------- | --------------------------------------------------------------------- | ----------------------------------- |
| `id`                  | `UUID`                  | Application identifier                                                | New UUID                            |
| `identityKey`         | `String`                | Normalized name scoped by stable platform UUID, or explicit nil scope | Derived in initializer              |
| `name`                | `String`                | Asset name                                                            | Required initializer argument       |
| `platformRecord`      | `Platform?`             | Optional persisted custodian relationship; nil means none             | `nil`                               |
| `currency`            | `String`                | Native currency; empty inherits display currency for conversion       | `""`                                |
| `category`            | `Category?`             | Optional category assignment                                          | `nil`                               |
| `snapshotAssetValues` | `[SnapshotAssetValue]?` | Recorded values across snapshots                                      | Empty collection in the initializer |

Text input uses `normalizedForIdentity` to trim outer whitespace, collapse internal whitespace, and lowercase names. Platform text resolves to a record; matching persisted assets then uses normalized asset name and optional platform UUID. Derived platform groups, totals, and history also use platform UUIDs, independently of display labels. The model's `#Unique` key uses `identityKey`, combining normalized asset name with the platform UUID or an explicit nil scope. A relationship-based compound constraint does not enforce the nil-platform case. Name, platform assignment, and identity key have private setters and change together through `updateIdentity(name:platform:)`; application operations reject conflicts before mutation. `platform` is a read-only display/interchange projection of `platformRecord?.name`, returning an empty string for nil; no platform name string is stored on Asset. [`BusinessLogic.md`](BusinessLogic.md#asset-identity-and-matching) owns matching and rename behavior.

The initializer accepts `name` and `platform`; currency can be assigned afterward in a main-actor model operation:

```swift
@MainActor
func makeAsset(in context: ModelContext) throws -> Asset {
  let platform = try PlatformService.resolve(name: "Brokerage", in: context)
  let asset = Asset(name: "AAPL", platform: platform)
  asset.currency = "USD"
  context.insert(asset)
  return asset
}
```

### Snapshot

A Snapshot represents the portfolio state recorded for one calendar date. See [`Snapshot.swift`](../AssetFlow/Models/Snapshot.swift).

| Property             | Type                    | Stored meaning                                                                      | Initial value                       |
| -------------------- | ----------------------- | ----------------------------------------------------------------------------------- | ----------------------------------- |
| `id`                 | `UUID`                  | Application identifier                                                              | New UUID                            |
| `date`               | `Date`                  | Snapshot date, normalized by the initializer to `Calendar.current.startOfDay(for:)` | Required initializer argument       |
| `createdAt`          | `Date`                  | Creation timestamp                                                                  | `Date()`                            |
| `assetValues`        | `[SnapshotAssetValue]?` | Direct asset records at this date                                                   | Empty collection in the initializer |
| `cashFlowOperations` | `[CashFlowOperation]?`  | External flows assigned to this date                                                | Empty collection in the initializer |
| `exchangeRate`       | `ExchangeRate?`         | Optional rate record for this date                                                  | `nil`                               |

`date` remains a `Date` value representing local start of day, not a date-only storage type. `#Unique<Snapshot>([\.date])` allows at most one snapshot for that stored date. The creation and import flows reject future dates; that restriction is application validation, not a property type constraint. Multiple permitted imports can add records to an existing date. A snapshot can omit an asset altogether or contain an explicit zero-valued `SnapshotAssetValue`; those states differ. See [`SPEC.md`](SPEC.md#8-snapshot-lifecycle) for lifecycle behavior.

### SnapshotAssetValue

A SnapshotAssetValue records one asset's market value in one snapshot, forming the join between Asset and Snapshot. See [`SnapshotAssetValue.swift`](../AssetFlow/Models/SnapshotAssetValue.swift).

| Property      | Type        | Stored meaning                                                                    | Initial value                 |
| ------------- | ----------- | --------------------------------------------------------------------------------- | ----------------------------- |
| `marketValue` | `Decimal`   | Value in the linked asset's currency, or display currency when that code is empty | Required initializer argument |
| `snapshot`    | `Snapshot?` | Parent snapshot                                                                   | `nil` until linked            |
| `asset`       | `Asset?`    | Valued asset                                                                      | `nil` until linked            |

The model declares `#Unique<SnapshotAssetValue>([\.snapshot, \.asset])`: a valid saved graph has at most one value for an asset in a snapshot. The Swift properties are optional so an object may be unlinked while it is being constructed; application flows and backup graph validation require both links for a meaningful recorded value. Zero is a stored value, not absence. Negative values are allowed for liabilities or short positions. Import handling of zero placeholders is defined in [`SPEC.md`](SPEC.md#46-duplicate-detection).

### CashFlowOperation

A CashFlowOperation records an external contribution or withdrawal at a snapshot date. See [`CashFlowOperation.swift`](../AssetFlow/Models/CashFlowOperation.swift).

| Property              | Type        | Stored meaning                                                  | Initial value                 |
| --------------------- | ----------- | --------------------------------------------------------------- | ----------------------------- |
| `id`                  | `UUID`      | Application identifier                                          | New UUID                      |
| `cashFlowDescription` | `String`    | Description within its snapshot                                 | Required initializer argument |
| `amount`              | `Decimal`   | Positive contribution; negative withdrawal                      | Required initializer argument |
| `currency`            | `String`    | Native currency; empty inherits display currency for conversion | `""`                          |
| `snapshot`            | `Snapshot?` | Parent snapshot                                                 | `nil` until linked            |

The property is named `cashFlowDescription` in Swift; backup transfer data uses `description`. `#Unique<CashFlowOperation>([\.snapshot, \.cashFlowDescription])` declares the stored-property key. Application paths also check duplicate descriptions without case; the macro alone does not specify that comparison. A valid saved operation is linked to one snapshot, although its Swift property is optional during construction. Net cash flow is derived from operations with currency conversion where needed; [`BusinessLogic.md`](BusinessLogic.md#net-cash-flow) defines its timing and calculation.

### ExchangeRate

An ExchangeRate stores rates applicable to a snapshot date. See [`ExchangeRate.swift`](../AssetFlow/Models/ExchangeRate.swift).

| Property       | Type        | Stored meaning                                                 | Initial value                 |
| -------------- | ----------- | -------------------------------------------------------------- | ----------------------------- |
| `baseCurrency` | `String`    | Base currency code, stored lowercase by the current fetch path | Required initializer argument |
| `ratesJSON`    | `Data`      | JSON-encoded `[String: Decimal]` rates                         | Required initializer argument |
| `fetchDate`    | `Date`      | Date to which the rates apply                                  | Required initializer argument |
| `isFallback`   | `Bool`      | Stored fallback flag retained in model and backup data         | `false`                       |
| `snapshot`     | `Snapshot?` | Parent snapshot                                                | `nil` until linked            |

Each rate represents units of that currency per one base-currency unit; the base currency has an implicit rate of one. `rates` decodes `ratesJSON` into a lowercased dictionary and caches it in the `@Transient` `_cachedRates` property; a decode failure yields an empty dictionary.

`updateRates(baseCurrency:ratesJSON:fetchDate:)` updates the stored fields, clears that cache, and sets `isFallback` to `false`. The current fetch path creates or refreshes records with the flag false; a restored backup can retain its stored value. The flag does not establish an active stale-rate fallback path.

The model's `convert(value:from:to:)` uses positive finite cross-rates and returns `nil` when a required rate is unusable. `matchesDate(_:timeZone:)` compares Gregorian calendar days, and `supportsAll(_:)` checks currency coverage. The service additionally requires the appropriate base currency, snapshot date, and coverage before reusing a record or presenting a converted aggregate. A wrong-date or incomplete record is unavailable for that purpose; see [`CurrencyConversionService.swift`](../AssetFlow/Services/CurrencyConversionService.swift) and [`ExchangeRateService.swift`](../AssetFlow/Services/ExchangeRateService.swift).

## Relationships and Integrity

### Entity Relationship Diagram

```text
Platform ←── optional platformRecord ── Asset
Category ←── optional category ── Asset
Asset ←── one asset ── SnapshotAssetValue ── one snapshot ──→ Snapshot
Snapshot ── zero or more ──→ CashFlowOperation
Snapshot ── zero or one ───→ ExchangeRate
```

Each SnapshotAssetValue connects one Asset to one Snapshot in a valid saved graph, so Asset and Snapshot have a many-to-many relationship through that entity. The parent links on SnapshotAssetValue, CashFlowOperation, and ExchangeRate are declared optional to allow construction before linking; the cardinalities above describe valid application data, not nonoptional Swift types.

| Declared relationship                                        | Cardinality in valid application data        | Configured delete rule                                             |
| ------------------------------------------------------------ | -------------------------------------------- | ------------------------------------------------------------------ |
| `Platform.assets` ↔ `Asset.platformRecord`                   | Platform: 0–many assets; Asset: 0–1 platform | `.deny` on `Platform.assets`; `.nullify` on `Asset.platformRecord` |
| `Category.assets` ↔ `Asset.category`                         | Category: 0–many assets; Asset: 0–1 category | `.deny` on `Category.assets`; `.nullify` on `Asset.category`       |
| `Asset.snapshotAssetValues` ↔ `SnapshotAssetValue.asset`     | Asset: 0–many values; value: one asset       | `.deny` on `Asset.snapshotAssetValues`                             |
| `Snapshot.assetValues` ↔ `SnapshotAssetValue.snapshot`       | Snapshot: 0–many values; value: one snapshot | `.cascade` on `Snapshot.assetValues`                               |
| `Snapshot.cashFlowOperations` ↔ `CashFlowOperation.snapshot` | Snapshot: 0–many flows; flow: one snapshot   | `.cascade` on `Snapshot.cashFlowOperations`                        |
| `Snapshot.exchangeRate` ↔ `ExchangeRate.snapshot`            | Snapshot: 0–1 rate; rate: one snapshot       | `.cascade` on `Snapshot.exchangeRate`                              |

The rule is configured on a particular relationship; it applies when deleting a model that contains references through that relationship. Inverse-side rules cannot be dismissed as universally meaningless. [Apple's SwiftData delete-rule reference](https://developer.apple.com/documentation/swiftdata/schema/relationship/deleterule-swift.enum) defines the rule directions. Snapshot declares `.cascade` for its values, cash flows, and rate record. [`SwiftDataRelationshipTests.swift`](../AssetFlowTests/Integration/SwiftDataRelationshipTests.swift) asserts value and cash-flow cascades and that deleting one snapshot preserves its Assets and other snapshots' values.

Application deletion paths also guard `.deny` relationships: [`CategoryListViewModel.swift`](../AssetFlow/ViewModels/CategoryListViewModel.swift) refuses to delete a category with assigned assets, and [`AssetListViewModel.swift`](../AssetFlow/ViewModels/AssetListViewModel.swift) refuses to delete an asset with snapshot values. Those guards enforce the app's deletion rules and provide user-facing errors. Restore deletes related records in dependency order; see [`BackupService+Restore.swift`](../AssetFlow/Services/BackupService+Restore.swift).

### Uniqueness and Valid-Graph Rules

| Model              | Declared `#Unique` key            | Additional application rule                                                    |
| ------------------ | --------------------------------- | ------------------------------------------------------------------------------ |
| Category           | `name`                            | Nonempty; case-insensitive name conflict check                                 |
| Platform           | `normalizedName`                  | Nonempty normalized name; preserve UUID on rename                              |
| Asset              | `identityKey`                     | Match and reject conflicts using normalized identity                           |
| Snapshot           | `date`                            | Normalize to local start of day; reject future creation dates                  |
| SnapshotAssetValue | `snapshot`, `asset`               | Link both parents; one direct value per asset and snapshot                     |
| CashFlowOperation  | `snapshot`, `cashFlowDescription` | Link a snapshot; check descriptions without case                               |
| ExchangeRate       | No `#Unique` declaration          | At most one rate through the snapshot's to-one relationship; link its snapshot |

These declared keys are not substitutes for validation before mutation. In particular, a `#Unique` declaration does not encode the application's text normalization. The graph rules describe app-created and validated backup data; the optional relationship properties do not alone prohibit an unlinked object from existing during construction. See [`BackupService+GraphValidation.swift`](../AssetFlow/Services/BackupService+GraphValidation.swift) for restore-time reference checks.

## Schema, Migration, and Preservation

[`SchemaVersioning.swift`](../AssetFlow/Models/SchemaVersioning.swift) selects SchemaV4 (4.0.0) as current. V1 and V2 model definitions are frozen in [`SchemaV1Models.swift`](../AssetFlow/Models/SchemaV1Models.swift) and [`SchemaV2Models.swift`](../AssetFlow/Models/SchemaV2Models.swift). The migration plan opens V1 through V2, whose category minimum fields are optional.

V2→V3 first rejects duplicate normalized asset-name/platform pairs before changing the graph. V3 is an intermediate schema retaining the old asset string alongside the new relationship: the custom migration creates one platform per normalized nonempty name and assigns assets without changing their UUIDs or recorded values. Migrated platforms without a legacy ordering preference use the same name ordering as new platforms. V3 also fills each asset identity key. V3→V4 removes the old string and enforces uniqueness on that key. A collision fails migration; records are never silently merged. Store-open failure shows a database error and exits without deleting or recreating the store. [`AssetFlowApp.swift`](../AssetFlow/AssetFlowApp.swift) opens the normal disk store through this migration plan; Debug preview launches and tests use separate disposable stores.

After opening, `PlatformService.migrateLegacyOrder` transfers the old UserDefaults name ordering to platform records and clears the old key only after saving successfully. Platform IDs and ordering then belong to SwiftData. [`PlatformPersistenceTests.swift`](../AssetFlowTests/Integration/PlatformPersistenceTests.swift) checks V2 conversion, reopen identity, and collision preservation; [`CategoryGoalMigrationTests.swift`](../AssetFlowTests/Integration/CategoryGoalMigrationTests.swift) checks the V1 path and financial graph. Future released-schema changes require a new migration assessment and frozen historical definitions. [`DevelopmentGuide.md`](DevelopmentGuide.md#working-with-swiftdata) owns the contributor procedure.

Current queries fetch snapshots by normalized date and read value history through `Asset.snapshotAssetValues`; the models declare no indexes. See [`SnapshotListViewModel.swift`](../AssetFlow/ViewModels/SnapshotListViewModel.swift) and [`AssetDetailViewModel.swift`](../AssetFlow/ViewModels/AssetDetailViewModel.swift). Query and context usage procedures belong in [`DevelopmentGuide.md`](DevelopmentGuide.md#working-with-swiftdata).

## Backup Mapping

Backup transfer records carry entity UUIDs and relationship references rather than persisting duplicate foreign-key properties on the SwiftData models. For example, `Asset.category` maps to a category UUID, and a cash flow's Swift `cashFlowDescription` maps to a transfer field named `description`. Snapshot and rate dates serialize as ISO 8601 timestamps, not date-only strings. The current backup format is v5, distinct from SwiftData SchemaV4. It includes all platform records, their UUIDs and order, asset platform UUID references, and Category minimum amount and currency. V1–v4 backups remain readable: their platform names resolve to shared platform relationships. V1–v3 backups have no category minimums; v4 retains minimums and the currency/rate data introduced in v3.

The format transfers only the documented settings subset; other UserDefaults preferences and the currency-list cache are outside the model graph. [`APIDesign.md`](APIDesign.md#backupservice) owns exact headers, field order, null representation, archive layout, and restore compatibility. [`BackupTypes.swift`](../AssetFlow/Services/BackupTypes.swift) and [`BackupService+Export.swift`](../AssetFlow/Services/BackupService+Export.swift) define the current transfer records and writer.
