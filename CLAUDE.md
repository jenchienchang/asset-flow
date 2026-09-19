# CLAUDE.md

## Project Overview

AssetFlow is a macOS 15.0+ desktop app for snapshot-based portfolio management and asset allocation tracking. Built with SwiftUI, SwiftData, and Swift Charts. Local-first; network access limited to exchange rate fetching (cdn.jsdelivr.net).

## Build Commands

```bash
xcodebuild -project AssetFlow.xcodeproj -scheme AssetFlow build
```

**Testing**: Use the `/test` skill to run unit tests (see `AssetFlowTests/CLAUDE.md`) instead of xcodebuild unless the skill asks for.

**Formatting and linting are handled by pre-commit hooks — do not run them manually after edits.** They run automatically at commit time. Manual invocation if needed:

```bash
swift-format format --in-place --recursive --parallel .
swift-format lint --strict --recursive --parallel .
swiftlint --fix
```

## Architecture

MVVM with SwiftData. Models: `@Model` classes (see `Models/README.md`). Views: SwiftUI. ViewModels: `@Observable @MainActor` classes. Services: stateless utilities and singleton services (see `AssetFlow/CLAUDE.md`).

```
Category (1:Many) → Asset
Asset (Many:Many via SnapshotAssetValue) → Snapshot
Snapshot (1:Many) → SnapshotAssetValue
Snapshot (1:Many) → CashFlowOperation
Snapshot (1:1) → ExchangeRate
```

All models registered in `SchemaV1` (`Models/SchemaVersioning.swift`). When adding models, update `SchemaV1.models`, `Models/README.md`, and `Documentation/DataModel.md`.

**Xcode:** When adding files/features, update targets, `Info.plist`, entitlements, and scheme configs as needed.

## Documentation

Source of truth: `Documentation/SPEC.md`. Design docs in `Documentation/`: Architecture, DataModel, DevelopmentGuide, CodeStyle, TestingStrategy, UserInterfaceDesign, BusinessLogic, SecurityAndPrivacy, APIDesign.

Before completing any task, review and update affected docs. Key mappings:

| Change Type              | Update                             |
| ------------------------ | ---------------------------------- |
| Add/modify model         | `Models/README.md`, `DataModel.md` |
| Architecture/service     | `Architecture.md`, `APIDesign.md`  |
| UI/screen                | `UserInterfaceDesign.md`           |
| Business rule            | `BusinessLogic.md`                 |
| Security/privacy         | `SecurityAndPrivacy.md`            |
| Testing approach         | `TestingStrategy.md`               |
| Coding convention        | `CodeStyle.md`                     |
| Build command/dependency | `DevelopmentGuide.md`, this file   |

**Markdown conventions:** Use `1.` for all ordered list items. Don't manually adjust table column widths (`mdformat` hook handles it).

## Code Quality

- `swift-format` (config: `.swift-format`) and `SwiftLint` (config: `.swiftlint.yml`)
- **Python dependencies**: Use `uv add --group <group> <package>` to add dependencies (never edit `pyproject.toml` directly). Groups: `dev` (pre-commit), `docs` (mkdocs/mike)
- Pre-commit runs from a project-local uv venv (`.venv/`). Setup: `uv sync && uv run pre-commit install`
- Pre-commit hooks run both automatically. Manual: `uv run pre-commit run --all-files`
- Fix all compilation warnings before committing — treat warnings as errors

## Critical Conventions

- **Financial data**: Always `Decimal` for monetary values (never Float/Double). See `AssetFlow/CLAUDE.md` for `formattedPercentage()` details.
- **Localization**: String Catalogs (`.xcstrings`), English + Traditional Chinese (`zh-Hant`). See `AssetFlow/CLAUDE.md` for patterns.
- **Commits**: [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) — `type(scope): description`. Types: `feat`, `fix`, `refactor`, `ci`, `build`, `chore`, `docs`, `style`, `test`, `perf`. Scope optional but encouraged (e.g., `feat(dashboard):`). Breaking changes: append `!` (e.g., `feat!:`) or add `BREAKING CHANGE:` footer. Every commit message must include a body, and every body line must be 72 characters or fewer.
- **Git state and history**: Do not run any Git operation that changes the working tree, index, refs, or history without the user's explicit approval for that operation. This includes staging or unstaging, restoring files, cleaning files, commits and amendments, resets, reverts, merges, rebases, cherry-picks, branch or tag changes, pulls, and pushes. Read-only commands such as `git status`, `git diff`, `git log`, and `git show` are allowed.
- **Commit approval workflow**: When the user invokes the `commit` skill or directly asks for a commit, inspect the staged changes and show the full proposed commit message before running `git commit`. Treat the initial request as authorization to prepare only; wait for explicit approval of that exact message before creating the commit. If the message changes, show the revised message and wait for approval again.
- **Testing**: Swift Testing (`import Testing`), NOT XCTest. TDD: red-green-refactor — RED phase must produce assertion failures, not compilation errors. Use `/test` skill to run tests. See `AssetFlowTests/CLAUDE.md`.
- **Tooltip help text**: Always use `.helpWhenUnlocked("…")` instead of `.help("…")`. The app uses `AuthenticationService` for app lock; `.help()` exposes tooltip content on the lock screen, while `.helpWhenUnlocked()` only shows tooltips after the user has authenticated.
- **Hover interactions**: Always use `.onHoverWhenUnlocked()` and `.onContinuousHoverWhenUnlocked()` instead of `.onHover()` and `.onContinuousHover()`. Hover effects (chart tooltips, highlights) can leak data through the lock overlay. See `AssetFlow/Utilities/WhenUnlockedModifiers.swift`.
- **macOS only (v1)**: No iOS/iPadOS. No `#if os(...)` needed.

## Notes

- Codex will review your changes after you complete every tasks.
