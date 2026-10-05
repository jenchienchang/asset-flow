# AssetFlow Source Code

## Directory Structure

| Directory     | Purpose                                                            |
| ------------- | ------------------------------------------------------------------ |
| `Models/`     | SwiftData `@Model` classes (see `Models/README.md`)                |
| `Views/`      | SwiftUI views (includes `Charts/` and `Components/` subdirs)       |
| `ViewModels/` | `@Observable @MainActor` classes for form state and business logic |
| `Services/`   | Stateless utilities (see list below)                               |
| `Utilities/`  | Extensions and helpers (e.g., `Decimal.formatted(currency:)`)      |
| `Resources/`  | Non-code assets (XML data, `.xcstrings` localization catalogs)     |

## Patterns

### ViewModel

`@Observable @MainActor` class handling data loading, saving, and computed aggregates via injected `ModelContext`. Form state (text fields, pickers) lives in View-local `@State` properties; ViewModels expose `save()`/`delete()` and validation methods. Use `@State var viewModel` in views (not `@StateObject`).

### ViewModel Data Reload

Aggregate ViewModels use an `@ObservationIgnored` `ObservedRefresh` coordinator:

```swift
func loadData() {
  refresh.perform {
    let rows = calculateRowsFromSourceModels()
    refresh.publish { self.rows = rows }
  } reload: { [weak self] in self?.loadData() }
}
func requestRefresh() {
  refresh.request { [weak self] in self?.loadData() }
}
```

- Track source model/settings reads while calculating into locals; publish observable results outside tracking. Never read derived output as an input to the tracked calculation.
- Explicit loads remain synchronous. `requestRefresh()` coalesces observation/query notifications; each explicit load supersedes callbacks and tasks from older generations. New changes after that load remain observed.
- Use weak ViewModel captures so pending work does not retain SwiftData containers.
- `ContentView` publishes its six-model `ModelQueryRevision` through the `storeRevision` environment. All ten aggregate screens use `.refreshOnStoreChanges` to request a refresh after membership changes, date ordering changes, child-record changes and whole-store replacement. Local queries remain supported for standalone screens.
- Background data reloads preserve category editor drafts. Asset editor option lists also refresh without resetting edited fields.
- Dashboard internal caches are excluded from source observation; their public readers observe a publication revision so chart and period consumers still invalidate.
- Applied to Dashboard, Snapshot list/detail, Category list/detail, Platform list/detail, Asset list/detail and Rebalancing. Import and Bulk Entry retain their existing query reconciliation and draft-staleness behavior.

### Model

`@Model final class` with `Decimal` for money, `#Unique` for constraints, explicit `@Relationship` with delete rules (`.cascade`, `.deny`, `.nullify`). Register new models in `SchemaV2.models` (`Models/SchemaVersioning.swift`). Domain error enums (`AssetError`, `CategoryError`, `PlatformError`) also live in `Models/`.

### Services

Stateless enums or classes with no direct SwiftData dependency:

- **CalculationService** -- `enum`, growth rate, Modified Dietz, cumulative TWR, CAGR, category allocation
- **CSVParsingService** -- `enum`, parses asset/cash flow CSV with intra-CSV duplicate detection (cross-snapshot dedup is handled by `ImportViewModel`)
- **RebalancingCalculator** -- `enum`, rebalancing adjustment amounts (buy/sell)
- **BackupService** -- `@MainActor enum`, ZIP backup via `/usr/bin/ditto`
- **SettingsService** -- `@Observable @MainActor class`, app-wide settings (currency, date format, default platform)
- **AuthenticationService** -- `@Observable @MainActor class` singleton, app lock via LocalAuthentication (Touch ID, Apple Watch, system password)
- **CurrencyService** -- `@Observable @MainActor class` singleton (`static let shared`), currency data with UserDefaults caching
- **ExchangeRateService** -- `final class` (`@unchecked Sendable`), fetches rates from cdn.jsdelivr.net, batch-fetches missing rates on launch and after restore, graceful degradation when offline
- **CurrencyConversionService** -- `enum`, stateless currency conversion using ExchangeRate data, returns unconverted values when rates unavailable
- **ChartDataService** -- `enum`, time range filtering, TWR rebasing (`rebasedTWR`), and Y-axis abbreviation
- **DateFormatStyle** -- `enum`, user-selectable date formats → `Date.FormatStyle.DateStyle`

### Localization

- **Views**: String literals in `Text()`, `Label()`, etc. auto-extract into `Localizable.xcstrings`
- **ViewModels/Services**: `String(localized: "message", table: "Asset")` with tables: `Asset`, `Snapshot`, `Category`, `Import`, `Services`, `Settings`, `Platform`, `Rebalancing`
- **Enums**: `localizedName` for display; `rawValue` for persistence only
- Avoid `+` concatenation in `Text()` — prevents auto-extraction

## SwiftData Notes

- Single shared `ModelContainer` injected at app root
- No manual `save()` — SwiftData auto-persists
- Snapshots contain only directly-recorded values; no carry-forward

## SwiftUI Pitfalls

**`formattedPercentage()` expects percentage-scale input:** Pass `Decimal(60)` for 60%, not `0.6`. It divides by 100 internally. Raw decimals like TWR (0.21 for 21%) need `(twr * 100).formattedPercentage()`.

**Stable IDs in computed properties:** Never `let id = UUID()` in structs from computed properties — creates new IDs each render. Use stable composite keys: `var id: String { "\(category)-\(date.timeIntervalSince1970)" }`.

**Optional Picker needs nil tag:** Include `Text("Label").tag(Optional<T>.none)` when `Picker` selection is `Optional<T>`.

**Pin chart axis domains on interactive charts:** Set explicit `.chartXScale(domain:)` and `.chartYScale(domain:)` when using hover/tap overlays with conditional marks, otherwise axes shift during interaction.

**ViewModel empty↔content transitions:** Don't use `.animation(_:value:)` for empty↔content in ViewModel-based views (flashes on load). Use instant swap; `withAnimation` only in user-action handlers (`onChange`, delete). `@Query`-based views can animate safely.

**Use `.helpWhenUnlocked()` not `.help()`:** The app supports app lock via `AuthenticationService`. `.help("…")` tooltips are visible on the lock screen, leaking content. Always use `.helpWhenUnlocked("…")` to restrict tooltips to authenticated sessions.

**Use `.onHoverWhenUnlocked()` and `.onContinuousHoverWhenUnlocked()` instead of `.onHover()` and `.onContinuousHover()`:** Hover interactions (chart tooltips, highlight effects) can leak financial data through the lock overlay. The lock-aware variants gate callbacks behind the `isAppLocked` environment key, resetting hover state (`false` / `.ended`) when locked. Defined in `Utilities/WhenUnlockedModifiers.swift`.

**Chart requirements:** Every chart in `Views/Charts/` needs: hover tooltip (`.annotation()` on `RuleMark` with `overflowResolution` for positioning, `.chartOverlay` + `onContinuousHoverWhenUnlocked` for hover detection), pinned axis domains (`.chartXScale(domain:)` and `.chartYScale(domain:)` to prevent shifts from conditional marks), empty state messages (no data, no data for time range, single data point), click-to-navigate where specified, `ChartTimeRangeSelector` binding.

## Naming

- PascalCase: `AssetFormViewModel`, `AssetFormView`, `CurrencyService`
- File name matches primary type
- Suffixes: `*View`, `*Row`, `*Section`, `*ViewModel`, `*Service`, `*Calculator`

**File headers (SwiftLint enforced):**

```swift
//  AssetFlow — snapshot-based portfolio management for macOS.
//  Copyright (C) 2026 Jen-Chien Chang
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//
```

Clean category editors adopt externally updated saved fields after a data refresh; editors with unsaved changes retain every draft field. Saved-field source reads are tracked even for empty categories.
