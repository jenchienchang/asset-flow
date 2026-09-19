# AssetFlow

A macOS desktop application for snapshot-based portfolio management and asset allocation tracking.

## Overview

![AssetFlow Dashboard](mkdocs/assets/images/app-overview.png)

AssetFlow helps you take control of your investments by recording portfolio snapshots over time. Instead of syncing with brokerage accounts, you capture the state of your portfolio whenever you choose — giving you a clear, private picture of how your assets are allocated and how they grow. Everything stays on your Mac, with no cloud accounts required.

## Why AssetFlow?

AssetFlow is for DIY investors who manage portfolios across multiple brokers, currencies, and asset types — and want to see their whole allocation without handing account access to an aggregator.

- **Any asset, any broker.** Track stocks, ETFs, mutual funds, crypto, real estate, cash, or anything else — without waiting for the developer to add support for your platform. No curated compatibility list, no roadmap to wait on.
- **Allocation-first, not transaction-first.** Most trackers obsess over every buy and sell. AssetFlow asks the more useful question: how is your wealth distributed, and what do you need to adjust to hit your targets? Record snapshots when it matters instead of reconciling every trade.
- **Native macOS, not phone-first.** Most portfolio trackers are iOS apps with a thin web companion — but the work itself isn't phone-shaped. Broker websites are built for desktop browsers, CSV exports land in your downloads folder, and reviewing allocation needs real screen real estate. AssetFlow runs natively on macOS, on the same screen as the broker tabs you're already using.
- **CSV import beats account linking.** Most brokerages already let you export CSV — and AssetFlow imports it directly. No handing your broker login to a third-party app, no fragile aggregator in the middle, no waiting on integrations that may never ship.
- **Private by design.** Your portfolio data never leaves your Mac. The only network request fetches public exchange rates from a CDN — no account, no telemetry, no developer servers to trust.
- **Open source and auditable.** AssetFlow's source is on GitHub. You don't have to trust the privacy claim — you (or anyone) can verify it.

## Platform Support

- **macOS 15.0+** — Full-featured desktop application (local-first; network used only for exchange rate fetching)

## Tech Stack

- **Language**: Swift
- **UI Framework**: SwiftUI
- **Data Persistence**: SwiftData
- **Data Visualization**: Swift Charts
- **Minimum Deployment Target**: macOS 15.0+

## Project Structure

```
AssetFlow/
├── Models/          # SwiftData models and entities
├── Views/           # SwiftUI views and UI components
├── ViewModels/      # View models and business logic
├── Services/        # Stateless calculation services
├── Utilities/       # Helper functions and extensions
└── Resources/       # Assets, localization files
```

## Getting Started

### Download & Install

1. Go to the [Releases](https://github.com/jenchienchang/asset-flow/releases) page and download the latest `AssetFlow-x.y.z.zip`.

1. Unzip the file and move `AssetFlow.app` to your `/Applications` folder.

1. **First launch — bypass the Gatekeeper warning:**

   Because the app is not signed with an Apple Developer certificate, macOS will block it on first open. To allow it:

   1. Double-click `AssetFlow.app`. You will see a warning that the app cannot be opened.
   1. Open **System Settings → Privacy & Security**.
   1. Scroll down to the **Security** section. You will see a message: _"AssetFlow was blocked from use because it is not from an identified developer."_
   1. Click **Open Anyway**, then authenticate with Touch ID or your password.
   1. In the confirmation dialog, click **Open**.

   The app will open normally on all subsequent launches.

### Build from Source

#### Prerequisites

- Xcode 27.0 or later (Swift 6.4 compiler)
- macOS Tahoe 26.6 or later (for development; the app supports macOS 15.0+)
- [swift-format](https://github.com/swiftlang/swift-format/tree/main)
- [SwiftLint](https://github.com/realm/SwiftLint/tree/main)

#### Steps

1. Clone the repository:

   ```bash
   git clone git@github.com:jenchienchang/asset-flow.git AssetFlow
   cd AssetFlow
   ```

1. Open the project in Xcode:

   ```bash
   open AssetFlow.xcodeproj
   ```

1. Build and run the project (⌘+R)

   Alternatively, use the Makefile from the command line:

   ```bash
   make          # Archive a Release build → build/AssetFlow.app
   make test     # Run the test suite
   make lint     # Run pre-commit hooks (swift-format + SwiftLint)
   make clean    # Remove the build/ directory
   ```

### Tooling Setup

Install the required code quality tools using Homebrew:

```bash
brew install swift-format
brew install swiftlint
```

Set up the pre-commit hooks via a project-local [uv](https://docs.astral.sh/uv/) virtual environment:

```bash
uv sync
uv run pre-commit install
```

These hooks will automatically format and lint your code before you commit.

## Development

### VSCode Setup

This project ships with `.vscode/settings.json` that configures SourceKit-LSP for the Xcode build system. To enable accurate cross-file symbol resolution, install [xcode-build-server](https://github.com/SolaWing/xcode-build-server) and generate a local build server config:

```bash
brew install xcode-build-server
xcode-build-server config -scheme AssetFlow -project AssetFlow.xcodeproj
```

This creates a machine-local `buildServer.json` (already in `.gitignore`) that tells SourceKit-LSP how to compile each file with the correct flags. Build in Xcode at least once to populate the index store, then restart the language server in VSCode.

### Code Style

This project uses a combination of `swift-format` and `SwiftLint` to ensure high code quality and a consistent style.

- **`swift-format`**: Used for automated code formatting.
- **`SwiftLint`**: Used to enforce stylistic conventions and catch common errors.

Configurations for these tools can be found in `.swift-format` and `.swiftlint.yml` respectively. Both are run automatically before each commit via pre-commit hooks.

### Architecture

The application follows the MVVM (Model-View-ViewModel) architecture pattern:

- **Models**: SwiftData models (Category, Asset, Snapshot, SnapshotAssetValue, CashFlowOperation, ExchangeRate)
- **Views**: SwiftUI components for UI presentation
- **ViewModels**: `@Observable @MainActor` classes for business logic and state management
- **Services**: Stateless calculation utilities (CalculationService, CSVParsingService, RebalancingCalculator, BackupService, SettingsService, AuthenticationService, CurrencyService, ChartDataService, ExchangeRateService, CurrencyConversionService, DateFormatStyle)

## Features

- Snapshot-based portfolio tracking with point-in-time recording
- CSV import for assets and cash flows with validation and duplicate detection
- Category management with target allocation percentages
- Platform-based asset organization and tracking
- Multi-currency support with automatic exchange rate fetching
- Portfolio-level return analysis (growth rate, Modified Dietz, cumulative TWR, CAGR)
- Rebalancing calculator with suggested buy/sell actions
- Data visualization with pie charts, line charts, and cumulative TWR charts
- Backup and restore via ZIP archive
- Settings for display currency, date format, and default platform
- Optional app lock with Touch ID and system password authentication
- Localization support (English and Traditional Chinese)

## Documentation

The user guide and documentation site is built with [Material for MkDocs](https://squidfunk.github.io/mkdocs-material/). Source files live in the [`mkdocs/`](mkdocs/) directory. See [`mkdocs/README.md`](mkdocs/README.md) for setup and development instructions.

## Contributing

This is a personal project. Contributions, issues, and feature requests are welcome.

## License

[GNU General Public License v3.0](LICENSE) — Copyright © 2026 Jen-Chien Chang
