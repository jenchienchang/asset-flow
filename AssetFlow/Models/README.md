# Data Models - Quick Reference

This directory contains the core SwiftData models for AssetFlow.

**For comprehensive documentation, see [`Documentation/DataModel.md`](../../Documentation/DataModel.md)**

## Models Overview

### Category

Asset categorization with optional target allocation percentage.

**Key Properties:**

- `name` - Display name (unique, case-insensitive)
- `targetAllocationPercentage` - Optional pool preference (0-100, Decimal)
- `minimumBalanceAmount` - Optional finite nonnegative minimum (Decimal)
- `minimumBalanceCurrency` - Explicit original currency, paired with minimum
- `displayOrder` - Sort order for user-defined ordering (Int, default: 0)

**Relationships:**

- Assets (many children, `.deny` delete rule -- must reassign assets before deleting)

### Platform

Persistent custodian identity with `id: UUID`, display `name`, unique `normalizedName`, and `displayOrder`. `PlatformService` owns normalized resolution and validated renames. `assets` is the inverse of `Asset.platformRecord` with `.deny` deletion. Empty platforms remain stored but hidden; a rename preserves identity and ordering.

### Asset

Individual investment identified by normalized name and optional platform UUID.

**Key Properties:**

- `name` - Display name (private setter)
- `identityKey` - Persisted normalized-name/platform-UUID uniqueness key, including nil platform
- `platformRecord` - Optional relationship to Platform (nil means none)
- `platform` - Read-only display/interchange name projection (empty for nil)
- `currency` - Native currency code (e.g., "USD", "TWD"; default: "")

**Computed Properties:**

- `normalizedName` - Trimmed, collapsed spaces, lowercased
- `normalizedPlatform` - Trimmed, collapsed spaces, lowercased
- `normalizedIdentity` - Combined `normalizedName|normalizedPlatform` text projection for interchange; persisted matching uses platform UUID

**Relationships:**

- Platform (optional parent, `.nullify`)
- Category (optional parent, `.nullify`)
- SnapshotAssetValues (many children, `.deny` -- must delete values before deleting asset)

### Snapshot

Portfolio state at a specific date.

**Key Properties:**

- `date` - Snapshot date (unique, normalized to start of day)
- `createdAt` - Timestamp when the snapshot was created

**Relationships:**

- SnapshotAssetValues (many children, `.cascade`)
- CashFlowOperations (many children, `.cascade`)
- ExchangeRate (optional 1:1, `.cascade`)

### SnapshotAssetValue

Market value of an asset within a specific snapshot (join entity).

**Key Properties:**

- `marketValue` - Market value at the snapshot date (Decimal)

**Relationships:**

- Snapshot (parent)
- Asset (parent)

### CashFlowOperation

External cash flow event (deposit/withdrawal) associated with a snapshot.

**Key Properties:**

- `cashFlowDescription` - Description of the cash flow (unique per snapshot, case-insensitive)
- `amount` - Amount (Decimal, positive=inflow, negative=outflow)
- `currency` - Native currency code (e.g., "USD", "TWD"; default: "")

**Relationships:**

- Snapshot (parent)

### ExchangeRate

Exchange rate data for currency conversion at a specific snapshot date.

**Key Properties:**

- `baseCurrency` - Base currency code (lowercase, e.g., "usd")
- `ratesJSON` - `Data` blob containing JSON-encoded `[String: Decimal]` of currency rates
- `fetchDate` - Date these rates apply to
- `isFallback` - Whether rates came from a fallback source

**Relationships:**

- Snapshot (1:1, inverse of `Snapshot.exchangeRate`)

**Computed Properties:**

- `rates` - Decoded, lowercased `[String: Decimal]` from `ratesJSON`
- `missingCurrencies(_:)` / `supportsAll(_:)` - Validate that requested currencies have usable positive finite rates
- `convert(value:from:to:)` - Cross-rate currency conversion

An exchange-rate record is usable only when its base currency matches the configured display currency and it contains a valid rate for every non-display currency used by the snapshot. Invalid or incomplete records are refreshed before being used.

## Relationships

```
Platform (1:Many) -> Asset
Category (1:Many) -> Asset
Asset (Many:Many via SnapshotAssetValue) -> Snapshot
Snapshot (1:Many) -> SnapshotAssetValue
Snapshot (1:Many) -> CashFlowOperation
Snapshot (1:1) -> ExchangeRate (optional)
```

Delete Rules:

- Category -> Assets: `.deny` (must reassign assets before deleting category)
- Asset -> Category: `.nullify` (category ref set to nil when asset deleted)
- Asset -> SnapshotAssetValues: `.deny` (must delete values before deleting asset)
- Snapshot -> SnapshotAssetValues: `.cascade` (values deleted with snapshot)
- Snapshot -> CashFlowOperations: `.cascade` (operations deleted with snapshot)
- Snapshot -> ExchangeRate: `.cascade` (exchange rate deleted with snapshot)

## Critical Conventions

### Financial Data

**Always use `Decimal` for monetary values** (never Float/Double)

```swift
var marketValue: Decimal  // Correct
var marketValue: Double   // Never do this
```

### Schema Registration

All models are registered via `SchemaV4` (versioned schema) in [`SchemaVersioning.swift`](SchemaVersioning.swift):

```swift
let schema = CurrentSchema.schema
// SchemaV4.models includes: Category, Asset, Snapshot,
// SnapshotAssetValue, CashFlowOperation, ExchangeRate, Platform
```

### When Adding/Modifying Models

1. Update the model file
1. Register in `SchemaV4.models` ([`SchemaVersioning.swift`](SchemaVersioning.swift)) if new
1. Update this README
1. Update [`Documentation/DataModel.md`](../../Documentation/DataModel.md)
1. Consider migration strategy if changing existing models

## Quick Links

- [Architecture Documentation](../../Documentation/Architecture.md)
- [Complete Data Model Documentation](../../Documentation/DataModel.md)
- [Development Guide](../../Documentation/DevelopmentGuide.md)
- [Code Style Guide](../../Documentation/CodeStyle.md)

## File Organization

```
Models/
├── README.md (this file)
├── SchemaVersioning.swift
├── SchemaV1Models.swift
├── SchemaV2Models.swift
├── SchemaV3Models.swift
├── Platform.swift
├── Category.swift
├── Asset.swift
├── Snapshot.swift
├── SnapshotAssetValue.swift
├── CashFlowOperation.swift
├── ExchangeRate.swift
├── AssetError.swift
├── CategoryError.swift
└── PlatformError.swift
```

______________________________________________________________________

For detailed information on:

- Complete property tables
- Uniqueness constraints
- Computed properties
- Validation rules
- SwiftData configuration
- Migration strategies
- Usage examples

See the comprehensive [`Documentation/DataModel.md`](../../Documentation/DataModel.md) documentation.

## Category Minimum Balances

`minimumBalanceAmount: Decimal?` and `minimumBalanceCurrency: String?` must be jointly present or absent. Amounts are finite and nonnegative; zero is valid. Goals belong to categories and are independent of asset currency. Percentages can coexist with minimums. Effective targets/status are derived from current snapshot data and are not persisted. Use frozen V1/V2 definitions and intermediate V3 for migration; current application models belong to V4.
