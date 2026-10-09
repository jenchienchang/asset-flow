#!/usr/bin/env python3
"""Synchronize and verify release versions using macOS tools and Python only."""

from __future__ import annotations

import argparse
import copy
import json
import plistlib
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
PROJECT = Path("AssetFlow.xcodeproj/project.pbxproj")


def read_version(root: Path) -> str:
    version = (root / "version.txt").read_text(encoding="utf-8").strip()
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError("version.txt must contain a numeric major.minor.patch version")
    return version


def parse_project(source: str) -> dict[str, Any]:
    result = subprocess.run(
        ["/usr/bin/plutil", "-convert", "json", "-o", "-", "--", "-"],
        input=source,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode:
        raise ValueError(f"Cannot parse Xcode project: {result.stdout}{result.stderr}")
    return json.loads(result.stdout)


def app_configurations(project: dict[str, Any]) -> list[tuple[str, dict[str, Any]]]:
    objects = project["objects"]
    targets = [
        objects[identifier]
        for identifier in objects[project["rootObject"]]["targets"]
        if objects[identifier].get("isa") == "PBXNativeTarget"
        and objects[identifier].get("name") == "AssetFlow"
        and objects[identifier].get("productType")
        == "com.apple.product-type.application"
    ]
    if len(targets) != 1:
        raise ValueError("Expected exactly one AssetFlow application target")
    identifiers = objects[targets[0]["buildConfigurationList"]]["buildConfigurations"]
    configurations = [(identifier, objects[identifier]) for identifier in identifiers]
    names = [configuration.get("name") for _, configuration in configurations]
    if len(set(identifiers)) != len(identifiers) or len(set(names)) != len(names):
        raise ValueError("Duplicate app build configurations")
    if not {"Debug", "Release", "Testing"}.issubset(names):
        raise ValueError("App target must include Debug, Release and Testing")
    for _, configuration in configurations:
        if configuration.get("isa") != "XCBuildConfiguration":
            raise ValueError("Invalid app build configuration")
        settings = configuration["buildSettings"]
        if any(key.startswith("MARKETING_VERSION[") for key in settings):
            raise ValueError(
                f"{configuration['name']}: remove conditional MARKETING_VERSION overrides"
            )
    return configurations


def check_project(root: Path) -> None:
    expected = read_version(root)
    project = parse_project((root / PROJECT).read_text(encoding="utf-8"))
    mismatches = [
        f"{configuration['name']}: {configuration['buildSettings'].get('MARKETING_VERSION')!r}"
        for _, configuration in app_configurations(project)
        if configuration["buildSettings"].get("MARKETING_VERSION") != expected
    ]
    if mismatches:
        raise ValueError(
            f"Expected MARKETING_VERSION {expected}; {'; '.join(mismatches)}. "
            "Run python3 scripts/release_version.py sync."
        )
    print(f"All app configurations match version.txt ({expected})")


def sync_project(root: Path) -> None:
    version = read_version(root)
    path = root / PROJECT
    original = path.read_text(encoding="utf-8")
    source = original
    project = parse_project(source)
    expected = copy.deepcopy(project)
    for identifier, configuration in app_configurations(project):
        if configuration["buildSettings"].get("MARKETING_VERSION") == version:
            continue
        # Locate only the objects selected by the plist parser. Preserve Xcode's
        # serialization, comments and all unrelated settings instead of rewriting
        # the project as XML/JSON. Unexpected formatting fails before any write.
        pattern = re.compile(
            rf"^(?P<indent>[ \t]*){re.escape(identifier)}[ \t]*"
            rf"(?:/\*[^\n]*?\*/[ \t]*)?=[ \t]*\{{.*?^(?P=indent)\}};",
            re.MULTILINE | re.DOTALL,
        )
        blocks = list(pattern.finditer(source))
        if len(blocks) != 1:
            raise ValueError(f"Cannot locate configuration {configuration['name']}")
        block = blocks[0]
        text = block.group()
        assignment = re.compile(
            r"^(?P<prefix>[ \t]*MARKETING_VERSION[ \t]*=[ \t]*)"
            r'(?:"(?:\\.|[^"\\])*"|[^;\n]+);',
            re.MULTILINE,
        )
        if "MARKETING_VERSION" in configuration["buildSettings"]:
            text, count = assignment.subn(
                lambda match: f"{match['prefix']}{version};", text
            )
        else:
            text, count = re.subn(
                r"^([ \t]*)buildSettings[ \t]*=[ \t]*\{\n",
                lambda match: f"{match.group()}{match[1]}\tMARKETING_VERSION = {version};\n",
                text,
                flags=re.MULTILINE,
            )
        if count != 1:
            raise ValueError(f"Cannot update configuration {configuration['name']}")
        source = source[: block.start()] + text + source[block.end() :]
        expected["objects"][identifier]["buildSettings"]["MARKETING_VERSION"] = version
    # Validate the entire object graph before writing; only the selected settings
    # may differ. This also guards against a text match inside a quoted value.
    if parse_project(source) != expected:
        raise ValueError("Version synchronization changed unrelated project data")
    if path.read_text(encoding="utf-8") != original:
        raise ValueError("Xcode project changed during synchronization; retry")
    if source != original:
        path.write_text(source, encoding="utf-8")
    check_project(root)


def check_archive(root: Path, archive: Path) -> None:
    expected = read_version(root)
    path = archive / "Products/Applications/AssetFlow.app/Contents/Info.plist"
    with path.open("rb") as file:
        info = plistlib.load(file)
    actual = info.get("CFBundleShortVersionString")
    if actual != expected:
        raise ValueError(
            f"Archive version mismatch: expected {expected}, found {actual!r}"
        )
    print(f"Archived app matches version.txt ({expected})")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("sync", help="Update app target MARKETING_VERSION settings")
    commands.add_parser("check", help="Verify every app target configuration")
    commands.add_parser("version", help="Print the validated release version")
    archive = commands.add_parser("archive", help="Verify the finished archived app")
    archive.add_argument("path", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "sync":
            sync_project(args.root)
        elif args.command == "check":
            check_project(args.root)
        elif args.command == "archive":
            check_archive(args.root, args.path)
        else:
            print(read_version(args.root))
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"Release version error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
