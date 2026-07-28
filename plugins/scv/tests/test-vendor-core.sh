#!/usr/bin/env bash
# Exercise the wrapper's release-download checksum and artifact lock contract.

set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"
VENDOR_TOOL="$REPO_ROOT/tools/vendor-core.sh"
TREE_VALIDATOR="$REPO_ROOT/tools/validate-core-tree.py"
SOURCE_VENDOR="$PLUGIN_ROOT/vendor/scv-core"

PASS=0
FAIL=0

ok() {
  echo "  ✓ $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "  ✖ FAIL: $1"
  FAIL=$((FAIL + 1))
}

portable_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

tree_snapshot() {
  python3 - "$1" <<'PY'
import hashlib
import os
import stat
import sys
from pathlib import Path

root = Path(sys.argv[1])
digest = hashlib.sha256()
for path in sorted(root.rglob("*")):
    relative = path.relative_to(root).as_posix()
    mode = path.lstat().st_mode
    if stat.S_ISLNK(mode):
        kind = b"L"
        payload = os.readlink(path).encode()
    elif stat.S_ISDIR(mode):
        kind = b"D"
        payload = b""
    elif stat.S_ISREG(mode):
        kind = b"F"
        payload = path.read_bytes()
    else:
        kind = b"O"
        payload = b""
    digest.update(kind + b"\0" + relative.encode() + b"\0" + payload + b"\0")
print(digest.hexdigest())
PY
}

make_malicious_archive() {
  local kind="$1"
  local source_archive="$2"
  local output_archive="$3"
  local archive_root="$4"

  python3 - "$kind" "$source_archive" "$output_archive" "$archive_root" <<'PY'
import sys
import tarfile

kind, source_path, output_path, archive_root = sys.argv[1:]
with tarfile.open(source_path, "r:gz") as source:
    with tarfile.open(output_path, "w:gz") as output:
        for member in source.getmembers():
            if member.isfile():
                with source.extractfile(member) as payload:
                    output.addfile(member, payload)
            else:
                output.addfile(member)

        injected = tarfile.TarInfo(
            f"{archive_root}/core/unsafe-{kind}"
        )
        if kind == "symlink":
            injected.type = tarfile.SYMTYPE
            injected.linkname = "../VERSION"
        elif kind == "hardlink":
            injected.type = tarfile.LNKTYPE
            injected.linkname = f"{archive_root}/VERSION"
        elif kind == "fifo":
            injected.type = tarfile.FIFOTYPE
        else:
            raise SystemExit(f"unsupported malicious archive kind: {kind}")
        output.addfile(injected)
PY
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

VERSION="$(tr -d '[:space:]' <"$SOURCE_VENDOR/VERSION")"
TAG="v$VERSION"
ARCHIVE_NAME="scv-core-v${VERSION}.tar.gz"
PAYLOAD_ROOT="$WORK/payload/scv-core-v${VERSION}"
RELEASE_DIR="$WORK/releases/releases/download/$TAG"
ARCHIVE="$RELEASE_DIR/$ARCHIVE_NAME"
CHECKSUM="$ARCHIVE.sha256"

mkdir -p "$PAYLOAD_ROOT" "$RELEASE_DIR"
cp -R "$SOURCE_VENDOR/." "$PAYLOAD_ROOT/"
tar -czf "$ARCHIVE" -C "$WORK/payload" "scv-core-v${VERSION}"
ACTUAL_SHA="$(portable_sha256 "$ARCHIVE")"
printf '%s  %s\n' "$ACTUAL_SHA" "$ARCHIVE_NAME" >"$CHECKSUM"
VALID_ARCHIVE="$WORK/valid-$ARCHIVE_NAME"
cp "$ARCHIVE" "$VALID_ARCHIVE"

echo "── wrapper release vendoring ──"

output="$(
  bash "$VENDOR_TOOL" \
    --tag "$TAG" \
    --repository "file://$WORK/releases" \
    --target "$WORK/vendored" \
    --profile "$PLUGIN_ROOT/adapter/host-profile.env" 2>&1
)"
rc=$?
if [[ "$rc" -eq 0 ]]; then
  ok "checksummed local release fixture vendors successfully"
else
  fail "checksummed local release fixture failed: $rc"
  printf '%s\n' "$output"
fi

locked_sha="$(
  python3 - "$WORK/vendored/core.lock.json" <<'PY' 2>/dev/null
import json
import sys
from pathlib import Path
print(json.loads(Path(sys.argv[1]).read_text()).get("artifact_sha256"))
PY
)"
if [[ "$locked_sha" == "$ACTUAL_SHA" ]]; then
  ok "core.lock.json retains the actual verified tarball SHA-256"
else
  fail "artifact_sha256 mismatch: expected $ACTUAL_SHA, got $locked_sha"
fi

if bash "$WORK/vendored/tools/verify-core.sh" \
  --root "$WORK/vendored" >/dev/null 2>&1; then
  ok "release-vendored payload verifies independently"
else
  fail "release-vendored payload failed independent verification"
fi

if python3 "$TREE_VALIDATOR" --root "$WORK/vendored" >/dev/null 2>&1; then
  ok "materialized vendor tree contains only ordinary files and directories"
else
  fail "valid materialized vendor tree was rejected"
fi

# The materialized-tree validator must also reject links and special files.
for malicious_kind in symlink hardlink fifo; do
  malicious_tree="$WORK/materialized-$malicious_kind"
  mkdir -p "$malicious_tree"
  cp -R -p "$WORK/vendored/." "$malicious_tree/"
  case "$malicious_kind" in
    symlink)
      ln -s VERSION "$malicious_tree/unsafe-symlink"
      ;;
    hardlink)
      ln "$malicious_tree/VERSION" "$malicious_tree/unsafe-hardlink"
      ;;
    fifo)
      mkfifo "$malicious_tree/unsafe-fifo"
      ;;
  esac
  output="$(
    python3 "$TREE_VALIDATOR" --root "$malicious_tree" 2>&1
  )"
  rc=$?
  if [[ "$rc" -ne 0 ]] \
    && grep -qF "link or special file" <<<"$output"; then
    ok "materialized $malicious_kind is rejected"
  else
    fail "materialized $malicious_kind was accepted or misdiagnosed"
  fi
done

# Link and special-file archives must fail before replacing an existing,
# independently verified vendor target.
for malicious_kind in symlink hardlink fifo; do
  make_malicious_archive \
    "$malicious_kind" "$VALID_ARCHIVE" "$ARCHIVE" "scv-core-v${VERSION}"
  malicious_sha="$(portable_sha256 "$ARCHIVE")"
  printf '%s  %s\n' "$malicious_sha" "$ARCHIVE_NAME" >"$CHECKSUM"
  before_rejection="$(tree_snapshot "$WORK/vendored")"
  output="$(
    bash "$VENDOR_TOOL" \
      --tag "$TAG" \
      --repository "file://$WORK/releases" \
      --target "$WORK/vendored" \
      --profile "$PLUGIN_ROOT/adapter/host-profile.env" 2>&1
  )"
  rc=$?
  after_rejection="$(tree_snapshot "$WORK/vendored")"
  if [[ "$rc" -ne 0 ]] \
    && grep -qF "link or special file" <<<"$output"; then
    ok "$malicious_kind release member is rejected"
  else
    fail "$malicious_kind release member was accepted or misdiagnosed"
  fi
  if [[ "$before_rejection" == "$after_rejection" ]]; then
    ok "$malicious_kind rejection preserves the existing vendor atomically"
  else
    fail "$malicious_kind rejection changed the existing vendor"
  fi
done

# The final replacement is a same-filesystem rename. An injected failure after
# the old target is backed up must restore its exact byte/type tree.
cp "$VALID_ARCHIVE" "$ARCHIVE"
printf '%s  %s\n' "$ACTUAL_SHA" "$ARCHIVE_NAME" >"$CHECKSUM"
before_rejection="$(tree_snapshot "$WORK/vendored")"
output="$(
  SCV_VENDOR_TEST_FAIL_INSTALL=1 \
    bash "$VENDOR_TOOL" \
      --tag "$TAG" \
      --repository "file://$WORK/releases" \
      --target "$WORK/vendored" \
      --profile "$PLUGIN_ROOT/adapter/host-profile.env" 2>&1
)"
rc=$?
after_rejection="$(tree_snapshot "$WORK/vendored")"
if [[ "$rc" -eq 97 ]] \
  && grep -qF "previous vendor restored" <<<"$output"; then
  ok "injected install failure is detected after backup"
else
  fail "injected install failure was accepted or misdiagnosed: $rc"
fi
if [[ "$before_rejection" == "$after_rejection" ]]; then
  ok "install failure restores the existing vendor exactly"
else
  fail "install failure changed the existing vendor"
fi
leftovers="$(
  find "$WORK" -maxdepth 1 \
    \( -name '.vendored.install.*' -o -name '.vendored.previous.*' \) \
    -print
)"
if [[ -z "$leftovers" ]]; then
  ok "install failure leaves no transaction directories"
else
  fail "install failure left transaction directories: $leftovers"
fi

# A release tag must describe the embedded payload version, even when the
# tarball checksum and top-level directory are otherwise valid.
MISMATCH_VERSION="$(
  python3 - "$VERSION" <<'PY'
import sys
major, minor, patch = map(int, sys.argv[1].split("."))
print(f"{major}.{minor}.{patch + 1}")
PY
)"
MISMATCH_TAG="v$MISMATCH_VERSION"
MISMATCH_ARCHIVE_NAME="scv-core-v${MISMATCH_VERSION}.tar.gz"
MISMATCH_PAYLOAD="$WORK/mismatch/scv-core-v${MISMATCH_VERSION}"
MISMATCH_RELEASE="$WORK/releases/releases/download/$MISMATCH_TAG"
mkdir -p "$MISMATCH_PAYLOAD" "$MISMATCH_RELEASE"
cp -R "$SOURCE_VENDOR/." "$MISMATCH_PAYLOAD/"
tar -czf "$MISMATCH_RELEASE/$MISMATCH_ARCHIVE_NAME" \
  -C "$WORK/mismatch" "scv-core-v${MISMATCH_VERSION}"
mismatch_sha="$(
  portable_sha256 "$MISMATCH_RELEASE/$MISMATCH_ARCHIVE_NAME"
)"
printf '%s  %s\n' "$mismatch_sha" "$MISMATCH_ARCHIVE_NAME" \
  >"$MISMATCH_RELEASE/$MISMATCH_ARCHIVE_NAME.sha256"
output="$(
  bash "$VENDOR_TOOL" \
    --tag "$MISMATCH_TAG" \
    --repository "file://$WORK/releases" \
    --target "$WORK/version-mismatch" \
    --profile "$PLUGIN_ROOT/adapter/host-profile.env" 2>&1
)"
rc=$?
if [[ "$rc" -ne 0 ]] \
  && grep -qF "does not match payload VERSION" <<<"$output"; then
  ok "release tag/payload VERSION mismatch is rejected"
else
  fail "release tag/payload VERSION mismatch was accepted or misdiagnosed"
fi
if [[ ! -e "$WORK/version-mismatch" ]]; then
  ok "version mismatch leaves no partial vendor target"
else
  fail "version mismatch left a partial vendor target"
fi

# The wrapper verifier must bind the lock to the independently checksummed
# provenance files, not merely validate the lock's field shapes.
cp -R -p "$WORK/vendored" "$WORK/provenance-mismatch"
python3 - "$WORK/provenance-mismatch/core.lock.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
lock = json.loads(path.read_text())
lock["source_commit"] = "0" * 40
path.write_text(json.dumps(lock, indent=2) + "\n")
PY
output="$(
  bash "$REPO_ROOT/tools/verify-core.sh" \
    --vendor "$WORK/provenance-mismatch" 2>&1
)"
rc=$?
if [[ "$rc" -ne 0 ]] \
  && grep -qF "source_commit does not match SOURCE_COMMIT" <<<"$output"; then
  ok "wrapper verifier rejects a poisoned provenance lock"
else
  fail "wrapper verifier accepted or misdiagnosed poisoned provenance"
fi

# A valid-looking but incorrect checksum must fail before creating a target.
cp "$VALID_ARCHIVE" "$ARCHIVE"
printf '%064d  %s\n' 0 "$ARCHIVE_NAME" >"$CHECKSUM"
output="$(
  bash "$VENDOR_TOOL" \
    --tag "$TAG" \
    --repository "file://$WORK/releases" \
    --target "$WORK/rejected" \
    --profile "$PLUGIN_ROOT/adapter/host-profile.env" 2>&1
)"
rc=$?
if [[ "$rc" -ne 0 ]]; then
  ok "mismatched release checksum is rejected"
else
  fail "mismatched release checksum was accepted"
fi
if [[ ! -e "$WORK/rejected" ]]; then
  ok "checksum rejection leaves no partial vendor target"
else
  fail "checksum rejection left a partial vendor target"
fi

# Replacement is allowed only for an existing locked core payload.
mkdir -p "$WORK/unrelated"
printf 'keep me\n' >"$WORK/unrelated/sentinel"
output="$(
  bash "$VENDOR_TOOL" \
    --source "$SOURCE_VENDOR" \
    --target "$WORK/unrelated" \
    --profile "$PLUGIN_ROOT/adapter/host-profile.env" 2>&1
)"
rc=$?
if [[ "$rc" -ne 0 ]]; then
  ok "unrelated existing target is rejected"
else
  fail "unrelated existing target was replaced"
fi
if [[ "$(cat "$WORK/unrelated/sentinel" 2>/dev/null)" == "keep me" ]]; then
  ok "target rejection preserves unrelated data"
else
  fail "target rejection changed unrelated data"
fi

echo
echo "── result: $PASS passed, $FAIL failed ──"
[[ "$FAIL" -eq 0 ]]
