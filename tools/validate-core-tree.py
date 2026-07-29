#!/usr/bin/env python3
"""Reject links and special files in a materialized SCV Core tree."""

from __future__ import annotations

import argparse
import json
import stat
from pathlib import Path
from typing import NoReturn


def fail(message: str) -> NoReturn:
    raise SystemExit(f"error: {message}")


def validate(root: Path) -> None:
    try:
        root_stat = root.lstat()
    except OSError as error:
        fail(f"cannot inspect materialized core root {root}: {error}")
    if not stat.S_ISDIR(root_stat.st_mode):
        fail(f"materialized core root is not an ordinary directory: {root}")

    for path in root.rglob("*"):
        try:
            entry = path.lstat()
        except OSError as error:
            fail(f"cannot inspect materialized core entry {path}: {error}")
        if stat.S_ISDIR(entry.st_mode):
            continue
        if stat.S_ISREG(entry.st_mode) and entry.st_nlink == 1:
            continue
        fail(f"materialized core contains a link or special file: {path}")

    manifest_path = root / "core-manifest.json"
    if not manifest_path.is_file():
        fail("materialized core lacks core-manifest.json")
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"invalid core-manifest.json: {error}")
    if not isinstance(manifest, dict) or not isinstance(
        manifest.get("files"), list
    ):
        fail("core manifest files must be an array")

    listed: set[str] = set()
    for entry in manifest["files"]:
        relative = entry.get("path") if isinstance(entry, dict) else None
        if not isinstance(relative, str):
            fail("core manifest contains an invalid file path")
        if "\\" in relative or "\x00" in relative:
            fail(f"unsafe core manifest path: {relative!r}")
        path = Path(relative)
        if path.is_absolute() or not path.parts or any(
            part in {"", ".", ".."} for part in path.parts
        ):
            fail(f"unsafe core manifest path: {relative}")
        normalized = path.as_posix()
        if normalized != relative:
            fail(f"non-canonical core manifest path: {relative}")
        if normalized in listed:
            fail(f"duplicate core manifest path: {normalized}")
        listed.add(normalized)

    metadata = {
        "CHANGELOG.md",
        "LICENSE",
        "README.md",
        "README.ko.md",
        "README.ja.md",
        "SHA256SUMS",
        "core-manifest.json",
        "core.lock.json",
    }
    allowed_files = listed | metadata
    actual_files = {
        path.relative_to(root).as_posix()
        for path in root.rglob("*")
        if path.is_file()
    }
    missing_files = sorted(allowed_files - actual_files)
    extra_files = sorted(actual_files - allowed_files)
    if missing_files:
        fail(f"materialized core files are missing: {missing_files}")
    if extra_files:
        fail(f"materialized core contains untracked files: {extra_files}")

    allowed_directories: set[str] = set()
    for relative in allowed_files:
        parent = Path(relative).parent
        while parent != Path("."):
            allowed_directories.add(parent.as_posix())
            parent = parent.parent
    actual_directories = {
        path.relative_to(root).as_posix()
        for path in root.rglob("*")
        if path.is_dir()
    }
    extra_directories = sorted(actual_directories - allowed_directories)
    if extra_directories:
        fail(
            "materialized core contains untracked directories: "
            f"{extra_directories}"
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    args = parser.parse_args()
    validate(args.root)


if __name__ == "__main__":
    main()
