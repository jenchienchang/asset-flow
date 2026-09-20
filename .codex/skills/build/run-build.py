#!/usr/bin/env python3
"""Run an Xcode build with compact output and complete log capture."""

from __future__ import annotations

import argparse
import re
import shlex
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Iterable


DEFAULT_PROJECT = "AssetFlow.xcodeproj"
DEFAULT_SCHEME = "AssetFlow"
DEFAULT_RESULTS_DIR = ".codex/skills/build/results"
BUILD_SUCCESS = "** BUILD SUCCEEDED **"
BUILD_FAILURE = "** BUILD FAILED **"


def positive_int(value: str) -> int:
    """Parse a positive integer argparse option."""
    parsed = int(value)
    if parsed < 1:
        raise argparse.ArgumentTypeError("must be at least 1")
    return parsed


def parser() -> argparse.ArgumentParser:
    """Create the command-line parser."""
    result = argparse.ArgumentParser(
        description="Build AssetFlow with compact output and full log capture"
    )
    result.add_argument(
        "--project",
        default=DEFAULT_PROJECT,
        help=f"Xcode project path (default: {DEFAULT_PROJECT})",
    )
    result.add_argument(
        "--scheme",
        default=DEFAULT_SCHEME,
        help=f"Xcode scheme (default: {DEFAULT_SCHEME})",
    )
    result.add_argument(
        "--configuration",
        help="Build configuration, such as Debug or Release",
    )
    result.add_argument(
        "--destination",
        help="Xcode destination specification",
    )
    result.add_argument(
        "--derived-data-path",
        help="Custom derived-data path",
    )
    result.add_argument(
        "--xcconfig",
        help="Custom xcconfig file",
    )
    result.add_argument(
        "--result-bundle-path",
        help="Optional path for an Xcode result bundle",
    )
    result.add_argument(
        "--results-dir",
        default=DEFAULT_RESULTS_DIR,
        help=f"Directory for captured logs (default: {DEFAULT_RESULTS_DIR})",
    )
    result.add_argument(
        "-o",
        "--output",
        help="Log filename under results-dir, or an absolute path",
    )
    result.add_argument(
        "--verbose",
        action="store_true",
        help="Stream the complete build output to the console",
    )
    result.add_argument(
        "--show-warnings",
        action="store_true",
        help="Include filtered warning lines in the summary",
    )
    result.add_argument(
        "--max-diagnostics",
        type=positive_int,
        default=40,
        help="Maximum filtered diagnostic lines to print (default: 40)",
    )
    result.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the assembled xcodebuild command without running it",
    )
    result.add_argument(
        "xcodebuild_args",
        nargs=argparse.REMAINDER,
        help="Additional xcodebuild arguments after `--`",
    )
    return result


def repository_root() -> Path:
    """Return the repository root containing the project."""
    root = subprocess.check_output(
        ["git", "rev-parse", "--show-toplevel"],
        text=True,
    ).strip()
    return Path(root)


def build_command(args: argparse.Namespace) -> list[str]:
    """Build the xcodebuild argv without invoking a shell."""
    command = [
        "xcodebuild",
        "-project",
        args.project,
        "-scheme",
        args.scheme,
    ]
    if args.configuration:
        command.extend(["-configuration", args.configuration])
    if args.destination:
        command.extend(["-destination", args.destination])
    if args.derived_data_path:
        command.extend(["-derivedDataPath", args.derived_data_path])
    if args.xcconfig:
        command.extend(["-xcconfig", args.xcconfig])
    if args.result_bundle_path:
        command.extend(["-resultBundlePath", args.result_bundle_path])

    passthrough = list(args.xcodebuild_args)
    if passthrough and passthrough[0] == "--":
        passthrough.pop(0)
    command.extend(passthrough)
    command.append("build")
    return command


def output_path(args: argparse.Namespace, root: Path) -> Path:
    """Resolve and create the parent directory for the captured log."""
    results_dir = Path(args.results_dir).expanduser()
    if not results_dir.is_absolute():
        results_dir = root / results_dir

    if args.output:
        path = Path(args.output).expanduser()
        if not path.is_absolute():
            path = results_dir / path
    else:
        timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        path = results_dir / f"build-{timestamp}.txt"

    path.parent.mkdir(parents=True, exist_ok=True)
    return path


def display_path(path: Path, root: Path) -> str:
    """Prefer a repository-relative path in console output."""
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def diagnostic_lines(
    lines: Iterable[str],
    show_warnings: bool,
    limit: int,
) -> list[str]:
    """Extract useful diagnostics without dumping the entire build log."""
    selected: list[str] = []
    seen: set[str] = set()
    for line in lines:
        stripped = line.strip()
        lowered = stripped.lower()
        is_failure = (
            "error:" in lowered
            or "fatal error:" in lowered
            or "build failed" in lowered
            or "failed" in lowered
        )
        is_warning = "warning:" in lowered
        if not (is_failure or (show_warnings and is_warning)):
            continue
        if stripped and stripped not in seen:
            selected.append(stripped)
            seen.add(stripped)
        if len(selected) >= limit:
            break
    return selected


def recent_lines(lines: list[str], limit: int = 12) -> list[str]:
    """Return a short non-empty tail when no structured diagnostic exists."""
    return [line.strip() for line in lines if line.strip()][-limit:]


def warning_count(lines: Iterable[str]) -> int:
    """Count compiler and build-script warning diagnostics."""
    return sum(1 for line in lines if re.search(r"\bwarning:", line, re.IGNORECASE))


def run_build(args: argparse.Namespace) -> int:
    """Run the build and print a concise result."""
    try:
        root = repository_root()
    except (OSError, subprocess.CalledProcessError) as error:
        print(f"Unable to determine repository root: {error}", file=sys.stderr)
        return 2

    command = build_command(args)
    command_text = shlex.join(command)
    if args.dry_run:
        print(command_text)
        return 0

    log_path = output_path(args, root)
    start = time.monotonic()
    captured: list[str] = []

    try:
        process = subprocess.Popen(
            command,
            cwd=root,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            errors="replace",
            bufsize=1,
        )
    except OSError as error:
        log_path.write_text(
            f"Command: {command_text}\n\nUnable to start xcodebuild: {error}\n",
            encoding="utf-8",
        )
        print(BUILD_FAILURE)
        print(f"Output: {display_path(log_path, root)}")
        print(f"Error: unable to start xcodebuild: {error}")
        return 127

    with log_path.open("w", encoding="utf-8") as log:
        log.write(f"Command: {command_text}\n")
        log.write(f"Started: {datetime.now().isoformat(timespec='seconds')}\n\n")
        if process.stdout:
            for line in process.stdout:
                captured.append(line)
                log.write(line)
                if args.verbose:
                    print(line, end="", flush=True)

    return_code = process.wait()
    elapsed = time.monotonic() - start
    succeeded = return_code == 0
    result_line = BUILD_SUCCESS if succeeded else BUILD_FAILURE

    print(result_line)
    print(f"Output: {display_path(log_path, root)}")
    print(f"Duration: {elapsed:.1f}s")

    warnings = warning_count(captured)
    if warnings:
        print(f"Warnings: {warnings}")

    if not succeeded:
        diagnostics = diagnostic_lines(
            captured,
            show_warnings=args.show_warnings,
            limit=args.max_diagnostics,
        )
        if not diagnostics:
            diagnostics = recent_lines(captured)
        if diagnostics:
            print("Diagnostics:")
            for line in diagnostics:
                print(line)
    elif args.show_warnings:
        diagnostics = diagnostic_lines(
            captured,
            show_warnings=True,
            limit=args.max_diagnostics,
        )
        if diagnostics:
            print("Warnings:")
            for line in diagnostics:
                print(line)

    return return_code


def main() -> int:
    """Parse arguments and run the build."""
    return run_build(parser().parse_args())


if __name__ == "__main__":
    sys.exit(main())
