# Data Models - Quick Reference

This directory contains the core SwiftData models for AssetFlow.

**For comprehensive documentation, see [Documentation/DataModel.md](../../Documentation/DataModel.md)**

## Models Overview

### Category

Asset categorization with optional target allocation percentage.

**Key Properties:**

- `name` - Display name (unique, case-insensitive)
- `targetAllocationPercentage` - Optional target allocation (0-100, Decimal)
- `displayOrder` - Sort order for user-defined ordering (Int, default: 0)

**Relationships:**

- Assets (many children, `.deny` delete rule -- must reassign assets before deleting)

### Asset

Individual investment identified by (name, platform) tuple.

**Key Properties:**

- `name` - Display name
- `platform` - Platform/broker (optional, default: "")
- `currency` - Native currency code (e.g., "USD", "TWD"; default: "")

**Computed Properties:**

- `normalizedName` - Trimmed, collapsed spaces, lowercased
- `normalizedPlatform` - Trimmed, collapsed spaces, lowercased
- `normalizedIdentity` - Combined `normalizedName|normalizedPlatform` for matching

**Relationships:**

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

All models are registered via `SchemaV1` (versioned schema) in `Models/SchemaVersioning.swift`:

```swift
let schema = Schema(versionedSchema: SchemaV1.self)
// SchemaV1.models includes: Category, Asset, Snapshot,
// SnapshotAssetValue, CashFlowOperation, ExchangeRate
```

### When Adding/Modifying Models

1. Update the model file
1. Register in `SchemaV1.models` (`Models/SchemaVersioning.swift`) if new
1. Update this README
1. Update [Documentation/DataModel.md](../../Documentation/DataModel.md)
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

See the comprehensive [DataModel.md](../../Documentation/DataModel.md) documentation.
