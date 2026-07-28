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

TARGET="$(
  python3 - "$TARGET" "$REPO_ROOT" <<'PY'
import os
import sys
from pathlib import Path

raw_target = Path(sys.argv[1]).expanduser()
if raw_target.is_symlink():
    raise SystemExit(f"error: refusing symlink vendor target: {raw_target}")
target = raw_target.resolve(strict=False)
repo = Path(sys.argv[2]).resolve()
plugin = (repo / "plugins/scv").resolve()
forbidden = {Path("/").resolve(), repo, plugin}
home = os.environ.get("HOME")
if home:
    forbidden.add(Path(home).resolve())
if target in forbidden:
    raise SystemExit(f"error: refusing unsafe vendor target: {target}")
if target.exists():
    if not target.is_dir() or not (target / "core.lock.json").is_file():
        raise SystemExit(
            "error: existing vendor target is not a locked SCV Core payload: "
            f"{target}"
        )
print(target)
PY
)"

TASK_TMP="$(mktemp -d "${TMPDIR:-/tmp}/scv-codex-vendor.XXXXXX")"
INSTALL_STAGE=""
BACKUP=""
cleanup() {
  local rc=$?
  trap - EXIT
  if [[ -n "$BACKUP" && -e "$BACKUP" && ! -e "$TARGET" ]]; then
    mv "$BACKUP" "$TARGET" || {
      echo "error: failed to restore previous vendor from $BACKUP" >&2
    }
  fi
  if [[ -n "$INSTALL_STAGE" && -e "$INSTALL_STAGE" ]]; then
    rm -rf "$INSTALL_STAGE"
  fi
  rm -rf "$TASK_TMP"
  exit "$rc"
}
trap cleanup EXIT

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

TARGET_PARENT="$(dirname "$TARGET")"
TARGET_NAME="$(basename "$TARGET")"
mkdir -p "$TARGET_PARENT"
INSTALL_STAGE="$(
  mktemp -d "$TARGET_PARENT/.${TARGET_NAME}.install.XXXXXX"
)"
if command -v rsync >/dev/null 2>&1; then
  rsync -a "$STAGED_TARGET/" "$INSTALL_STAGE/"
else
  cp -R -p "$STAGED_TARGET/." "$INSTALL_STAGE/"
fi
python3 "$SCRIPT_DIR/validate-core-tree.py" --root "$INSTALL_STAGE"
bash "$INSTALL_STAGE/tools/verify-core.sh" --root "$INSTALL_STAGE"

if [[ -e "$TARGET" ]]; then
  BACKUP="$(
    mktemp -d "$TARGET_PARENT/.${TARGET_NAME}.previous.XXXXXX"
  )"
  rmdir "$BACKUP"
  mv "$TARGET" "$BACKUP"
fi

install_rc=0
if [[ "${SCV_VENDOR_TEST_FAIL_INSTALL:-0}" == "1" ]]; then
  install_rc=97
else
  if mv "$INSTALL_STAGE" "$TARGET"; then
    INSTALL_STAGE=""
  else
    install_rc=$?
  fi
fi
if [[ "$install_rc" -ne 0 ]]; then
  if [[ -n "$BACKUP" && -e "$BACKUP" ]]; then
    mv "$BACKUP" "$TARGET"
    BACKUP=""
  fi
  echo "error: failed to install verified core; previous vendor restored" >&2
  exit "$install_rc"
fi

if [[ -n "$BACKUP" && -e "$BACKUP" ]]; then
  if rm -rf "$BACKUP"; then
    BACKUP=""
  else
    echo "warning: installed core but could not remove backup: $BACKUP" >&2
  fi
fi

if [[ ! -d "$TARGET" ]]; then
  echo "error: failed to replace $TARGET" >&2
  exit 1
fi

echo "SCV Core vendored successfully"
echo "TARGET: $TARGET"
echo "CORE_VERSION: $(tr -d '[:space:]' < "$TARGET/VERSION")"
echo "CORE_API: $(tr -d '[:space:]' < "$TARGET/CORE_API")"
echo "TEMPLATE_VERSION: $(tr -d '[:space:]' < "$TARGET/TEMPLATE_VERSION")"
