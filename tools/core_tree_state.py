#!/usr/bin/env python3
"""Snapshot and sanitize a Codex wrapper's vendored SCV Core tree."""

from __future__ import annotations

import argparse
import hashlib
import os
import shutil
import stat
from pathlib import Path
from typing import NoReturn


MIGRATED_RUNTIME_DIRECTORIES = {
    ("core", "DeckUI", "node_modules"),
    ("core", "DeckUI", "scripts", "deckdoc", "node_modules"),
    ("core", "DeckUI", "dist-deck"),
}
MANAGED_DECKS = {"demo-prd", "refund"}


def fail(message: str) -> NoReturn:
    raise SystemExit(f"error: {message}")


def _open_directory(path: Path) -> int:
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
    flags |= getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        fail(f"cannot open ordinary directory {path}: {error}")
    entry = os.fstat(descriptor)
    if not stat.S_ISDIR(entry.st_mode):
        os.close(descriptor)
        fail(f"tree root is not an ordinary directory: {path}")
    return descriptor


def _same_entry(first: os.stat_result, second: os.stat_result) -> bool:
    return (
        first.st_dev == second.st_dev
        and first.st_ino == second.st_ino
        and first.st_mode == second.st_mode
    )


def _digest_directory(
    directory_fd: int,
    relative: tuple[str, ...],
    digest: "hashlib._Hash",
    root_device: int,
) -> None:
    try:
        names = sorted(os.listdir(directory_fd))
    except OSError as error:
        fail(f"cannot list tree directory {'/'.join(relative) or '.'}: {error}")

    for name in names:
        child_relative = relative + (name,)
        encoded = "/".join(child_relative).encode("utf-8", "surrogateescape")
        try:
            before = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
        except OSError as error:
            fail(f"cannot inspect tree entry {encoded!r}: {error}")
        mode = stat.S_IMODE(before.st_mode)
        digest.update(encoded + b"\0" + str(mode).encode() + b"\0")

        if stat.S_ISDIR(before.st_mode):
            if before.st_dev != root_device:
                fail(f"tree crosses a filesystem boundary: {encoded!r}")
            flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
            flags |= getattr(os, "O_NOFOLLOW", 0)
            try:
                child_fd = os.open(name, flags, dir_fd=directory_fd)
            except OSError as error:
                fail(f"cannot open tree directory {encoded!r}: {error}")
            try:
                opened = os.fstat(child_fd)
                if not _same_entry(before, opened):
                    fail(f"tree directory changed while reading: {encoded!r}")
                digest.update(b"D\0")
                _digest_directory(
                    child_fd, child_relative, digest, root_device
                )
                after = os.stat(
                    name, dir_fd=directory_fd, follow_symlinks=False
                )
                if not _same_entry(before, after):
                    fail(f"tree directory changed while reading: {encoded!r}")
            finally:
                os.close(child_fd)
        elif stat.S_ISREG(before.st_mode):
            flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
            try:
                child_fd = os.open(name, flags, dir_fd=directory_fd)
            except OSError as error:
                fail(f"cannot open tree file {encoded!r}: {error}")
            try:
                opened = os.fstat(child_fd)
                if not _same_entry(before, opened):
                    fail(f"tree file changed while reading: {encoded!r}")
                digest.update(b"F\0")
                while True:
                    chunk = os.read(child_fd, 1024 * 1024)
                    if not chunk:
                        break
                    digest.update(chunk)
                after_open = os.fstat(child_fd)
                after_path = os.stat(
                    name, dir_fd=directory_fd, follow_symlinks=False
                )
                if (
                    not _same_entry(before, after_open)
                    or not _same_entry(before, after_path)
                    or before.st_size != after_open.st_size
                    or before.st_mtime_ns != after_open.st_mtime_ns
                ):
                    fail(f"tree file changed while reading: {encoded!r}")
            finally:
                os.close(child_fd)
            digest.update(b"\0")
        elif stat.S_ISLNK(before.st_mode):
            try:
                target = os.readlink(name, dir_fd=directory_fd)
                after = os.stat(
                    name, dir_fd=directory_fd, follow_symlinks=False
                )
            except OSError as error:
                fail(f"cannot read tree link {encoded!r}: {error}")
            if not _same_entry(before, after):
                fail(f"tree link changed while reading: {encoded!r}")
            digest.update(
                b"L\0" + os.fsencode(target) + b"\0"
            )
        else:
            fail(f"tree contains a special file: {'/'.join(child_relative)}")


def tree_digest_fd(descriptor: int) -> str:
    entry = os.fstat(descriptor)
    if not stat.S_ISDIR(entry.st_mode):
        fail("tree descriptor is not an ordinary directory")
    digest = hashlib.sha256()
    digest.update(
        b"ROOT\0" + str(stat.S_IMODE(entry.st_mode)).encode() + b"\0"
    )
    _digest_directory(descriptor, (), digest, entry.st_dev)
    return digest.hexdigest()


def tree_digest(root: Path) -> str:
    descriptor = _open_directory(root)
    try:
        return tree_digest_fd(descriptor)
    finally:
        os.close(descriptor)


def _is_generated_deck(parts: tuple[str, ...]) -> bool:
    return (
        len(parts) == 7
        and parts[:5] == ("core", "DeckUI", "src", "deck", "decks")
        and parts[-1] == "deck.json"
        and parts[-2] not in MANAGED_DECKS
    )


def _is_generated_deck_directory(parts: tuple[str, ...]) -> bool:
    return (
        len(parts) == 6
        and parts[:5] == ("core", "DeckUI", "src", "deck", "decks")
        and parts[-1] not in MANAGED_DECKS
    )


def _copy_sanitized_directory(
    source: Path,
    destination: Path,
    relative: tuple[str, ...],
) -> None:
    try:
        entries = sorted(os.scandir(source), key=lambda entry: entry.name)
    except OSError as error:
        fail(f"cannot list existing vendor tree {source}: {error}")

    for entry in entries:
        parts = relative + (entry.name,)
        source_entry = source / entry.name
        destination_entry = destination / entry.name
        try:
            metadata = entry.stat(follow_symlinks=False)
        except OSError as error:
            fail(f"cannot inspect existing vendor entry {source_entry}: {error}")

        if parts in MIGRATED_RUNTIME_DIRECTORIES and (
            stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode)
        ):
            continue
        if _is_generated_deck(parts):
            continue

        if stat.S_ISDIR(metadata.st_mode):
            excluded_generated_deck = (
                _is_generated_deck_directory(parts)
                and (
                    (source_entry / "deck.json").exists()
                    or (source_entry / "deck.json").is_symlink()
                )
            )
            destination_entry.mkdir(mode=stat.S_IMODE(metadata.st_mode))
            _copy_sanitized_directory(source_entry, destination_entry, parts)
            if excluded_generated_deck and not any(destination_entry.iterdir()):
                destination_entry.rmdir()
        elif stat.S_ISREG(metadata.st_mode):
            if metadata.st_nlink != 1:
                fail(f"existing immutable Core file is hard-linked: {source_entry}")
            shutil.copy2(source_entry, destination_entry)
        elif stat.S_ISLNK(metadata.st_mode):
            fail(f"existing immutable Core contains a link: {source_entry}")
        else:
            fail(f"existing immutable Core contains a special file: {source_entry}")


def sanitize_tree(source: Path, destination: Path) -> None:
    try:
        source_entry = source.lstat()
    except OSError as error:
        fail(f"cannot inspect existing vendor root {source}: {error}")
    if not stat.S_ISDIR(source_entry.st_mode):
        fail(f"existing vendor is not an ordinary directory: {source}")
    if destination.exists() or destination.is_symlink():
        fail(f"sanitized output already exists: {destination}")
    destination.mkdir(mode=stat.S_IMODE(source_entry.st_mode), parents=True)
    _copy_sanitized_directory(source, destination, ())


def has_runtime(deckui: Path) -> bool:
    try:
        metadata = deckui.lstat()
    except FileNotFoundError:
        return False
    except OSError as error:
        fail(f"cannot inspect DeckUI runtime source {deckui}: {error}")
    if not stat.S_ISDIR(metadata.st_mode):
        fail(f"DeckUI runtime source is not an ordinary directory: {deckui}")

    for relative in (
        Path("node_modules"),
        Path("scripts/deckdoc/node_modules"),
        Path("dist-deck"),
    ):
        candidate = deckui / relative
        if candidate.exists() or candidate.is_symlink():
            return True

    decks = deckui / "src/deck/decks"
    if decks.is_symlink():
        fail(f"generated Deck directory is a symlink: {decks}")
    if not decks.is_dir():
        return False
    for entry in os.scandir(decks):
        if entry.name in MANAGED_DECKS:
            continue
        try:
            entry_metadata = entry.stat(follow_symlinks=False)
        except OSError as error:
            fail(f"cannot inspect generated Deck entry {entry.path}: {error}")
        if stat.S_ISLNK(entry_metadata.st_mode):
            fail(f"generated Deck directory is a symlink: {entry.path}")
        if not stat.S_ISDIR(entry_metadata.st_mode):
            continue
        candidate = Path(entry.path) / "deck.json"
        if candidate.exists() or candidate.is_symlink():
            return True
    return False


def _copy_entry_from_fd(
    source_parent_fd: int,
    name: str,
    destination: Path,
    root_device: int,
    display: str,
) -> None:
    try:
        before = os.stat(name, dir_fd=source_parent_fd, follow_symlinks=False)
    except OSError as error:
        fail(f"cannot inspect runtime entry {display}: {error}")

    if stat.S_ISLNK(before.st_mode):
        try:
            target = os.readlink(name, dir_fd=source_parent_fd)
            after = os.stat(
                name, dir_fd=source_parent_fd, follow_symlinks=False
            )
        except OSError as error:
            fail(f"cannot read runtime link {display}: {error}")
        if not _same_entry(before, after):
            fail(f"runtime link changed while reading: {display}")
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.symlink_to(target)
        return

    if stat.S_ISREG(before.st_mode):
        flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
        try:
            source_fd = os.open(name, flags, dir_fd=source_parent_fd)
        except OSError as error:
            fail(f"cannot open runtime file {display}: {error}")
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination_fd = -1
        try:
            opened = os.fstat(source_fd)
            if not _same_entry(before, opened):
                fail(f"runtime file changed while opening: {display}")
            destination_fd = os.open(
                destination,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                stat.S_IMODE(before.st_mode),
            )
            while True:
                chunk = os.read(source_fd, 1024 * 1024)
                if not chunk:
                    break
                offset = 0
                while offset < len(chunk):
                    offset += os.write(destination_fd, chunk[offset:])
            os.fchmod(destination_fd, stat.S_IMODE(before.st_mode))
            after_open = os.fstat(source_fd)
            after_path = os.stat(
                name, dir_fd=source_parent_fd, follow_symlinks=False
            )
            if (
                not _same_entry(before, after_open)
                or not _same_entry(before, after_path)
                or before.st_size != after_open.st_size
                or before.st_mtime_ns != after_open.st_mtime_ns
            ):
                fail(f"runtime file changed while reading: {display}")
        finally:
            if destination_fd >= 0:
                os.close(destination_fd)
            os.close(source_fd)
        return

    if not stat.S_ISDIR(before.st_mode):
        fail(f"runtime contains a special file: {display}")
    if before.st_dev != root_device:
        fail(f"runtime crosses a filesystem boundary: {display}")
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
    flags |= getattr(os, "O_NOFOLLOW", 0)
    try:
        source_fd = os.open(name, flags, dir_fd=source_parent_fd)
    except OSError as error:
        fail(f"cannot open runtime directory {display}: {error}")
    try:
        opened = os.fstat(source_fd)
        if not _same_entry(before, opened):
            fail(f"runtime directory changed while opening: {display}")
        destination.mkdir(
            mode=stat.S_IMODE(before.st_mode), parents=True, exist_ok=False
        )
        for child in sorted(os.listdir(source_fd)):
            _copy_entry_from_fd(
                source_fd,
                child,
                destination / child,
                root_device,
                f"{display}/{child}",
            )
        after = os.stat(
            name, dir_fd=source_parent_fd, follow_symlinks=False
        )
        if not _same_entry(before, after):
            fail(f"runtime directory changed while reading: {display}")
        os.chmod(destination, stat.S_IMODE(before.st_mode))
    finally:
        os.close(source_fd)


def _open_relative_directory(
    root_fd: int, parts: tuple[str, ...]
) -> int | None:
    current_fd = os.dup(root_fd)
    try:
        for index, part in enumerate(parts):
            try:
                before = os.stat(
                    part, dir_fd=current_fd, follow_symlinks=False
                )
            except FileNotFoundError:
                os.close(current_fd)
                return None
            except OSError as error:
                fail(
                    f"cannot inspect runtime directory "
                    f"{'/'.join(parts[:index + 1])}: {error}"
                )
            if not stat.S_ISDIR(before.st_mode):
                fail(
                    "runtime path is not an ordinary directory: "
                    f"{'/'.join(parts[:index + 1])}"
                )
            flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
            flags |= getattr(os, "O_NOFOLLOW", 0)
            child_fd = os.open(part, flags, dir_fd=current_fd)
            opened = os.fstat(child_fd)
            if not _same_entry(before, opened):
                os.close(child_fd)
                fail(
                    "runtime directory changed while opening: "
                    f"{'/'.join(parts[:index + 1])}"
                )
            os.close(current_fd)
            current_fd = child_fd
        return current_fd
    except BaseException:
        try:
            os.close(current_fd)
        except OSError:
            pass
        raise


def _copy_runtime_from_deckui_fd(
    deckui_fd: int, destination: Path, root_device: int
) -> bool:
    found = False
    destination.mkdir(mode=0o700, parents=True)

    runtime_paths = (
        ("node_modules",),
        ("scripts", "deckdoc", "node_modules"),
        ("dist-deck",),
    )
    for parts in runtime_paths:
        parent_parts = parts[:-1]
        parent_fd = (
            _open_relative_directory(deckui_fd, parent_parts)
            if parent_parts
            else os.dup(deckui_fd)
        )
        if parent_fd is None:
            continue
        try:
            entry = _entry_at_fd(parent_fd, parts[-1])
            if entry is None:
                continue
            _copy_entry_from_fd(
                parent_fd,
                parts[-1],
                destination.joinpath(*parts),
                root_device,
                "/".join(parts),
            )
            found = True
        finally:
            os.close(parent_fd)

    decks_fd = _open_relative_directory(
        deckui_fd, ("src", "deck", "decks")
    )
    if decks_fd is not None:
        try:
            for slug in sorted(os.listdir(decks_fd)):
                if slug in MANAGED_DECKS:
                    continue
                directory_entry = _entry_at_fd(decks_fd, slug)
                if directory_entry is None:
                    continue
                if stat.S_ISLNK(directory_entry.st_mode):
                    fail(f"generated Deck directory is a symlink: {slug}")
                if not stat.S_ISDIR(directory_entry.st_mode):
                    continue
                slug_fd = _open_relative_directory(decks_fd, (slug,))
                if slug_fd is None:
                    continue
                try:
                    generated = _entry_at_fd(slug_fd, "deck.json")
                    if generated is None:
                        continue
                    if not stat.S_ISREG(generated.st_mode):
                        fail(
                            "generated Deck file is unsafe: "
                            f"src/deck/decks/{slug}/deck.json"
                        )
                    _copy_entry_from_fd(
                        slug_fd,
                        "deck.json",
                        destination
                        / "src"
                        / "deck"
                        / "decks"
                        / slug
                        / "deck.json",
                        root_device,
                        f"src/deck/decks/{slug}/deck.json",
                    )
                    found = True
                finally:
                    os.close(slug_fd)
        finally:
            os.close(decks_fd)
    return found


def _entry_at_fd(directory_fd: int, name: str) -> os.stat_result | None:
    try:
        return os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
    except FileNotFoundError:
        return None
    except OSError as error:
        fail(f"cannot inspect runtime path {name}: {error}")


def export_runtime(
    source_root: Path,
    destination: Path,
    expected_digest: str,
    direct_deckui: bool,
) -> bool:
    root_fd = _open_directory(source_root)
    try:
        opened_root = os.fstat(root_fd)
        if tree_digest_fd(root_fd) != expected_digest:
            fail("runtime source changed before extraction")
        deckui_fd = (
            os.dup(root_fd)
            if direct_deckui
            else _open_relative_directory(root_fd, ("core", "DeckUI"))
        )
        if deckui_fd is None:
            fail("vendored Core lacks core/DeckUI")
        try:
            found = _copy_runtime_from_deckui_fd(
                deckui_fd, destination, opened_root.st_dev
            )
        finally:
            os.close(deckui_fd)
        if tree_digest_fd(root_fd) != expected_digest:
            fail("runtime source changed during extraction")
        path_entry = source_root.lstat()
        if not _same_entry(opened_root, path_entry):
            fail("runtime source path identity changed during extraction")
        return found
    finally:
        os.close(root_fd)


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    snapshot_parser = subparsers.add_parser("snapshot")
    snapshot_parser.add_argument("--root", required=True, type=Path)

    sanitize_parser = subparsers.add_parser("sanitize")
    sanitize_parser.add_argument("--root", required=True, type=Path)
    sanitize_parser.add_argument("--output", required=True, type=Path)

    runtime_parser = subparsers.add_parser("has-runtime")
    runtime_root = runtime_parser.add_mutually_exclusive_group(required=True)
    runtime_root.add_argument("--root", type=Path)
    runtime_root.add_argument("--deckui-root", type=Path)

    export_parser = subparsers.add_parser("export-runtime")
    export_source = export_parser.add_mutually_exclusive_group(required=True)
    export_source.add_argument("--root", type=Path)
    export_source.add_argument("--deckui-root", type=Path)
    export_parser.add_argument("--output", required=True, type=Path)
    export_parser.add_argument("--expected-digest", required=True)

    args = parser.parse_args()
    if args.command == "snapshot":
        print(tree_digest(args.root))
    elif args.command == "sanitize":
        sanitize_tree(args.root, args.output)
    elif args.command == "has-runtime":
        deckui = args.deckui_root or args.root / "core/DeckUI"
        print("yes" if has_runtime(deckui) else "no")
    else:
        source = args.deckui_root or args.root
        found = export_runtime(
            source,
            args.output,
            args.expected_digest,
            args.deckui_root is not None,
        )
        print("yes" if found else "no")


if __name__ == "__main__":
    main()
