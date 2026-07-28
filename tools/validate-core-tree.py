#!/usr/bin/env python3
"""Reject links and special files in a materialized SCV Core tree."""

from __future__ import annotations

import argparse
import stat
from pathlib import Path


def validate(root: Path) -> None:
    root_stat = root.lstat()
    if not stat.S_ISDIR(root_stat.st_mode):
        raise SystemExit(f"error: materialized core root is not a directory: {root}")

    for path in root.rglob("*"):
        entry = path.lstat()
        if stat.S_ISDIR(entry.st_mode):
            continue
        if stat.S_ISREG(entry.st_mode) and entry.st_nlink == 1:
            continue
        raise SystemExit(
            f"error: materialized core contains a link or special file: {path}"
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    args = parser.parse_args()
    validate(args.root)


if __name__ == "__main__":
    main()
