#!/usr/bin/env python3
"""Run unit tests with output capture."""

import argparse
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Optional

DEFAULT_PROJECT = "AssetFlow.xcodeproj"
DEFAULT_SCHEME = "AssetFlow"
DEFAULT_DESTINATION = "platform=macOS"
DEFAULT_RESULTS_DIR = ".codex/skills/test/results"
FALLBACK_RESULTS_DIR_NAME = "assetflow-test-results"
FALLBACK_DERIVED_DATA_NAME = "assetflow-derived-data"
HOST_ACCESS_ACTION = (
    "Action: stop retrying in this sandbox; request host-level execution "
    "and rerun this test command."
)


def positive_int(value: str) -> int:
    """Parse a positive integer argparse option."""
    parsed = int(value)
    if parsed < 1:
        raise argparse.ArgumentTypeError("must be at least 1")
    return parsed


def repository_root() -> Path:
    """Return the repository root containing the project."""
    root = subprocess.check_output(
        ["git", "rev-parse", "--show-toplevel"],
        text=True,
    ).strip()
    return Path(root)


def ensure_writable_directory(directory: Path) -> None:
    """Create a directory and verify that a file can be created in it."""
    directory.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        dir=directory, prefix=".write-probe-", delete=True
    ):
        pass


def output_path(args: argparse.Namespace, root: Path) -> Path:
    """Resolve and create the parent directory for the captured test log."""
    if args.output and Path(args.output).expanduser().is_absolute():
        path = Path(args.output).expanduser()
        ensure_writable_directory(path.parent)
        return path

    results_dir = Path(args.results_dir).expanduser()
    if not results_dir.is_absolute():
        results_dir = root / results_dir

    try:
        ensure_writable_directory(results_dir)
    except OSError:
        default_results_dir = root / DEFAULT_RESULTS_DIR
        if results_dir != default_results_dir:
            raise
        results_dir = Path(tempfile.gettempdir()) / FALLBACK_RESULTS_DIR_NAME
        ensure_writable_directory(results_dir)
        print(
            f"Notice: {default_results_dir} is not writable; "
            f"using {results_dir} for test logs.",
            file=sys.stderr,
        )

    if args.output:
        path = results_dir / Path(args.output).expanduser()
    elif args.suite:
        path = results_dir / f"{args.suite}.txt"
    else:
        path = results_dir / "all-tests.txt"

    ensure_writable_directory(path.parent)
    return path


def display_path(path: Path, root: Path) -> str:
    """Prefer a repository-relative path in console output."""
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def has_restricted_execution_marker(line: str) -> bool:
    """Identify Xcode failures caused by restricted host access."""
    lowered = line.lower()
    return any(
        marker in lowered
        for marker in (
            "coresimulatorservice connection became invalid",
            "thwarted by sandboxing",
            "attempt to post distributed notification",
            "error opening log file",
        )
    )


def writable_default_derived_data_path() -> Optional[Path]:
    """Return a writable DerivedData path for Xcode test runs."""
    default_path = Path.home() / "Library/Developer/Xcode/DerivedData"
    try:
        ensure_writable_directory(default_path)
        return None
    except OSError:
        fallback_path = Path(tempfile.gettempdir()) / FALLBACK_DERIVED_DATA_NAME
        ensure_writable_directory(fallback_path)
        print(
            f"Notice: {default_path} is not writable; "
            f"using {fallback_path} for DerivedData.",
            file=sys.stderr,
        )
        return fallback_path


def main() -> int:
    parser: argparse.ArgumentParser = argparse.ArgumentParser(
        description="Run AssetFlow unit tests"
    )
    parser.add_argument("--project", default=DEFAULT_PROJECT, help="Xcode project path")
    parser.add_argument("--scheme", default=DEFAULT_SCHEME, help="Xcode scheme")
    parser.add_argument(
        "--destination",
        default=DEFAULT_DESTINATION,
        help=f"Xcode destination (default: {DEFAULT_DESTINATION})",
    )
    parser.add_argument(
        "--results-dir",
        default=DEFAULT_RESULTS_DIR,
        help=f"Directory for captured logs (default: {DEFAULT_RESULTS_DIR})",
    )
    parser.add_argument(
        "--derived-data-path",
        help="Custom DerivedData path",
    )
    parser.add_argument(
        "-s", "--suite", help="Test suite name (e.g., DecimalParsingTests)"
    )
    parser.add_argument(
        "-o", "--output", help="Output filename (default: based on suite)"
    )
    parser.add_argument(
        "--no-parallel", action="store_true", help="Disable parallel testing"
    )
    parser.add_argument(
        "--timeout",
        type=positive_int,
        help="Max seconds per test (prevents crash loops)",
    )
    args: argparse.Namespace = parser.parse_args()

    try:
        root = repository_root()
    except (OSError, subprocess.CalledProcessError) as error:
        print(f"Unable to determine repository root: {error}", file=sys.stderr)
        return 2

    try:
        output_file = output_path(args, root)
    except OSError as error:
        print(f"** TEST FAILED **: unable to create test log: {error}")
        return 2

    # Clear previous output if exists (avoids stale data if build fails early)
    try:
        output_file.unlink(missing_ok=True)
    except OSError as error:
        print(f"** TEST FAILED **: unable to clear test log: {error}")
        return 2

    # Build xcodebuild command
    cmd: list[str] = [
        "xcodebuild",
        "-project",
        args.project,
        "-scheme",
        args.scheme,
        "test",
        "-destination",
        args.destination,
    ]
    if args.suite:
        cmd.extend(["-only-testing:AssetFlowTests/" + args.suite])
    if args.no_parallel:
        cmd.extend(["-parallel-testing-enabled", "NO"])
    if args.timeout:
        cmd.extend(["-maximum-test-execution-time-allowance", str(args.timeout)])
    if args.derived_data_path:
        cmd.extend(["-derivedDataPath", args.derived_data_path])
    else:
        derived_data_path = writable_default_derived_data_path()
        if derived_data_path:
            cmd.extend(["-derivedDataPath", str(derived_data_path)])

    # Run tests (output saved to file, minimal console output)
    try:
        process: subprocess.Popen[str] = subprocess.Popen(
            cmd,
            cwd=root,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
    except OSError as error:
        output_file.write_text(
            f"Command: {shlex.join(cmd)}\n\n" f"Unable to start xcodebuild: {error}\n",
            encoding="utf-8",
        )
        print("** TEST FAILED **")
        print(f"Output: {display_path(output_file, root)}")
        print(f"Error: unable to start xcodebuild: {error}")
        return 127

    summary_line: str = ""
    xcresult_path: str = ""
    restricted_execution_failure = False
    with output_file.open("w", encoding="utf-8") as output:
        if process.stdout:
            line: str
            for line in process.stdout:
                output.write(line)
                stripped: str = line.strip()
                restricted_execution_failure = (
                    restricted_execution_failure
                    or has_restricted_execution_marker(stripped)
                )
                # Capture summary line
                if (
                    "** TEST SUCCEEDED **" in stripped
                    or "** TEST FAILED **" in stripped
                ):
                    summary_line = stripped
                # Capture .xcresult path
                if stripped.endswith(".xcresult"):
                    xcresult_path = stripped

    process.wait()

    # Print summary and paths
    if summary_line:
        print(summary_line)
    elif process.returncode:
        print("** TEST FAILED **")
        print(f"Exit code: {process.returncode}")
    else:
        print("Tests completed (no summary found).")
    print(f"Output: {display_path(output_file, root)}")
    if xcresult_path:
        print(f"xcresult: {xcresult_path}")
    if process.returncode and restricted_execution_failure:
        print(HOST_ACCESS_ACTION)

    return process.returncode or 0


if __name__ == "__main__":
    sys.exit(main())
