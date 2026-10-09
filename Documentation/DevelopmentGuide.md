# Development Guide

## Getting Started

### Prerequisites

Before you begin development, ensure you have the following installed:

- **Xcode 27.0+** (Swift 6.4 compiler, with Command Line Tools)
- **macOS Tahoe 26.6+** (for development; the app supports macOS 15.0+)
- **Git** (for version control)
- **[Git LFS](https://git-lfs.com/)** (for documentation screenshot images)
- **Homebrew** (recommended for tool installation)
- **[uv](https://docs.astral.sh/uv/)** (Python package manager for pre-commit, pytest and docs dependencies)

### Required Tools

- **swift-format** - Code formatting
- **SwiftLint** - Code style enforcement
- **uv** - Python virtual environment and package manager
- **pre-commit** - Git hooks for automation (installed via uv venv)
- **pytest** - Python script tests (installed via uv `dev` group)
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

   # Set up development tools in a project-local uv virtual environment
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
   - To review the dashboard with disposable sample assets and snapshots, add `--preview-data` under the Run scheme's **Arguments Passed On Launch**. This Debug-only mode uses an in-memory store and does not modify saved portfolio data.

### Python Runtime and Environment

The root `.python-version` pins Python 3.12 for local uv commands and every GitHub Actions job that runs Python. Workflows use `actions/setup-python` with `python-version-file: .python-version`, including jobs that call `python3` directly. uv creates the repo-local `.venv` using the same pin.

CI installs development or documentation dependencies with `uv sync --locked --only-group dev` or `uv sync --locked --only-group docs`, then runs tools through `uv run --locked` with the matching group. All uv workflow steps enable dependency caching keyed by `uv.lock`; pre-commit hook environments are cached separately with keys that also include `.python-version` and `.pre-commit-config.yaml`.

### App Version Metadata

- `version.txt` is the authoritative marketing version, using three numeric components (for example, `0.7.1`). Release Please's config and release-bookkeeping manifest are in `.github/release-please/`. Automation first synchronizes and commits all app target `MARKETING_VERSION` settings from `version.txt`, without replacement comments. Release PR formatting then runs on the synchronized branch, commits any fixes, and runs pre-commit again; remaining failures fail the job. Xcode generates `CFBundleShortVersionString` normally for Debug, Release and Testing.
- On macOS with Python 3.9+, run `python3 scripts/release_version.py check` to verify project versions, or `python3 scripts/release_version.py sync` after intentionally changing `version.txt`. The script uses built-in `plutil` and Python only; builds do not modify the source project. See [APIDesign.md](APIDesign.md#app-version-and-build-metadata) for synchronization details.
- Release Please enables `bump-minor-pre-major`: breaking changes increment the minor version while the current version is below `1.0.0` (for example, `0.7.1` → `0.8.0`). At `1.0.0` and later, breaking changes increment the major version. Feature and fix commits retain their usual minor and patch bumps.
- Local builds use the numeric `CURRENT_PROJECT_VERSION` configured in Xcode. Release archives set it to GitHub Actions' `GITHUB_RUN_NUMBER`, so distributed build numbers increase across workflow runs and may have gaps between releases.
- PR archive checks, unit tests and release builds share `.github/workflows/xcode-build.yml`, the `xcode-27` runner and Xcode 27.0. Both operations verify project versions; archive jobs also check the finished app's `CFBundleShortVersionString` against `version.txt` before packaging. CI archives disable signing. Packaging and artifact upload run only for releases.
- After release PR version synchronization and formatting finish, manually approve its pending PR workflows and wait for the required checks to pass before merging. Archive Check, Unit Tests and Pre-commit Checks retain their existing `pull_request` triggers. Project/workflow changes can remove version safeguards and require review.
- The release workflow downloads the packaged app artifact and attaches it to the GitHub release.
- The build script writes the first eight characters of the Git revision to the custom `AppCommit` property. It appends `-dirty` when the working tree has uncommitted changes. `CFBundleVersion` remains numeric and is not used for the commit ID.

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

### Python Script Tests

From the repository root on macOS, run:

```bash
uv run pytest
```

Pytest is part of the default uv `dev` group. uv synchronizes the project-local `.venv` automatically, and pytest discovers tests in `scripts/tests/` using the root `pyproject.toml`. To run only the release-version suite, use `uv run pytest scripts/tests/test_release_version.py`.

The release-version tests require macOS because they exercise `/usr/bin/plutil`. They use temporary project and archive fixtures, leaving the real project untouched. See [TestingStrategy.md](TestingStrategy.md#python-script-tests) for coverage and conventions.

The Unit Tests workflow runs Python tests in a separate macOS job alongside Swift tests. `astral-sh/setup-uv` enables dependency caching keyed by `uv.lock`; each job creates its own `.venv` with `uv sync --locked --only-group dev` and runs `uv run --locked --group dev python -m pytest`. The cache stores uv downloads, rather than the virtual environment.

### 3. Pre-Commit Checks

Pre-commit hooks are configured in `.pre-commit-config.yaml` and run automatically on `git commit`:

Run local checks through `uv run pre-commit run --all-files`. Although pre-commit itself runs in the repo-local `.venv`, its hooks use isolated environments. Pyright is configured to resolve project dependencies from `.venv`. Both the Pre-commit Checks workflow and release PR formatting job install the locked uv `dev` group before running checks, with uv caching keyed by `uv.lock`.

Both jobs restore `~/.cache/pre-commit` before running hooks, using the same cache key based on the runner OS, `.python-version`, `.pre-commit-config.yaml` and `uv.lock`. On a cache miss, pre-commit installs the hook environments and `actions/cache` saves them after a successful job. Release PR auto-fix and final verification reuse those environments within the job.

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

1. **Register in Schema** (update `SchemaV2.models` in `Models/SchemaVersioning.swift`):

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

Screenshots use shared styling in `mkdocs/assets/stylesheets/extra.css`, registered through `extra_css` in `mkdocs.yml`. Standalone screenshots are centered within the text column and scale down to fit. Introduce each image with relevant explanatory text, and separate images of different views into distinct explanations or subsections in both language versions.

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

## Changing Category Goals

Keep SchemaV1Models.swift frozen. Add current fields to a new active schema and prove migration with disposable disk fixtures; the app now uses SchemaV2 and AssetFlowMigrationPlan. Goal rules live in CategoryGoalValidator, RebalancingCalculator, and CategoryGoalAssessmentService. Currency/percentage formatting follows the existing Decimal conventions. Run test/build skills with required host access; normal formatter/linter work remains with pre-commit hooks. App catalogs use zh-Hant, while user guide content lives in mkdocs/zh-TW. Backup v4 parsing must retain v3 asset/cash-flow currencies and exchange rates.

## Category Editing and Compact Goal Presentation

Category draft edits remain in CategoryDetailViewModel until save. Keep CategoryEditingSession navigation guards when adding routes out of Categories. Information popovers use GoalHelpButton so lock transitions dismiss their content. Do not add a default Return shortcut to Save Changes; attach onSubmit only to editable text fields.
