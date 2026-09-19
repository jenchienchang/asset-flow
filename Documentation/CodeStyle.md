# Code Style Guide

## Overview

This document defines the code style standards for the AssetFlow project. Consistency in code style improves readability, maintainability, and collaboration.

## Enforcement

Code style is enforced through:

- **`swift-format`**: Automated code formatting. Configuration in `.swift-format`.
- **`SwiftLint`**: Static analysis for stylistic and convention-based rules. Configuration in `.swiftlint.yml`.
- **EditorConfig**: Editor settings (`.editorconfig`)
- **Pre-commit hooks**: Automated checks before commits (`.pre-commit-config.yaml`)

______________________________________________________________________

## General Principles

1. **Clarity over brevity**: Code should be self-documenting
1. **Consistency**: Follow established patterns in the codebase
1. **Swift API Design Guidelines**: Follow Apple's official guidelines
1. **Type safety**: Leverage Swift's type system
1. **Immutability**: Prefer `let` over `var` when possible

______________________________________________________________________

## File Organization

### File Structure

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

// 1. Imports (sorted alphabetically)
import Foundation
import SwiftData
import SwiftUI

// 2. Type definitions
// 3. Extensions
// 4. Helper types (if small and related)
```

### Import Organization

**Order**:

1. System frameworks (alphabetically)
1. Third-party dependencies (alphabetically)
1. Internal modules (alphabetically)

**SwiftLint Rule**: Imports must be sorted alphabetically.

______________________________________________________________________

## Naming Conventions

### Types

**Classes, Structs, Enums, Protocols**: `UpperCamelCase`

```swift
class SnapshotDetailViewModel { }
struct Category { }
enum ImportType { }
protocol CalculationResolving { }
```

### Variables and Functions

**Variables, Constants, Functions**: `lowerCamelCase`

```swift
var marketValue: Decimal
let snapshotDate: Date
func calculateCompositeValue() -> Decimal
```

### Acronyms

Follow Swift standard library convention: short acronyms (2-3 letters) remain uppercase, longer ones are treated as words:

```swift
// Good
let urlString: String
let csvParser: CSVParsingService
class HTTPClient { }       // Short acronym: all caps
var jsonDecoder: JSONDecoder

// Bad
let uRLString: String
let cSVParser: CSVParsingService
class HttpClient { }       // Should be HTTPClient
```

### Boolean Properties

Use `is`, `has`, `should`, or `can` prefixes:

```swift
var isImportDisabled: Bool
var hasSnapshotValues: Bool
var canDeleteAsset: Bool
```

______________________________________________________________________

## Code Formatting

### Line Length

- **Warning**: 120 characters
- **Error**: 150 characters

### Indentation

- **4 spaces** (no tabs)
- Configuration: `.editorconfig`, `.swift-format`

### Braces

Opening brace on same line, closing brace on new line:

```swift
if condition {
    // code
}
```

### Blank Lines

- One blank line between functions
- One blank line between types
- No blank line at start/end of braces

______________________________________________________________________

## Type Declarations

### Classes and Structs

**Use structs by default**, classes when needed for:

- Reference semantics
- SwiftData models (`@Model` requires class)
- ViewModels (`@Observable` requires class)

### Sendable Conformance

For Swift 6 strict concurrency compatibility, all data types passed across isolation boundaries must conform to `Sendable`. In particular:

- Service data types (structs used as inputs/outputs, such as `CSVParseResult`, `RebalancingAction`) should conform to `Sendable`
- Using `enum` for stateless services naturally avoids actor isolation issues
- Pure helpers that access only their value-type inputs should be marked `nonisolated` when they are used from nonisolated code
- Avoid `@unchecked Sendable` and `nonisolated(unsafe)` unless the shared-state invariant is documented and tested

### Properties

**Computed properties** when appropriate:

```swift
var totalValue: Decimal {
    assetValues?.reduce(0) { $0 + $1.marketValue } ?? 0
}
```

### Type Inference

Use type inference when obvious:

```swift
// Good
let name = "Category"
let count = 5
let items: [Asset] = []  // Explicit when empty

// Avoid
let name: String = "Category"
let count: Int = 5
```

______________________________________________________________________

## Functions

### Declaration

```swift
func functionName(parameterLabel argumentName: Type) -> ReturnType {
    // implementation
}
```

### Multiple Parameters

Line breaks for readability (>3 parameters or long):

```swift
func createSnapshotAssetValue(
    snapshotID: UUID,
    assetID: UUID,
    marketValue: Decimal
) -> SnapshotAssetValue
```

### Function Length

- **Warning**: 60 lines
- **Error**: 100 lines
- Extract into smaller functions when needed

______________________________________________________________________

## Control Flow

### guard Statements

**Early exit pattern**:

```swift
func deleteCategory(_ category: Category) throws {
    guard category.assets?.isEmpty ?? true else {
        throw CategoryError.cannotDeleteWithAssignedAssets
    }
    modelContext.delete(category)
}
```

### switch Statements

**Prefer switch over if-else chains**:

```swift
switch importType {
case .assets:
    parseAssetCSV(url)
case .cashFlows:
    parseCashFlowCSV(url)
}
```

______________________________________________________________________

## Optionals

### Unwrapping

**Prefer optional binding**:

```swift
if let snapshot = selectedSnapshot {
    showDetail(for: snapshot)
}

guard let category = category else { return }
```

**Avoid force unwrapping** (generates SwiftLint warning).

### Nil Coalescing

```swift
let platform = asset.platform ?? ""
let netCashFlow = cashFlows?.reduce(0) { $0 + $1.amount } ?? 0
```

______________________________________________________________________

## SwiftUI-Specific

### View Structure

```swift
struct SnapshotDetailView: View {
    // 1. Property wrappers
    @State private var viewModel: SnapshotDetailViewModel
    @State private var showingAddAsset = false

    // 2. Body
    var body: some View {
        content
    }

    // 3. Extracted view builders
    private var content: some View {
        VStack {
            assetTable
            cashFlowSection
        }
    }
}
```

### ViewBuilder

Extract complex views into computed properties:

```swift
var body: some View {
    content
}

private var content: some View {
    VStack {
        header
        mainContent
        footer
    }
}
```

### Modifiers

Order (generally):

1. Layout modifiers (frame, padding)
1. Style modifiers (foregroundColor, font)
1. Behavior modifiers (onTapGesture, task)

### Property Wrappers Order

```swift
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var snapshots: [Snapshot]
    @State private var viewModel: ViewModel
    @State private var isPresented = false
    @Binding var selectedSnapshot: Snapshot?
}
```

______________________________________________________________________

## SwiftData-Specific

### Model Definition

```swift
import SwiftData
import Foundation

@Model
final class Asset {
    // 1. Stored Properties
    var id: UUID
    var name: String
    var platform: String
    var currency: String

    // 2. Relationships
    @Relationship(deleteRule: .nullify)
    var category: Category?

    @Relationship(deleteRule: .deny, inverse: \SnapshotAssetValue.asset)
    var snapshotAssetValues: [SnapshotAssetValue]?

    // 3. Initializer
    init(name: String, platform: String = "") {
        self.id = UUID()
        self.name = name
        self.platform = platform
        self.currency = ""
    }
}
```

______________________________________________________________________

## Financial Data

### Critical Rule: Use Decimal

**Always use `Decimal`** for monetary values:

```swift
// Good
var marketValue: Decimal
var targetAllocationPercentage: Decimal?
let total: Decimal = 100.50

// Bad - NEVER use Float/Double for money
var marketValue: Double  // NO
var targetAllocation: Float  // NO
```

### Display Currency

- Default display currency: `"USD"` (cosmetic only, no FX conversion)
- Use extensions from `Utilities/Extensions.swift`:

```swift
let formatted = value.formatted(currency: "USD")  // "$1,234.56"
let percentage = ratio.formattedPercentage()       // "12.34%"
```

### Parsing User Input

Use `Decimal.parse(_:locale:)` for parsing user-entered numeric strings. Never use `Decimal(string:)` directly for UI text field input — it doesn't handle locale-specific separators.

```swift
// Good — locale-aware parsing handles "1,000" correctly
guard let value = Decimal.parse(amountText) else { return }

// Bad — "1,000" returns nil or parses incorrectly
guard let value = Decimal(string: amountText) else { return }
```

`Decimal.parse()` uses `NumberFormatter` internally, supporting:

- Thousands separators (comma in US, period in Germany, space in France)
- Decimal separators (period in US, comma in Germany)
- Currency symbols ($, €, £, ¥, ₩, ₹)
- Leading/trailing whitespace

**Note**: CSV parsing uses `CSVParsingService.parseDecimalValue()` which has different rules (strips all commas) since CSV files use a canonical format.

______________________________________________________________________

## Localization

### String Localization in ViewModels and Services

All user-facing strings in ViewModels and Services must be localized:

```swift
// Good
nameValidationMessage = String(localized: "Category name cannot be empty.", table: "Category")

// Bad -- not localized
nameValidationMessage = "Category name cannot be empty."
```

### Enum Display Names

Never display enum `rawValue` directly in the UI. Use `localizedName`:

```swift
// Good
Text(importType.localizedName)

// Bad
Text(importType.rawValue)
```

### String Concatenation in Views

Avoid `+` concatenation inside `Text()` -- it breaks localization auto-extraction:

```swift
// Good (single literal)
Text("This asset cannot be deleted because it has values in snapshot(s).")

// Bad (concatenation breaks localization)
Text("This asset cannot be deleted" + " because it has values.")
```

______________________________________________________________________

## macOS-Specific Code

AssetFlow targets macOS only (15.0+). No `#if os(iOS)` or `#if os(iPadOS)` compiler directives are needed.

```swift
// macOS window configuration
.frame(minWidth: 900, minHeight: 600)
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        Button("Import", systemImage: "square.and.arrow.down") { /* action */ }
    }
}
```

______________________________________________________________________

## Documentation

### File Headers

**Required** (enforced by SwiftLint):

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

### Inline Comments

Document complex logic. Avoid obvious comments:

```swift
// BAD
// Set name to "Category"
name = "Category"

// GOOD - explains WHY
// Normalize platform name for case-insensitive matching
let normalized = platform.trimmingCharacters(in: .whitespaces).lowercased()
```

### Doc Comments

Use for public APIs:

```swift
/// Calculates the total portfolio value for a snapshot.
///
/// - Parameters:
///   - snapshot: The target snapshot
/// - Returns: Total value as the sum of all SnapshotAssetValues
static func totalValue(
    for snapshot: Snapshot
) -> Decimal
```

______________________________________________________________________

## Error Handling

### Custom Errors

```swift
enum ImportError: LocalizedError {
    case missingRequiredColumns([String])
    case duplicateAssetsInCSV([(row1: Int, row2: Int, name: String)])
    case emptyFile

    var errorDescription: String? {
        switch self {
        case .missingRequiredColumns(let columns):
            return "Missing required columns: \(columns.joined(separator: ", "))"
        case .duplicateAssetsInCSV(let duplicates):
            return "Duplicate assets found in CSV"
        case .emptyFile:
            return "File contains no data rows"
        }
    }
}
```

______________________________________________________________________

## Logging

### No print() Statements

**SwiftLint Custom Rule**: `print()` statements are **prohibited**.

### Use os.log Instead

```swift
import os.log

let logger = Logger(
    subsystem: "com.yourname.AssetFlow",
    category: "Import"
)

// Log levels
logger.debug("Debug information")
logger.info("CSV import completed successfully")
logger.warning("Zero market value detected for asset")
logger.error("Failed to parse CSV: \(error.localizedDescription)")
```

______________________________________________________________________

## Code Review Guidelines

### What to Look For

- [ ] Follows naming conventions
- [ ] Proper use of `Decimal` for financial data
- [ ] No `print()` statements
- [ ] File headers present
- [ ] Appropriate access control
- [ ] Optional handling is safe
- [ ] Functions are focused and short
- [ ] Comments explain "why" not "what"
- [ ] SwiftLint warnings addressed
- [ ] Formatted with swift-format
- [ ] Localization used for user-facing strings
- [ ] No force unwrapping without good reason

______________________________________________________________________

## Project-Specific Patterns

### Test Isolation (TestContext Pattern)

**Problem**: `ModelContainer` must be retained for the entire test scope. If a helper creates a container, the caller must hold a strong reference to it. Otherwise, ARC deallocates the container early and crashes occur on `@Relationship` property access ("model instance destroyed by calling ModelContext.reset").

**Solution**: Use a `TestContext` struct to bundle container + context + model objects:

```swift
private struct TestContext {
    let container: ModelContainer
    let context: ModelContext
}

private func createTestContext() -> TestContext {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    return TestContext(container: container, context: context)
}

// Usage — container stays alive through `tc` for entire test scope
let tc = createTestContext()
let viewModel = DashboardViewModel(modelContext: tc.context)
```

**Note**: Never use `_ = helper()` or `let (_, context, ...) = helper()` — this discards the container immediately.

### Stable Identifiable IDs in Computed Properties

**Problem**: Using `let id = UUID()` in structs created inside computed properties (e.g., chart data) generates new UUIDs on every body evaluation. SwiftUI/Charts treats every render as a full data replacement, breaking animations and diffing.

**Solution**: Use stable composite keys based on data content:

```swift
// BAD — new UUID every recompute
struct ChartPoint: Identifiable {
    let id = UUID()
    let date: Date
    let category: String
}

// GOOD — stable identity
struct ChartPoint: Identifiable {
    var id: String { "\(category)-\(date.timeIntervalSince1970)" }
    let date: Date
    let category: String
}
```

### Naming to Avoid Protocol Conflicts

**Problem**: Property names like `description` conflict with Swift's built-in `CustomStringConvertible` protocol requirement.

**Solution**: Use domain-specific names that avoid conflicts:

```swift
// Instead of:
struct CashFlowOperation {
    var description: String  // Conflicts with CustomStringConvertible
}

// Use:
struct CashFlowOperation {
    var cashFlowDescription: String  // Clear, no conflict
}
```

**Example**: `CashFlowOperation.cashFlowDescription` is used instead of `.description` to avoid protocol conflicts while maintaining clarity.

### Animating Empty↔Content Transitions

**Problem**: Using `.animation(_:value:)` on ViewModel-based views animates the initial `.onAppear` data load, causing a flash of the empty state on every navigation. Adding `.transition(.opacity)` to empty/content branches is also unnecessary and may cause jitter.

**Solution**: Do NOT add `.transition(.opacity)` to empty/content branches. The `withAnimation` in user-action code paths smoothly updates list content; the empty↔content switch itself should be instant. Views using `@Query` (data available synchronously) can use `.animation(_:value:)` safely.

```swift
// BAD — flashes empty state on initial navigation
Group {
    if viewModel.isEmpty { emptyState.transition(.opacity) }
    else { content.transition(.opacity) }
}
.animation(.easeOut, value: viewModel.isEmpty)
.onAppear { viewModel.load() }

// GOOD — instant empty↔content swap, withAnimation only for list content changes
Group {
    if viewModel.isEmpty { emptyState }
    else { content }
}
.onAppear { viewModel.load() }
.onChange(of: dataFingerprint) {
    withAnimation(AnimationConstants.standard) { viewModel.load() }
}
```

All animation durations are defined in `AnimationConstants` (`Utilities/AnimationConstants.swift`), which automatically respects the Reduce Motion accessibility setting.

### ViewModel Auto-Reload with `withObservationTracking`

**Problem**: ViewModels compute aggregate/converted values eagerly in their load method (called from `.onAppear`). When external dependencies change (e.g., display currency, asset currency, exchange rates), computed values become stale.

**Solution**: Wrap the load method body with `withObservationTracking`. All `@Observable`/`@Model` property reads during execution are automatically tracked. When any tracked property changes, `onChange` fires and re-triggers the load.

```swift
func loadData() {
  withObservationTracking {
    performLoadData()
  } onChange: { [weak self] in
    Task { @MainActor [weak self] in
      self?.loadData()
    }
  }
}
private func performLoadData() { /* original load body */ }
```

**Convention**: Always use double `[weak self]` — on both the outer `onChange` closure and the inner `Task` closure. This prevents the ViewModel from being retained after its `ModelContainer` is deallocated, which causes SIGTRAP crashes in tests with in-memory containers.

______________________________________________________________________

## Tools Configuration

### .swift-format

```json
{
  "version": 1,
  "indentation": {
    "spaces": 4
  },
  "lineLength": 100,
  "respectsExistingLineBreaks": true
}
```

### .swiftlint.yml

Key rules:

- `line_length`: warning: 120, error: 150
- `function_body_length`: warning: 60, error: 100
- `custom_rules.no_print`: Prohibit `print()`
- `sorted_imports`: Required

### .editorconfig

```ini
[*.swift]
indent_style = space
indent_size = 4
end_of_line = lf
charset = utf-8
trim_trailing_whitespace = true
insert_final_newline = true
```

______________________________________________________________________

## References

- [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- [SwiftLint Rules](https://realm.github.io/SwiftLint/rule-directory.html)
- [swift-format](https://github.com/apple/swift-format)
- Project configurations: `.swiftlint.yml`, `.swift-format`, `.editorconfig`
