# Development Guide

## Getting Started

### Prerequisites

Before you begin development, ensure you have the following installed:

- **Xcode 26.3+** (with Command Line Tools)
- **macOS 15.0+** (for development and running the app)
- **Git** (for version control)
- **[Git LFS](https://git-lfs.com/)** (for documentation screenshot images)
- **Homebrew** (recommended for tool installation)
- **[uv](https://docs.astral.sh/uv/)** (Python package manager for pre-commit and docs dependencies)

### Required Tools

- **swift-format** - Code formatting
- **SwiftLint** - Code style enforcement
- **uv** - Python virtual environment and package manager
- **pre-commit** - Git hooks for automation (installed via uv venv)
- **[Material for MkDocs](https://squidfunk.github.io/mkdocs-material/)** - Documentation site (installed via uv `docs` group)

### Initial Setup

1. **Clone the Repository**

   ```bash
   git clone git@github.com:jenchienchang/asset-flow.git AssetFlow
   cd AssetFlow
   ```

1. **Open in Xcode**

   ```bash
   open AssetFlow.xcodeproj
   ```

1. **Install Development Tools**

   ```bash
   # Install formatting and linting tools
   brew install swift-format
   brew install swiftlint

   # Install Git LFS (for documentation screenshots)
   brew install git-lfs
   git lfs install
   git lfs pull

   # Set up pre-commit in a project-local uv virtual environment
   uv sync
   uv run pre-commit install
   ```

1. **Build the Project**

   - In Xcode: Cmd+B
   - Command line: `xcodebuild -project AssetFlow.xcodeproj -scheme AssetFlow build`

1. **Run the Application**

   - In Xcode: Cmd+R
   - Target platform: macOS only
   - Debug builds produce `AssetFlow-Debug.app`; Release builds produce `AssetFlow.app`, allowing both builds to coexist in separate locations.

______________________________________________________________________

## Project Structure

```
AssetFlow/
+-- AssetFlow/                  # Main application code
|   +-- Models/                 # SwiftData models
|   +-- Views/                  # SwiftUI views
|   |   +-- Charts/             # Chart components (7 interactive charts)
|   |   +-- Components/         # Reusable view components (AssetTableView, CategoryPickerField, EditValuePopover, PlatformPickerField)
|   +-- ViewModels/             # ViewModels
|   +-- Services/               # Stateless services and utilities
|   +-- Utilities/              # Helper functions and extensions
|   +-- Resources/              # Assets, localization
|   +-- AssetFlowApp.swift      # App entry point
+-- AssetFlowTests/             # Test target (642+ tests across 44 files)
+-- AssetFlow.xcodeproj/        # Xcode project
+-- Documentation/              # Design documents (this folder)
+-- mkdocs/                     # Documentation site source (Material for MkDocs)
+-- overrides/                  # Material for MkDocs theme overrides
+-- .codex/                     # Codex agent instructions, review agents, and project-local skills
+-- .claude/                    # Claude Code commands, agents, settings, and skills
+-- .gitignore                  # Git ignore rules
+-- .swiftlint.yml              # SwiftLint configuration
+-- .swift-format               # swift-format configuration
+-- .editorconfig               # Editor settings
+-- .pre-commit-config.yaml     # Pre-commit hooks
+-- AGENTS.md                   # Codex instructions entrypoint
+-- CLAUDE.md                   # Claude Code instructions entrypoint
+-- README.md                   # Project overview
```

______________________________________________________________________

## Development Workflow

### 1. Creating a New Feature

**Branching Strategy**

```bash
# Create feature branch from main
git checkout main
git pull
git checkout -b feature/your-feature-name
```

**Implementation Steps**

1. Plan the feature (update models, views, services as needed)
1. Write code following style guidelines
1. Add tests (Swift Testing framework)
1. Test manually on macOS
1. Run linting and formatting
1. Commit with descriptive messages

### 2. Code -> Build -> Test Cycle

1. Make code changes
1. Run pre-commit checks:
   ```bash
   uv run pre-commit run --all-files
   ```
1. Build:
   ```bash
   xcodebuild -project AssetFlow.xcodeproj -scheme AssetFlow build
   ```
1. Run tests:
   ```bash
   xcodebuild -project AssetFlow.xcodeproj -scheme AssetFlow test -destination 'platform=macOS'
   ```
1. Run the app (Xcode Cmd+R)

**Manual tool usage** (if needed):

```bash
# Format Swift code only
swift-format format --in-place --recursive --parallel .

# Lint Swift code
swift-format lint --strict --recursive --parallel .

# Lint and fix with SwiftLint
swiftlint --fix

# Format markdown only
uv run pre-commit run mdformat --all-files
```

### 3. Pre-Commit Checks

Pre-commit hooks are configured in `.pre-commit-config.yaml` and run automatically on `git commit`:

**Automated Checks**:

- **Swift formatting**: Formats Swift code with swift-format
- **Swift linting**: Checks code style with SwiftLint
- **Markdown formatting**: Formats Markdown files with mdformat
- **MkDocs markdown formatting**: Formats MkDocs content with mdformat-mkdocs
- **Spelling check**: Checks spelling in documentation files with codespell
- **uv lock**: Validates `uv.lock` is up to date with `pyproject.toml`
- **Trailing whitespace**: Removes trailing whitespace
- **Case conflicts**: Checks for case-sensitive filename conflicts
- **Merge conflicts**: Prevents committing merge conflict markers
- **YAML validation**: Validates YAML file syntax (`check-yaml`)
- **Line ending normalization**: Converts line endings to LF (`mixed-line-ending --fix=lf`)
- **JSON formatting**: Formats JSON files with 2-space indent, preserving key order (`pretty-format-json --no-sort-keys`)

**Setup Pre-commit Hooks**:

```bash
# Set up the uv virtual environment (if not already created)
uv sync

# Install hooks for this repository
uv run pre-commit install

# Run hooks manually on all files
uv run pre-commit run --all-files
```

### 4. Committing Changes

**Commit Message Format**

```
<type>(<scope>): <subject>
```

**Types**:

- `feat`: New feature
- `fix`: Bug fix
- `refactor`: Code refactoring
- `docs`: Documentation changes
- `style`: Code style changes (formatting)
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

**Example**:

```bash
git commit -m "feat(import): Add CSV parsing for asset import"
```

Codex agents can use the project-local `$commit` skill to inspect staged changes and create a conventional commit message. The `$pull-request` skill writes `PR_DESCRIPTION.md` from the current branch diff against a target branch.

______________________________________________________________________

## Working with SwiftData

### Model Creation

1. **Create Model File** in `AssetFlow/Models/`

1. **Define Model**

   ```swift
   import SwiftData
   import Foundation

   @Model
   final class Category {
       var id: UUID
       var name: String
       var targetAllocationPercentage: Decimal?

       init(name: String, targetAllocationPercentage: Decimal? = nil) {
           self.id = UUID()
           self.name = name
           self.targetAllocationPercentage = targetAllocationPercentage
       }
   }
   ```

1. **Register in Schema** (update `SchemaV1.models` in `Models/SchemaVersioning.swift`):

   ```swift
   static var models: [any PersistentModel.Type] {
     [
       Category.self,
       Asset.self,
       Snapshot.self,
       SnapshotAssetValue.self,
       CashFlowOperation.self,
       ExchangeRate.self,
     ]
   }
   ```

1. **Update Documentation**

   - Update `AssetFlow/Models/README.md`
   - Update `Documentation/DataModel.md`

### Querying Data

**In SwiftUI Views**:

```swift
@Query(sort: \Snapshot.date, order: .reverse)
private var snapshots: [Snapshot]
```

**With Predicates**:

```swift
@Query(filter: #Predicate<Asset> { $0.platform == "Interactive Brokers" })
private var ibAssets: [Asset]
```

**Manual Context Access**:

```swift
@Environment(\.modelContext) private var modelContext

func addSnapshot() {
    let snapshot = Snapshot(date: Calendar.current.startOfDay(for: Date()))
    modelContext.insert(snapshot)
    // Save is automatic
}
```

______________________________________________________________________

## macOS Development

**Target**: macOS 15.0+

**Key Considerations**:

- Sidebar navigation with `NavigationSplitView`
- List-detail split for data browsing screens
- Minimum window size: 900 x 600 points
- Menu bar integration (Settings via Cmd+,)
- Keyboard shortcuts for common actions
- Right-click context menus
- Toolbar with import button
- Light and dark mode support

**Window Configuration**:

```swift
.frame(minWidth: 900, minHeight: 600)
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        Button("Import", systemImage: "square.and.arrow.down") { /* action */ }
    }
}
```

**No iOS or iPadOS development** -- the app targets macOS only in v1.

______________________________________________________________________

## Code Formatting and Linting

### swift-format (for Formatting)

```bash
# Format all files in place
swift-format format --in-place --recursive --parallel .

# Check for formatting issues without making changes
swift-format lint --strict --recursive --parallel .
```

Configuration: `.swift-format`

### SwiftLint (for Linting)

```bash
# Lint and automatically correct violations where possible
swiftlint --fix
```

Configuration: `.swiftlint.yml`. Key rules:

- Sorted imports
- No force unwrapping (warning)
- No `print()` statements (use `os.log`)
- Required file headers

______________________________________________________________________

## File Headers

**Required Format** (enforced by SwiftLint):

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

______________________________________________________________________

## App Lock Conventions

AssetFlow supports app locking via `AuthenticationService`. When the app is locked, a full-screen opaque overlay is shown over all windows. Two SwiftUI modifier conventions prevent financial data from leaking through this overlay:

### Tooltips: `.helpWhenUnlocked()` instead of `.help()`

Always use `.helpWhenUnlocked("…")` instead of `.help("…")` for tooltip help text. The standard `.help()` modifier shows tooltips even when the lock overlay is active, exposing content before the user has authenticated. `.helpWhenUnlocked()` suppresses the tooltip when the app is locked.

```swift
// Correct
Button("Info") { ... }
    .helpWhenUnlocked("Shows the current portfolio value")

// Incorrect — tooltip visible on lock screen
Button("Info") { ... }
    .help("Shows the current portfolio value")
```

### Hover interactions: `.onHoverWhenUnlocked()` and `.onContinuousHoverWhenUnlocked()`

Always use `.onHoverWhenUnlocked()` and `.onContinuousHoverWhenUnlocked()` instead of `.onHover()` and `.onContinuousHover()`. Hover callbacks (chart tooltips, highlight effects) can fire through the lock overlay, leaking financial data. The lock-aware variants reset hover state (`false` / `.ended`) when the app is locked.

```swift
// Correct
Rectangle()
    .onContinuousHoverWhenUnlocked { phase in
        // handle hover — only fires when unlocked
    }

// Incorrect — hover fires through lock overlay
Rectangle()
    .onContinuousHover { phase in
        // ...
    }
```

Both modifiers are defined in `AssetFlow/Utilities/WhenUnlockedModifiers.swift`.

______________________________________________________________________

## Localization

### Overview

AssetFlow uses Apple's **String Catalogs** (`.xcstrings`) for localization. English is the development language, with Traditional Chinese (`zh-Hant`) as an additional supported language.

### String Catalog Tables

Strings are organized into feature-scoped tables:

| Table file                        | Used by                                              | Scope                          |
| --------------------------------- | ---------------------------------------------------- | ------------------------------ |
| `Resources/Localizable.xcstrings` | SwiftUI views (auto-extracted), enum `localizedName` | Default table                  |
| `Resources/Snapshot.xcstrings`    | SnapshotDetailViewModel, SnapshotListViewModel       | Snapshot validation and errors |
| `Resources/Asset.xcstrings`       | AssetDetailViewModel, AssetListViewModel             | Asset validation and errors    |
| `Resources/Category.xcstrings`    | CategoryListViewModel, CategoryDetailViewModel       | Category validation and errors |
| `Resources/Import.xcstrings`      | ImportViewModel                                      | Import validation and errors   |
| `Resources/Platform.xcstrings`    | PlatformDetailViewModel, PlatformListViewModel       | Platform validation and errors |
| `Resources/Rebalancing.xcstrings` | RebalancingViewModel                                 | Rebalancing validation         |
| `Resources/Services.xcstrings`    | BackupService, SettingsService                       | Service error messages         |
| `Resources/Settings.xcstrings`    | SettingsViewModel                                    | Settings validation and errors |

### How Strings Are Localized

1. **SwiftUI views**: String literals in `Text()`, `Label()`, etc. are automatically extracted into `Localizable.xcstrings` by Xcode at build time.
1. **ViewModels and Services**: Use `String(localized:table:)` with the appropriate feature table:
   ```swift
   errorMessage = String(localized: "Category name cannot be empty.", table: "Category")
   ```
1. **Enums**: Use the `localizedName` computed property. Never display `rawValue` in UI.

### Adding New Strings

1. **In SwiftUI views**: Just use string literals -- Xcode auto-extracts them.
1. **In ViewModels/Services**: Wrap with `String(localized:table:)`.
1. **Build the project** to populate the String Catalogs.
1. **Open the `.xcstrings` file** in Xcode to add translations for `zh-Hant`.

### Adding a New Language

1. Open `AssetFlow.xcodeproj/project.pbxproj` and add the language code to `knownRegions`.
1. Build the project.
1. Open each `.xcstrings` file in Xcode and provide translations.

### Exporting/Importing Translations

```bash
# Export for translators
xcodebuild -exportLocalizations -project AssetFlow.xcodeproj -localizationPath ./Localizations

# Import translated .xliff files
xcodebuild -importLocalizations -project AssetFlow.xcodeproj -localizationPath ./Localizations/zh-Hant.xcloc
```

______________________________________________________________________

## Documentation Site

The user guide is built with [Material for MkDocs](https://squidfunk.github.io/mkdocs-material/). Source files live in `mkdocs/` and the configuration is in `mkdocs.yml`.

### Local Development

```bash
# Start the live-reloading dev server (http://127.0.0.1:8000)
uv run mkdocs serve

# Build the static site (output: site/)
uv run mkdocs build
```

### Versioning

The site uses [mike](https://github.com/jimporter/mike) for multi-version docs. CI deploys automatically via `.github/workflows/docs.yml`:

- Pushes to `main` (when docs change) deploy the `dev` version
- GitHub releases deploy a tagged version with the `latest` alias

```bash
# Manual deployment (if needed)
uv run mike deploy --push --update-aliases v1.0.0 latest
uv run mike set-default --push latest
uv run mike serve   # Preview all deployed versions
```

See `mkdocs/README.md` for the full directory structure and contribution guide.

______________________________________________________________________

## Debugging

### Xcode Debugging

- **Breakpoints**: Click gutter to add; right-click for conditional breakpoints
- **View Debugging**: Debug > View Debugging > Capture View Hierarchy
- **Memory Graph**: Debug > Memory Graph

### Logging

Use `os.log` (not `print()`):

```swift
import os.log

let logger = Logger(subsystem: "com.yourname.AssetFlow", category: "Import")

logger.info("CSV import started for file: \(url.lastPathComponent)")
logger.error("Failed to parse CSV: \(error.localizedDescription)")
```

### SwiftData Debugging

Enable SQL logging via launch argument in scheme:

```
-com.apple.CoreData.SQLDebug 1
```

______________________________________________________________________

## Building for Release

### Build Configuration

- **Debug**: Full symbols, assertions enabled
- **Release**: Optimized, symbols stripped, Hardened Runtime enabled

### macOS Distribution

1. **Xcode**: Product > Archive
1. Organizer opens with archive
1. Distribute App > Choose method
1. Sign with Developer ID certificate
1. Notarize for distribution
1. Hardened Runtime enabled

______________________________________________________________________

## Troubleshooting

### Common Issues

**SwiftData not persisting**:

- Check ModelContainer is injected at app root
- Verify schema registration
- Check console for SwiftData errors

**UI not updating**:

- Ensure ViewModel uses `@Observable`
- Verify View uses `@State` for ViewModel
- Check `@Query` predicate

**Build failures**:

- Clean build folder: Shift+Cmd+K
- Delete derived data: `~/Library/Developer/Xcode/DerivedData/`
- Restart Xcode

**Linting errors**:

- Run `swift-format format --in-place` before committing
- Check `.swiftlint.yml` for custom rules
- Add `// swiftlint:disable:next <rule>` for exceptions (use sparingly)

### Getting Help

- Check [CLAUDE.md](../CLAUDE.md) for project conventions
- Review [Architecture.md](Architecture.md) for design patterns
- Consult Apple's SwiftUI/SwiftData documentation
- Search existing code for similar patterns

______________________________________________________________________

## Code Review Checklist

Before submitting code:

- [ ] Code follows style guidelines
- [ ] File headers are correct
- [ ] No `print()` statements (use logging)
- [ ] SwiftLint passes without warnings
- [ ] swift-format applied
- [ ] Financial values use `Decimal`
- [ ] Documentation updated (if applicable)
- [ ] Models registered in Schema (if new)
- [ ] Tested on macOS
- [ ] No force unwrapping without good reason
- [ ] Commit messages are descriptive
- [ ] Build produces zero warnings
- [ ] All tooltip help text uses `.helpWhenUnlocked()` (not `.help()`)
- [ ] All hover interactions use `.onHoverWhenUnlocked()` / `.onContinuousHoverWhenUnlocked()` (not `.onHover()` / `.onContinuousHover()`)

______________________________________________________________________

## Performance Best Practices

### SwiftUI

- Use `@State` for simple local state
- Minimize view body complexity
- Extract subviews for reusability
- Use `.task()` for async operations
- Use `#Preview` macro with traits for macOS-specific preview sizing:
  ```swift
  #Preview(traits: .fixedLayout(width: 900, height: 600)) {
      DashboardView()
          .modelContainer(PreviewContainer.container)
  }
  ```
- Use `@Previewable` macro for preview-specific state injection

### SwiftData

- Use predicates to filter queries
- Avoid loading entire relationship graphs
- Batch operations for CSV imports
- Profile with Instruments

______________________________________________________________________

## Resources

### Documentation

- [Architecture.md](Architecture.md) - App architecture
- [DataModel.md](DataModel.md) - Data models
- [CodeStyle.md](CodeStyle.md) - Style guide
- [TestingStrategy.md](TestingStrategy.md) - Testing approach
- [mkdocs/README.md](../mkdocs/README.md) - Documentation site setup

### External Resources

- [Swift.org](https://swift.org/documentation/)
- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui/)
- [SwiftData Documentation](https://developer.apple.com/documentation/swiftdata/)
- [Swift Charts Documentation](https://developer.apple.com/documentation/charts)
- [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)

### Tools

- [SwiftLint](https://github.com/realm/SwiftLint)
- [swift-format](https://github.com/apple/swift-format)
- [SF Symbols](https://developer.apple.com/sf-symbols/) - Icon library
