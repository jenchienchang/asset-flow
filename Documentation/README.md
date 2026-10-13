# AssetFlow Documentation

This folder contains design documents and guides for developing and maintaining AssetFlow, a macOS desktop application for snapshot-based portfolio management and asset allocation tracking built with SwiftUI, SwiftData, and Swift Charts.

This README defines what each document should provide, based on the needs of this project. It is a guide to intended scope, not an audit of the documents’ current contents. Keep detailed definitions in the document that owns them and cross-link related topics to avoid duplication.

## Documentation Index

### [SPEC.md](SPEC.md)

**Product and technical specification**

The authoritative requirements document defining what AssetFlow must do:

- Product purpose, intended users, terminology, supported platform, and non-goals
- Core concept: snapshot-based portfolio model
- Feature requirements and user outcomes for portfolio tracking, import, allocation, rebalancing, and data management
- Required behavior for success, invalid input, empty data, and unavailable exchange rates
- Product constraints for offline use, localization, accessibility, privacy, and data preservation
- Verifiable acceptance criteria, with stable references for design documents and tests
- Clear distinction between accepted requirements, proposals, and future work

Keep detailed schemas, formulas, interface contracts, and screen designs in their respective documents and link to them here.

**Who should read**: Everyone — this is the source of truth for intended product behavior

______________________________________________________________________

### [Architecture.md](Architecture.md)

**System design and architectural patterns**

Should explain how the shipped application is organized and why:

- System context: the app, local storage, user-selected files, operating-system services, and exchange-rate provider
- MVVM architecture and layer responsibilities (View, ViewModel, Model, Service, Utility)
- Data flow, state ownership, observation, refresh, and cache invalidation
- SwiftData integration and shared container lifecycle
- Dependency injection, service lifetimes, actor isolation, and concurrency
- Architectural handling of startup, import, restore, authentication, and failures
- Significant decisions, alternatives, tradeoffs, and rationale, supported by diagrams where useful

Keep schema details in DataModel, interface contracts in APIDesign, and setup procedures in DevelopmentGuide. Repository tooling, including Python scripts and documentation tooling, belongs in DevelopmentGuide unless it affects application architecture.

**Who should read**: All developers working on AssetFlow

______________________________________________________________________

### [DataModel.md](DataModel.md)

**Complete data model reference**

Should define stored data and how its integrity is preserved:

- Core entities: Category, Asset, Snapshot, SnapshotAssetValue, CashFlowOperation, ExchangeRate
- Property definitions, types, units, defaults, and optionality
- Relationships, cardinality, ownership, inverse relationships, and delete rules
- Identity, uniqueness constraints, and integrity invariants
- SwiftData configuration and boundaries between model storage, settings, and caches
- Financial data precision with Decimal and representation of currencies, dates, and percentages
- Stored versus derived values and snapshot membership
- Schema versioning, migration strategy, compatibility, and data preservation

Use an entity relationship diagram. Keep calculation rules in BusinessLogic and serialized file formats in APIDesign. The model README provides nearby source-level orientation and should link here for the full design.

**Who should read**: Developers working with data models or business logic

______________________________________________________________________

### [DevelopmentGuide.md](DevelopmentGuide.md)

**Getting started and development workflow**

Should provide reproducible contributor procedures, with separate sections for application development and repository tooling. Keep shared prerequisites and contributor workflows together:

- Project setup, supported development environment, and prerequisites
- Build, run, and test entry points, including the repository’s Swift test skill and Python tests
- Project-local uv environment, dependency management, and automatic formatting and linting hooks
- Working with SwiftData, previews, demo data, and debugging tools
- Adding files, Xcode target membership, and macOS-specific development
- Localization and documentation-site workflows
- CI checks, versioning, packaging, and release procedures
- Debugging tips, troubleshooting, and code review checklist

Commands should state their working directory and prerequisites and match repository tooling. Link to CodeStyle for conventions, TestingStrategy for test design, and repository instructions for Git approval requirements.

**Who should read**: New contributors, developers setting up their environment

______________________________________________________________________

### [CodeStyle.md](CodeStyle.md)

**Coding standards and conventions**

Should define consistent implementation practices:

- Naming, file organization, access control, and documentation conventions
- Formatter and linter configuration, with emphasis on rules tools cannot enforce
- SwiftUI state, identity, and ViewModel patterns
- SwiftData, dependency injection, and concurrency conventions consistent with Architecture
- Financial data handling with Decimal and explicit units
- Localization patterns and macOS-specific code patterns
- Logging guidelines that protect sensitive financial data
- Required lock-aware tooltip and hover modifiers
- Test naming and organization conventions

Use concise examples and rationale. Keep setup commands in DevelopmentGuide, architectural reasoning in Architecture, and test design in TestingStrategy.

**Who should read**: All developers to maintain code consistency

______________________________________________________________________

### [TestingStrategy.md](TestingStrategy.md)

**Comprehensive testing approach**

Should explain how to establish correctness in proportion to risk, with separate sections for Swift application tests and Python repository-tooling tests. Describe each area's risks, fixtures, and execution environment:

- Testing philosophy and responsibilities of unit, integration, UI, and manual checks
- Unit testing with Swift Testing and integration testing with isolated SwiftData containers
- Deterministic fixtures, mocking, dependency injection, and network test doubles
- Financial test cases using worked examples, precision expectations, edge cases, and invariants
- Migration, import, backup compatibility, restore failure, and data preservation tests
- Observation refresh and authentication tests, plus accessibility, localization, and chart interaction checks
- Python tooling tests, CI gates, failure diagnosis, and meaningful coverage expectations
- Test examples for new models and ViewModels, and red-green-refactor guidance when using TDD

Link application tests to SPEC acceptance criteria and BusinessLogic examples, and tooling tests to the scripts' expected behavior. Keep executable test commands and setup in DevelopmentGuide and, for Swift tests, the test skill; the TDD red phase should fail assertions rather than compilation.

**Who should read**: Developers writing tests, QA engineers, CI/CD maintainers

______________________________________________________________________

### [UserInterfaceDesign.md](UserInterfaceDesign.md)

**User interface and interaction design**

Should specify how users interact with the app and understand its state:

- Sidebar navigation, screen responsibilities, and window and sheet behavior
- Screen layouts, user flows, and list-detail split patterns
- Selection, editing, validation feedback, confirmation, and cancellation
- Visual style (colors, typography, icons) and reusable macOS interaction patterns
- Chart and table specifications: sorting, filtering, time ranges, axes, legends, and tooltips
- Empty, loading, partial-data, error, locked, and completed states, including unsaved drafts
- Settings and data management, including destructive-action handling
- Accessibility, keyboard and focus behavior, and English/Traditional Chinese localization considerations

Use sketches or screenshots where helpful. Link to BusinessLogic for calculations and SecurityAndPrivacy for data protection requirements.

**Who should read**: Developers building UI, designers, anyone working on user experience

______________________________________________________________________

### [BusinessLogic.md](BusinessLogic.md)

**Business rules and calculation logic**

Should define precise domain rules independently of Swift implementation:

- Snapshot-based portfolio model and handling of missing or explicitly copied values
- Portfolio value calculation and currency conversion policy
- Category allocation, target goals, and rebalancing rules and constraints
- Growth rate, Modified Dietz, cumulative TWR, and CAGR formulas, assumptions, and limitations
- Input/output units, cash-flow signs, period boundaries, dates, precision, and rounding
- CSV import validation, duplicate detection, and conflict resolution
- Asset identity and matching rules
- Edge cases, undefined results, and error handling
- Small worked examples with expected results for review and testing

Keep signatures and file formats in APIDesign and display formatting in UserInterfaceDesign. Domain rules should be understandable without reading source code.

**Who should read**: Developers implementing business logic, QA engineers verifying calculations

______________________________________________________________________

### [SecurityAndPrivacy.md](SecurityAndPrivacy.md)

**Security and privacy considerations**

Should describe sensitive data, trust boundaries, protections, and their limits:

- Local-first architecture and exchange-rate network access: destinations and data sent or received
- Sensitive data inventory, storage locations, retention, deletion, and logging or telemetry behavior
- Threats from local access, on-screen disclosure, untrusted files, and network responses
- App-lock authentication and lifecycle, including tooltip and hover disclosure prevention
- SwiftData, file permissions, and actual encryption properties of storage and ZIP backups
- macOS platform protections, sandbox and entitlement choices, and their limitations
- Safe import/archive handling, validation, resource limits, and restore failure behavior
- Evidence supporting privacy claims, known limitations, and proposed controls

Distinguish app lock from storage encryption and implemented protections from proposals. Include compliance claims only when supported. Link to Architecture and APIDesign for data flows and contracts.

**Who should read**: All developers, security-conscious contributors

______________________________________________________________________

### [APIDesign.md](APIDesign.md)

**Internal API and integration design**

Should define contracts between components and across file/network boundaries:

- Internal service APIs, including calculation, CSV parsing, and backup/restore
- ViewModel contracts, inputs, outputs, preconditions, and side effects
- Data access, persistence effects, actor requirements, and cancellation where relevant
- CSV import/export formats: encoding, headers, types, quoting, dates, and decimal representation
- Backup archive layout, manifest, format versions, validation, and compatibility
- Exchange-rate provider integration: request/response shape, date and currency conventions, caching, timeouts, and failure behavior
- Error handling patterns and the meaning of optional or unavailable results
- Minimal usage and file examples, with links to source declarations for exhaustive signatures

For this desktop app, API includes internal Swift interfaces and interchange formats. Keep system structure in Architecture, domain policy in BusinessLogic, and threat analysis in SecurityAndPrivacy.

**Who should read**: Developers working on services, import/export, or data management

______________________________________________________________________

## Quick Start

**New to the project?** Read in this order:

1. [SPEC.md](SPEC.md) - Understand the product requirements
1. [DevelopmentGuide.md](DevelopmentGuide.md) - Set up your environment
1. [Architecture.md](Architecture.md) - Understand the system design
1. [CodeStyle.md](CodeStyle.md) - Learn coding standards
1. [DataModel.md](DataModel.md) - Explore the data structures
1. [TestingStrategy.md](TestingStrategy.md) - Write quality tests

**Designing a feature?**

1. Start with [SPEC.md](SPEC.md) to define the intended behavior and acceptance criteria
1. Review [UserInterfaceDesign.md](UserInterfaceDesign.md) for UI patterns and screen layouts
1. Check [BusinessLogic.md](BusinessLogic.md) for business rules and calculations
1. Consider [SecurityAndPrivacy.md](SecurityAndPrivacy.md) if handling sensitive data
1. Plan [APIDesign.md](APIDesign.md) for internal service interfaces

**Implementing a feature?**

1. Review [Architecture.md](Architecture.md) for layer responsibilities
1. Check [DataModel.md](DataModel.md) if modifying data models
1. Reference [UserInterfaceDesign.md](UserInterfaceDesign.md) for UI implementation
1. Implement logic from [BusinessLogic.md](BusinessLogic.md)
1. Follow [CodeStyle.md](CodeStyle.md) for implementation
1. Reference [TestingStrategy.md](TestingStrategy.md) for test coverage

**Fixing a bug?**

1. Confirm expected behavior in [SPEC.md](SPEC.md) and the relevant design document
1. Add a regression test where appropriate ([TestingStrategy.md](TestingStrategy.md))
1. Follow debugging tips in [DevelopmentGuide.md](DevelopmentGuide.md)
1. Ensure code style compliance ([CodeStyle.md](CodeStyle.md))
1. Verify fix doesn't break architecture ([Architecture.md](Architecture.md))

______________________________________________________________________

## Additional Resources

### Project Files

- [`README.md`](../README.md) - Project overview
- [`AGENTS.md`](../AGENTS.md) and [`CLAUDE.md`](../CLAUDE.md) - Coding agent instructions
- [`AssetFlow/Models/README.md`](../AssetFlow/Models/README.md) - Source-level model orientation
- [`mkdocs/README.md`](../mkdocs/README.md) - Documentation-site workflow; `mkdocs/` contains user-facing guides
- [`CHANGELOG.md`](../CHANGELOG.md) - Release history maintained by Release Please; do not edit manually

### Configuration Files

- [`.swiftlint.yml`](../.swiftlint.yml) - Linting rules
- [`.swift-format`](../.swift-format) - Formatting configuration
- [`.editorconfig`](../.editorconfig) - Editor settings
- [`.pre-commit-config.yaml`](../.pre-commit-config.yaml) - Git hooks

### External Links

- [Swift Documentation](https://swift.org/documentation/)
- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui/)
- [SwiftData Documentation](https://developer.apple.com/documentation/swiftdata/)
- [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)

______________________________________________________________________

## Keeping Documentation Updated

SPEC is the source of truth for intended product behavior. Design documents explain how that behavior is realized within their scopes; code and tests provide implementation evidence. Resolve discrepancies explicitly rather than silently treating implementation as a new requirement.

**When to update documentation:**

| Change                      | Update                                                                                                 |
| --------------------------- | ------------------------------------------------------------------------------------------------------ |
| Add/modify model            | [DataModel.md](DataModel.md), `AssetFlow/Models/README.md`                                             |
| Change architecture/service | [Architecture.md](Architecture.md), [APIDesign.md](APIDesign.md)                                       |
| Add new tool/workflow       | [DevelopmentGuide.md](DevelopmentGuide.md)                                                             |
| Create coding convention    | [CodeStyle.md](CodeStyle.md)                                                                           |
| Modify testing approach     | [TestingStrategy.md](TestingStrategy.md)                                                               |
| New build command           | [DevelopmentGuide.md](DevelopmentGuide.md), [`CLAUDE.md`](../CLAUDE.md), applicable agent instructions |
| Design new screen/UI        | [UserInterfaceDesign.md](UserInterfaceDesign.md)                                                       |
| Add business rule/calc      | [BusinessLogic.md](BusinessLogic.md)                                                                   |
| Security/privacy change     | [SecurityAndPrivacy.md](SecurityAndPrivacy.md)                                                         |
| API/service integration     | [APIDesign.md](APIDesign.md)                                                                           |
| Add/change product behavior | [SPEC.md](SPEC.md) and all affected design documents                                                   |

Review related tests, source comments, model notes, agent instructions, and user guides when their behavior or procedures are affected. Cross-link shared definitions instead of copying them: for example, return formulas belong in BusinessLogic, interface result units in APIDesign, and presentation in UserInterfaceDesign.

Keep documentation accurate, clear, and proportional to the change. Label proposed work and known limitations explicitly.

______________________________________________________________________

## Contributing to Documentation

Found an error or unclear explanation?

1. Check whether the topic is already documented elsewhere and identify its owning document.
1. Update the relevant document, using durable explanations and concise examples.
1. Ensure consistency across related docs and check links and examples.
1. Update this README when adding a document or changing document responsibilities.
1. Follow the repository’s contribution and commit approval workflow.

Avoid blanket “Current” status labels or audit dates without a documented review scope and supporting evidence. This guide defines expected content; it does not certify completeness or implementation correctness.
