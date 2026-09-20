# Data Model Documentation

## Overview

AssetFlow uses SwiftData for type-safe, modern data persistence on macOS 15.0+. The data model is designed around a **snapshot-based portfolio tracking** approach, where portfolio state is captured at discrete points in time rather than derived from transaction history.

This document provides comprehensive documentation for all data models, including property definitions, relationships, uniqueness constraints, SwiftData configuration, validation rules, and usage examples.

## Core Principles

### Snapshot-Based Design

The data model captures portfolio state through snapshots rather than transactions:

- **Snapshots** represent the best-known portfolio state at a specific date
- **SnapshotAssetValues** record market values of assets within a snapshot
- **CashFlowOperations** record external money flows for return calculations

### Financial Data Precision

- **Always use `Decimal`** for monetary values (never `Float` or `Double`)
- Prevents floating-point rounding errors in financial calculations
- Per-asset native currency tracking with automatic exchange rate conversion
- Currency-aware formatting via extensions
- `Decimal` is natively supported by SwiftData (via Foundation's `NSDecimalNumber` bridging) -- no explicit `@Attribute(.transformable)` annotation is needed

### Relationship Design

- Clear parent-child relationships
- Cascade delete rules for snapshot data integrity
- SwiftData relationships for entity references
- Uniqueness constraints enforced at the model level

### Schema Management

- All models registered via `SchemaV1` (versioned schema) in `Models/SchemaVersioning.swift`
- `SchemaV1: VersionedSchema` defines all model types with `versionIdentifier = Schema.Version(1, 0, 0)`
- `destroyExistingStore()` fallback handles dev database incompatibility
- When adding models, update `SchemaV1.models`, this documentation, and `Models/README.md`

## Model Entities

### Category

Represents a user-defined grouping for assets (e.g., "Equities", "Bonds", "Cash") with an optional target allocation percentage for rebalancing.

**File**: `AssetFlow/Models/Category.swift`

#### Properties

| Property                     | Type       | Description                             | Required |
| ---------------------------- | ---------- | --------------------------------------- | -------- |
| `id`                         | `UUID`     | Primary key                             | Yes      |
| `name`                       | `String`   | Display name (unique, case-insensitive) | Yes      |
| `targetAllocationPercentage` | `Decimal?` | Target allocation (0-100), optional     | No       |
| `displayOrder`               | `Int`      | User-defined sort order (default: 0)    | Yes      |

#### Relationships

```swift
@Relationship(deleteRule: .deny, inverse: \Asset.category)
var assets: [Asset]?
```

- **Assets**: Assets assigned to this category (`.deny` on delete -- category cannot be deleted if assets are assigned)

#### Uniqueness Constraints

```swift
#Unique<Category>([\.name])
```

- `name` must be unique (case-insensitive comparison)
- **Note**: The `#Unique` macro enforces uniqueness at the SwiftData level, but case-insensitive uniqueness must be handled in business logic (ViewModel validation).

#### Validation Rules

- `name` must not be empty
- `targetAllocationPercentage`, if provided, must be between 0 and 100
- Target allocations across all categories should sum to 100% (warning if not, but not blocked)
- Categories without a target allocation are excluded from rebalancing calculations

#### Usage Example

```swift
let category = Category(
    name: "Equities",
    targetAllocationPercentage: 60.0
)
```

______________________________________________________________________

### Asset

Represents an individual investment identified by the tuple (name, platform). Assets persist across snapshots and are created during import if they don't already exist.

**File**: `AssetFlow/Models/Asset.swift`

#### Properties

| Property   | Type     | Description                                                                                              | Required           |
| ---------- | -------- | -------------------------------------------------------------------------------------------------------- | ------------------ |
| `id`       | `UUID`   | Primary key                                                                                              | Yes                |
| `name`     | `String` | Asset name (e.g., "AAPL", "Bitcoin", "Savings Account")                                                  | Yes                |
| `platform` | `String` | Platform/brokerage name. Always present as `String`, but may be an empty string to indicate no platform. | Yes (may be empty) |
| `currency` | `String` | Native currency code (e.g., "USD", "TWD"). Empty string if unset.                                        | Yes (may be empty) |

#### Relationships

```swift
@Relationship(deleteRule: .nullify)
var category: Category?

@Relationship(deleteRule: .deny, inverse: \SnapshotAssetValue.asset)
var snapshotAssetValues: [SnapshotAssetValue]?
```

- **Category**: Optional assignment (`.nullify` -- if the category is deleted, this becomes nil)
- **SnapshotAssetValues**: All value records across snapshots (`.deny` -- asset cannot be deleted while it has snapshot values)

**Note on SwiftData relationships vs. SPEC field names**: The SPEC defines `categoryID: UUID?` as a field on Asset. In SwiftData, this is modeled using a direct relationship property (`category: Category?`) rather than a manual UUID foreign key. SwiftData manages the underlying foreign key automatically. Access the category's UUID via `asset.category?.id` when needed (e.g., for backup serialization).

#### Uniqueness Constraints

```swift
#Unique<Asset>([\.name, \.platform])
```

- `(name, platform)` must be unique (case-insensitive, using normalized identity comparison)
- **Note**: The `#Unique` macro enforces uniqueness at the SwiftData level, but case-insensitive uniqueness cannot be enforced by the macro alone and must be handled in business logic (ViewModel validation).

#### Identity Matching

During import or manual operations, assets are matched using **normalized identity comparison**:

1. Trim leading and trailing whitespace
1. Collapse multiple consecutive spaces to a single space
1. Case-insensitive comparison (Unicode-aware, using `caseInsensitiveCompare` or equivalent)

#### Deletion Rules

An asset can only be deleted when it has **no SnapshotAssetValue records** in any snapshot. When associations exist, the delete action is disabled with explanatory text: "This asset cannot be deleted because it has values in [N] snapshot(s). Remove the asset from all snapshots first."

#### Usage Example

```swift
let asset = Asset(
    name: "AAPL",
    platform: "Interactive Brokers",
    currency: "USD"
)
asset.category = equitiesCategory
```

______________________________________________________________________

### Snapshot

Represents the best-known portfolio state at a specific date. A snapshot is uniquely identified by its date. Multiple imports on the same date add SnapshotAssetValues to the existing snapshot.

**File**: `AssetFlow/Models/Snapshot.swift`

#### Properties

| Property    | Type   | Description                                                                                | Required |
| ----------- | ------ | ------------------------------------------------------------------------------------------ | -------- |
| `id`        | `UUID` | Primary key                                                                                | Yes      |
| `date`      | `Date` | Calendar date (normalized to local midnight, no time component). Must be today or earlier. | Yes      |
| `createdAt` | `Date` | Auto-set creation timestamp                                                                | Yes      |

#### Relationships

```swift
@Relationship(deleteRule: .cascade, inverse: \SnapshotAssetValue.snapshot)
var assetValues: [SnapshotAssetValue]?

@Relationship(deleteRule: .cascade, inverse: \CashFlowOperation.snapshot)
var cashFlowOperations: [CashFlowOperation]?

@Relationship(deleteRule: .cascade, inverse: \ExchangeRate.snapshot)
var exchangeRate: ExchangeRate?
```

- **SnapshotAssetValues**: Asset values recorded in this snapshot (`.cascade` on delete)
- **CashFlowOperations**: Cash flow events associated with this snapshot (`.cascade` on delete)
- **ExchangeRate**: Exchange rate data for currency conversion (`.cascade` on delete, optional 1:1)

#### Uniqueness Constraints

- Only one Snapshot may exist per `date`

#### Important Notes

- `totalPortfolioValue` is **not stored** -- it is always derived by summing SnapshotAssetValues
- Future dates are not allowed
- The `date` field stores only the calendar date (no time component), normalized to local midnight

#### Usage Example

```swift
let snapshot = Snapshot(
    date: Calendar.current.startOfDay(for: Date())
)
```

______________________________________________________________________

### SnapshotAssetValue

Records the market value of a specific asset within a specific snapshot. This is the core join entity connecting snapshots to assets with their values.

**File**: `AssetFlow/Models/SnapshotAssetValue.swift`

#### Properties

| Property      | Type      | Description               | Required |
| ------------- | --------- | ------------------------- | -------- |
| `marketValue` | `Decimal` | Market value of the asset | Yes      |

**Note on SPEC field names**: The SPEC defines `snapshotID` and `assetID` as UUID foreign keys. In SwiftData, these are modeled as relationship properties (`snapshot` and `asset`) rather than manual UUID fields. SwiftData manages the underlying foreign keys automatically. Access UUIDs via `snapshot?.id` and `asset?.id` when needed (e.g., for backup serialization). Do not store both a relationship property and a manual UUID field for the same reference.

#### Relationships

```swift
var snapshot: Snapshot?  // Inverse of Snapshot.assetValues
var asset: Asset?        // Inverse of Asset.snapshotAssetValues
```

- **Snapshot**: Parent snapshot. Deletion is governed by the parent's delete rule (Snapshot -> assetValues uses `.cascade`, so deleting a Snapshot cascades to its SnapshotAssetValues).
- **Asset**: The asset being valued. Deletion is governed by the parent's delete rule (Asset -> snapshotAssetValues uses `.deny`, so the asset cannot be deleted while SnapshotAssetValues reference it).

**Note**: The child-side delete rule is not meaningful in SwiftData -- deletion behavior is controlled by the parent-side rule. The inverse relationships here exist to satisfy SwiftData's relationship modeling requirements.

#### Uniqueness Constraints

```swift
#Unique<SnapshotAssetValue>([\.snapshot, \.asset])
```

- `(snapshot, asset)` must be unique (one value per asset per snapshot). Enforced at the SwiftData level via `#Unique` macro, and also validated in business logic.

#### Notes

- Negative market values are allowed (for liabilities or short positions)
- Zero market values are allowed (with a warning during import)

#### Usage Example

```swift
let value = SnapshotAssetValue(marketValue: 15000)
value.snapshot = snapshot
value.asset = asset
context.insert(value)
```

______________________________________________________________________

### CashFlowOperation

Records an external money flow (deposit or withdrawal) associated with a snapshot. Cash flows are needed for accurate Modified Dietz return calculations.

**File**: `AssetFlow/Models/CashFlowOperation.swift`

#### Properties

| Property              | Type      | Description                                                       | Required           |
| --------------------- | --------- | ----------------------------------------------------------------- | ------------------ |
| `id`                  | `UUID`    | Primary key                                                       | Yes                |
| `cashFlowDescription` | `String`  | Description of the cash flow (e.g., "Salary deposit")             | Yes                |
| `amount`              | `Decimal` | Positive = inflow, negative = outflow                             | Yes                |
| `currency`            | `String`  | Native currency code (e.g., "USD", "TWD"). Empty string if unset. | Yes (may be empty) |

**Note on property naming**: The property is named `cashFlowDescription` (not `description`) to avoid conflict with Swift's built-in `CustomStringConvertible` protocol requirement. This is an implementation detail — the SPEC uses "description" in CSV columns and documentation.

**Note on SPEC field names**: The SPEC defines `snapshotID` as a UUID foreign key. In SwiftData, this is modeled as a relationship property (`snapshot`) rather than a manual UUID field. Access the snapshot UUID via `snapshot?.id` when needed (e.g., for backup serialization).

#### Relationships

```swift
var snapshot: Snapshot?  // Inverse of Snapshot.cashFlowOperations
```

- **Snapshot**: Parent snapshot. Deletion governed by Snapshot -> cashFlowOperations `.cascade` rule.

#### Uniqueness Constraints

```swift
#Unique<CashFlowOperation>([\.snapshot, \.cashFlowDescription])
```

- `(snapshot, cashFlowDescription)` must be unique (case-insensitive comparison on cashFlowDescription)

#### Notes

- The net cash flow for a snapshot is always derived: `netCashFlow = sum(CashFlowOperation.amount)` for all operations associated with that snapshot
- If a snapshot has no cash flow operations, net cash flow = 0 (assumes all value changes are due to investment returns)
- All cash flow operations within a snapshot are assumed to occur at the snapshot date for Modified Dietz time-weighting purposes
- Portfolio-level only in v1 (category-level cash flow tracking deferred)

#### Usage Example

```swift
let cashFlow = CashFlowOperation(
    cashFlowDescription: "Salary deposit",
    amount: 50000
)
cashFlow.snapshot = snapshot
context.insert(cashFlow)
```

______________________________________________________________________

### ExchangeRate

Records exchange rate data for currency conversion at a specific snapshot date. Fetched from the `@fawazahmed0/currency-api` CDN when a snapshot contains multi-currency assets.

**File**: `AssetFlow/Models/ExchangeRate.swift`

#### Properties

| Property       | Type     | Description                                                     | Required |
| -------------- | -------- | --------------------------------------------------------------- | -------- |
| `baseCurrency` | `String` | Base currency code (lowercase, e.g., "usd")                     | Yes      |
| `ratesJSON`    | `Data`   | JSON-encoded `[String: Double]` mapping currency codes to rates | Yes      |
| `fetchDate`    | `Date`   | Date these rates apply to                                       | Yes      |
| `isFallback`   | `Bool`   | Whether rates came from a fallback source                       | Yes      |

#### Relationships

```swift
var snapshot: Snapshot?  // Inverse of Snapshot.exchangeRate
```

- **Snapshot**: Parent snapshot (1:1). Deletion governed by Snapshot -> exchangeRate `.cascade` rule.

#### Transient Cache

```swift
@Transient
private var _cachedRates: [String: Double]?
```

- `_cachedRates` is a `@Transient` property that caches the decoded `rates` dictionary after first access. It is not persisted by SwiftData. The cache is cleared whenever `updateRates(baseCurrency:ratesJSON:fetchDate:)` is called.

#### Computed Properties and Methods

- `rates: [String: Double]` — Decodes `ratesJSON` to a lowercased dictionary (cached after first access via `_cachedRates`). Returns empty dict on decode failure.
- `missingCurrencies(_:) -> [String]` — Returns requested currencies that are absent or have non-positive/non-finite rates.
- `supportsAll(_:) -> Bool` — Returns whether the record has usable rates for every requested currency.
- `matchesDate(_:timeZone:) -> Bool` — Verifies that `fetchDate` and the snapshot date have the same Gregorian calendar day in the supplied timezone, preventing a complete rate record from being reused for the wrong historical snapshot.
- `func convert(value: Decimal, from: String, to: String) -> Decimal?` — Converts a value between currencies using cross-rates. Returns `nil` if either currency is missing from rates.
- `func updateRates(baseCurrency:ratesJSON:fetchDate:)` — Updates rate data in-place (sets `baseCurrency`, `ratesJSON`, `fetchDate`, clears `isFallback` to `false`) and invalidates the decoded cache (`_cachedRates = nil`). Use this method to refresh exchange rate data without replacing the model object.

#### Usage Example

```swift
let exchangeRate = ExchangeRate(
    baseCurrency: "usd",
    ratesJSON: try JSONEncoder().encode(["twd": 31.5, "eur": 0.92]),
    fetchDate: Date(),
    isFallback: false
)
exchangeRate.snapshot = snapshot
context.insert(exchangeRate)

// Convert 100 USD to TWD
let twdValue = exchangeRate.convert(value: 100, from: "usd", to: "twd")
// → 3150
```

______________________________________________________________________

## Entity Relationships

### Relationship Diagram

```
+-----------+
| Category  |
+-----+-----+
      | 1:Many
      v
+-----------+   1:Many   +--------------------+
|   Asset   +----------->| SnapshotAssetValue |
+-----------+            +----------+---------+
                                    |
                                    | Many:1
                                    v
                              +-----------+   1:Many   +--------------------+
                              |  Snapshot  +----------->| CashFlowOperation |
                              +-----+-----+            +--------------------+
                                    |
                                    | 1:1 (optional)
                                    v
                              +--------------+
                              | ExchangeRate |
                              +--------------+
```

### Delete Rules

| Relationship                    | Delete Rule | Behavior                                       |
| ------------------------------- | ----------- | ---------------------------------------------- |
| Category -> Assets              | `.deny`     | Cannot delete category if assets are assigned  |
| Asset -> SnapshotAssetValues    | `.deny`     | Cannot delete asset if snapshot values exist   |
| Snapshot -> SnapshotAssetValues | `.cascade`  | Deleting snapshot removes all its asset values |
| Snapshot -> CashFlowOperations  | `.cascade`  | Deleting snapshot removes all its cash flows   |
| Snapshot -> ExchangeRate        | `.cascade`  | Deleting snapshot removes its exchange rate    |

**Note**: Delete behavior is controlled by the parent-side rule. Child-side inverse relationships do not independently define delete behavior in SwiftData.

**Important: Category Deletion Protection**

SwiftData's `.deny` delete rule has known bugs and may not work reliably. **Business logic MUST enforce deletion prevention** by checking whether the category has any assigned assets before allowing deletion:

```swift
func deleteCategory(_ category: Category) throws {
    guard category.assets?.isEmpty ?? true else {
        throw CategoryError.cannotDeleteWithAssignedAssets
    }
    modelContext.delete(category)
}
```

**Important: Asset Deletion Protection**

Asset deletion is blocked at the SwiftData level via the `.deny` delete rule. Additionally, business logic MUST enforce deletion prevention and provide a clear error message:

```swift
func deleteAsset(_ asset: Asset) throws {
    guard asset.snapshotAssetValues?.isEmpty ?? true else {
        throw AssetError.cannotDeleteWithSnapshotValues(
            count: asset.snapshotAssetValues?.count ?? 0
        )
    }
    modelContext.delete(asset)
}
```

### Relationship Constraints

- An Asset can belong to **0 or 1** Category
- A Category can contain **0 to many** Assets
- A Snapshot can have **0 to many** SnapshotAssetValues
- A Snapshot can have **0 to many** CashFlowOperations
- An Asset can have **0 to many** SnapshotAssetValues (across different snapshots)
- A SnapshotAssetValue belongs to exactly **1** Snapshot and **1** Asset
- A Snapshot can have **0 or 1** ExchangeRate (optional 1:1)
- An ExchangeRate belongs to exactly **1** Snapshot

______________________________________________________________________

## SwiftData Configuration

### Model Container Setup

**Location**: `AssetFlowApp.swift`

```swift
var sharedModelContainer: ModelContainer = {
    let schema = Schema(versionedSchema: SchemaV1.self)

    let modelConfiguration = ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: false
    )

    do {
        return try ModelContainer(
            for: schema,
            configurations: [modelConfiguration]
        )
    } catch {
        fatalError("Could not create ModelContainer: \(error)")
    }
}()
```

`SchemaV1.models` includes: `Category`, `Asset`, `Snapshot`, `SnapshotAssetValue`, `CashFlowOperation`, `ExchangeRate`.

### Adding New Models

When adding a new model to the schema:

1. Create the model file in `AssetFlow/Models/`
1. Add `@Model` macro to the class
1. Register in `SchemaV1.models` (`Models/SchemaVersioning.swift`)
1. Update this documentation
1. Update `AssetFlow/Models/README.md`
1. Consider migration strategy if needed

### Querying Data

Using SwiftUI's `@Query`:

```swift
@Query(sort: \Snapshot.date, order: .reverse)
private var snapshots: [Snapshot]

@Query(sort: \Asset.name)
private var assets: [Asset]

@Query(sort: \Category.name)
private var categories: [Category]
```

### Manual Context Access

```swift
@Environment(\.modelContext) private var modelContext

// Insert
modelContext.insert(newSnapshot)

// Delete
modelContext.delete(snapshot)

// Save (usually automatic)
try? modelContext.save()
```

______________________________________________________________________

## Data Validation

### Model-Level Validation

Validation logic resides in ViewModels (not models):

```swift
// In ImportViewModel
func validateAssetCSV(_ rows: [CSVRow]) -> [ValidationError] {
    var errors: [ValidationError] = []

    for (index, row) in rows.enumerated() {
        if row.assetName.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append(.emptyAssetName(row: index + 1))
        }
        if Decimal(string: row.marketValue) == nil {
            errors.append(.invalidMarketValue(row: index + 1))
        }
    }

    return errors
}
```

### Business Rules

1. **Market Values**: Use `Decimal` for all monetary values
1. **Dates**: Snapshot dates cannot be in the future; normalized to local midnight
1. **Uniqueness**: (Asset name, Platform) must be unique; Snapshot date must be unique; (Snapshot, Asset) must be unique per SnapshotAssetValue; (Snapshot, Description) must be unique for cash flows
1. **Category Deletion**: Only allowed if no assets are assigned
1. **Asset Deletion**: Only allowed if no SnapshotAssetValue records exist
1. **Snapshot Deletion**: Always allowed (with confirmation dialog); cascades to all asset values and cash flow operations

______________________________________________________________________

## Backup Data Format

When exporting a backup, each entity is serialized to CSV with the following rules:

- Column headers match field names from this data model
- UUID fields serialized as standard UUID strings
- Decimal fields serialized at full precision
- Date fields use ISO 8601 format (YYYY-MM-DD)
- Optional/nullable fields use an empty string for null values
- A `manifest.json` file includes format version, export timestamp, and app version

See [APIDesign.md](APIDesign.md) for detailed backup format specification.

______________________________________________________________________

## Data Migration

### Schema Versioning

The app uses `VersionedSchema` for schema management:

```swift
enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] = [
        Category.self, Asset.self, Snapshot.self,
        SnapshotAssetValue.self, CashFlowOperation.self, ExchangeRate.self,
    ]
}
```

**File**: `AssetFlow/Models/SchemaVersioning.swift`

Since the app is not yet publicly released, `SchemaV1` defines the complete schema including all currency fields and the ExchangeRate model. No `SchemaMigrationPlan` is needed yet. The `destroyExistingStore()` fallback handles dev database incompatibility. Future schema changes will add `SchemaV2` + a migration plan.

### Migration Strategy

1. **Additive Changes**: New optional properties (no migration needed)
1. **Transformations**: Property renames or type changes (migration required)
1. **Relationship Changes**: Modify delete rules or cardinality (migration required)

The data model is designed to minimize future breaking changes by:

- Using UUID primary keys
- Keeping relationships simple
- Avoiding complex computed stored properties

______________________________________________________________________

## Performance Considerations

### Efficient Historical Queries

The data model must support efficient queries for:

- Fetching all snapshots (ordered by date)
- Fetching asset values across multiple snapshots (for charts)

### Indexing

Consider adding indices for frequently queried properties:

```swift
@Attribute(.index)
var date: Date  // On Snapshot

@Attribute(.index)
var name: String  // On Asset
```

______________________________________________________________________

## References

- Source: `AssetFlow/Models/`
- Extensions: `AssetFlow/Utilities/Extensions.swift`
- App Configuration: `AssetFlow/AssetFlowApp.swift`
- Quick Reference: `AssetFlow/Models/README.md`
- Specification: `SPEC.md` Section 7
