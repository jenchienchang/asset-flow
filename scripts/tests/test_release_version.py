"""Release-version CLI tests using disposable project and archive fixtures."""

from __future__ import annotations

import copy
import plistlib
import re
import subprocess
import sys
from pathlib import Path

import pytest

from scripts.release_version import PROJECT, ROOT, app_configurations, parse_project

pytestmark = pytest.mark.skipif(
    sys.platform != "darwin", reason="Release-version tooling requires macOS plutil"
)

SCRIPT = ROOT / "scripts/release_version.py"
VERSION = "9.8.7"


def run_cli(root: Path, *arguments: str, success: bool = True) -> str:
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--root", str(root), *arguments],
        capture_output=True,
        text=True,
        check=False,
    )
    output = result.stdout + result.stderr
    assert result.returncode == (0 if success else 1), output
    return output


@pytest.fixture
def release_root(tmp_path: Path) -> Path:
    """Copy the real project, removing markers and remapping app config IDs."""
    source = (ROOT / PROJECT).read_text(encoding="utf-8")
    source = re.sub(r"/\* x-release-please-version \*/", "", source)
    for index, (identifier, _) in enumerate(app_configurations(parse_project(source))):
        source = source.replace(identifier, f"{index + 1:024X}")
    project = tmp_path / PROJECT
    project.parent.mkdir()
    project.write_text(source, encoding="utf-8")
    (tmp_path / "version.txt").write_text(VERSION + "\n", encoding="utf-8")
    return tmp_path


@pytest.fixture
def synchronized_root(release_root: Path) -> Path:
    run_cli(release_root, "sync")
    return release_root


@pytest.fixture
def archive(release_root: Path) -> Path:
    path = release_root / "AssetFlow.xcarchive"
    info = path / "Products/Applications/AssetFlow.app/Contents/Info.plist"
    info.parent.mkdir(parents=True)
    return path


def archive_info(archive: Path) -> Path:
    return archive / "Products/Applications/AssetFlow.app/Contents/Info.plist"


def test_check_rejects_mismatched_project_without_modifying_it(
    release_root: Path,
) -> None:
    project = release_root / PROJECT
    before = project.read_bytes()
    assert f"Expected MARKETING_VERSION {VERSION}" in run_cli(
        release_root, "check", success=False
    )
    assert project.read_bytes() == before


def test_sync_changes_only_app_marketing_versions(release_root: Path) -> None:
    project = release_root / PROJECT
    before = parse_project(project.read_text(encoding="utf-8"))
    expected = copy.deepcopy(before)
    for identifier, _ in app_configurations(before):
        expected["objects"][identifier]["buildSettings"]["MARKETING_VERSION"] = VERSION

    run_cli(release_root, "sync")

    assert parse_project(project.read_text(encoding="utf-8")) == expected
    assert f"All app configurations match version.txt ({VERSION})" in run_cli(
        release_root, "check"
    )


def test_sync_preserves_bytes_when_versions_already_match(
    synchronized_root: Path,
) -> None:
    project = synchronized_root / PROJECT
    before = project.read_bytes()
    run_cli(synchronized_root, "sync")
    assert project.read_bytes() == before


@pytest.mark.parametrize("setting", ["missing", "quoted"])
def test_sync_repairs_missing_or_quoted_settings(
    synchronized_root: Path, setting: str
) -> None:
    project = synchronized_root / PROJECT
    source = project.read_text(encoding="utf-8")
    expected = parse_project(source)
    replacement = "" if setting == "missing" else 'MARKETING_VERSION = "1.2.3";'
    project.write_text(
        source.replace(f"MARKETING_VERSION = {VERSION};", replacement, 1),
        encoding="utf-8",
    )
    run_cli(synchronized_root, "check", success=False)
    run_cli(synchronized_root, "sync")
    assert parse_project(project.read_text(encoding="utf-8")) == expected


@pytest.mark.parametrize(
    ("original", "replacement", "error"),
    [
        (
            f"MARKETING_VERSION = {VERSION};",
            f'"MARKETING_VERSION[sdk=macosx*]" = {VERSION};',
            "conditional MARKETING_VERSION overrides",
        ),
        ("name = Testing;", "name = Other;", "Debug, Release and Testing"),
        ("name = AssetFlow;", "name = OtherApp;", "exactly one AssetFlow"),
    ],
    ids=["conditional-override", "missing-configuration", "missing-target"],
)
@pytest.mark.parametrize("command", ["sync", "check"])
def test_rejects_invalid_project_settings_without_writing(
    synchronized_root: Path,
    original: str,
    replacement: str,
    error: str,
    command: str,
) -> None:
    project = synchronized_root / PROJECT
    source = project.read_text(encoding="utf-8")
    assert original in source
    project.write_text(source.replace(original, replacement, 1), encoding="utf-8")
    before = project.read_bytes()
    assert error in run_cli(synchronized_root, command, success=False)
    assert project.read_bytes() == before


def test_version_prints_valid_version(release_root: Path) -> None:
    assert run_cli(release_root, "version").strip() == VERSION


@pytest.mark.parametrize(
    "version", ["", "1.2", "1.2.3-beta", "1.2.3+build", "1. 2.3", "1.2.3\n4.5.6"]
)
@pytest.mark.parametrize("command", ["sync", "check", "version"])
def test_rejects_invalid_versions_without_changing_project(
    release_root: Path, version: str, command: str
) -> None:
    (release_root / "version.txt").write_text(version, encoding="utf-8")
    project = release_root / PROJECT
    before = project.read_bytes()
    assert "numeric major.minor.patch" in run_cli(release_root, command, success=False)
    assert project.read_bytes() == before


@pytest.mark.parametrize("command", ["sync", "check", "version"])
def test_rejects_missing_version_file(release_root: Path, command: str) -> None:
    (release_root / "version.txt").unlink()
    project = release_root / PROJECT
    before = project.read_bytes()
    assert "version.txt" in run_cli(release_root, command, success=False)
    assert project.read_bytes() == before


@pytest.mark.parametrize("command", ["sync", "check"])
def test_rejects_malformed_project_without_writing(
    release_root: Path, command: str
) -> None:
    project = release_root / PROJECT
    project.write_text("invalid project", encoding="utf-8")
    assert "Cannot parse Xcode project" in run_cli(release_root, command, success=False)
    assert project.read_text(encoding="utf-8") == "invalid project"


@pytest.mark.parametrize(
    "fmt", [plistlib.FMT_XML, plistlib.FMT_BINARY], ids=["xml", "binary"]
)
def test_archive_accepts_matching_version_without_writing(
    release_root: Path, archive: Path, fmt: plistlib.PlistFormat
) -> None:
    info = archive_info(archive)
    info.write_bytes(plistlib.dumps({"CFBundleShortVersionString": VERSION}, fmt=fmt))
    before = info.read_bytes()
    assert f"Archived app matches version.txt ({VERSION})" in run_cli(
        release_root, "archive", str(archive)
    )
    assert info.read_bytes() == before


@pytest.mark.parametrize(
    "actual", ["1.2.3", None, 987], ids=["mismatch", "missing", "type"]
)
def test_archive_rejects_invalid_version_without_writing(
    release_root: Path, archive: Path, actual: str | int | None
) -> None:
    info = archive_info(archive)
    value = {} if actual is None else {"CFBundleShortVersionString": actual}
    info.write_bytes(plistlib.dumps(value))
    before = info.read_bytes()
    assert "Archive version mismatch" in run_cli(
        release_root, "archive", str(archive), success=False
    )
    assert info.read_bytes() == before


def test_archive_rejects_missing_plist(release_root: Path, archive: Path) -> None:
    info = archive_info(archive)
    assert "Info.plist" in run_cli(release_root, "archive", str(archive), success=False)
    assert not info.exists()


def test_archive_rejects_malformed_plist_without_writing(
    release_root: Path, archive: Path
) -> None:
    info = archive_info(archive)
    info.write_text("invalid plist", encoding="utf-8")
    assert "Release version error:" in run_cli(
        release_root, "archive", str(archive), success=False
    )
    assert info.read_text(encoding="utf-8") == "invalid plist"
