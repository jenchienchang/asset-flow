# GitHub Workflow Guidelines

These instructions apply to `.github/workflows/` and supplement repository-wide instructions.

## Action Versions

- Treat action references in workflow files as the version source of truth.
- Use the same reference for every occurrence of an external action.
- When upgrading an action, update all occurrences together.
- Use Dependabot's `github-actions` ecosystem to propose upgrades. Review compatibility and CI results before merging.
- New uses of an existing action must match its existing reference.
- Local reusable workflows use repository-relative references.
- Update this document when workflow policies change.

## Python and uv

- Read the required Python version from the root `.python-version`.
- Every job running Python must use `actions/setup-python` with `python-version-file: .python-version` before its first Python command.
- Use uv to create the repository-local `.venv`.
- Install locked dependencies with the required group: `uv sync --locked --only-group dev` or `uv sync --locked --only-group docs`.
- Run project tools through `uv run --locked` with the matching group.
- Add dependencies using `uv add --group <group> <package>` and include the resulting `pyproject.toml` and `uv.lock` changes.
- Create `.venv` before running pyright through pre-commit; pyright resolves project dependencies from this environment.

## Caching

### uv Dependencies

- Every job using uv must enable caching in `astral-sh/setup-uv`: `enable-cache: true` and `cache-dependency-glob: uv.lock`.
- Cache uv's downloaded dependencies and recreate `.venv` from the lockfile in each job.

### Pre-commit Hook Environments

- Every job running pre-commit must restore `~/.cache/pre-commit` before its first hook run.
- Use the same cache key across compatible jobs:
  ```
  pre-commit-${{ runner.os }}-${{ hashFiles('.python-version', '.pre-commit-config.yaml', 'uv.lock') }}
  ```
- On cache misses, let pre-commit install its environments and let `actions/cache` save them after a successful job.
- Run hooks on cache hits too.
- Reuse installed environments for subsequent runs within the job.

### Downloaded Tools and Homebrew Bottles

- Cache downloaded or extracted tools, including Homebrew bottles, SwiftLint, and swift-format.
- Resolve tool versions before constructing cache keys.
- Include tool versions in cache keys. Distinguish OS and architecture when binaries differ between runners.
- Restore caches before installation and install on cache misses.
- Preserve download integrity checks, including SHA-256 verification.
- Add cached binaries to PATH before invoking them.

## Workflow Structure

- Express execution order through `needs` and arrange jobs in the same order for readability.
- Release PR processing runs release-please, version synchronization, then formatting and final pre-commit verification.
- Auto-fix may tolerate initial failures; final verification must fail the job when issues remain.
- Keep Python script tests in the Unit Tests workflow.
- Build and archive jobs retain actual project and artifact checks.
- Use the shared Xcode build workflow for archives and Swift tests.
- Grant each job only the permissions it requires.

## Validation and Documentation

- Check action-reference consistency across all workflows.
- Validate YAML, reusable workflow inputs, dependency ordering, Python setup, and cache placement.
- Distinguish local checks from verified GitHub Actions execution.
- Update affected project documentation with workflow changes.
- Leave formatting and linting to repository pre-commit hooks.
