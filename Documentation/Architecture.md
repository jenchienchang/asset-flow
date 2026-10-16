# AssetFlow Architecture

## System Context

AssetFlow is a macOS 15.0+ application for snapshot-based portfolio management. SwiftUI presents the interface, SwiftData stores portfolio records, and Swift Charts visualizes derived data. The app works with local data and makes network requests to `cdn.jsdelivr.net` for the supported currency list and exchange rates.

```text
[User] <--------------------> [AssetFlow macOS app]
                                   |-- read/write --> [SwiftData portfolio store]
                                   |-- read/write --> [UserDefaults settings and currency cache]
                                   |-- read/write --> [User-selected CSV and ZIP files]
                                   |-- authenticate <--> [macOS LocalAuthentication]
                                   +-- HTTPS <------> [cdn.jsdelivr.net currency API]
```

The file boundary is used for imports and backups. Rate requests include currency codes and dates needed to choose provider data; the app does not upload portfolio records or backup contents as part of that flow. [`SecurityAndPrivacy.md`](SecurityAndPrivacy.md) owns the privacy claims and limits, while [`APIDesign.md`](APIDesign.md) owns the file and network contracts.

## Component Boundaries

The app uses Model-View-ViewModel (MVVM), with direct app-shell coordination where SwiftUI owns a lifecycle or navigation task.

```text
[SwiftUI Views / ContentView]
    |-- observe/call --> [@Observable ViewModels]
    |-- @Query -------> [ModelContext and @Model objects]
    +-- shell tasks --> [Stateful app services]

[@Observable ViewModels]
    |-- read/write ---> [ModelContext and @Model objects]
    |-- use ----------> [Stateful app services]
    +-- call ---------> [Calculation, import, backup services]

[Services needing persistence] -- main-actor access --> [ModelContext and @Model objects]
[ModelContext and @Model objects] -- persist -------> [SwiftData store]
```

Views can also read SwiftData through `@Query` and the environment's `ModelContext`. Some services accept a `ModelContext` for a specific main-actor operation; model objects do not call services. The arrows show use and data flow, not a requirement that every feature pass through every box.

- **Views** in [`AssetFlow/Views/`](../AssetFlow/Views/) own presentation, navigation, local form controls, and user actions. `ContentView` owns the sidebar, selected records, app-level query projection, import and Bulk Entry sessions, and rate-fetch tasks. The app root owns the shared container and lock overlay.
- **ViewModels** in [`AssetFlow/ViewModels/`](../AssetFlow/ViewModels/) are observable, main-actor coordinators for screen state, validation, persistence operations, and derived results. They receive a `ModelContext` or focused dependencies as needed. Editors that support drafts keep them separate from saved models until a save action.
- **Models** in [`AssetFlow/Models/`](../AssetFlow/Models/) represent stored entities and relationships. A snapshot contains only directly recorded values; derived portfolio statistics are recomputed. [`DataModel.md`](DataModel.md) owns fields, schema, relationships, and migration details.
- **Services and utilities** in [`AssetFlow/Services/`](../AssetFlow/Services/) and [`AssetFlow/Utilities/`](../AssetFlow/Utilities/) provide calculations, data preparation, persistence helpers, networking, and app-wide state. Their lifetimes and actor boundaries depend on the work they perform.

Pure, value-oriented services such as `CalculationService` and `RebalancingCalculator` are distinct from observable, main-actor `SettingsService`, `AuthenticationService`, and `CurrencyService`. `ExchangeRateService` owns network requests and shares a request coordinator so concurrent callers can reuse a date/base-currency fetch. `SnapshotSummaryService` and `CategoryGoalAssessmentService` read model data on the main actor. Service declarations do not imply statelessness or freedom from actor isolation.

## Persistence and Concurrency

[`AssetFlowApp.swift`](../AssetFlow/AssetFlowApp.swift) creates one `ModelContainer` with `CurrentSchema.schema` and `AssetFlowMigrationPlan`, then injects it into the app scene. A store-opening or migration failure shows an error and exits without deleting the existing store. The active schema is V2; [`DataModel.md`](DataModel.md) owns the versioned model contract.

The app target uses default main-actor isolation. Views, observable ViewModels, and access to the shared SwiftData `ModelContext` stay on the main actor. Work that does not need SwiftData can cross into explicitly nonisolated workers: security-scoped file reads, CSV preparation, backup serialization and validation, and ZIP operations. These workers exchange value records or `Sendable` results with main-actor coordinators. `CSVRecordReader` delegates record parsing to Apple's TabularData framework; `BackupService` invokes the macOS `/usr/bin/ditto` utility through `Process` for ZIP work. Neither task is implemented by Foundation alone.

Ordinary editing paths change or insert models in the shared context and rely on its autosave. Restore has deliberate persistence boundaries: `BackupService` saves any pending context changes as a rollback checkpoint, disables autosave during replacement, and performs the graph replacement in a main-actor transaction. It applies restored settings only after that transaction succeeds. The Debug-only disposable preview-data seed also calls `save()` explicitly.

Dependencies are supplied at the boundary where they matter: ViewModels can receive a `ModelContext` and `ModelFetching` for persistence reads, `ExchangeRateService` accepts a `URLSession`, and `AuthenticationService` accepts an `LAContext` factory for isolated tests. Production uses shared settings, authentication, and currency services where app-wide state is intended. [`APIDesign.md`](APIDesign.md) owns their detailed interfaces.

## State, Observation, and Refresh

Stored portfolio records live in SwiftData; preferences and the cached currency list live in UserDefaults. SwiftUI `@State` owns navigation, selected objects, sheets, and temporary editing sessions. ViewModels own screen-specific load, validation, and derived state. A calculation cache is an optimization, never the stored source of truth.

Aggregate ViewModels use [`ObservedRefresh.swift`](../AssetFlow/Utilities/ObservedRefresh.swift) to track reads of source models and settings while computing into local values, then publish observable results outside that tracking. An explicit load remains synchronous and supersedes queued callbacks from older generations. Coalesced refresh requests handle observation changes without a derived output repeatedly triggering its own reload. The Dashboard keeps internal caches outside source observation and exposes a publication revision so chart and period readers still refresh.

`ContentView` projects queries for the six persisted model types into [`ModelQueryRevision.swift`](../AssetFlow/Utilities/ModelQueryRevision.swift). Aggregate screens use [`StoreRevisionRefresh.swift`](../AssetFlow/Utilities/StoreRevisionRefresh.swift) to request reloads when membership, relevant fields, or the store changes, including records outside the last observed dependency set. Screen-local queries remain useful for standalone views. Import and Bulk Entry use their own query reconciliation because they maintain preview, picker, or draft state.

After a store replacement, the shell resolves selected snapshots, assets, and categories against live queried instances by stable UUID. Detail panes use the selected object's `ObjectIdentifier` as view identity so a replacement instance creates a fresh ViewModel.

`CategoryEditingSession` remains transient UI state. The active category detail registers its editor with the session, which guards navigation away from an unsaved draft and releases the editor when the visible category changes. A background refresh adopts changed saved fields into a clean editor while preserving one with unsaved changes. Bulk Entry and import drafts retain their own discard and staleness handling. [`UserInterfaceDesign.md`](UserInterfaceDesign.md) owns the interaction details.

## Main Data Flows

### Load and Conversion

A screen's ViewModel fetches the required models through the main-actor context, uses calculation services to derive results, and publishes a load state. Snapshots contain directly recorded values; an absent asset value is distinct from a recorded zero. Bounded snapshot helpers avoid repeated full-history fetches when a latest, prior, or date-specific snapshot is enough. Read failures are reported as failures rather than converted into an empty portfolio.

Conversion uses rates applicable to a snapshot's date and the selected display currency. [`CurrencyConversionService.swift`](../AssetFlow/Services/CurrencyConversionService.swift) returns an unavailable converted total when a required rate is missing or unusable and retains native totals separately by currency. An asset-rate failure need not disable a result that depends only on cash-flow rates, and a missing goal rate can disable rebalancing while valid portfolio statistics remain available. [`BusinessLogic.md`](BusinessLogic.md) defines the calculation and availability rules.

### Import and Bulk Entry

A selected file is read by a nonisolated worker. `CSVImportPreparationService` and `CSVRecordReader` prepare parsed rows or a column-mapping request away from the main actor, with cancellation checks. When mapping is needed, the loading task measures the preview's column widths before the ViewModel presents the sheet; row text is measured off the main actor, and the mapping controls are measured on it. The main-actor `ImportViewModel` owns preview state, effective-platform duplicate validation, checks against an existing snapshot, and the eventual model changes. Bulk Entry keeps an editable draft and validates a CSV replacement before replacing draft rows.

For multi-row mutations, [`ModelResolutionLookup.swift`](../AssetFlow/Utilities/ModelResolutionLookup.swift) provides operation-scoped indexes for assets, categories, and snapshot values. They are built for a preview, validation, import, or save operation, updated after insertions, and then discarded. The shared `ModelContext` lookup helpers remain for single-record work. [`BusinessLogic.md`](BusinessLogic.md) owns duplicate and zero-placeholder policy; [`APIDesign.md`](APIDesign.md) owns CSV syntax and column contracts.

### Exchange Rates and Rebalancing

When it appears, `ContentView` requests the currency list and starts a cancellable rate task. A currency-list failure leaves the cached or built-in list in place. The rate task is keyed by snapshot identity and date, display currency, goal currencies, and recorded asset and cash-flow currencies, so relevant changes can request missing rates again. `ExchangeRateService` reuses a valid stored rate when it covers the needed currencies and coalesces concurrent requests for the same provider date and base currency. Failed requests leave dependent converted results unavailable until usable rates exist.

`CategoryGoalAssessmentService` provides a shared assessment for category list/detail and rebalancing, separating asset conversion from goal-currency conversion. The category list reuses an assessment across rows; category detail computes the current plan once and converts only the selected minimum for historical overlays. Missing historical conversions leave gaps rather than fabricated values.

For a feasible plan, `RebalancingTransferPlanner` funds mandatory minimum shortfalls before optional percentage adjustments; `RebalancingViewModel` uses that result for actionable rows and suggested moves. `RebalancingHelpPresentation` turns assessment data into view-facing help without creating another calculation path. Rebalancing does not change stored holdings or create cash flows.

### Backup and Restore

Export captures SwiftData records and settings on the main actor as transfer values, then serializes and archives them outside it. Restore extracts, parses, and validates the archive before changing the live graph. After the save checkpoint, its main-actor transaction replaces records; on failure it rolls back and leaves settings unapplied. Successful replacement triggers the query and selection reconciliation described above. [`APIDesign.md`](APIDesign.md) owns archive format and validation contracts; [`SecurityAndPrivacy.md`](SecurityAndPrivacy.md) owns the protections and limits of ZIP files and extraction.

### App Lock

`AssetFlowApp` observes app activation and screen-lock events and passes them to `AuthenticationService`, which owns lock state and timeouts and requests macOS `LocalAuthentication` with `.deviceOwnerAuthentication`. The app root displays a lock overlay over the main and Settings scenes and publishes lock state through the environment. Failed or cancelled authentication leaves the app locked; lock-aware help and hover modifiers suppress content. The app does not choose a fixed authentication-method sequence. [`SecurityAndPrivacy.md`](SecurityAndPrivacy.md) owns authentication guarantees and storage-protection limits.

## Failure Boundaries and Design Choices

- `DataLoadState` distinguishes idle, loading, loaded, and failed reads; a failed fetch is not an empty data set.
- Import, rate, and restore failures remain with their coordinating ViewModel or service. A missing conversion produces an unavailable result rather than a mixed-currency value.
- Local records remain authoritative. Rates, converted aggregates, chart data, assessments, and transfer suggestions are derived or fetched data with explicit availability rules.
- The shared `ModelContainer` and main-actor context access keep model identity and observation in one application graph. ViewModels and bounded services use SwiftData directly, with `ModelFetching` as a narrow read seam; this avoids a second repository layer while keeping graph access on the main actor. Nonisolated workers handle file and archive preparation, and short-lived lookup indexes limit repeated work without a persistent calculation store.

For required product behavior, see [`SPEC.md`](SPEC.md). For screen design and localization, see [`UserInterfaceDesign.md`](UserInterfaceDesign.md). For contributor setup, configurations, commands, and tests, see [`DevelopmentGuide.md`](DevelopmentGuide.md) and [`TestingStrategy.md`](TestingStrategy.md).
