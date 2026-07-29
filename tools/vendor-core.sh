#!/usr/bin/env bash
# Vendor a pinned, verified SCV Core export into the self-contained Codex plugin.
#
# Development-time network access is allowed only with --tag. Installed plugin
# runtime never calls this script and never downloads core.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_TARGET="$REPO_ROOT/plugins/scv/vendor/scv-core"
DEFAULT_PROFILE="$REPO_ROOT/plugins/scv/adapter/host-profile.env"
DEFAULT_REPOSITORY="https://github.com/wookiya1364/scv-core"

SOURCE=""
TAG=""
REPOSITORY="$DEFAULT_REPOSITORY"
TARGET="$DEFAULT_TARGET"
PROFILE="$DEFAULT_PROFILE"

usage() {
  cat <<'EOF'
Usage:
  tools/vendor-core.sh --source <local-scv-core> [options]
  tools/vendor-core.sh --tag <vX.Y.Z> [options]

Options:
  --source <path>       Local scv-core checkout or exported core bundle.
  --tag <tag>           Public GitHub release tag, for example v0.20.1.
  --repository <url>    Release repository (default: official scv-core).
  --target <path>       Vendor destination (default: plugins/scv/vendor/scv-core).
  --profile <path>      Codex host profile.
  -h, --help            Show this help.

Exactly one of --source or --tag is required.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      [[ $# -ge 2 ]] || { echo "error: --source requires a path" >&2; exit 2; }
      SOURCE="$2"
      shift 2
      ;;
    --tag)
      [[ $# -ge 2 ]] || { echo "error: --tag requires a value" >&2; exit 2; }
      TAG="$2"
      shift 2
      ;;
    --repository)
      [[ $# -ge 2 ]] || { echo "error: --repository requires a URL" >&2; exit 2; }
      REPOSITORY="${2%/}"
      REPOSITORY="${REPOSITORY%.git}"
      shift 2
      ;;
    --target)
      [[ $# -ge 2 ]] || { echo "error: --target requires a path" >&2; exit 2; }
      TARGET="$2"
      shift 2
      ;;
    --profile)
      [[ $# -ge 2 ]] || { echo "error: --profile requires a path" >&2; exit 2; }
      PROFILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -n "$SOURCE" && -n "$TAG" ]] || [[ -z "$SOURCE" && -z "$TAG" ]]; then
  echo "error: choose exactly one of --source or --tag" >&2
  exit 2
fi

[[ -f "$PROFILE" ]] || {
  echo "error: Codex host profile not found: $PROFILE" >&2
  exit 1
}

TARGET_INFO="$(
  python3 - "$TARGET" "$DEFAULT_TARGET" "$REPO_ROOT" \
    "${SCV_VENDOR_ALLOW_CUSTOM_TARGET:-0}" <<'PY'
import os
import sys
from pathlib import Path

raw_target = Path(sys.argv[1]).expanduser()
default = Path(sys.argv[2]).resolve(strict=False)
repo = Path(sys.argv[3]).resolve()
allow_custom = sys.argv[4] == "1"
if not raw_target.is_absolute():
    raw_target = Path.cwd() / raw_target
if raw_target.is_symlink():
    raise SystemExit(f"error: refusing symlink vendor target: {raw_target}")
target = raw_target.resolve(strict=False)
plugin = (repo / "plugins/scv").resolve()
forbidden = {Path("/").resolve(), repo, plugin}
home = os.environ.get("HOME")
if home:
    forbidden.add(Path(home).resolve())
if target in forbidden:
    raise SystemExit(f"error: refusing unsafe vendor target: {target}")
if target != default and not allow_custom:
    raise SystemExit(
        "error: custom vendor targets require "
        "SCV_VENDOR_ALLOW_CUSTOM_TARGET=1"
    )
name = target.name
if (
    not name
    or name in {".", ".."}
    or any(character not in
           "abcdefghijklmnopqrstuvwxyz"
           "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
           "0123456789._-" for character in name)
):
    raise SystemExit(f"error: unsafe vendor target basename: {name!r}")
print(target)
print("default" if target == default else "custom")
PY
)"
TARGET="$(printf '%s\n' "$TARGET_INFO" | sed -n '1p')"
TARGET_KIND="$(printf '%s\n' "$TARGET_INFO" | sed -n '2p')"
[[ -n "$TARGET" && -n "$TARGET_KIND" ]] || {
  echo "error: failed to resolve vendor target" >&2
  exit 1
}
LEGACY_DECKUI="$REPO_ROOT/plugins/scv/DeckUI"
if [[ -n "${SCV_VENDOR_TEST_LEGACY_DECKUI:-}" ]]; then
  [[ "$TARGET_KIND" == "custom" ]] || {
    echo "error: legacy DeckUI test override requires a custom target" >&2
    exit 1
  }
  LEGACY_DECKUI="$SCV_VENDOR_TEST_LEGACY_DECKUI"
fi

TARGET_PARENT="$(dirname "$TARGET")"
TARGET_NAME="$(basename "$TARGET")"
mkdir -p "$TARGET_PARENT"
TARGET_PARENT="$(cd "$TARGET_PARENT" && pwd -P)"
TARGET="$TARGET_PARENT/$TARGET_NAME"
read -r PARENT_DEVICE PARENT_INODE < <(
  python3 - "$TARGET_PARENT" <<'PY'
import os
import stat
import sys
from pathlib import Path

path = Path(sys.argv[1])
flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
flags |= getattr(os, "O_NOFOLLOW", 0)
descriptor = os.open(path, flags)
try:
    opened = os.fstat(descriptor)
    entry = path.lstat()
    if (
        not stat.S_ISDIR(entry.st_mode)
        or entry.st_dev != opened.st_dev
        or entry.st_ino != opened.st_ino
    ):
        raise SystemExit(
            f"error: vendor parent identity or type changed: {path}"
        )
    print(opened.st_dev, opened.st_ino)
finally:
    os.close(descriptor)
PY
)

path_exists() {
  [[ -e "$1" || -L "$1" ]]
}

if path_exists "$TARGET"; then
  [[ -d "$TARGET" && ! -L "$TARGET" ]] || {
    echo "error: existing vendor target is not an ordinary directory: $TARGET" >&2
    exit 1
  }
  [[ -f "$TARGET/core.lock.json" && ! -L "$TARGET/core.lock.json" ]] || {
    echo "error: existing vendor target is not a locked SCV Core payload: $TARGET" >&2
    exit 1
  }
fi

process_start_id() {
  python3 - "$1" <<'PY'
import hashlib
import subprocess
import sys
from pathlib import Path

pid = sys.argv[1]
proc = Path("/proc") / pid / "stat"
try:
    print("proc-" + proc.read_text(encoding="utf-8").rsplit(")", 1)[1].split()[19])
except (IndexError, OSError):
    try:
        value = subprocess.check_output(
            ["ps", "-o", "lstart=", "-p", pid],
            stderr=subprocess.DEVNULL,
        ).strip()
    except (OSError, subprocess.CalledProcessError):
        value = b""
    if value:
        print("ps-" + hashlib.sha256(value).hexdigest())
    else:
        print("unknown")
PY
}

LOCK_PATH="$TARGET_PARENT/.${TARGET_NAME}.scv-vendor.lock"
LOCK_NAME="$(basename "$LOCK_PATH")"
LOCK_TOKEN="$(python3 -B -c 'import secrets; print(secrets.token_hex(24))')"
LOCK_PROCESS_START="$(process_start_id "$$")"
LOCK_OWNED=0

acquire_vendor_lock() {
  python3 -B "$SCRIPT_DIR/atomic_core_swap.py" lock-acquire \
    --parent "$TARGET_PARENT" \
    --lock-name "$LOCK_NAME" \
    --pid "$$" \
    --process-start "$LOCK_PROCESS_START" \
    --token "$LOCK_TOKEN" \
    --expected-parent-device "$PARENT_DEVICE" \
    --expected-parent-inode "$PARENT_INODE"
  LOCK_OWNED=1
}

release_vendor_lock() {
  (( LOCK_OWNED )) || return 0
  python3 -B "$SCRIPT_DIR/atomic_core_swap.py" lock-release \
    --parent "$TARGET_PARENT" \
    --lock-name "$LOCK_NAME" \
    --pid "$$" \
    --process-start "$LOCK_PROCESS_START" \
    --token "$LOCK_TOKEN" \
    --expected-parent-device "$PARENT_DEVICE" \
    --expected-parent-inode "$PARENT_INODE" || return 1
  LOCK_OWNED=0
}

trap 'release_vendor_lock || true' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
acquire_vendor_lock

for orphan in \
  "$TARGET_PARENT"/."$TARGET_NAME".install.* \
  "$TARGET_PARENT"/."$TARGET_NAME".previous.* \
  "$TARGET_PARENT"/."$TARGET_NAME".scv-vendor.stale-*; do
  if path_exists "$orphan"; then
    echo "error: unfinished Core vendor transaction requires recovery: $orphan" >&2
    release_vendor_lock || true
    exit 1
  fi
done

if [[ "${SCV_VENDOR_TEST_HOLD_LOCK:-0}" == "1" ]]; then
  [[ -n "${SCV_VENDOR_TEST_READY_FILE:-}" &&
     -n "${SCV_VENDOR_TEST_CONTINUE_FILE:-}" ]] || {
    echo "error: lock test hook requires ready and continue files" >&2
    release_vendor_lock || true
    exit 1
  }
  printf 'ready\n' >"$SCV_VENDOR_TEST_READY_FILE"
  while [[ ! -e "$SCV_VENDOR_TEST_CONTINUE_FILE" ]]; do
    sleep 0.02
  done
fi

TASK_TMP="$(mktemp -d "${TMPDIR:-/tmp}/scv-codex-vendor.XXXXXX")"
INSTALL_STAGE=""
INSTALL_STAGE_DIGEST=""
cleanup() {
  local rc=$? cleanup_rc=0
  trap - EXIT
  trap '' HUP INT TERM
  if [[ -n "$INSTALL_STAGE" && -n "$INSTALL_STAGE_DIGEST" ]] &&
     path_exists "$INSTALL_STAGE"; then
    python3 -B "$SCRIPT_DIR/atomic_core_swap.py" remove \
      --parent "$TARGET_PARENT" \
      --name "$(basename "$INSTALL_STAGE")" \
      --expected-digest "$INSTALL_STAGE_DIGEST" \
      --expected-parent-device "$PARENT_DEVICE" \
      --expected-parent-inode "$PARENT_INODE" || cleanup_rc=1
  fi
  rm -rf "$TASK_TMP"
  release_vendor_lock || cleanup_rc=1
  if [[ "$rc" -eq 0 && "$cleanup_rc" -ne 0 ]]; then
    rc="$cleanup_rc"
  fi
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

CACHE_BASE="$(
  python3 - \
    "${SCV_DECK_CACHE_DIR:-}" \
    "${XDG_CACHE_HOME:-}" \
    "${HOME:-}" \
    "$REPO_ROOT" \
    "$TARGET" \
    "$LEGACY_DECKUI" \
    "$TASK_TMP" <<'PY'
import os
import sys
from pathlib import Path

explicit, xdg, home, repo_arg, target_arg, legacy_arg, task_arg = sys.argv[1:]
if explicit:
    raw = Path(explicit).expanduser()
elif xdg:
    raw = Path(xdg).expanduser() / "scv/deckui"
elif home:
    raw = Path(home).expanduser() / ".cache/scv/deckui"
else:
    raise SystemExit(
        "error: set SCV_DECK_CACHE_DIR, XDG_CACHE_HOME, or HOME"
    )
if not raw.is_absolute():
    raise SystemExit("error: SCV Deck cache base must be an absolute path")
if raw.is_symlink():
    raise SystemExit(f"error: SCV Deck cache base must not be a symlink: {raw}")
base = raw.resolve(strict=False)

def overlaps(first: Path, second: Path) -> bool:
    try:
        first.relative_to(second)
        return True
    except ValueError:
        pass
    try:
        second.relative_to(first)
        return True
    except ValueError:
        return False

for label, value in (
    ("repository", repo_arg),
    ("vendor target", target_arg),
    ("legacy DeckUI", legacy_arg),
    ("vendor temporary directory", task_arg),
):
    forbidden = Path(value).resolve(strict=False)
    if overlaps(base, forbidden):
        raise SystemExit(
            f"error: SCV Deck cache overlaps the {label}: {base}"
        )
print(base)
PY
)"
export SCV_DECK_CACHE_DIR="$CACHE_BASE"

portable_sha256() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  else
    echo "error: sha256sum or shasum is required" >&2
    return 1
  fi
}

OLD_STATE="absent"
OLD_DIGEST=""
if path_exists "$TARGET"; then
  OLD_STATE="present"
  OLD_DIGEST="$(
    python3 "$SCRIPT_DIR/core_tree_state.py" snapshot --root "$TARGET"
  )"
  IMMUTABLE_PREIMAGE="$TASK_TMP/existing-immutable"
  python3 "$SCRIPT_DIR/core_tree_state.py" sanitize \
    --root "$TARGET" \
    --output "$IMMUTABLE_PREIMAGE"
  python3 "$SCRIPT_DIR/validate-core-tree.py" --root "$IMMUTABLE_PREIMAGE"
  [[ -x "$IMMUTABLE_PREIMAGE/tools/verify-core.sh" ]] || {
    echo "error: existing vendor lacks an executable Core verifier" >&2
    exit 1
  }
  bash "$IMMUTABLE_PREIMAGE/tools/verify-core.sh" \
    --root "$IMMUTABLE_PREIMAGE"
  OLD_AFTER_SANITIZE="$(
    python3 "$SCRIPT_DIR/core_tree_state.py" snapshot --root "$TARGET"
  )"
  [[ "$OLD_AFTER_SANITIZE" == "$OLD_DIGEST" ]] || {
    echo "error: existing vendor changed while validating its preimage" >&2
    exit 1
  }
fi

LEGACY_RUNTIME="no"
LEGACY_DIGEST=""
if path_exists "$LEGACY_DECKUI"; then
  [[ -d "$LEGACY_DECKUI" && ! -L "$LEGACY_DECKUI" ]] || {
    echo "error: legacy plugin-root DeckUI is not an ordinary directory" >&2
    exit 1
  }
  LEGACY_DIGEST="$(
    python3 "$SCRIPT_DIR/core_tree_state.py" snapshot \
      --root "$LEGACY_DECKUI"
  )"
fi

pause_vendor_test() {
  local point=$1 count=0
  [[ "${SCV_VENDOR_TEST_PAUSE_AT:-}" == "$point" ]] || return 0
  [[ -n "${SCV_VENDOR_TEST_READY_FILE:-}" &&
     -n "${SCV_VENDOR_TEST_CONTINUE_FILE:-}" ]] || {
    echo "error: test pause requires ready and continue files" >&2
    return 1
  }
  printf '%s\n' "$point" >"$SCV_VENDOR_TEST_READY_FILE"
  while [[ ! -e "$SCV_VENDOR_TEST_CONTINUE_FILE" &&
           "$count" -lt 1000 ]]; do
    sleep 0.02
    count=$((count + 1))
  done
  [[ -e "$SCV_VENDOR_TEST_CONTINUE_FILE" ]] || {
    echo "error: timed out at vendor test pause: $point" >&2
    return 1
  }
}

pause_vendor_test "before-runtime-export"

EXISTING_RUNTIME="no"
if [[ "$OLD_STATE" == "present" ]]; then
  EXISTING_RUNTIME="$(
    python3 "$SCRIPT_DIR/core_tree_state.py" export-runtime \
      --root "$TARGET" \
      --output "$TASK_TMP/existing-deck-runtime" \
      --expected-digest "$OLD_DIGEST"
  )"
fi
if [[ -n "$LEGACY_DIGEST" ]]; then
  LEGACY_RUNTIME="$(
    python3 "$SCRIPT_DIR/core_tree_state.py" export-runtime \
      --deckui-root "$LEGACY_DECKUI" \
      --output "$TASK_TMP/legacy-deck-runtime" \
      --expected-digest "$LEGACY_DIGEST"
  )"
fi

resolve_export_root() {
  local search_root="$1"
  local candidate

  if [[ -f "$search_root/core-manifest.json" && -d "$search_root/core" ]]; then
    printf '%s\n' "$search_root"
    return 0
  fi

  candidate="$(
    find "$search_root" -mindepth 1 -maxdepth 3 -type f \
      -name core-manifest.json -print -quit
  )"
  [[ -n "$candidate" ]] || {
    echo "error: core-manifest.json not found under $search_root" >&2
    return 1
  }
  dirname "$candidate"
}

CORE_INPUT=""
ACTUAL_SHA=""
if [[ -n "$SOURCE" ]]; then
  [[ -d "$SOURCE" ]] || {
    echo "error: local scv-core source does not exist: $SOURCE" >&2
    exit 1
  }
  SOURCE="$(cd "$SOURCE" && pwd)"

  if [[ -x "$SOURCE/tools/export-core.sh" ]]; then
    EXPORT_DIR="$TASK_TMP/export"
    bash "$SOURCE/tools/export-core.sh" --output "$EXPORT_DIR"
    CORE_INPUT="$(resolve_export_root "$EXPORT_DIR")"
  else
    CORE_INPUT="$(resolve_export_root "$SOURCE")"
  fi
else
  command -v curl >/dev/null 2>&1 || {
    echo "error: curl is required for --tag" >&2
    exit 1
  }
  RELEASE_TAG="$TAG"
  [[ "$RELEASE_TAG" == v* ]] || RELEASE_TAG="v$RELEASE_TAG"
  RELEASE_VERSION="${RELEASE_TAG#v}"
  [[ "$RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "error: release tag must be vX.Y.Z or X.Y.Z" >&2
    exit 2
  }
  ARCHIVE_NAME="scv-core-v${RELEASE_VERSION}.tar.gz"
  ARCHIVE="$TASK_TMP/$ARCHIVE_NAME"
  CHECKSUM="$TASK_TMP/$ARCHIVE_NAME.sha256"
  RELEASE_BASE="$REPOSITORY/releases/download/$RELEASE_TAG"

  echo "Downloading $RELEASE_BASE/$ARCHIVE_NAME"
  curl --fail --location --silent --show-error \
    "$RELEASE_BASE/$ARCHIVE_NAME" --output "$ARCHIVE"
  curl --fail --location --silent --show-error \
    "$RELEASE_BASE/$ARCHIVE_NAME.sha256" --output "$CHECKSUM"

  EXPECTED_SHA="$(
    awk 'NF { print $1; exit }' "$CHECKSUM" | tr '[:upper:]' '[:lower:]'
  )"
  ACTUAL_SHA="$(portable_sha256 "$ARCHIVE")"
  [[ "$EXPECTED_SHA" =~ ^[0-9a-f]{64}$ ]] || {
    echo "error: invalid release checksum file" >&2
    exit 1
  }
  [[ "$ACTUAL_SHA" == "$EXPECTED_SHA" ]] || {
    echo "error: release archive checksum mismatch" >&2
    exit 1
  }

  ARCHIVE_ROOT="scv-core-v${RELEASE_VERSION}"
  EXTRACT_DIR="$TASK_TMP/release"
  mkdir -p "$EXTRACT_DIR"
  python3 - "$ARCHIVE" "$ARCHIVE_ROOT" <<'PY'
import sys
import tarfile

archive = sys.argv[1]
expected_root = sys.argv[2]
seen = set()

with tarfile.open(archive, "r:gz") as bundle:
    for member in bundle.getmembers():
        raw = member.name
        normalized = raw.rstrip("/")
        parts = normalized.split("/")
        if (
            not normalized
            or raw.startswith("/")
            or any(part in {"", ".", ".."} for part in parts)
            or parts[0] != expected_root
        ):
            raise SystemExit(f"error: unsafe release archive path: {raw}")
        if normalized in seen:
            raise SystemExit(f"error: duplicate release archive path: {raw}")
        seen.add(normalized)
        if not (member.isdir() or member.isreg()):
            raise SystemExit(
                f"error: release archive contains a link or special file: {raw}"
            )

if expected_root not in seen:
    raise SystemExit(
        f"error: release archive lacks expected top-level directory: "
        f"{expected_root}"
    )
PY
  tar -xzf "$ARCHIVE" -C "$EXTRACT_DIR"
  CORE_INPUT="$(resolve_export_root "$EXTRACT_DIR")"
fi

for source_contract_path in \
  VERSION CORE_API TEMPLATE_VERSION SOURCE_COMMIT SOURCE_DATE SOURCE_INFO \
  core-manifest.json SHA256SUMS; do
  [[ -f "$CORE_INPUT/$source_contract_path" ]] || {
    echo "error: source core contract path missing: $source_contract_path" >&2
    exit 1
  }
done
SOURCE_VERSION="$(tr -d '[:space:]' <"$CORE_INPUT/VERSION")"
SOURCE_CORE_API="$(tr -d '[:space:]' <"$CORE_INPUT/CORE_API")"
SOURCE_TEMPLATE_VERSION="$(tr -d '[:space:]' <"$CORE_INPUT/TEMPLATE_VERSION")"
SOURCE_COMMIT="$(tr -d '[:space:]' <"$CORE_INPUT/SOURCE_COMMIT")"
SOURCE_DATE="$(tr -d '[:space:]' <"$CORE_INPUT/SOURCE_DATE")"
SOURCE_REPOSITORY="$(
  sed -n 's/^source_repository:[[:space:]]*//p' \
    "$CORE_INPUT/SOURCE_INFO" | head -1
)"
SOURCE_MANIFEST_SHA="$(portable_sha256 "$CORE_INPUT/core-manifest.json")"
SOURCE_PAYLOAD_SHA="$(portable_sha256 "$CORE_INPUT/SHA256SUMS")"

python3 - \
  "$CORE_INPUT/core-manifest.json" \
  "$SOURCE_VERSION" \
  "$SOURCE_CORE_API" \
  "$SOURCE_TEMPLATE_VERSION" \
  "$SOURCE_COMMIT" \
  "$SOURCE_DATE" \
  "$SOURCE_REPOSITORY" \
  "${RELEASE_VERSION:-}" <<'PY'
import json
import re
import sys
from pathlib import Path

(
    manifest_path,
    version,
    core_api,
    template_version,
    source_commit,
    source_date,
    source_repository,
    release_version,
) = sys.argv[1:]

if not re.fullmatch(r"\d+\.\d+\.\d+", version):
    raise SystemExit(f"error: invalid source VERSION: {version}")
if core_api != "1":
    raise SystemExit(f"error: unsupported source CORE_API: {core_api}")
if not re.fullmatch(r"\d+\.\d+\.\d+", template_version):
    raise SystemExit(
        f"error: invalid source TEMPLATE_VERSION: {template_version}"
    )
if not re.fullmatch(r"[0-9a-f]{40}", source_commit):
    raise SystemExit(f"error: invalid source commit: {source_commit}")
if not source_date or not source_repository:
    raise SystemExit("error: source date/repository provenance is incomplete")
if release_version and version != release_version:
    raise SystemExit(
        f"error: release tag version {release_version} does not match "
        f"payload VERSION {version}"
    )

manifest = json.loads(Path(manifest_path).read_text())
expected = {
    "schema_version": 1,
    "name": "scv-core",
    "version": version,
    "core_api": int(core_api),
    "template_version": template_version,
    "source_repository": source_repository,
    "source_commit": source_commit,
}
for key, value in expected.items():
    if manifest.get(key) != value:
        raise SystemExit(
            f"error: source manifest {key} does not match source contract"
        )
PY

VENDOR_TOOL=""
if [[ -x "$CORE_INPUT/tools/vendor-core.sh" ]]; then
  VENDOR_TOOL="$CORE_INPUT/tools/vendor-core.sh"
elif [[ -n "$SOURCE" && -x "$SOURCE/tools/vendor-core.sh" ]]; then
  VENDOR_TOOL="$SOURCE/tools/vendor-core.sh"
fi
[[ -n "$VENDOR_TOOL" ]] || {
  echo "error: the selected core does not provide tools/vendor-core.sh" >&2
  exit 1
}
if [[ -x "$CORE_INPUT/tools/verify-core.sh" ]]; then
  bash "$CORE_INPUT/tools/verify-core.sh" --root "$CORE_INPUT"
else
  echo "error: the selected core does not provide tools/verify-core.sh" >&2
  exit 1
fi

STAGED_TARGET="$TASK_TMP/materialized"
vendor_args=(
  --source "$CORE_INPUT" \
  --target "$STAGED_TARGET" \
  --profile "$PROFILE"
)
if [[ -n "$ACTUAL_SHA" ]]; then
  vendor_args+=(--artifact-sha256 "$ACTUAL_SHA")
fi
bash "$VENDOR_TOOL" "${vendor_args[@]}"

VERIFY_TOOL=""
if [[ -x "$STAGED_TARGET/tools/verify-core.sh" ]]; then
  VERIFY_TOOL="$STAGED_TARGET/tools/verify-core.sh"
elif [[ -x "$CORE_INPUT/tools/verify-core.sh" ]]; then
  VERIFY_TOOL="$CORE_INPUT/tools/verify-core.sh"
fi
[[ -n "$VERIFY_TOOL" ]] || {
  echo "error: vendored core does not provide tools/verify-core.sh" >&2
  exit 1
}
bash "$VERIFY_TOOL" --root "$STAGED_TARGET"

python3 - \
  "$STAGED_TARGET" \
  "$SOURCE_VERSION" \
  "$SOURCE_CORE_API" \
  "$SOURCE_TEMPLATE_VERSION" \
  "$SOURCE_COMMIT" \
  "$SOURCE_DATE" \
  "$SOURCE_REPOSITORY" \
  "$SOURCE_MANIFEST_SHA" \
  "$SOURCE_PAYLOAD_SHA" \
  "$ACTUAL_SHA" <<'PY'
import hashlib
import json
import re
import sys
from pathlib import Path

(
    root_arg,
    source_version,
    source_core_api,
    source_template_version,
    source_commit,
    source_date,
    source_repository,
    source_manifest_sha,
    source_payload_sha,
    artifact_sha,
) = sys.argv[1:]
root = Path(root_arg)
lock = json.loads((root / "core.lock.json").read_text())
manifest = json.loads((root / "core-manifest.json").read_text())

def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

expected_artifact = artifact_sha or None
expected_lock = {
    "schema_version": 1,
    "core_version": source_version,
    "core_api": int(source_core_api),
    "template_version": source_template_version,
    "source_repository": source_repository,
    "source_commit": source_commit,
    "source_manifest_sha256": source_manifest_sha,
    "source_payload_sha256": source_payload_sha,
    "manifest_sha256": sha256(root / "core-manifest.json"),
    "payload_sha256": sha256(root / "SHA256SUMS"),
    "artifact_sha256": expected_artifact,
    "vendored_at": source_date,
}
for key, value in expected_lock.items():
    if lock.get(key) != value:
        raise SystemExit(
            f"error: vendored lock {key} does not match verified source"
        )

expected_manifest = {
    "schema_version": 1,
    "name": "scv-core",
    "version": source_version,
    "core_api": int(source_core_api),
    "template_version": source_template_version,
    "source_repository": source_repository,
    "source_commit": source_commit,
}
for key, value in expected_manifest.items():
    if manifest.get(key) != value:
        raise SystemExit(
            f"error: materialized manifest {key} does not match verified source"
        )

for key in (
    "source_manifest_sha256",
    "source_payload_sha256",
    "manifest_sha256",
    "payload_sha256",
):
    if not re.fullmatch(r"[0-9a-f]{64}", lock[key]):
        raise SystemExit(f"error: vendored lock {key} is not a SHA-256")
PY

python3 "$SCRIPT_DIR/validate-core-tree.py" --root "$STAGED_TARGET"

STAGED_DIGEST_BEFORE_MIGRATION="$(
  python3 "$SCRIPT_DIR/core_tree_state.py" snapshot --root "$STAGED_TARGET"
)"
DECK_RUNTIME_HELPER="$STAGED_TARGET/core/scripts/deck-runtime.sh"
[[ -x "$DECK_RUNTIME_HELPER" ]] || {
  echo "error: candidate Core lacks an executable Deck runtime helper" >&2
  exit 1
}

if [[ "$EXISTING_RUNTIME" == "yes" ]]; then
  bash "$DECK_RUNTIME_HELPER" migrate \
    --from "$TASK_TMP/existing-deck-runtime" >/dev/null
fi
if [[ "$LEGACY_RUNTIME" == "yes" ]]; then
  bash "$DECK_RUNTIME_HELPER" migrate \
    --from "$TASK_TMP/legacy-deck-runtime" \
    --reuse-existing >/dev/null
fi

STAGED_DIGEST_AFTER_MIGRATION="$(
  python3 "$SCRIPT_DIR/core_tree_state.py" snapshot --root "$STAGED_TARGET"
)"
[[ "$STAGED_DIGEST_AFTER_MIGRATION" == "$STAGED_DIGEST_BEFORE_MIGRATION" ]] || {
  echo "error: candidate Core changed during Deck runtime migration" >&2
  exit 1
}
INSTALL_STAGE="$(
  mktemp -d "$TARGET_PARENT/.${TARGET_NAME}.install.XXXXXX"
)"
if command -v rsync >/dev/null 2>&1; then
  rsync -a "$STAGED_TARGET/" "$INSTALL_STAGE/"
else
  cp -R -p "$STAGED_TARGET/." "$INSTALL_STAGE/"
fi
python3 - "$STAGED_TARGET" "$INSTALL_STAGE" <<'PY'
import os
import stat
import sys
from pathlib import Path

source = Path(sys.argv[1]).lstat()
destination = Path(sys.argv[2])
if not stat.S_ISDIR(source.st_mode):
    raise SystemExit("error: staged Core root is not an ordinary directory")
os.chmod(destination, stat.S_IMODE(source.st_mode))
PY
python3 "$SCRIPT_DIR/validate-core-tree.py" --root "$INSTALL_STAGE"
bash "$INSTALL_STAGE/tools/verify-core.sh" --root "$INSTALL_STAGE"
INSTALL_STAGE_DIGEST="$(
  python3 "$SCRIPT_DIR/core_tree_state.py" snapshot --root "$INSTALL_STAGE"
)"

BACKUP_PATH="$(
  mktemp -d "$TARGET_PARENT/.${TARGET_NAME}.previous.XXXXXX"
)"
rmdir "$BACKUP_PATH"
BACKUP_NAME="$(basename "$BACKUP_PATH")"
INSTALL_NAME="$(basename "$INSTALL_STAGE")"

if [[ "${SCV_VENDOR_TEST_FAIL_INSTALL:-0}" == "1" &&
      -z "${SCV_VENDOR_TEST_FAILPOINT:-}" ]]; then
  export SCV_VENDOR_TEST_FAILPOINT="after-backup"
fi

swap_args=(
  swap
  --parent "$TARGET_PARENT"
  --target-name "$TARGET_NAME"
  --install-name "$INSTALL_NAME"
  --backup-name "$BACKUP_NAME"
  --old-state "$OLD_STATE"
  --expected-new "$INSTALL_STAGE_DIGEST"
  --expected-parent-device "$PARENT_DEVICE"
  --expected-parent-inode "$PARENT_INODE"
)
if [[ "$OLD_STATE" == "present" ]]; then
  swap_args+=(--expected-old "$OLD_DIGEST")
fi
trap '' HUP INT TERM
set +e
python3 -B "$SCRIPT_DIR/atomic_core_swap.py" "${swap_args[@]}"
swap_rc=$?
set -e
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
if [[ "$swap_rc" -ne 0 ]]; then
  exit "$swap_rc"
fi
INSTALL_STAGE=""
INSTALL_STAGE_DIGEST=""

if [[ ! -d "$TARGET" ]]; then
  echo "error: failed to replace $TARGET" >&2
  exit 1
fi
python3 "$SCRIPT_DIR/validate-core-tree.py" --root "$TARGET"
bash "$TARGET/tools/verify-core.sh" --root "$TARGET"

echo "SCV Core vendored successfully"
echo "TARGET: $TARGET"
echo "CORE_VERSION: $(tr -d '[:space:]' < "$TARGET/VERSION")"
echo "CORE_API: $(tr -d '[:space:]' < "$TARGET/CORE_API")"
echo "TEMPLATE_VERSION: $(tr -d '[:space:]' < "$TARGET/TEMPLATE_VERSION")"
