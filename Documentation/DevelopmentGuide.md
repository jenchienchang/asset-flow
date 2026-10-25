# Development Guide

This guide covers contributor setup and repeatable development procedures for AssetFlow. The app is a macOS project; Python supports repository checks, release tooling, and the documentation site. [`SPEC.md`](SPEC.md) owns intended product behavior, [`CodeStyle.md`](CodeStyle.md) owns implementation conventions, and [`TestingStrategy.md`](TestingStrategy.md) owns verification design.

Commands below use the repository root unless another location is stated. Git-changing and publication commands are contributor procedures, not standing authorization for coding agents. Follow [`AGENTS.md`](../AGENTS.md) and applicable agent instructions before an agent performs them.

## Shared Setup

### Development environment

The app's deployment target is macOS 15.0+. The shared `AssetFlow` scheme uses Debug to run, Testing to test, and Release to archive. CI selects Xcode 27.0 on the `xcode-27` runner; use that version when reproducing CI results. Xcode 27 includes the Swift 6.4 compiler, while the project sets Swift 6 language mode. [Apple's Xcode 27 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes) specify macOS Tahoe 26.6 or later and an Apple silicon Mac to run Xcode 27. These are development-host requirements, separate from the app's deployment target.

Install Git, [Git LFS](https://git-lfs.com/), [uv](https://docs.astral.sh/uv/), `swift-format`, and SwiftLint. Homebrew is a convenient way to install these command-line tools. Git LFS retrieves documentation screenshots and is installed separately from the Python packages in uv's `dev` and `docs` groups.

For a new human contributor, the commands below assume Homebrew and GitHub SSH access. Clone in the desired parent directory, then run the remaining commands from the repository root:

```bash
git clone git@github.com:jenchienchang/asset-flow.git asset-flow
cd asset-flow
brew install uv swift-format swiftlint git-lfs
git lfs install
git lfs pull
uv run pre-commit install --hook-type pre-commit --hook-type commit-msg
open AssetFlow.xcodeproj
```

`git lfs pull` populates screenshot files in the checkout. `uv run` creates or syncs the project-local `.venv` with the default `dev` group; it does not install the separate `docs` group. The `pre-commit install` command installs local Git hooks for file checks and the configured commit-message check. Hook environments are installed separately when first needed. See [pre-commit's installation options](https://pre-commit.com/#pre-commit-install) for the two hook types.

### Repository map

| Path                                                                                                                                | Purpose                                                                   |
| ----------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| [`AssetFlow/`](../AssetFlow/)                                                                                                       | SwiftUI app, ViewModels, models, services, utilities, and string catalogs |
| [`AssetFlowTests/`](../AssetFlowTests/)                                                                                             | Swift Testing target and isolated model fixtures                          |
| [`AssetFlow.xcodeproj/`](../AssetFlow.xcodeproj/)                                                                                   | Project settings and the shared app scheme                                |
| [`Documentation/`](./)                                                                                                              | Maintained design documents and this contributor guide                    |
| [`mkdocs/`](../mkdocs/), [`mkdocs.yml`](../mkdocs.yml), [`overrides/`](../overrides/)                                               | User guide source, site configuration, and theme overrides                |
| [`scripts/`](../scripts/), [`scripts/tests/`](../scripts/tests/)                                                                    | Repository release tooling and pytest suites                              |
| [`pyproject.toml`](../pyproject.toml), [`uv.lock`](../uv.lock), [`.python-version`](../.python-version)                             | Python requirements, resolved dependencies, and runtime pin               |
| [`.pre-commit-config.yaml`](../.pre-commit-config.yaml), [`.swift-format`](../.swift-format), [`.swiftlint.yml`](../.swiftlint.yml) | Automated checks and Swift tool configuration                             |
| [`Makefile`](../Makefile), [`.github/workflows/`](../.github/workflows/)                                                            | Local archive shortcut and CI/release workflows                           |

## Swift App Development

### Build, run, and test

Open `AssetFlow.xcodeproj`, select the shared `AssetFlow` scheme and a macOS destination, then use Command-B to build or Command-R to run. From the repository root, a human contributor can run the project build entry point:

```bash
xcodebuild -project AssetFlow.xcodeproj -scheme AssetFlow build
```

The command compiles the app and writes products to Xcode's build directory; inspect the result and resolve warnings before committing. If the wrong toolchain runs, check `xcodebuild -version` and the selected Xcode installation before changing project settings. App tests use Swift Testing. A human contributor can use Xcode's Test action or this repository-root command; the shared scheme selects its Testing configuration:

```bash
xcodebuild -project AssetFlow.xcodeproj -scheme AssetFlow test -destination 'platform=macOS'
```

CI runs the same Xcode test operation. When a failed Swift test run has a result bundle, CI prints and uploads a compact JSON report with the failed test names and assertions. Coding agents use the [build skill](../.codex/skills/build/SKILL.md) for compilation and the [test skill](../.codex/skills/test/SKILL.md) for Swift tests, including their host-access and log-inspection rules. The [test instructions](../AssetFlowTests/AGENTS.md) and [`TestingStrategy.md`](TestingStrategy.md) explain test structure and the evidence each test type provides. Python tests have a separate entry point below.

For routine app changes, build, run the relevant Swift tests, and exercise affected interactions where needed. Formatting and linting run through installed hooks at commit time; they are not an extra required step after every edit. A documentation-only change normally needs link and example checks instead of an app build.

### Disposable data and previews

To inspect the dashboard without using a saved portfolio, add `--preview-data` to the Run scheme's **Arguments Passed On Launch** and run a Debug build. [`AssetFlowApp.swift`](../AssetFlow/AssetFlowApp.swift) selects an in-memory `ModelContainer` and seeds sample assets and snapshots for that mode. Remove the argument when returning to the normal store.

To inspect converted asset history with a missing rate, launch a Debug build with `--preview-missing-rates`. This opens an in-memory asset on the Assets screen with converted chart mode selected and exchange-rate fetching disabled for the fixture. Remove the argument when returning to the normal store.

To inspect the Bulk Entry CSV loading indicator, launch a Debug build with `--preview-bulk-entry-csv-loading`. This opens Bulk Entry with in-memory sample data and keeps the importing platform's indicator visible until Cancel is selected or the window closes. The preview does not read a CSV or use the saved portfolio.

For SwiftUI previews, follow nearby `#Preview` declarations, such as [`SnapshotListView.swift`](../AssetFlow/Views/SnapshotListView.swift). They use `PreviewContainer.container` rather than the normal disk-backed app store. Keep the preview container alive for the preview's lifetime. App layout, focus, and lock interactions still require interactive checks; see [`UserInterfaceDesign.md`](UserInterfaceDesign.md) and [`TestingStrategy.md`](TestingStrategy.md).

### Working with SwiftData

1. Put new files in the appropriate `AssetFlow/` directory and check Xcode target membership. Review `Info.plist`, entitlements, resources, and scheme settings when the feature needs them.
1. For a model change, inspect `CurrentSchema`, `SchemaV2`, and `AssetFlowMigrationPlan` in [`SchemaVersioning.swift`](../AssetFlow/Models/SchemaVersioning.swift). `CurrentSchema` currently selects V2, so a model added to that active schema must appear in `SchemaV2.models`. Keep historical V1 definitions frozen. Assess whether a change to a released schema needs a new version and migration rather than assuming every future change belongs in V2.
1. Add or update isolated persistence and migration tests where the change needs them. Migration/reopen checks use disposable disk fixtures; normal model tests can use in-memory containers.
1. Update [`AssetFlow/Models/README.md`](../AssetFlow/Models/README.md) and [`DataModel.md`](DataModel.md) for model changes, plus affected design documents. [DataModel's migration section](DataModel.md#schema-migration-and-preservation) owns the persistence rules and preservation boundary.

Views can use `@Query` for view-owned collections, as [`SnapshotListView.swift`](../AssetFlow/Views/SnapshotListView.swift) does. ViewModels use their `ModelContext` on the main actor for data access; follow existing fetch and error-handling paths rather than treating a failed fetch as an empty result. [`Architecture.md`](Architecture.md) explains refresh and context ownership. Keep the `ModelContainer` alive for the lifetime of a preview or test fixture.

AssetFlow targets macOS only. Follow [`CodeStyle.md`](CodeStyle.md) for state, identity, Decimal, and lock-aware tooltip/hover conventions; [`UserInterfaceDesign.md`](UserInterfaceDesign.md) owns window, sidebar, keyboard, and presentation behavior.

When changing Category navigation or forms, verify that unsaved drafts remain guarded, Return saves only from an editable field, and information popovers dismiss on lock. [`UserInterfaceDesign.md`](UserInterfaceDesign.md#categories-screen) describes those interactions; the relevant source is [CategoryEditingSession](../AssetFlow/ViewModels/CategoryDetailViewModel.swift) and [GoalHelpButton](../AssetFlow/Views/Components/CategoryGoalEditor.swift).

### Localization

App strings use `.xcstrings` catalogs: English is the development language and Traditional Chinese uses `zh-Hant`. SwiftUI text is extracted into `Localizable.xcstrings`; ViewModels and services use `String(localized:table:)` with their feature table. Display names for enums use `localizedName`, not persisted `rawValue`. See [`AssetFlow/AGENTS.md`](../AssetFlow/AGENTS.md) for current patterns.

When adding app text, build with Xcode to update extraction, check the relevant catalog, and supply the Traditional Chinese translation. For a new app language, update the Xcode project's `knownRegions` and the catalogs. The user guide has its own [`mkdocs/en/`](../mkdocs/en/) and [`mkdocs/zh-TW/`](../mkdocs/zh-TW/) trees; app `zh-Hant` and site `zh-TW` are different locale identifiers.

For a human translation handoff, these optional commands run from the repository root with Xcode selected. Export writes files under `Localizations/`; import changes the app's localization resources, so inspect the resulting catalog diff. See Apple's [export](https://developer.apple.com/documentation/xcode/exporting-localizations) and [import](https://developer.apple.com/documentation/xcode/importing-localizations) instructions for the catalog workflow:

```bash
xcodebuild -exportLocalizations -project AssetFlow.xcodeproj -localizationPath ./Localizations
xcodebuild -importLocalizations -project AssetFlow.xcodeproj -localizationPath ./Localizations/zh-Hant.xcloc
```

### Debugging and review

Use Xcode breakpoints, View Debugging, and the Memory Graph for app diagnosis. Log an operation or stable error category, never portfolio values, asset names, imported filenames, backup contents, or raw error descriptions that may repeat user input. [`CodeStyle.md`](CodeStyle.md#localization-errors-and-logging) and [`SecurityAndPrivacy.md`](SecurityAndPrivacy.md#network-and-privacy) own the logging rule.

For SwiftData diagnosis, first inspect container creation, schema registration, and the relevant ViewModel fetch or refresh path. A database-open error must not be "fixed" by deleting the user's store. The optional `-com.apple.CoreData.SQLDebug 1` launch argument can expose financial data in diagnostic output; use only disposable synthetic data and handle the logs accordingly. Xcode's **Clean Build Folder** is an optional response to build-product problems. Removing DerivedData discards build caches and should be a deliberate troubleshooting step, not a routine verification action.

Before submitting app changes, check relevant behavior on macOS, review build warnings, run applicable tests, and ensure documentation follows the ownership in [`README.md`](README.md). Use [`CodeStyle.md`](CodeStyle.md) for implementation conventions and [`TestingStrategy.md`](TestingStrategy.md) for risk-based verification. Do not infer UI accessibility or lock behavior solely from a passing unit suite.

## Python and Repository Tooling

### Python runtime and dependencies

`pyproject.toml` requires Python 3.11 or later; `.python-version` pins 3.12 for this repository's local uv environment and Python-running CI jobs. Use the pin for supported contributor commands. The `dev` group supplies pre-commit and pytest. The `docs` group supplies MkDocs, mike, and site plugins. uv includes `dev` by default, but `docs` must be selected explicitly; see [uv's dependency-group rules](https://docs.astral.sh/uv/concepts/projects/dependencies/).

When changing Python dependencies, use `uv add --group dev` or `uv add --group docs` with the package name; this updates dependency declarations and `uv.lock`. Do not edit dependency declarations directly in `pyproject.toml`. Read the resulting lockfile diff and use the matching group for later commands.

### Python Script Tests

From the repository root on macOS, run Python script tests in the project-local `.venv`:

```bash
uv run pytest
```

Pytest discovers `scripts/tests/` from `pyproject.toml`. The release-version suite uses `/usr/bin/plutil`, so those cases require macOS. For a focused run, pass `scripts/tests/test_release_version.py` to `uv run pytest`. CI uses the locked `dev` group and runs pytest in a separate macOS job from the Swift suite. See [`TestingStrategy.md`](TestingStrategy.md#python-script-tests) for fixture and coverage details.

### Formatting and hooks

The installed pre-commit hook runs file checks when a contributor commits. The separate `commit-msg` hook runs the configured commitlint check when installed as shown in Shared Setup. The project-local `.venv` runs pre-commit, while most hooks manage their own isolated environments. The Swift hooks use system `swift-format` and SwiftLint.

The actual hook scopes are defined by [`.pre-commit-config.yaml`](../.pre-commit-config.yaml):

| Checks                                                            | Configured scope                                                           |
| ----------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `swift-format`, strict swift-format lint, SwiftLint               | Swift files                                                                |
| mdformat                                                          | Maintained project Markdown and MkDocs content use separate configurations |
| isort, Black, Pyright                                             | Python source                                                              |
| codespell                                                         | `mkdocs/` only                                                             |
| checkmake                                                         | Makefiles                                                                  |
| uv-lock                                                           | Python dependency lock consistency                                         |
| JSON/YAML, whitespace, line endings, case and merge-marker checks | Applicable repository files                                                |
| commitlint                                                        | Commit-message stage, when that hook is installed                          |

For an intentional repository-wide diagnostic, a human contributor can run `uv run pre-commit run --all-files` from the repository root. Some hooks modify files; review their diff before committing. Formatter and linter commands are not routine post-edit steps for coding agents. CI installs the locked `dev` group and runs pre-commit checks. uv downloads are cached by `uv.lock`; pre-commit environments use a separate cache keyed by the runner OS, `.python-version`, `.pre-commit-config.yaml`, and `uv.lock`.

## Documentation Site

The user guide uses Material for MkDocs. Source is in `mkdocs/`, configuration is in `mkdocs.yml`, and `overrides/` contains theme changes. Git LFS stores screenshots. [`mkdocs/README.md`](../mkdocs/README.md) covers site layout, screenshots, translation, and versioning in detail.

From the repository root, select the `docs` group for a live preview or a static build. `uv run` installs it alongside the default `dev` group as needed; `mkdocs build` also writes `site/`. If MkDocs cannot be found, confirm the `docs` group was selected:

```bash
uv run --group docs mkdocs serve
uv run --group docs mkdocs build
```

`mkdocs serve` provides a local preview at `http://127.0.0.1:8000`; stop it when finished. CI deploys the `dev` version after relevant changes on `main` and a versioned site on release. Publishing with mike changes remote Git state; the manual publishing procedure in [`mkdocs/README.md`](../mkdocs/README.md#manual-deployment) is for an authorized maintainer action. Keep English and Traditional Chinese page structure aligned when editing the user guide.

## Contributor Workflow

### Commits and pull requests

Use Conventional Commits with an optional scope: `type(scope): subject`. Allowed types are `feat`, `fix`, `refactor`, `ci`, `build`, `chore`, `docs`, `style`, `test`, `perf`, and `revert`. Mark a breaking change with `!` or a `BREAKING CHANGE:` footer. Every commit has a body, with every body line at most 72 characters. For example:

```text
docs(development): clarify contributor setup

Explain the app and repository tooling paths for new contributors.
```

Human contributors may create branches, pull changes, commit, and publish after reviewing their effect. For coding agents, the initial request to commit authorizes preparation only. The [commit skill](../.codex/skills/commit/SKILL.md) inspects already staged changes, shows the complete proposed message, and waits for explicit approval of that exact message before committing. Agent staging, branch changes, pulls, and pushes each require their own explicit authorization under [`AGENTS.md`](../AGENTS.md). The [pull-request skill](../.codex/skills/pull-request/SKILL.md) writes `PR_DESCRIPTION.md` from the current branch diff against the chosen target branch; it does not create a hosted pull request.

## Maintainer Release Procedures

### App Version Metadata

[`version.txt`](../version.txt) is the marketing-version source of truth. The macOS [release-version CLI](../scripts/release_version.py) checks all app-target Debug, Release, and Testing `MARKETING_VERSION` settings, can synchronize them, and checks a finished archive's `CFBundleShortVersionString`. These commands run from the repository root with the pinned Python environment. The CLI's `check` and `archive` operations read project or archive files, while `sync` edits [`AssetFlow.xcodeproj/project.pbxproj`](../AssetFlow.xcodeproj/project.pbxproj); uv may also sync the local `.venv`:

```bash
# Check the current project version.
uv run --locked python scripts/release_version.py check

# Run only for an intentional version change; edits the Xcode project.
uv run --locked python scripts/release_version.py sync

# Check a completed archive at this path.
uv run --locked python scripts/release_version.py archive build/AssetFlow.xcarchive
```

Run `sync` only for an intentional version change, then inspect the project diff and rerun `check`. The archive command requires a completed archive at the supplied path. A failure reports a version or file problem; it does not justify changing unrelated project settings. The [pytest suite](../scripts/tests/test_release_version.py) exercises this CLI on disposable project and archive fixtures, while CI also checks the real project and archive.

Xcode supplies numeric `CFBundleVersion` from `CURRENT_PROJECT_VERSION`. Local builds use the project setting; CI archives override it with `GITHUB_RUN_NUMBER`. A build phase writes the first eight characters of the Git revision to custom `AppCommit` when available, or `unknown` otherwise; it appends `-dirty` when Git reports uncommitted changes. [`APIDesign.md`](APIDesign.md#app-version-and-build-metadata) describes how runtime metadata is consumed; the Xcode project and release script define its production.

### Archives, CI, and release publication

From the repository root, `make build` creates an unsigned Release archive at `build/AssetFlow.xcarchive` and copies its app to `build/AssetFlow.app`. It is suitable for local inspection; `make clean` removes the `build/` directory and should be used only when discarding those generated artifacts is intended. The [shared Xcode workflow](../.github/workflows/xcode-build.yml) checks versions, creates an unsigned CI archive, verifies the app version, and packages a ZIP only for a release. Its uploaded artifact is not evidence of Developer ID signing or notarization. Signing and notarization are separate optional distribution steps that must be verified on the resulting artifact; see [`SecurityAndPrivacy.md`](SecurityAndPrivacy.md#storage-protection-deletion-and-distribution).

Release Please uses [its configuration](../.github/release-please/release-please-config.json) and `version.txt`; it maintains [`CHANGELOG.md`](../CHANGELOG.md). A release PR is synchronized to the app project version and formatted. After those jobs finish, approve pending PR workflows if GitHub requests it, then wait for Archive Check, Unit Tests, and Pre-commit Checks before merging. The `bump-minor-pre-major` setting makes a breaking change bump the minor version below 1.0.0. After a release, CI builds the unsigned ZIP, uploads it to the GitHub release, and deploys versioned documentation. Review artifact and version results before publication; example commands in this guide do not authorize deployment.

Before editing GitHub workflows, read [`.github/workflows/AGENTS.md`](../.github/workflows/AGENTS.md). Workflow files own their action-version references; update every use of the same action consistently. [Dependabot configuration](../.github/dependabot.yml) requests weekly GitHub Actions updates but does not enforce consistency after manual edits. CI tooling jobs use locked uv groups and cache downloads by `uv.lock`; each job that runs uv creates its own `.venv`.
