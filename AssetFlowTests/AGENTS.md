# AssetFlow Tests

## Framework

Uses **Swift Testing** (`import Testing`), NOT XCTest. No `XCTAssert*` or `XCTestCase`. See `Documentation/TestingStrategy.md` for coverage goals.

## Test-Driven Development (TDD)

Red-Green-Refactor: write a failing test first, implement minimum code to pass, then refactor. Test pure calculations with input/output; use isolated in-memory containers for model-backed services.

**RED phase must produce assertion failures, not compilation errors.** Compilation errors are trivial and don't validate that the tests actually test anything. Before running tests:

1. Write the test file with all test functions
1. Write minimal code stubs (empty methods returning dummy values like `[]`, `false`, `0`, etc.) so everything compiles
1. Run tests — confirm they fail with **assertion failures**
1. Only then implement the real logic
1. Run tests — confirm GREEN

## Structure

```swift
import Foundation
import SwiftData  // omit for tests that don't use SwiftData types
import Testing

@testable import AssetFlow

@Suite("ComponentName Tests")
@MainActor
struct ComponentNameTests {

  @Test("Description of what is tested")
  func testDescriptiveName() {
    let container = TestDataManager.createInMemoryContainer()
    let context = container.mainContext
    // Arrange → Act → Assert
    #expect(result == expected)
  }
}
```

## Key Rules

1. Tests are `struct`, annotated with `@Suite("Name")` and `@MainActor` — even for pure-logic tests (ensures consistency and avoids issues if SwiftData dependencies are added later)
1. `@Test("Human-readable description")` on each test method
1. `#expect(...)` for assertions, `#require(...)` for preconditions
1. Each test creates its own in-memory container — no shared state
1. Use private helpers inside the test struct for reusable setup

## SwiftData Lifetime (Critical)

`ModelContainer` must be retained for the entire test scope. ARC can deallocate it early even if `ModelContext` holds a back-reference, destroying the backing store. Accessing `@Relationship` properties then crashes with SIGTRAP: "This model instance was destroyed by calling ModelContext.reset". All tests in the suite report "failed" at 0.000s.

**`_` does NOT retain** — `let (_, context) = helper()` discards immediately. Use the `TestContext` pattern:

```swift
private struct TestContext {
    let container: ModelContainer
    let context: ModelContext
    let snapshot: Snapshot
}

// Usage — container stays alive through `tc`
let tc = createSnapshotWithContext()
let (context, snapshot) = (tc.context, tc.snapshot)
```

## Running Tests

Use the `/test` skill to run unit tests. See `.codex/skills/test/SKILL.md` for its required host-access and runner instructions.

- `/test` - Run all tests
- `/test -s SuiteName` - Run specific test suite

## Directory Structure

```
AssetFlowTests/
├── Models/          Model and relationship tests
├── ViewModels/      ViewModel tests (including currency-specific)
├── Services/        Service and calculator tests
├── Integration/     Cross-cutting and spec verification tests
├── DateFormattingTests.swift      Date formatting tests (root level)
├── SnapshotTimeBucketTests.swift  Snapshot time-bucket tests (root level)
├── TestDataManager.swift          @MainActor class, shared in-memory container helper
└── AGENTS.md
```

Place new test files in the subdirectory matching the source layer.

## File Naming

`[Component]Tests.swift` — e.g., `AssetFormViewModelTests.swift`
