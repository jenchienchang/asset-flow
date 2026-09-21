---
name: test
description: Use when running unit tests, verifying test results, or during TDD red-green-refactor cycles
---

# Run Unit Tests

Run Swift Testing unit tests and capture output for analysis.

## Required execution rule

1. Before invoking the runner, request host-level execution through `exec_command` with `sandbox_permissions: "require_escalated"` and a justification that Xcode services need host access.
1. After approval, run the test script once.
1. If approval is denied or unavailable, stop and report the blocker; do not run a sandboxed substitute.
1. If a run nevertheless contains `CoreSimulatorService`, `Operation not permitted`, `AppIcon.icon` could not be opened, `sandbox`, or exit `-5`, stop immediately and request host-level execution. Do not modify the icon or test code.

The temporary log and DerivedData notices printed by the runner are expected; they are not failure markers.

## Usage

- `/test` - Run all tests
- `/test -s SuiteName` - Run specific test suite
- `/test -o custom.txt` - Run all tests with custom output filename
- `/test -s SuiteName -o custom.txt` - Run specific suite with custom output
- `/test -s SuiteName --no-parallel` - Run without parallel testing (isolate crashes)
- `/test -s SuiteName --timeout 10` - Set max seconds per test (prevent crash loops)
- `/test --results-dir PATH` - Store captured logs in a specific directory
- `/test --derived-data-path PATH` - Use a specific Xcode DerivedData directory

## Workflow

1. Run the test script (clears previous output if exists, runs xcodebuild)
1. Script prints: summary line, output file path, and `.xcresult` path
1. Use the commands below to analyze results
1. On failure, read the output file for full details

## Commands

```bash
# All tests -> results/all-tests.txt
.codex/skills/test/run-tests.py

# Specific suite -> results/SuiteName.txt
.codex/skills/test/run-tests.py -s SuiteName

# Custom output filename -> results/custom.txt
.codex/skills/test/run-tests.py -o custom.txt

# Debugging: isolate crashes
.codex/skills/test/run-tests.py -s SuiteName --no-parallel --timeout 10

# Explicitly place logs in a writable temporary directory when the Codex
# workspace exposes .codex as read-only
.codex/skills/test/run-tests.py --results-dir /private/tmp/assetflow-test-results
```

## Checking Results

```bash
# Replace OUTPUT_PATH with the path printed by the runner.
rg -n "^\*\* TEST|Test session results" OUTPUT_PATH

# Failure details
rg -n "failed|error:|FAILED" OUTPUT_PATH
```

## Output File

The script prints the output path after each run. Use the Read tool to examine full details. Do not re-run tests just to check different aspects of the output.

## Debugging Crashes

- Use `--no-parallel` and `--timeout N` flags to isolate crashes and prevent retry loops
- When one test crashes (SIGTRAP), the entire process dies and all tests report "failed" at 0.000s — only one test is at fault
- The script prints the `.xcresult` path — use it with: `xcrun xcresulttool get test-results summary --path <.xcresult>`
- The default log directory is `.codex/skills/test/results`. If that directory is not writable, the runner automatically uses the system temporary directory and prints the actual output path. An explicitly supplied `--results-dir` is never replaced.
- Use `--results-dir` when a run must leave logs in a known writable location.
- If Xcode's default `~/Library/Developer/Xcode/DerivedData` is unavailable, the runner automatically uses a writable system-temporary DerivedData path and prints it. Pass `--derived-data-path` to choose a location explicitly.
- For non-sandbox failures, bare `xcodebuild` commands are still acceptable for full control over flags:
  ```bash
  xcodebuild -project AssetFlow.xcodeproj -scheme AssetFlow test -destination 'platform=macOS'
  ```

## Diagnostic reference

`xcodebuild test` launches `actool` and `ibtoold` and posts test progress through Xcode services. The `AppIcon.icon` message and exit `-5` can be downstream symptoms of blocked host access rather than an invalid icon or a failing test.
