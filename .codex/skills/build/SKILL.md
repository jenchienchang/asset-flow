---
name: build
description: Use when building the AssetFlow Xcode application or verifying compilation; captures complete logs and reports concise build results.
---

# Build the Application

Run the repository's Xcode build with compact console output and a complete log saved for diagnostics. This skill is for compilation and packaging verification; use the `test` skill for test execution.

## Required execution rule

1. Before invoking the runner, request host-level execution through `exec_command` with `sandbox_permissions: "require_escalated"` and a justification that Xcode services need host access.
1. After approval, run the build script once.
1. If approval is denied or unavailable, stop and report the blocker; do not run a sandboxed substitute.
1. If a run nevertheless contains `CoreSimulatorService`, `Operation not permitted`, `AppIcon.icon` could not be opened, or `sandbox`, stop immediately and request host-level execution. Do not modify the icon or build settings.

The temporary log and DerivedData notices printed by the runner are expected; they are not failure markers.

## Usage

```bash
# Default Debug build
.codex/skills/build/run-build.py

# Common build settings
.codex/skills/build/run-build.py \
  --configuration Release \
  --destination 'platform=macOS'

# Forward uncommon xcodebuild flags after `--`
.codex/skills/build/run-build.py -- -jobs 4 CODE_SIGNING_ALLOWED=NO

# Stream the full log as well as saving it
.codex/skills/build/run-build.py --verbose

# Explicitly place logs in a writable temporary directory when the Codex
# workspace exposes .codex as read-only
.codex/skills/build/run-build.py --results-dir /private/tmp/assetflow-build-results
```

## Options

- `--project PATH` — Xcode project path, default `AssetFlow.xcodeproj`.
- `--scheme NAME` — scheme name, default `AssetFlow`.
- `--configuration NAME` — build configuration, such as `Debug` or `Release`.
- `--destination VALUE` — destination passed to `xcodebuild`.
- `--derived-data-path PATH` — custom derived-data location.
- `--xcconfig PATH` — custom build-settings file.
- `--result-bundle-path PATH` — optional Xcode result bundle location.
- `--results-dir PATH` — directory for captured logs.
- `--output NAME` — log filename under the results directory, or an absolute path.
- `--verbose` — stream the complete build output to the console.
- `--show-warnings` — include filtered warning lines in the summary.
- `--max-diagnostics N` — maximum filtered diagnostic lines to print, default `40`.
- `--dry-run` — print the assembled command without running it.
- If the default `.codex/skills/build/results` directory is unavailable, the runner automatically uses the system temporary directory and prints the actual log path. An explicitly supplied `--results-dir` is never replaced.
- If Xcode's default `~/Library/Developer/Xcode/DerivedData` is unavailable, the runner automatically uses a writable system-temporary DerivedData path and prints it. Pass `--derived-data-path` to choose a location explicitly.
- Runner options must appear before `--`; arguments after `--` are passed directly to `xcodebuild` before the `build` action.

## Output and troubleshooting

The runner always prints the build result, elapsed time, warning count when available, and the complete log path. On failure it also prints a bounded set of error and failed-command lines. The full log should be inspected when the summary is insufficient:

```bash
# Replace LOG_PATH with the path printed by the runner.
rg -n -i 'error:|fatal error:|warning:|failed|BUILD FAILED' LOG_PATH
```

The process exit status is preserved, so a failed build remains failed when called from another script or CI job.

## Diagnostic reference

`xcodebuild` launches `actool` and `ibtoold`, which communicate with CoreSimulator and Xcode services. The `AppIcon.icon` message can be a downstream symptom of blocked host access rather than an invalid icon.
