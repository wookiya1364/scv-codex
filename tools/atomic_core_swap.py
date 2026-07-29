#!/usr/bin/env python3
"""Atomically replace one verified SCV Core directory without following paths.

The caller prepares an install directory in the target's parent and supplies
stable digests for both the live preimage and the candidate.  Every lookup and
rename in the transaction is relative to one opened parent-directory
descriptor, so a late parent-path symlink cannot redirect the operation.
"""

from __future__ import annotations

import argparse
import ctypes
import errno
import hashlib
import os
import re
import signal
import stat
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import NoReturn

sys.dont_write_bytecode = True

from core_tree_state import tree_digest_fd  # noqa: E402


SIGNALS = (signal.SIGHUP, signal.SIGINT, signal.SIGTERM)


class SwapError(RuntimeError):
    pass


class SwapInterrupted(SwapError):
    def __init__(self, signum: int):
        super().__init__(f"transaction interrupted by {signal.Signals(signum).name}")
        self.signum = signum


@dataclass(frozen=True)
class LockOwner:
    pid: int
    process_start: str
    token: str
    payload: bytes


@dataclass(frozen=True)
class LockSnapshot:
    directory: os.stat_result
    owner_entry: os.stat_result
    owner: LockOwner


def fail(message: str) -> NoReturn:
    raise SystemExit(f"error: {message}")


def _validate_name(name: str, label: str) -> None:
    if (
        not name
        or name in {".", ".."}
        or "/" in name
        or (os.altsep and os.altsep in name)
        or "\x00" in name
    ):
        fail(f"unsafe {label} basename: {name!r}")


def _same_entry(first: os.stat_result, second: os.stat_result) -> bool:
    return (
        first.st_dev == second.st_dev
        and first.st_ino == second.st_ino
        and first.st_mode == second.st_mode
    )


def _entry_at(parent_fd: int, name: str) -> os.stat_result | None:
    try:
        return os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
    except FileNotFoundError:
        return None
    except OSError as error:
        raise SwapError(f"cannot inspect transaction path {name}: {error}") from error


def _open_parent(path: Path, expected_device: int, expected_inode: int) -> int:
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
    flags |= getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise SwapError(f"cannot open transaction parent {path}: {error}") from error
    entry = os.fstat(descriptor)
    if (
        not stat.S_ISDIR(entry.st_mode)
        or entry.st_dev != expected_device
        or entry.st_ino != expected_inode
    ):
        os.close(descriptor)
        raise SwapError("transaction parent identity or type changed")
    return descriptor


def _assert_parent_path(
    parent: Path,
    parent_fd: int,
    expected_device: int,
    expected_inode: int,
) -> None:
    try:
        path_entry = parent.lstat()
    except OSError as error:
        raise SwapError(f"transaction parent path changed: {error}") from error
    opened = os.fstat(parent_fd)
    if (
        not stat.S_ISDIR(path_entry.st_mode)
        or path_entry.st_dev != expected_device
        or path_entry.st_ino != expected_inode
        or opened.st_dev != expected_device
        or opened.st_ino != expected_inode
    ):
        raise SwapError("transaction parent identity or type changed")


def _digest_at(parent_fd: int, name: str) -> str:
    before = _entry_at(parent_fd, name)
    if before is None:
        raise SwapError(f"transaction directory disappeared: {name}")
    if not stat.S_ISDIR(before.st_mode):
        raise SwapError(f"transaction path is not an ordinary directory: {name}")
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
    flags |= getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(name, flags, dir_fd=parent_fd)
    except OSError as error:
        raise SwapError(f"cannot open transaction directory {name}: {error}") from error
    try:
        opened = os.fstat(descriptor)
        if not _same_entry(before, opened):
            raise SwapError(f"transaction directory changed while opening: {name}")
        digest = tree_digest_fd(descriptor)
        after = _entry_at(parent_fd, name)
        if after is None or not _same_entry(before, after):
            raise SwapError(f"transaction directory changed while reading: {name}")
        return digest
    finally:
        os.close(descriptor)


def _assert_digest(parent_fd: int, name: str, expected: str, label: str) -> None:
    actual = _digest_at(parent_fd, name)
    if actual != expected:
        raise SwapError(
            f"{label} changed during Core update "
            f"(expected {expected}, got {actual})"
        )


def _rename_noreplace(
    parent_fd: int, source_name: str, destination_name: str
) -> None:
    encoded_source = os.fsencode(source_name)
    encoded_destination = os.fsencode(destination_name)
    library = ctypes.CDLL(None, use_errno=True)
    result: int

    if hasattr(library, "renameat2"):
        renameat2 = library.renameat2
        renameat2.argtypes = [
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_uint,
        ]
        renameat2.restype = ctypes.c_int
        result = renameat2(
            parent_fd,
            encoded_source,
            parent_fd,
            encoded_destination,
            1,  # RENAME_NOREPLACE
        )
    elif hasattr(library, "renameatx_np"):
        renameatx_np = library.renameatx_np
        renameatx_np.argtypes = [
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_uint,
        ]
        renameatx_np.restype = ctypes.c_int
        result = renameatx_np(
            parent_fd,
            encoded_source,
            parent_fd,
            encoded_destination,
            0x00000004,  # RENAME_EXCL on macOS
        )
    else:
        raise SwapError(
            "this platform has no supported atomic no-replace rename primitive"
        )

    if result != 0:
        error_number = ctypes.get_errno()
        if error_number in {errno.EEXIST, errno.ENOTEMPTY}:
            raise SwapError(
                f"transaction destination already exists: {destination_name}"
            )
        raise SwapError(
            f"cannot rename {source_name} to {destination_name}: "
            f"{os.strerror(error_number)}"
        )


def _write_all(descriptor: int, payload: bytes) -> None:
    offset = 0
    while offset < len(payload):
        written = os.write(descriptor, payload[offset:])
        if written <= 0:
            raise SwapError("cannot write Core vendor lock owner")
        offset += written


def _read_all(descriptor: int, limit: int = 4096) -> bytes:
    chunks: list[bytes] = []
    size = 0
    while True:
        chunk = os.read(descriptor, min(4096, limit + 1 - size))
        if not chunk:
            break
        chunks.append(chunk)
        size += len(chunk)
        if size > limit:
            raise SwapError("unsafe or malformed Core vendor lock")
    return b"".join(chunks)


def _owner_payload(pid: int, process_start: str, token: str) -> bytes:
    return (
        f"pid={pid}\n"
        f"process_start={process_start}\n"
        f"token={token}\n"
    ).encode("ascii")


def _parse_lock_owner(payload: bytes) -> LockOwner:
    try:
        lines = payload.decode("ascii").splitlines()
    except UnicodeDecodeError as error:
        raise SwapError("unsafe or malformed Core vendor lock") from error
    if len(lines) != 3:
        raise SwapError("unsafe or malformed Core vendor lock")
    values: dict[str, str] = {}
    for line in lines:
        key, separator, value = line.partition("=")
        if not separator or key in values:
            raise SwapError("unsafe or malformed Core vendor lock")
        values[key] = value
    if set(values) != {"pid", "process_start", "token"}:
        raise SwapError("unsafe or malformed Core vendor lock")
    if not re.fullmatch(r"[1-9][0-9]*", values["pid"]):
        raise SwapError("unsafe or malformed Core vendor lock")
    if not re.fullmatch(
        r"(?:proc-[0-9]+|ps-[0-9a-f]{64}|unknown)",
        values["process_start"],
    ):
        raise SwapError("unsafe or malformed Core vendor lock")
    if not re.fullmatch(r"[0-9a-f]{48}", values["token"]):
        raise SwapError("unsafe or malformed Core vendor lock")
    return LockOwner(
        pid=int(values["pid"]),
        process_start=values["process_start"],
        token=values["token"],
        payload=payload,
    )


def _open_lock_directory(
    parent_fd: int, name: str
) -> tuple[int, os.stat_result]:
    before = _entry_at(parent_fd, name)
    if before is None or not stat.S_ISDIR(before.st_mode):
        raise SwapError("unsafe or malformed Core vendor lock")
    parent_entry = os.fstat(parent_fd)
    if before.st_dev != parent_entry.st_dev:
        raise SwapError("unsafe or malformed Core vendor lock")
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
    flags |= getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(name, flags, dir_fd=parent_fd)
    except OSError as error:
        raise SwapError("unsafe or malformed Core vendor lock") from error
    opened = os.fstat(descriptor)
    if not _same_entry(before, opened):
        os.close(descriptor)
        raise SwapError("Core vendor lock changed while opening")
    return descriptor, before


def _read_lock_owner_at(
    lock_fd: int, lock_entry: os.stat_result
) -> tuple[os.stat_result, LockOwner]:
    try:
        names = sorted(os.listdir(lock_fd))
    except OSError as error:
        raise SwapError("cannot list Core vendor lock") from error
    if names != ["owner"]:
        raise SwapError("unsafe or malformed Core vendor lock")
    try:
        before = os.stat("owner", dir_fd=lock_fd, follow_symlinks=False)
    except OSError as error:
        raise SwapError("unsafe or malformed Core vendor lock") from error
    if (
        not stat.S_ISREG(before.st_mode)
        or before.st_nlink != 1
        or before.st_dev != lock_entry.st_dev
    ):
        raise SwapError("unsafe or malformed Core vendor lock")
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    try:
        owner_fd = os.open("owner", flags, dir_fd=lock_fd)
    except OSError as error:
        raise SwapError("unsafe or malformed Core vendor lock") from error
    try:
        opened = os.fstat(owner_fd)
        if not _same_entry(before, opened):
            raise SwapError("Core vendor lock owner changed while opening")
        payload = _read_all(owner_fd)
        after = os.stat("owner", dir_fd=lock_fd, follow_symlinks=False)
        if not _same_entry(before, after):
            raise SwapError("Core vendor lock owner changed while reading")
    finally:
        os.close(owner_fd)
    return before, _parse_lock_owner(payload)


def _read_lock_snapshot(parent_fd: int, name: str) -> LockSnapshot:
    lock_fd, before = _open_lock_directory(parent_fd, name)
    try:
        owner_entry, owner = _read_lock_owner_at(lock_fd, before)
        after = _entry_at(parent_fd, name)
        if after is None or not _same_entry(before, after):
            raise SwapError("Core vendor lock changed while reading")
        return LockSnapshot(before, owner_entry, owner)
    finally:
        os.close(lock_fd)


def _same_lock_snapshot(first: LockSnapshot, second: LockSnapshot) -> bool:
    return (
        _same_entry(first.directory, second.directory)
        and _same_entry(first.owner_entry, second.owner_entry)
        and first.owner == second.owner
    )


def _create_lock_at(
    parent_fd: int,
    name: str,
    owner: LockOwner,
) -> LockSnapshot:
    try:
        os.mkdir(name, mode=0o700, dir_fd=parent_fd)
    except FileExistsError:
        raise
    except OSError as error:
        raise SwapError(f"cannot create Core vendor lock: {error}") from error
    _pause_for_test("after-lock-mkdir", name)
    lock_fd, lock_entry = _open_lock_directory(parent_fd, name)
    try:
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
        flags |= getattr(os, "O_NOFOLLOW", 0)
        try:
            owner_fd = os.open(
                "owner", flags, 0o600, dir_fd=lock_fd
            )
        except OSError as error:
            raise SwapError(
                "cannot create Core vendor lock owner safely"
            ) from error
        try:
            _write_all(owner_fd, owner.payload)
            os.fsync(owner_fd)
        finally:
            os.close(owner_fd)
        owner_entry, observed_owner = _read_lock_owner_at(
            lock_fd, lock_entry
        )
        if observed_owner != owner:
            raise SwapError("Core vendor lock owner changed during creation")
        after = _entry_at(parent_fd, name)
        if after is None or not _same_entry(lock_entry, after):
            raise SwapError("Core vendor lock changed during creation")
        return LockSnapshot(lock_entry, owner_entry, observed_owner)
    finally:
        os.close(lock_fd)


def _remove_lock_at(
    parent_fd: int,
    name: str,
    expected: LockSnapshot,
) -> None:
    lock_fd, lock_entry = _open_lock_directory(parent_fd, name)
    try:
        owner_entry, owner = _read_lock_owner_at(lock_fd, lock_entry)
        observed = LockSnapshot(lock_entry, owner_entry, owner)
        if not _same_lock_snapshot(observed, expected):
            raise SwapError("Core vendor lock ownership or identity changed")
        os.unlink("owner", dir_fd=lock_fd)
        if os.listdir(lock_fd):
            raise SwapError("Core vendor lock gained an unexpected entry")
        after = _entry_at(parent_fd, name)
        if after is None or not _same_entry(lock_entry, after):
            raise SwapError("Core vendor lock changed during removal")
    finally:
        os.close(lock_fd)
    os.rmdir(name, dir_fd=parent_fd)


def _process_start_id(pid: int) -> str:
    proc = Path("/proc") / str(pid) / "stat"
    try:
        fields = proc.read_text(encoding="utf-8").rsplit(")", 1)[1].split()
        return "proc-" + fields[19]
    except (IndexError, OSError):
        try:
            value = subprocess.check_output(
                ["ps", "-o", "lstart=", "-p", str(pid)],
                stderr=subprocess.DEVNULL,
            ).strip()
        except (OSError, subprocess.CalledProcessError):
            value = b""
        if value:
            return "ps-" + hashlib.sha256(value).hexdigest()
        return "unknown"


def _process_is_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def _lock_quarantine_name(
    lock_name: str, token: str, suffix: str
) -> str:
    if not lock_name.endswith(".lock"):
        raise SwapError("Core vendor lock basename must end in .lock")
    return f"{lock_name[:-5]}.stale-{suffix}-{token}"


def acquire_lock(args: argparse.Namespace) -> None:
    _validate_name(args.lock_name, "lock")
    owner_payload = _owner_payload(
        args.pid, args.process_start, args.token
    )
    owner = _parse_lock_owner(owner_payload)
    parent_fd = _open_parent(
        args.parent, args.expected_parent_device, args.expected_parent_inode
    )
    try:
        for attempt in range(1, 5):
            _assert_parent_path(
                args.parent,
                parent_fd,
                args.expected_parent_device,
                args.expected_parent_inode,
            )
            try:
                _create_lock_at(parent_fd, args.lock_name, owner)
                return
            except FileExistsError:
                pass

            stale = _read_lock_snapshot(parent_fd, args.lock_name)
            if _process_is_alive(stale.owner.pid):
                current_start = _process_start_id(stale.owner.pid)
                if (
                    stale.owner.process_start == "unknown"
                    or current_start == "unknown"
                    or stale.owner.process_start == current_start
                ):
                    raise SwapError(
                        "another Core vendor update is running "
                        f"(pid {stale.owner.pid})"
                    )

            quarantine = _lock_quarantine_name(
                args.lock_name, args.token, str(attempt)
            )
            _pause_for_test(
                "before-stale-lock-quarantine", quarantine
            )
            _assert_parent_path(
                args.parent,
                parent_fd,
                args.expected_parent_device,
                args.expected_parent_inode,
            )
            _rename_noreplace(parent_fd, args.lock_name, quarantine)
            quarantined = _read_lock_snapshot(parent_fd, quarantine)
            if not _same_lock_snapshot(stale, quarantined):
                raise SwapError(
                    "stale Core vendor lock changed before quarantine"
                )
            _remove_lock_at(parent_fd, quarantine, quarantined)
        raise SwapError("could not acquire Core vendor lock")
    finally:
        os.close(parent_fd)


def release_lock(args: argparse.Namespace) -> None:
    _validate_name(args.lock_name, "lock")
    expected_owner = _parse_lock_owner(
        _owner_payload(args.pid, args.process_start, args.token)
    )
    parent_fd = _open_parent(
        args.parent, args.expected_parent_device, args.expected_parent_inode
    )
    try:
        _assert_parent_path(
            args.parent,
            parent_fd,
            args.expected_parent_device,
            args.expected_parent_inode,
        )
        owned = _read_lock_snapshot(parent_fd, args.lock_name)
        if owned.owner != expected_owner:
            raise SwapError("Core vendor lock ownership changed")
        quarantine = _lock_quarantine_name(
            args.lock_name, args.token, "release"
        )
        _pause_for_test("before-lock-release", quarantine)
        _assert_parent_path(
            args.parent,
            parent_fd,
            args.expected_parent_device,
            args.expected_parent_inode,
        )
        _rename_noreplace(parent_fd, args.lock_name, quarantine)
        quarantined = _read_lock_snapshot(parent_fd, quarantine)
        if not _same_lock_snapshot(owned, quarantined):
            raise SwapError(
                "Core vendor lock ownership or identity changed before release"
            )
        _remove_lock_at(parent_fd, quarantine, quarantined)
    finally:
        os.close(parent_fd)


def _remove_contents(
    directory_fd: int, root_device: int, relative: tuple[str, ...]
) -> None:
    try:
        names = sorted(os.listdir(directory_fd))
    except OSError as error:
        raise SwapError(
            f"cannot list owned transaction tree {'/'.join(relative) or '.'}: "
            f"{error}"
        ) from error

    for name in names:
        child_relative = relative + (name,)
        display = "/".join(child_relative)
        try:
            before = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
        except OSError as error:
            raise SwapError(
                f"cannot inspect owned transaction entry {display}: {error}"
            ) from error
        if stat.S_ISDIR(before.st_mode):
            if before.st_dev != root_device:
                raise SwapError(
                    f"owned transaction tree crosses a filesystem boundary: {display}"
                )
            flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
            flags |= getattr(os, "O_NOFOLLOW", 0)
            try:
                child_fd = os.open(name, flags, dir_fd=directory_fd)
            except OSError as error:
                raise SwapError(
                    f"cannot open owned transaction directory {display}: {error}"
                ) from error
            try:
                opened = os.fstat(child_fd)
                if not _same_entry(before, opened):
                    raise SwapError(
                        f"owned transaction directory changed: {display}"
                    )
                _remove_contents(child_fd, root_device, child_relative)
                after = os.stat(
                    name, dir_fd=directory_fd, follow_symlinks=False
                )
                if not _same_entry(before, after):
                    raise SwapError(
                        f"owned transaction directory changed: {display}"
                    )
            finally:
                os.close(child_fd)
            os.rmdir(name, dir_fd=directory_fd)
        elif stat.S_ISREG(before.st_mode) or stat.S_ISLNK(before.st_mode):
            os.unlink(name, dir_fd=directory_fd)
        else:
            raise SwapError(
                f"owned transaction tree contains a special file: {display}"
            )


def _remove_tree_at(
    parent_fd: int, name: str, expected_digest: str, label: str
) -> None:
    _assert_digest(parent_fd, name, expected_digest, label)
    before = _entry_at(parent_fd, name)
    if before is None or not stat.S_ISDIR(before.st_mode):
        raise SwapError(f"owned transaction directory is missing: {name}")
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
    flags |= getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(name, flags, dir_fd=parent_fd)
    try:
        opened = os.fstat(descriptor)
        if not _same_entry(before, opened):
            raise SwapError(f"owned transaction directory changed: {name}")
        _remove_contents(descriptor, opened.st_dev, (name,))
        after = _entry_at(parent_fd, name)
        if after is None or not _same_entry(before, after):
            raise SwapError(f"owned transaction directory changed: {name}")
    finally:
        os.close(descriptor)
    os.rmdir(name, dir_fd=parent_fd)


def _pause_for_test(point: str, detail: str | None = None) -> None:
    if os.environ.get("SCV_VENDOR_TEST_PAUSE_AT") != point:
        return
    ready_raw = os.environ.get("SCV_VENDOR_TEST_READY_FILE")
    continue_raw = os.environ.get("SCV_VENDOR_TEST_CONTINUE_FILE")
    if not ready_raw or not continue_raw:
        raise SwapError("test pause requires ready and continue files")
    ready = Path(ready_raw)
    continuation = Path(continue_raw)
    message = point + "\n"
    if detail is not None:
        message += detail + "\n"
    ready.write_text(message, encoding="utf-8")
    deadline = time.monotonic() + 20
    while not continuation.exists():
        if time.monotonic() >= deadline:
            raise SwapError(f"timed out at transaction test pause: {point}")
        time.sleep(0.02)


def _inject(point: str, parent_fd: int, install_name: str) -> None:
    failpoint = os.environ.get("SCV_VENDOR_TEST_FAILPOINT", "")
    if failpoint == point:
        raise SwapError(f"injected Core vendor failure at {point}")
    prefix = "signal-"
    suffix = f"-{point}"
    if failpoint.startswith(prefix) and failpoint.endswith(suffix):
        signal_name = failpoint[len(prefix) : -len(suffix)]
        try:
            signum = getattr(signal, f"SIG{signal_name}")
        except AttributeError as error:
            raise SwapError(f"invalid injected signal: {signal_name}") from error
        os.kill(os.getpid(), signum)
    if failpoint == f"rollback-collision-{point}":
        os.mkdir(install_name, mode=0o700, dir_fd=parent_fd)
        raise SwapError(f"injected rollback collision at {point}")


def _signal_handler(signum: int, _frame: object) -> None:
    raise SwapInterrupted(signum)


def _install_signal_handlers() -> dict[int, object]:
    previous: dict[int, object] = {}
    for signum in SIGNALS:
        previous[signum] = signal.getsignal(signum)
        signal.signal(signum, _signal_handler)
    return previous


def _ignore_transaction_signals() -> None:
    for signum in SIGNALS:
        signal.signal(signum, signal.SIG_IGN)


def swap(args: argparse.Namespace) -> None:
    for name, label in (
        (args.target_name, "target"),
        (args.install_name, "install"),
        (args.backup_name, "backup"),
    ):
        _validate_name(name, label)
    if len({args.target_name, args.install_name, args.backup_name}) != 3:
        fail("target, install, and backup basenames must differ")
    if args.old_state == "present" and not args.expected_old:
        fail("--expected-old is required for a present target")
    if args.old_state == "absent" and args.expected_old:
        fail("--expected-old is invalid for an absent target")

    parent_fd = _open_parent(
        args.parent, args.expected_parent_device, args.expected_parent_inode
    )
    previous_handlers = _install_signal_handlers()
    old_moved = False
    new_installed = False
    committed = False
    interrupted_signal: int | None = None
    transaction_error: BaseException | None = None

    try:
        _assert_parent_path(
            args.parent,
            parent_fd,
            args.expected_parent_device,
            args.expected_parent_inode,
        )
        if _entry_at(parent_fd, args.backup_name) is not None:
            raise SwapError(
                f"backup transaction path already exists: {args.backup_name}"
            )
        target_entry = _entry_at(parent_fd, args.target_name)
        if args.old_state == "present":
            if target_entry is None:
                raise SwapError("vendor target disappeared before commit")
            _assert_digest(
                parent_fd,
                args.target_name,
                args.expected_old,
                "vendor preimage",
            )
        elif target_entry is not None:
            raise SwapError("vendor target appeared before commit")
        _assert_digest(
            parent_fd,
            args.install_name,
            args.expected_new,
            "verified install stage",
        )

        _pause_for_test("before-swap")
        _assert_parent_path(
            args.parent,
            parent_fd,
            args.expected_parent_device,
            args.expected_parent_inode,
        )
        if args.old_state == "present":
            if _entry_at(parent_fd, args.target_name) is None:
                raise SwapError("vendor target disappeared before backup")
            _assert_digest(
                parent_fd,
                args.target_name,
                args.expected_old,
                "vendor preimage",
            )
            _rename_noreplace(
                parent_fd, args.target_name, args.backup_name
            )
            old_moved = True
            if _entry_at(parent_fd, args.target_name) is not None:
                raise SwapError("vendor target remained after backup rename")
            _assert_digest(
                parent_fd,
                args.backup_name,
                args.expected_old,
                "vendor backup",
            )
        elif _entry_at(parent_fd, args.target_name) is not None:
            raise SwapError("vendor target appeared before install")

        _pause_for_test("after-backup")
        _assert_parent_path(
            args.parent,
            parent_fd,
            args.expected_parent_device,
            args.expected_parent_inode,
        )
        _assert_digest(
            parent_fd,
            args.install_name,
            args.expected_new,
            "verified install stage",
        )
        if _entry_at(parent_fd, args.target_name) is not None:
            raise SwapError("vendor target appeared after backup")
        _inject("after-backup", parent_fd, args.install_name)

        _rename_noreplace(
            parent_fd, args.install_name, args.target_name
        )
        new_installed = True
        _assert_digest(
            parent_fd,
            args.target_name,
            args.expected_new,
            "installed vendor",
        )
        if old_moved:
            _assert_digest(
                parent_fd,
                args.backup_name,
                args.expected_old,
                "vendor backup",
            )

        _pause_for_test("after-install")
        _assert_parent_path(
            args.parent,
            parent_fd,
            args.expected_parent_device,
            args.expected_parent_inode,
        )
        _assert_digest(
            parent_fd,
            args.target_name,
            args.expected_new,
            "installed vendor",
        )
        _inject("after-install", parent_fd, args.install_name)
        committed = True
    except BaseException as error:  # rollback also covers an injected signal
        transaction_error = error
        if isinstance(error, SwapInterrupted):
            interrupted_signal = error.signum
    finally:
        if not committed:
            _ignore_transaction_signals()
            rollback_errors: list[str] = []
            try:
                if new_installed:
                    _assert_digest(
                        parent_fd,
                        args.target_name,
                        args.expected_new,
                        "installed vendor during rollback",
                    )
                    if _entry_at(parent_fd, args.install_name) is not None:
                        raise SwapError(
                            "rollback install destination already exists"
                        )
                    _rename_noreplace(
                        parent_fd, args.target_name, args.install_name
                    )
                    new_installed = False
                    _assert_digest(
                        parent_fd,
                        args.install_name,
                        args.expected_new,
                        "rolled-back install stage",
                    )
                if old_moved:
                    if _entry_at(parent_fd, args.target_name) is not None:
                        raise SwapError(
                            "rollback target destination already exists"
                        )
                    _assert_digest(
                        parent_fd,
                        args.backup_name,
                        args.expected_old,
                        "vendor backup during rollback",
                    )
                    _rename_noreplace(
                        parent_fd, args.backup_name, args.target_name
                    )
                    old_moved = False
                    _assert_digest(
                        parent_fd,
                        args.target_name,
                        args.expected_old,
                        "restored vendor",
                    )
            except BaseException as error:
                rollback_errors.append(str(error))

            if not rollback_errors:
                try:
                    if _entry_at(parent_fd, args.install_name) is not None:
                        _remove_tree_at(
                            parent_fd,
                            args.install_name,
                            args.expected_new,
                            "rolled-back install stage",
                        )
                except BaseException as error:
                    rollback_errors.append(str(error))

            if rollback_errors:
                print(
                    "error: Core vendor rollback incomplete; transaction "
                    f"paths preserved under {args.parent}",
                    file=sys.stderr,
                )
                for message in rollback_errors:
                    print(f"error: rollback detail: {message}", file=sys.stderr)
                transaction_error = transaction_error or SwapError(
                    "Core vendor rollback failed"
                )
            elif transaction_error is not None:
                print(
                    "error: Core vendor transaction failed; previous vendor "
                    "restored exactly",
                    file=sys.stderr,
                )

    if not committed:
        os.close(parent_fd)
        for signum, previous in previous_handlers.items():
            signal.signal(signum, previous)
        if transaction_error is not None:
            print(f"error: {transaction_error}", file=sys.stderr)
        if interrupted_signal is not None:
            raise SystemExit(128 + interrupted_signal)
        raise SystemExit(1)

    # The new target is committed.  From here until the verified old backup is
    # completely removed, catchable termination signals are intentionally
    # ignored.  This prevents a half-deleted recovery directory from becoming
    # an ambiguous orphan.
    _ignore_transaction_signals()
    try:
        _pause_for_test("before-cleanup")
        _inject("before-cleanup", parent_fd, args.install_name)
        if old_moved:
            _remove_tree_at(
                parent_fd,
                args.backup_name,
                args.expected_old,
                "committed vendor backup",
            )
        _assert_parent_path(
            args.parent,
            parent_fd,
            args.expected_parent_device,
            args.expected_parent_inode,
        )
        _assert_digest(
            parent_fd,
            args.target_name,
            args.expected_new,
            "committed vendor",
        )
    except BaseException as error:
        os.close(parent_fd)
        for signum, previous in previous_handlers.items():
            signal.signal(signum, previous)
        fail(
            "Core vendor committed, but verified backup cleanup/final "
            f"validation failed: {error}"
        )
    os.close(parent_fd)
    for signum, previous in previous_handlers.items():
        signal.signal(signum, previous)


def remove(args: argparse.Namespace) -> None:
    _validate_name(args.name, "cleanup")
    parent_fd = _open_parent(
        args.parent, args.expected_parent_device, args.expected_parent_inode
    )
    try:
        entry = _entry_at(parent_fd, args.name)
        if entry is not None:
            _remove_tree_at(
                parent_fd, args.name, args.expected_digest, "cleanup stage"
            )
    finally:
        os.close(parent_fd)


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    swap_parser = subparsers.add_parser("swap")
    swap_parser.add_argument("--parent", required=True, type=Path)
    swap_parser.add_argument("--target-name", required=True)
    swap_parser.add_argument("--install-name", required=True)
    swap_parser.add_argument("--backup-name", required=True)
    swap_parser.add_argument(
        "--old-state", required=True, choices=("present", "absent")
    )
    swap_parser.add_argument("--expected-old")
    swap_parser.add_argument("--expected-new", required=True)
    swap_parser.add_argument(
        "--expected-parent-device", required=True, type=int
    )
    swap_parser.add_argument(
        "--expected-parent-inode", required=True, type=int
    )

    remove_parser = subparsers.add_parser("remove")
    remove_parser.add_argument("--parent", required=True, type=Path)
    remove_parser.add_argument("--name", required=True)
    remove_parser.add_argument("--expected-digest", required=True)
    remove_parser.add_argument(
        "--expected-parent-device", required=True, type=int
    )
    remove_parser.add_argument(
        "--expected-parent-inode", required=True, type=int
    )

    for command in ("lock-acquire", "lock-release"):
        lock_parser = subparsers.add_parser(command)
        lock_parser.add_argument("--parent", required=True, type=Path)
        lock_parser.add_argument("--lock-name", required=True)
        lock_parser.add_argument("--pid", required=True, type=int)
        lock_parser.add_argument("--process-start", required=True)
        lock_parser.add_argument("--token", required=True)
        lock_parser.add_argument(
            "--expected-parent-device", required=True, type=int
        )
        lock_parser.add_argument(
            "--expected-parent-inode", required=True, type=int
        )

    args = parser.parse_args()
    try:
        if args.command == "swap":
            swap(args)
        elif args.command == "remove":
            remove(args)
        elif args.command == "lock-acquire":
            acquire_lock(args)
        else:
            release_lock(args)
    except SwapError as error:
        fail(str(error))


if __name__ == "__main__":
    main()
