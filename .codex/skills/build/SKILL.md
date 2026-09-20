---
name: build
description: Use when building the AssetFlow Xcode application or verifying compilation; captures complete logs and reports concise build results.
---

# Build the Application

Run the repository's Xcode build with compact console output and a complete log saved for diagnostics. This skill is for compilation and packaging verification; use the `test` skill for test execution.

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
- Runner options must appear before `--`; arguments after `--` are passed directly to `xcodebuild` before the `build` action.

## Output and troubleshooting

The runner always prints the build result, elapsed time, warning count when available, and the complete log path. On failure it also prints a bounded set of error and failed-command lines. The full log should be inspected when the summary is insufficient:

```bash
rg -n -i 'error:|fatal error:|warning:|failed|BUILD FAILED' \
  .codex/skills/build/results/BUILD_LOG.txt
```

The process exit status is preserved, so a failed build remains failed when called from another script or CI job.
