# Code Style Guide

This guide defines implementation conventions for AssetFlow. The configuration files enforce mechanical rules; this document explains project choices that need developer judgment. [`DevelopmentGuide.md`](DevelopmentGuide.md) owns setup and contributor commands, [`Architecture.md`](Architecture.md) owns component boundaries, and [`TestingStrategy.md`](TestingStrategy.md) owns verification design.

## Formatting and Enforcement

Swift source uses two-space indentation and a configured 100-character line length. [`.swift-format`](../.swift-format) and [`.editorconfig`](../.editorconfig) define formatting; [`.swiftlint.yml`](../.swiftlint.yml) defines lint rules and their scope. Keep imports ordered as required by swift-format. SwiftLint warns on force unwrapping and `print()` and checks the required file header in [`AssetFlow/`](../AssetFlow/). Review warnings instead of treating the examples here as a second configuration file.

[`.pre-commit-config.yaml`](../.pre-commit-config.yaml) runs formatting and linting hooks at commit time. Follow [`DevelopmentGuide.md`](DevelopmentGuide.md) for the contributor workflow.

## Naming, Files, and Access

Use `UpperCamelCase` for types and protocols, `lowerCamelCase` for properties and functions, and names that explain their use. File names normally match their primary type; established suffixes include `View`, `ViewModel`, `Service`, and `Calculator`. Give Boolean properties assertion-like names such as `isImportDisabled` or `hasSnapshotValues`.

Follow [Swift's API case conventions](https://www.swift.org/documentation/api-design-guidelines/) for acronyms and initialisms: common uppercase forms are uniformly upper- or lowercased to fit the identifier's position. For example, `HTTPClient`, `urlString`, and `csvParser` are consistent with that rule. There is no two- or three-letter cutoff. Prefer a domain name when it clarifies meaning: `CashFlowOperation.cashFlowDescription` is the established property name, not a requirement imposed by `CustomStringConvertible` on every `description` property.

Keep helpers and stored implementation details `private` when they are used only by their declaring type or file. Expose the narrowest useful interface for a ViewModel, service, or model. Organize a file so its primary type and closely related helpers are easy to find; split unrelated responsibilities rather than adding generic extensions to a large file.

### File Headers and Comments

Swift files use the project license header. SwiftLint's configured `file_header` rule checks app source under `AssetFlow/`; follow the same convention in test source. The header is:

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

Use `///` comments to state a nonobvious contract, unit, actor requirement, or failure condition. Ordinary comments should explain why a choice is necessary rather than repeat the code. Keep examples and comments current when an interface changes.

## SwiftUI State and Identity

AssetFlow targets macOS 15.0+; app views do not need iOS or iPadOS conditional branches. Views use `@State` for navigation, presentation, and simple temporary form fields, `@FocusState` for focus bindings, and `@Binding` for state owned by a parent. A view can read SwiftData with `@Query` where a direct query fits. Screen ViewModels are `@Observable @MainActor` classes and are held in view `@State`, as in [`AssetListView.swift`](../AssetFlow/Views/AssetListView.swift).

A larger draft may live in a ViewModel, as in [`CategoryDetailViewModel.swift`](../AssetFlow/ViewModels/CategoryDetailViewModel.swift); keep it separate from persisted models until the screen's commit action. [`UserInterfaceDesign.md`](UserInterfaceDesign.md) defines the visible Save and Cancel behavior.

Give computed `Identifiable` values stable IDs derived from their underlying records. Creating `UUID()` each time a computed chart or row collection is evaluated changes identity on every render. For example, [CategoryRowData](../AssetFlow/ViewModels/CategoryListViewModel.swift) returns its category's stored UUID; a derived chart point can combine a stable series key and date.

When a restore replaces a selected SwiftData object with a new instance, the parent detail view uses `.id(ObjectIdentifier(selectedObject))` to recreate state tied to that instance; see [`ContentView.swift`](../AssetFlow/Views/ContentView.swift). Use the identity appropriate to the purpose: stored UUID for the same record across renders, instance identity when replacing a stateful detail.

For a `Picker` with an optional selection, include an explicitly typed nil tag such as `.tag(Optional<Date>.none)`. See [`CategoryAllocationPieChart.swift`](../AssetFlow/Views/Charts/CategoryAllocationPieChart.swift) for an existing use.

### Lock-Aware Help and Hover

Use `.helpWhenUnlocked()` for tooltip help text and `.onHoverWhenUnlocked()` or `.onContinuousHoverWhenUnlocked()` for hover callbacks. The modifiers in [`WhenUnlockedModifiers.swift`](../AssetFlow/Utilities/WhenUnlockedModifiers.swift) suppress help and send `false` or `.ended` for hover callbacks received while locked. Ordinary `.help()`, `.onHover()`, and `.onContinuousHover()` can expose content through the lock overlay. [`SecurityAndPrivacy.md`](SecurityAndPrivacy.md#app-lock-optional) describes the protection boundary.

### Animating Empty↔Content Transitions

A ViewModel-based screen may initially render an empty state before its load completes. Do not attach `.animation(_:value:)` or an opacity transition to that empty/content switch; it can flash on navigation. Keep the switch immediate, and animate list changes in the user-action path when useful. `@Query`-driven views whose data is available synchronously can use value-driven animation where appropriate. Use [`AnimationConstants.swift`](../AssetFlow/Utilities/AnimationConstants.swift) for shared durations and Reduce Motion behavior.

## SwiftData, Concurrency, and Refresh

SwiftData entities are `@Model` classes. Keep model relationships and persistence invariants consistent with [`DataModel.md`](DataModel.md); access the shared `ModelContext` on the main actor. Inject a `ModelContext` or focused service dependency at the boundary that needs it, rather than making a broad global dependency. [`Architecture.md`](Architecture.md#persistence-and-concurrency) explains the shared container, stateful services, and worker boundaries.

The app target has default MainActor isolation. An `enum` declaration does not itself make a service nonisolated. Mark a pure helper `nonisolated` only when its implementation can safely run without main-actor state. Values crossing isolation boundaries should be `Sendable`; review each service input and result for that boundary.

Use `@unchecked Sendable` or `nonisolated(unsafe)` only with a documented shared-state invariant and evidence that it holds. Do not pass live SwiftData models or a `ModelContext` into nonisolated file, parsing, or archive work.

Aggregate ViewModels use an `@ObservationIgnored` [ObservedRefresh](../AssetFlow/Utilities/ObservedRefresh.swift) coordinator. Compute local results while tracking reads of source models and settings, then queue observable assignments with `refresh.publish` so publication happens outside tracking. Do not read derived output as an input to that calculation; doing so can create a reload loop.

Keep explicit loads synchronous. Use weak ViewModel captures in the reload and requested-refresh closures so pending work does not retain the ViewModel or its container. `refresh.request` coalesces notifications, and the coordinator's generation check prevents an older callback from superseding a newer explicit load. [`CategoryListViewModel.swift`](../AssetFlow/ViewModels/CategoryListViewModel.swift) shows the pattern; [`Architecture.md`](Architecture.md#state-observation-and-refresh) explains how store-query revisions complement source observation.

## Financial Values and Optionals

Use `Decimal` for monetary amounts and exchange rates through parsing, calculation, conversion, and persistence. Convert to `Double` only at a visualization boundary such as chart coordinates. Keep the currency unit attached to a value's meaning. The selected display currency drives actual conversion; a missing required rate makes the affected converted result unavailable. Never label a sum of different native currencies as a single-currency total. [`BusinessLogic.md`](BusinessLogic.md) owns the calculation and availability rules.

`formattedPercentage()` expects **percentage-scale** `Decimal` input. A ratio such as `0.1234` must be multiplied by 100 before formatting:

```swift
let percentagePoints: Decimal = 12.34
let percentageLabel = percentagePoints.formattedPercentage()

let returnRatio: Decimal = 0.1234
let returnLabel = (returnRatio * 100).formattedPercentage()
```

These examples run in a main-actor view or ViewModel; the formatter is defined in [`Extensions.swift`](../AssetFlow/Utilities/Extensions.swift). Format a converted amount with its actual currency code, for example `convertedValue.formatted(currency: displayCurrency)`. A default `"USD"` formatting argument does not perform conversion.

Use `Decimal.parse(_:locale:)` for localized user-entered numbers on the main actor. CSV input has its own parsing and interchange rules in [`APIDesign.md`](APIDesign.md); do not apply UI-locale parsing to canonical CSV data.

Prefer optional binding when absence changes behavior. Coalesce only a genuinely optional value, and choose a fallback that preserves the domain meaning. A missing rate or failed fetch is not zero, and a nonoptional `Asset.platform` needs no `?? ""`. Avoid force unwrapping; if an invariant justifies one, make the invariant visible near the use.

## Localization, Errors, and Logging

User-facing literals in `Text` and `Label` are extracted into String Catalogs; maintain English and Traditional Chinese (`zh-Hant`) entries. Use `String(localized:table:)` for strings created in ViewModels, services, and `LocalizedError.errorDescription`. Keep interpolated values inside a localizable string and avoid concatenating `Text` fragments to assemble sentences. Display an enum's `localizedName`, not its persistence `rawValue`. See [`AssetFlow/AGENTS.md`](../AssetFlow/AGENTS.md) for the catalog tables and patterns.

Report errors to the user in localized, actionable language. Localize each `LocalizedError` description. Keep the underlying error available to the handling layer without inserting raw parser or filesystem messages into user-facing text or logs when they may contain private data.

Do not use `print()` for diagnostics. When logging is needed, use `Logger` with operation and error categories that help diagnose a failure without recording portfolio values, asset or platform names, cash-flow descriptions, imported filenames, backup contents, or raw error descriptions that may repeat them. See [`SecurityAndPrivacy.md`](SecurityAndPrivacy.md#network-and-privacy) for the data boundary. A lint rule against `print()` cannot establish that logging is privacy-safe.

## Test Code Conventions

App tests use Swift Testing: name suites for the component or behavior, use descriptive `@Test` names, and keep reusable setup in private helpers. Place suites under the corresponding [`AssetFlowTests/`](../AssetFlowTests/) area, such as `Models/`, `Services/`, `ViewModels/`, or `Integration/`. Follow [`AssetFlowTests/AGENTS.md`](../AssetFlowTests/AGENTS.md) for test structure and [`TestingStrategy.md`](TestingStrategy.md) for what to verify.

When a helper creates an in-memory SwiftData context, retain its `ModelContainer` for the full test scope; discarding the container while keeping only the context can invalidate related models. The test instructions document the `TestContext` pattern.

## Python Repository Tooling

Python scripts are repository tooling, separate from the Swift app. [`.pre-commit-config.yaml`](../.pre-commit-config.yaml) runs isort before Black and includes Pyright. [`pyproject.toml`](../pyproject.toml) sets isort's Black profile and points Pyright at the repo-local `.venv`; pre-commit hook environments are separate. Follow those configurations for formatting and type-checking conventions. [`DevelopmentGuide.md`](DevelopmentGuide.md) owns environment setup and commands, while [`TestingStrategy.md`](TestingStrategy.md) owns Python test design.
